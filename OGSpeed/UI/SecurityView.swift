import SwiftUI

/// Warnbanner – steht ganz oben im Ergebnis, wenn etwas gefunden wurde
struct SecurityBanner: View {
    let findings: [SecurityFinding]

    var body: some View {
        let problems = findings.problems
        if !problems.isEmpty {
            let danger = problems.contains { $0.severity >= 3 }
            let color = danger ? Neon.red : Neon.yellow
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: danger ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.title3).foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(danger ? "Gefahr in diesem Netzwerk" : "Achtung in diesem Netzwerk")
                            .font(.subheadline.weight(.heavy)).foregroundStyle(color)
                        Text(problems.map(\.title).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                ForEach(problems.prefix(2)) { p in
                    if let advice = p.advice {
                        Label(advice, systemImage: "arrow.turn.down.right")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(color.opacity(0.55), lineWidth: 1.5))
        }
    }
}

/// Abschnitt mit allen Befunden
struct SecuritySection: View {
    let findings: [SecurityFinding]

    var body: some View {
        if !findings.isEmpty {
            let head = findings.headline
            VStack(spacing: 10) {
                SectionLabel(title: "Sicherheits-Check", trailing: "\(findings.count) Punkte")
                HStack(alignment: .top, spacing: 12) {
                    AmpelDot(level: head.0, size: 12).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(head.1).font(.subheadline.weight(.bold)).foregroundStyle(head.0.color)
                        Text(head.2).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .glass(radius: 20, padding: 14)

                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { i, f in
                        SecurityRow(finding: f)
                        if i < sorted.count - 1 { Divider().overlay(.white.opacity(0.07)) }
                    }
                }
                .glass(radius: 20, padding: 14)
            }
        }
    }

