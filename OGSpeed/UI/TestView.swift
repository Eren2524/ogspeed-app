import SwiftUI

// MARK: - Bausteine im iOS-Stil

/// Abschnitts-Überschrift wie in den iOS-Einstellungen
struct SectionLabel: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }
}

/// Kachel für einen Messwert
struct MetricTile: View {
    let icon: String
    let title: String
    let value: String
    var unit: String = ""
    var level: Level? = nil
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if let level { AmpelDot(level: level, size: 7) }
            }
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }

            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 20, padding: 13)
    }
}

/// Zeile im Listenstil (Titel links, Wert rechts)
struct InfoLine: View {
    let title: String
    let value: String
    var icon: String? = nil
    var level: Level? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon).font(.caption).foregroundStyle(Neon.cyan).frame(width: 18)
            }
            Text(title).font(.subheadline)
            Spacer(minLength: 8)
            if let level { AmpelDot(level: level, size: 7) }
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)
    }
}

/// Fortschritt der drei Mess-Schritte
struct PhaseStepper: View {
    let phase: TestPhase

    private var order: [TestPhase] { [.ping, .download, .upload] }
    private var titles: [String] { ["Reaktion", "Download", "Upload"] }
    private var icons: [String] { ["bolt.horizontal.fill", "arrow.down", "arrow.up"] }

    /// 0 = kommt noch, 1 = läuft, 2 = fertig
    private func state(_ index: Int) -> Int {
        switch phase {
        case .ping: return index == 0 ? 1 : 0
        case .download: return index < 1 ? 2 : (index == 1 ? 1 : 0)
        case .upload: return index < 2 ? 2 : 1
        case .done: return 2
        default: return 0
        }
    }

