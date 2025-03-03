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

/// Current NetworkChangeNotifier version 0.3.3. Necessary since SPM doesn't use dynamic libraries. Plus this will be more accurate.
public let version = "0.3.3"

#if canImport(Network)

import Network
import SwiftyTimer

public protocol NetworkChangeNotifierDelegate: AnyObject, Sendable {
    func shouldChangeBetween(newInterface: NetworkChangeNotifier.NetworkInterface?, currentInterface: NetworkChangeNotifier.NetworkInterface?) -> Bool
}

public extension NetworkChangeNotifier {
    struct UpdateStrategy: Sendable {
        let debouncerDelay: SwiftyTimer.Interval?
        let interfaceExpiration: TimeInterval?
        let ignoreFirstUpdate: Bool

        public init(debouncerDelay: SwiftyTimer.Interval? = nil, interfaceExpiration: TimeInterval? = nil, ignoreFirstUpdate: Bool = false) {
            self.debouncerDelay = debouncerDelay
            self.interfaceExpiration = interfaceExpiration
            self.ignoreFirstUpdate = ignoreFirstUpdate
        }

        public static let `default` = UpdateStrategy(debouncerDelay: nil, interfaceExpiration: nil, ignoreFirstUpdate: false)
    }
}

public class NetworkChangeNotifier: @unchecked Sendable {
    public typealias NetworkChangeHandler = @Sendable (NetworkChangeNotifier.NetworkInterface?) -> Void

    public weak var delegate: NetworkChangeNotifierDelegate?

    public var currentInterface: NetworkChangeNotifier.NetworkInterface?

    private var tempInterface: NetworkChangeNotifier.NetworkInterface?

    public var currentBSDName: String? { currentInterface?.bsdName }

    private var networkChangeHandler: NetworkChangeNotifier.NetworkChangeHandler?

    private let pathMonitor = Network.NWPathMonitor()

    private var handlerQueue: DispatchQueue

    private let pathMonitorQueue = DispatchQueue(label: "com.networkChangeNotifier.pathMonitor")

    private var debouncer: SwiftyTimer.Debouncer?

    private let updateStrategy: UpdateStrategy

    private var didIgnoreFirstUpdate: Bool = false

    public required init(queue: DispatchQueue = .main, updateStrategy: UpdateStrategy = .default) {
        self.handlerQueue = queue
        self.updateStrategy = updateStrategy
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.updateInterface(NetworkChangeNotifier.NetworkInterface(path: path))
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    public convenience init(queue: DispatchQueue = .main, debouncerDelay: SwiftyTimer.Interval? = nil, interfaceExpiration: TimeInterval? = nil, ignoreFirstUpdate: Bool = false) {
        let updateStrategy = UpdateStrategy(debouncerDelay: debouncerDelay, interfaceExpiration: interfaceExpiration, ignoreFirstUpdate: ignoreFirstUpdate)
        self.init(queue: queue, updateStrategy: updateStrategy)
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

    private func updateInterface(_ interface: NetworkChangeNotifier.NetworkInterface?) {
        tempInterface = interface
        guard let _ = networkChangeHandler else {
            currentInterface = tempInterface
            return
        }
        if let debouncerDelay = updateStrategy.debouncerDelay {
            debouncer(interval: debouncerDelay).call()
        } else {
            handleNetworkChange()
        }
    }

    private func handleNetworkChange() {
        let shouldTriggerNotify: Bool = {
            if self.updateStrategy.ignoreFirstUpdate, !self.didIgnoreFirstUpdate {
                self.didIgnoreFirstUpdate = true
                return false
            }
            if let delegate = self.delegate {
                return delegate.shouldChangeBetween(newInterface: tempInterface, currentInterface: currentInterface)
            }
            if self.tempInterface != self.currentInterface {
                return true
            }
            if let interfaceExpiration = self.updateStrategy.interfaceExpiration,
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
