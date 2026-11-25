import SwiftUI

// MARK: - Router- und Anbieter-Auswahl

enum RouterChoice {
    static let key = "routerChoice"      // "auto" oder RouterVendor.rawValue
    static let providerKey = "providerChoice"

    static let selectable: [RouterVendor] = [.fritz, .speedport, .vodafoneStation, .easybox, .o2, .tplink, .asus, .netgear, .unknown]

    static func effective(choice: String, detected: RouterVendor?) -> RouterVendor? {
        if choice != "auto", let v = RouterVendor(rawValue: choice) { return v }
        return detected
    }

    static func effectiveProvider(choice: String, detected: Provider?) -> Provider? {
        if choice != "auto", let p = Provider(rawValue: choice) { return p }
        return detected
    }

    static func shortName(_ v: RouterVendor) -> String {
        switch v {
        case .fritz: return "FRITZ!Box"
        case .speedport: return "Speedport"
        case .vodafoneStation: return "Vodafone Station"
        case .easybox: return "EasyBox"
        case .o2: return "o2 HomeBox"
        case .unknown: return "Anderer"
        default: return v.label
        }
    }

    static func defaultAddress(_ v: RouterVendor?) -> String {
        switch v {
        case .fritz?: return "fritz.box"
        case .speedport?: return "speedport.ip"
        case .vodafoneStation?, .easybox?, .tplink?: return "192.168.0.1"
        case .o2?, .asus?, .netgear?: return "192.168.1.1"
        default: return "192.168.0.1"
        }
    }

    /// WLAN-relevante Router-Tipps zuerst
    static func routerSection(for v: RouterVendor?, access: AccessType?) -> GuideSection {
        switch v {
        case .fritz?: return Guides.fritz(access: access)
        case .speedport?: return Guides.speedport
        case .vodafoneStation?, .easybox?: return Guides.vodafoneStation
        case .o2?: return Guides.o2Box
        default: return Guides.genericRouter(v)
        }
    }
}

