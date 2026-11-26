import Foundation
import Security

/// Schlüssel für @AppStorage und direkte Zugriffe
enum K {
    static let fritzEnabled = "fritzEnabled"
    static let fritzHost = "fritzHost"
    static let fritzUser = "fritzUser"
    static let dataSaver = "dataSaver"
    static let searchSound = "searchSound"
    static let watchEnabled = "watchEnabled"
    static let watchMinMbps = "watchMinMbps"
    // Festnetz-Tarif laut Vertrag (Mbit/s)
    static let tDownMax = "tDownMax", tDownNormal = "tDownNormal", tDownMin = "tDownMin"
    static let tUpMax = "tUpMax", tUpNormal = "tUpNormal", tUpMin = "tUpMin"
    static let tProvider = "tProvider"
    // Mobilfunk
    static let mDownMax = "mDownMax", mProvider = "mProvider"
}

enum Prefs {
    static var d: UserDefaults { .standard }
    static var fritzEnabled: Bool { d.bool(forKey: K.fritzEnabled) }
    static var fritzHost: String { (d.string(forKey: K.fritzHost)).flatMap { $0.isEmpty ? nil : $0 } ?? "fritz.box" }
    static var fritzUser: String { d.string(forKey: K.fritzUser) ?? "" }
    static var dataSaver: Bool { d.object(forKey: K.dataSaver) as? Bool ?? true }
    static var watchEnabled: Bool { d.bool(forKey: K.watchEnabled) }
    static var watchMinMbps: Double { let v = d.double(forKey: K.watchMinMbps); return v > 0 ? v : 5 }
    static func double(_ k: String) -> Double { d.double(forKey: k) }
}

/// Passwort der FRITZ!Box sicher im Schlüsselbund
enum Keychain {
    private static let service = "com.eren2524.ogspeed.fritz"

    static func set(_ value: String, account: String = "fritz") {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        // Nur auf diesem iPhone und nur im entsperrten Zustand lesbar;
        // landet damit auch in keinem Backup.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(account: String = "fritz") -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
