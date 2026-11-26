import Foundation

// MARK: - Zertifikats-Prüfung

/// Sieht nach, wer das Zertifikat einer bekannten Webseite ausgestellt hat.
/// Bricht jemand im Netz die Verschlüsselung auf (Firmen-Proxy, Schnüffel-Software,
/// Angreifer), taucht dort ein unbekannter Aussteller auf.
final class TLSInspector: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var chain: [String] = []

    /// Große, öffentlich bekannte Zertifizierungsstellen
    static let publicRoots = [
        "digicert", "globalsign", "isrg", "let's encrypt", "baltimore", "gts", "google trust",
        "amazon", "sectigo", "usertrust", "comodo", "geotrust", "rapidssl", "thawte", "verisign",
        "entrust", "certum", "quovadis", "swisssign", "t-systems", "telesec", "d-trust",
        "starfield", "go daddy", "microsoft", "buypass", "actalis", "harica", "ssl.com",
        "zerossl", "apple", "cloudflare", "identrust", "trustwave", "atos", "e-szigno"
    ]

    var issuers: [String] { lock.withLock { chain } }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if let certs = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
            let names = certs.compactMap { SecCertificateCopySubjectSummary($0) as String? }
            lock.withLock { chain = names }
        }
        completionHandler(.performDefaultHandling, nil)
    }

    /// Prüft eine bekannte HTTPS-Seite und liefert den obersten Aussteller zurück
    static func check(host: String = "https://www.apple.com/library/test/success.html") async -> (ok: Bool, root: String?) {
        let inspector = TLSInspector()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.urlCache = nil
        let session = URLSession(configuration: cfg, delegate: inspector, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let url = URL(string: host) else { return (false, nil) }
        var r = URLRequest(url: url)
        r.timeoutInterval = 8
        guard (try? await session.data(for: r)) != nil else { return (false, nil) }
        let names = inspector.issuers
        guard let root = names.last else { return (false, nil) }
        let lower = root.lowercased()
        let known = publicRoots.contains { lower.contains($0) }
        return (known, Sanitize.deviceName(root, max: 44))
    }
}

// MARK: - Der Scan

enum SecurityScan {

    static func run(connection: ConnectionKind, identity: NetIdentity?) async -> [SecurityFinding] {
        async let tls = TLSInspector.check()
        async let portal = captivePortal()
        async let dnsOK = dnsIntegrity()
        async let dnsWho = ExitProbe.dnsExit()
        async let fritz = fritzChecks()

        var out: [SecurityFinding] = []
        out.append(tlsFinding(await tls))
        out.append(portalFinding(await portal))
        out.append(dnsFinding(await dnsOK, who: await dnsWho, identity: identity))
        out.append(proxyFinding())
        out.append(vpnFinding(connection: connection))
        out += await fritz
        if let f = exposureFinding(identity) { out.append(f) }
        return out
    }

    // MARK: Einzelne Prüfungen

    private static func tlsFinding(_ r: (ok: Bool, root: String?)) -> SecurityFinding {
        guard let root = r.root else {
            return SecurityFinding(key: "tls", icon: "lock.slash", title: "Verschlüsselung geprüft",
                                   value: "Nicht prüfbar",
                                   detail: "Die Testseite war nicht erreichbar. Besteht gerade eine Internetverbindung?",
                                   severity: 1)
        }
        if r.ok {
            return SecurityFinding(key: "tls", icon: "checkmark.shield.fill", title: "Niemand liest mit",
                                   value: "Echtes Zertifikat",
                                   detail: "Das Zertifikat der Testseite stammt von „\(root)“ – einer offiziellen Zertifizierungsstelle. Deine verschlüsselten Verbindungen werden in diesem Netz nicht aufgebrochen.",
                                   severity: 0)
        }
        return SecurityFinding(key: "tls", icon: "eye.trianglebadge.exclamationmark.fill",
                               title: "Verschlüsselung wird aufgebrochen", value: "Fremder Aussteller",
                               detail: "Das Zertifikat wurde von „\(root)“ ausgestellt – das ist keine der großen offiziellen Stellen. In diesem Netz schaltet sich jemand zwischen dich und die Webseiten und kann mitlesen, was eigentlich verschlüsselt sein sollte. Typisch für Firmennetze mit Filter-Proxy, Schutzsoftware auf dem Gerät – oder einen Angriff.",
                               advice: "In einem fremden Netz: sofort VPN einschalten oder auf mobile Daten wechseln. Zu Hause: prüfen, welches Profil oder Programm das verursacht.",
                               severity: 3)
    }

