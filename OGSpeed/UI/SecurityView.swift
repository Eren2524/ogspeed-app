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

/// Eigener Bildschirm: Check ohne Speedtest
struct NetworkSecurityView: View {
    @Environment(NetworkMonitor.self) private var network
    @Environment(HistoryStore.self) private var history
    @State private var findings: [SecurityFinding] = []
    @State private var running = false
    @State private var checkedAt: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Was hier geprüft wird", systemImage: "shield.lefthalf.filled")
                        .font(.headline)
                    Text("OGSpeed sieht nach, ob in diesem Netzwerk jemand mitlesen, dich umleiten oder sich einklinken kann – und ob dein Heimnetz offene Türen hat. Derselbe Check läuft automatisch bei jedem Speedtest mit.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass()

                SecurityBanner(findings: findings)

                if running {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Prüfe Netzwerk …").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                    .glass()
                }

                SecuritySection(findings: findings)

                Button {
                    Task { await run() }
                } label: {
                    Label(checkedAt == nil ? "Netzwerk prüfen" : "Erneut prüfen", systemImage: "shield.checkered")
                }
                .buttonStyle(NeonButtonStyle(colors: [Neon.green, Neon.cyan]))
                .disabled(running)

                if let at = checkedAt {
                    Text("Geprüft \(Fmt.relative(at))").font(.caption2).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Grenzen", systemImage: "info.circle").font(.subheadline.weight(.semibold))
                    Text("Offenes WLAN, Portfreigaben und fremde Geräte kann OGSpeed nur mit verbundener FRITZ!Box prüfen – iOS gibt Apps diese Angaben nicht heraus. Alles andere funktioniert in jedem Netz, auch im Mobilfunk.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass()
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle("Netzwerk-Sicherheit")
        .navigationBarTitleDisplayMode(.inline)
        .task { if findings.isEmpty { await run() } }
        .refreshable { await run() }
    }

    private func run() async {
        running = true
        defer { running = false }
        findings = await SecurityScan.run(connection: network.kind, identity: NetDetector.shared.identity)
        checkedAt = Date()
        if findings.worstSeverity >= 3 {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } else if findings.worstSeverity >= 2 {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
