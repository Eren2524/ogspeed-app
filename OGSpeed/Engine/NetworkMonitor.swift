import Foundation
import Network
import CoreTelephony
import Observation

@MainActor @Observable
final class NetworkMonitor {
    var kind: ConnectionKind = .unknown
    var radio: String?
    var isExpensive = false
    var isConnected = true

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.update(path) }
        }
        monitor.start(queue: DispatchQueue(label: "ogspeed.path"))
    }

    private func update(_ p: NWPath) {
        isConnected = p.status == .satisfied
        isExpensive = p.isExpensive
        if !isConnected { kind = .none }
        else if p.usesInterfaceType(.wifi) { kind = .wifi }
        else if p.usesInterfaceType(.cellular) { kind = .cellular }
        else if p.usesInterfaceType(.wiredEthernet) { kind = .wired }
        else { kind = .unknown }
        radio = kind == .cellular ? Self.radioTechnology() : nil
    }

    var summary: String {
        if kind == .cellular, let radio { return "Mobilfunk · \(radio)" }
        return kind.label
    }

    static func radioTechnology() -> String? {
        guard let techs = CTTelephonyNetworkInfo().serviceCurrentRadioAccessTechnology?.values else { return nil }
        let names = techs.map { tech -> (Int, String) in
            switch tech {
            case CTRadioAccessTechnologyNR: return (5, "5G")
            case CTRadioAccessTechnologyNRNSA: return (5, "5G")
            case CTRadioAccessTechnologyLTE: return (4, "4G (LTE)")
            case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA:
                return (3, "3G")
            case CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS: return (2, "2G (Edge)")
            default: return (1, "Mobilfunk")
            }
        }
        return names.max { $0.0 < $1.0 }?.1
    }

    /// Eigene IPv4-Adresse im WLAN (en0)
    nonisolated static func localWiFiIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: ifa.ifa_name) == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            ptr = ifa.ifa_next
        }
        return nil
    }
}
