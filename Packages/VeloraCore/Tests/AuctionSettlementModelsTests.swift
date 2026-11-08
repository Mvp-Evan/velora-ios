import XCTest
@testable import VeloraCore

final class AuctionSettlementModelsTests: XCTestCase {
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

    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: Reserve / EndLot decision

    func testReserveMetNilMeansTrue() {
        XCTAssertTrue(AuctionSettlementLogic.reserveMet(currentPrice: 100, reservePrice: nil))
        XCTAssertTrue(AuctionSettlementLogic.reserveMet(currentPrice: 1000, reservePrice: 1000))
        XCTAssertFalse(AuctionSettlementLogic.reserveMet(currentPrice: 999, reservePrice: 1000))
    }

    func testShouldCreateOrderRequiresWinnerAndReserve() {
        XCTAssertTrue(AuctionSettlementLogic.shouldCreateOrder(hasWinner: true, reserveMet: true))
        XCTAssertFalse(AuctionSettlementLogic.shouldCreateOrder(hasWinner: true, reserveMet: false))
        XCTAssertFalse(AuctionSettlementLogic.shouldCreateOrder(hasWinner: false, reserveMet: true))
    }

    func testPublicUnsoldReasonNeverExposesGap() {
        XCTAssertEqual(
            AuctionSettlementLogic.publicUnsoldReason(reserveNotMet: true),
            AuctionSettlementCopy.unsoldReasonPublic
        )
        XCTAssertEqual(
            AuctionSettlementLogic.publicUnsoldReason(reserveNotMet: false),
            "未成交"
        )
    }

    // MARK: Cancel / relist eligibility

    func testSellerCancelRequiresZeroBids() {
        XCTAssertTrue(AuctionSettlementLogic.canSellerCancel(status: "live", bidCount: 0))
        XCTAssertTrue(AuctionSettlementLogic.canSellerCancel(status: "scheduled", bidCount: 0))
        XCTAssertFalse(AuctionSettlementLogic.canSellerCancel(status: "live", bidCount: 1))
        XCTAssertFalse(AuctionSettlementLogic.canSellerCancel(status: "ended", bidCount: 0))
        XCTAssertEqual(
            AuctionSettlementLogic.sellerCancelBlockedReason(bidCount: 2),
            AuctionSettlementCopy.cancelDisabledHasBids
        )
    }

    func testRelistBlockedCodes() {
        XCTAssertTrue(AuctionSettlementLogic.canRelist(status: "unsold"))
        XCTAssertFalse(AuctionSettlementLogic.canRelist(status: "unsold", secondChancePending: true))
        XCTAssertEqual(
            AuctionSettlementLogic.relistBlockedReason(status: "live", secondChancePending: false),
            .notUnsold
        )
        XCTAssertEqual(
            AuctionSettlementLogic.relistBlockedReason(status: "unsold", secondChancePending: true),
            .secondChanceOpen
        )
    }

    func testForceCancelReasonMinLength() {
        XCTAssertFalse(AuctionSettlementLogic.isForceCancelReasonValid("短"))
        XCTAssertFalse(AuctionSettlementLogic.isForceCancelReasonValid("一二三四五六七八九")) // 9
        XCTAssertTrue(AuctionSettlementLogic.isForceCancelReasonValid("一二三四五六七八九十")) // 10
        XCTAssertTrue(AuctionSettlementLogic.isForceCancelReasonValid("  运营强制撤拍原因说明  "))
    }

    // MARK: Pay deadline / N-06

    func testPayDeadlineAndRemind() {
        let hammer = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = AuctionSettlementLogic.payDeadline(hammerAt: hammer, payHours: 24)
        XCTAssertEqual(deadline.timeIntervalSince(hammer), 24 * 3600)

        let remind = AuctionSettlementLogic.payRemindAt(payDeadline: deadline, hammerAt: hammer)
        XCTAssertEqual(remind.timeIntervalSince(deadline), -2 * 3600)

        // Short audit window: remind collapses to hammerAt
        let shortDeadline = AuctionSettlementLogic.payDeadline(hammerAt: hammer, payHours: 1)
        let shortRemind = AuctionSettlementLogic.payRemindAt(payDeadline: shortDeadline, hammerAt: hammer)
        XCTAssertEqual(shortRemind, hammer)

        XCTAssertTrue(
            AuctionSettlementLogic.isPayRemindWindow(
                now: remind.addingTimeInterval(60),
                payDeadline: deadline,
                hammerAt: hammer
            )
        )
        XCTAssertFalse(
            AuctionSettlementLogic.isPayRemindWindow(
                now: remind.addingTimeInterval(-3600),
                payDeadline: deadline,
                hammerAt: hammer
            )
        )
    }

