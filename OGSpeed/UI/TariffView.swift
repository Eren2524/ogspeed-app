import SwiftUI
import UIKit

struct TariffCheck {
    let tests: [SpeedResult]
    let max: Double, normal: Double, min: Double

    var maxReached: Bool { tests.contains { $0.downMbps >= max * 0.9 } }
    var normalShare: Double {
        guard !tests.isEmpty, normal > 0 else { return 0 }
        return Double(tests.filter { $0.downMbps >= normal }.count) / Double(tests.count)
    }
    var belowMin: [SpeedResult] { min > 0 ? tests.filter { $0.downMbps < min } : [] }
    var average: Double { tests.isEmpty ? 0 : tests.map(\.downMbps).reduce(0, +) / Double(tests.count) }
    var bestValue: Double { tests.map(\.downMbps).max() ?? 0 }

    var level: Level {
        if tests.count < 3 { return .ok }
        if !maxReached || normalShare < 0.9 || !belowMin.isEmpty { return .bad }
        return average >= max * 0.9 ? .great : .good
    }
}

struct TariffView: View {
    @Environment(HistoryStore.self) private var history
    @AppStorage(K.tProvider) private var provider = "1&1"
    @AppStorage(K.tDownMax) private var downMax = 0.0
    @AppStorage(K.tDownNormal) private var downNormal = 0.0
    @AppStorage(K.tDownMin) private var downMin = 0.0
    @AppStorage(K.tUpMax) private var upMax = 0.0
    @AppStorage(K.mProvider) private var mProvider = ""
    @AppStorage(K.mDownMax) private var mDownMax = 0.0
    @State private var line: FritzLine?
    @State private var pdfURL: URL?

    private var wifiTests: [SpeedResult] {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return history.results.filter { $0.connection == .wifi && $0.date >= since }
    }
    private var mobileTests: [SpeedResult] { history.results.filter { $0.connection == .cellular }.prefix(30).map { $0 } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                inputCard
                if downMax > 0 { resultCard }
                if mDownMax > 0 { mobileCard }
                proofCard
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle("Tarif-Check")
        .task { line = try? await FritzClient.fromPrefs()?.line() }
    }

