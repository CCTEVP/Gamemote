import Foundation
import Observation

/// The Live console's lines: plain words, newest last, capped. Repeated updates of the same
/// thing (stick position, telemetry) rewrite one line instead of flooding the log.
@Observable
public final class ConsoleLog {
    public enum Kind: String, Sendable {
        case status, command, feedback, error
    }

    public struct Line: Identifiable, Equatable, Sendable {
        public let id: Int
        public var text: String
        public var kind: Kind
        /// Merge key: "" for normal lines.
        public var key: String
    }

    public static let maxLines = 200
    public static let rttWindow = 40

    public private(set) var lines: [Line] = []
    public private(set) var latestRTT: Int?
    public private(set) var p95RTT: Int?

    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var rtts: [Int] = []

    public init() {}

    /// Appends a line.
    @discardableResult
    public func add(_ text: String, kind: Kind = .status) -> Line {
        append(text, kind: kind, key: "")
    }

    /// Rewrites the last line if it has the same key, otherwise appends a new one.
    @discardableResult
    public func update(key: String, _ text: String, kind: Kind = .command) -> Line {
        if var last = lines.last, last.key == key, !key.isEmpty {
            last.text = text
            last.kind = kind
            lines[lines.count - 1] = last
            return last
        }
        return append(text, kind: kind, key: key)
    }

    public func clear() { lines = [] }

    public func addRTT(_ ms: Int) {
        rtts.append(ms)
        if rtts.count > Self.rttWindow { rtts.removeFirst() }
        let sorted = rtts.sorted()
        latestRTT = ms
        p95RTT = sorted[Swift.min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    }

    public func clearRTT() {
        rtts = []
        latestRTT = nil
        p95RTT = nil
    }

    private func append(_ text: String, kind: Kind, key: String) -> Line {
        let line = Line(id: nextID, text: text, kind: kind, key: key)
        nextID += 1
        lines.append(line)
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
        return line
    }
}