    /// Probleme zuerst
    private var sorted: [SecurityFinding] {
        findings.sorted { $0.severity > $1.severity }
    }
}

struct SecurityRow: View {
    let finding: SecurityFinding
    @State private var open = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Image(systemName: finding.icon).font(.caption)
                        .foregroundStyle(finding.level.color).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(finding.title).font(.subheadline)
                        if finding.severity >= 2 {
                            Text(finding.severityLabel).font(.caption2.weight(.bold))
                                .foregroundStyle(finding.level.color)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(finding.value).font(.subheadline.weight(.semibold))
                        .foregroundStyle(finding.severity >= 2 ? finding.level.color : .primary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary).rotationEffect(.degrees(open ? 180 : 0))
                }
                if open {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(finding.detail).font(.caption).foregroundStyle(.secondary)
                        if let a = finding.advice {
                            Label(a, systemImage: "wrench.and.screwdriver.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(Neon.cyan)
                        }
                    }
                    .padding(.leading, 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Sicherheits-Labor: der große Check ohne Speedtest
struct NetworkSecurityView: View {
    @Environment(NetworkMonitor.self) private var network
    @State private var report: DeepReport?
    @State private var running = false
    @State private var step = 0
    @State private var openCategory: ScanCategory?

    private let steps = ["Zertifikate prüfen", "DNS testen", "Router abklopfen", "Geräte suchen",
                         "IP-Ruf abfragen", "Uhrzeit & iOS prüfen"]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let r = report {
                    scoreCard(r)
                    SecurityBanner(findings: r.findings)
                } else if !running {
                    introCard
                }

                if running { progressCard }

                if let r = report {
                    ForEach(ScanCategory.allCases) { c in
                        let list = r.findings(in: c)
                        if !list.isEmpty { categoryCard(c, list) }
                    }
                    if !r.routerPorts.isEmpty || r.routerHost != nil { portsCard(r) }
                    if !r.services.isEmpty { devicesCard(r.services) }
                    factsCard(r.facts)
                    legendCard
                }

                Button {
                    Task { await run() }
                } label: {
                    Label(report == nil ? "Sicherheits-Labor starten" : "Erneut prüfen", systemImage: "shield.checkered")
                }
                .buttonStyle(NeonButtonStyle(colors: [Neon.green, Neon.cyan]))
                .disabled(running)

                if let r = report {
                    Text("Geprüft \(Fmt.relative(r.date)) · \(r.findings.count) Prüfungen · \(network.summary)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                limitsCard
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle("Sicherheits-Labor")
        .navigationBarTitleDisplayMode(.inline)
        .task { if report == nil { await run() } }
        .refreshable { await run() }
    }

    // MARK: Ablauf

    private func run() async {
        running = true
        step = 0
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                step = (step + 1) % steps.count
            }
        }
        defer { running = false; ticker.cancel() }
        let r = await DeepScan.run(connection: network.kind, identity: NetDetector.shared.identity)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { report = r }
        if r.findings.worstSeverity >= 3 {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } else if r.findings.worstSeverity >= 2 {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: Karten

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Was hier geprüft wird", systemImage: "shield.lefthalf.filled").font(.headline)
            Text("Über 25 Prüfungen in einem Durchgang: Liest jemand mit? Wird DNS gefälscht? Welche Türen hat dein Router offen? Wer ist noch im Netz? Steht deine IP auf einer Sperrliste? Ist dein iPhone aktuell? Funktioniert im WLAN, im Mobilfunk und am Hotspot. Jedes Ergebnis lässt sich antippen und wird in Alltagssprache erklärt.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    private var progressCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Labor läuft …").font(.subheadline.weight(.semibold))
                Text(steps[step]).font(.caption).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .glass()
    }

    private func scoreCard(_ r: DeepReport) -> some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(r.score) / 100)
                    .stroke(r.scoreLevel.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .neonGlow(r.scoreLevel.color, radius: 8)
                VStack(spacing: 0) {
                    Text("\(r.score)").font(.system(size: 34, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                    Text("von 100").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 6) {
                Text(r.scoreText).font(.headline).foregroundStyle(r.scoreLevel.color)
                let danger = r.findings.filter { $0.severity >= 3 }.count
                let warn = r.findings.filter { $0.severity == 2 }.count
                let hint = r.findings.filter { $0.severity == 1 }.count
                let ok = r.findings.filter { $0.severity == 0 }.count
                countRow(Neon.red, danger, "Gefahr")
                countRow(Neon.yellow, warn, "Warnung")
                countRow(Neon.cyan, hint, "Hinweis")
                countRow(Neon.green, ok, "in Ordnung")
            }
            Spacer(minLength: 0)
        }
        .glass()
    }

    private func countRow(_ c: Color, _ n: Int, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text("\(n) \(label)").font(.caption).foregroundStyle(n == 0 && label != "in Ordnung" ? .secondary : .primary)
        }
    }

    private func categoryCard(_ c: ScanCategory, _ list: [SecurityFinding]) -> some View {
        let worst = list.map(\.severity).max() ?? 0
        let level: Level = worst >= 3 ? .bad : worst == 2 ? .ok : .great
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: c.icon).foregroundStyle(level.color).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.subheadline.weight(.bold))
                    Text(c.intro).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                AmpelDot(level: level, size: 10)
            }
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, f in
                    SecurityRow(finding: f)
                    if i < list.count - 1 { Divider().overlay(.white.opacity(0.07)) }
                }
            }
        }
        .glass(radius: 20, padding: 14)
    }

    private func portsCard(_ r: DeepReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Dienste am Router", trailing: r.routerHost)
            if r.routerPorts.isEmpty {
                Text("Keiner der 16 geprüften Dienste antwortet. Der Router bietet im Netz keine Angriffsfläche.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(r.routerPorts) { p in
                ExplainRow(icon: p.severity >= 2 ? "exclamationmark.triangle.fill" : "circle.fill",
                           color: p.severity >= 3 ? Neon.red : p.severity == 2 ? Neon.yellow : p.severity == 1 ? Neon.cyan : Neon.green,
                           label: "Port \(p.port)", value: p.name, explain: p.explain)
            }
            Text("Ein offener Port ist eine Tür, an der ein Programm wartet. Je weniger Türen, desto weniger Angriffsfläche. Geprüft wird nur dein eigener Router, nichts außerhalb deines Netzes.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .glass(radius: 20, padding: 14)
    }

    private func devicesCard(_ services: [NetService]) -> some View {
        let grouped = Dictionary(grouping: services, by: \.name).sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Geräte, die sich zeigen", trailing: "\(grouped.count)")
            ForEach(grouped, id: \.key) { entry in
                let name = entry.key
                let kinds = entry.value.compactMap { BonjourScan.kind(for: $0.type) }
                let worst = kinds.map(\.severity).max() ?? 0
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: kinds.first?.icon ?? "questionmark.square")
                        .foregroundStyle(worst >= 2 ? Neon.yellow : Neon.cyan).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.subheadline.weight(.semibold))
                        Text(Array(Set(kinds.map(\.label))).sorted().joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(worst >= 2 ? AnyShapeStyle(Neon.yellow) : AnyShapeStyle(.secondary))
                    }
                    Spacer(minLength: 0)
                }
            }
            Text("Diese Geräte melden sich per Bonjour mit Namen und Diensten. Kennst du eins nicht, gehört es vielleicht einem Nachbarn oder Gast im selben WLAN.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .glass(radius: 20, padding: 14)
    }

    private func factsCard(_ facts: [ScanFact]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Messwerte erklärt", trailing: "antippen")
            ForEach(facts) { f in
                ExplainRow(icon: f.icon, color: Neon.cyan, label: f.label, value: f.value, explain: f.explain)
            }
        }
        .glass(radius: 20, padding: 14)
    }

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("So liest du das Ergebnis", systemImage: "questionmark.circle").font(.subheadline.weight(.semibold))
            legend(Neon.green, "In Ordnung", "Geprüft, alles so, wie es sein soll.")
            legend(Neon.cyan, "Hinweis", "Kein Angriff, aber eine Schutzschicht fehlt. Beheben, wenn es leicht geht.")
            legend(Neon.yellow, "Warnung", "Echte Schwachstelle. Mit dem Tipp unter dem Befund beheben.")
            legend(Neon.red, "Gefahr", "Hier liest oder greift jemand ein. Sofort das Netz verlassen oder VPN einschalten.")
            Text("Die Punktzahl startet bei 100. Jede Gefahr kostet 25 Punkte, jede Warnung 10, jeder Hinweis 2.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    private func legend(_ c: Color, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(c).frame(width: 8, height: 8).padding(.top, 5)
            (Text(t + ": ").bold() + Text(d)).font(.caption)
        }
    }

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Grenzen", systemImage: "info.circle").font(.subheadline.weight(.semibold))
            Text("iOS erlaubt Apps keinen Blick auf andere Apps, installierte Profile oder den Funkverkehr selbst. WLAN-Verschlüsselung, Portfreigaben und neue Geräte prüft OGSpeed deshalb über die FRITZ!Box. Die Geräte-Suche braucht die Erlaubnis „Lokales Netzwerk“ und klappt nicht, wenn OGSpeed in LiveContainer läuft.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }
}

/// Zeile mit Wert, die beim Antippen ihre Erklärung zeigt
struct ExplainRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String
    let explain: String
    @State private var open = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: icon).font(.caption).foregroundStyle(color).frame(width: 20)
                    Text(label).font(.subheadline)
                    Spacer(minLength: 8)
                    Text(value).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary).rotationEffect(.degrees(open ? 180 : 0))
                }
                if open {
                    Text(explain).font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 30)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
