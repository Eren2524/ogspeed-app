import Foundation

/// Messungen gegen das Speedtest-Netz von Cloudflare (kostenlos, ohne Anmeldung,
/// Server in Frankfurt, Düsseldorf, Hamburg, Berlin, München …).
enum Cloudflare {
    static let host = "https://speed.cloudflare.com"

    static func makePingSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpMaximumConnectionsPerHost = 1
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = 4
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }

    /// Ein HTTP-"Ping": Zeit bis zur Antwort minus Rechenzeit des Servers.
    static func ping(_ session: URLSession, timeout: TimeInterval = 2.5) async -> Double? {
        var r = URLRequest(url: URL(string: "\(host)/__down?bytes=0&r=\(UInt32.random(in: 0...UInt32.max))")!)
        r.timeoutInterval = timeout
        r.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let (_, resp) = try await session.data(for: r)
            var ms = (clock.now - start).milliseconds
            if let h = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Server-Timing"),
               let dur = serverDuration(h) {
                ms -= dur
            }
            return max(ms, 0.3)
        } catch {
            return nil
        }
    }

    static func serverDuration(_ header: String) -> Double? {
        guard let range = header.range(of: #"dur=([0-9.]+)"#, options: .regularExpression) else { return nil }
        return Double(header[range].dropFirst(4))
    }

    /// Server-Standort (z. B. "FRA" → Frankfurt)
    static func serverLocation(_ session: URLSession) async -> String? {
        guard let url = URL(string: "\(host)/cdn-cgi/trace"),
              let res = try? await session.data(from: url),
              let text = String(data: res.0, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("colo=") {
            let code = String(line.dropFirst(5))
            return colos[code].map { "\($0) (\(code))" } ?? code
        }
        return nil
    }

    static let colos: [String: String] = [
        "FRA": "Frankfurt", "DUS": "Düsseldorf", "HAM": "Hamburg", "BER": "Berlin", "MUC": "München",
        "STR": "Stuttgart", "AMS": "Amsterdam", "BRU": "Brüssel", "CDG": "Paris", "LHR": "London",
        "VIE": "Wien", "ZRH": "Zürich", "PRG": "Prag", "WAW": "Warschau", "CPH": "Kopenhagen",
        "MAD": "Madrid", "MXP": "Mailand", "LUX": "Luxemburg"
    ]

    /// DNS-Antwortzeit: Auflösung eines zufälligen, nicht zwischengespeicherten Namens.
    static func dnsTime() async -> Double? {
        await Task.detached(priority: .userInitiated) { () -> Double? in
            let name = "og\(UInt32.random(in: 0...UInt32.max)).example.com"
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var res: UnsafeMutablePointer<addrinfo>?
            let clock = ContinuousClock()
            let start = clock.now
            let rc = getaddrinfo(name, nil, &hints, &res)
            let ms = (clock.now - start).milliseconds
            if res != nil { freeaddrinfo(res) }
            // NXDOMAIN (EAI_NONAME) ist hier die erwartete, gültige Antwort.
            if rc == 0 || rc == EAI_NONAME { return ms }
            return nil
        }.value
    }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
    var seconds: Double { milliseconds / 1000 }
}

/// Zählt laufend die übertragenen Bytes mehrerer paralleler Verbindungen.
final class TransferProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Kind { case download, upload }

    private let kind: Kind
    private let streams: Int
    private let lock = NSLock()
    private var total: Int64 = 0
    private var active = false
    private var errors = 0
    private var session: URLSession!
    private let body: Data

    init(kind: Kind, streams: Int) {
        self.kind = kind
        self.streams = streams
        if kind == .upload {
            var d = Data(count: 4_000_000)
            d.withUnsafeMutableBytes { buf in
                if let base = buf.baseAddress { arc4random_buf(base, buf.count) }
            }
            body = d
        } else {
            body = Data()
        }
        super.init()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpMaximumConnectionsPerHost = streams
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    var bytes: Int64 { lock.withLock { total } }
    var errorCount: Int { lock.withLock { errors } }

    func start() {
        lock.withLock { active = true }
        for _ in 0..<streams { launch() }
    }

    func stop() {
        lock.lock()
        active = false
        session.invalidateAndCancel()
        lock.unlock()
    }

    private func launch() {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        switch kind {
        case .download:
            var r = URLRequest(url: URL(string: "\(Cloudflare.host)/__down?bytes=50000000&r=\(UInt32.random(in: 0...UInt32.max))")!)
            r.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            session.dataTask(with: r).resume()
        case .upload:
            var r = URLRequest(url: URL(string: "\(Cloudflare.host)/__up?r=\(UInt32.random(in: 0...UInt32.max))")!)
            r.httpMethod = "POST"
            r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            session.uploadTask(with: r, from: body).resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard kind == .download else { return }
        lock.withLock { total += Int64(data.count) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard kind == .upload else { return }
        lock.withLock { total += bytesSent }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil {
            lock.withLock { errors += 1 }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.launch() }
        } else {
            launch()
        }
    }
}
