import Foundation
import Observation

// MARK: - Anbieter

enum Provider: String, Codable {
    case telekom, vodafone, o2, einsUndEins, deutscheGlasfaser, other

    var label: String {
        switch self {
        case .telekom: return "Telekom"
        case .vodafone: return "Vodafone"
        case .o2: return "o2 (Telefónica)"
        case .einsUndEins: return "1&1"
        case .deutscheGlasfaser: return "Deutsche Glasfaser"
        case .other: return "Anderer Anbieter"
        }
    }

    static func classify(org: String, asn: Int?) -> Provider {
        let o = org.lowercased()
        let a = asn ?? 0
        if a == 3320 || o.contains("telekom") { return .telekom }
        if [3209, 31334, 6830, 29562].contains(a) || o.contains("vodafone") || o.contains("kabel deutschland")
            || o.contains("unitymedia") || o.contains("liberty") { return .vodafone }
        if [6805, 13184].contains(a) || o.contains("telefonica") || o.contains("telefónica") || o.hasPrefix("o2") { return .o2 }
        if a == 8881 || o.contains("1&1") || o.contains("versatel") || o.contains("united internet") { return .einsUndEins }
        if a == 60294 || o.contains("deutsche glasfaser") { return .deutscheGlasfaser }
        return .other
    }
}

enum AccessType: String {
    case dsl = "DSL", kabel = "Kabel", glasfaser = "Glasfaser", mobil = "Mobilfunk", unbekannt = "Festnetz"
}

// MARK: - Router

enum RouterVendor: String, Codable, CaseIterable {
    case fritz, speedport, vodafoneStation, easybox, o2, tplink, asus, netgear, zyxel, huawei, unknown

    var label: String {
        switch self {
        case .fritz: return "FRITZ!Box"
        case .speedport: return "Telekom Speedport"
        case .vodafoneStation: return "Vodafone Station"
        case .easybox: return "Vodafone EasyBox"
        case .o2: return "o2 HomeBox"
        case .tplink: return "TP-Link"
        case .asus: return "ASUS"
        case .netgear: return "Netgear"
        case .zyxel: return "Zyxel"
        case .huawei: return "Huawei"
        case .unknown: return "Unbekannter Router"
        }
    }
}

struct RouterInfo: Equatable {
    var vendor: RouterVendor
    var model: String?
    var address: String
    var adminURL: String { vendor == .fritz ? "http://fritz.box" : vendor == .speedport ? "http://speedport.ip" : "http://\(address)" }
    var displayName: String { model ?? vendor.label }
}

enum IPv4Mode: Equatable {
    case real            // eigene öffentliche IPv4 – ideal für Konsolen
    case dsLite          // IPv4 nur über Tunnel – Portfreigaben gehen nicht
    case cgnat           // geteilte IPv4 beim Anbieter
    case likelyDsLite    // Vermutung (z. B. Vodafone Station)
    case unknown

    var title: String {
        switch self {
        case .real: return "Echte IPv4 (Dual Stack)"
        case .dsLite: return "DS-Lite (IPv4 nur getunnelt)"
        case .cgnat: return "Geteilte IPv4 (CGNAT)"
        case .likelyDsLite: return "Wahrscheinlich DS-Lite"
        case .unknown: return "Nicht prüfbar"
        }
    }

    var level: Level {
        switch self {
        case .real: return .great
        case .unknown: return .good
        case .likelyDsLite: return .ok
        case .dsLite, .cgnat: return .ok
        }
    }

    var natHint: String {
        switch self {
        case .real: return "PS5/Xbox schaffen NAT-Typ 2 bzw. „Offen“, wenn UPnP/Portfreigabe am Router an ist."
        case .dsLite, .cgnat, .likelyDsLite: return "Konsolen landen oft bei NAT-Typ 3 bzw. „Strikt“: Probleme bei Party-Chat, Matchmaking und Host-Spielen. Abhilfe steht im Turbo-Plan."
        case .unknown: return "Mit FRITZ!Box-Anbindung kann OGSpeed das genau prüfen."
        }
    }
}

struct NetIdentity: Equatable {
    var connection: ConnectionKind
    var radio: String?
    var provider: Provider = .other
    var providerName: String?
    var asn: Int?
    var city: String?
    var access: AccessType = .unbekannt
    var ipv4: String?
    var ipv6: String?
    var router: RouterInfo?
    var ipv4Mode: IPv4Mode = .unknown
    var localIP: String?
    var checked = Date()

