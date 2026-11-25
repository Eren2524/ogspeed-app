import Foundation
import Observation
import UIKit

enum TestPhase: Equatable {
    case idle, preparing, ping, download, upload, done
    case failed(String)

    var title: String {
        switch self {
        case .idle: return "Bereit"
        case .preparing: return "Verbinde mit Server …"
        case .ping: return "Reaktionszeit"
        case .download: return "Download"
        case .upload: return "Upload"
        case .done: return "Fertig"
        case .failed: return "Fehler"
        }
    }
}

@MainActor @Observable
final class SpeedTester {
    var phase: TestPhase = .idle
    var liveValue: Double = 0      // Mbit/s bzw. ms im Ping-Schritt
    var progress: Double = 0
    var pingMs: Double?
    var jitterMs: Double?
    var downMbps: Double?
    var upMbps: Double?
    var server: String?
    var result: SpeedResult?
    var trace: [Double] = []       // Verlauf der Live-Werte für die Mini-Kurve

    private var task: Task<Void, Never>?

    var isRunning: Bool {
        switch phase {
        case .preparing, .ping, .download, .upload: return true
        default: return false
        }
    }

    func start(network: NetworkMonitor, history: HistoryStore) {
        guard !isRunning else { return }
        task?.cancel()
        task = Task { await run(network: network, history: history) }
    }

    func cancel() {
        task?.cancel()
        phase = .idle
        liveValue = 0
    }

    func reset() {
        phase = .idle; liveValue = 0; progress = 0
        pingMs = nil; jitterMs = nil; downMbps = nil; upMbps = nil; result = nil; trace = []
    }

    // MARK: Ablauf

