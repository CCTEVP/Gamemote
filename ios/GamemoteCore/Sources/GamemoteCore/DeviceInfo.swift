import Foundation

/// The device's self-description, read from the INFO characteristic (JSON, PROTOCOL.md section 3).
public struct DeviceInfo: Codable, Equatable, Sendable {
    public struct Channel: Codable, Equatable, Sendable, Identifiable {
        public var id: Int
        public var name: String
        /// "speed", "angle" or "level".
        public var kind: String
        public var min: Int
        public var max: Int
        public var neutral: Int
    }

    public struct Param: Codable, Equatable, Sendable {
        public var name: String
        public var min: Int
        public var max: Int
        public var `default`: Int
    }

    public struct Action: Codable, Equatable, Sendable, Identifiable {
        public var id: Int
        public var name: String
        public var params: [Param]
    }

    public struct Telemetry: Codable, Equatable, Sendable {
        public var name: String
        public var min: Int
        public var max: Int
    }

    public struct Routines: Codable, Equatable, Sendable {
        public var transfer: Bool
        public var maxBytes: Int
        public var maxLoopDepth: Int

        enum CodingKeys: String, CodingKey {
            case transfer
            case maxBytes = "max_bytes"
            case maxLoopDepth = "max_loop_depth"
        }
    }

    public var proto: Int
    public var name: String
    public var fw: String
    public var channels: [Channel]
    public var actions: [Action]
    public var telemetry: [Telemetry]
    public var routines: Routines?

    /// Parses the INFO JSON bytes.
    public static func parse(_ bytes: [UInt8]) throws -> DeviceInfo {
        try JSONDecoder().decode(DeviceInfo.self, from: Data(bytes))
    }

    public func jsonBytes() -> [UInt8] {
        (try? Array(JSONEncoder().encode(self))) ?? []
    }

    public func channel(_ id: Int) -> Channel? { channels.first { $0.id == id } }

    /// First channel of a kind ("speed", "angle", "level"), as the gamepad binds them.
    public func firstChannel(kind: String) -> Channel? { channels.first { $0.kind == kind } }

    public var supportsTransfer: Bool { routines?.transfer ?? false }
}
