import Foundation
import Observation
import GamemoteCore

/// App-wide state: the device link, the console, and the clock that drives them.
/// One instance lives for the whole app; Home, Live and the previews share it.
/// Runs on the main thread: the timer is scheduled on the main run loop.
@Observable
final class AppModel {
    let link = DeviceLink()
    let console = ConsoleLog()

    /// Connect picks the first gadget found (as in the Godot app).
    private var autoConnect = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let start = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var lastState: DeviceLink.State = .off

    init(transport: Transport = MockTransport()) {
        link.onEvent = { [weak self] in self?.handle($0) }
        link.use(transport)
        lastState = link.state
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private var nowMs: Int { Int((ProcessInfo.processInfo.systemUptime - start) * 1000) }

    private func tick() {
        link.poll(nowMs: nowMs)
        if autoConnect, link.state == .scanning, let first = link.devices.first {
            autoConnect = false
            link.connect(to: first.id)
        }
        if link.state != lastState {
            lastState = link.state
            logState()
        }
    }

    // MARK: connection

    var isBusy: Bool { [.ready, .connecting, .reconnecting].contains(link.state) }

    func connectOrDisconnect() {
        if isBusy {
            autoConnect = false
            link.disconnect()
        } else {
            autoConnect = true
            link.startScan()
        }
    }

    /// Why the mode tiles are disabled, in plain words.
    var reason: String {
        switch link.state {
        case .off: "Bluetooth is off. Turn it on, or choose Mock device."
        case .idle, .scanning: "Connect your gadget first"
        case .connecting: "Connecting to your gadget…"
        case .ready: "Pick what you want to do"
        case .reconnecting: "Reconnecting to your gadget…"
        }
    }

    // MARK: console lines (plain words, no protocol terms)

    private func logState() {
        switch link.state {
        case .scanning: console.add("Looking for gadgets…")
        case .connecting: console.add("Connecting…")
        case .ready: console.add(link.stateText)
        case .reconnecting: console.add("Connection lost, reconnecting…", kind: .error)
        case .idle: console.add("Disconnected")
        case .off: console.add("Bluetooth is off", kind: .error)
        }
        if link.state != .ready { console.clearRTT() }
    }

    private func handle(_ event: DeviceLink.Event) {
        switch event {
        case .rtt(let ms):
            console.addRTT(ms)
        case .deviceLog(let text):
            console.add("Gadget says: \(text)", kind: .feedback)
        case .commandFailed(let status):
            console.add(Self.plainError(status), kind: .error)
        case .telemetry(let flags, _, let values):
            if flags & GMProtocol.flagFailsafeTripped != 0 {
                console.update(key: "failsafe", "The gadget stopped itself (it lost contact)", kind: .error)
            }
            let names = link.info?.telemetry.map(\.name) ?? []
            let parts = zip(names, values).map { "\($0) \($1)" }
            if !parts.isEmpty {
                console.update(key: "telemetry", "Gadget reports: " + parts.joined(separator: ", "), kind: .feedback)
            }
        case .log:
            break   // technical log; not shown on the console
        }
    }

    static func plainError(_ status: UInt8) -> String {
        switch GMProtocol.Status(rawValue: status) {
        case .busy: "The gadget is busy, try again"
        case .badProgram: "The gadget could not understand that routine"
        default: "The gadget could not do that"
        }
    }

    // MARK: previews

    /// A model on the mock device; `connected` starts connecting right away (takes ~1 s).
    static func preview(connected: Bool) -> AppModel {
        let model = AppModel()
        if connected { model.connectOrDisconnect() }
        return model
    }
}