    var hasIPv6: Bool { ipv6 != nil }
}

// MARK: - Erkennung

@MainActor @Observable
final class NetDetector {
    static let shared = NetDetector()

    var identity: NetIdentity?
    var running = false
    private var lastKind: ConnectionKind?
    private var task: Task<Void, Never>?

    /// Wird bei jedem Netzwechsel aufgerufen
    func networkChanged(_ kind: ConnectionKind, radio: String?) {
        guard kind != lastKind else { return }
        lastKind = kind
        guard kind != .none else { identity = nil; return }
        refresh(kind: kind, radio: radio)
    }

    func refresh(kind: ConnectionKind, radio: String?) {
        task?.cancel()
        running = true
        task = Task {
            try? await Task.sleep(for: .milliseconds(800))   // Netz erst stabil werden lassen
            let id = await Self.detect(kind: kind, radio: radio)
            if !Task.isCancelled {
                identity = id
                running = false
            }
        }
    }

    nonisolated static func detect(kind: ConnectionKind, radio: String?) async -> NetIdentity {
        var id = NetIdentity(connection: kind, radio: radio)
        let localIP = NetworkMonitor.localWiFiIPv4()
        id.localIP = localIP
        let wantsRouter = kind == .wifi || kind == .wired

        async let meta = Probes.fetchJSON("https://speed.cloudflare.com/meta")
        async let v4 = trace("https://1.1.1.1/cdn-cgi/trace")
        async let v6 = trace("https://[2606:4700:4700::1111]/cdn-cgi/trace")
        async let router = routerIfNeeded(wantsRouter, localIP: localIP)

        if let m = await meta {
            let org = m["asOrganization"] as? String ?? ""
            let asn: Int? = (m["asn"] as? Int) ?? (m["asn"] as? String).flatMap { Int($0) }
            id.providerName = org.isEmpty ? nil : org
            id.asn = asn
            id.city = m["city"] as? String
            id.provider = Provider.classify(org: org, asn: asn)
            if id.ipv4 == nil, let ip = m["clientIp"] as? String, ip.contains(".") { id.ipv4 = ip }
        }
        let t4 = await v4
        let t6 = await v6
        if let ip = t4?["ip"] { id.ipv4 = ip }
        if let ip = t6?["ip"], ip.contains(":") { id.ipv6 = ip }
        id.router = await router

        // Zugangsart
        if kind == .cellular {
            id.access = .mobil
        } else if id.provider == .deutscheGlasfaser {
            id.access = .glasfaser
        } else if id.router?.vendor == .vodafoneStation || (id.router?.model ?? "").lowercased().contains("cable")
                    || [31334, 6830, 29562].contains(id.asn ?? 0) {
            id.access = .kabel
        } else if id.router?.vendor == .fritz, let fiber = id.router?.model, fiber.lowercased().contains("fiber") {
            id.access = .glasfaser
        } else if id.router?.vendor == .speedport || id.router?.vendor == .easybox || id.router?.vendor == .fritz {
            id.access = .dsl
        }

        // IPv4-Art prüfen
        if kind == .cellular {
            id.ipv4Mode = .cgnat   // Im Mobilfunk teilen sich fast immer viele Kunden eine IPv4
        } else if let fritz = FritzClient.fromPrefs(), let ext = try? await fritz.externalIPv4() {
            if ext.isEmpty || ext == "0.0.0.0" || ext.hasPrefix("192.0.0.") { id.ipv4Mode = .dsLite }
            else if isCGNAT(ext) || isPrivate(ext) { id.ipv4Mode = .cgnat }
            else if let pub = id.ipv4, pub == ext { id.ipv4Mode = .real }
            else { id.ipv4Mode = .cgnat }
        } else if id.router?.vendor == .vodafoneStation {
            id.ipv4Mode = .likelyDsLite
        } else if id.provider == .telekom {
            id.ipv4Mode = .real   // Telekom-Festnetz liefert echtes Dual Stack
        } else {
            id.ipv4Mode = .unknown
        }
        id.checked = Date()
        return id
    }

