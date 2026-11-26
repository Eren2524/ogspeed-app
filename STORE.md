# Veröffentlichung im App Store und bei Google Play

Stand: 26.11.2026 · OGSpeed 1.6

## Teil 1 – Apple App Store

### Im Code erledigt
- [x] **Privacy Manifest** (`PrivacyInfo.xcprivacy` in App und Widget). Seit 1. Mai 2024 Pflicht.
      Deklariert: UserDefaults (CA92.1) und Systemlaufzeit (35F9.1). Kein Tracking, keine Datenerhebung.
- [x] **Keine privaten APIs.** Nur öffentliche Schnittstellen (Network, Security, CFNetwork, CoreTelephony).
- [x] **Keine Fremd-SDKs**, dadurch keine fremden Privacy-Manifeste nötig.
- [x] **Kein Werbe-Identifier, kein Tracking, keine Analyse.**
- [x] **Zweck-Texte** für lokales Netzwerk und Kamera im Info.plist.
- [x] **Export-Compliance** (`ITSAppUsesNonExemptEncryption = false`): Die App nutzt nur
      Standard-Verschlüsselung des Systems (TLS, CommonCrypto).
      → Diese Erklärung gibst **du** ab. Im Zweifel in App Store Connect den Fragebogen ausfüllen.
- [x] **App-Icon** 1024 × 1024 ohne Transparenz.
- [x] **Launch Screen**, feste Hochformat-Ausrichtung, iOS 17 als Minimum.
- [x] **Datenschutzerklärung und Support-Seite** unter `docs/`.
- [x] **Markenhinweis** auf der Support-Seite (keine Verbindung zu AVM, Telekom, Vodafone …).

### Was nur du erledigen kannst
- [ ] **Apple Developer Program**, 99 € im Jahr. Ohne das geht keine Einreichung.
- [ ] **GitHub Pages einschalten** für dieses Repo (Settings › Pages › Branch `main`, Ordner `/docs`).
      Danach sind die Pflicht-Links erreichbar:
      - Datenschutz: `https://eren2524.github.io/ogspeed-app/datenschutz.html`
      - Support: `https://eren2524.github.io/ogspeed-app/`
- [ ] **In beiden HTML-Dateien die Platzhalter ausfüllen** (Name, Anschrift, E-Mail).
      Ohne Impressumsangaben ist die Erklärung nicht gültig.
- [ ] **Screenshots** für 6,9″ und 6,5″ iPhone, mindestens 3 Stück.
- [ ] **App-Privacy-Angaben** in App Store Connect: überall „Nein, wir erheben keine Daten“.
- [ ] **Altersfreigabe** 4+ und Kategorie „Dienstprogramme“.
- [ ] **Beschreibung und Schlüsselwörter** ohne fremde Markennamen im Titel.

### Bekannte Risiken bei der Prüfung
| Risiko | Warum | Gegenmaßnahme |
|---|---|---|
| Richtlinie 5.2.1 Marken | FRITZ!Box, Vodafone, Telekom, NordVPN werden benannt | Nur sachliche Kompatibilitätshinweise, Markenhinweis auf der Support-Seite, keine Fremdmarken in Titel und Untertitel |
| Richtlinie 2.5.1 Netzwerkzugriff | Auslesen des eigenen Routers im Heimnetz | Nur offizielle TR-064-Schnittstelle mit Zugangsdaten des Nutzers, kein Scannen fremder Netze |
| Richtlinie 2.3 Zutreffende Angaben | Aussagen zu Sicherheit und Verschlüsselung | Grenzen stehen in der App selbst, Formulierungen bleiben vorsichtig |
| Prüfer-Konto ohne FRITZ!Box | Teile der App bleiben leer | Im Prüfhinweis erklären, dass FRITZ!Box-Funktionen optional sind |

**Prüfhinweis für Apple (in App Store Connect eintragen):**
> OGSpeed misst die Internetverbindung und prüft das Netzwerk. Die Funktionen rund um
> Signalstärke, Geräteliste und Portfreigaben benötigen eine FRITZ!Box im selben WLAN und
> funktionieren ohne eine solche nicht – alle übrigen Funktionen laufen in jedem Netz.
> Die App baut selbst kein VPN auf, sie erkennt und prüft nur bestehende Verbindungen.

## Teil 2 – Google Play

**Wichtig: Es gibt bisher keine Android-Fassung.** OGSpeed ist in Swift/SwiftUI geschrieben und
läuft ausschließlich auf iOS. Eine APK lässt sich daraus nicht erzeugen – dafür ist eine neue
Fassung nötig (siehe `ANDROID.md`).

Sobald eine Android-Fassung existiert, verlangt Google:
- [ ] **Play-Entwicklerkonto**, einmalig 25 US-Dollar, mit Identitätsprüfung
- [ ] **Geschlossener Test mit mindestens 12 Testern über 14 zusammenhängende Tage**,
      bevor die Produktionsfreigabe überhaupt beantragt werden darf
      (gilt für persönliche Konten, die nach dem 13.11.2023 erstellt wurden)
- [ ] **Datensicherheits-Formular** (entspricht Apples App Privacy)
- [ ] **Datenschutzerklärung** – dieselbe Seite wie oben ist dafür nutzbar
- [ ] **Aktuelles Ziel-SDK**, App-Signierung durch Google, Inhaltsbewertung
