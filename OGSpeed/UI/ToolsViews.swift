import SwiftUI
import Charts

// MARK: - Liegt's an mir?

struct ServiceCheckView: View {
    @State private var checker = ServiceChecker()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let v = checker.verdict {
                    HStack(alignment: .top, spacing: 12) {
                        AmpelStack(level: v.0)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(v.1).font(.title3.weight(.heavy)).foregroundStyle(v.0.color)
                            Text(v.2).font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass()
                } else {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large).tint(Neon.cyan)
                        Text("Prüfe \(ServiceList.all.count) Dienste …").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                    .glass()
                }

                VStack(spacing: 0) {
                    ForEach(checker.results) { r in
                        HStack(spacing: 12) {
                            Image(systemName: Sym.safe(r.service.icon)).frame(width: 24)
                                .foregroundStyle(r.ok ? Neon.cyan : Neon.red)
                            Text(r.service.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            if let p = r.pingMs {
                                Text("\(Fmt.ms(p)) ms").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                AmpelDot(level: Rating.pingLevel(p), size: 8)
                            } else {
                                Text("nicht erreichbar").font(.caption.weight(.bold)).foregroundStyle(Neon.red)
                            }
                        }
                        .padding(.vertical, 9)
                        Divider().overlay(.white.opacity(0.06))
                    }
                }
                .glass()

                Button {
                    Task { await checker.run() }
                } label: { Label("Nochmal prüfen", systemImage: "arrow.clockwise") }
                .buttonStyle(NeonButtonStyle())
                .disabled(checker.running)

                Text("Gemessen wird der Verbindungsaufbau zum nächstgelegenen Server des Dienstes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle("Liegt's an mir?")
        .navigationBarTitleDisplayMode(.inline)
        .task { if checker.results.isEmpty { await checker.run() } }
    }
}

// MARK: - Gaming-Radar

struct PingRadarView: View {
    @State private var radar = PingRadar()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summary
                chart
                ForEach(radar.series) { s in row(s) }
                Text("Live-Ping alle 2 Sekunden zum nächsten Server des Dienstes. Unter 30 ms ideal für Shooter, Spitzen über 100 ms spürst du als Lag.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle("Gaming-Radar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            radar.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            radar.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var summary: some View {
        let measured = radar.series.filter { !$0.samples.isEmpty }
        let best = measured.min { $0.avg < $1.avg }
        let spikes = measured.map(\.spikes).reduce(0, +)
        let lost = radar.series.map(\.lost).reduce(0, +)
        let level: Level = spikes == 0 && lost == 0 ? .great : spikes < 4 && lost < 3 ? .good : .ok
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Live", systemImage: "dot.radiowaves.left.and.right").font(.headline).foregroundStyle(Neon.red)
                Spacer()
                LevelPill(level: level)
            }
            if let best {
                Text("Schnellster Server: \(best.service.name) mit Ø \(Fmt.ms(best.avg)) ms").font(.subheadline)
            } else {
                Text("Messe …").font(.subheadline).foregroundStyle(.secondary)
            }
            Text("\(spikes) Lag-Spitzen · \(lost) Aussetzer").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    private struct Point: Identifiable {
        let id = UUID()
        let name: String
        let index: Int
        let ms: Double
    }

    private var points: [Point] {
        var out: [Point] = []
        for s in radar.series.prefix(4) {
            for (i, v) in s.samples.enumerated() { out.append(Point(name: s.service.name, index: i, ms: v)) }
        }
        return out
    }

    private var chart: some View {
        Chart(points) { p in
            LineMark(x: .value("Messung", p.index), y: .value("ms", p.ms))
                .foregroundStyle(by: .value("Server", p.name))
                .interpolationMethod(.monotone)
        }
        .chartLegend(position: .bottom)
        .chartYAxisLabel("ms")
        .frame(height: 190)
        .glass()
    }

    private func row(_ s: PingRadar.Series) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Sym.safe(s.service.icon)).frame(width: 24).foregroundStyle(Neon.magenta)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.service.name).font(.subheadline.weight(.semibold))
                Text("Ø \(Fmt.ms(s.avg)) ms · Jitter \(Fmt.ms(s.jitter)) ms\(s.lost > 0 ? " · \(s.lost) verloren" : "")")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            if let last = s.last {
                Text(Fmt.ms(last)).font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Rating.pingLevel(last).color)
                    .contentTransition(.numericText(value: last))
                    .animation(.snappy, value: last)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .glass(radius: 20, padding: 12)
    }
}

// MARK: - DNS-Turbo