    private static func captivePortal() async -> Int {
        // Apple liefert hier genau „Success“. Antwortet etwas anderes, greift das Netz ein.
        guard let res = await Probes.fetchText("http://captive.apple.com/hotspot-detect.html", maxBytes: 8000) else {
            return -1
        }
        return res.text.contains("Success") ? 0 : 1
    }

    private static func portalFinding(_ state: Int) -> SecurityFinding {
        switch state {
        case 0:
            return SecurityFinding(key: "portal", icon: "arrow.triangle.branch", title: "Keine Umleitung",
                                   value: "Direkt ins Internet",
                                   detail: "Eine Testabfrage kam unverändert an. Das Netz schiebt dir keine fremde Seite unter.",
                                   severity: 0)
        case 1:
            return SecurityFinding(key: "portal", icon: "exclamationmark.triangle.fill",
                                   title: "Netz leitet um", value: "Antwort verändert",
                                   detail: "Eine Testabfrage wurde unterwegs verändert. Meist ist das ein Anmelde-Portal (Hotel, Café, Bahn). Es kann aber auch ein Filter oder etwas Bösartiges sein, das deinen Verkehr umbiegt.",
                                   advice: "Melde dich erst am Portal an. Erledige danach nichts Sensibles ohne VPN.",
                                   severity: 2)
        default:
            return SecurityFinding(key: "portal", icon: "questionmark.circle", title: "Umleitung geprüft",
                                   value: "Nicht prüfbar",
                                   detail: "Die Testabfrage kam nicht durch.", severity: 1)
        }
    }

    /// Bekannte Namen mit festen Adressen – weicht die Antwort ab, biegt jemand das DNS um
    private static func dnsIntegrity() async -> Int {
        let probes: [(String, Set<String>)] = [
            ("one.one.one.one", ["1.1.1.1", "1.0.0.1"]),
            ("dns.google", ["8.8.8.8", "8.8.4.4"])
        ]
        var checked = 0
        for (name, expected) in probes {
            let got = systemResolve(name)
            guard !got.isEmpty else { continue }
            checked += 1
            if got.intersection(expected).isEmpty { return 1 }   // umgeleitet
        }
        return checked > 0 ? 0 : -1
    }

