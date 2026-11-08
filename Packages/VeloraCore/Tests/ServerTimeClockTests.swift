import XCTest
@testable import VeloraCore

final class ServerTimeClockTests: XCTestCase {
    func testOffset() {
        let local = Date(timeIntervalSince1970: 100)
        var clock = ServerTimeClock()
        clock.applyHandshake(serverTimeMs: 500, localNow: local)
        XCTAssertEqual(clock.serverNowMs(localNow: local), 500)
    }

    func testLargeSkewWarningThreshold() {
        var clock = ServerTimeClock()
        clock.applyHandshake(serverTimeMs: 6_000, localNow: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(clock.showsLargeSkewWarning)
        clock.applyHandshake(serverTimeMs: 500, localNow: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(clock.showsLargeSkewWarning)
    }
}
