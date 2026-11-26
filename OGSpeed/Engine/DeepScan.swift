import Foundation
import Network
import LocalAuthentication
import CoreTelephony
import UIKit

// MARK: - Rubriken

enum ScanCategory: String, CaseIterable, Identifiable {
    case mitlesen, dns, verbindung, heimnetz, geraete, mobil, geraet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mitlesen: return "Verschlüsselung & Mitlesen"
        case .dns: return "Namensauflösung (DNS)"
        case .verbindung: return "Deine Verbindung ins Internet"
        case .heimnetz: return "Router & Heimnetz"
        case .geraete: return "Geräte im Netz"
        case .mobil: return "Mobilfunk & Hotspot"
        case .geraet: return "Dein iPhone"
        }
    }

    var icon: String {
        switch self {
        case .mitlesen: return "eye.slash.fill"
        case .dns: return "signpost.right.and.left.fill"
        case .verbindung: return "globe.europe.africa.fill"
        case .heimnetz: return "wifi.router.fill"
        case .geraete: return "laptopcomputer.and.iphone"
        case .mobil: return "antenna.radiowaves.left.and.right"
        case .geraet: return "iphone.gen3"
        }
    }

    /// Ein Satz: worum geht es in dieser Rubrik
    var intro: String {
        switch self {
        case .mitlesen: return "Kann jemand in diesem Netz sehen oder verändern, was du sendest?"
        case .dns: return "DNS ist das Telefonbuch des Internets. Wer es fälscht, schickt dich auf falsche Seiten."
        case .verbindung: return "Mit welcher Adresse du im Internet auftauchst und was man daraus sieht."
        case .heimnetz: return "Offene Türen am Router – genau dort suchen Angreifer zuerst."
        case .geraete: return "Wer sich in deinem Netz zeigt und welche Dienste er anbietet."
        case .mobil: return "Funkstandard, Fake-Mast-Risiko und dein eigener Hotspot."
        case .geraet: return "Sicherheit beginnt beim Gerät selbst."
        }
    }

    static func of(_ key: String) -> ScanCategory {
        switch key {
        case "tls", "tlsmulti", "tlsver", "portal", "proxy", "vpn": return .mitlesen
        case "dns", "nxdomain", "dnssec", "rebind", "dnsland": return .dns
        case "exposure", "reputation", "ipv6": return .verbindung
        case "wlanenc", "ports", "routerports", "upnp", "adminhttp", "routertelnet": return .heimnetz
        case "devices", "bonjour", "bonjourrisk", "guests": return .geraete
        case "radio", "hotspot", "hotspotclient": return .mobil
        default: return .geraet
        }
    }
}

// MARK: - Messwerte (keine Bewertung, nur Information mit Erklärung)

struct ScanFact: Identifiable, Hashable {
    var id = UUID()
    var icon: String
    var label: String
    var value: String
    var explain: String
}

struct LanService: Identifiable, Hashable {
    var id: String { name + type }
    var name: String
    var type: String
}

struct PortHit: Identifiable, Hashable {
    var id: Int { port }
    var port: Int
    var name: String
    var explain: String
    var severity: Int
}

struct DeepReport {
    var findings: [SecurityFinding] = []
    var facts: [ScanFact] = []
    var services: [LanService] = []
    var localNetworkDenied = false
    var routerPorts: [PortHit] = []
    var routerHost: String?
    var date = Date()

    /// 100 = nichts gefunden. Gefahr kostet viel, Hinweise wenig.
    var score: Int {
        let malus = findings.reduce(0) { sum, f in
            switch f.severity {
            case 3: return sum + 25
            case 2: return sum + 10
            case 1: return sum + 2
            default: return sum
            }
        }
        return max(0, min(100, 100 - malus))
    }

    var scoreLevel: Level {
        switch score {
        case 90...: return .great
        case 75..<90: return .good
        case 50..<75: return .ok
        default: return .bad
        }
    }

    var scoreText: String {
        switch score {
        case 90...: return "Sehr sicher"
        case 75..<90: return "Sicher mit kleinen Schwächen"
        case 50..<75: return "Lücken vorhanden"
        default: return "Unsicher – jetzt handeln"
        }
    }

    func findings(in c: ScanCategory) -> [SecurityFinding] {
        findings.filter { ScanCategory.of($0.key) == c }.sorted { $0.severity > $1.severity }
    }
}

// MARK: - Das große Labor

enum DeepScan {

    static func run(connection: ConnectionKind, identity: NetIdentity?) async -> DeepReport {
        var r = DeepReport()
        let isHomeNet = connection == .wifi || connection == .wired
        let routerHost = isHomeNet ? gatewayHost(identity) : nil
        r.routerHost = routerHost
        let systemVersion = await MainActor.run { UIDevice.current.systemVersion }

        async let base = SecurityScan.run(connection: connection, identity: identity)
        async let tlsMulti = tlsAcrossHosts()
        async let trace = NetDetector.trace("https://1.1.1.1/cdn-cgi/trace")
        async let rep = reputation()
        async let skew = clockSkew()
        async let nx = blocking { nxdomainHijack() }
        async let sec = blocking { dnssecValidates() }
        async let rebind = blocking { rebindProtection() }
        async let dnsWho = ExitProbe.dnsExit()
        async let ports = routerPorts(routerHost)
        async let upnp = upnpExposed(routerHost)
        async let bonjour = bonjourIfHome(isHomeNet)
        async let ios = iosVersionCheck(current: systemVersion)

        var out = await base

        // Verschlüsselung
        out.append(tlsMultiFinding(await tlsMulti))
        let t = await trace
        if let tls = t?["tls"] { out.append(tlsVersionFinding(tls)) }

        // DNS
        if let f = nxdomainFinding(await nx) { out.append(f) }
        if let f = dnssecFinding(await sec) { out.append(f) }
        if isHomeNet, let f = rebindFinding(await rebind) { out.append(f) }
        let who = await dnsWho
        if let f = dnsCountryFinding(who) { out.append(f) }

        // Verbindung
        let reputationData = await rep
        if let f = reputationFinding(reputationData, connection: connection) { out.append(f) }
        if let f = ipv6Finding(identity?.ipv6) { out.append(f) }

        // Router
        let hits = await ports
        r.routerPorts = hits
        if routerHost != nil { out += routerFindings(hits) }
        if let u = await upnp { out.append(u) }

        // Geräte im Netz
        let b = await bonjour
        r.services = b.services
        r.localNetworkDenied = b.denied
        if isHomeNet { out += bonjourFindings(b.services, denied: b.denied, identity: identity) }

        // Mobilfunk & Hotspot
        if connection == .cellular, let f = radioFinding() { out.append(f) }
        out += hotspotFindings(connection: connection, localIP: identity?.localIP)

        // Gerät
        out.append(passcodeFinding())
        if let f = await ios { out.append(f) }
        let sk = await skew
        if let f = clockFinding(sk) { out.append(f) }

        for i in out.indices { out[i].category = ScanCategory.of(out[i].key).rawValue }
        r.findings = out
        r.facts = facts(connection: connection, identity: identity, trace: t, dns: who,
                        rep: reputationData, skew: sk, routerHost: routerHost, systemVersion: systemVersion)
        r.date = Date()
        return r
    }

