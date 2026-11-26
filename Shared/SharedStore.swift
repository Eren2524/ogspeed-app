import Foundation

/// Gemeinsamer Speicher für App und Widget.
/// SideStore/AltStore benennen die App Group beim Signieren um und schreiben
/// den neuen Namen in "ALTAppGroups" – den lesen wir zuerst.
enum SharedStore {
    static let baseGroup = "group.com.eren2524.ogspeed"

    static let groupID: String? = {
        var bundles = [Bundle.main]
        // Im Widget liegt das Haupt-Bundle zwei Ebenen höher (OGSpeed.app/PlugIns/X.appex)
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        if let b = Bundle(url: parent), b.bundleURL != Bundle.main.bundleURL { bundles.append(b) }
        var candidates: [String] = []
        for b in bundles {
            if let groups = b.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
                candidates += groups.filter { $0.hasPrefix(baseGroup) }
            }
        }
        candidates.append(baseGroup)
        for id in candidates where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil {
            return id
        }
        return nil
    }()

    static var defaults: UserDefaults {
        if let id = groupID, let d = UserDefaults(suiteName: id) { return d }
        return .standard
    }

    static var folder: URL {
        if let id = groupID, let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return url
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var historyURL: URL { folder.appendingPathComponent("ogspeed-history.json") }

    static func loadHistory() -> [SpeedResult] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder.iso.decode([SpeedResult].self, from: data)) ?? []
    }

    static func saveHistory(_ list: [SpeedResult]) {
        if let data = try? JSONEncoder.iso.encode(list) {
            FileGuard.write(data, to: historyURL, widgetReadable: true)
        }
        if let last = list.first, let data = try? JSONEncoder.iso.encode(last) {
            defaults.set(data, forKey: "lastResult")
        } else {
            defaults.removeObject(forKey: "lastResult")
        }
    }

    static var lastResult: SpeedResult? {
        guard let data = defaults.data(forKey: "lastResult") else { return loadHistory().first }
        return try? JSONDecoder.iso.decode(SpeedResult.self, from: data)
    }

    /// Wird vom Siri-Kurzbefehl gesetzt, die App startet dann sofort einen Test.
    static var pendingStart: Bool {
        get { defaults.bool(forKey: "pendingStart") }
        set { defaults.set(newValue, forKey: "pendingStart") }
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
