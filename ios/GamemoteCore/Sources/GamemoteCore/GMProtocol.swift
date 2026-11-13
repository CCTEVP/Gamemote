import Foundation

/// Gamemote BLE protocol v0: frame encoding and decoding. See protocol/PROTOCOL.md.
/// Pure functions, no I/O. Verified against protocol/test_vectors.json.
public enum GMProtocol {
    public static let serviceUUID = "4afc0001-28d2-43f3-abb0-be04c0c1413f"
    public static let cmdUUID = "4afc0002-28d2-43f3-abb0-be04c0c1413f"
    public static let evtUUID = "4afc0003-28d2-43f3-abb0-be04c0c1413f"
    public static let infoUUID = "4afc0004-28d2-43f3-abb0-be04c0c1413f"

    public static let maxFrame = 20
    public static let maxSetPairs = 6
    public static let maxChunk = 16
    public static let noStep: UInt16 = 0xFFFF

    /// Frame type bytes. App -> device are 0x01...0x14, device -> app are 0x81...0x85.
    public enum FrameType: UInt8, CaseIterable, Sendable {
        case set = 0x01, trigger = 0x02, stopAll = 0x03, ping = 0x04
        case routineBegin = 0x10, routineChunk = 0x11, routineEnd = 0x12, routineRun = 0x13, routineStop = 0x14
        case ack = 0x81, pong = 0x82, telemetry = 0x83, log = 0x84, routineState = 0x85

        /// The name used in protocol/PROTOCOL.md and the test vectors ("SET", "STOP_ALL"...).
        public var specName: String {
            switch self {
            case .set: "SET"
            case .trigger: "TRIGGER"
            case .stopAll: "STOP_ALL"
            case .ping: "PING"
            case .routineBegin: "ROUTINE_BEGIN"
            case .routineChunk: "ROUTINE_CHUNK"
            case .routineEnd: "ROUTINE_END"
            case .routineRun: "ROUTINE_RUN"
            case .routineStop: "ROUTINE_STOP"
            case .ack: "ACK"
            case .pong: "PONG"
            case .telemetry: "TELEMETRY"
            case .log: "LOG"
            case .routineState: "ROUTINE_STATE"
            }
        }
    }

    /// ACK status codes.
    public enum Status: UInt8, Sendable {
        case ok = 0, unknownType, badLength, badID, busy, badProgram, unsupported, tooLarge
    }

    /// TELEMETRY flag bits.
    public static let flagRoutineRunning: UInt8 = 0x01
    public static let flagFailsafeTripped: UInt8 = 0x02
    public static let flagLiveActive: UInt8 = 0x04

    /// ROUTINE_STATE.state values.
    public enum RoutineState: UInt8, Sendable {
        case idle = 0, running, finished, stopped, error
    }

    /// CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflection.
    public static func crc16<S: Sequence>(_ data: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }
}

/// One channel and the value to set it to (a SET pair).
public struct ChannelValue: Equatable, Sendable {
    public var channel: UInt8
    public var value: Int16
    public init(channel: UInt8, value: Int16) {
        self.channel = channel
        self.value = value
    }
}

/// A decoded frame: header plus a typed payload.
public struct Frame: Equatable, Sendable {
    public var seq: UInt8
    public var payload: Payload

    public init(seq: UInt8, _ payload: Payload) {
        self.seq = seq
        self.payload = payload
    }

    /// Payload per frame type (field names follow protocol/PROTOCOL.md).
    public enum Payload: Equatable, Sendable {
        case set([ChannelValue])
        case trigger(action: UInt8, params: [Int16])
        case stopAll
        case ping(t: UInt32)
        case routineBegin(slot: UInt8, length: UInt16)
        case routineChunk(offset: UInt16, data: [UInt8])
        case routineEnd(crc: UInt16)
        case routineRun(slot: UInt8)
        case routineStop
        case ack(refSeq: UInt8, status: UInt8)
        case pong(t: UInt32)
        case telemetry(flags: UInt8, step: UInt16, values: [Int16])
        case log(String)
        case routineState(state: UInt8, step: UInt16)
    }

    public var type: GMProtocol.FrameType {
        switch payload {
        case .set: .set
        case .trigger: .trigger
        case .stopAll: .stopAll
        case .ping: .ping
        case .routineBegin: .routineBegin
        case .routineChunk: .routineChunk
        case .routineEnd: .routineEnd
        case .routineRun: .routineRun
        case .routineStop: .routineStop
        case .ack: .ack
        case .pong: .pong
        case .telemetry: .telemetry
        case .log: .log
        case .routineState: .routineState
        }
    }