    private static func bonjourIfHome(_ home: Bool) async -> (services: [LanService], denied: Bool) {
        guard home else { return ([], false) }
        return await BonjourScan.scan(seconds: 4)
    }

    /// Blockierende Systemaufrufe (getaddrinfo) nicht auf dem Haupt-Thread
    private static func blocking<T: Sendable>(_ f: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { f() }.value
    }

    static func gatewayHost(_ id: NetIdentity?) -> String? {
        if let a = id?.router?.address { return a }
        guard let ip = id?.localIP ?? NetworkMonitor.localWiFiIPv4() else { return nil }
        let p = ip.split(separator: ".")
        guard p.count == 4 else { return nil }
        return p.prefix(3).joined(separator: ".") + ".1"
    }

    // MARK: Verschlüsselung über mehrere Seiten

    private static let tlsHosts = [
        "https://www.apple.com/library/test/success.html",
        "https://www.google.com/generate_204",
        "https://www.cloudflare.com/cdn-cgi/trace",
        "https://www.wikipedia.org/"
    ]

    /// (geprüft, davon fremd, Namen der fremden Aussteller)
    private static func tlsAcrossHosts() async -> (checked: Int, foreign: Int, roots: [String]) {
        await withTaskGroup(of: (Bool, String?).self) { g in
            for h in tlsHosts {
                g.addTask {
                    let r = await TLSInspector.check(host: h)
                    return (r.ok, r.root)
                }
            }
            var checked = 0, foreign = 0
            var roots: [String] = []
            for await (ok, root) in g {
                guard let root else { continue }
                checked += 1
                if !ok { foreign += 1; roots.append(root) }
            }
            return (checked, foreign, roots)
        }
    }

    private static func tlsMultiFinding(_ r: (checked: Int, foreign: Int, roots: [String])) -> SecurityFinding {
        if r.checked == 0 {
            return SecurityFinding(key: "tlsmulti", icon: "questionmark.circle", title: "Zertifikate mehrerer Seiten",
                                   value: "Nicht prüfbar",
                                   detail: "Keine der Testseiten war erreichbar.", severity: 1)
        }
        if r.foreign == 0 {
            return SecurityFinding(key: "tlsmulti", icon: "checkmark.seal.fill", title: "Zertifikate gegengeprüft",
                                   value: "\(r.checked) von \(r.checked) echt",
                                   detail: "OGSpeed hat Apple, Google, Cloudflare und Wikipedia aufgerufen und bei jeder Seite nachgesehen, wer ihr Sicherheitszertifikat ausgestellt hat. Alle stammen von offiziellen Stellen. Ein Gerät, das sich heimlich dazwischenschaltet, müsste eigene Zertifikate unterschieben – das wäre hier aufgefallen.",
                                   severity: 0)
        }
        return SecurityFinding(key: "tlsmulti", icon: "eye.trianglebadge.exclamationmark.fill",
                               title: "Fremde Zertifikate", value: "\(r.foreign) von \(r.checked)",
                               detail: "Bei \(r.foreign) von \(r.checked) großen Webseiten kam ein Zertifikat von „\(r.roots.joined(separator: ", "))“ statt vom echten Aussteller. Das heißt: Irgendetwas zwischen dir und dem Internet entschlüsselt deine Verbindungen, liest sie und verschlüsselt sie neu. Das macht ein Firmen-Filter, ein Virenscanner-Profil – oder ein Angreifer.",
                               advice: "Sofort aus diesem Netz raus oder VPN einschalten. Danach unter Einstellungen › Allgemein › VPN & Geräteverwaltung nach unbekannten Profilen suchen.",
                               severity: 3)
    }

    private static func tlsVersionFinding(_ v: String) -> SecurityFinding {
        let modern = v.contains("1.3")
        let ok = modern || v.contains("1.2")
        return SecurityFinding(key: "tlsver", icon: modern ? "lock.fill" : "lock.trianglebadge.exclamationmark",
                               title: "Verschlüsselungs-Standard", value: v.replacingOccurrences(of: "TLSv", with: "TLS "),
                               detail: modern
                                ? "Deine Verbindungen nutzen TLS 1.3, den neuesten Standard. Er verschlüsselt schon den Verbindungsaufbau und lässt keine alten, knackbaren Verfahren mehr zu."
                                : ok ? "TLS 1.2 ist noch sicher, aber nicht mehr der neueste Stand. Meist liegt das an einem Zwischengerät im Netz, das TLS 1.3 nicht durchlässt."
                                     : "Ein veraltetes Verfahren wird erzwungen. Das passiert fast nur, wenn sich etwas in die Verbindung einmischt.",
                               advice: ok ? nil : "Netz wechseln oder VPN nutzen.",
                               severity: modern ? 0 : ok ? 1 : 3)
    }

    // MARK: DNS

