import Foundation

/// What a transport reports to the device link.
public enum TransportEvent: Equatable, Sendable {
    case adapterChanged(ready: Bool, message: String)
    case deviceFound(id: String, name: String, rssi: Int)
    case connected(id: String)
    case linkReady(DeviceInfo)
    case connectFailed(id: String, reason: String)
    case disconnected(id: String, reason: String)
    case frame([UInt8])
    case log(String)
}

public enum TransportKind: String, Sendable {
    case bluetooth, mock
}

/// Link between the app and one Gamemote device. Implementations: `MockTransport` (in-app
/// simulated device) and, later, a CoreBluetooth transport.
///
/// Lifecycle: start() -> startScan() -> deviceFound... -> connect(to:) -> connected
/// -> linkReady(info) -> frame... -> disconnected. Call poll(nowMs:) regularly from the main thread.
public protocol Transport: AnyObject {
    var kind: TransportKind { get }
    var onEvent: ((TransportEvent) -> Void)? { get set }
    /// True once the radio is usable (scan and connect will work).
    var isAdapterReady: Bool { get }
    /// True when an unreliable (write-without-response) frame can be queued now.
    var canSendUnreliable: Bool { get }
    func start()
    func poll(nowMs: Int)
    func startScan()
    func stopScan()
    func connect(to id: String)
    func disconnect()
    /// Sends one CMD frame. reliable = GATT write with response. False if it could not be queued.
    @discardableResult func send(_ frame: [UInt8], reliable: Bool) -> Bool
}