    func testRelistEndAtMustBeAtLeast24h() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(AuctionSettlementLogic.isRelistEndAtValid(now.addingTimeInterval(23 * 3600), now: now))
        XCTAssertTrue(AuctionSettlementLogic.isRelistEndAtValid(now.addingTimeInterval(24 * 3600), now: now))
    }

    // MARK: Penalty ladder

    func testBiddingBanLadder() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = AuctionSettlementLogic.biddingBanUntil(offenseCount: 1, now: now)
        XCTAssertEqual(first?.timeIntervalSince(now), TimeInterval(30 * 86_400))
        let second = AuctionSettlementLogic.biddingBanUntil(offenseCount: 2, now: now)
        XCTAssertEqual(second?.timeIntervalSince(now), TimeInterval(90 * 86_400))
        XCTAssertNil(AuctionSettlementLogic.biddingBanUntil(offenseCount: 3, now: now))
        XCTAssertNil(AuctionSettlementLogic.biddingBanUntil(offenseCount: 9, now: now))
    }

    func testForfeitSplit50_50() {
        XCTAssertEqual(AuctionSettlementLogic.forfeitSellerAmount(depositFen: 10_000), 5_000)
        XCTAssertEqual(AuctionSettlementLogic.forfeitPlatformAmount(depositFen: 10_000), 5_000)
        XCTAssertEqual(AuctionSettlementLogic.forfeitSellerAmount(depositFen: 10_001), 5_000)
        XCTAssertEqual(AuctionSettlementLogic.forfeitPlatformAmount(depositFen: 10_001), 5_001)
    }

    // MARK: Outcome

    func testOutcomeResolution() {
        XCTAssertEqual(
            AuctionSettlementLogic.outcome(
                lotStatus: "ended",
                viewerIsWinner: true,
                viewerHadBid: true,
                orderCancelledAsDefault: false
            ),
            .won
        )
        XCTAssertEqual(
            AuctionSettlementLogic.outcome(
                lotStatus: "ended",
                viewerIsWinner: false,
                viewerHadBid: true,
                orderCancelledAsDefault: false
            ),
            .lost
        )
        XCTAssertEqual(
            AuctionSettlementLogic.outcome(
                lotStatus: "unsold",
                viewerIsWinner: false,
                viewerHadBid: false,
                orderCancelledAsDefault: false
            ),
            .unsold
        )
        XCTAssertEqual(
            AuctionSettlementLogic.outcome(
                lotStatus: "ended",
                viewerIsWinner: true,
                viewerHadBid: true,
                orderCancelledAsDefault: true
            ),
            .defaulted
        )
    }

    // MARK: Decode / encode

    func testFeeRuleSnapshotDecode() throws {
        let json = """
        {
          "seller_type": "personal",
          "trade_type": "auction",
          "rate_bp": 500,
          "rule_id": "fee_auction_personal_v1",
          "snapped_at": "2026-11-05T12:00:00Z",
          "shipping_fee": 0,
          "platform_fee": 2500,
          "seller_net": 47500
        }
        """.data(using: .utf8)!
        let snap = try decoder.decode(FeeRuleSnapshot.self, from: json)
        XCTAssertEqual(snap.sellerType, "personal")
        XCTAssertEqual(snap.rateBp, 500)
        XCTAssertEqual(snap.platformFee, 2500)
        XCTAssertEqual(snap.ratePercentText, "5.0%")
    }

    func testRelistRequestEncode() throws {
        let end = Date(timeIntervalSince1970: 1_700_086_400)
        let req = RelistLotRequest(endAt: end, startPrice: 50_000, bidIncrement: 5_000, depositAmount: 5_000)
        let data = try encoder.encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["start_price"] as? Int, 50_000)
        XCTAssertEqual(obj?["bid_increment"] as? Int, 5_000)
        XCTAssertNotNil(obj?["end_at"])
    }

    func testRelistResponseDecodeFlatAndNested() throws {
        let flat = """
        {"lot_id": 42, "status": "scheduled", "relisted_from_lot_id": 7, "end_at": "2026-11-07T12:00:00Z"}
        """.data(using: .utf8)!
        let a = try decoder.decode(RelistLotResponse.self, from: flat)
        XCTAssertEqual(a.lotId, 42)
        XCTAssertEqual(a.relistedFromLotId, 7)

        let nested = """
        {"lot": {"id": 99, "status": "live", "relisted_from_lot_id": 7, "end_at": "2026-11-07T12:00:00Z"}}
        """.data(using: .utf8)!
        let b = try decoder.decode(RelistLotResponse.self, from: nested)
        XCTAssertEqual(b.lotId, 99)
        XCTAssertEqual(b.status, "live")
    }

    func testSecondChanceOfferDecode() throws {
        let json = """
        {
          "id": 3,
          "lot_id": 10,
          "from_order_id": 20,
          "invitee_id": 8,
          "price": 180000,
          "expires_at": "2026-11-06T12:00:00Z",
          "status": "pending"
        }
        """.data(using: .utf8)!
        let offer = try decoder.decode(SecondChanceOffer.self, from: json)
        XCTAssertEqual(offer.price, 180_000)
        XCTAssertTrue(offer.isAcceptable)
        XCTAssertEqual(offer.status.displayLabel, "次高价待确认")
    }

    func testCancelAuctionOrderConfirmPhrase() throws {
        let req = CancelAuctionOrderRequest()
        XCTAssertEqual(req.confirm, CancelAuctionOrderRequest.confirmPhrase)
        let data = try encoder.encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["confirm"] as? String, "取消即视为违约")
    }

    func testErrorCodesAndCopy() {
        XCTAssertEqual(AuctionSettlementErrorCode.priceLocked.rawValue, "price_locked")
        XCTAssertEqual(AuctionSettlementErrorCode.lotHasBids.rawValue, "lot_has_bids")
        XCTAssertTrue(AuctionSettlementErrorCode.priceLocked.opensAfterSalesHint)
        XCTAssertTrue(AuctionSettlementErrorCode.lotHasBids.blocksSellerCancel)
        XCTAssertEqual(AuctionSettlementCopy.priceLocked, "成交价已锁定，如需协商请走售后")
        XCTAssertEqual(AuctionSettlementCopy.unsoldEmpty, "暂无流拍拍品")
        XCTAssertEqual(AuctionSettlementCopy.cancelDisabledHasBids, "已有出价不可撤回")
        XCTAssertEqual(AuctionSettlementConfig.payHoursDefault, 24)
        XCTAssertEqual(AuctionSettlementConfig.creditPenalty, -10)
        XCTAssertEqual(AuctionSettlementConfig.firstBanDays, 30)
        XCTAssertEqual(AuctionSettlementConfig.defaultForfeitSellerBp, 5000)
    }

    func testDefaultSummaries() {
        let ban = Date(timeIntervalSince1970: 1_700_000_000 + 30 * 86_400)
        let buyer = AuctionDefaultBuyerSummary(banUntil: ban, orderId: 1, lotTitle: "F1")
        XCTAssertEqual(buyer.creditLine, "信用分 −10")
        XCTAssertTrue(buyer.banLine(dateText: { _ in "2026-12-01" }).contains("禁竞拍至"))

        let permanent = AuctionDefaultBuyerSummary(banUntil: nil, isPermanentBan: true)
        XCTAssertEqual(permanent.banLine(dateText: { _ in "" }), AuctionSettlementCopy.defaultBanPermanent)

        let seller = AuctionDefaultSellerSummary(depositFen: 20_000, canInviteSecondChance: true)
        XCTAssertEqual(seller.estimatedSellerShareFen, 10_000)
        XCTAssertEqual(seller.payoutStatusLabel, "处理中")
    }

    func testRelistPrefillBuildsRequest() {
        let prefill = RelistPrefill(
            sourceLotId: 7,
            title: "红牛 RB19",
            startPrice: 50_000,
            bidIncrement: 5_000,
            reservePrice: 80_000,
            depositAmount: 5_000
        )
        let end = Date(timeIntervalSince1970: 1_700_086_400)
        let req = prefill.makeRequest(endAt: end)
        XCTAssertEqual(req.startPrice, 50_000)
        XCTAssertEqual(req.reservePrice, 80_000)
        XCTAssertEqual(req.endAt, end)
    }
}
