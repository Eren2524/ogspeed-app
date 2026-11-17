import Foundation

/// Eine Zeile in einer Bewertungs-Karte, z. B. "Netflix · 4K möglich".
struct RatingRow: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let level: Level
    let text: String
}

/// Eine Bewertungs-Karte (Gaming, Streaming …).
struct Verdict: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let icon: String
    let level: Level
    let headline: String
    let rows: [RatingRow]
}

/// Übersetzt Messwerte in verständliche Aussagen.
/// Grenzwerte orientieren sich an den Empfehlungen der Anbieter
/// (Netflix, YouTube, Sony Remote Play, GeForce Now, FaceTime/Zoom).
enum Rating {

    // MARK: Gesamturteil

    static func overall(_ r: SpeedResult) -> (level: Level, title: String, text: String) {
        let parts = all(r)
        let worst = parts.map(\.level).min() ?? .bad
        let avg = Double(parts.map(\.level.rawValue).reduce(0, +)) / Double(max(parts.count, 1))
        let level: Level
        if r.downMbps < 1 { level = .bad }
        else if avg >= 2.7 && worst >= .good { level = .great }
        else if avg >= 1.9 { level = .good }
        else if avg >= 1.0 { level = .ok }
        else { level = .bad }

        switch level {
        case .great:
            return (level, "Sehr gutes Internet", "Alles läuft gleichzeitig flüssig: Online-Games, 4K-Streams, Videocalls und große Downloads.")
        case .good:
            return (level, "Gutes Internet", goodText(r))
        case .ok:
            return (level, "Reicht für den Alltag", okText(r))
        case .bad:
            return (level, "Schwache Verbindung", badText(r))
        }
    }

    private static func goodText(_ r: SpeedResult) -> String {
        if r.pingMs > 40 { return "Tempo passt, aber der Ping ist etwas hoch – bei schnellen Shootern merkst du das." }
        if r.bufferbloatMs > 60 { return "Gut, solange nicht alle gleichzeitig laden. Unter Last steigt die Verzögerung stark." }
        if r.downMbps < 50 { return "Für Streaming und Gaming gut. Große Downloads dauern etwas." }
        return "Fast alles läuft flüssig, nur an einzelnen Stellen geht noch mehr."
    }

    private static func okText(_ r: SpeedResult) -> String {
        if r.dropoutPercent > 3 { return "Die Verbindung hat Aussetzer – Spiele und Calls können kurz hängen." }
        if r.pingMs > 80 { return "Surfen und Streaming gehen, für Online-Games ist der Ping zu hoch." }
        return "Surfen, Musik und HD-Video klappen. Bei mehreren Geräten gleichzeitig wird es eng."
    }

    private static func badText(_ r: SpeedResult) -> String {
        if r.downMbps < 1 { return "Kaum Durchsatz. Prüf, ob du weit vom Router weg bist oder schlechten Empfang hast." }
        if r.dropoutPercent > 8 { return "Viele Aussetzer. Die Verbindung bricht immer wieder kurz ab." }
        return "Nur einfache Dinge wie Nachrichten und Surfen laufen zuverlässig."
    }

    static func all(_ r: SpeedResult) -> [Verdict] {
        [gaming(r), streaming(r), calls(r), downloads(r)]
    }

    // MARK: Gaming

    static func shooter(_ r: SpeedResult) -> RatingRow {
        let lvl: Level
        let text: String
        if r.pingMs <= 20 && r.jitterMs <= 5 && r.dropoutPercent <= 0.5 && r.bufferbloatMs <= 30 && r.downMbps >= 5 {
            lvl = .great; text = "Wie am LAN-Kabel – Treffer kommen sofort an."
        } else if r.pingMs <= 35 && r.jitterMs <= 10 && r.dropoutPercent <= 1.5 && r.downMbps >= 3 {
            lvl = .good; text = "Flüssig, kaum spürbare Verzögerung."
        } else if r.pingMs <= 60 && r.jitterMs <= 20 && r.dropoutPercent <= 4 {
            lvl = .ok; text = "Spielbar, aber du stirbst öfter „hinter der Wand“."
        } else {
            lvl = .bad; text = "Lag und Ruckler – Ranked lieber nicht."
        }
        return RatingRow(name: "Shooter · Fortnite, CoD, Valorant", level: lvl, text: text)
    }

