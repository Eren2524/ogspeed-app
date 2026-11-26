import SwiftUI

/// Ein Einrichtungs-Schritt mit Nummer, Text und optionalem Knopf
private struct Step: View {
    let number: Int
    let title: String
    let text: String
    var link: (label: String, url: String)? = nil
    var warn: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.heavy)).foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(Neon.cyan, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary)
                if let warn {
                    Label(warn, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(Neon.yellow)
                }
                if let link, let url = URL(string: link.url) {
                    Link(link.label, destination: url)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Neon.cyan.opacity(0.15), in: Capsule())
                        .tint(Neon.cyan)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - NordVPN

struct NordSetupView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Das passt für dich", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(Neon.green)
                    Text("Mit deinem Premium-Abo brauchst du nichts zusätzlich zu kaufen. NordVPN deckt drei deiner vier Wünsche ab: sicher in fremden WLANs, in einem anderen Land erscheinen und dein Anbieter sieht nicht mehr mit – im WLAN wie über mobile Daten.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass()

                SectionLabel(title: "Einrichten")
                VStack(spacing: 0) {
                    Step(number: 1, title: "NordVPN-App installieren",
                         text: "Aus dem offiziellen App Store. Die App darf den Tunnel fahren, weil sie Apples VPN-Berechtigung hat. Danach mit deinem Premium-Konto anmelden.",
                         link: ("Im App Store öffnen", "https://apps.apple.com/de/app/id905953485"))
                    Divider().overlay(.white.opacity(0.07))
                    Step(number: 2, title: "Protokoll auf NordLynx stellen",
                         text: "In den App-Einstellungen unter „VPN-Protokoll“. NordLynx basiert auf WireGuard und ist deutlich schneller als OpenVPN – besonders beim Ping, also beim Zocken.")
                    Divider().overlay(.white.opacity(0.07))
                    Step(number: 3, title: "Automatisch verbinden einschalten",
                         text: "Unter „Automatische Verbindung“ für WLAN und für mobile Daten aktivieren. Dann baut sich der Tunnel von selbst auf, sobald du in ein fremdes Netz kommst – du musst an nichts denken.")
                    Divider().overlay(.white.opacity(0.07))
                    Step(number: 4, title: "Kill Switch aktivieren",
                         text: "Bricht der Tunnel ab, wird die Internetverbindung sofort gekappt, statt ungeschützt weiterzulaufen. Ohne diesen Schalter läuft bei jedem Aussetzer kurz alles offen durch dein Netz.")
                    Divider().overlay(.white.opacity(0.07))
                    Step(number: 5, title: "Bedrohungsschutz einschalten",
                         text: "Damit laufen auch die Namensanfragen über NordVPN statt über deinen Anbieter. Genau das prüft OGSpeed als DNS-Leck.")
                    Divider().overlay(.white.opacity(0.07))
                    Step(number: 6, title: "Server wählen und zurück zu OGSpeed",
                         text: "Deutschland oder Niederlande für höchstes Tempo, ein anderes Land fürs Geoblocking. Dann hier auf „Jetzt prüfen“ – OGSpeed weist dir nach, wo du jetzt herauskommst.")
                }
                .glass(radius: 20, padding: 14)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Wichtig für den Beweis", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Neon.yellow)
                    Text("Prüf einmal **ohne** aktives VPN. OGSpeed merkt sich dann deinen normalen Ausgang. Erst danach kann es dir schwarz auf weiß zeigen, dass sich mit VPN Land, Betreiber und IP wirklich ändern.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass()
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle("NordVPN")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Heimnetz über die FRITZ!Box

struct HomeVPNSetupView: View {
    @State private var detector = NetDetector.shared

    private var dsLite: Bool {
        guard let m = detector.identity?.ipv4Mode else { return false }
        return m == .dsLite || m == .cgnat || m == .likelyDsLite
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Wofür das gut ist", systemImage: "house.fill").font(.headline)
                    Text("Ein Tunnel zu deiner eigenen FRITZ!Box – kostenlos, weil WireGuard dort schon eingebaut ist. Damit kommst du von überall an PS5, NAS, Smart Home und den Claude-PC, als säßest du zu Hause. Dein iPhone leitet dabei auf Wunsch den gesamten Verkehr über dein Zuhause.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass()

                if dsLite {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Bei dir geht das gerade nicht", systemImage: "xmark.octagon.fill")
                            .font(.subheadline.weight(.bold)).foregroundStyle(Neon.red)
                        Text("OGSpeed hat an diesem Anschluss DS-Lite erkannt: Du hast keine eigene öffentliche IPv4-Adresse. Von außen ist dein Heimnetz damit nicht erreichbar – egal welcher Router. Lass deinen Anbieter auf Dual Stack umstellen (steht im Netz-Tab unter „Maximum rausholen“), dann klappt es. Fürs Absichern unterwegs nimm bis dahin NordVPN.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass()
                }

                SectionLabel(title: "Voraussetzungen")
                VStack(spacing: 0) {
                    InfoLine(title: "FRITZ!Box mit WireGuard", value: "ab FRITZ!OS 7.50", icon: "wifi.router.fill")
                    Divider().overlay(.white.opacity(0.07))
                    InfoLine(title: "Öffentliche IPv4 oder IPv6", value: ipStatus, icon: "number",
                             level: dsLite ? .bad : .great)
                    Divider().overlay(.white.opacity(0.07))
                    InfoLine(title: "MyFRITZ!-Konto", value: "kostenlos", icon: "person.crop.circle")
                    Divider().overlay(.white.opacity(0.07))
                    InfoLine(title: "WireGuard-App", value: "kostenlos", icon: "app.badge")
                }
                .glass(radius: 20, padding: 14)

                SectionLabel(title: "Einrichten")
                VStack(spacing: 0) {
                    Step(number: 1, title: "MyFRITZ! einrichten",
                         text: "Unter Internet › MyFRITZ!-Konto ein kostenloses Konto anlegen und die Bestätigungs-E-Mail anklicken. Darüber findet dein iPhone später deine wechselnde Heim-Adresse.",
                         link: ("fritz.box öffnen", "http://fritz.box"))
                    Divider().overlay(.white.opacity(0.07))
                    Step(number: 2, title: "Heim-Netz auf eine ungewöhnliche Adresse legen",
                         text: "Unter Heimnetz › Netzwerk › Netzwerkeinstellungen › IPv4-Adressen. Stell etwas Seltenes ein, zum Beispiel 192.168.188.1.",
                         warn: "Wichtig: Beide Seiten brauchen verschiedene IP-Netze. Sitzt du in einem fremden WLAN mit demselben Netz wie zu Hause, funktioniert der Tunnel nicht. Mit 192.168.178.1 passiert das oft.")
                    Divider().overlay(.white.opacity(0.07))
                    Step(number: 3, title: "WireGuard-App installieren",
                         text: "Die offizielle App der WireGuard-Entwickler aus dem App Store.",
                         link: ("Im App Store öffnen", "https://apps.apple.com/de/app/id1441195209"))
                    Divider().overlay(.white.opacity(0.07))
                    Step(number: 4, title: "Verbindung in der FRITZ!Box anlegen",
                         text: "Internet › Freigaben › VPN (WireGuard) › „Verbindung hinzufügen“ › „Einzelgerät“. Wähle dabei, dass der gesamte Verkehr über die FRITZ!Box laufen soll – nur dann bist du in fremden WLANs wirklich geschützt.")
                    Divider().overlay(.white.opacity(0.07))
                    Step(number: 5, title: "QR-Code scannen",
                         text: "Die FRITZ!Box zeigt am Ende einen QR-Code. In der WireGuard-App auf „+“ › „Aus QR-Code erstellen“ und abfotografieren. Name vergeben, fertig.")
                    Divider().overlay(.white.opacity(0.07))
                    Step(number: 6, title: "Prüfen",
                         text: "Tunnel in der WireGuard-App einschalten, mobile Daten statt WLAN nutzen und hier auf „Jetzt prüfen“. Der Ausgangsserver muss dann dein Zuhause mit 1&1 zeigen.")
                }
                .glass(radius: 20, padding: 14)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Beides zusammen geht nicht", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Neon.yellow)
                    Text("Die FRITZ!Box kann auch selbst zu einem VPN-Anbieter verbinden und das ganze Heimnetz darüber leiten. Dafür darf aber keine einzige WireGuard-Verbindung für ein Gerät eingerichtet sein – du musst dich also zwischen „Tunnel nach Hause“ und „ganzes Zuhause über NordVPN“ entscheiden. Auf dem iPhone brauchst du das ohnehin nicht: Dort schaltest du einfach zwischen beiden Apps um.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass()
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(NeonBackground())
        .navigationTitle("VPN nach Hause")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ipStatus: String {
        guard let m = detector.identity?.ipv4Mode else { return "noch nicht geprüft" }
        switch m {
        case .real: return "vorhanden"
        case .dsLite, .cgnat: return "fehlt (DS-Lite)"
        case .likelyDsLite: return "wahrscheinlich DS-Lite"
        case .unknown: return "nicht prüfbar"
        }
    }
}
