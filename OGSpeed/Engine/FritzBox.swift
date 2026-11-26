import Foundation

/// Liest über die offizielle TR-064-Schnittstelle der FRITZ!Box die echte
/// WLAN-Signalstärke des iPhones aus (iOS selbst gibt sie Apps nicht frei).
/// Voraussetzung in der FRITZ!Box: Heimnetz › Netzwerk › Netzwerkeinstellungen ›
/// „Zugriff für Anwendungen zulassen“ (TR-064) eingeschaltet.
struct FritzWLAN: Equatable {
    var signal: Int          // 0–100 %
    var linkMbps: Int?       // Verbindungsgeschwindigkeit iPhone ↔ Router
    var ssid: String?
    var channel: Int?
    var band: String?
    var standard: String?
}

struct FritzLine: Equatable {
    var downMbps: Double
    var upMbps: Double
    var type: String?
}

struct FritzDevice: Equatable {
    var model: String
    var firmware: String
}

enum FritzError: LocalizedError {
    case unreachable, auth, notInWLAN, notFound, fault(String)
    case insecureBlocked, certChanged

    var errorDescription: String? {
        switch self {
        case .unreachable: return "FRITZ!Box nicht erreichbar. Bist du in deinem WLAN und ist „Zugriff für Anwendungen zulassen“ an?"
        case .auth: return "Benutzername oder Kennwort der FRITZ!Box stimmt nicht."
        case .notInWLAN: return "Das iPhone ist gerade nicht im WLAN."
        case .notFound: return "Die FRITZ!Box kennt dieses iPhone im WLAN nicht."
        case .fault(let s): return "FRITZ!Box meldet: \(s)"
        case .insecureBlocked:
            return "Die FRITZ!Box ist nur unverschlüsselt erreichbar. OGSpeed schickt dein Kennwort nicht über eine unverschlüsselte Verbindung. Aktiviere in der FRITZ!Box unter Heimnetz › Netzwerk › Netzwerkeinstellungen den Zugriff für Anwendungen (dort auch über HTTPS)."
        case .certChanged:
            return "Das Sicherheitszertifikat deiner FRITZ!Box hat sich geändert. Das passiert nach einem Werksreset – kann aber auch bedeuten, dass sich jemand im WLAN als deine FRITZ!Box ausgibt. Prüfe die Verbindung in den Einstellungen."
        }
    }
}