    static func coop(_ r: SpeedResult) -> RatingRow {
        let lvl: Level
        let text: String
        if r.pingMs <= 50 && r.jitterMs <= 15 && r.dropoutPercent <= 1 {
            lvl = .great; text = "Läuft rund, auch mit vielen Spielern."
        } else if r.pingMs <= 80 && r.jitterMs <= 25 && r.dropoutPercent <= 2 {
            lvl = .good; text = "Gut spielbar, kleine Verzögerungen fallen kaum auf."
        } else if r.pingMs <= 140 && r.dropoutPercent <= 5 {
            lvl = .ok; text = "Spielbar, aber Gegner und Pals springen manchmal."
        } else {
            lvl = .bad; text = "Häufige Lags und Verbindungsabbrüche möglich."
        }
        return RatingRow(name: "Koop & MMO · Palworld, Minecraft", level: lvl, text: text)
    }

    static func cloud(_ r: SpeedResult) -> RatingRow {
        let lvl: Level
        let text: String
        if r.downMbps >= 45 && r.pingMs <= 30 && r.jitterMs <= 8 && r.dropoutPercent <= 0.5 {
            lvl = .great; text = "Bis 4K bzw. 1080p mit 60 Bildern, kaum Eingabeverzögerung."
        } else if r.downMbps >= 25 && r.pingMs <= 45 && r.jitterMs <= 12 && r.dropoutPercent <= 1 {
            lvl = .good; text = "1080p mit 60 Bildern läuft flüssig."
        } else if r.downMbps >= 12 && r.pingMs <= 80 && r.dropoutPercent <= 3 {
            lvl = .ok; text = "Eher 720p, das Bild wird manchmal matschig."
        } else {
            lvl = .bad; text = "Ruckelt und pixelt stark."
        }
        return RatingRow(name: "PS Remote Play & Cloud-Gaming", level: lvl, text: text)
    }

    static func gaming(_ r: SpeedResult) -> Verdict {
        let rows = [shooter(r), coop(r), cloud(r)]
        let lvl = rows.map(\.level).min() ?? .bad
        let head: String
        switch lvl {
        case .great: head = "Perfekt zum Zocken"
        case .good: head = "Gut zum Zocken"
        case .ok: head = "Zocken geht, aber mit Abstrichen"
        case .bad: head = "Nicht gut für Online-Games"
        }
        return Verdict(title: "Gaming", icon: "gamecontroller.fill", level: lvl, headline: head, rows: rows)
    }

    // MARK: Streaming

    static func streaming(_ r: SpeedResult) -> Verdict {
        let d = r.downMbps
        func q(_ need4k: Double, _ needHD: Double, _ needSD: Double) -> (Level, String) {
            if d >= need4k * 2 { return (.great, "4K auf mehreren Geräten gleichzeitig") }
            if d >= need4k { return (.great, "4K Ultra HD") }
            if d >= needHD { return (.good, "Full HD (1080p)") }
            if d >= needSD { return (.ok, "Nur SD, Bild eher unscharf") }
            return (.bad, "Hängt und lädt ständig nach")
        }
        let netflix = q(15, 5, 3)
        let youtube = q(20, 5, 2.5)
        let disney = q(25, 5, 2.5)
        let twitch: (Level, String) = d >= 8 ? (.great, "1080p mit 60 Bildern") : d >= 4.5 ? (.good, "720p mit 60 Bildern") : d >= 2 ? (.ok, "480p") : (.bad, "Ruckelt")
        let live: (Level, String) = r.upMbps >= 10 ? (.great, "Selbst live streamen in 1080p60 möglich") : r.upMbps >= 6 ? (.good, "Live streamen in 1080p30/720p60") : r.upMbps >= 3 ? (.ok, "Live streamen nur in 720p") : (.bad, "Upload zu schwach zum Live-Streamen")

        let rows = [
            RatingRow(name: "Netflix", level: netflix.0, text: netflix.1),
            RatingRow(name: "YouTube", level: youtube.0, text: youtube.1),
            RatingRow(name: "Disney+ / Prime Video", level: disney.0, text: disney.1),
            RatingRow(name: "Twitch zuschauen", level: twitch.0, text: twitch.1),
            RatingRow(name: "Selbst streamen", level: live.0, text: live.1)
        ]
        let main = [netflix.0, youtube.0, twitch.0].min() ?? .bad
        let head: String
        switch main {
        case .great: head = d >= 30 ? "4K-Streaming ohne Probleme" : "4K-Streaming möglich"
        case .good: head = "Full-HD-Streaming läuft"
        case .ok: head = "Nur niedrige Qualität"
        case .bad: head = "Streaming hängt"
        }
        return Verdict(title: "Streaming", icon: "play.tv.fill", level: main, headline: head, rows: rows)
    }

    // MARK: Videocalls & Musik