    nonisolated static func trace(_ url: String) async -> [String: String]? {
        guard let res = await Probes.fetchText(url, maxBytes: 4000) else { return nil }
        var out: [String: String] = [:]
        for line in res.text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]) }
        }
        return out.isEmpty ? nil : out
    }

    nonisolated static func isCGNAT(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        return p.count == 4 && p[0] == 100 && (64...127).contains(p[1])
    }

    nonisolated static func isPrivate(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        return p[0] == 10 || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 192 && p[1] == 168)
    }

    // MARK: Router finden

    nonisolated static func routerIfNeeded(_ wanted: Bool, localIP: String?) async -> RouterInfo? {
        guard wanted else { return nil }
        return await detectRouter(localIP: localIP)
    }

    nonisolated static func detectRouter(localIP: String?) async -> RouterInfo? {
        // 1) FRITZ!Box: öffentliche Gerätebeschreibung (ohne Anmeldung)
        if let desc = await Probes.fetchText("http://fritz.box:49000/tr64desc.xml", maxBytes: 20_000),
           let name = FritzClient.tag("friendlyName", in: desc.text) ?? FritzClient.tag("modelName", in: desc.text),
           name.contains("FRITZ") {
            return RouterInfo(vendor: .fritz, model: name, address: "fritz.box")
        }
        // 2) Telekom Speedport hat einen eigenen Namen im Heimnetz
        if let sp = await Probes.fetchText("http://speedport.ip/"), let r = identify(sp.text, server: sp.server, address: "speedport.ip") {
            return r
        }
        // 3) Typische Router-Adressen im eigenen Netz
        var candidates: [String] = []
        if let ip = localIP {
            let parts = ip.split(separator: ".")
            if parts.count == 4 {
                let prefix = parts.prefix(3).joined(separator: ".")
                candidates += ["\(prefix).1", "\(prefix).254"]
            }
        }
        candidates += ["192.168.178.1", "192.168.2.1", "192.168.0.1", "192.168.1.1"]
        var seen = Set<String>()
        let list = candidates.filter { seen.insert($0).inserted }
        let preferred = list.first

        return await withTaskGroup(of: RouterInfo?.self) { group in
            for c in list {
                group.addTask {
                    guard let res = await Probes.fetchText("http://\(c)/") else { return nil }
                    return identify(res.text, server: res.server, address: c)
                        ?? RouterInfo(vendor: .unknown, model: nil, address: c)
                }
            }
            var fallback: RouterInfo?
            for await r in group {
                guard let r else { continue }
                if r.vendor != .unknown {
                    group.cancelAll()
                    return r
                }
                if fallback == nil || r.address == preferred { fallback = r }
            }
            return fallback
        }
    }

    nonisolated static func identify(_ html: String, server: String?, address: String) -> RouterInfo? {
        let t = html + " " + (server ?? "")
        let low = t.lowercased()
        func model(_ pattern: String) -> String? {
            guard let r = t.range(of: pattern, options: .regularExpression) else { return nil }
            return String(t[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if low.contains("fritz!box") || low.contains("fritz.box") {
            return RouterInfo(vendor: .fritz, model: model("FRITZ!Box [0-9A-Za-z ]{2,20}"), address: address)
        }
        if low.contains("speedport") {
            return RouterInfo(vendor: .speedport, model: model("Speedport [A-Za-z0-9 ]{2,18}"), address: address)
        }
        if low.contains("vodafone station") || low.contains("vodafonestation") {
            return RouterInfo(vendor: .vodafoneStation, model: "Vodafone Station", address: address)
        }
        if low.contains("easybox") { return RouterInfo(vendor: .easybox, model: model("EasyBox [0-9A-Za-z ]{2,10}"), address: address) }
        if low.contains("vodafone") && address == "192.168.0.1" {
            return RouterInfo(vendor: .vodafoneStation, model: "Vodafone Station", address: address)
        }
        if low.contains("homebox") || low.contains("o2 box") || low.contains("homespot") {
            return RouterInfo(vendor: .o2, model: model("(o2 )?Home(Box|Spot)[ 0-9A-Za-z]{0,10}"), address: address)
        }
        if low.contains("tp-link") || low.contains("tplink") || low.contains("archer") || low.contains("deco") {
            return RouterInfo(vendor: .tplink, model: model("Archer [A-Z0-9]{2,10}"), address: address)
        }
        if low.contains("asus") || low.contains("asuswrt") { return RouterInfo(vendor: .asus, model: model("RT-[A-Z0-9]{3,10}"), address: address) }
        if low.contains("netgear") || low.contains("nighthawk") || low.contains("orbi") { return RouterInfo(vendor: .netgear, model: nil, address: address) }
        if low.contains("zyxel") { return RouterInfo(vendor: .zyxel, model: nil, address: address) }
        if low.contains("huawei") { return RouterInfo(vendor: .huawei, model: nil, address: address) }
        return nil
    }
}