final class FritzClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let host: String
    private let user: String
    private let password: String
    private var session: URLSession!
    private var mac: String?
    private var wlanIndex: Int?
    private var infoCache: [Int: (Date, [String: String])] = [:]
    private let lock = NSLock()
    /// nil = noch nicht geprüft, sonst "https://host:49443" bzw. "http://host:49000"
    private var base: String?
    private(set) var usedInsecureTransport = false
    private var certMismatch = false

    init(host: String, user: String, password: String) {
        self.host = host
        self.user = user
        self.password = password
        super.init()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cached: FritzClient?

    /// Gemeinsamer Client (eine URLSession), wird neu gebaut, wenn sich die Zugangsdaten ändern.
    static func fromPrefs() -> FritzClient? {
        guard Prefs.fritzEnabled else { return nil }
        let host = Prefs.fritzHost, user = Prefs.fritzUser, pw = Keychain.get()
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let c = cached, c.host == host, c.user == user, c.password == pw { return c }
        cached?.session.invalidateAndCancel()
        let c = FritzClient(host: host, user: user, password: pw)
        cached = c
        return c
    }

    /// Für Einmal-Clients (Einrichtung): Sitzung schließen, damit nichts im Speicher bleibt.
    func close() { session.finishTasksAndInvalidate() }

    // MARK: SOAP

    /// TR-064 läuft verschlüsselt auf Port 49443 und unverschlüsselt auf 49000.
    /// OGSpeed nimmt immer zuerst die verschlüsselte Verbindung.
    func baseURL() async throws -> String {
        if let b = lock.withLock({ base }) { return b }
        let secure = "https://\(host):49443"
        if await reachable(secure) {
            lock.withLock { base = secure; usedInsecureTransport = false }
            return secure
        }
        if lock.withLock({ certMismatch }) { throw FritzError.certChanged }
        guard Privacy.fritzAllowHTTP else { throw FritzError.insecureBlocked }
        let plain = "http://\(host):49000"
        lock.withLock { base = plain; usedInsecureTransport = true }
        return plain
    }

    private func reachable(_ base: String) async -> Bool {
        guard let url = URL(string: base + "/tr64desc.xml") else { return false }
        var r = URLRequest(url: url)
        r.timeoutInterval = 4
        guard let res = try? await session.data(for: r) else { return false }
        return ((res.1 as? HTTPURLResponse)?.statusCode ?? 0) == 200
    }

    func soap(service: String, control: String, action: String, args: [(String, String)] = []) async throws -> [String: String] {
        let base = try await baseURL()
        guard let url = URL(string: base + control) else { throw FritzError.unreachable }
        let argXML = args.map { "<\($0.0)>\(escape($0.1))</\($0.0)>" }.joined()
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\(action) xmlns:u="\(service)">\(argXML)</u:\(action)></s:Body></s:Envelope>
        """
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        r.setValue("\(service)#\(action)", forHTTPHeaderField: "SOAPAction")
        r.httpBody = Data(body.utf8)

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: r)
        } catch let e as URLError where e.code == .userCancelledAuthentication {
            throw FritzError.auth
        } catch {
            throw FritzError.unreachable
        }
        let resp = result.1
        guard result.0.count <= 1_000_000 else { throw FritzError.fault("Unerwartet große Antwort") }
        let data = result.0
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        if code == 401 { throw FritzError.auth }
        if code != 200 {
            let desc = Self.tag("errorDescription", in: text) ?? "Fehler \(code)"
            throw FritzError.fault(desc)
        }
        return Self.values(in: text)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        let m = space.authenticationMethod

        // Selbstsigniertes Zertifikat der FRITZ!Box: nur der beim ersten Mal
        // gemerkte Fingerabdruck wird akzeptiert.
        if m == NSURLAuthenticationMethodServerTrust {
            guard space.host.lowercased() == host.lowercased(), let trust = space.serverTrust else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            if CertPin.accept(trust: trust, host: host) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                lock.withLock { certMismatch = true }
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }

        if m == NSURLAuthenticationMethodHTTPDigest || m == NSURLAuthenticationMethodHTTPBasic {
            // Basic schickt das Kennwort praktisch im Klartext – über eine
            // unverschlüsselte Verbindung wird es niemals gesendet.
            let encrypted = space.protocol?.lowercased() == "https"
            if m == NSURLAuthenticationMethodHTTPBasic && !encrypted {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            guard challenge.previousFailureCount == 0 else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(user: user, password: password, persistence: .none))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func values(in xml: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let re = try? NSRegularExpression(pattern: "<(New[A-Za-z0-9_\\-]+)>([^<]*)</\\1>") else { return out }
        let ns = xml as NSString
        for m in re.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let k = ns.substring(with: m.range(at: 1))
            let v = ns.substring(with: m.range(at: 2))
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
            out[k] = v
        }
        return out
    }

    static func tag(_ name: String, in xml: String) -> String? {
        guard let a = xml.range(of: "<\(name)>"), let b = xml.range(of: "</\(name)>", range: a.upperBound..<xml.endIndex) else { return nil }
        return String(xml[a.upperBound..<b.lowerBound])
    }

    private static func wlanService(_ i: Int) -> String { "urn:dslforum-org:service:WLANConfiguration:\(i)" }

    // MARK: Abfragen

    func deviceInfo() async throws -> FritzDevice {
        let v = try await soap(service: "urn:dslforum-org:service:DeviceInfo:1", control: "/upnp/control/deviceinfo", action: "GetInfo")
        return FritzDevice(model: v["NewModelName"] ?? "FRITZ!Box", firmware: v["NewSoftwareVersion"] ?? "")
    }

    func line() async throws -> FritzLine {
        let v = try await soap(service: "urn:dslforum-org:service:WANCommonInterfaceConfig:1",
                               control: "/upnp/control/wancommonifconfig1", action: "GetCommonLinkProperties")
        let down = Double(v["NewLayer1DownstreamMaxBitRate"] ?? "") ?? 0
        let up = Double(v["NewLayer1UpstreamMaxBitRate"] ?? "") ?? 0
        return FritzLine(downMbps: down / 1_000_000, upMbps: up / 1_000_000, type: v["NewWANAccessType"])
    }

    private func myMAC(ip: String) async throws -> String {
        if let m = lock.withLock({ mac }) { return m }
        let v = try await soap(service: "urn:dslforum-org:service:Hosts:1", control: "/upnp/control/hosts",
                               action: "X_AVM-DE_GetSpecificHostEntryByIP", args: [("NewIPAddress", ip)])
        guard let m = v["NewMACAddress"], !m.isEmpty else { throw FritzError.notFound }
        lock.withLock { mac = m }
        return m
    }

    private func info(_ i: Int) async -> [String: String] {
        if let c = lock.withLock({ infoCache[i] }), Date().timeIntervalSince(c.0) < 30 { return c.1 }
        let v = (try? await soap(service: Self.wlanService(i), control: "/upnp/control/wlanconfig\(i)", action: "GetInfo")) ?? [:]
        lock.withLock { infoCache[i] = (Date(), v) }
        return v
    }

    /// Signalstärke & Co. für dieses iPhone
    func wlanStatus() async throws -> FritzWLAN {
        guard let ip = NetworkMonitor.localWiFiIPv4() else { throw FritzError.notInWLAN }
        var lastError: Error = FritzError.notFound

        if let macAddr = try? await myMAC(ip: ip) {
            let first = lock.withLock { wlanIndex }
            let order = ([first].compactMap { $0 } + [1, 2, 3, 4]).reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }
            for i in order {
                do {
                    let v = try await soap(service: Self.wlanService(i), control: "/upnp/control/wlanconfig\(i)",
                                           action: "GetSpecificAssociatedDeviceInfo",
                                           args: [("NewAssociatedDeviceMACAddress", macAddr)])
                    if v["NewX_AVM-DE_SignalStrength"] == nil && v["NewAssociatedDeviceIPAddress"] == nil { continue }
                    lock.withLock { wlanIndex = i }
                    return await build(v, index: i)
                } catch FritzError.auth {
                    throw FritzError.auth
                } catch {
                    lastError = error
                }
            }
        }

        // Plan B: alle verbundenen WLAN-Geräte durchgehen und über die IP finden
        for i in 1...4 {
            guard let t = try? await soap(service: Self.wlanService(i), control: "/upnp/control/wlanconfig\(i)", action: "GetTotalAssociations"),
                  let n = Int(t["NewTotalAssociations"] ?? "") else { continue }
            for idx in 0..<min(n, 64) {
                guard let v = try? await soap(service: Self.wlanService(i), control: "/upnp/control/wlanconfig\(i)",
                                              action: "GetGenericAssociatedDeviceInfo",
                                              args: [("NewAssociatedDeviceIndex", "\(idx)")]) else { continue }
                if v["NewAssociatedDeviceIPAddress"] == ip {
                    if let m = v["NewAssociatedDeviceMACAddress"] { lock.withLock { mac = m; wlanIndex = i } }
                    return await build(v, index: i)
                }
            }
        }
        throw lastError
    }

    private func build(_ v: [String: String], index: Int) async -> FritzWLAN {
        let raw = Int(v["NewX_AVM-DE_SignalStrength"] ?? "") ?? 0
        let percent = raw < 0 ? max(0, min(100, 2 * (raw + 100))) : max(0, min(100, raw))
        let inf = await info(index)
        let channel = Int(inf["NewChannel"] ?? "")
        var band = inf["NewX_AVM-DE_FrequencyBand"].flatMap { b -> String? in
            if b.contains("6") { return "6 GHz" }
            if b.contains("5") { return "5 GHz" }
            if b.contains("2") { return "2,4 GHz" }
            return nil
        }
        if band == nil, let c = channel { band = c <= 14 ? "2,4 GHz" : "5 GHz" }
        return FritzWLAN(signal: percent,
                         linkMbps: Int(v["NewX_AVM-DE_Speed"] ?? ""),
                         ssid: inf["NewSSID"],
                         channel: channel,
                         band: band,
                         standard: inf["NewStandard"])
    }

    // MARK: Anschluss & Geräte

    /// IPv4 der FRITZ!Box im Internet (leer bzw. 0.0.0.0 bei DS-Lite)
    func externalIPv4() async throws -> String {
        for (svc, ctl) in [("urn:dslforum-org:service:WANIPConnection:1", "/upnp/control/wanipconnection1"),
                           ("urn:dslforum-org:service:WANPPPConnection:1", "/upnp/control/wanpppconn1")] {
            if let v = try? await soap(service: svc, control: ctl, action: "GetExternalIPAddress"),
               let ip = v["NewExternalIPAddress"] {
                return ip
            }
        }
        throw FritzError.notFound
    }

    /// Alle Geräte, die die FRITZ!Box kennt
    func hostList() async throws -> [FritzHost] {
        let v = try await soap(service: "urn:dslforum-org:service:Hosts:1", control: "/upnp/control/hosts",
                               action: "X_AVM-DE_GetHostListPath")
        let base = try await baseURL()
        guard let path = v["NewX_AVM-DE_HostListPath"], let url = URL(string: base + path) else {
            throw FritzError.notFound
        }
        let res = try await session.data(from: url)
        guard res.0.count <= 2_000_000 else { throw FritzError.fault("Unerwartet große Geräteliste") }
        let xml = String(decoding: res.0, as: UTF8.self)
        var hosts: [FritzHost] = []
        var rest = xml[...]
        while let a = rest.range(of: "<Item>"), let b = rest.range(of: "</Item>", range: a.upperBound..<rest.endIndex) {
            let item = String(rest[a.upperBound..<b.lowerBound])
            let mac = Self.tag("MACAddress", in: item) ?? ""
            let name = Self.tag("HostName", in: item) ?? "Unbekannt"
            hosts.append(FritzHost(name: Sanitize.deviceName(name) ?? "Unbekannt",
                                   ip: Self.tag("IPAddress", in: item) ?? "",
                                   mac: mac,
                                   active: Self.tag("Active", in: item) == "1",
                                   interface: Self.tag("InterfaceType", in: item) ?? "",
                                   speedMbps: Int(Self.tag("X_AVM-DE_Speed", in: item) ?? ""),
                                   guest: Self.tag("X_AVM-DE_Guest", in: item) == "1"))
            rest = rest[b.upperBound...]
        }
        return hosts
    }
}

struct FritzHost: Identifiable, Hashable {
    var id: String { mac.isEmpty ? ip + name : mac }
    var name: String
    var ip: String
    var mac: String
    var active: Bool
    var interface: String
    var speedMbps: Int?
    var guest: Bool

    var isWLAN: Bool { interface.lowercased().contains("802.11") || interface.lowercased().contains("wlan") }
}
