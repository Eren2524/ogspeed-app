import Foundation
import Network

/// Sorgt dafür, dass eine Fortsetzung genau einmal aufgerufen wird.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ f: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        f()
    }
}

final class TimeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var t = DispatchTime.now()
    func reset() { lock.withLock { t = DispatchTime.now() } }
    var elapsedMs: Double {
        let start = lock.withLock { t }
        return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}

enum Probes {

    // MARK: TCP-"Ping" (Verbindungsaufbau = eine Hin- und Rückreise)

    /// Misst die Zeit für den TCP-Handshake. Der erste Aufruf wärmt die
    /// Verbindung auf, gemessen wird der zweite Wert.
    static func tcpPing(host: String, port: UInt16 = 443, timeout: Double = 3) async -> Double? {
        let target = await DoH.address(for: host) ?? host
        _ = await tcpConnect(host: target, port: port, timeout: timeout, resolve: false)
        return await tcpConnect(host: target, port: port, timeout: timeout, resolve: false)
    }

    /// `resolve: true` löst den Namen vorher verschlüsselt auf, damit im WLAN
    /// kein Klartext-Name sichtbar wird.
    static func tcpConnect(host: String, port: UInt16, timeout: Double, resolve: Bool = true) async -> Double? {
        var target = host
        if resolve, !DoH.isIPv4(host), !host.contains(":") {
            target = await DoH.address(for: host) ?? host
        }
        return await connect(target, port: port, timeout: timeout)
    }

    private static func connect(_ host: String, port: UInt16, timeout: Double) async -> Double? {
        await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            guard let p = NWEndpoint.Port(rawValue: port) else { cont.resume(returning: nil); return }
            let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
            let once = Once()
            let clock = TimeBox()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ms = clock.elapsedMs
                    once.run { cont.resume(returning: ms) }
                    conn.cancel()
                case .failed, .waiting:
                    once.run { cont.resume(returning: nil) }
                    conn.cancel()
                default:
                    break
                }
            }
            conn.start(queue: DispatchQueue.global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.run { cont.resume(returning: nil) }
                conn.cancel()
            }
        }
    }

    // MARK: DNS über UDP an einen bestimmten Server

    static func dnsQuery(server: String, name: String, timeout: Double = 2) async -> Double? {
        let packet = buildQuery(name)
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let conn = NWConnection(host: NWEndpoint.Host(server), port: 53, using: .udp)
            let once = Once()
            let clock = TimeBox()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    clock.reset()
                    conn.send(content: packet, completion: .contentProcessed { _ in })
                    conn.receiveMessage { data, _, _, _ in
                        let ms = clock.elapsedMs
                        if let d = data, d.count >= 12, d[d.startIndex] == packet[0], d[d.startIndex + 1] == packet[1] {
                            once.run { cont.resume(returning: ms) }
                        } else {
                            once.run { cont.resume(returning: nil) }
                        }
                        conn.cancel()
                    }
                case .failed:
                    once.run { cont.resume(returning: nil) }
                    conn.cancel()
                default:
                    break
                }
            }
            conn.start(queue: DispatchQueue.global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.run { cont.resume(returning: nil) }
                conn.cancel()
            }
        }
    }

    static func buildQuery(_ name: String) -> Data {
        var d = Data()
        d.append(UInt8.random(in: 0...255))
        d.append(UInt8.random(in: 0...255))
        d.append(contentsOf: [0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8.prefix(63))
            d.append(UInt8(bytes.count))
            d.append(contentsOf: bytes)
        }
        d.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x01])
        return d
    }

    // MARK: HTTP mit kurzer Zeitgrenze (für die Router-Erkennung)

    static let quickSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2.5
        cfg.timeoutIntervalForResource = 4
        cfg.waitsForConnectivity = false
        cfg.urlCache = nil
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpShouldSetCookies = false
        cfg.httpAdditionalHeaders = ["User-Agent": "OGSpeed"]
        return URLSession(configuration: cfg, delegate: NoRedirect.shared, delegateQueue: nil)
    }()

    /// Ein Gerät im Heimnetz könnte per Weiterleitung versuchen, die Abfrage
    /// nach außen zu schicken. Das wird hier unterbunden.
    final class NoRedirect: NSObject, URLSessionTaskDelegate {
        static let shared = NoRedirect()
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func fetchText(_ urlString: String, maxBytes: Int = 60_000) async -> (text: String, server: String?)? {
        guard let url = URL(string: urlString) else { return nil }
        var r = URLRequest(url: url)
        r.timeoutInterval = 2.5
        guard let res = try? await quickSession.data(for: r) else { return nil }
        if let http = res.1 as? HTTPURLResponse, http.expectedContentLength > 4_000_000 { return nil }
        guard res.0.count <= 4_000_000 else { return nil }
        let data = res.0.prefix(maxBytes)
        let text = String(decoding: data, as: UTF8.self)
        let server = (res.1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "Server")
        return (text, server)
    }

    static func fetchJSON(_ urlString: String) async -> [String: Any]? {
        guard let url = URL(string: urlString) else { return nil }
        var r = URLRequest(url: url)
        r.timeoutInterval = 4
        guard let res = try? await quickSession.data(for: r) else { return nil }
        return (try? JSONSerialization.jsonObject(with: res.0)) as? [String: Any]
    }
}
