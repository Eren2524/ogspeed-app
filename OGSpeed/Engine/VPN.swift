import Foundation
import Observation

// MARK: - Erkennung

enum VPNDetect {
    /// iOS verrät Apps nicht direkt, ob ein VPN läuft. Zwei Wege zusammen sind
    /// aber zuverlässig: die Netzwerk-Einstellungen nennen Tunnel-Schnittstellen,
    /// und ein aktiver Tunnel bekommt eine eigene IPv4-Adresse.
    static var isActive: Bool { scopedTunnel != nil || tunnelAddress != nil }

    /// Name der Tunnel-Schnittstelle aus den System-Einstellungen
    static var scopedTunnel: String? {
        guard let cf = CFNetworkCopySystemProxySettings()?.takeRetainedValue(),
              let settings = cf as? [String: Any],
              let scoped = settings["__SCOPED__"] as? [String: Any] else { return nil }
        let markers = ["tap", "tun", "ppp", "ipsec", "ipsec0"]
        for key in scoped.keys {
            let k = key.lowercased()
            if markers.contains(where: { k.hasPrefix($0) }) { return key }
        }
        return nil
    }

    /// IPv4-Adresse eines aktiven Tunnels (z. B. 10.5.0.2 bei WireGuard)
    static var tunnelAddress: String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            let name = String(cString: ifa.ifa_name)
            if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp"),
               let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if ip != "0.0.0.0" && !ip.hasPrefix("127.") { return ip }
                }
            }
            ptr = ifa.ifa_next
        }
        return nil
    }

    /// Grober Hinweis, welche Art von Tunnel läuft
    static var kindLabel: String {
        if let s = scopedTunnel?.lowercased() {
            if s.hasPrefix("ipsec") { return "IPSec/IKEv2" }
            if s.hasPrefix("ppp") { return "PPTP/L2TP" }
            return "WireGuard oder OpenVPN"
        }
        if tunnelAddress != nil { return "WireGuard oder OpenVPN" }
        return "keiner"
    }
}

// MARK: - Ausgangspunkt im Internet

struct ExitInfo: Codable, Equatable {
    var ip: String?
    var countryCode: String?
    var city: String?
    var organisation: String?
    var asn: String?
    var colo: String?
    var tls: String?
    var checked = Date()

    var countryName: String? {
        guard let c = countryCode else { return nil }
        return Locale(identifier: "de_DE").localizedString(forRegionCode: c) ?? c
    }

    var place: String {
        var parts: [String] = []
        if let c = city, !c.isEmpty { parts.append(c) }
        if let n = countryName { parts.append(n) }
        return parts.isEmpty ? "unbekannt" : parts.joined(separator: ", ")
    }

    var shortOrg: String? {
        guard let o = organisation else { return nil }
        return Sanitize.deviceName(o, max: 40)
    }
}

struct DNSExit: Codable, Equatable {
    var ip: String?
    var geo: String?        // z. B. "Germany - Vodafone GmbH"

    var operatorName: String? {
        guard let g = geo, let r = g.range(of: " - ") else { return geo }
        return String(g[r.upperBound...])
    }
    var countryName: String? {
        guard let g = geo, let r = g.range(of: " - ") else { return nil }
        return String(g[..<r.lowerBound])
    }
}

enum ExitProbe {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.waitsForConnectivity = false
        cfg.urlCache = nil
        cfg.httpCookieAcceptPolicy = .never
        return URLSession(configuration: cfg)
    }()

    private static func json(_ url: String) async -> [String: Any]? {
        guard let u = URL(string: url) else { return nil }
        var r = URLRequest(url: u)
        r.timeoutInterval = 8
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let res = try? await session.data(for: r), res.0.count < 200_000 else { return nil }
        return (try? JSONSerialization.jsonObject(with: res.0)) as? [String: Any]
    }

    private static func trace(_ url: String) async -> [String: String]? {
        guard let u = URL(string: url) else { return nil }
        var r = URLRequest(url: u)
        r.timeoutInterval = 8
        guard let res = try? await session.data(for: r), res.0.count < 20_000,
              let text = String(data: res.0, encoding: .utf8) else { return nil }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out.isEmpty ? nil : out
    }

    /// Wo tritt der Verkehr ins Internet aus?
    static func exit() async -> ExitInfo {
        var info = ExitInfo()
        if let t = await trace("https://speed.cloudflare.com/cdn-cgi/trace") {
            info.ip = t["ip"]
            info.countryCode = t["loc"]
            info.colo = t["colo"].flatMap { Cloudflare.colos[$0] ?? $0 }
            info.tls = t["tls"]
        }
        // Betreiber und Stadt dazu (zwei Quellen, falls eine gerade streikt)
        if let a = await json("https://api.ipapi.is/") {
            if info.ip == nil { info.ip = a["ip"] as? String }
            info.organisation = (a["company"] as? String) ?? (a["asn"] as? String)
            info.asn = a["asn"] as? String
            info.city = a["city"] as? String
            if info.countryCode == nil, let c = a["country"] as? String { info.countryCode = c }
        } else if let b = await json("https://ipinfo.io/json") {
            if info.ip == nil { info.ip = b["ip"] as? String }
            info.organisation = b["org"] as? String
            info.city = b["city"] as? String
            if info.countryCode == nil { info.countryCode = b["country"] as? String }
        }
        info.checked = Date()
        return info
    }

    /// Welcher Namensserver fragt für dich an? (DNS-Leck-Test)
    static func dnsExit() async -> DNSExit? {
        guard let d = await json("https://edns.ip-api.com/json"),
              let dns = d["dns"] as? [String: Any] else { return nil }
        return DNSExit(ip: dns["ip"] as? String, geo: Sanitize.deviceName(dns["geo"] as? String, max: 60))
    }
}

