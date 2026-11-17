import AppIntents

struct StartSpeedTestIntent: AppIntent {
    static var title: LocalizedStringResource = "Speedtest starten"
    static var description = IntentDescription("Öffnet OGSpeed und startet sofort einen Speedtest.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedStore.pendingStart = true
        return .result()
    }
}

struct LastResultIntent: AppIntent {
    static var title: LocalizedStringResource = "Letztes Speedtest-Ergebnis"
    static var description = IntentDescription("Sagt dir, wie schnell dein letzter Test war.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let r = SharedStore.lastResult else {
            return .result(dialog: "Du hast noch keinen Speedtest gemacht.")
        }
        let o = Rating.overall(r)
        let text = "\(o.title): \(Fmt.mbps(r.downMbps)) Megabit runter, \(Fmt.mbps(r.upMbps)) hoch, Ping \(Fmt.ms(r.pingMs)) Millisekunden."
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct OGSpeedShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartSpeedTestIntent(),
                    phrases: ["Teste mein Internet mit \(.applicationName)",
                              "\(.applicationName) Speedtest",
                              "Starte \(.applicationName)"],
                    shortTitle: "Speedtest starten",
                    systemImageName: "speedometer")
        AppShortcut(intent: LastResultIntent(),
                    phrases: ["Wie schnell ist mein Internet laut \(.applicationName)",
                              "Letzter Test in \(.applicationName)"],
                    shortTitle: "Letztes Ergebnis",
                    systemImageName: "chart.bar.fill")
    }
}