    static func systemResolve(_ host: String) -> Set<String> {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return [] }
        defer { freeaddrinfo(res) }
        var out = Set<String>()
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let cur = p {
            if let addr = cur.pointee.ai_addr {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, cur.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    out.insert(String(cString: buf))
                }
            }
            p = cur.pointee.ai_next
        }
        return out
    }

    private static func dnsFinding(_ state: Int, who: DNSExit?, identity: NetIdentity?) -> SecurityFinding {
        let whoText = who?.operatorName.map { "Deine Namensanfragen beantwortet gerade \($0)." } ?? ""
        if state == 1 {
            return SecurityFinding(key: "dns", icon: "exclamationmark.triangle.fill",
                                   title: "DNS wird umgeleitet", value: "Falsche Antwort",
                                   detail: "Bekannte Adressen werden in diesem Netz auf andere Server umgebogen. Damit kann man dich auf gefälschte Seiten schicken. \(whoText)",
                                   advice: "VPN einschalten oder am iPhone unter WLAN › DNS konfigurieren manuell 1.1.1.1 eintragen.",
                                   severity: 3)
        }
        if state == 0 {
            return SecurityFinding(key: "dns", icon: "checkmark.shield.fill", title: "DNS sauber",
                                   value: "Antworten stimmen",
                                   detail: "Bekannte Adressen werden korrekt aufgelöst, nichts wird umgebogen. \(whoText)",
                                   severity: 0)
        }
        return SecurityFinding(key: "dns", icon: "questionmark.circle", title: "DNS geprüft",
                               value: "Nicht prüfbar", detail: "Die Namensauflösung antwortete nicht.", severity: 1)
    }

    private static func proxyFinding() -> SecurityFinding {
        var entries: [String] = []
        if let cf = CFNetworkCopySystemProxySettings()?.takeRetainedValue(),
           let s = cf as? [String: Any] {
            if (s["HTTPProxy"] as? String) != nil { entries.append("HTTP") }
            if (s["HTTPSProxy"] as? String) != nil { entries.append("HTTPS") }
            if (s["ProxyAutoConfigURLString"] as? String) != nil { entries.append("automatisch (PAC)") }
        }
        if entries.isEmpty {
            return SecurityFinding(key: "proxy", icon: "checkmark.shield.fill", title: "Kein Zwischenserver",
                                   value: "Direkt",
                                   detail: "Es ist kein Proxy eingetragen. Dein Verkehr läuft nicht über einen fremden Zwischenserver.",
                                   severity: 0)
        }
        return SecurityFinding(key: "proxy", icon: "arrow.triangle.swap", title: "Proxy eingetragen",
                               value: entries.joined(separator: ", "),
                               detail: "Dein iPhone schickt den Verkehr über einen Zwischenserver. Wer diesen Server betreibt, sieht alles, was nicht zusätzlich verschlüsselt ist. Das kommt von den WLAN-Einstellungen oder einem installierten Profil.",
                               advice: "Einstellungen › WLAN › (i) › HTTP-Proxy auf „Aus“ stellen, wenn du das nicht selbst eingerichtet hast.",
                               severity: 3)
    }

    private static func vpnFinding(connection: ConnectionKind) -> SecurityFinding {
        if VPNDetect.isActive {
            return SecurityFinding(key: "vpn", icon: "lock.fill", title: "VPN schützt dich", value: "Aktiv",
                                   detail: "Ein Tunnel läuft. Selbst wenn in diesem Netz jemand mitschneidet, sieht er nur verschlüsselten Datenstrom.",
                                   severity: 0)
        }
        return SecurityFinding(key: "vpn", icon: "lock.open", title: "Kein VPN", value: "Aus",
                               detail: "Ohne VPN sieht der Betreiber dieses Netzes, mit welchen Servern du sprichst. Die Inhalte selbst sind durch HTTPS geschützt, die Ziele nicht.",
                               advice: "In fremden WLANs NordVPN einschalten.",
                               severity: connection == .wifi ? 1 : 0)
    }

    /// Bist du von außen erreichbar? Nur mit eigener öffentlicher Adresse relevant.
    private static func exposureFinding(_ identity: NetIdentity?) -> SecurityFinding? {
        guard let m = identity?.ipv4Mode else { return nil }
        switch m {
        case .real:
            return SecurityFinding(key: "exposure", icon: "globe", title: "Von außen erreichbar",
                                   value: "Eigene öffentliche IP",
                                   detail: "Dein Anschluss hat eine eigene öffentliche Adresse. Gut für Gaming und einen eigenen VPN-Server – aber alles, was du freigibst, ist dann wirklich aus dem Internet erreichbar.",
                                   advice: "Freigaben unten in dieser Liste prüfen.",
                                   severity: 1)
        case .dsLite, .cgnat, .likelyDsLite:
            return SecurityFinding(key: "exposure", icon: "shield.fill", title: "Von außen nicht erreichbar",
                                   value: "Geteilte Adresse",
                                   detail: "Dein Anschluss teilt sich die öffentliche Adresse mit anderen. Von außen kommt niemand an dein Heimnetz – nachteilig fürs Gaming, aber sicher.",
                                   severity: 0)
        case .unknown:
            return nil
        }
    }

    // MARK: Prüfungen über die FRITZ!Box

    private static func fritzChecks() async -> [SecurityFinding] {
        guard let c = FritzClient.fromPrefs() else { return [] }
        var out: [SecurityFinding] = []
        if let enc = try? await c.wlanEncryption() { out.append(encryptionFinding(enc)) }
        if let maps = try? await c.portMappings() { out.append(portFinding(maps)) }
        if let hosts = try? await c.hostList() { out.append(deviceFinding(hosts)) }
        return out
    }

    private static func encryptionFinding(_ beacon: String) -> SecurityFinding {
        let b = beacon.lowercased()
        if b.contains("none") || b.isEmpty {
            return SecurityFinding(key: "wlanenc", icon: "lock.open.trianglebadge.exclamationmark.fill",
                                   title: "WLAN ist offen", value: "Ohne Verschlüsselung",
                                   detail: "Dein WLAN ist unverschlüsselt. Jeder in Funkreichweite kann mitlesen und mitsurfen.",
                                   advice: "In der FRITZ!Box unter WLAN › Sicherheit sofort WPA2/WPA3 einschalten.",
                                   severity: 3)
        }
        if b.contains("wpa") && !b.contains("11i") && !b.contains("3") {
            return SecurityFinding(key: "wlanenc", icon: "exclamationmark.triangle.fill",
                                   title: "Veraltete WLAN-Verschlüsselung", value: beacon,
                                   detail: "Dein WLAN nutzt noch das alte WPA-Verfahren. Das gilt als knackbar.",
                                   advice: "FRITZ!Box › WLAN › Sicherheit › „WPA2 + WPA3“ wählen.",
                                   severity: 2)
        }
        let modern = b.contains("3") || b.contains("11i")
        return SecurityFinding(key: "wlanenc", icon: "checkmark.shield.fill", title: "WLAN verschlüsselt",
                               value: modern ? "WPA2/WPA3" : beacon,
                               detail: "Dein Funknetz ist zeitgemäß verschlüsselt. Mitlesen aus der Nachbarschaft ist damit praktisch ausgeschlossen.",
                               severity: 0)
    }

    private static func portFinding(_ maps: [PortMapping]) -> SecurityFinding {
        let active = maps.filter(\.enabled)
        if active.isEmpty {
            return SecurityFinding(key: "ports", icon: "checkmark.shield.fill", title: "Keine offenen Türen",
                                   value: "0 Freigaben",
                                   detail: "In deiner FRITZ!Box ist kein Port aus dem Internet freigegeben. Von außen kommt niemand direkt an ein Gerät im Heimnetz.",
                                   severity: 0)
        }
        let risky = active.filter { [21, 22, 23, 80, 443, 445, 3389, 5900, 8080].contains($0.externalPort) }
        let list = active.prefix(6).map { "\($0.externalPort) → \($0.client)" }.joined(separator: ", ")
        return SecurityFinding(key: "ports", icon: risky.isEmpty ? "door.left.hand.open" : "exclamationmark.triangle.fill",
                               title: "Offene Portfreigaben", value: "\(active.count)",
                               detail: "Aus dem Internet erreichbar: \(list). " + (risky.isEmpty
                                    ? "Prüfe, ob du jede davon noch brauchst – jede offene Tür ist ein Angriffspunkt."
                                    : "Darunter sind Ports für Fernwartung oder Weboberflächen – genau danach suchen Angreifer automatisiert."),
                               advice: "FRITZ!Box › Internet › Freigaben › Portfreigaben: alles löschen, was du nicht mehr brauchst.",
                               severity: risky.isEmpty ? 2 : 3)
    }

    private static func deviceFinding(_ hosts: [FritzHost]) -> SecurityFinding {
        let d = UserDefaults.standard
        let known = Set((d.string(forKey: "knownDevices") ?? "").split(separator: ",").map(String.init))
        let online = hosts.filter(\.active)
        if known.isEmpty {
            d.set(online.map(\.id).sorted().joined(separator: ","), forKey: "knownDevices")
            return SecurityFinding(key: "devices", icon: "person.2.fill", title: "Geräte im Netz",
                                   value: "\(online.count)",
                                   detail: "Beim ersten Mal merkt sich OGSpeed alle Geräte als bekannt. Ab jetzt meldet es dir neue.",
                                   severity: 0)
        }
        let fresh = online.filter { !known.contains($0.id) }
        if fresh.isEmpty {
            return SecurityFinding(key: "devices", icon: "checkmark.shield.fill", title: "Nur bekannte Geräte",
                                   value: "\(online.count) online",
                                   detail: "Alle verbundenen Geräte kennst du schon. Kein Fremder hängt in deinem WLAN.",
                                   severity: 0)
        }
        let names = fresh.prefix(5).map(\.name).joined(separator: ", ")
        return SecurityFinding(key: "devices", icon: "person.fill.questionmark", title: "Neue Geräte im WLAN",
                               value: "\(fresh.count)",
                               detail: "Zum ersten Mal gesehen: \(names). Wenn du die nicht zuordnen kannst, hängt jemand Fremdes in deinem Netz.",
                               advice: "Unter Netz › Geräte im WLAN ansehen und als bekannt markieren – oder WLAN-Kennwort ändern.",
                               severity: 2)
    }
}
