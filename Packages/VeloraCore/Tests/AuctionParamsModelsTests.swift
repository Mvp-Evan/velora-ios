import XCTest
@testable import VeloraCore

final class AuctionParamsModelsTests: XCTestCase {
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

    // MARK: AUC-01 kinds

    func testAuctionKindMappingBySellerType() {
        XCTAssertEqual(AuctionSellerType(raw: "personal").allowedAuctionKinds, [.personal])
        XCTAssertEqual(
            AuctionSellerType(raw: "proxy_agent").allowedAuctionKinds,
            [.proxySession, .proxyFree]
        )
        XCTAssertEqual(AuctionSellerType(raw: "brand").allowedAuctionKinds, [.brandSpecial])
        XCTAssertFalse(AuctionSellerType(raw: "personal").showsAuctionKindPicker)
        XCTAssertTrue(AuctionSellerType(raw: "proxy_agent").showsAuctionKindPicker)

        XCTAssertEqual(
            AuctionKindResolver.resolve(sellerTypeRaw: "personal", preferred: "proxy_session"),
            .personal
        )
        XCTAssertEqual(
            AuctionKindResolver.resolve(sellerTypeRaw: "proxy_agent", preferred: "proxy_free"),
            .proxyFree
        )
        XCTAssertFalse(AuctionKindResolver.isAllowed(.brandSpecial, sellerTypeRaw: "personal"))
    }

    // MARK: AUC-02 / 8.3 deposit

    func testDepositFormulaAcceptanceCases() {
        // DES §14: 起拍 1 / 800 / 30000 元 → 50 / 80 / 2000 元
        XCTAssertEqual(AuctionDepositFormula.systemFloor(startPriceFen: 100), 5_000)
        XCTAssertEqual(AuctionDepositFormula.systemFloor(startPriceFen: 80_000), 8_000)
        XCTAssertEqual(AuctionDepositFormula.systemFloor(startPriceFen: 3_000_000), 200_000)

        XCTAssertEqual(
            AuctionDepositFormula.validate(depositFen: 4_999, startPriceFen: 80_000),
            .depositBelowFloor
        )
        XCTAssertNil(AuctionDepositFormula.validate(depositFen: 8_000, startPriceFen: 80_000))
        XCTAssertNil(AuctionDepositFormula.validate(depositFen: 12_000, startPriceFen: 80_000))

        XCTAssertTrue(AuctionDepositFormula.previewCopy(startPriceFen: 80_000).contains("¥80"))
    }

    // MARK: AUC-03 ladder

    func testDefaultLadderBands() {
        XCTAssertEqual(BidIncrementLadder.minIncrement(forPriceFen: 0), 1_000)
        XCTAssertEqual(BidIncrementLadder.minIncrement(forPriceFen: 49_900), 1_000)
        XCTAssertEqual(BidIncrementLadder.minIncrement(forPriceFen: 50_000), 5_000)
        XCTAssertEqual(BidIncrementLadder.minIncrement(forPriceFen: 199_900), 5_000)
        XCTAssertEqual(BidIncrementLadder.minIncrement(forPriceFen: 200_000), 10_000)
        XCTAssertEqual(BidIncrementLadder.minIncrement(forPriceFen: 500_000), 20_000)
        XCTAssertEqual(BidIncrementLadder.minIncrement(forPriceFen: 2_000_000), 50_000)
    }

    func testPublishRejectsIncrementBelowTier() {
        // 起拍 800 元 → 档位最小 50 元；10 元拒绝
        XCTAssertEqual(
            BidIncrementLadder.validateSellerIncrement(incrementFen: 1_000, startPriceFen: 80_000),
            .incrementBelowTier
        )
        XCTAssertNil(
            BidIncrementLadder.validateSellerIncrement(incrementFen: 5_000, startPriceFen: 80_000)
        )
    }

    func testEffectiveIncrementCrossesTier() {
        // 起拍 1800 元、卖家幅度 50 元；价到 2000 元后有效幅度 = max(50,100)=100 元
        let seller: Int64 = 5_000
        let at1800 = BidIncrementLadder.effectiveIncrement(
            sellerBidIncrementFen: seller,
            currentPriceFen: 180_000
        )
        XCTAssertEqual(at1800, 5_000) // ladder at 1800 = 50 yuan
        let at2000 = BidIncrementLadder.effectiveIncrement(
            sellerBidIncrementFen: seller,
            currentPriceFen: 200_000
        )
        XCTAssertEqual(at2000, 10_000)
    }