    /// Encodes the frame to bytes (little-endian multi-byte fields).
    public func encoded() -> [UInt8] {
        var out: [UInt8] = [type.rawValue, seq]
        switch payload {
        case .set(let pairs):
            for p in pairs {
                out.append(p.channel)
                out.appendLE(p.value)
            }
        case .trigger(let action, let params):
            out.append(action)
            for p in params { out.appendLE(p) }
        case .stopAll, .routineStop:
            break
        case .ping(let t), .pong(let t):
            out.appendLE(t)
        case .routineBegin(let slot, let length):
            out.append(slot)
            out.appendLE(length)
        case .routineChunk(let offset, let data):
            out.appendLE(offset)
            out.append(contentsOf: data)
        case .routineEnd(let crc):
            out.appendLE(crc)
        case .routineRun(let slot):
            out.append(slot)
        case .ack(let refSeq, let status):
            out.append(refSeq)
            out.append(status)
        case .telemetry(let flags, let step, let values):
            out.append(flags)
            out.appendLE(step)
            for v in values { out.appendLE(v) }
        case .log(let text):
            out.append(contentsOf: Array(Array(text.utf8).prefix(GMProtocol.maxFrame - 2)))
        case .routineState(let state, let step):
            out.append(state)
            out.appendLE(step)
        }
        return out
    }

    /// Why a frame could not be decoded. `type` and `seq` are set when the header was readable.
    public struct DecodeError: Error, Equatable, Sendable {
        public var message: String
        public var typeByte: UInt8?
        public var seq: UInt8?
        /// True when the type byte is a known frame type (the length was wrong).
        public var isKnownType: Bool { typeByte.flatMap(GMProtocol.FrameType.init(rawValue:)) != nil }
    }

    /// Decodes any frame.
    public static func decode(_ bytes: [UInt8]) -> Result<Frame, DecodeError> {
        guard bytes.count >= 2 else {
            return .failure(DecodeError(message: "frame shorter than header"))
        }
        let t = bytes[0], seq = bytes[1]
        func bad(_ m: String) -> Result<Frame, DecodeError> {
            .failure(DecodeError(message: m, typeByte: t, seq: seq))
        }
        guard bytes.count <= GMProtocol.maxFrame else { return bad("frame longer than 20 bytes") }
        guard let type = GMProtocol.FrameType(rawValue: t) else {
            return bad(String(format: "unknown frame type 0x%02X", t))
        }
        let p = Array(bytes[2...])
        let n = p.count
        let payload: Payload
        switch type {
        case .set:
            guard n > 0, n % 3 == 0 else { return bad("SET: payload must be N*3 bytes") }
            payload = .set(stride(from: 0, to: n, by: 3).map {
                ChannelValue(channel: p[$0], value: p.int16(at: $0 + 1))
            })
        case .trigger:
            guard n >= 1, (n - 1) % 2 == 0 else { return bad("TRIGGER: bad length") }
            payload = .trigger(action: p[0], params: stride(from: 1, to: n, by: 2).map { p.int16(at: $0) })
        case .stopAll, .routineStop:
            guard n == 0 else { return bad("\(type.specName): unexpected payload") }
            payload = type == .stopAll ? .stopAll : .routineStop
        case .ping, .pong:
            guard n == 4 else { return bad("\(type.specName): expected 4 bytes") }
            payload = type == .ping ? .ping(t: p.uint32(at: 0)) : .pong(t: p.uint32(at: 0))
        case .routineBegin:
            guard n == 3 else { return bad("ROUTINE_BEGIN: expected 3 bytes") }
            payload = .routineBegin(slot: p[0], length: p.uint16(at: 1))
        case .routineChunk:
            guard n >= 3, n <= 2 + GMProtocol.maxChunk else { return bad("ROUTINE_CHUNK: bad length") }
            payload = .routineChunk(offset: p.uint16(at: 0), data: Array(p[2...]))
        case .routineEnd:
            guard n == 2 else { return bad("ROUTINE_END: expected 2 bytes") }
            payload = .routineEnd(crc: p.uint16(at: 0))
        case .routineRun:
            guard n == 1 else { return bad("ROUTINE_RUN: expected 1 byte") }
            payload = .routineRun(slot: p[0])
        case .ack:
            guard n == 2 else { return bad("ACK: expected 2 bytes") }
            payload = .ack(refSeq: p[0], status: p[1])
        case .telemetry:
            guard n >= 3, (n - 3) % 2 == 0 else { return bad("TELEMETRY: bad length") }
            payload = .telemetry(flags: p[0], step: p.uint16(at: 1),
                                 values: stride(from: 3, to: n, by: 2).map { p.int16(at: $0) })
        case .log:
            payload = .log(String(decoding: p, as: UTF8.self))
        case .routineState:
            guard n == 3 else { return bad("ROUTINE_STATE: expected 3 bytes") }
            payload = .routineState(state: p[0], step: p.uint16(at: 1))
        }
        return .success(Frame(seq: seq, payload))
    }
}

extension Array where Element == UInt8 {
    mutating func appendLE<T: FixedWidthInteger>(_ v: T) {
        Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) }
    }

    func uint16(at i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func int16(at i: Int) -> Int16 { Int16(bitPattern: uint16(at: i)) }
    func uint32(at i: Int) -> UInt32 {
        UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}

extension Array where Element == UInt8 {
    /// Lowercase hex, e.g. "0105025a00" (as in the test vectors).
    public var hexString: String { map { String(format: "%02x", $0) }.joined() }

    /// Bytes from a hex string; nil if it is malformed.
    public init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let b = UInt8(String(decoding: chars[i...i + 1], as: UTF8.self), radix: 16) else { return nil }
            out.append(b)
        }
        self = out
    }
}
