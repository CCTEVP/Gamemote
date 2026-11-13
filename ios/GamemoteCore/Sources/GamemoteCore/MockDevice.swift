import Foundation

/// In-app simulated Gamemote device (port of the Godot app's GmMockDevice and
/// tools/gamemote/device.py). Lets the app run without hardware.
///
/// Trial scope: live control, actions, PING, failsafe and telemetry. Routine upload and run
/// answer UNSUPPORTED until the routine builder is ported.
public final class MockDevice {
    public static let failsafeMs = 500
    public static let telemetryPeriodMs = 200

    public static let defaultInfo = DeviceInfo(
        proto: 0, name: "Gamemote Mock", fw: "mock-0.1",
        channels: [
            .init(id: 1, name: "LED", kind: "level", min: 0, max: 255, neutral: 0),
            .init(id: 2, name: "Servo", kind: "angle", min: 0, max: 180, neutral: 90),
            .init(id: 3, name: "Motor", kind: "speed", min: -100, max: 100, neutral: 0),
        ],
        actions: [.init(id: 1, name: "Beep", params: [.init(name: "ms", min: 10, max: 2000, default: 200)])],
        telemetry: [.init(name: "Knob", min: 0, max: 4095)],
        routines: .init(transfer: false, maxBytes: 512, maxLoopDepth: 4)
    )

    public let info: DeviceInfo
    /// Current value per channel id.
    public private(set) var values: [Int: Int] = [:]
    public private(set) var connected = false
    /// Human-readable notes ("[Beep] [200]", "all channels -> neutral (STOP_ALL)").
    public var onLog: ((String) -> Void)?

    private var seq: UInt8 = 0
    private var lastFrameMs = 0
    private var lastTelemetryMs = 0
    private var failsafeTripped = false
    private var liveActive = false

    public init(info: DeviceInfo = MockDevice.defaultInfo) {
        self.info = info
        for c in info.channels { values[c.id] = c.neutral }
    }

    private func nextSeq() -> UInt8 {
        defer { seq &+= 1 }
        return seq
    }

    private func ack(_ ref: UInt8, _ status: GMProtocol.Status) -> [UInt8] {
        Frame(seq: nextSeq(), .ack(refSeq: ref, status: status.rawValue)).encoded()
    }

    private func apply(_ ch: Int, _ value: Int) {
        guard let c = info.channel(ch) else { return }
        values[ch] = Swift.min(Swift.max(value, c.min), c.max)
    }

    private func neutralAll(_ reason: String) {
        var changed = false
        for c in info.channels where values[c.id] != c.neutral {
            changed = true
            values[c.id] = c.neutral
        }
        liveActive = false
        if changed { onLog?("all channels -> neutral (\(reason))") }
    }

    public func onConnect(nowMs: Int) {
        connected = true
        lastFrameMs = nowMs
        lastTelemetryMs = nowMs - Self.telemetryPeriodMs
    }

    public func onDisconnect(nowMs: Int) {
        connected = false
        neutralAll("link lost")
    }

    /// Processes one CMD write; returns EVT frames to notify.
    public func handle(_ data: [UInt8], nowMs: Int) -> [[UInt8]] {
        let frame: Frame
        switch Frame.decode(data) {
        case .failure(let e):
            guard let s = e.seq else { return [] }
            return [ack(s, e.isKnownType ? .badLength : .unknownType)]
        case .success(let f):
            frame = f
        }
        lastFrameMs = nowMs
        failsafeTripped = false
        switch frame.payload {
        case .set(let pairs):
            for p in pairs { apply(Int(p.channel), Int(p.value)) }
            liveActive = true
            return []
        case .trigger(let action, let params):
            guard let a = info.actions.first(where: { $0.id == Int(action) }) else {
                return [ack(frame.seq, .badID)]
            }
            onLog?("[\(a.name)] \(params)")
            return [ack(frame.seq, .ok)]
        case .stopAll:
            neutralAll("STOP_ALL")
            return [ack(frame.seq, .ok)]
        case .ping(let t):
            return [Frame(seq: nextSeq(), .pong(t: t)).encoded()]
        case .routineBegin, .routineEnd, .routineRun:
            return [ack(frame.seq, .unsupported)]
        case .routineChunk:
            return []
        case .routineStop:
            return [ack(frame.seq, .ok)]
        case .ack, .pong, .telemetry, .log, .routineState:
            return [ack(frame.seq, .unknownType)]
        }
    }

    /// Advances time; returns EVT frames to notify (none while disconnected).
    public func tick(nowMs: Int) -> [[UInt8]] {
        guard connected else { return [] }
        if liveActive && nowMs - lastFrameMs > Self.failsafeMs {
            failsafeTripped = true
            neutralAll("failsafe: no frames for 500 ms")
        }
        guard nowMs - lastTelemetryMs >= Self.telemetryPeriodMs else { return [] }
        lastTelemetryMs = nowMs
        var flags: UInt8 = 0
        if failsafeTripped { flags |= GMProtocol.flagFailsafeTripped }
        if liveActive { flags |= GMProtocol.flagLiveActive }
        let knob = Int16(2047 + 2047 * sin(Double(nowMs) / 2000.0))
        return [Frame(seq: nextSeq(), .telemetry(flags: flags, step: GMProtocol.noStep, values: [knob])).encoded()]
    }
}
