# OGSpeed

Moderner Speedtest und WLAN-Analyse fürs iPhone – dunkel, Neon, Glas-Look.
Sagt nicht nur *wie schnell*, sondern *was damit geht*: Shooter, Palworld, PS Remote Play, Netflix in 4K, FaceTime, wie lange ein 50-GB-Spiel lädt.

## Funktionen
- **Speedtest** gegen das Cloudflare-Netz (Server meist Frankfurt/Düsseldorf), inkl. Ping unter Last und Aussetzern
- **Ampel + Klartext** für Gaming, Streaming, Calls & Musik, Downloads
- **WLAN**: echte Signalstärke, Funkband und Verbindungstempo über die FRITZ!Box (TR-064)
- **Live-Suche** nach der besten Stelle (Geigerzähler-Ton)
- **Raum-Wärmekarte** auf einem Foto deines Zimmers
- **Verlauf**, **Tarif-Check mit PDF**, **Störungs-Wächter**, **Widget**, **Siri**

## FRITZ!Box einrichten
In der FRITZ!Box: *Heimnetz › Netzwerk › Netzwerkeinstellungen › „Zugriff für Anwendungen zulassen“* anhaken.
In OGSpeed unter *Mehr › FRITZ!Box* Benutzer und Kennwort eintragen.

## Bauen
GitHub Actions baut bei jedem Push auf `main` automatisch `OGSpeed.ipa` und legt ein Release `ogspeed-vX.Y` an.
Version ändern: `MARKETING_VERSION` in `project.yml` und einen Abschnitt in `CHANGELOG.md`.