struct DNSTurboView: View {
    let router: String?
    @State private var bench = DNSBench()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Was ist DNS?", systemImage: "book.fill").font(.headline)
                    Text("Bevor eine Seite, ein Stream oder eine Spiel-Lobby lädt, fragt dein Gerät das „Telefonbuch des Internets“ nach der Adresse. Ein schneller DNS-Server spart bei jedem Aufruf Zeit.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass()

                if bench.running {
                    ProgressView(value: bench.progress) { Text("Teste DNS-Server …").font(.subheadline) }
                        .tint(Neon.cyan)
                        .glass()
                }

                if !bench.results.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(Array(bench.results.enumerated()), id: \.element.id) { i, r in
                            HStack(spacing: 12) {
                                Text(rankText(i)).font(.headline).frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(r.server.name) · \(r.server.ip)").font(.subheadline.weight(.semibold))
                                    Text(r.server.note).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(msText(r.medianMs))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(msColor(r.medianMs))
                            }
                        }
                    }
                    .glass()
                }

                if !bench.running, let best = bench.results.first, best.medianMs != nil {
                    recommendation(best)
                }

                Button {
                    Task { await bench.run(router: router) }
                } label: { Label(bench.results.isEmpty ? "DNS-Test starten" : "Nochmal testen", systemImage: "hare.fill") }
                .buttonStyle(NeonButtonStyle())
                .disabled(bench.running)
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle("DNS-Turbo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rankText(_ i: Int) -> String { i == 0 && !bench.running ? "🏆" : "\(i + 1)" }

    private func msText(_ v: Double?) -> String {
        guard let v else { return "–" }
        return "\(Fmt.ms(v)) ms"
    }

    private func msColor(_ v: Double?) -> Color {
        guard let v else { return Neon.red }
        if v < 20 { return Neon.green }
        if v < 50 { return Neon.lime }
        return Neon.yellow
    }

    private func recommendation(_ best: DNSResult) -> some View {
        let routerResult = bench.results.first { $0.server.name == "Dein Router" }
        let gain: Double? = {
            guard let a = routerResult?.medianMs, let b = best.medianMs else { return nil }
            return a - b
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Label("Empfehlung", systemImage: "lightbulb.fill").font(.headline).foregroundStyle(Neon.yellow)
            if best.server.name == "Dein Router" {
                Text("Dein Router ist schon am schnellsten – nichts ändern.").font(.subheadline)
            } else {
                if let gain, gain > 3 {
                    Text("**\(best.server.name)** ist bei dir ca. \(Fmt.ms(gain)) ms schneller pro Aufruf als dein Router.").font(.subheadline)
                } else {
                    Text("**\(best.server.name)** antwortet am schnellsten.").font(.subheadline)
                }
                Text("Am iPhone: Einstellungen › WLAN › (i) › DNS konfigurieren › Manuell › \(best.server.ip). Für alle Geräte gleichzeitig trägst du ihn im Router ein (siehe Netz › Maximum rausholen).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }
}

// MARK: - Geräte im WLAN

struct DevicesView: View {
    @AppStorage(K.fritzEnabled) private var fritzEnabled = false
    @AppStorage("knownDevices") private var knownRaw = ""
    @State private var hosts: [FritzHost] = []
    @State private var error: String?
    @State private var loading = false

    private var known: Set<String> { Set(knownRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !fritzEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Nur mit FRITZ!Box", systemImage: "wifi.router.fill").font(.headline)
                        Text("iOS erlaubt Apps nicht, das Netz selbst nach Geräten abzusuchen. Die FRITZ!Box kennt aber alle Geräte – verbinde sie einmal.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        NavigationLink { FritzSetupView() } label: { Text("FRITZ!Box verbinden").frame(maxWidth: .infinity) }
                            .buttonStyle(GlassButtonStyle())
                    }
                    .glass()
                } else {
                    summary
                    if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Neon.yellow).glass() }
                    list("Gerade online", hosts.filter(\.active))
                    list("Bekannt, aber offline", hosts.filter { !$0.active })
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle("Geräte im WLAN")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if fritzEnabled && !hosts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Alle als bekannt") {
                        knownRaw = Set(hosts.map(\.id)).union(known).sorted().joined(separator: ",")
                    }
                    .font(.caption)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard fritzEnabled, let c = FritzClient.fromPrefs() else { return }
        loading = true
        defer { loading = false }
        do {
            hosts = try await c.hostList().sorted { ($0.active ? 0 : 1, $0.name.lowercased()) < ($1.active ? 0 : 1, $1.name.lowercased()) }
            error = nil
            if knownRaw.isEmpty { knownRaw = hosts.map(\.id).sorted().joined(separator: ",") }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var summary: some View {
        let online = hosts.filter(\.active)
        let newOnes = online.filter { !known.contains($0.id) }
        return HStack(spacing: 10) {
            StatTile(title: "Online", value: "\(online.count)", unit: "Geräte", icon: "dot.radiowaves.left.and.right")
            StatTile(title: "WLAN", value: "\(online.filter(\.isWLAN).count)", unit: "", icon: "wifi")
            StatTile(title: "Neu", value: "\(newOnes.count)", unit: "", level: newOnes.isEmpty ? .great : .ok, icon: "sparkles")
        }
        .overlay { if loading && hosts.isEmpty { ProgressView() } }
    }

    @ViewBuilder
    private func list(_ title: String, _ items: [FritzHost]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).padding(.bottom, 4)
                ForEach(items) { h in
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: h)).frame(width: 26).foregroundStyle(h.active ? Neon.cyan : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(h.name).font(.subheadline.weight(.semibold))
                                if !known.contains(h.id) {
                                    Text("NEU").font(.caption2.weight(.heavy)).foregroundStyle(.black)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Neon.yellow, in: Capsule())
                                }
                                if h.guest {
                                    Text("Gast").font(.caption2.weight(.bold)).foregroundStyle(Neon.magenta)
                                }
                            }
                            Text(detail(h)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    Divider().overlay(.white.opacity(0.06))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass()
        }
    }

    private func detail(_ h: FritzHost) -> String {
        var parts: [String] = []
        if !h.ip.isEmpty { parts.append(h.ip) }
        if h.isWLAN { parts.append("WLAN") } else if !h.interface.isEmpty { parts.append("LAN") }
        if let s = h.speedMbps, s > 0 { parts.append("\(s) Mbit/s") }
        return parts.joined(separator: " · ")
    }

    private func icon(for h: FritzHost) -> String {
        let n = h.name.lowercased()
        if n.contains("iphone") || n.contains("galaxy") || n.contains("android") || n.contains("pixel") { return "iphone" }
        if n.contains("ipad") || n.contains("tab") { return "ipad" }
        if n.contains("ps5") || n.contains("ps4") || n.contains("playstation") || n.contains("xbox") || n.contains("switch") { return "gamecontroller.fill" }
        if n.contains("tv") || n.contains("fire") || n.contains("chromecast") || n.contains("roku") { return "tv" }
        if n.contains("macbook") || n.contains("laptop") || n.contains("thinkpad") || n.contains("notebook") { return "laptopcomputer" }
        if n.contains("pc") || n.contains("desktop") || n.contains("minix") { return "desktopcomputer" }
        if n.contains("raspberry") || n.contains("pi") || n.contains("esp") { return "cpu" }
        if n.contains("nest") || n.contains("echo") || n.contains("alexa") || n.contains("homepod") { return "homepod.fill" }
        if n.contains("repeater") || n.contains("fritz") { return "wifi.router" }
        return h.isWLAN ? "wifi" : "cable.connector"
    }
}

// MARK: - Teilen-Bild

struct ShareCard: View {
    let result: SpeedResult

    var body: some View {
        let o = Rating.overall(result)
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("OGSpeed").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Neon.cyan)
                Spacer()
                Text(result.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.mbps(result.downMbps)).font(.system(size: 72, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("Mbit/s ↓").font(.title3.weight(.bold)).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 22) {
                stat("Upload", "\(Fmt.mbps(result.upMbps))", "Mbit/s")
                stat("Ping", Fmt.ms(result.pingMs), "ms")
                stat("Jitter", Fmt.ms(result.jitterMs), "ms")
            }
            HStack(spacing: 10) {
                Circle().fill(o.level.color).frame(width: 14, height: 14).shadow(color: o.level.color, radius: 6)
                Text(o.title).font(.headline).foregroundStyle(o.level.color)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Rating.all(result)) { v in
                    HStack(spacing: 8) {
                        Circle().fill(v.level.color).frame(width: 8, height: 8)
                        Text("\(v.title): \(v.headline)").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            Text(footer).font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .padding(28)
        .frame(width: 400)
        .background(
            ZStack {
                Neon.bg
                LinearGradient(colors: [Neon.purple.opacity(0.55), .clear, Neon.cyan.opacity(0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(LinearGradient(colors: [Neon.cyan, Neon.magenta], startPoint: .leading, endPoint: .trailing), lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    /// Der WLAN-Name steht nur im Bild, wenn es ausdrücklich erlaubt ist.
    private var footer: String {
        var parts = [result.connection.label]
        if Privacy.showSSIDInShare, let n = result.networkName { parts.append(n) }
        if let p = result.provider { parts.append(p) }
        if let s = result.server { parts.append(s) }
        return parts.joined(separator: " · ")
    }

    private func stat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.6))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.weight(.bold)).foregroundStyle(.white)
                Text(unit).font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    @MainActor
    static func render(_ r: SpeedResult) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(result: r))
        renderer.scale = 3
        return renderer.uiImage
    }
}

struct ShareResultButton: View {
    let result: SpeedResult
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, preview: SharePreview("Mein OGSpeed-Ergebnis", image: image)) {
                    Label("Ergebnis als Bild teilen", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .task(id: result.id) {
            if let ui = ShareCard.render(result) { image = Image(uiImage: ui) }
        }
    }
}
