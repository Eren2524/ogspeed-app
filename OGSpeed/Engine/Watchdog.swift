import Foundation
import BackgroundTasks
import UserNotifications
import Observation

/// Ein festgehaltener Ausfall oder Einbruch
struct Outage: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date?
    var reason: String
    var connection: ConnectionKind
}

/// Störungs-Wächter: prüft regelmäßig im Hintergrund (iOS entscheidet, wann genau –
/// meist alle 15–60 Minuten) und solange die App offen ist jede Minute.
@MainActor @Observable
final class Watchdog {
    static let taskID = "com.eren2524.ogspeed.watch"
    static let shared = Watchdog()

    var outages: [Outage] = []
    var lastCheck: Date?
    var lastOK: Bool = true
    private var foregroundTask: Task<Void, Never>?

    private let key = "outages"

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let list = try? JSONDecoder.iso.decode([Outage].self, from: d) {
            outages = list
        }
    }

    private func save() {
        if let d = try? JSONEncoder.iso.encode(Array(outages.prefix(300))) { UserDefaults.standard.set(d, forKey: key) }
    }

    // MARK: Registrierung

    nonisolated static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            schedule()
            let work = Task { @MainActor in
                await Watchdog.shared.check(fromBackground: true)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    nonisolated static func schedule() {
        guard Prefs.watchEnabled else { return }
        let req = BGAppRefreshTaskRequest(identifier: taskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func requestNotifications() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func setEnabled(_ on: Bool) {
        if on {
            Self.schedule()
            startForeground()
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
            foregroundTask?.cancel()
        }
    }

    func startForeground() {
        foregroundTask?.cancel()
        guard Prefs.watchEnabled else { return }
        foregroundTask = Task {
            while !Task.isCancelled {
                await check(fromBackground: false)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopForeground() { foregroundTask?.cancel() }

    // MARK: Prüfung

    func check(fromBackground: Bool) async {
        let sample = await QuickProbe.measure(downloadSeconds: 2)
        lastCheck = Date()
        let minMbps = Prefs.watchMinMbps
        var problem: String?
        if sample.pingMs == nil { problem = "Kein Internet" }
        else if let d = sample.downMbps, d < minMbps { problem = "Nur \(Fmt.mbps(d)) Mbit/s (Grenze \(Fmt.mbps(minMbps)))" }
        else if let p = sample.pingMs, p > 300 { problem = "Sehr hoher Ping (\(Fmt.ms(p)) ms)" }

        let kind: ConnectionKind = NetworkMonitor.localWiFiIPv4() != nil ? .wifi : .cellular
        if let problem {
            if lastOK || outages.first?.end != nil || outages.isEmpty {
                outages.insert(Outage(start: Date(), end: nil, reason: problem, connection: kind), at: 0)
                save()
                notify(title: "Internet gestört", body: problem)
            }
            lastOK = false
        } else {
            if !lastOK, var o = outages.first, o.end == nil {
                o.end = Date()
                outages[0] = o
                save()
                let mins = Int(o.end!.timeIntervalSince(o.start) / 60)
                notify(title: "Internet wieder da", body: "Die Störung hat ca. \(max(mins, 1)) Min gedauert.")
            }
            lastOK = true
        }
    }

    func clear() { outages = []; save() }

    private func notify(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
