import SwiftUI

struct MoreView: View {
    @AppStorage(K.dataSaver) private var dataSaver = true
    @AppStorage(K.fritzEnabled) private var fritzEnabled = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { TariffView() } label: {
                        row("doc.text.magnifyingglass", "Tarif-Check & Protokoll", "Bekommst du, was du bezahlst?", Neon.cyan)
                    }
                    NavigationLink { WatchView() } label: {
                        row("bell.badge.fill", "Störungs-Wächter", "Meldet Ausfälle und Einbrüche", Neon.magenta)
                    }
                }
                Section("Einstellungen") {
                    NavigationLink { RouterSettingsView() } label: {
                        row("wifi.router.fill", "Router & Anbieter", routerSubtitle, Neon.purple)
                    }
                    Toggle(isOn: $dataSaver) {
                        row("antenna.radiowaves.left.and.right", "Datensparmodus", "Bei Mobilfunk kürzer messen", Neon.yellow)
                    }
                    .tint(Neon.cyan)
                }
                Section("Siri & Widget") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sag „Hey Siri, teste mein Internet mit OGSpeed“ oder lege den Kurzbefehl in der Kurzbefehle-App an.")
                        Text("Widget: Homescreen lange drücken › + › OGSpeed.")
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    Text("Messungen über das Speedtest-Netz von Cloudflare. Deine Daten bleiben auf dem iPhone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(NeonBackground())
            .navigationTitle("Mehr")
        }
    }

    @AppStorage(RouterChoice.key) private var routerChoice = "auto"

    private var routerSubtitle: String {
        let v = RouterChoice.effective(choice: routerChoice, detected: NetDetector.shared.identity?.router?.vendor)
        let name = v.map { $0 == .unknown ? "Anderer Router" : $0.label } ?? "Automatisch"
        if v == .fritz { return name + (fritzEnabled ? " · verbunden" : " · nicht angemeldet") }
        return name
    }

    private func row(_ icon: String, _ title: String, _ sub: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.headline).foregroundStyle(color)
                .frame(width: 34, height: 34).background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - FRITZ!Box einrichten

struct FritzSetupView: View {
    @AppStorage(K.fritzEnabled) private var enabled = false
    @AppStorage(K.fritzHost) private var host = "fritz.box"
    @AppStorage(K.fritzUser) private var user = ""
    @State private var password = Keychain.get()
    @State private var status: String?
    @State private var ok = false
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Text("So holt sich OGSpeed das echte WLAN-Signal. Einmalig in der FRITZ!Box (Browser: fritz.box) einschalten:")
                    .font(.subheadline)
                Label("Heimnetz › Netzwerk › Netzwerkeinstellungen › „Zugriff für Anwendungen zulassen“ anhaken", systemImage: "1.circle.fill")
                Label("System › FRITZ!Box-Benutzer: deinen Benutzer mit Recht „FRITZ!Box Einstellungen“ verwenden", systemImage: "2.circle.fill")
            }
            .font(.caption)

            Section("Zugang") {
                TextField("Adresse", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Benutzername", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Kennwort", text: $password)
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Text(testing ? "Verbinde …" : "Verbinden & testen")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(testing || user.isEmpty || password.isEmpty)
                if let status {
                    Label(status, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(ok ? Neon.green : Neon.yellow).font(.subheadline)
                }
                if enabled {
                    Button("FRITZ!Box trennen", role: .destructive) {
                        enabled = false
                        Keychain.set("")
                        password = ""
                        status = nil
                    }
                }
            }
            Section {
                Text("Kennwort wird nur im Schlüsselbund dieses iPhones gespeichert und nur an deine FRITZ!Box geschickt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(NeonBackground())
        .navigationTitle("FRITZ!Box")
    }

    private func test() async {
        testing = true
        defer { testing = false }
        Keychain.set(password)
        let c = FritzClient(host: host.isEmpty ? "fritz.box" : host, user: user, password: password)
        defer { c.close() }
        do {
            let info = try await c.deviceInfo()
            var text = "\(info.model) verbunden"
            if let w = try? await c.wlanStatus() {
                text += " · dein Signal: \(w.signal) %"
            }
            enabled = true
            ok = true
            status = text
        } catch {
            ok = false
            enabled = false
            status = error.localizedDescription
        }
    }
}

// MARK: - Störungs-Wächter

struct WatchView: View {
    @State private var watch = Watchdog.shared
    @AppStorage(K.watchEnabled) private var enabled = false
    @AppStorage(K.watchMinMbps) private var minMbps = 5.0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $enabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wächter aktiv").font(.headline)
                            Text("Prüft regelmäßig und schickt dir eine Mitteilung, wenn das Internet weg oder sehr langsam ist.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(Neon.magenta)
                    HStack {
                        Text("Alarm unter")
                        Spacer()
                        Stepper("\(Int(minMbps)) Mbit/s", value: $minMbps, in: 1...200, step: minMbps < 10 ? 1 : 5)
                            .fixedSize()
                    }
                    .font(.subheadline)
                    if let last = watch.lastCheck {
                        Label("Zuletzt geprüft \(Fmt.relative(last)) – \(watch.lastOK ? "alles ok" : "Störung")",
                              systemImage: watch.lastOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(watch.lastOK ? Neon.green : Neon.red)
                    }
                    Button("Jetzt prüfen") { Task { await watch.check(fromBackground: false) } }
                        .buttonStyle(GlassButtonStyle())
                }
                .glass()

                VStack(alignment: .leading, spacing: 8) {
                    Label("So funktioniert's", systemImage: "info.circle.fill").font(.headline)
                    Text("Solange OGSpeed offen ist, wird jede Minute geprüft. Im Hintergrund entscheidet iOS, wann geprüft wird – meist alle 15–60 Minuten, wenn „Hintergrundaktualisierung“ für OGSpeed an ist (Einstellungen › OGSpeed).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Störungs-Protokoll").font(.headline)
                        Spacer()
                        if !watch.outages.isEmpty { Button("Leeren") { watch.clear() }.font(.caption) }
                    }
                    if watch.outages.isEmpty {
                        Text("Keine Störungen erfasst.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(watch.outages) { o in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: o.end == nil ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                                .foregroundStyle(o.end == nil ? Neon.red : Neon.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.reason).font(.subheadline.weight(.semibold))
                                Text(range(o)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass()
            }
            .padding()
        }
        .background(NeonBackground())
        .navigationTitle("Störungs-Wächter")
        .onChange(of: enabled) { _, on in
            Task {
                if on { _ = await Watchdog.requestNotifications() }
                watch.setEnabled(on)
            }
        }
    }

    private func range(_ o: Outage) -> String {
        let start = o.start.formatted(date: .abbreviated, time: .shortened)
        guard let end = o.end else { return "seit \(start) · \(o.connection.label)" }
        let mins = max(1, Int(end.timeIntervalSince(o.start) / 60))
        return "\(start) · \(mins) Min · \(o.connection.label)"
    }
}
