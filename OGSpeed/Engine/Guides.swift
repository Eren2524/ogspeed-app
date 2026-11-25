import Foundation

enum Impact: Int, Comparable {
    case klein = 1, mittel = 2, gross = 3
    static func < (a: Impact, b: Impact) -> Bool { a.rawValue < b.rawValue }
    var label: String { self == .gross ? "Großer Effekt" : self == .mittel ? "Spürbar" : "Feinschliff" }
}

enum TipTag: String {
    case gaming = "Gaming", wlan = "WLAN", tempo = "Tempo", stabil = "Stabilität", sicher = "Sicherheit"
}

struct GuideTip: Identifiable, Hashable {
    let id: String
    let title: String
    let why: String
    let how: String          // Menüpfad / Schritte
    let impact: Impact
    let tags: [TipTag]
    var caution: String? = nil

    static func == (a: GuideTip, b: GuideTip) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct GuideSection: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let tips: [GuideTip]
}

/// Tipps, um aus Router, Anschluss und iPhone das Maximum herauszuholen.
/// Menüpfade unterscheiden sich je nach Modell und Firmware leicht.
enum Guides {

    static func sections(router: RouterVendor?, provider: Provider?, access: AccessType?, connection: ConnectionKind) -> [GuideSection] {
        var out: [GuideSection] = []
        if connection == .cellular {
            out.append(mobile(provider))
            out.append(iphone)
            return out
        }
        switch router {
        case .fritz?: out.append(fritz(access: access))
        case .speedport?: out.append(speedport)
        case .vodafoneStation?, .easybox?: out.append(vodafoneStation)
        case .o2?: out.append(o2Box)
        default: out.append(genericRouter(router))
        }
        if let p = provider, let s = providerSection(p, access: access, router: router) { out.append(s) }
        out.append(console)
        out.append(iphone)
        out.append(home)
        return out
    }

    // MARK: FRITZ!Box

