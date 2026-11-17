import SwiftUI

struct TestView: View {
    @Environment(SpeedTester.self) private var tester
    @Environment(NetworkMonitor.self) private var network
    @Environment(HistoryStore.self) private var history
    @State private var showExplain = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    SpeedRing(phase: tester.phase, value: tester.liveValue, progress: tester.progress) {
                        tester.start(network: network, history: history)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 4)

                    if case .failed(let msg) = tester.phase {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(Neon.yellow)
                            .glass(radius: 18, padding: 12)
                    }

                    liveTiles

                    if tester.isRunning {
                        Button("Abbrechen", role: .cancel) { tester.cancel() }
                            .buttonStyle(GlassButtonStyle())
                            .frame(maxWidth: 200)
                    }

                    if let r = tester.result, tester.phase == .done {
                        ResultSections(result: r)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        Button {
                            tester.start(network: network, history: history)
                        } label: {
                            Label("Nochmal testen", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(NeonButtonStyle())
                        .padding(.top, 4)
                    } else if tester.phase == .idle, let last = history.results.first {
                        lastResultCard(last)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: tester.phase)
            }
            .scrollIndicators(.hidden)
            .background(NeonBackground())
            .navigationTitle("OGSpeed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showExplain = true } label: { Image(systemName: "questionmark.circle") }
                }
            }
            .sheet(isPresented: $showExplain) { ExplainSheet() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: network.kind.icon)
                .font(.headline)
                .foregroundStyle(Neon.cyan)
                .frame(width: 36, height: 36)
                .background(Neon.cyan.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(network.summary).font(.subheadline.weight(.bold))
                Text(tester.server.map { "Server: \($0)" } ?? (network.kind == .cellular && Prefs.dataSaver ? "Datensparmodus an" : "Server wird automatisch gewählt"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if network.kind == .cellular {
                Image(systemName: "chart.bar.fill").foregroundStyle(.secondary)
            }
        }
        .glass(radius: 22, padding: 12)
    }

    private var liveTiles: some View {
        HStack(spacing: 10) {
            StatTile(title: "Ping", value: tester.pingMs.map(Fmt.ms) ?? "–", unit: "ms",
                     level: tester.pingMs.map(Rating.pingLevel), icon: "bolt.horizontal.fill")
            StatTile(title: "Download", value: tester.downMbps.map(Fmt.mbps) ?? "–", unit: "Mbit/s",
                     level: tester.downMbps.map(Rating.downLevel), icon: "arrow.down")
            StatTile(title: "Upload", value: tester.upMbps.map(Fmt.mbps) ?? "–", unit: "Mbit/s",
                     level: tester.upMbps.map(Rating.upLevel), icon: "arrow.up")
        }
    }

    private func lastResultCard(_ r: SpeedResult) -> some View {
        let o = Rating.overall(r)
        return HStack(spacing: 12) {
            AmpelDot(level: o.level, size: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text("Letzter Test · \(Fmt.relative(r.date))").font(.caption).foregroundStyle(.secondary)
                Text(o.title).font(.headline)
                Text("\(Fmt.mbps(r.downMbps)) ↓  \(Fmt.mbps(r.upMbps)) ↑  \(Fmt.ms(r.pingMs)) ms")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glass()
    }
}

// MARK: - Ergebnis-Karten

struct ResultSections: View {
    let result: SpeedResult

    var body: some View {
        let o = Rating.overall(result)
        VStack(spacing: 14) {
            // Gesamturteil
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    AmpelStack(level: o.level)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dein Internet").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(o.title).font(.title2.weight(.heavy))
                            .foregroundStyle(o.level.color)
                    }
                }
                Text(o.text).font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass()

            ForEach(Rating.all(result)) { v in
                VerdictCard(verdict: v)
            }

            DetailCard(result: result)
        }
    }
}

/// Senkrechte Ampel
struct AmpelStack: View {
    let level: Level
    var body: some View {
        VStack(spacing: 5) {
            light(.bad, Neon.red)
            light(.ok, Neon.yellow)
            light(.good, Neon.green)
        }
        .padding(6)
        .background(.black.opacity(0.5), in: Capsule())
    }

    private func light(_ l: Level, _ c: Color) -> some View {
        let on = (l == .good && level >= .good) || l == level
        return Circle().fill(on ? c : c.opacity(0.12)).frame(width: 14, height: 14)
            .shadow(color: on ? c : .clear, radius: 6)
    }
}

struct VerdictCard: View {
    let verdict: Verdict
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { open.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: verdict.icon)
                        .font(.title3)
                        .foregroundStyle(verdict.level.color)
                        .frame(width: 42, height: 42)
                        .background(verdict.level.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verdict.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(verdict.headline).font(.headline).multilineTextAlignment(.leading)
                    }
                    Spacer()
                    LevelPill(level: verdict.level)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 10) {
                    ForEach(verdict.rows) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: row.level.symbol).foregroundStyle(row.level.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).font(.subheadline.weight(.semibold))
                                Text(row.text).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glass()
    }
}

