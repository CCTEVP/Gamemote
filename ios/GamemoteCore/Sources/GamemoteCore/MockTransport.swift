import Foundation

/// Simulated link to a `MockDevice` inside the app: no Bluetooth needed. Adds a little
/// latency so the app behaves like it would over a real link. Time comes from poll(nowMs:).
public final class MockTransport: Transport {
    public static let deviceID = "mock-1"
    public static let latencyMs = 20

    public let kind = TransportKind.mock
    public var onEvent: ((TransportEvent) -> Void)?
    public let device: MockDevice
    public var isAdapterReady: Bool { true }
    public var canSendUnreliable: Bool { true }

    private var now = 0
    private var scanning = false
    private var nextAdvertMs = 0
    private var connectAtMs: Int?
    private var linked = false
    private var inbox: [(at: Int, frame: [UInt8])] = []   // app -> device
    private var outbox: [(at: Int, frame: [UInt8])] = []  // device -> app

    public init(device: MockDevice = MockDevice()) {
        self.device = device
        device.onLog = { [weak self] in self?.onEvent?(.log("[mock] " + $0)) }
    }

    public func start() {
        onEvent?(.adapterChanged(ready: true, message: "Mock device (no Bluetooth)"))
    }

    public func poll(nowMs: Int) {
        now = nowMs
        if scanning && now >= nextAdvertMs {
            nextAdvertMs = now + 1000
            onEvent?(.deviceFound(id: Self.deviceID, name: "GM-Mock", rssi: -42))
        }
        if let at = connectAtMs, now >= at {
            connectAtMs = nil
            linked = true
            device.onConnect(nowMs: now)
            onEvent?(.connected(id: Self.deviceID))
            onEvent?(.linkReady(device.info))
        }
        while let first = inbox.first, first.at <= now {
            inbox.removeFirst()
            for evt in device.handle(first.frame, nowMs: now) { outbox.append((now + Self.latencyMs, evt)) }
        }
        for evt in device.tick(nowMs: now) { outbox.append((now + Self.latencyMs, evt)) }
        while linked, let first = outbox.first, first.at <= now {
            outbox.removeFirst()
            onEvent?(.frame(first.frame))
        }
    }

    public func startScan() {
        scanning = true
        nextAdvertMs = now + 400
    }

    public func stopScan() { scanning = false }

    public func connect(to id: String) {
        guard id == Self.deviceID else {
            onEvent?(.connectFailed(id: id, reason: "unknown mock device"))
            return
        }
        scanning = false
        connectAtMs = now + 300
    }

    public func disconnect() { dropLink(reason: "") }

    /// Test hook: drop the link as if the device went out of range.
    public func simulateLinkLoss() { dropLink(reason: "simulated link loss") }

    private func dropLink(reason: String) {
        connectAtMs = nil
        guard linked else { return }
        linked = false
        inbox.removeAll()
        outbox.removeAll()
        device.onDisconnect(nowMs: now)
        onEvent?(.disconnected(id: Self.deviceID, reason: reason))
    }

    @discardableResult
    public func send(_ frame: [UInt8], reliable: Bool) -> Bool {
        guard linked else { return false }
        inbox.append((now + Self.latencyMs, frame))
        return true
    }
}