    static func fritz(access: AccessType?) -> GuideSection {
        var tips: [GuideTip] = [
            GuideTip(id: "fritz.prio", title: "Konsole als „Echtzeitanwendung“ priorisieren",
                     why: "Wenn jemand streamt oder lädt, bleibt dein Ping trotzdem niedrig. Der Router schickt die Spiel-Daten immer zuerst raus – das wirkt direkt gegen „Ping unter Last“.",
                     how: "Internet › Filter › Priorisierung › Echtzeitanwendungen › Neue Regel › PS5/PC auswählen, Netzwerkanwendung „Alle“.",
                     impact: .gross, tags: [.gaming, .stabil]),
            GuideTip(id: "fritz.ports", title: "Selbstständige Portfreigaben für die Konsole erlauben",
                     why: "Damit bekommt die PS5/Xbox meist NAT-Typ 2 bzw. „Offen“ – besseres Matchmaking und Party-Chat ohne Abbrüche.",
                     how: "Internet › Freigaben › Portfreigaben › Gerät für Freigaben hinzufügen › Konsole wählen › Haken bei „Selbstständige Portfreigaben für dieses Gerät erlauben“.",
                     impact: .gross, tags: [.gaming]),
            GuideTip(id: "fritz.ssid", title: "Ein WLAN-Name für alle Funkbänder",
                     why: "Dann schiebt die FRITZ!Box Geräte selbst ins schnellere 5-GHz-Band (Band Steering), statt sie im langsamen 2,4 GHz hängen zu lassen.",
                     how: "WLAN › Funknetz › gleichen Namen für 2,4 und 5 GHz (bzw. Haken „gleicher Name für alle Frequenzbänder“).",
                     impact: .mittel, tags: [.wlan, .tempo]),
            GuideTip(id: "fritz.channel", title: "Autokanal an, volle Kanalbreite und maximale Sendeleistung",
                     why: "Der Autokanal weicht Nachbar-WLANs aus. Mit voller Kanalbreite (80/160 MHz im 5-GHz-Band) und 100 % Sendeleistung holst du das meiste Tempo und die größte Reichweite raus.",
                     how: "WLAN › Funkkanal › „Funkkanal-Einstellungen anpassen“ › Autokanal aktiv, unter „Weitere Einstellungen“ maximale Sendeleistung 100 %.",
                     impact: .mittel, tags: [.wlan, .tempo]),
            GuideTip(id: "fritz.dns", title: "Schnellere und verschlüsselte DNS-Server",
                     why: "Webseiten und Spiel-Lobbys starten schneller, und dein Anbieter sieht nicht mehr mit, welche Seiten du aufrufst. Welcher DNS bei dir am schnellsten ist, zeigt der DNS-Turbo in OGSpeed.",
                     how: "Internet › Zugangsdaten › DNS-Server › „Andere DNSv4-Server verwenden“ (z. B. 1.1.1.1 und 1.0.0.1) und „Verschlüsselte Namensauflösung (DNS over TLS)“ mit one.one.one.one.",
                     impact: .klein, tags: [.tempo, .sicher]),
            GuideTip(id: "fritz.mesh", title: "Mesh statt einzelner Repeater",
                     why: "Mit FRITZ!Repeatern im Mesh wechselt dein iPhone beim Laufen automatisch zum besten Zugangspunkt – ohne Abbruch.",
                     how: "Heimnetz › Mesh › Repeater per Knopfdruck (Connect/WPS) einbinden.",
                     impact: .mittel, tags: [.wlan, .stabil]),
            GuideTip(id: "fritz.update", title: "Automatische Updates einschalten",
                     why: "AVM verbessert mit FRITZ!OS-Updates regelmäßig WLAN-Tempo und DSL-Treiber.",
                     how: "System › Update › Auto-Update › „Über neues FRITZ!OS informieren und neue Versionen automatisch installieren“.",
                     impact: .klein, tags: [.stabil, .sicher]),
            GuideTip(id: "fritz.tr064", title: "Zugriff für Anwendungen zulassen",
                     why: "Damit kann OGSpeed das echte WLAN-Signal, die Leitung und die Geräte im Netz auslesen.",
                     how: "Heimnetz › Netzwerk › Netzwerkeinstellungen › Haken bei „Zugriff für Anwendungen zulassen“. Danach in OGSpeed unter Mehr › FRITZ!Box anmelden.",
                     impact: .mittel, tags: [.wlan])
        ]
        if access != .kabel && access != .glasfaser {
            tips.insert(GuideTip(id: "fritz.dsl", title: "DSL-Störsicherheit auf „maximale Performance“",
                                 why: "Der unbekannteste Regler der FRITZ!Box: Steht er auf Stabilität, verschenkst du Tempo. Läuft die Leitung stabil, gehören alle Regler ganz nach rechts. Wichtig: Danach ca. 14 Tage nicht neu starten – das Leitungsmanagement des Anbieters (DLM) stuft dich erst dann wieder hoch.",
                                 how: "Internet › DSL-Informationen › Störsicherheit (evtl. erst unten „Ansicht: Erweitert“ einschalten) › Regler Richtung „maximale Performance“.",
                                 impact: .gross, tags: [.tempo],
                                 caution: "Bricht die Verbindung danach öfter ab, einen Schritt zurück Richtung Stabilität."), at: 0)
        }
        return GuideSection(title: "Deine FRITZ!Box", icon: "wifi.router.fill", tips: tips)
    }

    // MARK: Telekom Speedport

    static let speedport = GuideSection(title: "Dein Speedport", icon: "wifi.router.fill", tips: [
        GuideTip(id: "sp.upnp", title: "UPnP / Portfreigaben für die Konsole",
                 why: "Die Telekom liefert eine echte IPv4 – mit UPnP bekommt die PS5 so meist NAT-Typ 2.",
                 how: "speedport.ip öffnen (Gerätepasswort steht unten am Router) › Internet › Portfreigaben › UPnP bzw. „Dynamische Portfreigaben“ aktivieren (Name je nach Modell).",
                 impact: .gross, tags: [.gaming]),
        GuideTip(id: "sp.ssid", title: "Ein WLAN-Name für 2,4 und 5 GHz",
                 why: "Der Speedport verteilt Geräte dann selbst auf das bessere Band. Hängen PS5 oder iPhone trotzdem im 2,4-GHz-Band, gib dem 5-GHz-Netz testweise einen eigenen Namen und verbinde sie gezielt damit.",
                 how: "Netzwerk › WLAN-Einstellungen › WLAN-Name (SSID) für beide Bänder.",
                 impact: .mittel, tags: [.wlan, .tempo]),
        GuideTip(id: "sp.channel", title: "Funkkanal automatisch, 5 GHz mit voller Breite",
                 why: "Weicht Nachbar-WLANs aus und nutzt das volle Tempo von Wi-Fi 6.",
                 how: "Netzwerk › WLAN-Einstellungen › Funkkanal auf „Automatisch“, im 5-GHz-Band die größte angebotene Kanalbreite.",
                 impact: .mittel, tags: [.wlan]),
        GuideTip(id: "sp.mesh", title: "Mesh mit Speed Home WLAN",
                 why: "Die Telekom-Mesh-Repeater verbinden sich automatisch mit dem Speedport Smart und lassen dich ohne Abbruch durchs Haus laufen.",
                 how: "Repeater in die Steckdose, WPS-Taste am Speedport und am Repeater drücken.",
                 impact: .mittel, tags: [.wlan, .stabil]),
        GuideTip(id: "sp.app", title: "Router-Einstellungen per MeinMagenta-App",
                 why: "Beim Speedport Smart 4 und Pro Plus kommst du auch übers Handy in die Einstellungen – praktisch fürs WLAN-Tuning beim Herumlaufen.",
                 how: "MeinMagenta-App › Router › Einstellungen.",
                 impact: .klein, tags: [.wlan]),
        GuideTip(id: "sp.dlm", title: "Router nicht ständig neu starten",
                 why: "Viele Neustarts deutet das Leitungsmanagement (DLM) als instabile Leitung und drosselt das Profil. Lass den Router möglichst durchlaufen.",
                 how: "Nur neu starten, wenn wirklich nichts mehr geht.",
                 impact: .mittel, tags: [.stabil, .tempo])
    ])