    /// Liefert eine erfundene Domain trotzdem eine Adresse, biegt der Anbieter Fehler um.
    private static func nxdomainHijack() -> Bool? {
        let random = String((0..<14).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        let got = SecurityScan.systemResolve("ogs-\(random).example.com")
        // Kontrolle: funktioniert die Namensauflösung überhaupt?
        guard !SecurityScan.systemResolve("one.one.one.one").isEmpty else { return nil }
        return !got.isEmpty
    }

    private static func nxdomainFinding(_ hijack: Bool?) -> SecurityFinding? {
        guard let hijack else { return nil }
        if hijack {
            return SecurityFinding(key: "nxdomain", icon: "arrow.uturn.right.circle.fill",
                                   title: "Fehlerseiten werden umgebogen", value: "Manipuliert",
                                   detail: "OGSpeed hat nach einer Adresse gefragt, die es garantiert nicht gibt. Statt „gibt es nicht“ kam trotzdem eine Antwort. Der DNS-Server dieses Netzes leitet Tippfehler also auf eigene Seiten um – oft Werbung, manchmal Schlimmeres. Wer das kann, kann auch echte Adressen umbiegen.",
                                   advice: "Unter Einstellungen › WLAN › (i) › DNS konfigurieren auf „Manuell“ stellen und 1.1.1.1 oder 9.9.9.9 eintragen – oder VPN nutzen.",
                                   severity: 2)
        }
        return SecurityFinding(key: "nxdomain", icon: "checkmark.shield.fill", title: "Ehrliche Fehlermeldungen",
                               value: "Unverfälscht",
                               detail: "Eine erfundene Adresse wurde korrekt mit „gibt es nicht“ beantwortet. Der DNS-Server spielt dir keine eigenen Seiten unter.",
                               severity: 0)
    }

    /// dnssec-failed.org ist absichtlich falsch signiert. Prüft der Server Signaturen,
    /// verweigert er die Antwort.
    private static func dnssecValidates() -> Bool? {
        guard !SecurityScan.systemResolve("one.one.one.one").isEmpty else { return nil }
        return SecurityScan.systemResolve("dnssec-failed.org").isEmpty
    }

    private static func dnssecFinding(_ validates: Bool?) -> SecurityFinding? {
        guard let validates else { return nil }
        if validates {
            return SecurityFinding(key: "dnssec", icon: "signature", title: "DNS-Signaturen werden geprüft",
                                   value: "DNSSEC an",
                                   detail: "Viele Adressen im Internet sind digital unterschrieben (DNSSEC). Dein DNS-Server prüft diese Unterschrift: Eine absichtlich gefälschte Testadresse wurde abgelehnt. Gefälschte Antworten von unterwegs haben damit keine Chance.",
                                   severity: 0)
        }
        return SecurityFinding(key: "dnssec", icon: "signature", title: "DNS-Signaturen ungeprüft",
                               value: "DNSSEC aus",
                               detail: "Eine absichtlich falsch unterschriebene Testadresse wurde trotzdem beantwortet. Dein DNS-Server prüft also nicht, ob Antworten echt sind. Das ist bei vielen Anbietern so und kein akuter Angriff – aber eine Schutzschicht fehlt.",
                               advice: "DNS-Server mit Prüfung nutzen: 1.1.1.1 (Cloudflare) oder 9.9.9.9 (Quad9). In der FRITZ!Box unter Internet › Zugangsdaten › DNS-Server eintragen, dann gilt es für alle Geräte.",
                               severity: 1)
    }

    /// DNS-Rebinding: Eine öffentliche Adresse, die auf ein Gerät in deinem Heimnetz zeigt.
    /// Gute Router blockieren solche Antworten – sonst können Webseiten deinen Router ansprechen.
    private static func rebindProtection() -> Bool? {
        // Kontrolle: ist der Dienst überhaupt erreichbar?
        guard SecurityScan.systemResolve("1.1.1.1.nip.io").contains("1.1.1.1") else { return nil }
        let got = SecurityScan.systemResolve("192.168.178.1.nip.io")
        return got.isEmpty
    }

    private static func rebindFinding(_ protected: Bool?) -> SecurityFinding? {
        guard let protected else { return nil }
        if protected {
            return SecurityFinding(key: "rebind", icon: "checkmark.shield.fill", title: "Rebind-Schutz aktiv",
                                   value: "Blockiert",
                                   detail: "Ein bekannter Trick: Eine fremde Webseite gibt sich als Adresse in deinem Heimnetz aus und kann dann im Hintergrund deinen Router oder deine Kameras ansprechen. Dein Router blockiert solche Antworten. Dieser Angriff funktioniert bei dir nicht.",
                                   severity: 0)
        }
        return SecurityFinding(key: "rebind", icon: "exclamationmark.triangle.fill", title: "Kein Rebind-Schutz",
                               value: "Durchgelassen",
                               detail: "Eine Internet-Adresse, die auf ein Gerät in deinem Heimnetz zeigt, wurde durchgelassen. Eine präparierte Webseite könnte so über deinen Browser deinen Router, Drucker oder Kameras ansprechen (DNS-Rebinding).",
                               advice: "Im Router den DNS-Rebind-Schutz einschalten. FRITZ!Box: ist ab Werk an – unter Heimnetz › Netzwerk › Netzwerkeinstellungen prüfen, dass dort keine Ausnahmen stehen.",
                               severity: 2)
    }

    private static func dnsCountryFinding(_ who: DNSExit?) -> SecurityFinding? {
        guard let land = who?.countryName else { return nil }
        let home = land.lowercased().contains("germany") || land.lowercased().contains("deutschland")
        let op = who?.operatorName ?? "unbekannt"
        if home || VPNDetect.isActive {
            return SecurityFinding(key: "dnsland", icon: "mappin.and.ellipse", title: "Wer deine Adressen nachschlägt",
                                   value: Sanitize.deviceName(op, max: 26) ?? "bekannt",
                                   detail: "Jede Webseite, die du aufrufst, wird zuerst bei einem DNS-Server nachgeschlagen. Bei dir ist das „\(op)“ (\(land)). Dieser Betreiber sieht, welche Seiten du aufrufst – nicht was du dort tust.",
                                   severity: 0)
        }
        return SecurityFinding(key: "dnsland", icon: "airplane.departure", title: "DNS läuft übers Ausland",
                               value: land,
                               detail: "Deine Namensanfragen beantwortet „\(op)“ in \(land), obwohl kein VPN läuft. Entweder hat dieses Netz einen ungewöhnlichen DNS-Server eingestellt, oder jemand hat ihn umgestellt – typisch für manipulierte Router.",
                               advice: "Wenn du das nicht selbst so eingestellt hast: Router-DNS prüfen und Router-Kennwort ändern.",
                               severity: 2)
    }

    // MARK: Verbindung

    struct Reputation: Sendable {
        var abuser = false
        var abuserScore: String?
        var datacenter = false
        var tor = false
        var proxy = false
        var vpn = false
        var mobile = false
        var type: String?
        var company: String?
    }

    private static let plainSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.waitsForConnectivity = false
        cfg.urlCache = nil
        cfg.httpCookieAcceptPolicy = .never
        return URLSession(configuration: cfg)
    }()

    private static func reputation() async -> Reputation? {
        guard let url = URL(string: "https://api.ipapi.is/"),
              let res = try? await plainSession.data(from: url), res.0.count < 200_000,
              let j = (try? JSONSerialization.jsonObject(with: res.0)) as? [String: Any] else { return nil }
        var r = Reputation()
        r.abuser = j["is_abuser"] as? Bool ?? false
        r.datacenter = j["is_datacenter"] as? Bool ?? false
        r.tor = j["is_tor"] as? Bool ?? false
        r.proxy = j["is_proxy"] as? Bool ?? false
        r.vpn = j["is_vpn"] as? Bool ?? false
        r.mobile = j["is_mobile"] as? Bool ?? false
        if let c = j["company"] as? [String: Any] {
            r.company = Sanitize.deviceName(c["name"] as? String, max: 40)
            r.type = c["type"] as? String
            r.abuserScore = c["abuser_score"] as? String
        }
        if r.abuserScore == nil, let a = j["asn"] as? [String: Any] { r.abuserScore = a["abuser_score"] as? String }
        return r
    }

