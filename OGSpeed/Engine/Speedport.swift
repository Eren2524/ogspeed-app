import Foundation
import CommonCrypto

/// Liest die öffentliche Statusseite eines Telekom Speedport (ohne Anmeldung).
/// Beim Speedport Smart 4 ist sie mit einem festen, öffentlich bekannten Schlüssel
/// verschlüsselt (AES-CCM) – ältere Modelle liefern sie unverschlüsselt.
struct SpeedportStatus: Equatable {
    var values: [String: String]

    var linkOnline: Bool? {
        guard let v = values["dsl_link_status"] else { return nil }
        return v.lowercased() == "online"
    }
    var downMbps: Double? { values["dsl_downstream"].flatMap(Double.init).map { $0 / 1000 } }
    var upMbps: Double? { values["dsl_upstream"].flatMap(Double.init).map { $0 / 1000 } }
    var firmware: String? { Sanitize.deviceName(values["firmware_version"], max: 32) }
    var name: String? { Sanitize.deviceName(values["device_name"] ?? values["router_name"]) }
    var wlanOn: Bool? { values["use_wlan"].map { $0 == "1" } }
    var wlan5On: Bool? { values["use_wlan_5ghz"].map { $0 == "1" } }
    var ssid: String? { Sanitize.deviceName(values["wlan_ssid"]) }
}

enum SpeedportClient {
    static let key = "cdc0cac1280b516e674f0057e4929bca84447cca8425007e33a88a5cf598a190"

    static func status(host: String = "speedport.ip") async -> SpeedportStatus? {
        guard let res = await Probes.fetchText("http://\(host)/data/Status.json", maxBytes: 400_000) else { return nil }
        let raw = res.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var jsonText: String?
        if raw.hasPrefix("[") || raw.hasPrefix("{") {
            jsonText = raw.replacingOccurrences(of: "'", with: "\"")
        } else if let plain = decrypt(hex: raw) {
            jsonText = plain
        }
        guard var text = jsonText else { return nil }
        // Speedports liefern teils ein Komma zu viel vor "]"
        text = text.replacingOccurrences(of: #"\}\s*,\s*\]"#, with: "}]", options: .regularExpression)
        guard let data = text.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        var dict: [String: String] = [:]
        for item in arr.prefix(400) {
            guard let id = item["varid"] as? String, id.count <= 64 else { continue }
            if let v = item["varvalue"] as? String {
                dict[id] = String(v.prefix(200))
            } else if let v = item["varvalue"] {
                dict[id] = String("\(v)".prefix(200))
            }
        }
        return dict.isEmpty ? nil : SpeedportStatus(values: dict)
    }

    /// AES-CCM entschlüsseln (Zählermodus; der 16-Byte-Prüfwert am Ende wird ignoriert)
    static func decrypt(hex: String) -> String? {
        guard let blob = Data(hexString: hex), blob.count > 16, let keyData = Data(hexString: key) else { return nil }
        let cipher = blob.prefix(blob.count - 16)
        let nonce = Array(keyData.prefix(8))
        let l = 15 - nonce.count
        var out = [UInt8]()
        out.reserveCapacity(cipher.count)
        let bytes = Array(cipher)
        var counter: UInt64 = 1
        var i = 0
        while i < bytes.count {
            var block = [UInt8](repeating: 0, count: 16)
            block[0] = UInt8(l - 1)
            for j in 0..<nonce.count { block[1 + j] = nonce[j] }
            var c = counter
            for j in stride(from: 15, through: 16 - l, by: -1) {
                block[j] = UInt8(c & 0xff)
                c >>= 8
            }
            guard let ks = aesBlock(Array(keyData), block) else { return nil }
            let end = min(i + 16, bytes.count)
            for k in i..<end { out.append(bytes[k] ^ ks[k - i]) }
            i += 16
            counter += 1
        }
        return String(bytes: out, encoding: .utf8)
    }

    private static func aesBlock(_ key: [UInt8], _ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: 16 + kCCBlockSizeAES128)
        var moved = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                             key, key.count, nil, input, input.count, &output, output.count, &moved)
        guard status == Int32(kCCSuccess), moved >= 16 else { return nil }
        return Array(output.prefix(16))
    }
}

extension Data {
    init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        func val(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: return c - 48
            case 65...70: return c - 55
            case 97...102: return c - 87
            default: return nil
            }
        }
        var i = 0
        while i < chars.count {
            guard let hi = val(chars[i]), let lo = val(chars[i + 1]) else { return nil }
            bytes.append(hi << 4 | lo)
            i += 2
        }
        self.init(bytes)
    }
}
