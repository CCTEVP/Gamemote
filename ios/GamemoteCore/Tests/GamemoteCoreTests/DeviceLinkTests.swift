import XCTest
@testable import GamemoteCore

/// Drives a DeviceLink against the mock device with a fake clock (deterministic, no timers).
final class DeviceLinkTests: XCTestCase {
    private var link: DeviceLink!
    private var mock: MockTransport!
    private var now = 0
    private var events: [DeviceLink.Event] = []

    override func setUp() {
        link = DeviceLink()
        mock = MockTransport()
        now = 0
        events = []
        link.onEvent = { [unowned self] in self.events.append($0) }
        link.use(mock)
    }

    private func run(ms: Int, step: Int = 10) {
        let end = now + ms
        while now < end {
            now += step
            link.poll(nowMs: now)
        }
    }

    private func connect() {
        link.startScan()
        run(ms: 600)
        XCTAssertEqual(link.devices.map(\.id), [MockTransport.deviceID])
        link.connect(to: MockTransport.deviceID)
        run(ms: 500)
    }

    func testMockAdapterIsReadyAtStart() {
        XCTAssertEqual(link.state, .idle)
    }

    func testScanAndConnectReachesReadyWithInfo() {
        connect()
        XCTAssertEqual(link.state, .ready)
        XCTAssertEqual(link.info?.name, "Gamemote Mock")
        XCTAssertEqual(link.stateText, "Connected to Gamemote Mock")
    }

    func testSetChannelIsStreamedToTheDevice() {
        connect()
        link.setChannel(2, 150)
        run(ms: 100)
        XCTAssertEqual(mock.device.values[2], 150)
    }

    func testValuesAreClampedByTheDevice() {
        connect()
        link.setChannel(3, 500)
        run(ms: 100)
        XCTAssertEqual(mock.device.values[3], 100)
    }

    func testStopAllReturnsEverythingToNeutral() {
        connect()
        link.setChannel(1, 200)
        link.setChannel(3, -50)
        run(ms: 100)
        link.stopAll()
        run(ms: 100)
        XCTAssertEqual(mock.device.values, [1: 0, 2: 90, 3: 0])
        XCTAssertEqual(link.channelValue(1), 0)
    }

    func testPingMeasuresRoundTripTime() {
        connect()
        run(ms: 600)
        XCTAssertNotNil(link.rttP95)
        XCTAssertTrue(events.contains { if case .rtt = $0 { true } else { false } })
    }

    func testTelemetryArrives() {
        connect()
        run(ms: 500)
        XCTAssertEqual(link.lastTelemetry.count, 1)
    }

    func testUnknownActionReportsCommandFailed() {
        connect()
        link.trigger(9)
        run(ms: 100)
        XCTAssertTrue(events.contains(.commandFailed(status: GMProtocol.Status.badID.rawValue)))
    }

    func testLinkLossReconnectsByItself() {
        connect()
        mock.simulateLinkLoss()
        XCTAssertEqual(link.state, .reconnecting)
        run(ms: 1600)
        XCTAssertEqual(link.state, .ready)
    }

    func testDisconnectDoesNotReconnect() {
        connect()
        link.disconnect()
        run(ms: 2000)
        XCTAssertEqual(link.state, .idle)
    }

    func testDeviceFailsSafeWhenFramesStop() {
        let device = MockDevice()
        device.onConnect(nowMs: 0)
        _ = device.handle(Frame(seq: 0, .set([ChannelValue(channel: 3, value: 80)])).encoded(), nowMs: 0)
        XCTAssertEqual(device.values[3], 80)
        _ = device.tick(nowMs: 600)
        XCTAssertEqual(device.values[3], 0)
    }
}

final class ConsoleLogTests: XCTestCase {
    func testUpdateMergesSameKeyOnly() {
        let log = ConsoleLog()
        log.update(key: "stick", "Stick: speed 10")
        log.update(key: "stick", "Stick: speed 20")
        XCTAssertEqual(log.lines.map(\.text), ["Stick: speed 20"])
        log.add("Sent: Beep", kind: .command)
        log.update(key: "stick", "Stick: centred")
        XCTAssertEqual(log.lines.count, 3)
    }

    func testLinesAreCapped() {
        let log = ConsoleLog()
        for i in 0..<(ConsoleLog.maxLines + 10) { log.add("line \(i)") }
        XCTAssertEqual(log.lines.count, ConsoleLog.maxLines)
        XCTAssertEqual(log.lines.last?.text, "line \(ConsoleLog.maxLines + 9)")
    }

    func testRTTTracksLatestAndP95() {
        let log = ConsoleLog()
        for ms in [10, 20, 30, 40] { log.addRTT(ms) }
        XCTAssertEqual(log.latestRTT, 40)
        XCTAssertEqual(log.p95RTT, 40)
    }
}
