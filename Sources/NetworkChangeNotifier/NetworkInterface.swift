//
//  NetworkInterface.swift
//  NetworkChangeNotifier
//
//  Created by CodingIran on 2023/8/8.
//

import Foundation

#if canImport(Network)

import Network

public struct NetworkInterface: Equatable {
    public var primaryInterface: String?
    public var ipAddress: String?
    public var timestamp: TimeInterval = 0

    var descriptionMap: [String: String] {
        [
            "interface": primaryInterface ?? "",
            "ipAddress": ipAddress ?? "",
            "timestamp": "\(timestamp)"
        ]
    }

    init?(primaryInterface: String? = nil, ipAddress: String? = nil) {
        guard let primaryInterface else { return nil }
        self.primaryInterface = primaryInterface
        self.ipAddress = ipAddress
        self.timestamp = Date().timeIntervalSince1970
    }

    public static func == (lhs: NetworkInterface, rhs: NetworkInterface) -> Bool {
        return lhs.primaryInterface == rhs.primaryInterface && lhs.ipAddress == rhs.ipAddress
    }
}

public extension NetworkInterface {
    init?(path: Network.NWPath) {
        // 可用的全部网卡
        let availableInterfaces = path.availableInterfaces
        // 过滤出当前使用的网卡
        let usesInterfaces = availableInterfaces.filter { path.usesInterfaceType($0.type) }
        // 过滤掉虚拟网卡
        let interface = usesInterfaces.filter { $0.type != .other }.first ?? availableInterfaces.filter { $0.type != .other }.first
        guard path.status != .unsatisfied, let interface else {
            return nil
        }
        let interfaceName = interface.name
        let ipAddress: String? = NetworkInterface.getIPAddress(of: interfaceName) ?? {
            let iPv4List = path.gateways.compactMap { $0.iPv4Address }
            if !iPv4List.isEmpty {
                return iPv4List.first
            } else {
                let iPv6List = path.gateways.compactMap { $0.iPv6Address }
                return iPv6List.first
            }
        }()
        self.init(primaryInterface: interfaceName, ipAddress: ipAddress)
    }
}

public extension NetworkInterface {
    /// https://github.com/foxglove/foxglove-ios-bridge/blob/858be71d0365d02fc6ba5d4f1eb1f7c0e55b809d/WebSocketDemo-Shared/getIPAddresses.swift#L38
    /// https://developer.apple.com/forums/thread/128215
    static func getIPAddress(of interfaceName: String?, allowIPV6: Bool = true) -> String? {
        guard let interfaceName, interfaceName.count > 0 else { return nil }
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        defer { freeifaddrs(ifaddr) }
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        var ptr = ifaddr
        var ipv6: String?
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) || addrFamily == UInt8(AF_INET6) {
                let name = String(cString: interface.ifa_name)
                if name == interfaceName {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr,
                                socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname,
                                socklen_t(hostname.count),
                                nil,
                                socklen_t(0),
                                NI_NUMERICHOST | NI_NUMERICSERV)

                    let ip = String(cString: hostname)
                    if addrFamily == UInt8(AF_INET) {
                        return ip
                    } else {
                        ipv6 = "\(ip)"
                    }
                }
            }
        }
        return allowIPV6 ? ipv6 : nil
    }
}

#endif