// MARK: - Prüfbericht

struct VPNFinding: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String
    let detail: String
    let level: Level
}

@MainActor @Observable
final class VPNChecker {
    var running = false
    var active = false
    var exitInfo: ExitInfo?
    var dns: DNSExit?
    var findings: [VPNFinding] = []
    var checkedAt: Date?

    private let baselineKey = "vpnBaselineExit"

    /// Zustand ohne VPN – daran erkennt die App, dass sich der Ausgang verschoben hat
    var baseline: ExitInfo? {
        get {
            guard let d = UserDefaults.standard.data(forKey: baselineKey) else { return nil }
            return try? JSONDecoder.iso.decode(ExitInfo.self, from: d)
        }
        set {
            if let v = newValue, let d = try? JSONEncoder.iso.encode(v) {
                UserDefaults.standard.set(d, forKey: baselineKey)
            }
        }
    }

    func refreshStatus() { active = VPNDetect.isActive }

    func run(connection: ConnectionKind) async {
        running = true
        defer { running = false }
        active = VPNDetect.isActive

        async let e = ExitProbe.exit()
        async let d = ExitProbe.dnsExit()
        let info = await e
        let dnsInfo = await d
        exitInfo = info
        dns = dnsInfo
        checkedAt = Date()

        if !active, info.ip != nil { baseline = info }   // Merker für später
        findings = build(info: info, dns: dnsInfo, connection: connection)
    }