    private func color(_ s: Int) -> Color {
        s == 2 ? Neon.green : (s == 1 ? Neon.cyan : Color.secondary)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                let s = state(i)
                HStack(spacing: 6) {
                    Image(systemName: s == 2 ? "checkmark.circle.fill" : icons[i])
                        .font(.caption2)
                        .foregroundStyle(color(s))
                    Text(titles[i])
                        .font(.caption2.weight(s == 1 ? .bold : .medium))
                        .foregroundStyle(s == 0 ? Color.secondary : Color.primary)
                }
                if i < 2 {
                    Rectangle()
                        .fill(state(i + 1) > 0 ? Neon.cyan.opacity(0.6) : Color.white.opacity(0.12))
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Vergleich mit früheren Tests

struct Comparison {
    var averageDown: Double?
    var bestDown: Double?
    var deltaPercent: Double?
    var sampleCount: Int
    var tariffShare: Double?
    var dayPart: String

    init(current: SpeedResult, history: [SpeedResult]) {
        let same = history.filter { $0.connection == current.connection && $0.id != current.id }
        let recent = Array(same.prefix(5))
        sampleCount = recent.count
        if !recent.isEmpty {
            let avg = recent.map(\.downMbps).reduce(0, +) / Double(recent.count)
            averageDown = avg
            if avg > 0.1 { deltaPercent = (current.downMbps - avg) / avg * 100 }
        }
        bestDown = same.map(\.downMbps).max()
        let booked = Prefs.double(current.connection == .cellular ? K.mDownMax : K.tDownMax)
        if booked > 0 { tariffShare = current.downMbps / booked * 100 }
        let hour = Calendar.current.component(.hour, from: current.date)
        switch hour {
        case 0...5: dayPart = "Nacht"
        case 6...10: dayPart = "Morgen"
        case 11...14: dayPart = "Mittag"
        case 15...17: dayPart = "Nachmittag"
        case 18...21: dayPart = "Abend"
        default: dayPart = "Später Abend"
        }
    }
}

// MARK: - Hauptseite

struct TestView: View {
    @Environment(SpeedTester.self) private var tester
    @Environment(NetworkMonitor.self) private var network
    @Environment(HistoryStore.self) private var history
    @State private var showExplain = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    connectionBar

                    SpeedRing(phase: tester.phase, value: tester.liveValue, progress: tester.progress) {
                        tester.start(network: network, history: history)
                    }
                    .padding(.horizontal, 34)

                    if tester.isRunning || tester.phase == .done {
                        PhaseStepper(phase: tester.phase)
                    }

                    if case .failed(let msg) = tester.phase { errorCard(msg) }

                    liveTiles

                    if tester.isRunning {
                        Button("Abbrechen", role: .cancel) { tester.cancel() }
                            .buttonStyle(GlassButtonStyle())
                            .frame(maxWidth: 220)
                    }

                    if let r = tester.result, tester.phase == .done {
                        resultBlock(r)
                    } else if tester.phase == .idle {
                        idleBlock
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 34)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: tester.phase)
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

    // MARK: Kopfzeile

    private var connectionBar: some View {
        HStack(spacing: 11) {
            Image(systemName: network.kind.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Neon.cyan)
                .frame(width: 32, height: 32)
                .background(Neon.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(headerSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if network.kind == .cellular && Prefs.dataSaver {
                Text("Sparmodus")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Neon.yellow.opacity(0.16), in: Capsule())
                    .foregroundStyle(Neon.yellow)
            }
        }
        .glass(radius: 20, padding: 12)
    }

    private var headerTitle: String {
        guard let id = NetDetector.shared.identity, id.connection == network.kind else { return network.summary }
        var parts = [network.summary]
        if id.provider != .other {
            parts.append(id.provider.label)
        } else if let n = id.providerName {
            parts.append(n)
        }
        return parts.joined(separator: " · ")
    }

    private var headerSubtitle: String {
        if let s = tester.server { return "Testserver: \(s)" }
        if network.kind == .wifi, let r = NetDetector.shared.identity?.router { return r.displayName }
        return "Server wird automatisch gewählt"
    }

    private func errorCard(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Neon.yellow)
            Text(msg).font(.subheadline)
            Spacer(minLength: 0)
        }
        .glass(radius: 18, padding: 13)
    }

    // MARK: Live-Werte

    private var liveTiles: some View {
        HStack(spacing: 10) {
            MetricTile(icon: "arrow.down", title: "Download",
                       value: tester.downMbps.map(Fmt.mbps) ?? "–", unit: "Mbit/s",
                       level: tester.downMbps.map(Rating.downLevel))
            MetricTile(icon: "arrow.up", title: "Upload",
                       value: tester.upMbps.map(Fmt.mbps) ?? "–", unit: "Mbit/s",
                       level: tester.upMbps.map(Rating.upLevel))
            MetricTile(icon: "bolt.horizontal.fill", title: "Ping",
                       value: tester.pingMs.map(Fmt.ms) ?? "–", unit: "ms",
                       level: tester.pingMs.map(Rating.pingLevel))
        }
    }

    // MARK: Startzustand

    @ViewBuilder
    private var idleBlock: some View {
        if let last = history.results.first {
            VStack(spacing: 10) {
                SectionLabel(title: "Letzter Test", trailing: Fmt.relative(last.date))
                NavigationLink {
                    ScrollView { ResultSections(result: last).padding() }
                        .background(NeonBackground())
                        .navigationTitle(last.date.formatted(date: .abbreviated, time: .shortened))
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    lastResultRow(last)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Erster Test", systemImage: "sparkles").font(.headline)
                Text("Der Test dauert rund 25 Sekunden und misst Reaktionszeit, Download und Upload. Danach siehst du nicht nur Zahlen, sondern auch, was damit flüssig läuft.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass()
        }
    }

    private func lastResultRow(_ r: SpeedResult) -> some View {
        let o = Rating.overall(r)
        return HStack(spacing: 12) {
            AmpelDot(level: o.level, size: 13)
            VStack(alignment: .leading, spacing: 3) {
                Text(o.title).font(.subheadline.weight(.semibold))
                Text("\(Fmt.mbps(r.downMbps)) ↓ · \(Fmt.mbps(r.upMbps)) ↑ · \(Fmt.ms(r.pingMs)) ms")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .glass(radius: 20, padding: 13)
    }

    // MARK: Ergebnis

    private func resultBlock(_ r: SpeedResult) -> some View {
        VStack(spacing: 14) {
            verdictHero(r)
            measurements(r)
            comparison(r)

            SectionLabel(title: "Was geht damit?")
            ForEach(Rating.all(r)) { v in VerdictCard(verdict: v) }

            SectionLabel(title: "Verbindung")
            connectionDetails(r)

            VStack(spacing: 10) {
                Button {
                    tester.start(network: network, history: history)
                } label: {
                    Label("Nochmal testen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(NeonButtonStyle())
                ShareResultButton(result: r)
            }
            .padding(.top, 4)
        }
    }

    private func verdictHero(_ r: SpeedResult) -> some View {
        let o = Rating.overall(r)
        return HStack(alignment: .top, spacing: 14) {
            AmpelStack(level: o.level)
            VStack(alignment: .leading, spacing: 5) {
                Text("Einschätzung").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(o.title).font(.title3.weight(.heavy)).foregroundStyle(o.level.color)
                Text(o.text).font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .glass()
    }

    private func measurements(_ r: SpeedResult) -> some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return VStack(spacing: 10) {
            SectionLabel(title: "Messwerte", trailing: r.date.formatted(date: .omitted, time: .shortened))
            LazyVGrid(columns: columns, spacing: 10) {
                MetricTile(icon: "waveform.path", title: "Jitter", value: Fmt.ms(r.jitterMs), unit: "ms",
                           level: Rating.jitterLevel(r.jitterMs), note: "Schwankung des Pings")
                MetricTile(icon: "gauge.with.dots.needle.67percent", title: "Ping unter Last",
                           value: "+" + Fmt.ms(r.bufferbloatMs), unit: "ms",
                           level: Rating.bloatLevel(r.bufferbloatMs), note: "Wenn gleichzeitig geladen wird")
                MetricTile(icon: "exclamationmark.triangle", title: "Aussetzer",
                           value: String(format: "%.1f", r.dropoutPercent), unit: "%",
                           level: Rating.dropoutLevel(r.dropoutPercent), note: "Verlorene Messungen")
                MetricTile(icon: "globe", title: "DNS-Antwort",
                           value: r.dnsMs.map(Fmt.ms) ?? "–", unit: "ms",
                           level: dnsLevel(r.dnsMs), note: "Tempo beim Seitenaufruf")
                if let s = r.signalPercent {
                    MetricTile(icon: "wifi", title: "WLAN-Signal", value: "\(s)", unit: "%",
                               level: Rating.signalLevel(s), note: r.band ?? "von der FRITZ!Box")
                }
                if let link = r.linkMbps {
                    MetricTile(icon: "link", title: "WLAN-Tempo", value: "\(link)", unit: "Mbit/s",
                               note: "iPhone ↔ Router")
                }
                MetricTile(icon: "arrow.up.arrow.down.circle", title: "Verbraucht",
                           value: String(format: "%.0f", r.dataUsedMB), unit: "MB",
                           note: "Daten für diesen Test")
                MetricTile(icon: "chart.bar.fill", title: "Verhältnis ↓/↑",
                           value: ratio(r), unit: "",
                           note: "Download zu Upload")
            }
        }
    }

    private func dnsLevel(_ v: Double?) -> Level? {
        guard let v else { return nil }
        if v < 40 { return .great }
        if v < 100 { return .good }
        return .ok
    }

    private func ratio(_ r: SpeedResult) -> String {
        guard r.upMbps > 0.05 else { return "–" }
        return String(format: "%.0f:1", r.downMbps / r.upMbps)
    }

    @ViewBuilder
    private func comparison(_ r: SpeedResult) -> some View {
        let c = Comparison(current: r, history: history.results)
        if c.sampleCount > 0 || c.tariffShare != nil {
            VStack(spacing: 10) {
                SectionLabel(title: "Vergleich")
                VStack(spacing: 0) {
                    if let d = c.deltaPercent, let avg = c.averageDown {
                        InfoLine(title: "Gegenüber den letzten \(c.sampleCount) Tests",
                                 value: deltaText(d) + " (Ø \(Fmt.mbps(avg)))",
                                 icon: d >= 0 ? "arrow.up.right" : "arrow.down.right",
                                 level: deltaLevel(d))
                        Divider().overlay(.white.opacity(0.07))
                    }
                    if let best = c.bestDown, best > 0 {
                        InfoLine(title: "Bester Wert bisher", value: "\(Fmt.mbps(best)) Mbit/s", icon: "trophy")
                        Divider().overlay(.white.opacity(0.07))
                    }
                    if let share = c.tariffShare {
                        InfoLine(title: "Anteil am gebuchten Tempo", value: "\(Int(share)) %",
                                 icon: "doc.text", level: shareLevel(share))
                        Divider().overlay(.white.opacity(0.07))
                    }
                    InfoLine(title: "Tageszeit", value: c.dayPart, icon: "sun.max")
                }
                .glass(radius: 20, padding: 14)
                if c.tariffShare == nil {
                    NavigationLink { TariffView() } label: {
                        Label("Tarif eintragen für den Soll-Ist-Vergleich", systemImage: "plus.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .tint(Neon.cyan)
                }
            }
        }
    }

    private func deltaText(_ d: Double) -> String {
        let sign = d >= 0 ? "+" : ""
        return sign + String(format: "%.0f", d) + " %"
    }

    private func deltaLevel(_ d: Double) -> Level {
        if d >= -10 { return .great }
        if d >= -30 { return .ok }
        return .bad
    }

    private func shareLevel(_ s: Double) -> Level {
        if s >= 90 { return .great }
        if s >= 70 { return .good }
        if s >= 50 { return .ok }
        return .bad
    }

    private func connectionDetails(_ r: SpeedResult) -> some View {
        VStack(spacing: 0) {
            InfoLine(title: "Verbindung", value: connectionText(r), icon: r.connection.icon)
            if let p = r.provider {
                Divider().overlay(.white.opacity(0.07))
                InfoLine(title: "Anbieter", value: p, icon: "building.2")
            }
            if let router = r.router {
                Divider().overlay(.white.opacity(0.07))
                InfoLine(title: "Router", value: router, icon: "wifi.router")
            }
            if let n = r.networkName {
                Divider().overlay(.white.opacity(0.07))
                InfoLine(title: "WLAN", value: n, icon: "wifi")
            }
            if let s = r.server {
                Divider().overlay(.white.opacity(0.07))
                InfoLine(title: "Testserver", value: s, icon: "server.rack")
            }
            Divider().overlay(.white.opacity(0.07))
            InfoLine(title: "VPN", value: r.vpnActive ? "Aktiv" : "Aus",
                     icon: r.vpnActive ? "lock.fill" : "lock.open", level: r.vpnActive ? .great : nil)
        }
        .glass(radius: 20, padding: 14)
    }

    private func connectionText(_ r: SpeedResult) -> String {
        if let radio = r.radio { return r.connection.label + " · " + radio }
        if let band = r.band { return r.connection.label + " · " + band }
        return r.connection.label
    }
}

// MARK: - Ergebnis-Abschnitte (auch im Verlauf verwendet)

struct ResultSections: View {
    let result: SpeedResult

    var body: some View {
        let o = Rating.overall(result)
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                AmpelStack(level: o.level)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Einschätzung").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(o.title).font(.title3.weight(.heavy)).foregroundStyle(o.level.color)
                    Text(o.text).font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            .glass()

            HStack(spacing: 10) {
                MetricTile(icon: "arrow.down", title: "Download", value: Fmt.mbps(result.downMbps), unit: "Mbit/s",
                           level: Rating.downLevel(result.downMbps))
                MetricTile(icon: "arrow.up", title: "Upload", value: Fmt.mbps(result.upMbps), unit: "Mbit/s",
                           level: Rating.upLevel(result.upMbps))
                MetricTile(icon: "bolt.horizontal.fill", title: "Ping", value: Fmt.ms(result.pingMs), unit: "ms",
                           level: Rating.pingLevel(result.pingMs))
            }

            ForEach(Rating.all(result)) { v in VerdictCard(verdict: v) }
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
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { open.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: verdict.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(verdict.level.color)
                        .frame(width: 38, height: 38)
                        .background(verdict.level.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verdict.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(verdict.headline).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    AmpelDot(level: verdict.level, size: 9)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(spacing: 10) {
                    ForEach(verdict.rows) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: row.level.symbol).font(.caption)
                                .foregroundStyle(row.level.color).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).font(.caption.weight(.semibold))
                                Text(row.text).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glass(radius: 22, padding: 14)
    }
}

struct DetailCard: View {
    let result: SpeedResult

    var body: some View {
        VStack(spacing: 0) {
            InfoLine(title: "Jitter", value: Fmt.ms(result.jitterMs) + " ms", icon: "waveform.path",
                     level: Rating.jitterLevel(result.jitterMs))
            Divider().overlay(.white.opacity(0.07))
            InfoLine(title: "Ping unter Last", value: "+" + Fmt.ms(result.bufferbloatMs) + " ms",
                     icon: "gauge.with.dots.needle.67percent", level: Rating.bloatLevel(result.bufferbloatMs))
            Divider().overlay(.white.opacity(0.07))
            InfoLine(title: "Aussetzer", value: String(format: "%.1f %%", result.dropoutPercent),
                     icon: "exclamationmark.triangle", level: Rating.dropoutLevel(result.dropoutPercent))
            if let dns = result.dnsMs {
                Divider().overlay(.white.opacity(0.07))
                InfoLine(title: "DNS-Antwort", value: Fmt.ms(dns) + " ms", icon: "globe")
            }
            if let s = result.signalPercent {
                Divider().overlay(.white.opacity(0.07))
                InfoLine(title: "WLAN-Signal", value: "\(s) %", icon: "wifi", level: Rating.signalLevel(s))
            }
            if let server = result.server {
                Divider().overlay(.white.opacity(0.07))
                InfoLine(title: "Testserver", value: server, icon: "server.rack")
            }
            Divider().overlay(.white.opacity(0.07))
            InfoLine(title: "Verbraucht", value: String(format: "%.0f MB", result.dataUsedMB),
                     icon: "arrow.up.arrow.down.circle")
        }
        .glass(radius: 20, padding: 14)
    }
}

// MARK: - Erklärungen

struct ExplainSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let items: [(String, String, String)] = [
        ("arrow.down", "Download", "Wie schnell Daten zu dir kommen: Streams, Downloads, Webseiten. 50 Mbit/s reichen für einen Haushalt mit 4K-Streaming."),
        ("arrow.up", "Upload", "Wie schnell du Daten wegschickst: Videocalls, Fotos in die Cloud, selbst streamen."),
        ("bolt.horizontal.fill", "Ping", "Die Reaktionszeit. Für Shooter wichtiger als hohe Mbit/s. Unter 20 ms top, über 60 ms merkst du es."),
        ("waveform.path", "Jitter", "Wie gleichmäßig der Ping ist. Schwankt er stark, ruckeln Spiele und Calls, auch wenn der Ping gut aussieht."),
        ("gauge.with.dots.needle.67percent", "Ping unter Last", "Steigt der Ping stark, sobald jemand etwas herunterlädt, heißt das „Bufferbloat“. Abhilfe: im Netz-Tab die Priorisierung für dein Gerät einschalten."),
        ("exclamationmark.triangle", "Aussetzer", "Messungen, die verloren gingen oder ewig brauchten. Schon 2 % sorgen für spürbare Hänger."),
        ("globe", "DNS-Antwort", "Wie schnell Adressen aufgelöst werden. Merkst du beim Öffnen von Seiten. Der DNS-Turbo im Netz-Tab findet den schnellsten Server."),
        ("wifi", "WLAN-Signal", "Kommt direkt von deiner FRITZ!Box. Ab 70 % ist alles top, unter 40 % wird es wackelig. Im WLAN-Tab findest du die beste Stelle im Raum."),
        ("antenna.radiowaves.left.and.right", "Mobilfunk", "Im Datensparmodus wird bei Mobilfunk weniger Datenvolumen verbraucht (ca. 50–150 MB statt bis zu 1 GB).")
    ]

    var body: some View {
        NavigationStack {
            List(items.indices, id: \.self) { i in
                let item = items[i]
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: item.0).font(.subheadline).foregroundStyle(Neon.cyan).frame(width: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.1).font(.subheadline.weight(.semibold))
                        Text(item.2).font(.caption).foregroundStyle(.secondary)
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
