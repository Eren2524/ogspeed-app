import SwiftUI

struct VPNView: View {
    @Environment(NetworkMonitor.self) private var network
    @Environment(HistoryStore.self) private var history
    @State private var checker = VPNChecker()
    @State private var timer: Timer?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                if checker.checkedAt != nil { findingsList }
                speedComparison
                SectionLabel(title: "Einrichten")
                NavigationLink { NordSetupView() } label: { setupRow(
                    icon: "globe.badge.chevron.backward", color: Neon.cyan,
                    title: "NordVPN (dein Abo)",
                    sub: "Anderes Land, Anbieter sieht nichts mehr, auch über mobile Daten") }
                    .buttonStyle(.plain)
                NavigationLink { HomeVPNSetupView() } label: { setupRow(
                    icon: "house.fill", color: Neon.magenta,
                    title: "VPN ins eigene Heimnetz",
                    sub: "Kostenlos über die FRITZ!Box – PS5, NAS und Smart Home von überall") }
                    .buttonStyle(.plain)
                limitsCard
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle("VPN")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checker.refreshStatus()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                Task { @MainActor in checker.refreshStatus() }
            }
        }
        .onDisappear { timer?.invalidate() }
        .refreshable { await checker.run(connection: network.kind) }
    }

    // MARK: Status

    private var statusCard: some View {
        let v = checker.verdict
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(checker.active ? Neon.green.opacity(0.16) : Color.white.opacity(0.07))
                        .frame(width: 62, height: 62)
                    Image(systemName: checker.active ? "lock.fill" : "lock.open.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(checker.active ? Neon.green : .secondary)
                }
                .neonGlow(checker.active ? Neon.green : .clear, radius: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(checker.active ? "VPN aktiv" : "Kein VPN")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(checker.active ? Neon.green : .primary)
                    Text(checker.active ? VPNDetect.kindLabel : "Tunnel in der NordVPN- oder WireGuard-App starten")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if checker.checkedAt != nil {
                HStack(alignment: .top, spacing: 10) {
                    AmpelDot(level: v.0, size: 10).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.1).font(.subheadline.weight(.bold)).foregroundStyle(v.0.color)
                        Text(v.2).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                Task { await checker.run(connection: network.kind) }
            } label: {
                HStack {
                    if checker.running { ProgressView().tint(.black) }
                    Text(checker.running ? "Prüfe …" : (checker.checkedAt == nil ? "Jetzt prüfen" : "Erneut prüfen"))
                }
            }
            .buttonStyle(NeonButtonStyle(colors: checker.active ? [Neon.green, Neon.lime] : [Neon.cyan, Neon.magenta]))
            .disabled(checker.running)

            if let at = checker.checkedAt {
                Text("Geprüft \(Fmt.relative(at))").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    // MARK: Befunde

    private var findingsList: some View {
        VStack(spacing: 10) {
            SectionLabel(title: "Prüfbericht")
            VStack(spacing: 0) {
                ForEach(Array(checker.findings.enumerated()), id: \.element.id) { i, f in
                    FindingRow(finding: f)
                    if i < checker.findings.count - 1 {
                        Divider().overlay(.white.opacity(0.07))
                    }
                }
            }
            .glass(radius: 20, padding: 14)
        }
    }

    // MARK: Tempo mit und ohne VPN

    @ViewBuilder
    private var speedComparison: some View {
        let withVPN = history.results.filter { $0.vpnActive }
        let without = history.results.filter { !$0.vpnActive }
        if !withVPN.isEmpty && !without.isEmpty {
            let a = avg(withVPN), b = avg(without)
            let loss = b.down > 0.1 ? (1 - a.down / b.down) * 100 : 0
            VStack(spacing: 10) {
                SectionLabel(title: "Tempo mit und ohne VPN")
                VStack(spacing: 0) {
                    InfoLine(title: "Mit VPN (\(withVPN.count) Tests)",
                             value: "\(Fmt.mbps(a.down)) Mbit/s · \(Fmt.ms(a.ping)) ms", icon: "lock.fill")
                    Divider().overlay(.white.opacity(0.07))
                    InfoLine(title: "Ohne VPN (\(without.count) Tests)",
                             value: "\(Fmt.mbps(b.down)) Mbit/s · \(Fmt.ms(b.ping)) ms", icon: "lock.open")
                    Divider().overlay(.white.opacity(0.07))
                    InfoLine(title: "Tempoverlust durch VPN", value: "\(Int(max(0, loss))) %",
                             icon: "arrow.down.right", level: lossLevel(loss))
                }
                .glass(radius: 20, padding: 14)
                Text("10 bis 30 Prozent Verlust sind normal, der Ping steigt um die Entfernung zum Server. Wähle einen Server in Deutschland oder den Niederlanden, wenn dir Tempo wichtiger ist als der Standort.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Tempo-Vergleich", systemImage: "chart.bar.fill").font(.subheadline.weight(.semibold))
                Text("Mach je einen Speedtest mit und ohne VPN. OGSpeed merkt sich automatisch, welcher Test durch den Tunnel lief, und zeigt dir hier den Unterschied.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass()
        }
    }

    private func avg(_ list: [SpeedResult]) -> (down: Double, ping: Double) {
        let n = Double(list.count)
        return (list.map(\.downMbps).reduce(0, +) / n, list.map(\.pingMs).reduce(0, +) / n)
    }

    private func lossLevel(_ l: Double) -> Level {
        if l <= 15 { return .great }
        if l <= 35 { return .good }
        if l <= 60 { return .ok }
        return .bad
    }

    private func setupRow(icon: String, color: Color, title: String, sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(sub).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .glass(radius: 20, padding: 13)
    }

    private var limitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Warum der Tunnel nicht in OGSpeed läuft", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
            Text("Apple erlaubt einen VPN-Tunnel nur Apps mit der Berechtigung „Network Extension“. Die gibt es ausschließlich mit einem kostenpflichtigen Entwickler-Konto, und sie lässt sich beim Sideloading nicht mitsignieren. Deshalb fährt den Tunnel die NordVPN- oder WireGuard-App, und OGSpeed prüft, misst und richtet ein.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }
}

struct FindingRow: View {
    let finding: VPNFinding
    @State private var open = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: finding.icon).font(.caption)
                        .foregroundStyle(finding.level.color).frame(width: 20)
                    Text(finding.title).font(.subheadline)
                    Spacer(minLength: 8)
                    Text(finding.value).font(.subheadline.weight(.semibold))
                        .foregroundStyle(finding.level == .bad ? finding.level.color : .primary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                if open {
                    Text(finding.detail).font(.caption).foregroundStyle(.secondary)
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