    static func calls(_ r: SpeedResult) -> Verdict {
        let face: (Level, String)
        if r.upMbps >= 3 && r.downMbps >= 3 && r.pingMs <= 80 && r.jitterMs <= 20 && r.dropoutPercent <= 2 {
            face = (.great, "HD-Video, Gruppen-Calls kein Problem")
        } else if r.upMbps >= 1.5 && r.downMbps >= 1.5 && r.pingMs <= 150 && r.jitterMs <= 35 {
            face = (.good, "Video-Call in guter Qualität")
        } else if r.upMbps >= 0.6 && r.pingMs <= 250 {
            face = (.ok, "Video ruckelt, Sprache geht")
        } else {
            face = (.bad, "Bild friert ein, Ton bricht ab")
        }
        let voice: (Level, String) = (r.pingMs <= 150 && r.jitterMs <= 30 && r.dropoutPercent <= 3) ? (.great, "Glasklar") : (r.pingMs <= 300) ? (.ok, "Verständlich, mit Verzögerung") : (.bad, "Abgehackt")
        let music: (Level, String) = r.downMbps >= 2 ? (.great, "Höchste Qualität ohne Pausen") : r.downMbps >= 0.5 ? (.good, "Normale Qualität") : (.bad, "Stockt")
        let rows = [
            RatingRow(name: "FaceTime, WhatsApp-Video, Zoom", level: face.0, text: face.1),
            RatingRow(name: "Telefonieren übers Internet", level: voice.0, text: voice.1),
            RatingRow(name: "Spotify & Apple Music", level: music.0, text: music.1)
        ]
        let lvl = min(face.0, voice.0)
        let head: String = lvl >= .good ? "Calls laufen sauber" : lvl == .ok ? "Calls mit kleinen Aussetzern" : "Calls werden schwierig"
        return Verdict(title: "Videocalls & Musik", icon: "video.fill", level: lvl, headline: head, rows: rows)
    }

    // MARK: Downloads

    static func seconds(gb: Double, mbps: Double) -> Double {
        guard mbps > 0.01 else { return .infinity }
        return gb * 8000.0 / mbps
    }

    static func downloads(_ r: SpeedResult) -> Verdict {
        let d = r.downMbps
        func row(_ name: String, gb: Double, great: Double, good: Double, ok: Double) -> RatingRow {
            let s = seconds(gb: gb, mbps: d)
            let lvl: Level = s <= great ? .great : s <= good ? .good : s <= ok ? .ok : .bad
            return RatingRow(name: name, level: lvl, text: Fmt.duration(seconds: s))
        }
        let rows = [
            row("PS5-Update (ca. 10 GB)", gb: 10, great: 600, good: 1800, ok: 5400),
            row("Neues Spiel (ca. 50 GB)", gb: 50, great: 2700, good: 7200, ok: 21600),
            row("Riesen-Spiel wie CoD (ca. 150 GB)", gb: 150, great: 7200, good: 21600, ok: 64800),
            row("Film in 4K (ca. 15 GB)", gb: 15, great: 900, good: 2700, ok: 7200),
            row("iPhone-Update (ca. 6 GB)", gb: 6, great: 300, good: 1200, ok: 3600)
        ]
        let lvl = rows[1].level
        let head = "50-GB-Spiel: \(Fmt.duration(seconds: seconds(gb: 50, mbps: d)))"
        return Verdict(title: "Downloads", icon: "arrow.down.circle.fill", level: lvl, headline: head, rows: rows)
    }

    // MARK: Einzelwerte erklärt

    static func pingLevel(_ v: Double) -> Level { v <= 20 ? .great : v <= 40 ? .good : v <= 80 ? .ok : .bad }
    static func jitterLevel(_ v: Double) -> Level { v <= 5 ? .great : v <= 12 ? .good : v <= 30 ? .ok : .bad }
    static func bloatLevel(_ v: Double) -> Level { v <= 30 ? .great : v <= 80 ? .good : v <= 200 ? .ok : .bad }
    static func dropoutLevel(_ v: Double) -> Level { v <= 0.5 ? .great : v <= 2 ? .good : v <= 5 ? .ok : .bad }
    static func downLevel(_ v: Double) -> Level { v >= 100 ? .great : v >= 30 ? .good : v >= 8 ? .ok : .bad }
    static func upLevel(_ v: Double) -> Level { v >= 30 ? .great : v >= 10 ? .good : v >= 3 ? .ok : .bad }
    static func signalLevel(_ v: Int) -> Level { v >= 70 ? .great : v >= 50 ? .good : v >= 30 ? .ok : .bad }
}