    private func field(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .padding(8)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            Text("Mbit/s").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dein Festnetz-Tarif", systemImage: "house.fill").font(.headline)
            Text("Die drei Werte stehen in deinem Vertrag bzw. im „Produktinformationsblatt“ von 1&1 (Kundencenter › Verträge).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Anbieter").font(.subheadline)
                Spacer()
                TextField("1&1", text: $provider).multilineTextAlignment(.trailing).frame(width: 140)
            }
            field("Maximal ↓", $downMax)
            field("Normalerweise ↓", $downNormal)
            field("Minimal ↓", $downMin)
            field("Maximal ↑", $upMax)
            if let line, line.downMbps > 0 {
                Divider().overlay(.white.opacity(0.1))
                HStack(alignment: .top) {
                    Image(systemName: "wifi.router.fill").foregroundStyle(Neon.cyan)
                    Text("Deine FRITZ!Box ist mit **\(Fmt.mbps(line.downMbps)) ↓ / \(Fmt.mbps(line.upMbps)) ↑ Mbit/s** mit dem Netz verbunden. Mehr kann im Haus nicht ankommen.")
                        .font(.caption)
                }
                if downMax == 0 {
                    Button("Werte als Maximum übernehmen") { downMax = (line.downMbps).rounded(); upMax = (line.upMbps).rounded() }
                        .font(.caption.weight(.semibold))
                }
            }
            Divider().overlay(.white.opacity(0.1))
            Label("Mobilfunk-Tarif (optional)", systemImage: "antenna.radiowaves.left.and.right").font(.subheadline.weight(.semibold))
            HStack {
                Text("Anbieter").font(.subheadline)
                Spacer()
                TextField("z. B. 1&1, Telekom", text: $mProvider).multilineTextAlignment(.trailing).frame(width: 160)
            }
            field("Maximal ↓", $mDownMax)
        }
        .glass()
    }

    private var resultCard: some View {
        let c = TariffCheck(tests: wifiTests, max: downMax, normal: downNormal, min: downMin)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ergebnis (WLAN, letzte 30 Tage)").font(.headline)
                Spacer()
                LevelPill(level: c.level)
            }
            if c.tests.count < 3 {
                Text("Noch zu wenig Messungen (\(c.tests.count)). Mach über ein paar Tage verteilt mindestens 10 Tests – am besten nah am Router.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                checkRow(c.maxReached, "Maximum mind. einmal zu 90 % erreicht",
                         "Bester Wert \(Fmt.mbps(c.bestValue)) von \(Fmt.mbps(downMax)) Mbit/s")
                if downNormal > 0 {
                    checkRow(c.normalShare >= 0.9, "„Normalerweise“ in 90 % der Tests erreicht",
                             "Erreicht in \(Int(c.normalShare * 100)) % der \(c.tests.count) Tests")
                }
                if downMin > 0 {
                    checkRow(c.belowMin.isEmpty, "Minimum nie unterschritten",
                             c.belowMin.isEmpty ? "Alles über \(Fmt.mbps(downMin)) Mbit/s" : "\(c.belowMin.count)× darunter")
                }
                Text("Ø \(Fmt.mbps(c.average)) Mbit/s – das sind \(Int(c.average / max(downMax, 1) * 100)) % von dem, was du bezahlst.")
                    .font(.subheadline.weight(.semibold))
                if c.level == .bad {
                    Text("Sieht nach zu wenig Leistung aus. Prüf erst, ob es am WLAN liegt (nah am Router messen, 5 GHz). Bleibt es so, hast du ein Recht auf Minderung oder Sonderkündigung.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                pdfURL = ReportPDF.make(tests: wifiTests, provider: provider, max: downMax, normal: downNormal, min: downMin, line: line)
            } label: {
                Label("Protokoll als PDF erstellen", systemImage: "doc.richtext")
            }
            .buttonStyle(GlassButtonStyle())
            if let pdfURL {
                ShareLink(item: pdfURL) {
                    Label("PDF teilen oder speichern", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(NeonButtonStyle())
            }
        }
        .glass()
    }

    private var mobileCard: some View {
        let avg = mobileTests.isEmpty ? 0 : mobileTests.map(\.downMbps).reduce(0, +) / Double(mobileTests.count)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Mobilfunk \(mProvider)").font(.headline)
            if mobileTests.isEmpty {
                Text("Noch keine Tests im Mobilfunk.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Ø \(Fmt.mbps(avg)) Mbit/s aus \(mobileTests.count) Tests – \(Int(avg / max(mDownMax, 1) * 100)) % vom Tarif-Maximum.")
                    .font(.subheadline)
                Text("Im Mobilfunk schwankt das Tempo je nach Ort und Auslastung stark. Ein fester Mindestwert ist hier nicht einklagbar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    private var proofCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Gut zu wissen", systemImage: "info.circle.fill").font(.headline)
            Text("Das OGSpeed-Protokoll ist ein starker Hinweis für ein Gespräch mit deinem Anbieter. Rechtlich anerkannt als Nachweis ist aber nur die kostenlose „Breitbandmessung“ der Bundesnetzagentur am PC mit LAN-Kabel (breitbandmessung.de) – 30 Messungen an 3 Tagen.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    private func checkRow(_ ok: Bool, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? Neon.green : Neon.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - PDF

enum ReportPDF {
    static func make(tests: [SpeedResult], provider: String, max: Double, normal: Double, min: Double, line: FritzLine?) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OGSpeed-Protokoll-\(Date().formatted(.iso8601.year().month().day())).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let check = TariffCheck(tests: tests, max: max, normal: normal, min: min)
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "dd.MM.yyyy HH:mm"

        func draw(_ s: String, _ font: UIFont, _ color: UIColor = .black, at p: CGPoint, width: CGFloat = 515) -> CGFloat {
            let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
            let r = attr.boundingRect(with: CGSize(width: width, height: 1000), options: [.usesLineFragmentOrigin], context: nil)
            attr.draw(with: CGRect(origin: p, size: CGSize(width: width, height: r.height)), options: [.usesLineFragmentOrigin], context: nil)
            return r.height
        }

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y: CGFloat = 40
                y += draw("OGSpeed – Messprotokoll Internetgeschwindigkeit", .boldSystemFont(ofSize: 18), at: CGPoint(x: 40, y: y)) + 6
                y += draw("Erstellt am \(df.string(from: Date())) · Anbieter: \(provider) · Messungen per WLAN mit iPhone gegen Cloudflare-Speedtest-Server",
                          .systemFont(ofSize: 9), .darkGray, at: CGPoint(x: 40, y: y)) + 14
                var lines = [
                    "Vertraglich: maximal \(Fmt.mbps(max)) / normalerweise \(Fmt.mbps(normal)) / minimal \(Fmt.mbps(min)) Mbit/s im Download",
                    "Anzahl Messungen: \(tests.count) · Durchschnitt: \(Fmt.mbps(check.average)) Mbit/s · Bester Wert: \(Fmt.mbps(check.bestValue)) Mbit/s",
                    "90 % des Maximums erreicht: \(check.maxReached ? "ja" : "NEIN") · Normalwert in \(Int(check.normalShare * 100)) % der Messungen erreicht · Minimum \(check.belowMin.count)× unterschritten"
                ]
                if let line, line.downMbps > 0 {
                    lines.append("Synchronisation der FRITZ!Box (Leitung): \(Fmt.mbps(line.downMbps)) ↓ / \(Fmt.mbps(line.upMbps)) ↑ Mbit/s")
                }
                for l in lines { y += draw(l, .systemFont(ofSize: 10), at: CGPoint(x: 40, y: y)) + 4 }
                y += 12

                let cols: [(String, CGFloat)] = [("Datum", 40), ("Download", 150), ("Upload", 225), ("Ping", 295), ("Jitter", 350),
                                                  ("Signal", 405), ("Band", 455), ("Server", 505)]
                func header() {
                    for c in cols { _ = draw(c.0, .boldSystemFont(ofSize: 9), at: CGPoint(x: c.1, y: y), width: 100) }
                    y += 16
                }
                header()
                for t in tests {
                    if y > 800 { ctx.beginPage(); y = 40; header() }
                    let vals = [df.string(from: t.date), "\(Fmt.mbps(t.downMbps)) Mbit/s", "\(Fmt.mbps(t.upMbps)) Mbit/s",
                                "\(Fmt.ms(t.pingMs)) ms", "\(Fmt.ms(t.jitterMs)) ms", t.signalPercent.map { "\($0) %" } ?? "–",
                                t.band ?? "–", String((t.server ?? "–").prefix(10))]
                    let low = min > 0 && t.downMbps < min
                    for (i, c) in cols.enumerated() {
                        _ = draw(vals[i], .monospacedDigitSystemFont(ofSize: 8.5, weight: .regular), low && i == 1 ? .systemRed : .black,
                                 at: CGPoint(x: c.1, y: y), width: 110)
                    }
                    y += 13
                }
                y += 16
                if y > 780 { ctx.beginPage(); y = 40 }
                _ = draw("Hinweis: Messungen per WLAN können durch das Heimnetz begrenzt sein. Als rechtsverbindlicher Nachweis gilt die Breitbandmessung der Bundesnetzagentur (breitbandmessung.de).",
                         .italicSystemFont(ofSize: 8), .darkGray, at: CGPoint(x: 40, y: y))
            }
            return url
        } catch {
            return nil
        }
    }
}