    // MARK: Vodafone Station

    static let vodafoneStation = GuideSection(title: "Deine Vodafone Station", icon: "wifi.router.fill", tips: [
        GuideTip(id: "vf.dslite", title: "DS-Lite → Dual Stack beantragen",
                 why: "Der wichtigste Gaming-Tipp bei Vodafone Kabel: Im normalen Router-Modus läuft die Station auf DS-Lite. Du hast dann keine eigene IPv4 – PS5/Xbox landen oft bei NAT-Typ 3/Strikt, Portfreigaben funktionieren nicht, manche Spiele haben Verbindungsprobleme.",
                 how: "Beim Vodafone-Kundenservice oder im Vodafone-Forum um Umstellung auf „Dual Stack“ (eigene IPv4) bitten und Gaming-Probleme nennen. Je nach Region klappt das auf Kulanz, teils nur mit Zusatzoption.",
                 impact: .gross, tags: [.gaming, .stabil]),
        GuideTip(id: "vf.bridge", title: "Profi-Weg: Bridge-Modus + eigener Router",
                 why: "Mit einer eigenen Kabel-FRITZ!Box (z. B. 6660/6690 Cable) hast du viel mehr Einstellungen: Priorisierung, Mesh, Portfreigaben, Störungsdiagnose.",
                 how: "Eigenen Kabelrouter bei Vodafone anmelden (Routerfreiheit) oder Station in den Bridge-Modus setzen lassen.",
                 impact: .gross, tags: [.gaming, .wlan],
                 caution: "Im Bridge-Modus macht die Station kein WLAN mehr – das übernimmt dann dein eigener Router."),
        GuideTip(id: "vf.bands", title: "2,4 und 5 GHz getrennt benennen",
                 why: "Die Station lässt Geräte gern im langsamen 2,4-GHz-Band hängen. Mit eigenem Namen für 5 GHz verbindest du PS5, iPhone und TV gezielt mit dem schnellen Band.",
                 how: "192.168.0.1 im Browser › WLAN › Einstellungen › getrennte Namen (z. B. „Zuhause“ und „Zuhause-5G“).",
                 impact: .mittel, tags: [.wlan, .tempo]),
        GuideTip(id: "vf.channel", title: "Kanal und Kanalbreite",
                 why: "Im 5-GHz-Band bringt die größte Kanalbreite (80 MHz oder mehr) das meiste Tempo. Bei Abbrüchen hilft ein fester Kanal ohne Nachbarn.",
                 how: "WLAN › Erweiterte Einstellungen › 5 GHz: Kanal automatisch, Bandbreite maximal.",
                 impact: .mittel, tags: [.wlan]),
        GuideTip(id: "vf.evening", title: "Abends langsam? Messprotokoll sammeln",
                 why: "Beim Kabel teilen sich viele Haushalte ein Segment. Bricht das Tempo abends regelmäßig ein, ist das Segment überlastet – das muss Vodafone beheben.",
                 how: "OGSpeed › Verlauf zeigt, wann es einbricht. Mit Tarif-Check-PDF bei Vodafone eine Störung melden.",
                 impact: .mittel, tags: [.tempo])
    ])

