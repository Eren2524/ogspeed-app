# OGSpeed auf Android

## Warum es keine APK der jetzigen App gibt
OGSpeed ist in Swift mit SwiftUI geschrieben. Dieser Code läuft nur auf iOS. Es gibt kein Werkzeug,
das daraus eine Android-App macht. Für Android braucht es eine eigene Fassung.

## Drei Wege

### 1. Web-App (am schnellsten)
Eine Webseite, die sich wie eine App auf den Startbildschirm legen lässt.
- **Aufwand:** klein
- **Läuft auf:** Android und iPhone sofort, ohne Store, ohne Konto, ohne Signierung
- **Funktioniert:** Speedtest, Bewertungen, Verlauf, Vergleich, Teilen-Bild
- **Funktioniert nicht:** FRITZ!Box-Zugriff (der Browser blockiert unverschlüsselte Aufrufe ins
  Heimnetz), Störungs-Wächter im Hintergrund, Widget, VPN-Erkennung, Raumfotos mit Wärmekarte

### 2. Native Android-App in Kotlin (das beste Ergebnis)
- **Aufwand:** groß, die App hat fünf Bereiche und rund 5.000 Zeilen Code
- **Vorteil:** Android kann mehr als iOS. Die Signalstärke liest die App selbst aus, ganz ohne
  FRITZ!Box. Das Heimnetz darf sie durchsuchen. Und ein echtes VPN ist ohne Sonderberechtigung
  möglich – das, was auf dem iPhone an Apple scheitert, ginge hier direkt in der App.
- **Ergebnis:** eine echte APK zum Weitergeben, später auch für Google Play

### 3. Eine Fassung für beide Systeme (Flutter)
- **Aufwand:** mittel bis groß, die iOS-Fassung müsste ebenfalls neu gebaut werden
- **Vorteil:** künftig nur noch ein Code-Stand für beide Systeme
- **Nachteil:** einige tiefe Systemfunktionen sind umständlicher

## Empfehlung
Willst du es **heute** auf einem Android-Handy haben: Web-App.
Willst du **auf Android das volle Programm inklusive echtem VPN**: Kotlin-Fassung.

## APK verteilen, ohne Play Store
Eine fertige APK lässt sich direkt weitergeben: per Datei aufs Handy, dann in den Android-
Einstellungen „Installation unbekannter Apps“ für den Dateimanager erlauben und antippen.
Kein Konto, keine Prüfung, keine 25 Dollar, keine 12 Tester. Für den eigenen Gebrauch und
zum Herumreichen ist das der kürzeste Weg.
