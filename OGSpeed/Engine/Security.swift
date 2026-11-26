import Foundation
import CryptoKit

/// Schalter rund um Privatsphäre und Sicherheit
enum PrivacyKeys {
    static let routerScan = "privRouterScan"        // Router im Heimnetz suchen
    static let encryptedDNS = "privEncryptedDNS"    // Namen über DNS-over-HTTPS auflösen
    static let showSSIDInShare = "privShareSSID"    // WLAN-Name in geteilten Bildern
    static let fritzAllowHTTP = "privFritzHTTP"     // Rückfall auf unverschlüsseltes TR-064 erlauben
}

enum Privacy {
    private static var d: UserDefaults { .standard }

    /// Standard: an – ohne Suche kennt OGSpeed das Router-Modell nicht.
    static var routerScan: Bool { d.object(forKey: PrivacyKeys.routerScan) as? Bool ?? true }
    /// Standard: an – Namen werden verschlüsselt aufgelöst, niemand im WLAN sieht sie.
    static var encryptedDNS: Bool { d.object(forKey: PrivacyKeys.encryptedDNS) as? Bool ?? true }
    /// Standard: aus – der WLAN-Name bleibt aus geteilten Bildern heraus.
    static var showSSIDInShare: Bool { d.bool(forKey: PrivacyKeys.showSSIDInShare) }
    /// Standard: aus – lieber keine Verbindung als eine unverschlüsselte.
    static var fritzAllowHTTP: Bool { d.bool(forKey: PrivacyKeys.fritzAllowHTTP) }
}

/// Text aus dem Heimnetz (Router-Seiten) ist fremde Eingabe: kürzen und säubern,
/// bevor er in der Oberfläche landet.
enum Sanitize {
    static func deviceName(_ s: String?, max: Int = 48) -> String? {
        guard let s else { return nil }
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " .,!+-_()/äöüÄÖÜß&"))
        let cleaned = String(s.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(max))
    }

    /// Nur private Adressen aus dem eigenen Netz zulassen
    static func isLocalAddress(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4, p.allSatisfy({ (0...255).contains($0) }) else { return false }
        if p[0] == 10 { return true }
        if p[0] == 172 && (16...31).contains(p[1]) { return true }
        if p[0] == 192 && p[1] == 168 { return true }
        return false
    }
}

/// Zertifikats-Bindung für die FRITZ!Box.
/// Die FRITZ!Box signiert ihr HTTPS-Zertifikat selbst, deshalb merkt sich OGSpeed
/// beim ersten Verbinden dessen Fingerabdruck. Taucht später ein anderes
/// Zertifikat auf, wird die Verbindung abgelehnt – so kann sich niemand im WLAN
/// als deine FRITZ!Box ausgeben und das Kennwort abgreifen.
enum CertPin {
    private static func key(_ host: String) -> String { "pin.\(host.lowercased())" }

    static func fingerprint(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else { return nil }
        let der = SecCertificateCopyData(leaf) as Data
        return SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    static func stored(_ host: String) -> String? {
        UserDefaults.standard.string(forKey: key(host))
    }

    static func store(_ fp: String, host: String) {
        UserDefaults.standard.set(fp, forKey: key(host))
    }

    static func forget(_ host: String) {
        UserDefaults.standard.removeObject(forKey: key(host))
    }

    /// true = Verbindung akzeptieren
    static func accept(trust: SecTrust, host: String) -> Bool {
        guard let fp = fingerprint(of: trust) else { return false }
        if let known = stored(host) {
            return known == fp
        }
        store(fp, host: host)   // erstes Verbinden: Fingerabdruck merken
        return true
    }
}
