import SwiftUI

/// Erledigte Tipps (für Häkchen und Turbo-Plan)
enum DoneTips {
    static let key = "doneTips"
    static func parse(_ s: String) -> Set<String> { Set(s.split(separator: ",").map(String.init)) }
    static func toggle(_ id: String, in s: String) -> String {
        var set = parse(s)
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        return set.sorted().joined(separator: ",")
    }
}

struct NetzView: View {
    @Environment(NetworkMonitor.self) private var network
    @Environment(HistoryStore.self) private var history
    @State private var detector = NetDetector.shared
    @AppStorage(DoneTips.key) private var doneRaw = ""
    @State private var showIP = false
    @AppStorage(RouterChoice.key) private var routerChoice = "auto"
    @AppStorage(RouterChoice.providerKey) private var providerChoice = "auto"

    private var vendor: RouterVendor? { RouterChoice.effective(choice: routerChoice, detected: detector.identity?.router?.vendor) }

    private var sections: [GuideSection] {
        let id = detector.identity
        let provider = RouterChoice.effectiveProvider(choice: providerChoice, detected: id?.provider)
        return Guides.sections(router: vendor, provider: provider, access: id?.access, connection: network.kind)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    identityCard
                    vpnCard
                    if network.kind != .cellular {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dein Router").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            RouterChips(detected: detector.identity?.router?.vendor)
                        }
                    }
                    turboCard
                    guideLink
                    toolsGrid
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(NeonBackground())
            .navigationTitle("Netz")
            .refreshable { detector.refresh(kind: network.kind, radio: network.radio) }
            .onAppear {
                if detector.identity == nil && !detector.running {
                    detector.refresh(kind: network.kind, radio: network.radio)
                }
            }
        }
    }

    // MARK: Mein Anschluss

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Mein Anschluss", systemImage: "network").font(.headline)
                Spacer()
                if detector.running {
                    ProgressView().controlSize(.small)
                } else {
                    Button { detector.refresh(kind: network.kind, radio: network.radio) } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(Neon.cyan)
                }
            }
            if let id = detector.identity {
                identityRows(id)
            } else if detector.running {
                Text("Erkenne Anbieter, Router und Anschluss …").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Keine Verbindung.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    @ViewBuilder
    private func identityRows(_ id: NetIdentity) -> some View {
        let connText = id.connection == .cellular ? "Mobilfunk\(id.radio.map { " · \($0)" } ?? "")" : id.access.rawValue + " · " + id.connection.label
        infoRow("antenna.radiowaves.left.and.right", "Anbieter", id.provider == .other ? (id.providerName ?? "Unbekannt") : id.provider.label)
        infoRow(id.connection.icon, "Verbindung", connText)
        if let r = id.router {
            HStack(alignment: .top) {
                infoRow("wifi.router.fill", "Router", r.displayName)
                if let url = URL(string: r.adminURL) {
                    Link(destination: url) {
                        Text("Öffnen").font(.caption.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Neon.cyan.opacity(0.15), in: Capsule())
                    }
                    .tint(Neon.cyan)
                }
            }
        }
        HStack(alignment: .top, spacing: 10) {
            AmpelDot(level: id.ipv4Mode.level, size: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(id.ipv4Mode.title).font(.subheadline.weight(.semibold))
                Text(id.ipv4Mode.natHint).font(.caption).foregroundStyle(.secondary)
            }
        }
        infoRow("6.circle", "IPv6", id.hasIPv6 ? "Ja" : "Nein")
        if let city = id.city { infoRow("mappin.and.ellipse", "Netz-Standort", city) }
        Button { showIP.toggle() } label: {
            infoRow("eye", "Öffentliche IP", showIP ? (id.ipv4 ?? id.ipv6 ?? "–") : "Antippen zum Anzeigen")
        }
        .buttonStyle(.plain)
        if id.router?.vendor == .fritz && !Prefs.fritzEnabled {
            NavigationLink { FritzSetupView() } label: {
                Label("FRITZ!Box verbinden für echtes WLAN-Signal und DS-Lite-Check", systemImage: "link")
                    .font(.caption.weight(.semibold))
            }
            .tint(Neon.cyan)
        }
    }

    private func infoRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.caption).foregroundStyle(Neon.cyan).frame(width: 20)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }

    // MARK: VPN

    private var vpnCard: some View {
        let active = VPNDetect.isActive
        return NavigationLink { VPNView() } label: {
            HStack(spacing: 13) {
                Image(systemName: active ? "lock.fill" : "lock.open.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(active ? Neon.green : Neon.cyan)
                    .frame(width: 42, height: 42)
                    .background((active ? Neon.green : Neon.cyan).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("VPN").font(.headline)
                        if active {
                            Text("AKTIV").font(.caption2.weight(.heavy)).foregroundStyle(.black)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Neon.green, in: Capsule())
                        }
                    }
                    Text(active
                         ? "Prüfen, ob wirklich verschlüsselt wird und wo dein Ausgang liegt"
                         : "Einrichten, prüfen und Tempo mit und ohne Tunnel vergleichen")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glass(radius: 22, padding: 14)
    }

    // MARK: Turbo-Plan

    private var turboCard: some View {
        let done = DoneTips.parse(doneRaw)
        let plan = Guides.turboPlan(identity: detector.identity, last: history.results.first, sections: sections, done: done)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Dein Turbo-Plan", systemImage: "bolt.fill").font(.headline).foregroundStyle(Neon.yellow)
            Text("Die drei Einstellungen, die bei deinem Netz am meisten bringen.")
                .font(.caption).foregroundStyle(.secondary)
            if plan.isEmpty {
                Text("Alles umgesetzt – stark! Mach einen neuen Speedtest zum Vergleich.").font(.subheadline)
            }
            ForEach(Array(plan.enumerated()), id: \.element.id) { i, tip in
                NavigationLink { TipDetailView(tip: tip) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)").font(.headline.weight(.heavy)).foregroundStyle(.black)
                            .frame(width: 28, height: 28)
                            .background(Neon.yellow, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tip.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                            Text(tip.impact.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    private var guideTitle: String {
        if network.kind == .cellular { return "Maximum aus dem Mobilfunk" }
        guard let v = vendor else { return "Maximum aus deinem Netz" }
        return v == .unknown ? "Maximum aus deinem Router" : "Maximum aus \(v.label)"
    }

    private var guideLink: some View {
        let done = DoneTips.parse(doneRaw)
        let all = sections.flatMap(\.tips)
        let count = all.filter { done.contains($0.id) }.count
        let title = guideTitle
        return NavigationLink { GuideView(sections: sections) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "slider.horizontal.3").font(.title3).foregroundStyle(Neon.magenta)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline).multilineTextAlignment(.leading)
                        Text("\(all.count) Einstellungen, die kaum jemand kennt").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                ProgressView(value: Double(count), total: Double(max(all.count, 1)))
                    .tint(Neon.magenta)
                Text("\(count) von \(all.count) umgesetzt").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glass()
    }

    // MARK: Werkzeuge

    private var toolsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Werkzeuge").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tool("Liegt's an mir?", "Prüft PSN, Netflix, WhatsApp & Co.", "questionmark.app.fill", Neon.green) { ServiceCheckView() }
                tool("Gaming-Radar", "Live-Ping zu Spiele-Servern", "scope", Neon.magenta) { PingRadarView() }
                tool("DNS-Turbo", "Schnellsten DNS finden", "hare.fill", Neon.cyan) { DNSTurboView(router: detector.identity?.router?.address) }
                tool("Geräte im WLAN", "Wer hängt in deinem Netz?", "person.2.wave.2.fill", Neon.purple) { DevicesView() }
                tool("VPN-Prüfung", "Verschlüsselt? Wo liegt der Server?", "lock.shield.fill", Neon.green) { VPNView() }
                tool("Sicherheits-Labor", "25+ Prüfungen: Mitlesen, DNS, Router, Geräte", "shield.checkered", Neon.red) { NetworkSecurityView() }
            }
        }
    }

    private func tool<D: View>(_ title: String, _ sub: String, _ icon: String, _ color: Color, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(color).neonGlow(color, radius: 5)
                Text(title).font(.subheadline.weight(.bold))
                Text(sub).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glass(radius: 22, padding: 14)
    }
}

// MARK: - Anleitung

struct GuideView: View {
    let sections: [GuideSection]
    @AppStorage(DoneTips.key) private var doneRaw = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Tippe auf einen Tipp für die genaue Anleitung. Häkchen setzen, wenn du ihn umgesetzt hast – dein Turbo-Plan passt sich an.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(sections) { s in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(s.title, systemImage: s.icon).font(.headline)
                        ForEach(s.tips) { tip in tipRow(tip) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass()
                }
                Text("Menünamen können je nach Modell und Firmware leicht abweichen.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle("Maximum rausholen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tipRow(_ tip: GuideTip) -> some View {
        let done = DoneTips.parse(doneRaw).contains(tip.id)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                doneRaw = DoneTips.toggle(tip.id, in: doneRaw)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(done ? Neon.green : .secondary)
            }
            .buttonStyle(.plain)
            NavigationLink { TipDetailView(tip: tip) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tip.title).font(.subheadline.weight(.semibold)).strikethrough(done).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(tip.impact.label).font(.caption2.weight(.bold))
                            .foregroundStyle(tip.impact == .gross ? Neon.yellow : .secondary)
                        ForEach(tip.tags, id: \.self) { t in
                            Text(t.rawValue).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct TipDetailView: View {
    let tip: GuideTip
    @AppStorage(DoneTips.key) private var doneRaw = ""

    var body: some View {
        let done = DoneTips.parse(doneRaw).contains(tip.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tip.title).font(.title2.weight(.heavy))
                HStack(spacing: 8) {
                    Text(tip.impact.label).font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Neon.yellow.opacity(0.15), in: Capsule())
                        .foregroundStyle(Neon.yellow)
                    ForEach(tip.tags, id: \.self) { t in
                        Text(t.rawValue).font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                }
                block("Was bringt's?", "sparkles", tip.why)
                block("So geht's", "list.number", tip.how)
                if let c = tip.caution { block("Achtung", "exclamationmark.triangle.fill", c) }
                Button {
                    doneRaw = DoneTips.toggle(tip.id, in: doneRaw)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label(done ? "Erledigt" : "Als erledigt markieren", systemImage: done ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(NeonButtonStyle(colors: done ? [Neon.green, Neon.lime] : [Neon.cyan, Neon.magenta]))
                Text("Danach einen Speedtest machen – im Verlauf siehst du, was es gebracht hat.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(NeonBackground())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: String, _ icon: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(Neon.cyan)
            Text(text).font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }
}