    private static func reputationFinding(_ r: Reputation?, connection: ConnectionKind) -> SecurityFinding? {
        guard let r else { return nil }
        if r.abuser {
            return SecurityFinding(key: "reputation", icon: "hand.raised.slash.fill", title: "IP auf Sperrliste",
                                   value: "Gemeldet",
                                   detail: "Deine aktuelle Internet-Adresse steht auf einer Liste für Spam oder Angriffe. Im Mobilfunk teilen sich oft hunderte Kunden eine Adresse – dann war es meist jemand anderes. Folge: mehr Captchas, manche Seiten blocken dich. Im Heimnetz kann es heißen, dass ein Gerät bei dir verseucht ist.",
                                   advice: connection == .cellular ? "Flugmodus kurz an und aus – meist gibt's dann eine neue Adresse." : "FRITZ!Box neu verbinden (neue IP). Tritt es wieder auf: Geräte im Heimnetz auf Schadsoftware prüfen.",
                                   severity: 2)
        }
        if (r.tor || r.proxy) && !VPNDetect.isActive {
            return SecurityFinding(key: "reputation", icon: "theatermasks.fill", title: "Adresse gilt als Proxy",
                                   value: r.tor ? "Tor" : "Proxy",
                                   detail: "Deine Internet-Adresse ist als Anonymisierungsdienst bekannt, obwohl auf dem iPhone kein VPN läuft. Das Netz, in dem du bist, leitet deinen Verkehr also über einen fremden Dienst.",
                                   advice: "Herausfinden, wer dieses Netz betreibt. Für Sensibles mobile Daten nutzen.",
                                   severity: 2)
        }
        let score = r.abuserScore.flatMap { $0.split(separator: " ").first }.map(String.init) ?? "–"
        return SecurityFinding(key: "reputation", icon: "checkmark.seal.fill", title: "Ruf deiner IP-Adresse",
                               value: "Sauber",
                               detail: "Deine Internet-Adresse steht auf keiner Sperr- oder Missbrauchsliste. Missbrauchs-Wert des Netzes: \(score) (je kleiner, desto besser; unter 0,01 ist sehr gut).",
                               severity: 0)
    }

    private static func ipv6Finding(_ ip: String?) -> SecurityFinding? {
        guard let ip else { return nil }
        var b = in6_addr()
        guard inet_pton(AF_INET6, ip, &b) == 1 else { return nil }
        let bytes = withUnsafeBytes(of: b) { Array($0) }
        let eui64 = bytes.count == 16 && bytes[11] == 0xFF && bytes[12] == 0xFE
        if eui64 {
            return SecurityFinding(key: "ipv6", icon: "barcode.viewfinder", title: "IPv6 verrät Gerät",
                                   value: "Feste Kennung",
                                   detail: "Deine IPv6-Adresse enthält die Hardware-Kennung deines Geräts. Webseiten können dich damit über Netzwechsel hinweg wiedererkennen.",
                                   advice: "Im Router „IPv6-Datenschutzerweiterungen“ einschalten. Liegt es am iPhone: Einstellungen › WLAN › (i) › Private WLAN-Adresse auf „Rotierend“.",
                                   severity: 2)
        }
        return SecurityFinding(key: "ipv6", icon: "theatermasks", title: "IPv6-Adresse anonymisiert",
                               value: "Wechselnd",
                               detail: "Deine IPv6-Adresse enthält keine feste Gerätekennung, sondern einen Zufallsteil, der regelmäßig wechselt. Webseiten können dich darüber nicht dauerhaft wiedererkennen.",
                               severity: 0)
    }

    // MARK: Router-Dienste (nur am eigenen Router)

    private static let ports: [(Int, String, String, Int)] = [
        (21, "FTP", "Alter Dateidienst ohne Verschlüsselung. Kennwörter gehen im Klartext durchs Netz.", 2),
        (22, "SSH", "Fernzugriff auf die Kommandozeile. Verschlüsselt, aber ein lohnendes Ziel für Passwort-Raten.", 1),
        (23, "Telnet", "Uralter Fernzugriff ohne jede Verschlüsselung. Wer im Netz mithört, bekommt das Router-Kennwort.", 3),
        (53, "DNS", "Der Router beantwortet Adressanfragen. Normal und gewollt.", 0),
        (80, "Weboberfläche (HTTP)", "Router-Menü ohne Verschlüsselung. Meist leitet es auf HTTPS weiter.", 0),
        (139, "Windows-Freigabe (alt)", "Alte Datei-Freigabe (NetBIOS). Nur nötig für sehr alte Geräte.", 1),
        (443, "Weboberfläche (HTTPS)", "Router-Menü mit Verschlüsselung. So soll es sein.", 0),
        (445, "Datei-Freigabe (SMB)", "Netzwerkspeicher am Router (z. B. FRITZ!NAS). Praktisch, aber nur mit starkem Kennwort.", 1),
        (554, "Video-Stream (RTSP)", "Kamera- oder Medienstream. Oft ohne Kennwort abrufbar.", 1),
        (1900, "UPnP", "Geräte können sich hier selbst Türen nach außen öffnen.", 1),
        (5000, "UPnP / Web", "Häufig UPnP-Steuerung oder ein Zusatzmenü.", 1),
        (7547, "Fernwartung (TR-069)", "Kanal, über den der Anbieter den Router verwaltet. Sollte im Heimnetz nicht offen sein.", 2),
        (8080, "Zweite Weboberfläche", "Zusätzliches Menü, oft für Fernzugriff oder Medien.", 1),
        (8443, "Zweite Weboberfläche (HTTPS)", "Verschlüsseltes Zusatzmenü, oft für Fernzugriff.", 0),
        (49000, "TR-064", "Schnittstelle, über die Apps wie OGSpeed die FRITZ!Box abfragen. Nur mit Kennwort nutzbar.", 0),
        (49443, "TR-064 (HTTPS)", "Verschlüsselte Variante der Router-Schnittstelle.", 0)
    ]

    private static func routerPorts(_ host: String?) async -> [PortHit] {
        guard let host else { return [] }
        return await withTaskGroup(of: PortHit?.self) { g in
            for (port, name, explain, sev) in ports {
                g.addTask {
                    let ms = await Probes.tcpConnect(host: host, port: UInt16(port), timeout: 1.5, resolve: false)
                    return ms == nil ? nil : PortHit(port: port, name: name, explain: explain, severity: sev)
                }
            }
            var out: [PortHit] = []
            for await h in g { if let h { out.append(h) } }
            return out.sorted { $0.port < $1.port }
        }
    }

