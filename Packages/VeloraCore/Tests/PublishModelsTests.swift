import XCTest
@testable import VeloraCore

final class PublishModelsTests: XCTestCase {
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

    func testImageCountBounds() {
        XCTAssertEqual(PublishImageNorms.validateProductImages(count: 4, hashes: []), .imageCountInvalid)
        XCTAssertNil(PublishImageNorms.validateProductImages(count: 5, hashes: ["a", "b", "c", "d", "e"]))
        XCTAssertEqual(PublishImageNorms.validateProductImages(count: 10, hashes: []), .imageCountInvalid)
        XCTAssertEqual(
            PublishImageNorms.validateProductImages(count: 5, hashes: Array(repeating: "same", count: 5)),
            .imagesNotDistinct
        )
        XCTAssertEqual(PublishImageNorms.remainingProductCopy(current: 3), "再拍 2 张")
    }

    func testFlawRequiredWhenConditionFlawed() {
        XCTAssertEqual(
            PublishImageNorms.validateFlawImages(count: 0, condition: .flawed),
            .flawRequired
        )
        XCTAssertNil(PublishImageNorms.validateFlawImages(count: 1, condition: .flawed))
        XCTAssertNil(PublishImageNorms.validateFlawImages(count: 0, condition: .newSealed))
    }

    func testRawSizeCap() {
        XCTAssertEqual(
            PublishImageNorms.validateRawSize(PublishLimits.maxBytesBeforeCompress + 1),
            .imageTooLarge
        )
        XCTAssertNil(PublishImageNorms.validateRawSize(1024))
    }

