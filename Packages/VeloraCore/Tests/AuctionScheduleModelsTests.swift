import XCTest
@testable import VeloraCore

final class AuctionScheduleModelsTests: XCTestCase {
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let dt = withFrac.date(from: s) { return dt }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let dt = plain.date(from: s) { return dt }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    // MARK: MaybeExtend (AUC-04)

    func testMaybeExtendAddsWindowToOriginalEndAt() {
        let end = Date(timeIntervalSince1970: 1_000_000)
        var lot = AntiSnipeLogic.LotState(endAt: end, endAtVersion: 1, extensionCount: 0)
        // 10s remaining → new remaining 130s (end+120), not now+120.
        let now = end.addingTimeInterval(-10)
        XCTAssertTrue(AntiSnipeLogic.maybeExtend(&lot, now: now))
        XCTAssertEqual(lot.endAt.timeIntervalSince1970, end.timeIntervalSince1970 + 120, accuracy: 0.01)
        XCTAssertEqual(lot.extensionCount, 1)
        XCTAssertEqual(lot.endAtVersion, 2)
    }

    func testMaybeExtendSkipsOutsideWindow() {
        let end = Date(timeIntervalSince1970: 1_000_000)
        var lot = AntiSnipeLogic.LotState(endAt: end, endAtVersion: 1)
        let now = end.addingTimeInterval(-121)
        XCTAssertFalse(AntiSnipeLogic.maybeExtend(&lot, now: now))
        XCTAssertEqual(lot.endAt, end)
        XCTAssertEqual(lot.endAtVersion, 1)
        XCTAssertEqual(lot.extensionCount, 0)
    }

    func testMaybeExtendRespectsMaxExtensions() {
        let end = Date(timeIntervalSince1970: 1_000_000)
        var lot = AntiSnipeLogic.LotState(endAt: end, endAtVersion: 2, extensionCount: 1)
        let now = end.addingTimeInterval(-30)
        XCTAssertFalse(AntiSnipeLogic.maybeExtend(&lot, now: now, maxExtensions: 1))
        XCTAssertEqual(lot.endAt, end)
        XCTAssertEqual(lot.endAtVersion, 2)
        XCTAssertEqual(lot.extensionCount, 1)
    }

    func testContinuousExtendBumpsVersion() {
        var lot = AntiSnipeLogic.LotState(
            endAt: Date(timeIntervalSince1970: 1_000_000),
            endAtVersion: 1,
            extensionCount: 0
        )
        for i in 1...3 {
            let now = lot.endAt.addingTimeInterval(-15)
            XCTAssertTrue(AntiSnipeLogic.maybeExtend(&lot, now: now))
            XCTAssertEqual(lot.extensionCount, i)
            XCTAssertEqual(lot.endAtVersion, i + 1)
        }
    }

    func testClosingRemindRunAt() {
        let end = Date(timeIntervalSince1970: 1_000_000)
        let run = AntiSnipeLogic.closingRemindRunAt(endAt: end)
        XCTAssertEqual(run.timeIntervalSince1970, end.timeIntervalSince1970 - 300, accuracy: 0.01)
    }

    // MARK: Session schedule (AUC-05)

    func testPlannedEndAtFormula() {
        let first = Date(timeIntervalSince1970: 1_700_000_000) // arbitrary
        // Given first=… interval=90 i=3 Then end = first + 180s
        let third = AuctionSessionSchedule.plannedEndAt(firstEndAt: first, slotIndex: 3, intervalSeconds: 90)
        XCTAssertEqual(third.timeIntervalSince(first), 180, accuracy: 0.01)
        let firstSlot = AuctionSessionSchedule.plannedEndAt(firstEndAt: first, slotIndex: 1, intervalSeconds: 90)
        XCTAssertEqual(firstSlot, first)
    }

    func testIntervalValidation() {
        XCTAssertFalse(AuctionSessionSchedule.validateInterval(59))
        XCTAssertTrue(AuctionSessionSchedule.validateInterval(60))
        XCTAssertTrue(AuctionSessionSchedule.validateInterval(120))
        XCTAssertFalse(AuctionSessionSchedule.validateInterval(121))
    }

    func testDailyCapRejects31st() {
        XCTAssertTrue(AuctionSessionSchedule.wouldExceedDailyCap(existingCount: 30, adding: 1))
        XCTAssertFalse(AuctionSessionSchedule.wouldExceedDailyCap(existingCount: 29, adding: 1))
    }

