import SwiftUI
import AudioToolbox

@MainActor @Observable
final class WLANLive {
    var wlan: FritzWLAN?
    var error: String?
    var pingMs: Double?
    var history: [Int] = []
    var running = false
    private var task: Task<Void, Never>?

    func start(fast: Bool) {
        task?.cancel()
        running = true
        task = Task {
            let session = Cloudflare.makePingSession()
            while !Task.isCancelled {
                if let client = FritzClient.fromPrefs() {
                    do {
                        let w = try await client.wlanStatus()
                        wlan = w
                        error = nil
                        history.append(w.signal)
                        if history.count > 60 { history.removeFirst(history.count - 60) }
                    } catch {
                        self.error = error.localizedDescription
                    }
                } else {
                    error = nil
                }
                pingMs = await Cloudflare.ping(session)
                try? await Task.sleep(for: .milliseconds(fast ? 1200 : 4000))
            }
        }
    }

    func stop() { task?.cancel(); running = false }

    /// Trend über die letzten Messungen
    var trend: Int {
        guard history.count >= 4 else { return 0 }
        let recent = history.suffix(2).reduce(0, +) / 2
        let before = history.dropLast(2).suffix(3).reduce(0, +) / 3
        return recent - before
    }
}

struct WLANView: View {
    @Environment(NetworkMonitor.self) private var network
    @Environment(RoomStore.self) private var rooms
    @State private var live = WLANLive()
    @State private var searching = false
    @State private var newRoom = false
    @State private var line: FritzLine?
    @AppStorage(K.fritzEnabled) private var fritzEnabled = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if network.kind != .wifi {
                        Label("Du bist gerade nicht im WLAN. Verbinde dich mit deinem WLAN, um es zu analysieren.", systemImage: "wifi.slash")
                            .font(.subheadline).foregroundStyle(Neon.yellow)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glass()
                    }

                    if !fritzEnabled {
                        fritzPrompt
                    } else {
                        signalCard
                    }

                    Button { searching = true } label: {
                        Label("Beste Stelle live suchen", systemImage: "scope")
                    }
                    .buttonStyle(NeonButtonStyle())