    // MARK: o2 HomeBox

    static let o2Box = GuideSection(title: "Deine o2 HomeBox", icon: "wifi.router.fill", tips: [
        GuideTip(id: "o2.upnp", title: "UPnP für die Konsole einschalten",
                 why: "Für besseren NAT-Typ an PS5 und Xbox.",
                 how: "Router-Oberfläche (meist 192.168.1.1) › Netzwerk/Internet › UPnP aktivieren.",
                 impact: .gross, tags: [.gaming]),
        GuideTip(id: "o2.wlan", title: "5 GHz bevorzugen, Kanal automatisch",
                 why: "Mehr Tempo und weniger Störungen durch Nachbarn.",
                 how: "WLAN-Einstellungen › 5-GHz-Netz aktiv, Kanal automatisch, größte Kanalbreite.",
                 impact: .mittel, tags: [.wlan, .tempo])
    ])

    static func genericRouter(_ v: RouterVendor?) -> GuideSection {
        let name = v.map { $0 == .unknown ? "Dein Router" : "Dein \($0.label)-Router" } ?? "Dein Router"
        return GuideSection(title: name, icon: "wifi.router.fill", tips: [
            GuideTip(id: "gen.qos", title: "QoS / Gaming-Priorisierung einschalten",
                     why: "Fast jeder Router kann Spiele bevorzugen (QoS, „Game Boost“, „Gaming-Modus“). Das hält den Ping niedrig, wenn andere streamen.",
                     how: "Router-Oberfläche › QoS bzw. Priorisierung › Konsole/PC oben einordnen.",
                     impact: .gross, tags: [.gaming, .stabil]),
            GuideTip(id: "gen.upnp", title: "UPnP für Konsolen",
                     why: "Für NAT-Typ 2 bzw. „Offen“ an PS5/Xbox.",
                     how: "Router-Oberfläche › NAT/Weiterleitung › UPnP aktivieren.",
                     impact: .gross, tags: [.gaming]),
            GuideTip(id: "gen.wlan", title: "Autokanal, 5 GHz, volle Kanalbreite",
                     why: "Mehr Tempo und weniger Störungen.",
                     how: "WLAN-Einstellungen › Kanal automatisch, 5 GHz mit größter Kanalbreite.",
                     impact: .mittel, tags: [.wlan, .tempo]),
            GuideTip(id: "gen.fw", title: "Firmware aktualisieren",
                     why: "Updates bringen bessere WLAN-Treiber und schließen Sicherheitslücken.",
                     how: "Router-Oberfläche › System › Firmware-Update.",
                     impact: .klein, tags: [.sicher, .stabil])
        ])
    }

    // MARK: Anbieter

    static func providerSection(_ p: Provider, access: AccessType?, router: RouterVendor?) -> GuideSection? {
        switch p {
        case .telekom:
            return GuideSection(title: "Telekom-Anschluss", icon: "t.circle.fill", tips: [
                GuideTip(id: "tk.dual", title: "Du hast echtes Dual Stack",
                         why: "Die Telekom gibt dir eine eigene IPv4 und IPv6 – die besten Voraussetzungen für Konsolen und Portfreigaben. Du musst nichts beantragen.",
                         how: "Nur UPnP bzw. Portfreigaben am Router aktivieren.",
                         impact: .mittel, tags: [.gaming]),
                GuideTip(id: "tk.check", title: "Leitung von der Telekom prüfen lassen",
                         why: "Liegt das Tempo dauerhaft unter dem Vertrag, kann die Telekom die Leitung aus der Ferne messen und das Profil zurücksetzen.",
                         how: "MeinMagenta-App › Hilfe › Anschluss prüfen, oder Störung mit OGSpeed-Protokoll melden.",
                         impact: .mittel, tags: [.tempo])
            ])
        case .vodafone:
            guard access == .kabel || router == .vodafoneStation else { return nil }
            var tips: [GuideTip] = []
            if router != .vodafoneStation {
                tips.append(GuideTip(id: "vfk.dslite", title: "Prüfen: DS-Lite oder Dual Stack?",
                                     why: "Bei Vodafone Kabel läuft der Anschluss oft über DS-Lite – ohne eigene IPv4. Für Gaming und Portfreigaben ist Dual Stack besser.",
                                     how: "Den Status zeigt OGSpeed oben bei „Mein Anschluss“. Bei DS-Lite um Umstellung auf Dual Stack bitten.",
                                     impact: .gross, tags: [.gaming]))
            }
            tips.append(GuideTip(id: "vfk.cable", title: "Kabelanschluss: Dose und Kabel prüfen",
                                 why: "Alte Antennenkabel, Verteiler oder Verlängerungen kosten bei Kabel-Internet Signal und verursachen Aussetzer.",
                                 how: "Router direkt an die Multimediadose (Mitte) mit dem mitgelieferten Kabel, ohne Verteiler.",
                                 impact: .mittel, tags: [.stabil]))
            return GuideSection(title: "Vodafone Kabel", icon: "cable.coaxial", tips: tips)
        case .einsUndEins:
            return GuideSection(title: "1&1-Anschluss", icon: "1.circle.fill", tips: [
                GuideTip(id: "11.line", title: "Leitungsprofil im Blick behalten",
                         why: "1&1 nutzt meist Telekom-Leitungen. Nach Störungen stuft das Leitungsmanagement oft herunter und erholt sich erst nach einigen Tagen ohne Neustart.",
                         how: "Bei dauerhaft zu wenig Tempo: OGSpeed-Protokoll an den 1&1-Support schicken und Leitungsmessung verlangen.",
                         impact: .mittel, tags: [.tempo])
            ])
        default:
            return nil
        }
    }

