@testable import NetworkChangeNotifier
import XCTest

final class NetworkChangeNotifierTests: XCTestCase {
    func testExample() throws {}
    
    func testAddress() throws {
        let ipaddress = NetworkInterface.getIPAddress(of: "en0")
        print("ipaddress v4: \(ipaddress?.iPv4Address ?? ""), v6: \(ipaddress?.iPv6Address ?? "")")
    }
    
    func testGateway() throws {
        let gateway = NetworkInterface.getGateway(of: "en0")
        print("gateway v4: \(gateway?.iPv4Address ?? ""), v6: \(gateway?.iPv6Address ?? "")")
    }
    
    func testAll() throws {
        let all = NetworkInterface.all()
        print("all: \(all)")
    }
}
