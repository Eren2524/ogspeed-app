import Foundation

/// Kurzer Messpunkt (ca. 4 Sekunden) für Rundgang, Live-Suche und Wächter.
struct QuickSample: Codable, Hashable {
    var pingMs: Double?
    var downMbps: Double?
    var signal: Int?
    var linkMbps: Int?
    var band: String?

    /// 0–100: wie gut ist diese Stelle?
    var score: Double {
        // (Wert 0–100, Gewicht) – das echte Signal zählt am meisten
        var parts: [(Double, Double)] = []
        if let s = signal { parts.append((Double(s), 0.6)) }
        if let d = downMbps { parts.append((min(100, 34 * log10(1 + d)), 0.25)) }   // 300 Mbit/s ≈ 84
        if let p = pingMs { parts.append((max(0, min(100, 110 - p * 1.5)), 0.15)) }
        let w = parts.map(\.1).reduce(0, +)
        guard w > 0 else { return 0 }
        return max(0, min(100, parts.map { $0.0 * $0.1 }.reduce(0, +) / w))
    }

    var level: Level { score >= 75 ? .great : score >= 55 ? .good : score >= 35 ? .ok : .bad }
}

enum QuickProbe {
    static func measure(downloadSeconds: Double = 3) async -> QuickSample {
        let fritz = FritzClient.fromPrefs()
        let wlanTask = Task { () -> FritzWLAN? in try? await fritz?.wlanStatus() }
        let session = Cloudflare.makePingSession()
        _ = await Cloudflare.ping(session)
        var pings: [Double] = []
        for _ in 0..<5 {
            if let p = await Cloudflare.ping(session) { pings.append(p) }
        }
        var down: Double?
        if downloadSeconds > 0 {
            let probe = TransferProbe(kind: .download, streams: 4)
            probe.start()
            try? await Task.sleep(for: .milliseconds(700))
            let b0 = probe.bytes
            let clock = ContinuousClock()
            let t0 = clock.now
            try? await Task.sleep(for: .seconds(downloadSeconds))
            let b1 = probe.bytes
            let dt = (clock.now - t0).seconds
            probe.stop()
            down = Double(b1 - b0) * 8 / 1_000_000 / max(dt, 0.1)
        }
        let w = await wlanTask.value
        return QuickSample(pingMs: pings.isEmpty ? nil : pings.sorted()[pings.count / 2],
                           downMbps: down, signal: w?.signal, linkMbps: w?.linkMbps, band: w?.band)
    }
}
