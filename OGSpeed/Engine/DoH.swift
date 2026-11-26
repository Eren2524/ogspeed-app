import Foundation

/// Löst Namen über DNS-over-HTTPS auf (verschlüsselt).
///
/// Warum: Ein normaler Namensaufruf geht im Klartext durchs WLAN. Jeder, der
/// mitschneidet, sieht dann, welche Dienste dein iPhone gerade prüft – also
/// z. B. „my.playstation.com“ oder „netflix.com“. Mit DoH geht die Anfrage
/// verschlüsselt an Cloudflare, und OGSpeed verbindet sich danach direkt mit der
/// IP-Adresse. Im WLAN ist damit nur noch eine Verbindung zu einer IP sichtbar.
enum DoH {
    static let endpoint = URL(string: "https://cloudflare-dns.com/dns-query")!

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: (ips: [String], until: Date)] = [:]

    static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.waitsForConnectivity = false
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    /// Liefert eine IPv4-Adresse für den Namen, oder nil.
    /// Ist der Name schon eine IP-Adresse, kommt er unverändert zurück.
    static func address(for host: String) async -> String? {
        if isIPv4(host) || host.contains(":") { return host }
        guard Privacy.encryptedDNS else { return host }   // Schalter aus: System-Auflösung

        let now = Date()
        if let hit = lock.withLock({ cache[host] }), hit.until > now, let first = hit.ips.first {
            return first
        }
        guard let ips = await query(host), let first = ips.first else { return nil }
        lock.withLock { cache[host] = (ips, now.addingTimeInterval(300)) }
        return first
    }

    static func isIPv4(_ s: String) -> Bool {
        let p = s.split(separator: ".")
        return p.count == 4 && p.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    private static func query(_ name: String) async -> [String]? {
        var r = URLRequest(url: endpoint)
        r.httpMethod = "POST"
        r.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        r.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        r.httpBody = Probes.buildQuery(name)
        r.timeoutInterval = 4
        guard let res = try? await session.data(for: r),
              (res.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let ips = parseA(res.0)
        return ips.isEmpty ? nil : ips
    }

    /// Antwortpaket auswerten und die A-Einträge herausziehen
    static func parseA(_ data: Data) -> [String] {
        let b = [UInt8](data)
        guard b.count > 12 else { return [] }
        let qd = Int(b[4]) << 8 | Int(b[5])
        let an = Int(b[6]) << 8 | Int(b[7])
        var i = 12

        func skipName(_ start: Int) -> Int? {
            var j = start
            while j < b.count {
                let len = Int(b[j])
                if len == 0 { return j + 1 }
                if len & 0xC0 == 0xC0 { return j + 2 }   // Verweis auf frühere Stelle
                j += 1 + len
            }
            return nil
        }

        for _ in 0..<qd {
            guard let next = skipName(i), next + 4 <= b.count else { return [] }
            i = next + 4
        }

        var out: [String] = []
        for _ in 0..<an {
            guard let next = skipName(i), next + 10 <= b.count else { break }
            var j = next
            let type = Int(b[j]) << 8 | Int(b[j + 1])
            j += 8                                    // Typ(2) + Klasse(2) + TTL(4)
            let rdlen = Int(b[j]) << 8 | Int(b[j + 1])
            j += 2
            guard j + rdlen <= b.count else { break }
            if type == 1 && rdlen == 4 {
                out.append("\(b[j]).\(b[j + 1]).\(b[j + 2]).\(b[j + 3])")
            }
            i = j + rdlen
        }
        return out
    }
}