    private static func routerFindings(_ hits: [PortHit]) -> [SecurityFinding] {
        var out: [SecurityFinding] = []
        let open = Set(hits.map(\.port))
        if open.contains(23) {
            out.append(SecurityFinding(key: "routertelnet", icon: "exclamationmark.octagon.fill",
                                       title: "Telnet am Router offen", value: "Port 23",
                                       detail: "Dein Router lässt Fernzugriff per Telnet zu. Das ist völlig unverschlüsselt – das Kennwort geht im Klartext durchs WLAN. Moderne Router haben das ab Werk aus.",
                                       advice: "Im Router-Menü Telnet abschalten. Bei der FRITZ!Box: Telefon › Telefoniegeräte – Telnet wurde früher per #96*7* eingeschaltet, mit #96*8* wieder aus.",
                                       severity: 3))
        }
        if open.contains(80) && !open.contains(443) {
            out.append(SecurityFinding(key: "adminhttp", icon: "lock.open.fill", title: "Router-Menü unverschlüsselt",
                                       value: "Nur HTTP",
                                       detail: "Die Anmeldeseite deines Routers läuft ohne Verschlüsselung. Wer im WLAN mithört, kann beim Einloggen das Router-Kennwort mitlesen.",
                                       advice: "Wenn der Router es kann: HTTPS für die Weboberfläche einschalten. Sonst nur per Kabel einloggen.",
                                       severity: 2))
        }
        let risky = hits.filter { $0.severity >= 2 && $0.port != 23 }
        let summary = hits.map { "\($0.port) \($0.name)" }.joined(separator: ", ")
        out.append(SecurityFinding(key: "routerports", icon: risky.isEmpty ? "checkmark.shield.fill" : "door.left.hand.open",
                                   title: "Offene Dienste am Router", value: "\(hits.count)",
                                   detail: hits.isEmpty
                                    ? "OGSpeed hat 16 typische Dienste an deinem Router abgeklopft. Keiner antwortet – der Router zeigt im WLAN keine Angriffsfläche."
                                    : "OGSpeed hat 16 typische Dienste an deinem Router abgeklopft. Diese antworten: \(summary). Die Liste unten erklärt jeden einzelnen." + (risky.isEmpty ? " Nichts davon ist bedenklich." : " Darunter sind Dienste, die im Heimnetz nicht offen sein sollten."),
                                   advice: risky.isEmpty ? nil : "Im Router-Menü die markierten Dienste abschalten.",
                                   severity: risky.isEmpty ? 0 : 2))
        return out
    }

    /// Kann sich ein Gerät selbst Türen nach außen öffnen (UPnP-IGD)?
    private static func upnpExposed(_ host: String?) async -> SecurityFinding? {
        guard let host else { return nil }
        let urls = ["http://\(host):49000/igddesc.xml", "http://\(host):5000/rootDesc.xml", "http://\(host):1900/rootDesc.xml"]
        var found = false
        for u in urls {
            if let r = await Probes.fetchText(u, maxBytes: 20_000),
               r.text.contains("InternetGatewayDevice") || r.text.contains("WANIPConnection") {
                found = true
                break
            }
        }
        if found {
            return SecurityFinding(key: "upnp", icon: "door.right.hand.open", title: "UPnP am Router aktiv",
                                   value: "An",
                                   detail: "Über UPnP dürfen Geräte im Heimnetz selbst beim Router Türen nach außen öffnen – ohne dich zu fragen. Spielkonsolen brauchen das für guten NAT-Typ. Eine verseuchte Kamera oder ein billiges Smart-Gerät kann es aber genauso nutzen.",
                                   advice: "FRITZ!Box: Internet › Freigaben › Gerät bearbeiten › „Selbstständige Portfreigaben erlauben“ nur für die Konsole an, für alle anderen Geräte aus.",
                                   severity: 1)
        }
        return SecurityFinding(key: "upnp", icon: "checkmark.shield.fill", title: "UPnP-Steuerung",
                               value: "Nicht erreichbar",
                               detail: "Der Router bietet im Netz keine UPnP-Steuerung an. Geräte können sich nicht heimlich selbst Türen nach außen öffnen.",
                               severity: 0)
    }

    // MARK: Geräte im Netz (Bonjour)

    private static func bonjourFindings(_ services: [LanService], denied: Bool, identity: NetIdentity?) -> [SecurityFinding] {
        if denied {
            return [SecurityFinding(key: "bonjour", icon: "hand.raised.fill", title: "Geräte-Suche gesperrt",
                                    value: "Keine Erlaubnis",
                                    detail: "OGSpeed darf das lokale Netzwerk nicht durchsuchen. Läuft OGSpeed in LiveContainer, gilt dessen Erlaubnis – dann klappt die Suche dort nicht.",
                                    advice: "Einstellungen › Datenschutz › Lokales Netzwerk › OGSpeed einschalten.",
                                    severity: 1)]
        }
        var out: [SecurityFinding] = []
        let devices = Set(services.map(\.name))
        let risky = services.compactMap { s -> (LanService, BonjourScan.Kind)? in
            guard let k = BonjourScan.kind(for: s.type), k.severity >= 2 else { return nil }
            return (s, k)
        }
        out.append(SecurityFinding(key: "bonjour", icon: "dot.radiowaves.left.and.right", title: "Sichtbare Geräte",
                                   value: "\(devices.count)",
                                   detail: devices.isEmpty
                                    ? "Kein Gerät stellt sich in diesem Netz vor. Entweder ist das Netz leer, oder es trennt die Geräte voneinander (gut in Hotels und Cafés)."
                                    : "\(devices.count) Geräte stellen sich in diesem Netz mit Namen und Diensten vor – Drucker, Fernseher, Lautsprecher, Computer. Die Liste unten zeigt alle.",
                                   severity: 0))
        if !risky.isEmpty {
            let list = risky.prefix(5).map { "„\($0.0.name)“ (\($0.1.label))" }.joined(separator: ", ")
            out.append(SecurityFinding(key: "bonjourrisk", icon: "exclamationmark.triangle.fill",
                                       title: "Fernzugriff angeboten", value: "\(risky.count)",
                                       detail: "Diese Geräte bieten Fernsteuerung oder Dateizugriff offen im Netz an: \(list). Jeder im selben WLAN kann versuchen, sich dort anzumelden.",
                                       advice: "Auf den Geräten nicht genutzte Freigaben ausschalten (Mac: Systemeinstellungen › Allgemein › Teilen) und starke Kennwörter setzen.",
                                       severity: 2))
        }
        // Öffentliches WLAN: sieht man fremde Geräte, sehen die auch dich
        let ownRouter = identity?.router != nil && identity?.router?.vendor != .unknown
        if !ownRouter && devices.count >= 3 {
            out.append(SecurityFinding(key: "guests", icon: "person.3.fill", title: "Gäste nicht getrennt",
                                       value: "\(devices.count) sichtbar",
                                       detail: "Du siehst in diesem Netz fremde Geräte. Umgekehrt sehen die auch dein iPhone und können es direkt ansprechen. Gute öffentliche WLANs trennen die Gäste voneinander.",
                                       advice: "In fremden WLANs VPN einschalten und AirDrop auf „Nur Kontakte“ stellen.",
                                       severity: 2))
        }
        return out
    }

    // MARK: Mobilfunk

