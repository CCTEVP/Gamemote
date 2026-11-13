import XCTest
@testable import GamemoteCore

/// Checks the Swift protocol against protocol/test_vectors.json (shared with the Python tools).
final class ProtocolTests: XCTestCase {
    private static let vectors: [String: Any] = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }   // .../Tests/GamemoteCoreTests/<file> -> repo root
        url.appendPathComponent("protocol/test_vectors.json")
        let data = try! Data(contentsOf: url)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()

    private func int(_ d: [String: Any], _ k: String) -> Int { (d[k] as! NSNumber).intValue }

    /// Builds the expected Frame from the vector's dictionary form.
    private func frame(from d: [String: Any]) -> Frame {
        let seq = UInt8(int(d, "seq"))
        let payload: Frame.Payload
        switch d["type"] as! String {
        case "SET":
            let pairs = (d["pairs"] as! [[NSNumber]]).map {
                ChannelValue(channel: UInt8($0[0].intValue), value: Int16($0[1].intValue))
            }
            payload = .set(pairs)
        case "TRIGGER":
            payload = .trigger(action: UInt8(int(d, "action")),
                               params: (d["params"] as! [NSNumber]).map { Int16($0.intValue) })
        case "STOP_ALL": payload = .stopAll
        case "PING": payload = .ping(t: UInt32(int(d, "t")))
        case "PONG": payload = .pong(t: UInt32(int(d, "t")))
        case "ROUTINE_BEGIN": payload = .routineBegin(slot: UInt8(int(d, "slot")), length: UInt16(int(d, "length")))
        case "ROUTINE_CHUNK": payload = .routineChunk(offset: UInt16(int(d, "offset")), data: [UInt8](hex: d["data"] as! String)!)
        case "ROUTINE_END": payload = .routineEnd(crc: UInt16(int(d, "crc")))
        case "ROUTINE_RUN": payload = .routineRun(slot: UInt8(int(d, "slot")))
        case "ROUTINE_STOP": payload = .routineStop
        case "ACK": payload = .ack(refSeq: UInt8(int(d, "ref_seq")), status: UInt8(int(d, "status")))
        case "TELEMETRY":
            payload = .telemetry(flags: UInt8(int(d, "flags")), step: UInt16(int(d, "step")),
                                 values: (d["values"] as! [NSNumber]).map { Int16($0.intValue) })
        case "LOG": payload = .log(d["text"] as! String)
        case "ROUTINE_STATE": payload = .routineState(state: UInt8(int(d, "state")), step: UInt16(int(d, "step")))
        case let other: fatalError("unknown type \(other)")
        }
        return Frame(seq: seq, payload)
    }

    func testCRCCheckValue() {
        for c in Self.vectors["crc"] as! [[String: Any]] {
            let data = Array((c["data_ascii"] as! String).utf8)
            XCTAssertEqual(GMProtocol.crc16(data), UInt16(int(c, "crc")), c["name"] as! String)
        }
    }

    func testFramesEncodeAndDecode() {
        let frames = Self.vectors["frames"] as! [[String: Any]]
        XCTAssertFalse(frames.isEmpty)
        for v in frames {
            let name = v["name"] as! String
            let hex = v["hex"] as! String
            let expected = frame(from: v["frame"] as! [String: Any])
            XCTAssertEqual(expected.encoded().hexString, hex, "encode: \(name)")
            XCTAssertEqual(try? Frame.decode([UInt8](hex: hex)!).get(), expected, "decode: \(name)")
        }
    }

    func testInvalidFramesAreRejected() {
        for v in Self.vectors["invalid_frames"] as! [[String: Any]] {
            let bytes = [UInt8](hex: v["hex"] as! String)!
            if case .success = Frame.decode(bytes) {
                XCTFail("accepted invalid frame: \(v["name"] as! String)")
            }
        }
    }

    func testLogIsTruncatedToFrameSize() {
        let bytes = Frame(seq: 1, .log(String(repeating: "x", count: 40))).encoded()
        XCTAssertEqual(bytes.count, GMProtocol.maxFrame)
    }
}