                    roomsSection
                    tipsCard
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(NeonBackground())
            .navigationTitle("WLAN")
            .navigationDestination(for: RoomMap.ID.self) { id in RoomMapView(roomID: id) }
            .fullScreenCover(isPresented: $searching) { LiveSearchView() }
            .sheet(isPresented: $newRoom) { NewRoomSheet() }
            .onAppear { live.start(fast: false) }
            .onDisappear { live.stop() }
            .task(id: fritzEnabled) {
                if fritzEnabled { line = try? await FritzClient.fromPrefs()?.line() }
            }
        }
    }

    private var fritzPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("FRITZ!Box verbinden", systemImage: "wifi.router.fill").font(.headline)
            Text("iOS verrät Apps die WLAN-Stärke nicht – deine FRITZ!Box schon. Verbinde sie einmal, dann siehst du hier das echte Signal, das Funkband und die Verbindungsgeschwindigkeit.")
                .font(.subheadline).foregroundStyle(.secondary)
            NavigationLink { FritzSetupView() } label: {
                Text("Jetzt einrichten").frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle())
        }
        .glass()
    }

    private var signalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(live.wlan?.ssid ?? "Dein WLAN", systemImage: "wifi").font(.headline)
                Spacer()
                if let w = live.wlan { LevelPill(level: Rating.signalLevel(w.signal)) }
            }
            if let w = live.wlan {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(w.signal)").font(.system(size: 56, weight: .heavy, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(w.signal)))
                        .foregroundStyle(Rating.signalLevel(w.signal).color)
                    Text("% Signal").font(.headline).foregroundStyle(.secondary)
                }
                Text(signalText(w.signal)).font(.subheadline)
                SignalSparkline(values: live.history).frame(height: 44)
                HStack(spacing: 10) {
                    StatTile(title: "Funkband", value: w.band ?? "–", unit: "", icon: "dot.radiowaves.right")
                    StatTile(title: "Verbindung", value: w.linkMbps.map { "\($0)" } ?? "–", unit: "Mbit/s", icon: "link")
                    StatTile(title: "Kanal", value: w.channel.map { "\($0)" } ?? "–", unit: "", icon: "number")
                }
                if let band = w.band, band.hasPrefix("2,4"), w.signal >= 40 {
                    Label("Du hängst im langsamen 2,4-GHz-Band. Näher am Router springt das iPhone meist auf 5 GHz – das ist deutlich schneller.", systemImage: "lightbulb.fill")
                        .font(.caption).foregroundStyle(Neon.yellow)
                }
            } else if let e = live.error {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(Neon.yellow)
                NavigationLink("Einstellungen prüfen") { FritzSetupView() }.font(.subheadline.weight(.semibold))
            } else {
                ProgressView("Frage FRITZ!Box …").frame(maxWidth: .infinity)
            }
            if let line, line.downMbps > 0 {
                Divider().overlay(.white.opacity(0.1))
                Label("Leitung der FRITZ!Box: \(Fmt.mbps(line.downMbps)) ↓ / \(Fmt.mbps(line.upMbps)) ↑ Mbit/s", systemImage: "cable.connector")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .glass()
    }

    private func signalText(_ s: Int) -> String {
        switch s {
        case 70...: return "Ausgezeichnet – hier holst du alles aus deinem WLAN heraus."
        case 50..<70: return "Gut – für Streaming und Gaming reicht es locker."
        case 30..<50: return "Mittel – ein paar Meter näher zum Router bringt spürbar mehr."
        default: return "Schwach – hier lieber nicht zocken. Router umstellen oder Repeater/Mesh nutzen."
        }
    }

    private var roomsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Räume & Wärmekarten").font(.headline)
                Spacer()
                Button { newRoom = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .tint(Neon.cyan)
            }
            if rooms.rooms.isEmpty {
                Text("Mach ein Foto oder Panorama von deinem Raum. Dann tippst du darauf, wo du stehst, und OGSpeed misst. Am Ende siehst du farbig, wo das WLAN am besten ist.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { newRoom = true } label: { Label("Ersten Raum anlegen", systemImage: "camera.fill") }
                    .buttonStyle(GlassButtonStyle())
            } else {
                ForEach(rooms.rooms) { room in
                    NavigationLink(value: room.id) { RoomRow(room: room) }
                        .buttonStyle(.plain)
                }
            }
        }
        .glass()
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Schnelle Tipps", systemImage: "sparkles").font(.headline)
            tip("Router frei und erhöht hinstellen – nicht in den Schrank, nicht hinter den Fernseher.")
            tip("Wände aus Beton und Fußbodenheizung schlucken viel Funk. Mesh-Repeater helfen.")
            tip("Für die PS5 ist ein LAN-Kabel oder Powerline-Adapter immer stabiler als WLAN.")
            tip("In der FRITZ!Box unter WLAN › Funkkanal die automatische Kanalwahl anlassen.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    private func tip(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Neon.cyan).frame(width: 5, height: 5).padding(.top, 7)
            Text(t).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

struct SignalSparkline: View {
    let values: [Int]
    var body: some View {
        GeometryReader { geo in
            let pts = values.suffix(40)
            Path { p in
                guard pts.count > 1 else { return }
                let step = geo.size.width / CGFloat(max(pts.count - 1, 1))
                for (i, v) in pts.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(v) / 100))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(LinearGradient(colors: [Neon.cyan, Neon.magenta], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .neonGlow(Neon.cyan, radius: 4)
        }
    }
}

struct RoomRow: View {
    @Environment(RoomStore.self) private var rooms
    let room: RoomMap

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let img = rooms.image(for: room) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 64, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(room.name).font(.subheadline.weight(.semibold))
                if let best = room.best {
                    Text("\(room.points.count) Messpunkte · bester Platz \(Int(best.sample.score)) Punkte")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Noch keine Messpunkte").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let best = room.best { AmpelDot(level: best.sample.level, size: 10) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Live-Suche ("Wünschelrute")

struct LiveSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var live = WLANLive()
    @State private var best: Int = 0
    @AppStorage(K.searchSound) private var sound = true
    @AppStorage(K.fritzEnabled) private var fritzEnabled = false
    @State private var clickTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            NeonBackground()
            VStack(spacing: 24) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                    Toggle(isOn: $sound) { Image(systemName: sound ? "speaker.wave.2.fill" : "speaker.slash.fill") }
                        .toggleStyle(.button).tint(Neon.cyan)
                }
                Spacer()
                Text("Lauf langsam durch den Raum").font(.headline).foregroundStyle(.secondary)

                let value = currentValue
                let lvl: Level = value >= 70 ? .great : value >= 50 ? .good : value >= 30 ? .ok : .bad
                ZStack {
                    Circle().stroke(.white.opacity(0.07), lineWidth: 26)
                    Circle().trim(from: 0, to: CGFloat(value) / 100)
                        .stroke(AngularGradient(colors: [lvl.color, Neon.cyan, lvl.color], center: .center),
                                style: StrokeStyle(lineWidth: 26, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .neonGlow(lvl.color, radius: 14)
                        .animation(.spring(response: 0.6), value: value)
                    VStack(spacing: 4) {
                        Text("\(value)").font(.system(size: 84, weight: .heavy, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText(value: Double(value)))
                            .animation(.snappy, value: value)
                        Text(fritzEnabled ? "% Signal" : "Punkte (aus Ping)").font(.headline).foregroundStyle(.secondary)
                        trendLabel
                    }
                }
                .frame(width: 280, height: 280)

                HStack(spacing: 10) {
                    StatTile(title: "Bester Wert", value: "\(best)", unit: fritzEnabled ? "%" : "", icon: "star.fill")
                    StatTile(title: "Ping", value: live.pingMs.map(Fmt.ms) ?? "–", unit: "ms", icon: "bolt.horizontal.fill")
                    StatTile(title: "Band", value: live.wlan?.band ?? "–", unit: "", icon: "dot.radiowaves.right")
                }

                if let e = live.error, fritzEnabled {
                    Text(e).font(.caption).foregroundStyle(Neon.yellow).multilineTextAlignment(.center)
                }
                if !fritzEnabled {
                    Text("Ohne FRITZ!Box schätzt OGSpeed die Qualität nur über den Ping. Mit FRITZ!Box siehst du das echte Signal.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Spacer()
            }
            .padding()
        }
        .onAppear {
            live.start(fast: true)
            UIApplication.shared.isIdleTimerDisabled = true
            startClicks()
        }
        .onDisappear {
            live.stop()
            clickTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: currentValue) { _, v in
            if v > best {
                best = v
                if v > 0 { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            }
        }
    }

    private var currentValue: Int {
        if fritzEnabled, let w = live.wlan { return w.signal }
        if let p = live.pingMs { return Int(max(0, min(100, 110 - p * 1.5))) }
        return 0
    }

    @ViewBuilder private var trendLabel: some View {
        let t = live.trend
        if t >= 3 {
            Label("wird besser", systemImage: "arrow.up").font(.subheadline.weight(.bold)).foregroundStyle(Neon.green)
        } else if t <= -3 {
            Label("wird schlechter", systemImage: "arrow.down").font(.subheadline.weight(.bold)).foregroundStyle(Neon.red)
        } else {
            Label("gleich", systemImage: "equal").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    /// Geigerzähler-Klicks: je besser das Signal, desto schneller
    private func startClicks() {
        clickTask = Task {
            while !Task.isCancelled {
                let v = currentValue
                if sound && v > 0 {
                    AudioServicesPlaySystemSound(1104)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: CGFloat(v) / 100)
                }
                let delay = 1300 - Double(v) * 11   // 100 % ≈ 0,2 s, 10 % ≈ 1,2 s
                try? await Task.sleep(for: .milliseconds(Int(max(180, delay))))
            }
        }
    }
}