    // MARK: Konsole, iPhone, Zuhause

    static let console = GuideSection(title: "PS5 & Konsole", icon: "gamecontroller.fill", tips: [
        GuideTip(id: "con.lan", title: "LAN-Kabel statt WLAN",
                 why: "Der größte Gaming-Boost überhaupt: kein Jitter, keine Aussetzer durch Nachbar-WLANs. Geht kein Kabel, sind Powerline-Adapter die zweitbeste Lösung.",
                 how: "Konsole per Netzwerkkabel an den Router; PS5: Einstellungen › Netzwerk › Einstellungen › Internetverbindung einrichten › „LAN-Kabel verwenden“.",
                 impact: .gross, tags: [.gaming, .stabil]),
        GuideTip(id: "con.nat", title: "NAT-Typ an der PS5 prüfen",
                 why: "NAT-Typ 2 ist das Ziel. Typ 3 bedeutet Probleme mit Party-Chat und Matchmaking.",
                 how: "PS5: Einstellungen › Netzwerk › Verbindungsstatus › Internetverbindung testen.",
                 impact: .mittel, tags: [.gaming]),
        GuideTip(id: "con.rest", title: "Downloads im Ruhemodus",
                 why: "Updates laufen nachts im Ruhemodus, statt dir beim Zocken das Netz zu blockieren.",
                 how: "PS5: Einstellungen › System › Energiesparen › Im Ruhemodus verfügbare Funktionen › „Mit dem Internet verbunden bleiben“.",
                 impact: .klein, tags: [.gaming, .tempo])
    ])

    static let iphone = GuideSection(title: "Dein iPhone", icon: "iphone", tips: [
        GuideTip(id: "ip.private", title: "„Private WLAN-Adresse“ zu Hause auf „Fest“",
                 why: "Wechselt das iPhone seine Adresse, erkennt der Router es nicht wieder – Priorisierung, Geräte-Namen und FRITZ!Box-Auswertung gehen verloren.",
                 how: "Einstellungen › WLAN › (i) neben deinem WLAN › Private WLAN-Adresse › „Fest“.",
                 impact: .mittel, tags: [.wlan]),
        GuideTip(id: "ip.lowdata", title: "Datensparmodus im WLAN aus",
                 why: "Im Datensparmodus bremst iOS Hintergrund-Updates und Streaming-Qualität.",
                 how: "Einstellungen › WLAN › (i) › Datensparmodus aus.",
                 impact: .klein, tags: [.tempo]),
        GuideTip(id: "ip.dns", title: "Schnelleren DNS direkt am iPhone",
                 why: "Wenn du am Router nichts ändern kannst: Der DNS-Turbo in OGSpeed zeigt, welcher Server bei dir am schnellsten antwortet.",
                 how: "Einstellungen › WLAN › (i) › DNS konfigurieren › Manuell › z. B. 1.1.1.1 hinzufügen.",
                 impact: .klein, tags: [.tempo])
    ])