    static func radioRaw() -> String? {
        guard let techs = CTTelephonyNetworkInfo().serviceCurrentRadioAccessTechnology?.values else { return nil }
        let order = [CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA, CTRadioAccessTechnologyLTE,
                     CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA,
                     CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS]
        return order.first { techs.contains($0) } ?? techs.first
    }

    static func radioLabel() -> String? {
        switch radioRaw() {
        case CTRadioAccessTechnologyNR?: return "5G SA"
        case CTRadioAccessTechnologyNRNSA?: return "5G"
        case CTRadioAccessTechnologyLTE?: return "4G"
        case CTRadioAccessTechnologyEdge?, CTRadioAccessTechnologyGPRS?: return "2G"
        case nil: return nil
        default: return "3G"
        }
    }

    private static func radioFinding() -> SecurityFinding? {
        guard let t = radioRaw() else { return nil }
        switch t {
        case CTRadioAccessTechnologyNR:
            return SecurityFinding(key: "radio", icon: "checkmark.shield.fill", title: "5G Standalone", value: "Bestes Netz",
                                   detail: "Du bist im echten 5G-Netz. Hier wird sogar deine Teilnehmerkennung verschlüsselt übertragen – gefälschte Mobilfunkmasten („IMSI-Catcher“) können dich nicht mehr einfach identifizieren.",
                                   severity: 0)
        case CTRadioAccessTechnologyNRNSA, CTRadioAccessTechnologyLTE:
            return SecurityFinding(key: "radio", icon: "checkmark.shield.fill",
                                   title: t == CTRadioAccessTechnologyLTE ? "4G (LTE)" : "5G (mit 4G-Kern)", value: "Sicher",
                                   detail: "Starke Verschlüsselung zwischen Handy und Mast, und das Netz muss sich dir gegenüber ausweisen. Gefälschte Masten bekommen hier nur deine Kennung, nicht deine Daten.",
                                   severity: 0)
        case CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS:
            return SecurityFinding(key: "radio", icon: "exclamationmark.octagon.fill", title: "2G-Netz (EDGE/GPRS)",
                                   value: "Unsicher",
                                   detail: "Du hängst im uralten 2G-Netz. Dessen Verschlüsselung gilt seit Jahren als geknackt, und das Netz muss sich nicht ausweisen. Gefälschte Mobilfunkmasten zwingen Handys gezielt auf 2G, um mitzuhören. In Deutschland ist 2G kaum noch nötig.",
                                   advice: "Wenn du hier eigentlich 4G/5G haben müsstest: misstrauisch sein. Den Blockierungsmodus (Einstellungen › Datenschutz & Sicherheit) einschalten – er verbietet 2G komplett.",
                                   severity: 2)
        default:
            return SecurityFinding(key: "radio", icon: "antenna.radiowaves.left.and.right", title: "3G-Netz", value: "Veraltet",
                                   detail: "3G ist in Deutschland abgeschaltet. Wenn dein iPhone das anzeigt, bist du im Ausland oder es stimmt etwas mit dem Netz nicht.",
                                   severity: 1)
        }
    }

    // MARK: Hotspot

