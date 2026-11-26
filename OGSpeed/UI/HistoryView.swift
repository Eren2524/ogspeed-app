import SwiftUI
import Charts

struct HistoryView: View {
    @Environment(HistoryStore.self) private var history
    @State private var filter: ConnectionKind? = nil
    @State private var metric = 0   // 0 Download, 1 Upload, 2 Ping
    @State private var confirmClear = false

    private var items: [SpeedResult] {
        guard let filter else { return history.results }
        return history.results.filter { $0.connection == filter }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Verbindung", selection: $filter) {
                        Text("Alle").tag(ConnectionKind?.none)
                        Text("WLAN").tag(ConnectionKind?.some(.wifi))
                        Text("Mobilfunk").tag(ConnectionKind?.some(.cellular))
                    }
                    .pickerStyle(.segmented)

                    if items.isEmpty {
                        ContentUnavailableView("Noch keine Tests", systemImage: "chart.xyaxis.line",
                                               description: Text("Starte einen Speedtest – jedes Ergebnis landet hier."))
                            .glass()
                    } else {
                        summaryCard
                        chartCard
                        hourCard
                        listCard
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(NeonBackground())
            .navigationTitle("Verlauf")
            .toolbar {
                if !history.results.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Verlauf löschen", role: .destructive) { confirmClear = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .confirmationDialog("Alle Tests löschen?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Alles löschen", role: .destructive) { history.clear() }
            }
        }
    }

    private func avg(_ f: (SpeedResult) -> Double) -> Double {
        items.isEmpty ? 0 : items.map(f).reduce(0, +) / Double(items.count)
    }

    private var summaryCard: some View {
        HStack(spacing: 10) {
            StatTile(title: "Ø Download", value: Fmt.mbps(avg(\.downMbps)), unit: "Mbit/s", icon: "arrow.down")
            StatTile(title: "Ø Upload", value: Fmt.mbps(avg(\.upMbps)), unit: "Mbit/s", icon: "arrow.up")
            StatTile(title: "Ø Ping", value: Fmt.ms(avg(\.pingMs)), unit: "ms", icon: "bolt.horizontal.fill")
        }
    }

    private func value(_ r: SpeedResult) -> Double {
        metric == 0 ? r.downMbps : metric == 1 ? r.upMbps : r.pingMs
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Wert", selection: $metric) {
                Text("Download").tag(0); Text("Upload").tag(1); Text("Ping").tag(2)
            }
            .pickerStyle(.segmented)
            Chart(Array(items.prefix(60).reversed())) { r in
                AreaMark(x: .value("Zeit", r.date), y: .value("Wert", value(r)))
                    .foregroundStyle(LinearGradient(colors: [Neon.cyan.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Zeit", r.date), y: .value("Wert", value(r)))
                    .foregroundStyle(LinearGradient(colors: [Neon.cyan, Neon.magenta], startPoint: .leading, endPoint: .trailing))
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Zeit", r.date), y: .value("Wert", value(r)))
                    .foregroundStyle(Rating.overall(r).level.color)
                    .symbolSize(28)
            }
            .chartYAxisLabel(metric == 2 ? "ms" : "Mbit/s")
            .frame(height: 200)
        }
        .glass()
    }

    /// Durchschnitt je Tageszeit – wann ist das Netz am schnellsten?
    private var hourBuckets: [(String, Double, Int)] {
        let cal = Calendar.current
        let slots: [(String, ClosedRange<Int>)] = [("Nacht", 0...5), ("Morgen", 6...10), ("Mittag", 11...14),
                                                    ("Nachmittag", 15...17), ("Abend", 18...21), ("Spät", 22...23)]
        return slots.compactMap { name, range in
            let list = items.filter { range.contains(cal.component(.hour, from: $0.date)) }
            guard !list.isEmpty else { return nil }
            return (name, list.map(\.downMbps).reduce(0, +) / Double(list.count), list.count)
        }
    }

    private var hourCard: some View {
        let buckets = hourBuckets
        let best = buckets.max { $0.1 < $1.1 }
        let worst = buckets.min { $0.1 < $1.1 }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Wann ist dein Netz am schnellsten?").font(.headline)
            Chart(buckets, id: \.0) { b in
                BarMark(x: .value("Tageszeit", b.0), y: .value("Mbit/s", b.1))
                    .foregroundStyle(b.0 == best?.0 ? Neon.green.gradient : Neon.purple.gradient)
                    .cornerRadius(8)
            }
            .frame(height: 150)
            if let best, let worst, buckets.count > 1 {
                Text("Am schnellsten: **\(best.0)** (Ø \(Fmt.mbps(best.1)) Mbit/s). Am langsamsten: **\(worst.0)** (Ø \(Fmt.mbps(worst.1)) Mbit/s). Große Downloads und Updates am besten \(best.0.lowercased()) starten.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Teste zu verschiedenen Tageszeiten, dann siehst du hier, wann es am schnellsten ist.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .glass()
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Alle Tests").font(.headline).padding(.bottom, 6)
            ForEach(items.prefix(100)) { r in
                NavigationLink {
                    ScrollView { ResultSections(result: r).padding() }
                        .background(NeonBackground())
                        .navigationTitle(r.date.formatted(date: .abbreviated, time: .shortened))
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack(spacing: 12) {
                        AmpelDot(level: Rating.overall(r).level, size: 10)
                        Image(systemName: r.connection.icon).foregroundStyle(.secondary).frame(width: 22)
                        if r.vpnActive {
                            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Neon.green)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
                            Text([r.networkName, r.radio, r.band].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Fmt.mbps(r.downMbps)) ↓").font(.subheadline.weight(.bold).monospacedDigit())
                            Text("\(Fmt.mbps(r.upMbps)) ↑ · \(Fmt.ms(r.pingMs)) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Löschen", systemImage: "trash", role: .destructive) { history.delete([r.id]) }
                }
                Divider().overlay(.white.opacity(0.06))
            }
        }
        .glass()
    }
}
