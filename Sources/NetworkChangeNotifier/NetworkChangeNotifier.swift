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

/// Current NetworkChangeNotifier version 0.0.1. Necessary since SPM doesn't use dynamic libraries. Plus this will be more accurate.
public let version = "0.0.1"

#if canImport(Network)

import Network
import SwiftyTimer

public protocol NetworkChangeNotifierDelegate: AnyObject {
    func networkChangeNotifier(shouldNotify newInterface: NetworkInterface?, currentInterface: NetworkInterface?) -> Bool
}

public class NetworkChangeNotifier {
    public typealias NetworkChangeHandler = (NetworkInterface?) -> Void

    public weak var delegate: NetworkChangeNotifierDelegate?

    public var currentInterface: NetworkInterface?

    private var networkChange: NetworkChangeNotifier.NetworkChangeHandler?

    private lazy var throttlerQueue = DispatchQueue(label: "com.networkChangeNotifier")

    private let pathMonitor = Network.NWPathMonitor()

    private var handlerQueue: DispatchQueue

    private var throtter: SwiftyTimer.Throttler?

    private var throttleInterval: SwiftyTimer.Interval?

    private var interfaceExpiration: TimeInterval?

    public init(queue: DispatchQueue = .main, throttleInterval: SwiftyTimer.Interval? = .milliseconds(2000), interfaceExpiration: TimeInterval? = nil) {
        self.handlerQueue = queue
        self.throttleInterval = throttleInterval
        self.interfaceExpiration = interfaceExpiration
        var group: DispatchGroup? = DispatchGroup()
        group?.enter()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let interface = NetworkInterface(path: path)
            self?.updateInterface(interface, ignoreNotify: group != nil)
            group?.leave()
            group = nil
        }
        pathMonitor.start(queue: handlerQueue)
        _ = group?.wait(timeout: .now() + 0.5)
    }

    deinit {
        networkChange = nil
        pathMonitor.cancel()
    }

    public func start(change: NetworkChangeNotifier.NetworkChangeHandler? = nil) {
        stop()
        networkChange = change
    }

    public func stop() {
        networkChange = nil
    }
}

private extension NetworkChangeNotifier {
    private func throtter(interval: SwiftyTimer.Interval) -> SwiftyTimer.Throttler {
        if let throtter = self.throtter {
            return throtter
        }
        let throtter = Throttler(time: interval, queue: throttlerQueue, mode: .fixed, immediateFire: false) { [weak self] in
            self?.handleNetworkChange()
        }
        self.throtter = throtter
        return throtter
    }

    private func updateInterface(_ interface: NetworkInterface?, ignoreNotify: Bool) {
        let shouldTriggerNotify: Bool = {
            if ignoreNotify {
                return false
            }
            if let delegate = self.delegate {
                return delegate.networkChangeNotifier(shouldNotify: interface, currentInterface: currentInterface)
            }
            if interface != currentInterface {
                return true
            }
            if let interfaceExpiration = self.interfaceExpiration,
               let interface = interface,
               let currentInterface = currentInterface,
               abs(interface.timestamp - currentInterface.timestamp) > interfaceExpiration
            {
                return true
            }

            return false
        }()

        currentInterface = interface
        guard shouldTriggerNotify else { return }
        if let throttleInterval = throttleInterval {
            throtter(interval: throttleInterval).call()
        } else {
            handleNetworkChange()
        }
    }

    private func handleNetworkChange() {
        guard let networkChange = networkChange else { return }
        handlerQueue.async { networkChange(self.currentInterface) }
    }
}

#endif