/// Chips zum Umschalten des Routers
struct RouterChips: View {
    @AppStorage(RouterChoice.key) private var choice = "auto"
    let detected: RouterVendor?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: detected.map { "Automatisch · \(RouterChoice.shortName($0))" } ?? "Automatisch", value: "auto")
                ForEach(RouterChoice.selectable, id: \.self) { v in
                    chip(title: RouterChoice.shortName(v), value: v.rawValue)
                }
            }
        }
    }

    private func chip(title: String, value: String) -> some View {
        let on = choice == value
        return Button {
            choice = value
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(title).font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? Neon.cyan.opacity(0.22) : Color.white.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Neon.cyan : Color.white.opacity(0.12), lineWidth: 1))
                .foregroundStyle(on ? Neon.cyan : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tipp-Zeile mit Häkchen

struct TipRow: View {
    let tip: GuideTip
    @AppStorage(DoneTips.key) private var doneRaw = ""

    var body: some View {
        let done = DoneTips.parse(doneRaw).contains(tip.id)
        HStack(alignment: .top, spacing: 12) {
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
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Router-Karte im WLAN-Tab (für alle Router außer verbundener FRITZ!Box)

@MainActor @Observable
final class RouterLive {
    var rtt: Double?
    var samples: [Double] = []
    var speedport: SpeedportStatus?
    var speedportChecked = false
    private var task: Task<Void, Never>?

    /// Geschätzte WLAN-Qualität aus der Antwortzeit des Routers (0–100)
    var quality: Int? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let med = sorted[sorted.count / 2]
        var jit = 0.0
        if samples.count > 1 {
            for i in 1..<samples.count { jit += abs(samples[i] - samples[i - 1]) }
            jit /= Double(samples.count - 1)
        }
        let score = 100 - max(0, med - 3) * 3 - jit * 2
        return Int(max(5, min(100, score)))
    }

    func start(address: String, vendor: RouterVendor?) {
        task?.cancel()
        samples = []
        speedport = nil
        speedportChecked = false
        task = Task {
            if vendor == .speedport {
                speedport = await SpeedportClient.status(host: address)
                speedportChecked = true
            }
            while !Task.isCancelled {
                if let r = await Probes.tcpConnect(host: address, port: 80, timeout: 2) {
                    rtt = r
                    samples.append(r)
                    if samples.count > 15 { samples.removeFirst() }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() { task?.cancel() }
}

struct RouterStatusCard: View {
    let vendor: RouterVendor?
    let model: String?
    let address: String
    @State private var live = RouterLive()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(model ?? vendor.map(\.label) ?? "Dein Router", systemImage: "wifi.router.fill").font(.headline)
                Spacer()
                if let q = live.quality { LevelPill(level: Rating.signalLevel(q)) }
            }
            if let q = live.quality {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(q)").font(.system(size: 52, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Rating.signalLevel(q).color)
                        .contentTransition(.numericText(value: Double(q)))
                        .animation(.snappy, value: q)
                    Text("% Verbindung (geschätzt)").font(.subheadline).foregroundStyle(.secondary)
                }
                SignalSparkline(values: live.samples.map { Int(max(0, min(100, 100 - ($0 - 3) * 3))) }).frame(height: 40)
                Text("Gemessen an der Antwortzeit deines Routers: \(Fmt.ms(live.rtt ?? 0)) ms. Unter 5 ms ist top, über 20 ms ist das WLAN schwach oder gestört.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Messe die Verbindung zu \(address) …").font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if vendor == .speedport { speedportBlock }
            if vendor == .vodafoneStation || vendor == .easybox {
                Label("Die Vodafone Station gibt ihre Daten nicht an Apps heraus. Signal- und Kabelwerte siehst du in der Router-Oberfläche unter Status.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let url = URL(string: vendor == .speedport ? "http://speedport.ip" : "http://\(address)") {
                Link(destination: url) {
                    Label("Router-Oberfläche öffnen", systemImage: "safari").frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
        .task(id: address + (vendor?.rawValue ?? "")) { live.start(address: address, vendor: vendor) }
        .onDisappear { live.stop() }
    }

    @ViewBuilder
    private var speedportBlock: some View {
        if let s = live.speedport {
            Divider().overlay(.white.opacity(0.1))
            VStack(alignment: .leading, spacing: 8) {
                Label("Live vom Speedport", systemImage: "antenna.radiowaves.left.and.right").font(.subheadline.weight(.bold))
                    .foregroundStyle(Neon.cyan)
                HStack(spacing: 10) {
                    StatTile(title: "Leitung ↓", value: s.downMbps.map(Fmt.mbps) ?? "–", unit: "Mbit/s", icon: "arrow.down")
                    StatTile(title: "Leitung ↑", value: s.upMbps.map(Fmt.mbps) ?? "–", unit: "Mbit/s", icon: "arrow.up")
                }
                if let online = s.linkOnline {
                    Label(online ? "DSL verbunden" : "DSL getrennt", systemImage: online ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption).foregroundStyle(online ? Neon.green : Neon.red)
                }
                if let fw = s.firmware { Text("Firmware \(fw)").font(.caption).foregroundStyle(.secondary) }
            }
        } else if live.speedportChecked {
            Label("Status des Speedport nicht lesbar – bist du in seinem WLAN?", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(Neon.yellow)
        }
    }
}

/// Optimale Einstellungen direkt im WLAN-Tab
struct RouterTipsCard: View {
    let vendor: RouterVendor?
    let provider: Provider?
    let access: AccessType?
    @AppStorage(DoneTips.key) private var doneRaw = ""

    private var section: GuideSection { RouterChoice.routerSection(for: vendor, access: access) }
    private var extra: GuideSection? {
        guard let provider else { return nil }
        return Guides.providerSection(provider, access: access, router: vendor)
    }

    private var subtitle: String {
        var name = "deinen Router"
        if let v = vendor, v != .unknown { name = v.label }
        if extra != nil, let p = provider { name += " und deinen \(p.label)-Anschluss" }
        return "Für \(name) – damit holst du das Maximum raus."
    }

    var body: some View {
        let tips = section.tips + (extra?.tips ?? [])
        let done = DoneTips.parse(doneRaw)
        let count = tips.filter { done.contains($0.id) }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Optimale Einstellungen", systemImage: "slider.horizontal.3").font(.headline).foregroundStyle(Neon.magenta)
                Spacer()
                Text("\(count)/\(tips.count)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            ProgressView(value: Double(count), total: Double(max(tips.count, 1))).tint(Neon.magenta)
            ForEach(tips) { tip in TipRow(tip: tip) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }
}

// MARK: - Einstellungen: Router & Anbieter

struct RouterSettingsView: View {
    @AppStorage(RouterChoice.key) private var choice = "auto"
    @AppStorage(RouterChoice.providerKey) private var providerChoice = "auto"
    @AppStorage(K.fritzEnabled) private var fritzEnabled = false
    @State private var detector = NetDetector.shared
    @State private var spStatus: SpeedportStatus?
    @State private var spTesting = false
    @State private var spChecked = false

    private var vendor: RouterVendor? { RouterChoice.effective(choice: choice, detected: detector.identity?.router?.vendor) }

    var body: some View {
        Form {
            Section {
                if let id = detector.identity {
                    LabeledContent("Erkannter Router", value: id.router?.displayName ?? "–")
                    LabeledContent("Erkannter Anbieter", value: id.provider == .other ? (id.providerName ?? "–") : id.provider.label)
                } else {
                    Text("Noch nichts erkannt – öffne den Netz-Tab.").foregroundStyle(.secondary)
                }
            } header: { Text("Automatisch erkannt") }

            Section {
                Picker("Router", selection: $choice) {
                    Text("Automatisch").tag("auto")
                    ForEach(RouterChoice.selectable, id: \.self) { v in
                        Text(v == .unknown ? "Anderer Router" : v.label).tag(v.rawValue)
                    }
                }
                Picker("Anbieter", selection: $providerChoice) {
                    Text("Automatisch").tag("auto")
                    ForEach([Provider.telekom, .vodafone, .o2, .einsUndEins, .deutscheGlasfaser], id: \.self) { p in
                        Text(p.label).tag(p.rawValue)
                    }
                }
            } header: { Text("Mein Router & Anbieter") } footer: {
                Text("Stimmt die Erkennung nicht, stell es hier fest ein. Danach zeigen WLAN- und Netz-Tab die passenden Einstellungen.")
            }

            routerSection
        }
        .scrollContentBackground(.hidden)
        .background(NeonBackground())
        .navigationTitle("Router & Anbieter")
    }

    @ViewBuilder
    private var routerSection: some View {
        switch vendor {
        case .fritz?:
            Section {
                NavigationLink { FritzSetupView() } label: {
                    LabeledContent("FRITZ!Box anmelden", value: fritzEnabled ? "Verbunden" : "Nicht verbunden")
                }
            } header: { Text("FRITZ!Box") } footer: {
                Text("Mit Anmeldung: echtes WLAN-Signal, Funkband, Leitungstempo, Geräte im WLAN und DS-Lite-Check.")
            }
        case .speedport?:
            Section {
                Button {
                    Task {
                        spTesting = true
                        spStatus = await SpeedportClient.status()
                        spChecked = true
                        spTesting = false
                    }
                } label: {
                    HStack {
                        Text(spTesting ? "Lese Speedport …" : "Speedport-Status lesen")
                        Spacer()
                        if spTesting { ProgressView() }
                    }
                }
                if let s = spStatus {
                    LabeledContent("Leitung", value: "\(s.downMbps.map(Fmt.mbps) ?? "–") ↓ / \(s.upMbps.map(Fmt.mbps) ?? "–") ↑ Mbit/s")
                    if let fw = s.firmware { LabeledContent("Firmware", value: fw) }
                } else if spChecked {
                    Text("Nicht lesbar. Bist du im WLAN des Speedport?").foregroundStyle(Neon.yellow)
                }
            } header: { Text("Telekom Speedport") } footer: {
                Text("Kein Passwort nötig: OGSpeed liest die öffentliche Statusseite des Speedport (Leitungstempo, Firmware). Ein echtes WLAN-Signal pro Gerät gibt der Speedport nicht heraus – das schätzt OGSpeed über die Antwortzeit des Routers.")
            }
        case .vodafoneStation?, .easybox?:
            Section {
                Link("Router öffnen (192.168.0.1)", destination: URL(string: "http://192.168.0.1")!)
            } header: { Text("Vodafone") } footer: {
                Text("Die Vodafone Station hat keine Schnittstelle für Apps. OGSpeed schätzt die WLAN-Qualität über die Antwortzeit des Routers und zeigt dir alle wichtigen Einstellungen – inklusive DS-Lite → Dual Stack für Gaming.")
            }
        default:
            Section {
                Link("Router öffnen (\(RouterChoice.defaultAddress(vendor)))", destination: URL(string: "http://\(RouterChoice.defaultAddress(vendor))")!)
            } header: { Text("Router") } footer: {
                Text("OGSpeed schätzt die WLAN-Qualität über die Antwortzeit des Routers.")
            }
        }
    }
}
