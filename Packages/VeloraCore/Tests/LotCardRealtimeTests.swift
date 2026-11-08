import XCTest
@testable import VeloraCore

final class LotCardRealtimeTests: XCTestCase {

    func testPolicyConstants() {
        XCTAssertEqual(LotCardSubscribePolicy.minVisibleRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(LotCardSubscribePolicy.unsubscribeRatio, 0.1, accuracy: 0.001)
        XCTAssertEqual(LotCardSubscribePolicy.minVisibleMs, 300)
        XCTAssertEqual(LotCardSubscribePolicy.maxSubscriptions, 30)
        XCTAssertEqual(LotCardSubscribePolicy.debounceMs, 200)
        XCTAssertEqual(LotCardSubscribePolicy.heartbeatSeconds, 15)
        XCTAssertEqual(LotCardSubscribePolicy.subscribeEvent, "subscribe_card")
        XCTAssertEqual(LotCardSubscribePolicy.tickEvent, "lot_card_tick")
    }

    func testVisibilityRequires300msAtHalf() {
        var engine = LotCardVisibilityEngine()
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.updateRatio(lotId: 1, ratio: 0.6, now: t0)
        var desired = engine.desiredSubscriptions(now: t0.addingTimeInterval(0.2))
        XCTAssertTrue(desired.isEmpty)

        desired = engine.desiredSubscriptions(now: t0.addingTimeInterval(0.301))
        XCTAssertEqual(desired, [1])

        let diff = engine.applyDesired(desired)
        XCTAssertEqual(diff.subscribe, [1])
        XCTAssertEqual(engine.states[1], .subscribed)
    }

    func testBelowTenPercentUnsubscribes() {
        var engine = LotCardVisibilityEngine()
        let t0 = Date(timeIntervalSince1970: 1_000)
        engine.updateRatio(lotId: 7, ratio: 0.8, now: t0)
        _ = engine.applyDesired(engine.desiredSubscriptions(now: t0.addingTimeInterval(0.4)))
        XCTAssertTrue(engine.subscribed.contains(7))

        engine.updateRatio(lotId: 7, ratio: 0.05, now: t0.addingTimeInterval(1))
        let desired = engine.desiredSubscriptions(now: t0.addingTimeInterval(1))
        let diff = engine.applyDesired(desired)
        XCTAssertEqual(diff.unsubscribe, [7])
        XCTAssertFalse(engine.subscribed.contains(7))
    }

    func testFlingBlocksSubscribe() {
        var engine = LotCardVisibilityEngine()
        engine.setFlinging(true)
        let t0 = Date(timeIntervalSince1970: 2_000)
        engine.updateRatio(lotId: 3, ratio: 0.9, now: t0)
        XCTAssertTrue(engine.desiredSubscriptions(now: t0.addingTimeInterval(1)).isEmpty)
        engine.setFlinging(false)
        engine.updateRatio(lotId: 3, ratio: 0.9, now: t0.addingTimeInterval(1.1))
        let desired = engine.desiredSubscriptions(now: t0.addingTimeInterval(1.5))
        XCTAssertEqual(desired, [3])
    }

    func testMaxThirtyCapKeepsPreferredOrder() {
        var engine = LotCardVisibilityEngine()
        let t0 = Date(timeIntervalSince1970: 3_000)
        let ids = Array(Int64(1)...Int64(35))
        for id in ids {
            engine.updateRatio(lotId: id, ratio: 0.7, now: t0)
        }
        let desired = engine.desiredSubscriptions(now: t0.addingTimeInterval(0.5), preferredOrder: ids)
        XCTAssertEqual(desired.count, 30)
        XCTAssertFalse(desired.contains(35))
        XCTAssertTrue(desired.contains(1))
        XCTAssertTrue(desired.contains(30))
    }

    func testEndTimeChangeBannerUsesVersionNotTickCount() {
        var tracker = EndTimeChangeTracker()
        tracker.seed(lotId: 10, version: 1)
        XCTAssertFalse(tracker.noteVersionChange(lotId: 10, newVersion: 1))
        XCTAssertFalse(tracker.showsBanner)

        XCTAssertTrue(tracker.noteVersionChange(lotId: 10, newVersion: 2))
        // First sighting of 11 must not count toward the banner.
        XCTAssertFalse(tracker.noteVersionChange(lotId: 11, newVersion: 3))
        XCTAssertEqual(tracker.count, 1)
        XCTAssertTrue(tracker.noteVersionChange(lotId: 11, newVersion: 4))
        XCTAssertEqual(tracker.count, 2)
        XCTAssertEqual(tracker.bannerText, "2 件拍品结束时间已变化，点击刷新")

        // Same version again — no double count.
        XCTAssertFalse(tracker.noteVersionChange(lotId: 10, newVersion: 2))
        XCTAssertEqual(tracker.count, 2)

        tracker.clear()
        XCTAssertFalse(tracker.showsBanner)
        // Versions retained so a later same bump doesn't re-add incorrectly after clear? Design: clear set on refresh; versions can stay.
        XCTAssertTrue(tracker.changedEndIds.isEmpty)
    }

    func testBannerCapsAt99Plus() {
        var tracker = EndTimeChangeTracker()
        for i in Int64(1)...Int64(120) {
            tracker.seed(lotId: i, version: 1)
            _ = tracker.noteVersionChange(lotId: i, newVersion: 2)
        }
        XCTAssertEqual(tracker.count, 120)
        XCTAssertTrue(tracker.bannerText.hasPrefix("99+"))
    }

    func testLiveFieldsApplySeqAndDelayed() {
        var live = LotCardLiveFields(endAtVersion: 1, extensionCount: 0)
        let older = LotCardTick(lotId: 1, currentPrice: 100, endAtVersion: 1, seq: 5)
        XCTAssertFalse(live.apply(older))
        XCTAssertEqual(live.currentPrice, 100)
        XCTAssertEqual(live.lastSeq, 5)

        let staleSeq = LotCardTick(lotId: 1, currentPrice: 50, endAtVersion: 1, seq: 3)
        XCTAssertFalse(live.apply(staleSeq))
        XCTAssertEqual(live.currentPrice, 100)

        let delayed = LotCardTick(
            lotId: 1,
            currentPrice: 120,
            endAtVersion: 2,
            extensionCount: 1,
            delayed: true,
            seq: 6
        )
        XCTAssertTrue(live.apply(delayed))
        XCTAssertTrue(live.delayed)
        XCTAssertEqual(live.endAtVersion, 2)
        XCTAssertEqual(live.currentPrice, 120)
    }

    func testOlderEndAtVersionDropped() {
        var live = LotCardLiveFields(currentPrice: 10, endAtVersion: 5)
        let old = LotCardTick(lotId: 1, currentPrice: 99, endAtVersion: 4, seq: 1)
        XCTAssertFalse(live.apply(old))
        XCTAssertEqual(live.currentPrice, 10)
    }

    func testHeatCopy() {
        XCTAssertEqual(LotCardHeatCopy.line(viewers: 0), "刚刚开始")
        XCTAssertEqual(LotCardHeatCopy.line(viewers: nil), "刚刚开始")
        XCTAssertEqual(
            LotCardHeatCopy.line(viewers: 123, favoriteCount: 8, bidderCount: 5),
            "123 人围观 · 8 收藏 · 5 人出价"
        )
        XCTAssertEqual(LotCardHeatCopy.delayedBadge, "已延时")
    }

    func testTickDecodableSnakeCase() throws {
        let json = """
        {
          "lot_id": 42,
          "current_price": 88000,
          "bid_count": 3,
          "end_at": "2026-11-05T12:00:00Z",
          "end_at_version": 2,
          "extension_count": 1,
          "delayed": true,
          "status": "live",
          "viewers": 12,
          "favorite_count": 4,
          "bidder_count": 2,
          "server_time": 1730000000000,
          "seq": 9
        }
        """.data(using: .utf8)!
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .iso8601
        let tick = try dec.decode(LotCardTick.self, from: json)
        XCTAssertEqual(tick.lotId, 42)
        XCTAssertEqual(tick.currentPrice, 88000)
        XCTAssertEqual(tick.endAtVersion, 2)
        XCTAssertEqual(tick.delayed, true)
        XCTAssertEqual(tick.viewers, 12)
        XCTAssertEqual(tick.favoriteCount, 4)
        XCTAssertEqual(tick.seq, 9)
    }

    func testTerminalStatus() {
        var live = LotCardLiveFields()
        _ = live.apply(LotCardTick(lotId: 1, status: "ended", seq: 1))
        XCTAssertTrue(live.isTerminalStatus)
    }

    func testSubscribeDiff() {
        let diff = LotCardSubscribeDiff.compute(visible: [1, 2, 3], subscribed: [2, 4])
        XCTAssertEqual(diff.subscribe, [1, 3])
        XCTAssertEqual(diff.unsubscribe, [4])
    }

    func testFilterChangeClearsBannerAndVersions() {
        var tracker = EndTimeChangeTracker()
        tracker.seed(lotId: 1, version: 1)
        _ = tracker.noteVersionChange(lotId: 1, newVersion: 2)
        tracker.clearForFilterChange()
        XCTAssertTrue(tracker.changedEndIds.isEmpty)
        XCTAssertTrue(tracker.knownVersions.isEmpty)
    }
}
