//
//  NetworkInterface.swift
//  NetworkChangeNotifier
//
//  Created by CodingIran on 2023/8/8.
//

import Foundation
import Network
#if canImport(CoreWLAN)
import CoreWLAN
#endif
#if canImport(SystemConfiguration)
import SystemConfiguration
import SystemConfiguration.CaptiveNetwork
#endif

public struct NetworkInterface: Equatable, Codable {
    public var bsdName: String
    public var displayName: String?
    public var hardMAC: String?
    public var address: String?
    public var kind: String?
    public var type: NetworkInterface.InterfaceType
    public var timestamp = Date().timeIntervalSince1970

    public var descriptionMap: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    public static func == (lhs: NetworkInterface, rhs: NetworkInterface) -> Bool {
        return lhs.bsdName == rhs.bsdName && lhs.address == rhs.address
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
        let type = NetworkInterface.InterfaceType(type: interface.type)
        self.init(bsdName: interfaceName, address: ipAddress, type: type)
    }
}

public extension NetworkInterface {
    enum InterfaceType: String, Codable {
        case wifi
        case cellular
        case wiredEthernet
        case bluetooth
        case loopback
        case other

        init(type: NWInterface.InterfaceType) {
            switch type {
            case .wifi:
                self = .wifi
            case .cellular:
                self = .cellular
            case .wiredEthernet:
                self = .wiredEthernet
            case .loopback:
                self = .loopback
            case .other:
                self = .other
            @unknown default:
                self = .other
            }
        }
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

public extension NetworkInterface {
    @available(macOS 10.15, *)
    @available(iOS 13.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    static func currentWifiSSID() -> String? {
        #if os(macOS)
        return CWWiFiClient.shared().interface()?.ssid()
        #elseif os(iOS)
        var ssid: String?
        if let interfaces = CNCopySupportedInterfaces() as NSArray? {
            for interface in interfaces {
                if let interfaceInfo = CNCopyCurrentNetworkInfo(interface as! CFString) as NSDictionary? {
                    ssid = interfaceInfo[kCNNetworkInfoKeySSID as String] as? String
                    break
                }
            }
        }
        return ssid
        #else
        return nil
        #endif
    }

    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    static func wifiSSID(withInterface interfaceName: String) -> String? {
        #if os(macOS)
        CWWiFiClient.shared().interface(withName: interfaceName)?.ssid()
        #else
        return nil
        #endif
    }

    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    var wifiSSID: String? { NetworkInterface.wifiSSID(withInterface: bsdName) }
}

#if os(macOS)

public extension NetworkInterface {
    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    static func all() -> [NetworkInterface] {
        let interfaces = SCNetworkInterfaceCopyAll()
        var instances: [NetworkInterface] = []
        for interfaceRef in interfaces {
            let interface = interfaceRef as! SCNetworkInterface
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) else { continue }
            guard let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface) else { continue }
            guard let hardMAC = SCNetworkInterfaceGetHardwareAddressString(interface) else { continue }
            guard let kind = SCNetworkInterfaceGetInterfaceType(interface) else { continue }
            let type = NetworkInterface.InterfaceType(kind: kind as String)
            let instance = NetworkInterface(bsdName: bsdName as String, displayName: displayName as String, hardMAC: hardMAC as String, kind: kind as String, type: type)
            instances.append(instance)
        }
        return instances
    }

    static func displayName(with bsdName: String) -> String? { all().first(where: { $0.bsdName == bsdName })?.displayName }

    static func hardMAC(with bsdName: String) -> String? { all().first(where: { $0.bsdName == bsdName })?.hardMAC }
}

public extension NetworkInterface.InterfaceType {
    @available(macOS 10.15, *)
    @available(iOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    init(kind: String?) {
        guard let kind = kind as CFString? else {
            self = .other
            return
        }
        switch kind {
        case kSCNetworkInterfaceTypeEthernet:
            self = .wiredEthernet
        case kSCNetworkInterfaceTypeIEEE80211, kSCNetworkInterfaceTypeWWAN:
            self = .wifi
        case kSCNetworkInterfaceTypeBluetooth:
            self = .bluetooth
        default:
            self = .other
        }
    }
}

#endif
