import XCTest
@testable import VeloraCore

final class SpotReleaseModelsTests: XCTestCase {
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if let s = try? c.decode(String.self) {
                let withFrac = ISO8601DateFormatter()
                withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let dt = withFrac.date(from: s) { return dt }
                let plain = ISO8601DateFormatter()
                plain.formatOptions = [.withInternetDateTime]
                if let dt = plain.date(from: s) { return dt }
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
            }
            if let ms = try? c.decode(Int64.self) {
                return Date(timeIntervalSince1970: Double(ms) / 1000)
            }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date"))
        }
        return d
    }()

    private let t0 = ISO8601DateFormatter().date(from: "2026-11-05T04:00:00Z")!

    // MARK: Defaults / copy

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(SpotReleaseConfigDefaults.payWindowSec, 900)
        XCTAssertEqual(SpotReleaseConfigDefaults.holdGraceSec, 60)
        XCTAssertEqual(SpotReleaseConfigDefaults.limitPerUserMax, 5)
        XCTAssertEqual(SpotReleaseConfigDefaults.exclusiveDepositDefaultFen, 20_000)
        XCTAssertEqual(SpotReleaseConfigDefaults.clockSkewWarnMs, 2_000)
        XCTAssertEqual(SpotReleaseConfigDefaults.pollBeforeSaleSec, 30)
        XCTAssertEqual(SpotReleaseConfigDefaults.pollNearSaleSec, 1)
        XCTAssertEqual(SpotReleaseConfigDefaults.pollLiveSec, 3)
        XCTAssertEqual(SpotReleaseConfigDefaults.orderType, "spot_release")
        XCTAssertEqual(SpotReleaseConfigDefaults.shipHoursAfterPay, 48)
    }

    func testServerTimeHintCopy() {
        XCTAssertEqual(SpotReleaseCopy.serverTimeHint, "以服务器时间为准")
        XCTAssertEqual(SpotReleaseCopy.rush, "立即抢购")
        XCTAssertEqual(SpotReleaseCopy.soldOutHint, "已售罄，订阅补货")
        XCTAssertEqual(SpotReleaseCopy.completeEligibility, "去完成资格")
        XCTAssertEqual(SpotReleaseCopy.vipWindowClosed, "当前会员等级窗口未开放")
    }

    // MARK: Decoding detail / eligibility / next window

    func testDecodeReleaseDetailWithEligibilityAndSaleOpen() throws {
        let json = """
        {
          "id": 42,
          "listing_id": 100,
          "title": "GT3 RS 现货",
          "mode": "spot",
          "status": "scheduled",
          "start_at": "2026-11-05T05:00:00Z",
          "limit_per_user": 1,
          "exclusive": true,
          "exclusive_quota": 50,
          "exclusive_deposit_fen": 20000,
          "sale_open": false,
          "remaining": 50,
          "server_now": "2026-11-05T04:00:00Z",
          "user_eligibility": {
            "real_named": true,
            "deposit_frozen": false,
            "quota_left": 50,
            "vip_level": 1,
            "reserved": true
          },
          "next_window": {
            "open_at": "2026-11-05T05:15:00Z",
            "min_level": 1,
            "level_name": "银"
          },
          "skus": [
            {
              "id": 7,
              "sku_code": "BLK",
              "color": "黑",
              "stock_total": 50,
              "stock_reserved": 0,
              "stock_sold": 0,
              "remaining": 50,
              "price_fen": 259900
            }
          ],
          "vip_windows": [
            { "min_level": 3, "open_at": "2026-11-05T05:00:00Z", "level_name": "钻" },
            { "min_level": 2, "open_at": "2026-11-05T05:05:00Z", "level_name": "金" },
            { "min_level": 1, "open_at": "2026-11-05T05:15:00Z", "level_name": "银" },
            { "min_level": 0, "open_at": "2026-11-05T05:30:00Z" }
          ]
        }
        """.data(using: .utf8)!

        let detail = try decoder.decode(SpotReleaseDetail.self, from: json)
        XCTAssertEqual(detail.id, 42)
        XCTAssertEqual(detail.listingId, 100)
        XCTAssertEqual(detail.mode, .spot)
        XCTAssertEqual(detail.status, .scheduled)
        XCTAssertEqual(detail.saleOpen, false)
        XCTAssertEqual(detail.remaining, 50)
        XCTAssertTrue(detail.isExclusive)
        XCTAssertEqual(detail.eligibility?.isRealNamed, true)
        XCTAssertEqual(detail.eligibility?.isDepositFrozen, false)
        XCTAssertEqual(detail.eligibility?.quotaLeft, 50)
        XCTAssertEqual(detail.eligibility?.resolvedVipLevel, 1)
        XCTAssertTrue(detail.isViewerReserved)
        XCTAssertEqual(detail.nextWindow?.minLevel, 1)
        XCTAssertEqual(detail.skus.count, 1)
        XCTAssertEqual(detail.skus[0].priceFen, 259_900)
        XCTAssertEqual(detail.vipWindows.count, 4)
        XCTAssertNotNil(detail.resolvedServerNow)
        XCTAssertEqual(detail.resolvedDepositFen, 20_000)
    }

    func testDecodeServerTimeMsFallback() throws {
        let json = """
        {
          "id": 1,
          "sale_open": true,
          "server_time": 1730779200000,
          "skus": []
        }
        """.data(using: .utf8)!
        let detail = try decoder.decode(SpotReleaseDetail.self, from: json)
        XCTAssertEqual(detail.resolvedServerNowMs, 1_730_779_200_000)
        XCTAssertEqual(detail.saleOpen, true)
    }

    func testDecodeHoldAndOrderResult() throws {
        let orderJSON = """
        {
          "order_id": 9001,
          "hold_id": 55,
          "pay_deadline": "2026-11-05T05:15:00Z",
          "remaining": 49
        }
        """.data(using: .utf8)!
        let order = try decoder.decode(SpotReleaseOrderResult.self, from: orderJSON)
        XCTAssertEqual(order.orderId, 9001)
        XCTAssertEqual(order.holdId, 55)
        XCTAssertEqual(order.remaining, 49)

        let reserveJSON = """
        { "release_id": 42, "reserved": true, "already_reserved": false }
        """.data(using: .utf8)!
        let reserve = try decoder.decode(SpotReleaseReserveResult.self, from: reserveJSON)
        XCTAssertTrue(reserve.isReserved)

        let depJSON = """
        { "deposit_id": 3, "amount_fen": 20000, "status": "frozen", "channel": "preauth" }
        """.data(using: .utf8)!
        let dep = try decoder.decode(SpotReleaseExclusiveDepositResult.self, from: depJSON)
        XCTAssertTrue(dep.isFrozen)
        XCTAssertEqual(dep.amountFen, 20_000)
    }

    // MARK: Countdown / sale_open / poll

    func testCountdownUsesServerNowNotWallClock() {
        let start = t0.addingTimeInterval(120)
        let serverNow = t0
        XCTAssertEqual(SpotReleaseLogic.countdownSeconds(until: start, serverNow: serverNow), 120)
        // Device wall clock in the future must not affect the helper — only serverNow matters.
        XCTAssertEqual(
            SpotReleaseLogic.countdownSeconds(until: start, serverNow: serverNow.addingTimeInterval(60)),
            60
        )
    }

    func testSaleOpenPrefersServerFlagOverLocalZero() {
        let start = t0
        var detail = SpotReleaseDetail(
            id: 1,
            status: .scheduled,
            startAt: start,
            saleOpen: false,
            serverNow: start.addingTimeInterval(1)
        )
        // Local time past start_at but open flag not written → not open (design §5.9).
        XCTAssertFalse(SpotReleaseLogic.isSaleOpen(detail, serverNow: start.addingTimeInterval(1)))

        detail = SpotReleaseDetail(id: 1, status: .live, startAt: start, saleOpen: true)
        XCTAssertTrue(SpotReleaseLogic.isSaleOpen(detail, serverNow: start.addingTimeInterval(1)))
    }

    func testPollIntervalCadence() {
        XCTAssertEqual(SpotReleaseLogic.pollIntervalSeconds(remainingToStart: 120, saleOpen: false), 30)
        XCTAssertEqual(SpotReleaseLogic.pollIntervalSeconds(remainingToStart: 8, saleOpen: false), 1)
        XCTAssertEqual(SpotReleaseLogic.pollIntervalSeconds(remainingToStart: 0, saleOpen: false), 1)
        XCTAssertEqual(SpotReleaseLogic.pollIntervalSeconds(remainingToStart: nil, saleOpen: true), 3)
    }

    func testClockSkewHint() {
        XCTAssertFalse(SpotReleaseLogic.shouldShowServerTimeSkewHint(clientSkewMs: 500))
        XCTAssertTrue(SpotReleaseLogic.shouldShowServerTimeSkewHint(clientSkewMs: 2_001))
        XCTAssertTrue(SpotReleaseLogic.shouldShowServerTimeSkewHint(clientSkewMs: -3_000))
    }

    // MARK: VIP next window

    func testNextVIPWindowForLowLevel() {
        let windows = [
            SpotReleaseVIPWindow(minLevel: 3, openAt: t0),
            SpotReleaseVIPWindow(minLevel: 2, openAt: t0.addingTimeInterval(300)),
            SpotReleaseVIPWindow(minLevel: 1, openAt: t0.addingTimeInterval(900)),
            SpotReleaseVIPWindow(minLevel: 0, openAt: t0.addingTimeInterval(1800)),
        ]
        // VIP1 before their window.
        let next = SpotReleaseLogic.nextWindow(forLevel: 1, windows: windows, serverNow: t0.addingTimeInterval(60))
        XCTAssertEqual(next?.minLevel, 1)
        XCTAssertEqual(next?.openAt, t0.addingTimeInterval(900))

        // After VIP1 opens — nil.
        XCTAssertNil(SpotReleaseLogic.nextWindow(forLevel: 1, windows: windows, serverNow: t0.addingTimeInterval(901)))

        // VIP3 at T — nil (open).
        XCTAssertNil(SpotReleaseLogic.nextWindow(forLevel: 3, windows: windows, serverNow: t0))
    }

    func testVIPWindowsMonotonicValidation() {
        let ok = [
            SpotReleaseVIPWindow(minLevel: 3, openAt: t0),
            SpotReleaseVIPWindow(minLevel: 0, openAt: t0.addingTimeInterval(1800)),
        ]
        XCTAssertNil(SpotReleaseLogic.validateVIPWindows(ok))

        let missingPublic = [SpotReleaseVIPWindow(minLevel: 2, openAt: t0)]
        XCTAssertEqual(SpotReleaseLogic.validateVIPWindows(missingPublic), .vipWindowIncomplete)

        let inverted = [
            SpotReleaseVIPWindow(minLevel: 3, openAt: t0.addingTimeInterval(600)),
            SpotReleaseVIPWindow(minLevel: 0, openAt: t0),
        ]
        XCTAssertEqual(SpotReleaseLogic.validateVIPWindows(inverted), .vipWindowInvalid)
    }

    // MARK: Exclusive checklist

    func testExclusiveChecklistSteps() {
        let items = SpotReleaseLogic.exclusiveChecklist(
            isLoggedIn: true,
            eligibility: SpotReleaseEligibility(realNamed: true, depositFrozen: false),
            exclusive: true
        )
        XCTAssertEqual(items.map(\.step), [.login, .realName, .deposit])
        XCTAssertEqual(items.map(\.done), [true, true, false])
        XCTAssertEqual(
            SpotReleaseLogic.nextExclusiveStep(
                isLoggedIn: true,
                eligibility: SpotReleaseEligibility(realNamed: true, depositFrozen: false),
                exclusive: true
            ),
            .deposit
        )
        XCTAssertTrue(
            SpotReleaseLogic.exclusiveReady(
                isLoggedIn: true,
                eligibility: SpotReleaseEligibility(realNamed: true, depositFrozen: true),
                exclusive: true
            )
        )
        XCTAssertTrue(
            SpotReleaseLogic.exclusiveChecklist(
                isLoggedIn: false,
                eligibility: nil,
                exclusive: false
            ).isEmpty
        )
    }

    // MARK: CTA / error codes

    func testCTAReserveThenRushRequiresSaleOpen() {
        let start = t0.addingTimeInterval(600)
        let before = SpotReleaseDetail(
            id: 1,
            status: .scheduled,
            startAt: start,
            remaining: 10,
            saleOpen: false,
            reserved: false
        )
        XCTAssertEqual(
            SpotReleaseLogic.resolveCTA(detail: before, serverNow: t0, isLoggedIn: true),
            .reserve
        )

        let reserved = SpotReleaseDetail(
            id: 1,
            status: .scheduled,
            startAt: start,
            remaining: 10,
            saleOpen: false,
            reserved: true
        )
        XCTAssertEqual(
            SpotReleaseLogic.resolveCTA(detail: reserved, serverNow: t0, isLoggedIn: true),
            .reservedWaiting
        )

        // Local past start but sale_open still false → wait, not rush.
        let waitingOpen = SpotReleaseDetail(
            id: 1,
            status: .scheduled,
            startAt: t0,
            remaining: 10,
            saleOpen: false
        )
        XCTAssertEqual(
            SpotReleaseLogic.resolveCTA(detail: waitingOpen, serverNow: t0.addingTimeInterval(2), isLoggedIn: true),
            .waitSaleOpen
        )

        let live = SpotReleaseDetail(
            id: 1,
            status: .live,
            startAt: t0,
            eligibility: SpotReleaseEligibility(realNamed: true, vipLevel: 0),
            remaining: 10,
            saleOpen: true
        )
        XCTAssertEqual(
            SpotReleaseLogic.resolveCTA(detail: live, serverNow: t0.addingTimeInterval(1), isLoggedIn: true),
            .rush
        )
    }

    func testCTAExclusiveAndVIPWindowAndSoldOut() {
        let exclusive = SpotReleaseDetail(
            id: 1,
            status: .live,
            startAt: t0,
            exclusive: true,
            eligibility: SpotReleaseEligibility(realNamed: true, depositFrozen: false, vipLevel: 2),
            remaining: 5,
            saleOpen: true
        )
        XCTAssertEqual(
            SpotReleaseLogic.resolveCTA(detail: exclusive, serverNow: t0.addingTimeInterval(1), isLoggedIn: true),
            .completeEligibility
        )

        let vipClosed = SpotReleaseDetail(
            id: 1,
            status: .live,
            startAt: t0,
            vipWindows: [
                SpotReleaseVIPWindow(minLevel: 1, openAt: t0.addingTimeInterval(900)),
                SpotReleaseVIPWindow(minLevel: 0, openAt: t0.addingTimeInterval(1800)),
            ],
            eligibility: SpotReleaseEligibility(realNamed: true, vipLevel: 1),
            nextWindow: SpotReleaseNextWindow(openAt: t0.addingTimeInterval(900), minLevel: 1),
            remaining: 5,
            saleOpen: true
        )
        XCTAssertEqual(
            SpotReleaseLogic.resolveCTA(detail: vipClosed, serverNow: t0.addingTimeInterval(1), isLoggedIn: true),
            .waitVIPWindow
        )

        let sold = SpotReleaseDetail(id: 1, status: .soldOut, remaining: 0, saleOpen: true)
        XCTAssertEqual(
            SpotReleaseLogic.resolveCTA(detail: sold, serverNow: t0, isLoggedIn: true),
            .soldOut
        )
    }

    func testHoldOrderErrorCodes() {
        XCTAssertEqual(SpotReleaseErrorCode.saleNotStarted.rawValue, "sale_not_started")
        XCTAssertEqual(SpotReleaseErrorCode.vipWindowClosed.rawValue, "vip_window_closed")
        XCTAssertEqual(SpotReleaseErrorCode.exclusiveEligibilityRequired.rawValue, "exclusive_eligibility_required")
        XCTAssertEqual(SpotReleaseErrorCode.soldOut.rawValue, "sold_out")
        XCTAssertEqual(SpotReleaseErrorCode.purchaseLimitExceeded.rawValue, "purchase_limit_exceeded")
        XCTAssertEqual(SpotReleaseErrorCode.holdExpired.rawValue, "hold_expired")
        XCTAssertTrue(SpotReleaseErrorCode.authRequired.opensLogin)
        XCTAssertTrue(SpotReleaseErrorCode.exclusiveEligibilityRequired.opensRealName)
        XCTAssertTrue(SpotReleaseErrorCode.depositNotFrozen.opensExclusiveDeposit)
        XCTAssertEqual(SpotReleaseErrorCode.vipWindowClosed.fallbackMessage, SpotReleaseCopy.vipWindowClosed)
    }

    func testValidateQtyAndStartAt() {
        XCTAssertEqual(SpotReleaseLogic.validateQty(0, limitPerUser: 1), .invalidQty)
        XCTAssertEqual(SpotReleaseLogic.validateQty(2, limitPerUser: 1), .invalidQty)
        XCTAssertNil(SpotReleaseLogic.validateQty(1, limitPerUser: 1))
        XCTAssertEqual(
            SpotReleaseLogic.validateStartAt(t0.addingTimeInterval(60), serverNow: t0),
            .invalidStartAt
        )
        XCTAssertNil(
            SpotReleaseLogic.validateStartAt(t0.addingTimeInterval(6 * 60), serverNow: t0)
        )
    }

    func testSKURemainingAndCountdownLine() {
        let sku = SpotReleaseSKU(id: 1, stockTotal: 10, stockReserved: 2, stockSold: 3)
        XCTAssertEqual(sku.resolvedRemaining, 5)
        let line = SpotReleaseLogic.countdownLine(seconds: 65)
        XCTAssertTrue(line.contains(SpotReleaseCopy.serverTimeHint))
        XCTAssertTrue(line.contains("00:01:05"))
    }
}