    private func run(network: NetworkMonitor, history: HistoryStore) async {
        reset()
        guard network.isConnected else { phase = .failed("Keine Internetverbindung."); return }
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.prepare()

        let kind = network.kind
        let cellular = kind == .cellular
        let saver = cellular && Prefs.dataSaver
        let downCap: Int64 = saver ? 120_000_000 : 3_000_000_000
        let upCap: Int64 = saver ? 40_000_000 : 1_000_000_000

        // FRITZ!Box parallel abfragen (Signal am Anfang)
        let fritz = kind == .wifi ? FritzClient.fromPrefs() : nil
        let fritzTask: Task<FritzWLAN?, Never>? = fritz.map { f in Task { try? await f.wlanStatus() } }

        phase = .preparing
        let pingSession = Cloudflare.makePingSession()
        async let dnsValue = Cloudflare.dnsTime()
        server = await Cloudflare.serverLocation(pingSession)
        _ = await Cloudflare.ping(pingSession) // Verbindung aufwärmen
        if Task.isCancelled { return }

        // 1) Ping & Jitter
        phase = .ping
        haptic.impactOccurred()
        var samples: [Double] = []
        var failures = 0
        let count = 20
        for i in 0..<count {
            if Task.isCancelled { return }
            if let p = await Cloudflare.ping(pingSession) {
                samples.append(p)
                liveValue = p
                trace.append(p)
            } else {
                failures += 1
            }
            progress = Double(i + 1) / Double(count)
            try? await Task.sleep(for: .milliseconds(60))
        }
        guard !samples.isEmpty else {
            phase = .failed("Der Testserver antwortet nicht. Prüf deine Verbindung.")
            return
        }
        let ping = median(samples)
        let jitter = jitterOf(samples)
        let spikes = samples.filter { $0 > max(ping * 3, ping + 50) }.count
        pingMs = ping
        jitterMs = jitter

        // 2) Download
        phase = .download
        haptic.impactOccurred()
        trace = []
        let down = await transfer(.download, duration: saver ? 7 : 10, cap: downCap, streams: 6)
        if Task.isCancelled { return }
        downMbps = down.mbps

        // 3) Upload
        phase = .upload
        haptic.impactOccurred()
        trace = []
        let up = await transfer(.upload, duration: saver ? 6 : 8, cap: upCap, streams: 4)
        if Task.isCancelled { return }
        upMbps = up.mbps

        let loaded = down.loaded + up.loaded
        let loadedPing = loaded.isEmpty ? ping : max(median(down.loaded.isEmpty ? [ping] : down.loaded),
                                                     median(up.loaded.isEmpty ? [ping] : up.loaded))
        let loadedFails = down.loadedFailures + up.loadedFailures
        let totalProbes = Double(count + loaded.count + loadedFails)
        let dropout = Double(failures + spikes + loadedFails) / max(totalProbes, 1) * 100

        let wlan = await fritzTask?.value
        var r = SpeedResult()
        r.connection = kind
        r.radio = cellular ? NetworkMonitor.radioTechnology() : nil
        if let id = NetDetector.shared.identity {
            r.provider = id.provider == .other ? id.providerName : id.provider.label
            r.router = id.router?.displayName
        }
        r.networkName = wlan?.ssid
        r.band = wlan?.band
        r.downMbps = down.mbps
        r.upMbps = up.mbps
        r.pingMs = ping
        r.jitterMs = jitter
        r.loadedPingMs = loadedPing
        r.dropoutPercent = dropout
        r.dnsMs = await dnsValue
        r.server = server
        r.dataUsedMB = Double(down.bytes + up.bytes) / 1_000_000
        r.signalPercent = wlan?.signal
        r.linkMbps = wlan?.linkMbps

        result = r
        liveValue = down.mbps
        progress = 1
        phase = .done
        history.add(r)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private struct TransferResult {
        var mbps: Double
        var bytes: Int64
        var loaded: [Double]
        var loadedFailures: Int
    }

    private func transfer(_ kind: TransferProbe.Kind, duration: Double, cap: Int64, streams: Int) async -> TransferResult {
        let probe = TransferProbe(kind: kind, streams: streams)
        let pingSession = Cloudflare.makePingSession()
        _ = await Cloudflare.ping(pingSession)
        probe.start()

        // Ping unter Last parallel messen (zeigt "Bufferbloat")
        let pinger = Task.detached { () -> ([Double], Int) in
            var arr: [Double] = []
            var fails = 0
            try? await Task.sleep(for: .milliseconds(800))
            while !Task.isCancelled {
                if let p = await Cloudflare.ping(pingSession, timeout: 3) { arr.append(p) } else if !Task.isCancelled { fails += 1 }
                try? await Task.sleep(for: .milliseconds(300))
            }
            return (arr, fails)
        }

        let clock = ContinuousClock()
        let t0 = clock.now
        var samples: [(Double, Int64)] = [(0, 0)]
        var t = 0.0
        while true {
            try? await Task.sleep(for: .milliseconds(100))
            t = (clock.now - t0).seconds
            let b = probe.bytes
            samples.append((t, b))
            if let old = samples.last(where: { $0.0 <= t - 1.0 }) ?? samples.first, t - old.0 > 0.05 {
                let v = Double(b - old.1) * 8 / 1_000_000 / (t - old.0)
                liveValue = v
                if samples.count % 3 == 0 { trace.append(v) }
            }
            progress = min(t / duration, 1)
            if t >= duration || b >= cap || Task.isCancelled { break }
        }
        probe.stop()
        pinger.cancel()
        let (loaded, fails) = await pinger.value

        let warm = min(1.5, t * 0.25)
        let s0 = samples.first(where: { $0.0 >= warm }) ?? samples[0]
        let s1 = samples[samples.count - 1]
        let mbps = Double(s1.1 - s0.1) * 8 / 1_000_000 / max(s1.0 - s0.0, 0.1)
        return TransferResult(mbps: max(mbps, 0), bytes: s1.1, loaded: loaded, loadedFailures: fails)
    }

    // MARK: Statistik

    private func median(_ a: [Double]) -> Double {
        let s = a.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    private func jitterOf(_ a: [Double]) -> Double {
        guard a.count > 1 else { return 0 }
        var sum = 0.0
        for i in 1..<a.count { sum += abs(a[i] - a[i - 1]) }
        return sum / Double(a.count - 1)
    }
}
