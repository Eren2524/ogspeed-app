import Foundation
import Observation

struct NetService: Identifiable, Hashable {
    var id: String { host }
    let name: String
    let host: String
    let icon: String
    let gaming: Bool
}

enum ServiceList {
    static let baseline = [NetService(name: "Cloudflare", host: "1.1.1.1", icon: "cloud.fill", gaming: false),
                           NetService(name: "Google", host: "www.google.com", icon: "magnifyingglass", gaming: false)]

    static let all: [NetService] = [
        NetService(name: "PlayStation Network", host: "my.playstation.com", icon: "gamecontroller.fill", gaming: true),
        NetService(name: "Xbox Live", host: "www.xbox.com", icon: "gamecontroller.fill", gaming: true),
        NetService(name: "Steam", host: "store.steampowered.com", icon: "gamecontroller.fill", gaming: true),
        NetService(name: "Epic Games / Fortnite", host: "www.epicgames.com", icon: "gamecontroller.fill", gaming: true),
        NetService(name: "Riot (LoL, Valorant)", host: "www.riotgames.com", icon: "gamecontroller.fill", gaming: true),
        NetService(name: "EA / FC", host: "www.ea.com", icon: "soccerball", gaming: true),
        NetService(name: "Discord", host: "discord.com", icon: "bubble.left.and.bubble.right.fill", gaming: true),
        NetService(name: "Netflix", host: "www.netflix.com", icon: "play.tv.fill", gaming: false),
        NetService(name: "YouTube", host: "www.youtube.com", icon: "play.rectangle.fill", gaming: false),
        NetService(name: "Twitch", host: "www.twitch.tv", icon: "tv.fill", gaming: false),
        NetService(name: "Disney+", host: "www.disneyplus.com", icon: "tv.fill", gaming: false),
        NetService(name: "Prime Video", host: "www.primevideo.com", icon: "film.fill", gaming: false),
        NetService(name: "Spotify", host: "open.spotify.com", icon: "music.note", gaming: false),
        NetService(name: "WhatsApp", host: "web.whatsapp.com", icon: "message.fill", gaming: false),
        NetService(name: "Instagram", host: "www.instagram.com", icon: "camera.fill", gaming: false),
        NetService(name: "TikTok", host: "www.tiktok.com", icon: "music.note.tv.fill", gaming: false),
        NetService(name: "iCloud", host: "www.icloud.com", icon: "icloud.fill", gaming: false)
    ]

    static var gamingTargets: [NetService] {
        [NetService(name: "Cloudflare Frankfurt", host: "1.1.1.1", icon: "cloud.fill", gaming: true)] + all.filter(\.gaming)
    }
}

struct ServiceResult: Identifiable, Hashable {
    var id: String { service.id }
    let service: NetService
    let pingMs: Double?
    var ok: Bool { pingMs != nil }
}

/// „Liegt's an mir?“ – prüft, ob die Dienste erreichbar sind
@MainActor @Observable
final class ServiceChecker {
    var results: [ServiceResult] = []
    var baselineOK: Bool?
    var running = false

    var verdict: (Level, String, String)? {
        guard let base = baselineOK, !running else { return nil }
        if !base {
            return (.bad, "Dein Internet ist gerade weg", "Nicht mal Google und Cloudflare antworten. Router neu starten oder WLAN/Mobilfunk prüfen.")
        }
        let failed = results.filter { !$0.ok }
        if failed.isEmpty {
            return (.great, "Bei dir ist alles okay", "Alle Dienste sind erreichbar. Hängt eine App trotzdem, liegt die Störung beim Anbieter selbst – oder die App braucht ein Update.")
        }
        let names = failed.map(\.service.name).joined(separator: ", ")
        return (.ok, "Störung bei \(names)", "Dein Internet läuft. Diese Dienste antworten gerade nicht – das Problem liegt sehr wahrscheinlich bei ihnen, nicht bei dir.")
    }