    static func interfaces() -> [(name: String, ip: String)] {
        var out: [(String, String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    out.append((String(cString: ifa.ifa_name), String(cString: host)))
                }
            }
            ptr = ifa.ifa_next
        }
        return out
    }

    private static func hotspotFindings(connection: ConnectionKind, localIP: String?) -> [SecurityFinding] {
        var out: [SecurityFinding] = []
        if interfaces().contains(where: { $0.name.hasPrefix("bridge") }) {
            out.append(SecurityFinding(key: "hotspot", icon: "personalhotspot", title: "Du teilst gerade Hotspot",
                                       value: "Aktiv",
                                       detail: "Mindestens ein Gerät surft gerade über dein iPhone. Alles, was es tut, läuft über deinen Anschluss und deine Adresse. Der Hotspot ist mit WPA2/WPA3 verschlüsselt – so stark wie sein Kennwort.",
                                       advice: "Einstellungen › Persönlicher Hotspot: Kennwort mit mindestens 12 Zeichen, „Kompatibilität maximieren“ aus (dann WPA3), Hotspot ausschalten, wenn du ihn nicht brauchst.",
                                       severity: 1))
        }
        if connection == .wifi, let ip = localIP {
            if ip.hasPrefix("172.20.10.") {
                out.append(SecurityFinding(key: "hotspotclient", icon: "iphone.radiowaves.left.and.right",
                                           title: "Über iPhone-Hotspot verbunden", value: "Mobilfunk",
                                           detail: "Du hängst am Hotspot eines anderen iPhones. Dessen Besitzer ist dein „Router“: Er sieht, mit welchen Servern du sprichst. Die Inhalte bleiben durch HTTPS geschützt.",
                                           severity: 0))
            } else if ip.hasPrefix("192.168.43.") || ip.hasPrefix("192.168.49.") {
                out.append(SecurityFinding(key: "hotspotclient", icon: "iphone.radiowaves.left.and.right",
                                           title: "Über Handy-Hotspot verbunden", value: "Android",
                                           detail: "Du hängst am Hotspot eines Android-Handys. Dessen Besitzer sieht, mit welchen Servern du sprichst.",
                                           severity: 0))
            }
        }
        return out
    }

    // MARK: Gerät

    private static func passcodeFinding() -> SecurityFinding {
        let ctx = LAContext()
        var err: NSError?
        let has = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
        let noCode = !has && (err.map { LAError.Code(rawValue: $0.code) == .passcodeNotSet } ?? false)
        if noCode {
            return SecurityFinding(key: "passcode", icon: "lock.open.trianglebadge.exclamationmark.fill",
                                   title: "Kein Gerätecode", value: "Ungeschützt",
                                   detail: "Dein iPhone hat keinen Code. Dann sind auch deine Daten auf dem Gerät nicht verschlüsselt – wer es in der Hand hat, kommt an alles.",
                                   advice: "Einstellungen › Face ID & Code › Code aktivieren (6 Ziffern oder mehr).",
                                   severity: 3)
        }
        let bio: String
        switch ctx.biometryType {
        case .faceID: bio = "Face ID"
        case .touchID: bio = "Touch ID"
        default: bio = "Code"
        }
        return SecurityFinding(key: "passcode", icon: "lock.iphone", title: "Gerät gesperrt", value: bio,
                               detail: "Dein iPhone ist mit Code\(bio == "Code" ? "" : " und \(bio)") geschützt. Damit sind auch alle Daten darauf verschlüsselt.",
                               severity: 0)
    }

    /// Fragt Apples öffentliche Liste der aktuellen iOS-Versionen ab.
    private static func iosVersionCheck(current: String) async -> SecurityFinding? {
        guard let url = URL(string: "https://gdmf.apple.com/v2/pmv"),
              let res = try? await plainSession.data(from: url), res.0.count < 2_000_000,
              let j = (try? JSONSerialization.jsonObject(with: res.0)) as? [String: Any],
              let sets = j["PublicAssetSets"] as? [String: Any],
              let ios = sets["iOS"] as? [[String: Any]] else { return nil }
        let major = current.split(separator: ".").first.map(String.init) ?? current
        let versions = ios.compactMap { $0["ProductVersion"] as? String }
        guard let newestSameMajor = versions.filter({ $0.split(separator: ".").first.map(String.init) == major })
                .max(by: { versionLess($0, $1) }) else { return nil }
        let newestOverall = versions.max(by: { versionLess($0, $1) }) ?? newestSameMajor

        if versionLess(current, newestSameMajor) {
            return SecurityFinding(key: "ios", icon: "arrow.down.circle.fill", title: "Sicherheits-Update offen",
                                   value: "iOS \(newestSameMajor)",
                                   detail: "Du hast iOS \(current). Apple hat bereits iOS \(newestSameMajor) veröffentlicht. Solche Updates schließen fast immer Sicherheitslücken, die teils schon aktiv ausgenutzt werden.",
                                   advice: "Einstellungen › Allgemein › Softwareupdate. Achtung: Danach kann die SideStore-Kopplung neu nötig sein.",
                                   severity: 2)
        }
        let note = versionLess(current, newestOverall) ? " Eine neue Hauptversion (iOS \(newestOverall)) gibt es auch – sie ist nicht zwingend, bekommt aber die längste Unterstützung." : ""
        return SecurityFinding(key: "ios", icon: "checkmark.seal.fill", title: "iOS aktuell", value: "iOS \(current)",
                               detail: "Laut Apples offizieller Versionsliste hast du alle Sicherheits-Updates für deine iOS-Version.\(note)",
                               severity: 0)
    }

    static func versionLess(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    /// Abweichung der iPhone-Uhr von der Server-Zeit in Sekunden
    private static func clockSkew() async -> Double? {
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = "HEAD"
        let start = Date()
        guard let res = try? await plainSession.data(for: r),
              let http = res.1 as? HTTPURLResponse,
              let dateString = http.value(forHTTPHeaderField: "Date") else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let server = f.date(from: dateString) else { return nil }
        let mid = start.addingTimeInterval(Date().timeIntervalSince(start) / 2)
        return mid.timeIntervalSince(server)
    }

    private static func clockFinding(_ s: Double?) -> SecurityFinding? {
        guard let s else { return nil }
        let a = abs(s)
        let text = a < 2 ? "unter 1 s" : a < 120 ? "\(Int(a.rounded())) s" : "\(Int((a / 60).rounded())) min"
        if a < 60 {
            return SecurityFinding(key: "clock", icon: "clock.badge.checkmark.fill", title: "Uhrzeit stimmt", value: text,
                                   detail: "Die Uhr deines iPhones weicht nur \(text) von der Weltzeit ab. Das ist wichtig: Zertifikate und Bestätigungscodes (2FA) sind an die Uhrzeit gebunden.",
                                   severity: 0)
        }
        return SecurityFinding(key: "clock", icon: "clock.badge.exclamationmark.fill", title: "Uhrzeit falsch", value: text,
                               detail: "Die Uhr deines iPhones geht \(text) \(s > 0 ? "vor" : "nach"). Dadurch können Sicherheitszertifikate falsch bewertet werden und Bestätigungscodes scheitern. Manche Angriffe verstellen absichtlich die Zeit.",
                               advice: "Einstellungen › Allgemein › Datum & Uhrzeit › „Automatisch einstellen“ einschalten.",
                               severity: 2)
    }

    // MARK: Messwerte mit Erklärung

    private static func facts(connection: ConnectionKind, identity id: NetIdentity?, trace: [String: String]?,
                              dns: DNSExit?, rep: Reputation?, skew: Double?, routerHost: String?,
                              systemVersion: String) -> [ScanFact] {
        var f: [ScanFact] = []
        var art = connection.label
        if connection == .cellular, let r = radioLabel() { art += " · \(r)" }
        if VPNDetect.isActive { art += " · VPN" }
        f.append(ScanFact(icon: connection.icon, label: "Verbindung", value: art,
                          explain: "Über welchen Weg dein iPhone gerade ins Internet geht. Im WLAN ist der Betreiber des Routers dein „Türsteher“, im Mobilfunk dein Mobilfunkanbieter."))
        if let ip = id?.localIP {
            f.append(ScanFact(icon: "house", label: "Adresse im Netz", value: ip,
                              explain: "Deine interne Adresse in diesem Netz. Sie ist nur hier gültig und von außen nicht erreichbar. 192.168.178.x ist typisch für eine FRITZ!Box, 172.20.10.x für einen iPhone-Hotspot."))
        }
        if let h = routerHost {
            f.append(ScanFact(icon: "wifi.router", label: "Router", value: id?.router?.displayName ?? h,
                              explain: "Das Gerät, über das alles in diesem Netz ins Internet geht. Wer den Router kontrolliert, kontrolliert das Netz – deshalb prüft OGSpeed ihn auf offene Türen."))
        }
        if let ip = id?.ipv4 ?? trace?["ip"] {
            f.append(ScanFact(icon: "globe", label: "Öffentliche IPv4", value: ip,
                              explain: "Unter dieser Adresse sieht dich jede Webseite. Sie verrät grob deinen Ort und deinen Anbieter, aber nicht deinen Namen. Im Mobilfunk teilen sich oft viele Kunden eine Adresse."))
        }
        if let v6 = id?.ipv6 {
            f.append(ScanFact(icon: "globe.badge.chevron.backward", label: "Öffentliche IPv6", value: v6,
                              explain: "Die neue Adressart des Internets. Jedes Gerät hat eine eigene. Die hintere Hälfte sollte zufällig sein und regelmäßig wechseln, damit du nicht wiedererkannt wirst."))
        } else {
            f.append(ScanFact(icon: "globe.badge.chevron.backward", label: "Öffentliche IPv6", value: "keine",
                              explain: "Dieses Netz nutzt kein IPv6. Das ist kein Sicherheitsproblem, nur etwas altmodisch."))
        }
        if let p = id?.providerName ?? rep?.company {
            var v = p
            if let asn = id?.asn { v += " (AS\(asn))" }
            f.append(ScanFact(icon: "building.2", label: "Anbieter", value: v,
                              explain: "Wem die Internet-Adresse gehört. „AS“ ist die Nummer des Netzes im weltweiten Internet – so finden sich die Netze gegenseitig."))
        }
        if let c = id?.city ?? trace?["loc"] {
            f.append(ScanFact(icon: "mappin", label: "Standort laut IP", value: c,
                              explain: "Wo Webseiten dich anhand deiner Adresse vermuten. Das ist meist der Knotenpunkt deines Anbieters, nicht deine Wohnung."))
        }
        if let r = rep {
            let typ: String
            if r.vpn { typ = "VPN-Dienst" }
            else if r.datacenter { typ = "Rechenzentrum" }
            else if r.mobile { typ = "Mobilfunk" }
            else { typ = r.type == "isp" ? "Privatanschluss" : (r.type ?? "Privatanschluss") }
            f.append(ScanFact(icon: "tag", label: "Art der Adresse", value: typ,
                              explain: "So stufen Webseiten deine Adresse ein. „Rechenzentrum“ oder „VPN“ führt öfter zu Captchas, „Privatanschluss“ und „Mobilfunk“ wirken normal."))
        }
        if let op = dns?.operatorName {
            f.append(ScanFact(icon: "book.closed", label: "DNS-Server", value: op,
                              explain: "Dieser Dienst übersetzt Namen wie apple.com in Adressen. Er sieht, welche Seiten du aufrufst. Ideal ist dein eigener Anbieter oder ein vertrauenswürdiger Dienst wie Cloudflare oder Quad9."))
        }
        if let tls = trace?["tls"] {
            f.append(ScanFact(icon: "lock", label: "Verschlüsselung", value: tls.replacingOccurrences(of: "TLSv", with: "TLS "),
                              explain: "Das Verfahren, mit dem Webseiten-Verbindungen verschlüsselt werden. TLS 1.3 ist der aktuelle Standard, TLS 1.2 noch in Ordnung, alles darunter unsicher."))
        }
        if let h = trace?["http"] {
            f.append(ScanFact(icon: "arrow.left.arrow.right", label: "Protokoll", value: h.uppercased(),
                              explain: "Die Sprache zwischen Browser und Server. HTTP/3 ist am schnellsten und läuft komplett verschlüsselt über UDP."))
        }
        if let s = skew {
            f.append(ScanFact(icon: "clock", label: "Uhr-Abweichung", value: String(format: "%+.1f s", s).replacingOccurrences(of: ".", with: ","),
                              explain: "Wie weit deine iPhone-Uhr von der Weltzeit abweicht. Unter einer Minute ist alles gut."))
        }
        f.append(ScanFact(icon: "iphone", label: "iOS", value: systemVersion,
                          explain: "Deine Systemversion. Die wichtigste Sicherheitsmaßnahme überhaupt ist, sie aktuell zu halten."))
        return f
    }
}