struct DetailCard: View {
    let result: SpeedResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details").font(.headline)
            row("Ping (Reaktionszeit)", "\(Fmt.ms(result.pingMs)) ms", Rating.pingLevel(result.pingMs),
                "Wie schnell eine Antwort zurückkommt. Unter 20 ms fühlt sich an wie sofort.")
            row("Jitter (Schwankung)", "\(Fmt.ms(result.jitterMs)) ms", Rating.jitterLevel(result.jitterMs),
                "Wie stark der Ping wackelt. Hoher Jitter = Ruckler in Spielen und Calls.")
            row("Ping unter Last", "+\(Fmt.ms(result.bufferbloatMs)) ms", Rating.bloatLevel(result.bufferbloatMs),
                "Wie viel langsamer die Reaktion wird, wenn gleichzeitig geladen wird (z. B. jemand streamt).")
            row("Aussetzer", String(format: "%.1f %%", result.dropoutPercent), Rating.dropoutLevel(result.dropoutPercent),
                "Anteil der Messungen, die gar nicht oder extrem spät ankamen.")
            if let dns = result.dnsMs {
                row("DNS-Antwort", "\(Fmt.ms(dns)) ms", dns < 40 ? .great : dns < 100 ? .good : .ok,
                    "Wie schnell Webadressen aufgelöst werden – merkst du beim Öffnen von Seiten.")
            }
            if let s = result.signalPercent {
                row("WLAN-Signal (FRITZ!Box)", "\(s) %", Rating.signalLevel(s),
                    [result.band, result.linkMbps.map { "Verbindung \($0) Mbit/s" }].compactMap { $0 }.joined(separator: " · "))
            }
            Divider().overlay(.white.opacity(0.1))
            HStack {
                Text(result.server.map { "Server \($0)" } ?? "")
                Spacer()
                Text(String(format: "%.0f MB verbraucht", result.dataUsedMB))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .glass()
    }

    private func row(_ title: String, _ value: String, _ level: Level, _ hint: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AmpelDot(level: level, size: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(value).font(.subheadline.weight(.bold).monospacedDigit())
                }
                if !hint.isEmpty {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Erklärungen

struct ExplainSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let items: [(String, String, String)] = [
        ("arrow.down", "Download", "Wie schnell Daten zu dir kommen: Streams, Downloads, Webseiten. 50 Mbit/s reichen für einen Haushalt mit 4K-Streaming."),
        ("arrow.up", "Upload", "Wie schnell du Daten wegschickst: Videocalls, Fotos in die Cloud, selbst streamen."),
        ("bolt.horizontal.fill", "Ping", "Die Reaktionszeit. Für Shooter wichtiger als hohe Mbit/s! Unter 20 ms top, über 60 ms merkst du es."),
        ("waveform.path", "Jitter", "Wie gleichmäßig der Ping ist. Schwankt er stark, ruckeln Spiele und Calls, auch wenn der Ping gut aussieht."),
        ("gauge.with.dots.needle.67percent", "Ping unter Last", "Steigt der Ping stark, sobald jemand etwas herunterlädt, heißt das „Bufferbloat“. Abhilfe: in der FRITZ!Box die Priorisierung für dein Gerät einschalten."),
        ("exclamationmark.triangle", "Aussetzer", "Messungen, die verloren gingen oder ewig brauchten. Schon 2 % sorgen für spürbare Hänger."),
        ("wifi", "WLAN-Signal", "Kommt direkt von deiner FRITZ!Box. Ab 70 % ist alles top, unter 40 % wird es wackelig. Im Tab WLAN findest du die beste Stelle im Raum."),
        ("antenna.radiowaves.left.and.right", "Mobilfunk", "Im Datensparmodus wird bei Mobilfunk weniger Datenvolumen verbraucht (ca. 50–150 MB statt bis zu 1 GB).")
    ]

    var body: some View {
        NavigationStack {
            List(items.indices, id: \.self) { i in
                let item = items[i]
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: item.0).font(.title3).foregroundStyle(Neon.cyan).frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.1).font(.headline)
                        Text(item.2).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.white.opacity(0.05))
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
            .background(NeonBackground())
            .navigationTitle("Was heißt das?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
