import SwiftUI

@main
struct OGSpeedApp: App {
    @State private var tester = SpeedTester()
    @State private var network = NetworkMonitor()
    @State private var history = HistoryStore()
    @State private var rooms = RoomStore()
    @State private var tab = 0
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Watchdog.register()
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                TestView().tag(0).tabItem { Label("Test", systemImage: "speedometer") }
                NetzView().tag(4).tabItem { Label("Netz", systemImage: "network") }
                WLANView().tag(1).tabItem { Label("WLAN", systemImage: "wifi") }
                HistoryView().tag(2).tabItem { Label("Verlauf", systemImage: "chart.xyaxis.line") }
                MoreView().tag(3).tabItem { Label("Mehr", systemImage: "square.grid.2x2") }
            }
            .tint(Neon.cyan)
            .preferredColorScheme(.dark)
            .environment(tester)
            .environment(network)
            .environment(history)
            .environment(rooms)
            .onOpenURL { url in
                if url.host == "test" { startFromShortcut() }
                if url.host == "wlan" { tab = 1 }
                if url.host == "netz" { tab = 4 }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    if SharedStore.pendingStart { startFromShortcut() }
                    Watchdog.shared.startForeground()
                case .background:
                    Watchdog.shared.stopForeground()
                    Watchdog.schedule()
                default: break
                }
            }
        }
    }

    private func startFromShortcut() {
        SharedStore.pendingStart = false
        tab = 0
        Task {
            try? await Task.sleep(for: .milliseconds(600))   // Netzstatus erst einlesen lassen
            tester.start(network: network, history: history)
        }
    }
}
