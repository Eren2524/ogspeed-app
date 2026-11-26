import SwiftUI

struct PrivacyView: View {
    @AppStorage(PrivacyKeys.encryptedDNS) private var encryptedDNS = true
    @AppStorage(PrivacyKeys.routerScan) private var routerScan = true
    @AppStorage(PrivacyKeys.showSSIDInShare) private var shareSSID = false
    @AppStorage(PrivacyKeys.fritzAllowHTTP) private var allowHTTP = false
    @AppStorage(K.fritzHost) private var fritzHost = "fritz.box"
    @State private var pinReset = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $encryptedDNS) {
                    label("Verschlüsselte Namensauflösung",
                          "Adressen werden über DNS-over-HTTPS aufgelöst. Ohne das sieht jeder, der im WLAN mitschneidet, welche Dienste OGSpeed gerade prüft.")
                }
                .tint(Neon.green)
                Toggle(isOn: $routerScan) {
                    label("Router im Heimnetz erkennen",
                          "OGSpeed ruft die Startseite deines Routers auf, um Modell und Hersteller zu erkennen. Aus heißt: keine Anfragen ins Heimnetz, aber auch keine passenden Einstellungs-Tipps.")
                }
                .tint(Neon.green)
                Toggle(isOn: $shareSSID) {
                    label("WLAN-Name in geteilten Bildern",
                          "Standardmäßig aus. Dein WLAN-Name verrät sonst in jedem geteilten Ergebnis, wo du wohnst.")
                }
                .tint(Neon.yellow)
            } header: { Text("Im Netzwerk") }

            Section {
                Toggle(isOn: $allowHTTP) {
                    label("Unverschlüsselt zur FRITZ!Box erlauben",
                          "Standardmäßig aus. OGSpeed spricht mit der FRITZ!Box über HTTPS und merkt sich beim ersten Mal ihr Zertifikat. Dein Kennwort wird nie im Klartext gesendet – auch unverschlüsselt nur über das Digest-Verfahren.")
                }
                .tint(Neon.yellow)
                Button("Gemerktes FRITZ!Box-Zertifikat vergessen") {
                    CertPin.forget(fritzHost)
                    pinReset = true
                }
                if pinReset {
                    Text("Beim nächsten Verbinden wird das Zertifikat neu gemerkt.")
                        .font(.caption).foregroundStyle(Neon.green)
                }
            } header: { Text("FRITZ!Box-Verbindung") } footer: {
                Text("Nach einem Werksreset der FRITZ!Box ändert sich ihr Zertifikat. Dann einmal hier zurücksetzen.")
            }

            Section {
                info("lock.doc.fill", "Alles bleibt auf dem iPhone",
                     "Verlauf, Messpunkte und Raumfotos liegen verschlüsselt im App-Ordner und werden nur gelesen, während das iPhone entsperrt ist. OGSpeed hat keinen eigenen Server, es gibt kein Konto und keine Werbung.")
                info("key.fill", "Kennwort im Schlüsselbund",
                     "Das FRITZ!Box-Kennwort liegt im Schlüsselbund dieses iPhones, nur für dieses Gerät und nur im entsperrten Zustand lesbar. Es landet in keinem Backup und verlässt dein Heimnetz nicht.")
                info("eye.slash.fill", "Neutrale Testnamen",
                     "Der DNS-Turbo fragt Zufallsnamen bei harmlosen Domains ab statt echter Dienste. Die Messung bleibt genau, verrät aber nichts über dich.")
                info("network.badge.shield.half.filled", "Keine offenen Türen",
                     "OGSpeed nimmt selbst keine Verbindungen an und hört auf keinem Port. Ein anderes Gerät im WLAN kann die App nicht ansprechen.")
            } header: { Text("So geht OGSpeed mit deinen Daten um") }

            Section {
                info("exclamationmark.triangle.fill", "Was auch OGSpeed nicht verbergen kann",
                     "Dein Router sieht immer, welche Geräte verbunden sind und wie viele Daten fließen – das gehört zu seiner Aufgabe. Auch die Gerätekennung (MAC-Adresse) im WLAN kann keine App verstecken. Dagegen hilft nur die iPhone-Einstellung „Private WLAN-Adresse“.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(NeonBackground())
        .navigationTitle("Privatsphäre & Sicherheit")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func info(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Neon.cyan).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
