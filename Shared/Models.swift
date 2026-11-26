import Foundation
import SwiftUI

// MARK: - Verbindungsart

enum ConnectionKind: String, Codable, CaseIterable {
    case wifi, cellular, wired, none, unknown

    var label: String {
        switch self {
        case .wifi: return "WLAN"
        case .cellular: return "Mobilfunk"
        case .wired: return "Kabel"
        case .none: return "Offline"
        case .unknown: return "Unbekannt"
        }
    }

    var icon: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .wired: return "cable.connector"
        case .none: return "wifi.slash"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Ergebnis eines Tests

struct SpeedResult: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var connection: ConnectionKind = .unknown
    var radio: String?          // z. B. "5G", "4G (LTE)"
    var provider: String?       // z. B. "Vodafone"
    var router: String?         // z. B. "FRITZ!Box 7690"
    var vpnActive = false       // lief dieser Test durch einen VPN-Tunnel?
    var networkName: String?    // z. B. WLAN-Name von der FRITZ!Box
    var band: String?           // "2,4 GHz", "5 GHz", "6 GHz"
    var downMbps: Double = 0
    var upMbps: Double = 0
    var pingMs: Double = 0
    var jitterMs: Double = 0
    var loadedPingMs: Double = 0   // Ping während voller Auslastung
    var dropoutPercent: Double = 0 // Aussetzer (Zeitüberschreitungen + starke Ausreißer)
    var dnsMs: Double?
    var server: String?
    var dataUsedMB: Double = 0
    var signalPercent: Int?     // von der FRITZ!Box
    var linkMbps: Int?          // WLAN-Verbindungsgeschwindigkeit laut FRITZ!Box

    var bufferbloatMs: Double { max(0, loadedPingMs - pingMs) }
}

// MARK: - Ampel-Stufen

enum Level: Int, Codable, Comparable {
    case bad = 0, ok = 1, good = 2, great = 3

    static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .great: return "Top"
        case .good: return "Gut"
        case .ok: return "Geht so"
        case .bad: return "Schlecht"
        }
    }

    var color: Color {
        switch self {
        case .great: return Neon.green
        case .good: return Neon.lime
        case .ok: return Neon.yellow
        case .bad: return Neon.red
        }
    }

    var symbol: String {
        switch self {
        case .great, .good: return "checkmark.circle.fill"
        case .ok: return "exclamationmark.circle.fill"
        case .bad: return "xmark.circle.fill"
        }
    }
}

// MARK: - Farben (auch im Widget genutzt)

enum Neon {
    static let cyan = Color(red: 0.0, green: 0.94, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.17, blue: 0.84)
    static let purple = Color(red: 0.54, green: 0.36, blue: 1.0)
    static let green = Color(red: 0.22, green: 1.0, blue: 0.53)
    static let lime = Color(red: 0.70, green: 1.0, blue: 0.30)
    static let yellow = Color(red: 1.0, green: 0.82, blue: 0.25)
    static let red = Color(red: 1.0, green: 0.23, blue: 0.36)
    static let bg = Color(red: 0.03, green: 0.03, blue: 0.07)
}

// MARK: - Zahlen schön formatieren

enum Fmt {
    static func mbps(_ v: Double) -> String {
        if v >= 100 { return String(format: "%.0f", v) }
        if v >= 10 { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }
    static func ms(_ v: Double) -> String { String(format: "%.0f", v) }

    static func duration(seconds s: Double) -> String {
        if !s.isFinite || s <= 0 { return "–" }
        if s < 60 { return "unter 1 Min" }
        let m = Int(s / 60)
        if m < 60 { return "ca. \(m) Min" }
        let h = m / 60, rm = m % 60
        if h >= 48 { return "über \(h / 24) Tage" }
        return rm == 0 ? "ca. \(h) Std" : "ca. \(h) Std \(rm) Min"
    }

    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