    private func build(info: ExitInfo, dns: DNSExit?, connection: ConnectionKind) -> [VPNFinding] {
        var out: [VPNFinding] = []
        let base = baseline

        // 1) Läuft überhaupt ein Tunnel?
        out.append(VPNFinding(
            icon: active ? "lock.fill" : "lock.open.fill",
            title: "VPN-Tunnel",
            value: active ? "Aktiv (\(VPNDetect.kindLabel))" : "Nicht aktiv",
            detail: active
                ? "iOS meldet eine aktive Tunnel-Verbindung. Alles, was dein iPhone sendet, läuft verschlüsselt durch diesen Tunnel."
                : "Gerade läuft kein VPN. Starte es in der NordVPN- oder WireGuard-App und prüfe dann erneut.",
            level: active ? .great : .bad))

        // 2) Wo tritt der Verkehr aus?
        if let ip = info.ip {
            let org = info.shortOrg ?? "unbekannter Betreiber"
            out.append(VPNFinding(
                icon: "globe.europe.africa.fill",
                title: "Ausgangsserver",
                value: info.place,
                detail: "Jede Webseite sieht dich mit \(ip) bei \(org). Cloudflare erreicht dich über \(info.colo ?? "unbekannt").",
                level: active ? .great : .ok))
        } else {
            out.append(VPNFinding(icon: "globe", title: "Ausgangsserver", value: "Nicht prüfbar",
                                  detail: "Der Prüfdienst war nicht erreichbar. Besteht gerade Internetverbindung?",
                                  level: .ok))
        }

        // 3) Hat sich der Standort wirklich verschoben?
        if active {
            if let b = base, let bip = b.ip, let nip = info.ip {
                let moved = bip != nip
                let countryChanged = (b.countryCode ?? "") != (info.countryCode ?? "")
                var text = moved
                    ? "Ohne VPN tritt dein Verkehr in \(b.place) bei \(b.shortOrg ?? "deinem Anbieter") aus, jetzt in \(info.place)."
                    : "Die öffentliche Adresse ist dieselbe wie ohne VPN. Entweder ist der Tunnel nicht aktiv, oder er leitet nicht den ganzen Verkehr."
                if moved && !countryChanged {
                    text += " Gleiches Land, aber anderer Betreiber – typisch für ein VPN zu dir nach Hause."
                }
                out.append(VPNFinding(
                    icon: moved ? "arrow.triangle.swap" : "exclamationmark.triangle.fill",
                    title: "Standort verschoben",
                    value: moved ? (countryChanged ? "Ja, anderes Land" : "Ja, anderer Betreiber") : "Nein",
                    detail: text,
                    level: moved ? .great : .bad))
            } else {
                out.append(VPNFinding(
                    icon: "questionmark.circle",
                    title: "Standort verschoben",
                    value: "Noch kein Vergleich",
                    detail: "Schalte das VPN einmal aus und prüfe erneut. OGSpeed merkt sich dann deinen normalen Ausgang und kann ab dann beweisen, dass sich etwas verschiebt.",
                    level: .ok))
            }
        }

        // 4) DNS-Leck
        if let dns {
            let op = dns.operatorName ?? "unbekannt"
            let leaks = active && isOwnProvider(op, base: base)
            out.append(VPNFinding(
                icon: leaks ? "exclamationmark.triangle.fill" : "checkmark.shield.fill",
                title: "DNS-Leck",
                value: leaks ? "Undicht!" : (active ? "Dicht" : op),
                detail: leaks
                    ? "Deine Namensanfragen gehen an \(op) – also am Tunnel vorbei. Dein Anbieter sieht dadurch weiterhin, welche Seiten du aufrufst. In der NordVPN-App „Bedrohungsschutz“ bzw. eigenes DNS einschalten."
                    : "Namensanfragen werden von \(op)\(dns.countryName.map { " in \($0)" } ?? "") beantwortet. \(active ? "Das liegt innerhalb deines Tunnels – dein Anbieter sieht die Namen nicht." : "Ohne VPN ist das normal.")",
                level: leaks ? .bad : (active ? .great : .ok)))
        }

        // 5) Verschlüsselung
        out.append(VPNFinding(
            icon: "lock.shield.fill",
            title: "Verschlüsselung",
            value: active ? "Tunnel + HTTPS" : "Nur HTTPS",
            detail: active
                ? "Doppelt abgesichert: Der VPN-Tunnel verschlüsselt alles zwischen iPhone und Server (WireGuard nutzt ChaCha20), darin liegt zusätzlich das HTTPS der einzelnen Seiten. Im WLAN, in dem du sitzt, ist nur noch eine einzige Verbindung zum VPN-Server sichtbar – keine Ziele, keine Namen."
                : "Ohne VPN ist jede Seite einzeln per HTTPS geschützt. Wer im WLAN mitschneidet, sieht aber weiterhin, mit welchen Servern du sprichst.",
            level: active ? .great : .ok))

        // 6) Mobilfunk ausdrücklich bestätigen
        out.append(VPNFinding(
            icon: connection.icon,
            title: "Verbindungsart",
            value: connection.label,
            detail: connection == .cellular
                ? (active ? "Der Tunnel läuft auch über mobile Daten – genau wie gewünscht." : "Mobilfunk erkannt. Ein VPN funktioniert hier genauso wie im WLAN.")
                : "Im WLAN. Prüf den Tunnel auch einmal unterwegs über mobile Daten.",
            level: .great))

        return out
    }

    /// Gehört der DNS-Betreiber zu deinem eigenen Anbieter? Dann ist es ein Leck.
    private func isOwnProvider(_ op: String, base: ExitInfo?) -> Bool {
        let o = op.lowercased()
        let known = ["1&1", "versatel", "united internet", "vodafone", "kabel deutschland",
                     "telekom", "telefonica", "telefónica"]
        if known.contains(where: { o.contains($0) }) { return true }
        if let b = base?.shortOrg?.lowercased() {
            let word = b.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
            if word.count > 3 && o.contains(word) { return true }
        }
        return false
    }

    var verdict: (Level, String, String) {
        guard checkedAt != nil else {
            return (.ok, "Noch nicht geprüft", "Tippe auf „Jetzt prüfen“.")
        }
        if !active {
            return (.ok, "Kein VPN aktiv",
                    "Dein Verkehr läuft direkt über deinen Anbieter. Für den Beweis später merkt sich OGSpeed jetzt diesen Normalzustand.")
        }
        let bad = findings.filter { $0.level == .bad }
        if bad.isEmpty {
            let place = exitInfo?.place ?? "einem anderen Netz"
            return (.great, "VPN arbeitet sauber",
                    "Verschlüsselt, und dein Verkehr tritt in \(place) aus. Kein DNS-Leck gefunden.")
        }
        return (.ok, "VPN aktiv, aber mit Lücke",
                bad.map(\.title).joined(separator: ", ") + " – Details stehen unten.")
    }
}
