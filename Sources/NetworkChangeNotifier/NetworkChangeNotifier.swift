//
//  NetworkChangeNotifier.swift
//  NetworkChangeNotifier
//
//  Created by CodingIran on 2023/8/8.
//

import Foundation

// Enforce minimum Swift version for all platforms and build systems.
#if swift(<5.5)
#error("NetworkChangeNotifier doesn't support Swift versions below 5.5.")
#endif

/// Current NetworkChangeNotifier version 0.1.1. Necessary since SPM doesn't use dynamic libraries. Plus this will be more accurate.
public let version = "0.1.1"

#if canImport(Network)

import Network
import SwiftyTimer

public protocol NetworkChangeNotifierDelegate: AnyObject {
    func shouldChangeBetween(newInterface: NetworkInterface?, currentInterface: NetworkInterface?) -> Bool
}

public class NetworkChangeNotifier {
    public typealias NetworkChangeHandler = (NetworkInterface?) -> Void

    public weak var delegate: NetworkChangeNotifierDelegate?

    public var currentInterface: NetworkInterface?

    private var tempInterface: NetworkInterface?

    public var currentBSDName: String? { currentInterface?.bsdName }

    private var networkChangeHandler: NetworkChangeNotifier.NetworkChangeHandler?

    private let pathMonitor = Network.NWPathMonitor()

    private var handlerQueue: DispatchQueue

    private var debouncer: SwiftyTimer.Debouncer?

    private var debouncerDelay: SwiftyTimer.Interval?

    private var interfaceExpiration: TimeInterval?

    public init(queue: DispatchQueue = .main, debouncerDelay: SwiftyTimer.Interval? = nil, interfaceExpiration: TimeInterval? = nil) {
        self.handlerQueue = queue
        self.debouncerDelay = debouncerDelay
        self.interfaceExpiration = interfaceExpiration
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.updateInterface(NetworkInterface(path: path))
        }
        pathMonitor.start(queue: handlerQueue)
    }

    deinit {
        stop()
        pathMonitor.cancel()
    }

    public func start(change: @escaping NetworkChangeNotifier.NetworkChangeHandler) {
        stop()
        networkChangeHandler = change
    }

    public func stop() {
        networkChangeHandler = nil
    }

    public var currentPath: NWPath {
        pathMonitor.currentPath
    }

    public var availableInterfaces: [NWInterface] {
        guard currentPath.status != .unsatisfied else { return [] }
        return currentPath.availableInterfaces
    }

    public var usesInterfaces: [NWInterface] {
        availableInterfaces.filter { self.currentPath.usesInterfaceType($0.type) }
    }
}

public extension Array where Element == NWInterface {
    var bsdNames: [String] {
        map(\.name)
    }
}

private extension NetworkChangeNotifier {
    private func debouncer(interval: SwiftyTimer.Interval) -> SwiftyTimer.Debouncer {
        if let debouncer = self.debouncer {
            return debouncer
        }
        let debouncer = SwiftyTimer.Debouncer(interval) { [weak self] in
            self?.handleNetworkChange()
        }
        self.debouncer = debouncer
        return debouncer
    }

    private func updateInterface(_ interface: NetworkInterface?) {
        tempInterface = interface
        guard let _ = networkChangeHandler else {
            currentInterface = tempInterface
            return
        }
        if let debouncerDelay = debouncerDelay {
            debouncer(interval: debouncerDelay).call()
        } else {
            handleNetworkChange()
        }
    }

    private func handleNetworkChange() {
        let shouldTriggerNotify: Bool = {
            if let delegate = self.delegate {
                return delegate.shouldChangeBetween(newInterface: tempInterface, currentInterface: currentInterface)
            }
            if tempInterface != currentInterface {
                return true
            }
            if let interfaceExpiration = self.interfaceExpiration,
               let tempInterface = self.tempInterface,
               let currentInterface = self.currentInterface,
               abs(tempInterface.timestamp - currentInterface.timestamp) > interfaceExpiration
            {
                return true
            }
            return false
        }()
        currentInterface = tempInterface
        guard shouldTriggerNotify, let networkChangeHandler = networkChangeHandler else { return }
        handlerQueue.async { networkChangeHandler(self.currentInterface) }
    }
}

#endif
