//
//  Extension.swift
//  NetworkChangeNotifier
//
//  Created by CodingIran on 2023/8/8.
//

import Foundation

#if canImport(Network)

import Network

public extension Network.NWEndpoint {
    var hostPort: (host: Network.NWEndpoint.Host, port: Network.NWEndpoint.Port)? {
        switch self {
        case .hostPort(let host, let port):
            return (host, port)
        default:
            return nil
        }
    }

    var service: (name: String, type: String, domain: String, interface: NWInterface?)? {
        switch self {
        case .service(let name, let type, let domain, let interface):
            return (name, type, domain, interface)
        default:
            return nil
        }
    }

    var iPv4Address: String? { hostPort?.host.iPv4Addr }

    var iPv6Address: String? { hostPort?.host.iPv6Addr }
}

public extension Network.NWEndpoint.Host {
    var iPv4Addr: String? {
        switch self {
        case .ipv4(let iPv4Address):
            return iPv4Address.debugDescription
        default:
            return nil
        }
    }

    var iPv6Addr: String? {
        switch self {
        case .ipv6(let iPv6Address):
            return iPv6Address.debugDescription
        default:
            return nil
        }
    }
}

public extension Network.NWInterface.InterfaceType {
    var name: String {
        switch self {
        case .other:
            return "other"
        case .wifi:
            return "wifi"
        case .cellular:
            return "cellular"
        case .wiredEthernet:
            return "wiredEthernet"
        case .loopback:
            return "loopback"
        @unknown default:
            return "other"
        }
    }
}

#endif

#if canImport(SystemConfiguration)

import SystemConfiguration

public extension SCNetworkReachabilityFlags {
    var isReachable: Bool { contains(.reachable) }
    var isConnectionRequired: Bool { contains(.connectionRequired) }
    var canConnectAutomatically: Bool { contains(.connectionOnDemand) || contains(.connectionOnTraffic) }
    var canConnectWithoutUserInteraction: Bool { canConnectAutomatically && !contains(.interventionRequired) }
    var isActuallyReachable: Bool { isReachable && (!isConnectionRequired || canConnectWithoutUserInteraction) }
    var isCellular: Bool {
        #if os(iOS) || os(tvOS)
        return contains(.isWWAN)
        #else
        return false
        #endif
    }
}

#endif

extension CFArray: @retroactive Sequence {
    public func makeIterator() -> AnyIterator<AnyObject> {
        var index = -1
        let maxIndex = CFArrayGetCount(self)
        return AnyIterator {
            index += 1
            guard index < maxIndex else {
                return nil
            }
            let unmanagedObject: UnsafeRawPointer = CFArrayGetValueAtIndex(self, index)
            let rec = unsafeBitCast(unmanagedObject, to: AnyObject.self)
            return rec
        }
    }
}
