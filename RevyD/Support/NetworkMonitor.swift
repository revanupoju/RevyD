import Foundation
import Network

/// Monitors network connectivity for offline mode detection.
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "revyd.network")
    private(set) var isConnected = true

    var onStatusChanged: ((Bool) -> Void)?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                let changed = self?.isConnected != connected
                self?.isConnected = connected
                if changed {
                    self?.onStatusChanged?(connected)
                    SessionDebugLogger.log("network", connected ? "Online" : "Offline")
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