    static let home = GuideSection(title: "Aufstellung & Zuhause", icon: "house.fill", tips: [
        GuideTip(id: "home.place", title: "Router frei und erhöht aufstellen",
                 why: "Im Schrank, hinter dem Fernseher oder auf dem Boden verliert das WLAN bis zur Hälfte seiner Reichweite.",
                 how: "Mittig in der Wohnung, auf Kopfhöhe, Antennen senkrecht. Die Wärmekarte im WLAN-Tab zeigt dir, ob es was gebracht hat.",
                 impact: .gross, tags: [.wlan]),
        GuideTip(id: "home.interf", title: "Störquellen weg vom Router",
                 why: "Mikrowelle, Babyphone, DECT-Basis, Aquarien und Spiegel stören das WLAN.",
                 how: "Mindestens 1–2 Meter Abstand halten.",
                 impact: .mittel, tags: [.wlan, .stabil])
    ])

    // MARK: Mobilfunk

    static func mobile(_ p: Provider?) -> GuideSection {
        var tips: [GuideTip] = [
            GuideTip(id: "mob.5g", title: "5G fest einschalten",
                     why: "In „5G Auto“ spart das iPhone Akku und bleibt oft bei 4G. Mit „5G Ein“ nutzt es 5G, wo immer es geht.",
                     how: "Einstellungen › Mobilfunk › Mobilfunkoptionen › Sprache & Daten › „5G Ein“.",
                     impact: .gross, tags: [.tempo]),
            GuideTip(id: "mob.moredata", title: "„Mehr Daten bei 5G erlauben“",
                     why: "Dann laden FaceTime, Streams und Updates über 5G in voller Qualität.",
                     how: "Einstellungen › Mobilfunk › Mobilfunkoptionen › Datenmodus › „Mehr Daten bei 5G erlauben“.",
                     impact: .mittel, tags: [.tempo],
                     caution: "Verbraucht mehr Datenvolumen."),
            GuideTip(id: "mob.assist", title: "WLAN-Assistent einschalten",
                     why: "Bei schwachem WLAN wechselt das iPhone automatisch auf Mobilfunk, statt zu hängen.",
                     how: "Einstellungen › Mobilfunk › ganz unten „WLAN-Assistent“.",
                     impact: .klein, tags: [.stabil]),
            GuideTip(id: "mob.wificall", title: "WLAN-Call für schlechten Empfang drinnen",
                     why: "Telefonieren über dein WLAN, wenn das Handynetz im Haus schwach ist.",
                     how: "Einstellungen › Mobilfunk › WLAN-Anrufe › an (wenn dein Tarif es unterstützt).",
                     impact: .klein, tags: [.stabil])
        ]
        if let p, p != .other {
            tips.append(GuideTip(id: "mob.provider", title: "Netzabdeckung von \(p.label) prüfen",
                                 why: "Die Netzkarte zeigt, ob an deinem Ort 5G verfügbar ist oder eine Störung vorliegt.",
                                 how: "Auf der Webseite von \(p.label) nach „Netzabdeckung“ bzw. „Netzstatus“ suchen.",
                                 impact: .klein, tags: [.tempo]))
        }
        return GuideSection(title: "Mobilfunk-Turbo", icon: "antenna.radiowaves.left.and.right", tips: tips)
    }

    // MARK: Persönlicher Turbo-Plan

    /// Die drei wichtigsten Tipps für genau dein Netz und deinen letzten Test.
    static func turboPlan(identity: NetIdentity?, last: SpeedResult?, sections: [GuideSection], done: Set<String>) -> [GuideTip] {
        let all = sections.flatMap(\.tips).filter { !done.contains($0.id) }
        var picked: [GuideTip] = []
        func add(_ id: String) {
            if let t = all.first(where: { $0.id == id }), !picked.contains(t) { picked.append(t) }
        }
        if let mode = identity?.ipv4Mode, mode == .dsLite || mode == .likelyDsLite {
            add("vf.dslite"); add("vfk.dslite")
        }
        if let r = last {
            if r.bufferbloatMs > 60 { add("fritz.prio"); add("gen.qos") }
            if let s = r.signalPercent, s < 50 { add("home.place"); add("fritz.mesh"); add("sp.mesh") }
            if let b = r.band, b.hasPrefix("2,4") { add("fritz.ssid"); add("vf.bands"); add("sp.ssid") }
            if r.connection == .cellular && r.downMbps < 50 { add("mob.5g") }
            if r.pingMs > 40 || r.jitterMs > 10 { add("con.lan") }
        }
        for t in all.sorted(by: { $0.impact > $1.impact }) where picked.count < 3 {
            if !picked.contains(t) { picked.append(t) }
        }
        return Array(picked.prefix(3))
    }
}