    func testCloseWeekdayThuToSun() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        // 2026-11-05 is Thursday
        let thu = cal.date(from: DateComponents(year: 2026, month: 11, day: 5))!
        let tue = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let sun = cal.date(from: DateComponents(year: 2026, month: 11, day: 8))!
        XCTAssertTrue(AuctionSessionSchedule.isValidCloseWeekday(thu, calendar: cal))
        XCTAssertTrue(AuctionSessionSchedule.isValidCloseWeekday(sun, calendar: cal))
        XCTAssertFalse(AuctionSessionSchedule.isValidCloseWeekday(tue, calendar: cal))
    }

    // MARK: Decode

    func testCalendarResponseDecode() throws {
        let json = """
        {
          "items": [
            {
              "id": 7,
              "name": "周四集中结拍",
              "preview_start_at": "2026-11-02T16:00:00Z",
              "close_date": "2026-11-05T00:00:00Z",
              "first_end_at": "2026-11-05T12:00:00Z",
              "interval_seconds": 90,
              "daily_cap": 30,
              "status": "published",
              "lot_count": 12,
              "subscribed": false
            }
          ],
          "week_start": "2026-11-02T16:00:00Z",
          "week_end": "2026-11-09T15:59:59Z",
          "server_time": "2026-11-05T04:00:00Z"
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(AuctionSessionCalendarResponse.self, from: json)
        XCTAssertEqual(resp.items.count, 1)
        XCTAssertEqual(resp.items[0].id, 7)
        XCTAssertEqual(resp.items[0].intervalSeconds, 90)
        XCTAssertEqual(resp.items[0].status, .published)
        XCTAssertEqual(resp.displaySessions.count, 1)
        XCTAssertEqual(resp.items[0].staggerHint, "错峰结束 · 间隔 90 秒")
        XCTAssertEqual(resp.items[0].statusChip, "预展中")
    }

    func testDraftHiddenFromCalendar() throws {
        let json = """
        {"items":[
          {"id":1,"name":"A","status":"draft"},
          {"id":2,"name":"B","status":"live"}
        ]}
        """.data(using: .utf8)!
        let resp = try decoder.decode(AuctionSessionCalendarResponse.self, from: json)
        XCTAssertEqual(resp.displaySessions.map(\.id), [2])
        XCTAssertEqual(resp.displaySessions[0].statusChip, "今晚结拍")
    }

    func testSessionDetailLotsBySlot() throws {
        let json = """
        {
          "session": {"id": 3, "name": "专场", "status": "live", "interval_seconds": 90},
          "lots": [
            {"lot_id": 20, "slot_index": 2, "planned_end_at": "2026-11-05T12:01:30Z", "title": "B"},
            {"lot_id": 10, "slot_index": 1, "planned_end_at": "2026-11-05T12:00:00Z", "title": "A"}
          ]
        }
        """.data(using: .utf8)!
        let detail = try decoder.decode(AuctionSessionDetailResponse.self, from: json)
        XCTAssertEqual(detail.lotsBySlot.map(\.lotId), [10, 20])
        XCTAssertEqual(detail.lotsBySlot[0].slotIndex, 1)
    }

    func testLotRemindResponseIdempotent() throws {
        let json = #"{"subscribed":true,"lot_id":42}"#.data(using: .utf8)!
        let r = try decoder.decode(LotRemindResponse.self, from: json)
        XCTAssertTrue(r.isSubscribed)
        XCTAssertEqual(r.lotId, 42)
        let empty = try decoder.decode(LotRemindResponse.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.isSubscribed)
    }

    func testAuctionExtendedPayload() throws {
        let json = """
        {
          "lot_id": 9,
          "end_at": "2026-11-05T12:02:00Z",
          "extension_count": 2,
          "end_at_version": 3
        }
        """.data(using: .utf8)!
        let p = try decoder.decode(AuctionExtendedPayload.self, from: json)
        XCTAssertEqual(p.extensionCount, 2)
        XCTAssertEqual(p.endAtVersion, 3)
    }

    func testErrorCodesAndCopy() {
        XCTAssertEqual(AuctionScheduleErrorCode.sessionFull.rawValue, "session_full")
        XCTAssertEqual(AntiSnipeCopy.extendToastTitle, "已延时 2 分钟")
        XCTAssertEqual(AntiSnipeCopy.closingRemindSuccess, "已订阅结拍提醒，结束前 5 分钟通知您")
        XCTAssertEqual(AntiSnipeCopy.sessionEmpty, "本场排期中")
        XCTAssertTrue(AntiSnipeCopy.remainingMinutesAccessibility(remain: 90).contains("2"))
        XCTAssertEqual(AntiSnipeConfig.windowSeconds, 120)
        XCTAssertEqual(AntiSnipeConfig.remindBeforeSeconds, 300)
    }
}