// MARK: - Bonjour-Suche

enum BonjourScan {

    struct Kind {
        var label: String
        var severity: Int
        var icon: String
    }

    static let types: [(String, Kind)] = [
        ("_ssh._tcp", Kind(label: "SSH-Fernzugriff", severity: 2, icon: "terminal")),
        ("_sftp-ssh._tcp", Kind(label: "SFTP-Dateizugriff", severity: 2, icon: "folder")),
        ("_rfb._tcp", Kind(label: "Bildschirmfreigabe (VNC)", severity: 2, icon: "display")),
        ("_telnet._tcp", Kind(label: "Telnet", severity: 3, icon: "terminal")),
        ("_ftp._tcp", Kind(label: "FTP-Server", severity: 2, icon: "folder")),
        ("_smb._tcp", Kind(label: "Datei-Freigabe", severity: 1, icon: "externaldrive.connected.to.line.below")),
        ("_afpovertcp._tcp", Kind(label: "Apple-Freigabe", severity: 1, icon: "externaldrive")),
        ("_adisk._tcp", Kind(label: "Time-Machine-Speicher", severity: 0, icon: "clock.arrow.circlepath")),
        ("_mqtt._tcp", Kind(label: "Smart-Home-Zentrale (MQTT)", severity: 1, icon: "house")),
        ("_home-assistant._tcp", Kind(label: "Home Assistant", severity: 0, icon: "house.fill")),
        ("_hap._tcp", Kind(label: "HomeKit-Gerät", severity: 0, icon: "homekit")),
        ("_http._tcp", Kind(label: "Weboberfläche", severity: 0, icon: "safari")),
        ("_ipp._tcp", Kind(label: "Drucker", severity: 0, icon: "printer")),
        ("_printer._tcp", Kind(label: "Drucker", severity: 0, icon: "printer")),
        ("_airplay._tcp", Kind(label: "AirPlay", severity: 0, icon: "airplayvideo")),
        ("_raop._tcp", Kind(label: "AirPlay-Lautsprecher", severity: 0, icon: "hifispeaker")),
        ("_googlecast._tcp", Kind(label: "Chromecast", severity: 0, icon: "tv")),
        ("_spotify-connect._tcp", Kind(label: "Spotify Connect", severity: 0, icon: "music.note")),
        ("_sonos._tcp", Kind(label: "Sonos", severity: 0, icon: "hifispeaker.2")),
        ("_hue._tcp", Kind(label: "Philips Hue", severity: 0, icon: "lightbulb")),
        ("_companion-link._tcp", Kind(label: "Apple-Gerät", severity: 0, icon: "applelogo")),
        ("_amzn-wplay._tcp", Kind(label: "Fire TV / Echo", severity: 0, icon: "tv")),
        ("_workstation._tcp", Kind(label: "Computer / NAS", severity: 0, icon: "desktopcomputer")),
        ("_device-info._tcp", Kind(label: "Gerät", severity: 0, icon: "questionmark.square"))
    ]

    static func kind(for type: String) -> Kind? {
        let t = type.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return types.first { t.hasPrefix($0.0) }?.1
    }

    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var items = Set<LanService>()
        private var denied = false
        func add(_ s: LanService) { _ = lock.withLock { items.insert(s) } }
        func deny() { lock.withLock { denied = true } }
        var result: (services: [LanService], denied: Bool) {
            lock.withLock { (items.sorted { $0.name < $1.name }, denied && items.isEmpty) }
        }
    }

    /// Sucht einige Sekunden nach Geräten, die sich im Netz vorstellen.
    static func scan(seconds: Double) async -> (services: [LanService], denied: Bool) {
        await withCheckedContinuation { cont in
            let box = Collector()
            let q = DispatchQueue(label: "ogspeed.bonjour")
            let browsers: [NWBrowser] = types.map { t in
                let b = NWBrowser(for: .bonjour(type: t.0, domain: "local."), using: NWParameters())
                b.browseResultsChangedHandler = { results, _ in
                    for r in results {
                        if case let .service(name, type, _, _) = r.endpoint,
                           let clean = Sanitize.deviceName(name, max: 40) {
                            box.add(LanService(name: clean, type: type))
                        }
                    }
                }
                b.stateUpdateHandler = { state in
                    switch state {
                    case .waiting(let e), .failed(let e):
                        if case let .dns(code) = e, code == -65570 { box.deny() }
                    default: break
                    }
                }
                return b
            }
            for b in browsers { b.start(queue: q) }
            q.asyncAfter(deadline: .now() + seconds) {
                for b in browsers { b.cancel() }
                cont.resume(returning: box.result)
            }
        }
    }
}
