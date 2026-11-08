import Foundation

public struct ServerTimeClock: Sendable {
    /// DES-v1.3-14-01 §5.4 — prompt re-sync when |offset| > 5s.
    public static let skewWarnThresholdMs: Int64 = 5_000

    public private(set) var offsetMs: Int64 = 0

    public init() {}

    public var showsLargeSkewWarning: Bool {
        abs(offsetMs) > Self.skewWarnThresholdMs
    }

    public mutating func applyHandshake(serverTimeMs: Int64, localNow: Date = Date()) {
        let localMs = Int64(localNow.timeIntervalSince1970 * 1000)
        offsetMs = serverTimeMs - localMs
    }

    public func serverNowMs(localNow: Date = Date()) -> Int64 {
        Int64(localNow.timeIntervalSince1970 * 1000) + offsetMs
    }
}