    func testMinNextBidAndNMultiple() {
        let start: Int64 = 10_000
        let sellerInc: Int64 = 1_000

        // First bid may equal start
        XCTAssertEqual(
            BidIncrementLadder.minNextBid(
                startPriceFen: start, currentPriceFen: start, bidCount: 0,
                sellerBidIncrementFen: sellerInc
            ),
            start
        )
        XCTAssertTrue(
            BidIncrementLadder.isValidBidAmount(
                amountFen: start, startPriceFen: start, currentPriceFen: start,
                bidCount: 0, sellerBidIncrementFen: sellerInc
            )
        )
        // n=3 first raise
        XCTAssertTrue(
            BidIncrementLadder.isValidBidAmount(
                amountFen: start + 3 * sellerInc, startPriceFen: start, currentPriceFen: start,
                bidCount: 0, sellerBidIncrementFen: sellerInc
            )
        )
        // Off-by-1 fen fails
        XCTAssertFalse(
            BidIncrementLadder.isValidBidAmount(
                amountFen: start + sellerInc + 1, startPriceFen: start, currentPriceFen: start,
                bidCount: 0, sellerBidIncrementFen: sellerInc
            )
        )

        let current: Int64 = 200_000
        let next = BidIncrementLadder.minNextBid(
            startPriceFen: start, currentPriceFen: current, bidCount: 2,
            sellerBidIncrementFen: 5_000
        )
        // effective = max(50, 100) = 100 yuan
        XCTAssertEqual(next, 210_000)
        XCTAssertTrue(
            BidIncrementLadder.isValidBidAmount(
                amountFen: 220_000, startPriceFen: start, currentPriceFen: current,
                bidCount: 2, sellerBidIncrementFen: 5_000
            )
        )
        XCTAssertFalse(
            BidIncrementLadder.isValidBidAmount(
                amountFen: 210_001, startPriceFen: start, currentPriceFen: current,
                bidCount: 2, sellerBidIncrementFen: 5_000
            )
        )
    }

    func testDecodeBidIncrementsMeta() throws {
        let json = """
        {
          "version": 3,
          "tiers": [
            {"min_price_fen": 0, "max_price_fen": 49900, "min_increment_fen": 1000},
            {"min_price_fen": 50000, "max_price_fen": null, "min_increment_fen": 5000}
          ],
          "effective_at": "2026-11-05T00:00:00Z"
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(BidIncrementTiersResponse.self, from: json)
        XCTAssertEqual(resp.version, 3)
        XCTAssertEqual(resp.tiers.count, 2)
        XCTAssertEqual(resp.tiers[0].minIncrementFen, 1_000)
        XCTAssertNil(resp.tiers[1].maxPriceFen)
    }

    func testDecodeLadderSnapshotCompact() throws {
        let json = """
        {
          "version": 3,
          "tiers": [
            {"min": 0, "max": 49900, "inc": 1000},
            {"min": 2000000, "max": null, "inc": 50000}
          ]
        }
        """.data(using: .utf8)!
        let snap = try decoder.decode(BidIncrementLadderSnapshot.self, from: json)
        XCTAssertEqual(snap.version, 3)
        XCTAssertEqual(snap.tiers.last?.minIncrementFen, 50_000)
    }

    // MARK: AUC-06 duration

    func testDurationCodesAndBounds() {
        XCTAssertEqual(AuctionDurationCode.from(days: 3), .d3)
        XCTAssertEqual(AuctionDurationCode.d7.rawValue, "7d")
        XCTAssertEqual(PublishAuctionDuration.durationCode(days: 5), "5d")

        let now = Date()
        XCTAssertEqual(
            PublishAuctionDuration.validateEndAt(now.addingTimeInterval(23 * 3600), now: now),
            .endAtTooSoon
        )
        XCTAssertNil(
            PublishAuctionDuration.validateEndAt(now.addingTimeInterval(24 * 3600), now: now)
        )
        XCTAssertEqual(
            PublishAuctionDuration.validateEndAt(now.addingTimeInterval(15 * 86_400), now: now),
            .endAtTooFar
        )
    }

    func testLiveTipsReflectDepositAndIncrement() {
        let tips = PublishAuctionLiveTips.make(
            startPriceFen: 80_000,
            incrementFen: 1_000,
            depositFen: 8_000,
            durationDays: 3,
            useCustomEndAt: false,
            endAt: Date()
        )
        XCTAssertTrue(tips.depositOK)
        XCTAssertFalse(tips.incrementOK)
        XCTAssertTrue(tips.durationOK)
        XCTAssertTrue(tips.depositTip.contains("¥80"))
        XCTAssertTrue(tips.incrementTip.contains("不可低于"))
    }

    func testEditionRequiredForBrandSpecial() {
        var d = PublishDraftPayload(tradeType: .auction)
        d.title = "合法标题五个字"
        d.startPriceYuan = "200"
        d.depositYuan = "50"
        d.incrementYuan = "10"
        d.durationDays = 3
        d.auctionKind = AuctionKind.brandSpecial.rawValue
        d.productImages = (0..<5).map { PublishImageSlot(sha256: "x\($0)") }
        d.feeQuoteId = "fq"
        XCTAssertEqual(PublishValidator.validate(d, enabledScales: ["1:43"]), .editionRequired)
        d.limitedNo = "01/99"
        XCTAssertNil(PublishValidator.validate(d, enabledScales: ["1:43"]))
    }
}
