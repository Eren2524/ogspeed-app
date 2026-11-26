import Foundation

// MARK: - Befund

struct SecurityFinding: Codable, Identifiable, Hashable {
    var id = UUID()
    var key: String
    var icon: String
    var title: String
    var value: String
    var detail: String
    var advice: String?
    /// 0 = alles gut, 1 = Hinweis, 2 = Warnung, 3 = Gefahr
    var severity: Int
    /// Rubrik im Sicherheits-Labor (fehlt bei älteren gespeicherten Tests)
    var category: String? = nil

    var level: Level {
        switch severity {
        case 0: return .great
        case 1: return .good
        case 2: return .ok
        default: return .bad
        }
    }

    var severityLabel: String {
        switch severity {
        case 0: return "In Ordnung"
        case 1: return "Hinweis"
        case 2: return "Warnung"
        default: return "Gefahr"
        }
    }
}

extension Array where Element == SecurityFinding {
    var worstSeverity: Int { map(\.severity).max() ?? 0 }
    var problems: [SecurityFinding] { filter { $0.severity >= 2 }.sorted { $0.severity > $1.severity } }

    var headline: (Level, String, String) {
        let bad = problems
        if isEmpty { return (.ok, "Nicht geprüft", "Der Sicherheits-Check lief nicht.") }
        if bad.isEmpty {
            return (.great, "Netzwerk unauffällig",
                    "Keine Anzeichen für Mitlesen, Umleitung oder offene Türen. \(count) Punkte geprüft.")
        }
        if bad.contains(where: { $0.severity >= 3 }) {
            return (.bad, "Gefahr erkannt", bad.filter { $0.severity >= 3 }.map(\.title).joined(separator: ", "))
        }
        return (.ok, "\(bad.count) \(bad.count == 1 ? "Warnung" : "Warnungen")",
                bad.map(\.title).joined(separator: ", "))
    }
}