    func run() async {
        running = true
        results = []
        let base = await withTaskGroup(of: Bool.self) { g -> Bool in
            for s in ServiceList.baseline { g.addTask { await Probes.tcpPing(host: s.host) != nil } }
            var any = false
            for await ok in g where ok { any = true }
            return any
        }
        baselineOK = base
        let list = await withTaskGroup(of: ServiceResult.self) { g -> [ServiceResult] in
            for s in ServiceList.all {
                g.addTask { ServiceResult(service: s, pingMs: await Probes.tcpPing(host: s.host)) }
            }
            var out: [ServiceResult] = []
            for await r in g { out.append(r) }
            return out
        }
        let order = ServiceList.all.map(\.id)
        results = list.sorted { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
        running = false
    }
}

/// Gaming-Ping-Radar: dauerhafte Messung zu Spiele-Servern
@MainActor @Observable
final class PingRadar {
    struct Series: Identifiable {
        var id: String { service.id }
        let service: NetService
        var samples: [Double] = []
        var lost = 0
        var last: Double? { samples.last }
        var avg: Double { samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count) }
        var jitter: Double {
            guard samples.count > 1 else { return 0 }
            var s = 0.0
            for i in 1..<samples.count { s += abs(samples[i] - samples[i - 1]) }
            return s / Double(samples.count - 1)
        }
        var spikes: Int { samples.filter { $0 > avg * 2 + 20 }.count }
    }

    var series: [Series] = ServiceList.gamingTargets.map { Series(service: $0) }
    var running = false
    private var task: Task<Void, Never>?

    func start() {
        task?.cancel()
        running = true
        series = ServiceList.gamingTargets.map { Series(service: $0) }
        task = Task {
            while !Task.isCancelled {
                let targets = series.map(\.service)
                let values = await withTaskGroup(of: (String, Double?).self) { g -> [String: Double?] in
                    for t in targets { g.addTask { (t.id, await Probes.tcpConnect(host: t.host, port: 443, timeout: 2)) } }
                    var out: [String: Double?] = [:]
                    for await (k, v) in g { out[k] = v }
                    return out
                }
                for i in series.indices {
                    if let v = values[series[i].id] ?? nil {
                        series[i].samples.append(v)
                        if series[i].samples.count > 40 { series[i].samples.removeFirst() }
                    } else {
                        series[i].lost += 1
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() { task?.cancel(); running = false }
}

/// DNS-Turbo: welcher Namensserver antwortet am schnellsten?
struct DNSServer: Identifiable, Hashable {
    var id: String { ip }
    let name: String
    let ip: String
    let note: String
}

struct DNSResult: Identifiable, Hashable {
    var id: String { server.id }
    let server: DNSServer
    let medianMs: Double?
    let failures: Int
}

@MainActor @Observable
final class DNSBench {
    var results: [DNSResult] = []
    var running = false
    var progress = 0.0

    /// Bewusst neutrale Namen: ein Zufallsname vor einer harmlosen Domain.
    /// So misst der Test echte Antwortzeiten (nichts liegt im Zwischenspeicher)
    /// und verrät niemandem im WLAN, welche Dienste dich interessieren.
    static let neutralDomains = ["example.com", "example.net", "example.org", "iana.org", "icann.org"]

    static func probeNames(_ count: Int = 10) -> [String] {
        (0..<count).map { i in
            let r = UInt32.random(in: 0...UInt32.max)
            return "og\(String(r, radix: 36)).\(neutralDomains[i % neutralDomains.count])"
        }
    }

    func servers(router: String?) -> [DNSServer] {
        var list: [DNSServer] = []
        if let router { list.append(DNSServer(name: "Dein Router", ip: router, note: "Standard – fragt meist den DNS deines Anbieters")) }
        list += [
            DNSServer(name: "Cloudflare", ip: "1.1.1.1", note: "Sehr schnell, datensparsam"),
            DNSServer(name: "Google", ip: "8.8.8.8", note: "Schnell und zuverlässig"),
            DNSServer(name: "Quad9", ip: "9.9.9.9", note: "Blockt bekannte Schadseiten"),
            DNSServer(name: "AdGuard", ip: "94.140.14.14", note: "Blockt Werbung und Tracker")
        ]
        return list
    }

    func run(router: String?) async {
        running = true
        results = []
        progress = 0
        let list = servers(router: router)
        var out: [DNSResult] = []
        for (i, s) in list.enumerated() {
            var times: [Double] = []
            var fails = 0
            for d in Self.probeNames() {
                if let t = await Probes.dnsQuery(server: s.ip, name: d) { times.append(t) } else { fails += 1 }
            }
            let sorted = times.sorted()
            let med: Double? = sorted.isEmpty ? nil : sorted[sorted.count / 2]
            out.append(DNSResult(server: s, medianMs: med, failures: fails))
            progress = Double(i + 1) / Double(list.count)
            results = out
        }
        results = out.sorted { ($0.medianMs ?? 9999) < ($1.medianMs ?? 9999) }
        running = false
    }
}
