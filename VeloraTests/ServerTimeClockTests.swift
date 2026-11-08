import XCTest
@testable import Velora

final class ServerTimeClockTests: XCTestCase {
    func testApplyHandshakeSetsOffset() {
        let local = Date(timeIntervalSince1970: 1_000)
        var clock = ServerTimeClock()
        clock.applyHandshake(serverTimeMs: 5_000, localNow: local)
        XCTAssertEqual(clock.offsetMs, 4_000)
        XCTAssertEqual(clock.serverNowMs(localNow: local), 5_000)
    }

    func testRemainingMsUsesOffset() {
        var clock = ServerTimeClock()
        let local = Date(timeIntervalSince1970: 10)
        clock.applyHandshake(serverTimeMs: 1_010, localNow: local)
        XCTAssertEqual(clock.remainingMs(until: 1_100, localNow: local), 90)
    }

    func testLargeSkewWarning() {
        var clock = ServerTimeClock()
        clock.applyHandshake(serverTimeMs: 6_000, localNow: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(clock.showsLargeSkewWarning)
    }
}
