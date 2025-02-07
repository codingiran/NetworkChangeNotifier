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

public struct NetworkInterface: Equatable, Codable, Sendable {
    public var bsdName: String
    public var displayName: String?
    public var hardMAC: String?
    public var address: IPEndpoint?
    public var gateway: IPEndpoint?
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
    struct IPEndpoint: Equatable, Codable, Sendable {
        public var iPv4Address: String?
        public var iPv6Address: String?

        public static func == (lhs: NetworkInterface.IPEndpoint, rhs: NetworkInterface.IPEndpoint) -> Bool {
            return lhs.iPv4Address == rhs.iPv4Address && lhs.iPv6Address == rhs.iPv6Address
        }
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
        let ipAddress = NetworkInterface.getIPAddress(of: interfaceName)
        let gateway = NetworkInterface.getGateway(of: interfaceName)
        let type = NetworkInterface.InterfaceType(type: interface.type)
        self.init(bsdName: interfaceName, address: ipAddress, gateway: gateway, type: type)
    }
}

public extension NetworkInterface {
    enum InterfaceType: String, Codable, Sendable {
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

// MARK: - Get IP Address

public extension NetworkInterface {
    /// https://github.com/foxglove/foxglove-ios-bridge/blob/858be71d0365d02fc6ba5d4f1eb1f7c0e55b809d/WebSocketDemo-Shared/getIPAddresses.swift#L38
    /// https://developer.apple.com/forums/thread/128215
    static func getIPAddress(of interfaceName: String?) -> NetworkInterface.IPEndpoint? {
        guard let interfaceName, interfaceName.count > 0 else { return nil }
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        defer { freeifaddrs(ifaddr) }
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        var ptr = ifaddr
        var ipv4List: [String] = []
        var ipv6List: [String] = []
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
                        ipv4List.append(ip)
                    } else if addrFamily == UInt8(AF_INET6) {
                        ipv6List.append(ip)
                    }
                }
            }
        }
        return NetworkInterface.IPEndpoint(iPv4Address: ipv4List.first, iPv6Address: ipv6List.first)
    }
}

// MARK: - Get Gateway

public extension NetworkInterface {
    #if os(iOS) || os(tvOS) || os(watchOS)

    private static let RTAX_GATEWAY = 1
    private static let RTAX_MAX = 8

    private struct rt_metrics {
        public var rmx_locks: UInt32 /* Kernel leaves these values alone */
        public var rmx_mtu: UInt32 /* MTU for this path */
        public var rmx_hopcount: UInt32 /* max hops expected */
        public var rmx_expire: Int32 /* lifetime for route, e.g. redirect */
        public var rmx_recvpipe: UInt32 /* inbound delay-bandwidth product */
        public var rmx_sendpipe: UInt32 /* outbound delay-bandwidth product */
        public var rmx_ssthresh: UInt32 /* outbound gateway buffer limit */
        public var rmx_rtt: UInt32 /* estimated round trip time */
        public var rmx_rttvar: UInt32 /* estimated rtt variance */
        public var rmx_pksent: UInt32 /* packets sent using this route */
        public var rmx_state: UInt32 /* route state */
        public var rmx_filler: (UInt32, UInt32, UInt32) /* will be used for TCP's peer-MSS cache */
    }

    private struct rt_msghdr2 {
        public var rtm_msglen: u_short /* to skip over non-understood messages */
        public var rtm_version: u_char /* future binary compatibility */
        public var rtm_type: u_char /* message type */
        public var rtm_index: u_short /* index for associated ifp */
        public var rtm_flags: Int32 /* flags, incl. kern & message, e.g. DONE */
        public var rtm_addrs: Int32 /* bitmask identifying sockaddrs in msg */
        public var rtm_refcnt: Int32 /* reference count */
        public var rtm_parentflags: Int32 /* flags of the parent route */
        public var rtm_reserved: Int32 /* reserved field set to 0 */
        public var rtm_use: Int32 /* from rtentry */
        public var rtm_inits: UInt32 /* which metrics we are initializing */
        public var rtm_rmx: rt_metrics /* metrics themselves */
    }

    #endif

    static func getGateway(of interfaceName: String?) -> IPEndpoint? {
        guard let interfaceName, interfaceName.count > 0 else { return nil }
        let ipv4Gateway = getRouterAddressFromSysctl(bsd: interfaceName, ipv6: false)
        let ipv6Gateway = getRouterAddressFromSysctl(bsd: interfaceName, ipv6: true)
        return IPEndpoint(iPv4Address: ipv4Gateway, iPv6Address: ipv6Gateway)
    }

    /// https://github.com/OpenIntelWireless/HeliPort/blob/1c3fdb56a7edcd6a38df448fafa5102e3dfa26be/HeliPort/NetworkManager.swift#L333
    private static func getRouterAddressFromSysctl(bsd: String, ipv6: Bool) -> String? {
        var mib: [Int32] = [CTL_NET,
                            PF_ROUTE,
                            0,
                            0,
                            NET_RT_DUMP2,
                            0]
        let mibSize = u_int(mib.count)

        var bufSize = 0
        sysctl(&mib, mibSize, nil, &bufSize, nil, 0)

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        buf.initialize(repeating: 0, count: bufSize)

        guard sysctl(&mib, mibSize, buf, &bufSize, nil, 0) == 0 else { return nil }

        // Routes
        var next = buf
        let lim = next.advanced(by: bufSize)
        while next < lim {
            let rtm = next.withMemoryRebound(to: rt_msghdr2.self, capacity: 1) { $0.pointee }
            var ifname = [CChar](repeating: 0, count: Int(IFNAMSIZ + 1))
            if_indextoname(UInt32(rtm.rtm_index), &ifname)

            if String(cString: ifname) == bsd, let addr = getRouterAddressFromRTM(rtm, next, ipv6) {
                return addr
            }

            next = next.advanced(by: Int(rtm.rtm_msglen))
        }

        return nil
    }

    private static func getRouterAddressFromRTM(_ rtm: rt_msghdr2, _ ptr: UnsafeMutablePointer<UInt8>, _ ipv6: Bool) -> String? {
        var rawAddr = ptr.advanced(by: MemoryLayout<rt_msghdr2>.stride)

        for idx in 0 ..< RTAX_MAX {
            let sockAddr = rawAddr.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0.pointee }

            if (rtm.rtm_addrs & (1 << idx)) != 0 && idx == RTAX_GATEWAY {
                let sa_family = Int32(sockAddr.sa_family)
                if ipv6, sa_family == AF_INET6 {
                    var sAddr6 = rawAddr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }.sin6_addr
                    var addrV6 = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    inet_ntop(AF_INET6, &sAddr6, &addrV6, socklen_t(INET6_ADDRSTRLEN))
                    return String(cString: addrV6, encoding: .ascii)
                }
                if !ipv6, sa_family == AF_INET {
                    let sAddr = rawAddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }.sin_addr
                    // Take the first match, assuming its destination is "default"
                    return String(cString: inet_ntoa(sAddr), encoding: .ascii)
                }
            }

            rawAddr = rawAddr.advanced(by: Int(sockAddr.sa_len))
        }

        return nil
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
            let address = NetworkInterface.getIPAddress(of: bsdName as String)
            let gateway = NetworkInterface.getGateway(of: bsdName as String)
            let instance = NetworkInterface(bsdName: bsdName as String, displayName: displayName as String, hardMAC: hardMAC as String, address: address, gateway: gateway, kind: kind as String, type: type)
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