    func testSha256Deterministic() {
        let a = PublishImageNorms.sha256Hex(Data("hello".utf8))
        let b = PublishImageNorms.sha256Hex(Data("hello".utf8))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 64)
    }

    func testDepositDefaultClamp() {
        // 100 fen start → 10% = 10, clamped to 5000 (50 yuan)
        XCTAssertEqual(PublishDeposit.defaultAmount(startPriceFen: 100), PublishLimits.depositMinFen)
        // 250000 fen (2500 yuan) → 250 yuan = 25000 fen
        XCTAssertEqual(PublishDeposit.defaultAmount(startPriceFen: 250_000), 25_000)
        // Huge start clamps to 2000 yuan
        XCTAssertEqual(PublishDeposit.defaultAmount(startPriceFen: 100_000_000), PublishLimits.depositMaxFen)
        XCTAssertEqual(
            PublishDeposit.validate(depositFen: 100, startPriceFen: 250_000),
            .depositTooLow
        )
        XCTAssertNil(PublishDeposit.validate(depositFen: 25_000, startPriceFen: 250_000))
    }

    func testEndAtTooSoon() {
        let now = Date()
        XCTAssertEqual(
            PublishAuctionDuration.validateEndAt(now.addingTimeInterval(3600), now: now),
            .endAtTooSoon
        )
        XCTAssertNil(
            PublishAuctionDuration.validateEndAt(now.addingTimeInterval(25 * 3600), now: now)
        )
    }

    func testFeeQuoteFormulaExample() {
        // DES §5.7 / §14: 250000 fen × 4% → fee 10000, net 240000 (free shipping)
        let r = FeeQuoteFormula.estimate(priceFen: 250_000, rate: 0.04, shippingFeeFen: 0)
        XCTAssertEqual(r.platformFee, 10_000)
        XCTAssertEqual(r.sellerNet, 240_000)
    }

    func testContactGuardOnTitle() {
        XCTAssertTrue(PublishContactGuard.containsContactInfo("加我微信 abc_12345"))
        XCTAssertFalse(PublishContactGuard.containsContactInfo("Spark GR010 成色好"))
        XCTAssertEqual(
            PublishContactGuard.firstHit(in: [("title", "电话 13812345678"), ("description", "ok")]),
            "title"
        )
    }

    func testEntryGateOrder() {
        XCTAssertEqual(
            PublishEntryResolver.resolve(
                isLoggedIn: false, isFrozen: false, canPublish: true,
                realNameDone: false, sellerReady: false,
                actionKey: "auction", actionEnabled: true, actionTitle: "拍卖",
                capabilityAllows: { _ in true }
            ),
            .loginRequired
        )
        XCTAssertEqual(
            PublishEntryResolver.resolve(
                isLoggedIn: true, isFrozen: true, canPublish: false,
                realNameDone: true, sellerReady: true,
                actionKey: "auction", actionEnabled: true, actionTitle: "拍卖",
                capabilityAllows: { _ in true }
            ),
            .frozen
        )
        XCTAssertEqual(
            PublishEntryResolver.resolve(
                isLoggedIn: true, isFrozen: false, canPublish: true,
                realNameDone: false, sellerReady: false,
                actionKey: "fixed", actionEnabled: true, actionTitle: "直购",
                capabilityAllows: { _ in true }
            ),
            .realNameRequired
        )
        XCTAssertEqual(
            PublishEntryResolver.resolve(
                isLoggedIn: true, isFrozen: false, canPublish: true,
                realNameDone: true, sellerReady: false,
                actionKey: "fixed", actionEnabled: true, actionTitle: "直购",
                capabilityAllows: { _ in true }
            ),
            .sellerRequired
        )
        XCTAssertEqual(
            PublishEntryResolver.resolve(
                isLoggedIn: true, isFrozen: false, canPublish: true,
                realNameDone: true, sellerReady: true,
                actionKey: "post", actionEnabled: true, actionTitle: "帖子",
                capabilityAllows: { _ in true }
            ),
            .comingSoon("帖子")
        )
        XCTAssertEqual(
            PublishEntryResolver.resolve(
                isLoggedIn: true, isFrozen: false, canPublish: true,
                realNameDone: true, sellerReady: true,
                actionKey: "auction", actionEnabled: true, actionTitle: "拍卖",
                capabilityAllows: { $0 != "can_auction" }
            ),
            .capabilityDisabled("can_auction")
        )
        XCTAssertEqual(
            PublishEntryResolver.resolve(
                isLoggedIn: true, isFrozen: false, canPublish: true,
                realNameDone: true, sellerReady: true,
                actionKey: "auction", actionEnabled: true, actionTitle: "拍卖",
                capabilityAllows: { _ in true }
            ),
            .ok
        )
        // Release: capability fails before comingSoon (create UX still gated).
        XCTAssertEqual(
            PublishEntryResolver.resolve(
                isLoggedIn: true, isFrozen: false, canPublish: true,
                realNameDone: true, sellerReady: true,
                actionKey: "release", actionEnabled: false, actionTitle: "新品发售",
                requiresCapability: "can_spot_release",
                capabilityAllows: { _ in false }
            ),
            .capabilityDisabled("can_spot_release")
        )
        XCTAssertEqual(
            PublishEntryResolver.resolve(
                isLoggedIn: true, isFrozen: false, canPublish: true,
                realNameDone: true, sellerReady: true,
                actionKey: "release", actionEnabled: false, actionTitle: "新品发售",
                requiresCapability: "can_spot_release",
                capabilityAllows: { _ in true }
            ),
            .comingSoon("新品发售")
        )
        XCTAssertEqual(
            PublishEntryResolver.resolve(
                isLoggedIn: true, isFrozen: false, canPublish: true,
                realNameDone: true, sellerReady: true,
                actionKey: "spot_release", actionEnabled: true, actionTitle: "现货发售",
                capabilityAllows: { _ in true }
            ),
            .comingSoon("现货发售")
        )
    }

    func testFixedStockMustBeOne() {
        var d = PublishDraftPayload(tradeType: .fixed)
        d.title = "合法标题五个字"
        d.condition = PublishConditionGrade.newSealed.rawValue
        d.priceYuan = "100"
        d.stock = 1
        d.productImages = (0..<5).map { PublishImageSlot(sha256: "h\($0)") }
        XCTAssertNil(PublishValidator.validate(d, enabledScales: ["1:43"]))
        d.stock = 2
        XCTAssertEqual(PublishValidator.validate(d, enabledScales: ["1:43"]), .invalidStock)
    }

    func testDraftConflictPrefersNewer() {
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        XCTAssertTrue(PublishDraftSync.preferCloud(local: older, cloud: newer))
        XCTAssertFalse(PublishDraftSync.preferCloud(local: newer, cloud: older))
        XCTAssertTrue(PublishDraftSync.preferCloud(local: newer, cloud: newer))
    }

    func testValidatorProductAndContact() {
        var d = PublishDraftPayload(tradeType: .fixed)
        d.title = "合法标题五个字"
        d.condition = PublishConditionGrade.flawed.rawValue
        d.priceYuan = "100"
        d.productImages = (0..<5).map { i in
            PublishImageSlot(sha256: "h\(i)", role: i == 0 ? .cover : .gallery)
        }
        XCTAssertEqual(PublishValidator.validate(d, enabledScales: ["1:43"]), .flawRequired)
        d.flawDesc = "右侧细痕"
        d.flawImages = [PublishImageSlot(role: .flaw)]
        XCTAssertNil(PublishValidator.validate(d, enabledScales: ["1:43"]))

        d.title = "微信 wxid_abc12 出售"
        XCTAssertEqual(PublishValidator.validate(d, enabledScales: ["1:43"]), .contactInfoForbidden)
    }

    func testValidatorScaleAndFee() {
        var d = PublishDraftPayload(tradeType: .auction)
        d.title = "合法标题五个字"
        d.startPriceYuan = "200"
        d.depositYuan = "50"
        d.incrementYuan = "10"
        d.durationDays = 3
        d.productImages = (0..<5).map { PublishImageSlot(sha256: "x\($0)") }
        d.scale = "1:18"
        XCTAssertEqual(PublishValidator.validate(d, enabledScales: ["1:43"]), .scaleNotEnabled)

        d.scale = "1:43"
        XCTAssertEqual(
            PublishValidator.validate(d, enabledScales: ["1:43"], requireFeeQuote: true),
            .feeUnavailable
        )
        d.feeQuoteId = "fq_1"
        XCTAssertNil(PublishValidator.validate(d, enabledScales: ["1:43"], requireFeeQuote: true))
    }

    func testDecodeFeeQuote() throws {
        let json = """
        {
          "fee_quote_id": "fq_abc",
          "rate": 0.04,
          "platform_fee": 10000,
          "seller_net": 240000,
          "quote_hash": "h1",
          "rule_version": "v1",
          "expires_at": "2026-11-05T02:00:00Z",
          "price": 250000,
          "shipping_fee": 0
        }
        """.data(using: .utf8)!
        let q = try decoder.decode(FeeQuoteEstimate.self, from: json)
        XCTAssertEqual(q.feeQuoteId, "fq_abc")
        XCTAssertEqual(q.platformFee, 10_000)
        XCTAssertEqual(q.sellerNet, 240_000)
        XCTAssertEqual(q.ratePercentText, "4.0%")
        XCTAssertTrue(q.disclaimer.contains("成交当时费率"))
    }

    func testPublishSubmitResultStatusCopy() {
        XCTAssertEqual(PublishListingStatus.pendingReview.submitSuccessCopy, "前 5 件需审核，通过后上架")
        let r = PublishSubmitResult(listingId: 9, lotId: 3, status: "pending_review", publishedSeq: 1)
        XCTAssertEqual(r.listingStatus, .pendingReview)
    }

    func testTitleBounds() {
        XCTAssertFalse(PublishValidator.validateTitle("短"))
        XCTAssertTrue(PublishValidator.validateTitle("五个字标题啊"))
        XCTAssertFalse(PublishValidator.validateTitle(String(repeating: "字", count: 41)))
    }
}
