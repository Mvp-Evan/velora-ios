import Foundation

/// Calibrates UI countdowns against server `server_time` (Unix ms) from HTTP/WS handshake (DES-v1.3-00-01).
struct ServerTimeClock: Sendable {
    static let skewWarnThresholdMs: Int64 = 5_000

    private(set) var offsetMs: Int64 = 0

    var showsLargeSkewWarning: Bool {
        abs(offsetMs) > Self.skewWarnThresholdMs
    }

    mutating func applyHandshake(serverTimeMs: Int64, localNow: Date = Date()) {
        let localMs = Int64(localNow.timeIntervalSince1970 * 1000)
        offsetMs = serverTimeMs - localMs
    }

    func serverNowMs(localNow: Date = Date()) -> Int64 {
        Int64(localNow.timeIntervalSince1970 * 1000) + offsetMs
    }

    func remainingMs(until endAtMs: Int64, localNow: Date = Date()) -> Int64 {
        endAtMs - serverNowMs(localNow: localNow)
    }
}
