import Foundation
import Observation

/// Owns the transport and the connection to one Gamemote device (port of the Godot app's
/// device service).
///
/// * connection state machine with auto-reconnect
/// * live control: `setChannel` values are streamed at 30 Hz (coalesced), with a PING
///   keepalive every 250 ms that also measures the round-trip time
/// * `stopAll()` puts every channel back to neutral
///
/// Time is injected: call `poll(nowMs:)` regularly (the app does it from a display-link timer;
/// tests pass a fake clock). Routines (live and transferred) come with the builder port.
@Observable
public final class DeviceLink {
    public enum State: Equatable, Sendable {
        case off, idle, scanning, connecting, ready, reconnecting
    }

    public struct FoundDevice: Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var rssi: Int
    }

    /// Events for the console and other listeners (in addition to the observed properties).
    public enum Event: Equatable, Sendable {
        case log(String)
        case deviceLog(String)
        case rtt(ms: Int)
        case commandFailed(status: UInt8)
        case telemetry(flags: UInt8, step: UInt16, values: [Int16])
    }

    public static let streamPeriodMs = 33
    public static let refreshPeriodMs = 200
    public static let keepalivePeriodMs = 250
    public static let connectTimeoutMs = 10_000
    public static let reconnectDelayMs = 1000
    public static let rttWindow = 40

    public private(set) var state: State = .off
    public private(set) var info: DeviceInfo?
    public private(set) var devices: [FoundDevice] = []
    public private(set) var deviceID = ""
    public private(set) var rttP50: Int?
    public private(set) var rttP95: Int?
    public private(set) var lastTelemetry: [Int16] = []
    public private(set) var transportKind: TransportKind = .mock

    @ObservationIgnored public var onEvent: ((Event) -> Void)?
    @ObservationIgnored public private(set) var transport: Transport?

    @ObservationIgnored private var now = 0
    @ObservationIgnored private var seq: UInt8 = 0
    @ObservationIgnored private var targets: [Int: Int] = [:]
    @ObservationIgnored private var dirty: [Int] = []
    @ObservationIgnored private var lastStreamMs = Int.min / 2
    @ObservationIgnored private var lastRefreshMs = Int.min / 2
    @ObservationIgnored private var lastPingMs = Int.min / 2
    @ObservationIgnored private var rtts: [Int] = []
    @ObservationIgnored private var wantConnected = false
    @ObservationIgnored private var connectStartedMs = 0
    @ObservationIgnored private var reconnectAtMs: Int?

    public init() {}

    public var isReady: Bool { state == .ready }

    /// Plain-word connection state for the UI.
    public var stateText: String {
        switch state {
        case .off: transportKind == .mock ? "Not connected" : "Bluetooth is off"
        case .idle: "Not connected"
        case .scanning: "Looking for your gadget…"
        case .connecting: "Connecting…"
        case .ready: "Connected to \(info?.name ?? "your gadget")"
        case .reconnecting: "Connection lost, reconnecting…"
        }
    }

    // MARK: transport

    /// Switches transport. Drops any current connection.
    public func use(_ newTransport: Transport) {
        if let old = transport {
            wantConnected = false
            old.onEvent = nil
            old.disconnect()
        }
        transport = newTransport
        transportKind = newTransport.kind
        newTransport.onEvent = { [weak self] in self?.handle($0) }
        devices = []
        info = nil
        setState(.off)
        log("Transport: \(newTransport.kind.rawValue)")
        newTransport.start()
    }

    private func log(_ text: String) { onEvent?(.log(text)) }

    private func setState(_ s: State) {
        if state != s { state = s }
    }

    private func nextSeq() -> UInt8 {
        defer { seq &+= 1 }
        return seq
    }

    // MARK: connection

    public func startScan() {
        guard let t = transport, t.isAdapterReady else {
            log("Cannot scan: adapter not ready")
            return
        }
        devices = []
        t.startScan()
        setState(.scanning)
    }

    public func stopScan() {
        transport?.stopScan()
        if state == .scanning { setState(.idle) }
    }

    public func connect(to id: String) {
        deviceID = id
        wantConnected = true
        connectStartedMs = now
        reconnectAtMs = nil
        transport?.stopScan()
        transport?.connect(to: id)
        setState(.connecting)
        log("Connecting to \(devices.first { $0.id == id }?.name ?? id)…")
    }

    /// Disconnects on purpose (no auto-reconnect). Leaves the device at neutral first.
    public func disconnect() {
        wantConnected = false
        reconnectAtMs = nil
        if state == .ready { stopAll() }
        transport?.disconnect()
        setState(transport?.isAdapterReady == true ? .idle : .off)
    }

    private func handle(_ event: TransportEvent) {
        switch event {
        case .adapterChanged(let ready, let message):
            log(message)
            if ready && state == .off { setState(.idle) } else if !ready { setState(.off) }
        case .deviceFound(let id, let name, let rssi):
            let found = FoundDevice(id: id, name: name.isEmpty ? "(unnamed)" : name, rssi: rssi)
            if let i = devices.firstIndex(where: { $0.id == id }) {
                devices[i] = found
            } else {
                devices.append(found)
                log("Found \(found.name) (\(rssi) dBm)")
            }
        case .connected:
            log("Link up, discovering services…")
        case .linkReady(let newInfo):
            info = newInfo
            rtts = []
            rttP50 = nil
            rttP95 = nil
            dirty = []
            targets = Dictionary(uniqueKeysWithValues: newInfo.channels.map { ($0.id, $0.neutral) })
            setState(.ready)
            log("Ready: \(newInfo.name) (fw \(newInfo.fw), protocol \(newInfo.proto))")
        case .connectFailed(_, let reason):
            log("Connect failed: \(reason)")
            if wantConnected && state == .reconnecting {
                reconnectAtMs = now + 2000
            } else {
                wantConnected = false
                setState(transport?.isAdapterReady == true ? .idle : .off)
            }
        case .disconnected(_, let reason):
            log(reason.isEmpty ? "Disconnected" : "Disconnected: \(reason)")
            if wantConnected {
                setState(.reconnecting)
                reconnectAtMs = now + Self.reconnectDelayMs
            } else {
                setState(transport?.isAdapterReady == true ? .idle : .off)
            }
        case .frame(let bytes):
            handleFrame(bytes)
        case .log(let text):
            log(text)
        }
    }

    private func handleFrame(_ bytes: [UInt8]) {
        switch Frame.decode(bytes) {
        case .failure(let e):
            log("Bad frame \(bytes.hexString): \(e.message)")
        case .success(let f):
            switch f.payload {
            case .ack(_, let status):
                if status != GMProtocol.Status.ok.rawValue { onEvent?(.commandFailed(status: status)) }
            case .pong(let t):
                addRTT(Int(UInt32(truncatingIfNeeded: now) &- t))
            case .telemetry(let flags, let step, let values):
                lastTelemetry = values
                onEvent?(.telemetry(flags: flags, step: step, values: values))
            case .log(let text):
                onEvent?(.deviceLog(text))
            default:
                break
            }
        }
    }

    private func addRTT(_ ms: Int) {
        guard (0...10_000).contains(ms) else { return }
        rtts.append(ms)
        if rtts.count > Self.rttWindow { rtts.removeFirst() }
        let sorted = rtts.sorted()
        rttP50 = sorted[sorted.count / 2]
        rttP95 = sorted[Swift.min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        onEvent?(.rtt(ms: ms))
    }

    // MARK: live control

    public func channelValue(_ ch: Int) -> Int { targets[ch] ?? 0 }

    /// Sets the value the device should have; it is streamed on the next tick.
    public func setChannel(_ ch: Int, _ value: Int) {
        guard targets[ch] != value else { return }
        targets[ch] = value
        if !dirty.contains(ch) { dirty.append(ch) }
    }

    public func trigger(_ action: Int, params: [Int] = []) {
        send(Frame(seq: nextSeq(), .trigger(action: UInt8(truncatingIfNeeded: action),
                                            params: params.map { Int16(clamping: $0) })), reliable: true)
    }

    /// Every channel back to neutral, on the device and in the app.
    public func stopAll() {
        for c in info?.channels ?? [] { targets[c.id] = c.neutral }
        dirty = []
        send(Frame(seq: nextSeq(), .stopAll), reliable: true)
    }

    @discardableResult
    private func send(_ frame: Frame, reliable: Bool) -> Bool {
        guard isReady, let t = transport else { return false }
        if !reliable && !t.canSendUnreliable { return false }
        return t.send(frame.encoded(), reliable: reliable)
    }

    private func stream() {
        guard isReady, now - lastStreamMs >= Self.streamPeriodMs, let info else { return }
        lastStreamMs = now
        var pairs: [(Int, Int)] = []
        if !dirty.isEmpty {
            pairs = dirty.map { ($0, targets[$0] ?? 0) }
        } else if now - lastRefreshMs >= Self.refreshPeriodMs {
            // Periodically resend non-neutral values in case an unreliable write was lost.
            lastRefreshMs = now
            pairs = info.channels.compactMap { c in
                let v = targets[c.id] ?? c.neutral
                return v != c.neutral ? (c.id, v) : nil
            }
        }
        var sentAll = true
        for start in stride(from: 0, to: pairs.count, by: GMProtocol.maxSetPairs) {
            let chunk = pairs[start..<Swift.min(start + GMProtocol.maxSetPairs, pairs.count)]
            let frame = Frame(seq: nextSeq(), .set(chunk.map {
                ChannelValue(channel: UInt8(truncatingIfNeeded: $0.0), value: Int16(clamping: $0.1))
            }))
            if send(frame, reliable: false) {
                dirty.removeAll { ch in chunk.contains { $0.0 == ch } }
            } else {
                sentAll = false
            }
        }
        // PING doubles as keepalive (device failsafe) and round-trip-time probe.
        if sentAll && now - lastPingMs >= Self.keepalivePeriodMs {
            if send(Frame(seq: nextSeq(), .ping(t: UInt32(truncatingIfNeeded: now))), reliable: false) {
                lastPingMs = now
            }
        }
    }

    // MARK: main loop

    /// Drives the transport, streaming, timeouts and reconnects. `nowMs` must not go backwards.
    public func poll(nowMs: Int) {
        now = nowMs
        transport?.poll(nowMs: nowMs)
        stream()
        if state == .connecting && now - connectStartedMs > Self.connectTimeoutMs {
            log("Connect timed out")
            wantConnected = false
            transport?.disconnect()
            setState(.idle)
        }
        if state == .reconnecting, let at = reconnectAtMs, now >= at {
            reconnectAtMs = nil
            log("Reconnecting…")
            transport?.connect(to: deviceID)
        }
    }
}
