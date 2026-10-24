import Foundation
import Network

/// Event-driven connectivity signal (NWPathMonitor). Sessions use it to retry a
/// failed load exactly once when the network comes back, instead of polling.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private(set) var isExpensive = false
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored var onReconnect: (@MainActor () -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOnline = self.isOnline
                self.isOnline = online
                self.isExpensive = expensive
                if online && !wasOnline {
                    Log.info("Network is back", .web)
                    self.onReconnect?()
                } else if !online && wasOnline {
                    Log.info("Network lost", .web)
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.wispapp.network", qos: .utility))
    }
}
