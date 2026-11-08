import XCTest
@testable import VeloraCore

final class OfferModelsTests: XCTestCase {
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
        return e
    }()

    // MARK: Defaults / copy

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(OfferConfigDefaults.minRatio, 0.50, accuracy: 0.0001)
        XCTAssertEqual(OfferConfigDefaults.ttlHours, 24)
        XCTAssertEqual(OfferConfigDefaults.maxRounds, 3)
        XCTAssertEqual(OfferConfigDefaults.payHours, 2)
        XCTAssertEqual(OfferConfigDefaults.priceDropCooldownHours, 24)
        XCTAssertEqual(OfferConfigDefaults.creditMinToOffer, 60)
        XCTAssertEqual(OfferConfigDefaults.creditDeltaUnpaid, -2)
        XCTAssertEqual(OfferConfigDefaults.messageTypeOfferCard, "offer_card")
        XCTAssertTrue(OfferLogic.lockPayHoursDistinctFromBuyNow())
    }

    func testCopyNeverImpliesChatCheckout() {
        XCTAssertTrue(OfferCopy.chatGuide.contains("议价"))
        XCTAssertTrue(OfferCopy.chatAmountHint.contains("报价卡片"))
        XCTAssertFalse(OfferCopy.chatAmountHint.contains("按此价买"))
        XCTAssertEqual(OfferCopy.priceDropPushTitle, "你收藏的商品降价了")
    }

    // MARK: Min price / validation

    func testMinPriceCeilHalf() {
        XCTAssertEqual(OfferLogic.minPriceFen(listPriceFen: 10_000), 5_000)
        XCTAssertEqual(OfferLogic.minPriceFen(listPriceFen: 10_001), 5_001)
        XCTAssertEqual(OfferLogic.minPriceFen(listPriceFen: 99), 50)
        XCTAssertEqual(OfferLogic.minPriceFen(listPriceFen: 100), 50)
        XCTAssertEqual(OfferLogic.minPriceFen(listPriceFen: 101), 51)
    }

    func testValidateBuyerQuoteBounds() {
        let list: Int64 = 10_000
        let min = OfferLogic.minPriceFen(listPriceFen: list)
        XCTAssertNil(OfferLogic.validateOfferPrice(priceFen: min, listPriceFen: list, minPriceFen: min, asBuyerQuote: true))
        XCTAssertNil(OfferLogic.validateOfferPrice(priceFen: list, listPriceFen: list, minPriceFen: min, asBuyerQuote: true))
        XCTAssertEqual(
            OfferLogic.validateOfferPrice(priceFen: min - 1, listPriceFen: list, minPriceFen: min, asBuyerQuote: true),
            .offerBelowMin
        )
        XCTAssertNotNil(OfferLogic.localPriceMessage(priceFen: list + 1, listPriceFen: list, minPriceFen: min, asBuyerQuote: true))
        // Seller counter may go below buyer ask but not below min.
        XCTAssertNil(OfferLogic.validateOfferPrice(priceFen: min, listPriceFen: list, minPriceFen: min, asBuyerQuote: false))
    }

    func testRoundLimits() {
        XCTAssertTrue(OfferLogic.canBuyerQuote(buyerQuoteCount: 0))
        XCTAssertTrue(OfferLogic.canBuyerQuote(buyerQuoteCount: 2))
        XCTAssertFalse(OfferLogic.canBuyerQuote(buyerQuoteCount: 3))
        XCTAssertTrue(OfferLogic.canSellerCounter(buyerQuoteCount: 2))
        XCTAssertFalse(OfferLogic.canSellerCounter(buyerQuoteCount: 3))
        XCTAssertEqual(OfferLogic.nextBuyerQuoteCount(current: 2, isBuyerQuote: true), 3)
        XCTAssertEqual(OfferLogic.nextBuyerQuoteCount(current: 2, isBuyerQuote: false), 2)
    }

    // MARK: State machine

    func testLegalTransitions() {
        XCTAssertTrue(OfferLogic.canTransition(from: .pendingSeller, to: .accepted))
        XCTAssertTrue(OfferLogic.canTransition(from: .pendingSeller, to: .pendingBuyer))
        XCTAssertTrue(OfferLogic.canTransition(from: .pendingBuyer, to: .pendingSeller))
        XCTAssertFalse(OfferLogic.canTransition(from: .rejected, to: .accepted))
        XCTAssertFalse(OfferLogic.canTransition(from: .expired, to: .pendingSeller))
        XCTAssertFalse(OfferLogic.canTransition(from: .superseded, to: .accepted))
        XCTAssertTrue(OfferStatus.pendingSeller.isPending)
        XCTAssertTrue(OfferStatus.expired.isInactiveChrome)
        XCTAssertTrue(OfferStatus.accepted.isTerminal)
    }

    func testDefaultActionsByRole() {
        XCTAssertEqual(
            OfferLogic.defaultActions(status: .pendingSeller, role: .seller, buyerQuoteCount: 1),
            [.accept, .reject, .counter]
        )
        XCTAssertEqual(
            OfferLogic.defaultActions(status: .pendingSeller, role: .seller, buyerQuoteCount: 3),
            [.accept, .reject]
        )
        XCTAssertEqual(
            OfferLogic.defaultActions(status: .pendingSeller, role: .buyer),
            [.cancel]
        )
        XCTAssertEqual(
            OfferLogic.defaultActions(status: .accepted, role: .buyer, hasOrder: true),
            [.pay]
        )
        XCTAssertTrue(OfferLogic.defaultActions(status: .expired, role: .seller).isEmpty)
    }

    // MARK: Countdown

    func testOfferAndPayCountdowns() {
        let server = Date(timeIntervalSince1970: 1_700_000_000)
        let offerEnd = server.addingTimeInterval(24 * 3600)
        let payEnd = OfferLogic.payDeadline(from: server)
        XCTAssertEqual(OfferLogic.countdownSeconds(deadline: offerEnd, serverTime: server), 24 * 3600)
        XCTAssertEqual(OfferLogic.countdownSeconds(deadline: payEnd, serverTime: server), 2 * 3600)
        XCTAssertTrue(OfferLogic.offerCountdownLine(seconds: 90).contains("01:30"))
        XCTAssertTrue(OfferLogic.offerCountdownLine(seconds: 90).contains(OfferCopy.serverTimeHint))
        XCTAssertTrue(OfferLogic.payCountdownLine(seconds: 7200).contains("02:00:00"))
        XCTAssertEqual(OfferLogic.formatCountdown(seconds: 90_000), "1天01:00:00")
    }

    // MARK: Gates / reject

    func testOfferGate() {
        XCTAssertEqual(
            OfferLogic.offerGate(
                isLoggedIn: false, realNameDone: false, creditScore: 100,
                isRestricted: false, isOwner: false, negotiable: true
            ),
            .unauthorized
        )
        XCTAssertEqual(
            OfferLogic.offerGate(
                isLoggedIn: true, realNameDone: true, creditScore: 100,
                isRestricted: false, isOwner: false, negotiable: false
            ),
            .listingNotNegotiable
        )
        XCTAssertEqual(
            OfferLogic.offerGate(
                isLoggedIn: true, realNameDone: true, creditScore: 100,
                isRestricted: false, isOwner: true, negotiable: true
            ),
            .selfTradeForbidden
        )
        XCTAssertEqual(
            OfferLogic.offerGate(
                isLoggedIn: true, realNameDone: true, creditScore: 100,
                isRestricted: false, isOwner: false, negotiable: true, unpaidBanned: true
            ),
            .offerUnpaidBanned
        )
        XCTAssertNil(
            OfferLogic.offerGate(
                isLoggedIn: true, realNameDone: true, creditScore: 60,
                isRestricted: false, isOwner: false, negotiable: true
            )
        )
    }

    func testRejectNoteValidation() {
        XCTAssertNil(OfferLogic.validateRejectNote(reason: .priceNotFit, note: nil))
        XCTAssertEqual(OfferLogic.validateRejectNote(reason: .other, note: "  "), "请填写原因")
        XCTAssertNil(OfferLogic.validateRejectNote(reason: .other, note: "已谈妥其他买家"))
        let long = String(repeating: "啊", count: OfferConfigDefaults.rejectOtherMaxChars + 1)
        XCTAssertNotNil(OfferLogic.validateRejectNote(reason: .other, note: long))
    }

    // MARK: Price drop DIR-05

    func testPriceDropNotifyRules() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(
            OfferLogic.shouldNotifyPriceDrop(
                oldPriceFen: 10_000, newPriceFen: 9_000, listingOnSale: true,
                lastNotifiedAt: nil, now: now
            )
        )
        XCTAssertFalse(
            OfferLogic.shouldNotifyPriceDrop(
                oldPriceFen: 10_000, newPriceFen: 11_000, listingOnSale: true,
                lastNotifiedAt: nil, now: now
            )
        )
        XCTAssertFalse(
            OfferLogic.shouldNotifyPriceDrop(
                oldPriceFen: 10_000, newPriceFen: 9_000, listingOnSale: false,
                lastNotifiedAt: nil, now: now
            )
        )
        let recent = now.addingTimeInterval(-12 * 3600)
        XCTAssertFalse(
            OfferLogic.shouldNotifyPriceDrop(
                oldPriceFen: 9_000, newPriceFen: 8_000, listingOnSale: true,
                lastNotifiedAt: recent, now: now
            )
        )
        let old = now.addingTimeInterval(-25 * 3600)
        XCTAssertTrue(
            OfferLogic.shouldNotifyPriceDrop(
                oldPriceFen: 9_000, newPriceFen: 8_000, listingOnSale: true,
                lastNotifiedAt: old, now: now
            )
        )
        XCTAssertTrue(OfferLogic.cooldownSurvivesUnfavorite())
    }

    func testChatPriceNotBindingDetection() {
        XCTAssertTrue(OfferLogic.looksLikePriceOfferText("1500"))
        XCTAssertTrue(OfferLogic.looksLikePriceOfferText("1,500"))
        XCTAssertTrue(OfferLogic.looksLikePriceOfferText("¥1200元"))
        XCTAssertTrue(OfferLogic.looksLikePriceOfferText("1200成交"))
        XCTAssertFalse(OfferLogic.looksLikePriceOfferText("还在吗？"))
        XCTAssertFalse(OfferLogic.looksLikePriceOfferText(""))
        XCTAssertEqual(OfferErrorCode.chatPriceNotBinding.fallbackMessage, "请使用报价卡片议价")
    }

    // MARK: Decode

    func testDecodeOfferCard() throws {
        let json = """
        {
          "offer_id": "42",
          "listing_id": 7,
          "cover": "https://cdn.example/a.jpg",
          "title": "RB19 直购",
          "list_price": 128000,
          "offer_price": 100000,
          "expires_at": "2026-11-06T04:00:00Z",
          "round": 2,
          "max_rounds": 3,
          "status": "pending_seller",
          "actions": ["accept", "reject", "counter"],
          "min_price": 64000,
          "buyer_quote_count": 2
        }
        """.data(using: .utf8)!
        let card = try decoder.decode(OfferCard.self, from: json)
        XCTAssertEqual(card.offerId, 42)
        XCTAssertEqual(card.listingId, 7)
        XCTAssertEqual(card.roundText, "第 2/3 轮")
        XCTAssertEqual(card.actions, [.accept, .reject, .counter])
        XCTAssertTrue(card.showsActions)
        XCTAssertTrue(card.accessibilityLabel.contains("报价卡片"))
        XCTAssertTrue(card.accessibilityLabel.contains("标价"))
    }

    func testDecodeCreateAndAccept() throws {
        let createJSON = """
        {
          "offer_id": 9,
          "expires_at": "2026-11-06T04:00:00Z",
          "min_price": 5000,
          "round": 1,
          "status": "pending_seller",
          "server_time": "2026-11-05T04:00:00Z"
        }
        """.data(using: .utf8)!
        let created = try decoder.decode(CreateOfferResponse.self, from: createJSON)
        XCTAssertEqual(created.offerId, 9)
        XCTAssertEqual(created.minPrice, 5_000)

        let acceptJSON = """
        {
          "order_id": "1001",
          "pay_deadline": "2026-11-05T06:00:00Z",
          "server_time": "2026-11-05T04:00:00Z",
          "amount": 10000,
          "offer_id": 9
        }
        """.data(using: .utf8)!
        let accepted = try decoder.decode(AcceptOfferResponse.self, from: acceptJSON)
        XCTAssertEqual(accepted.orderId, 1001)
        XCTAssertEqual(
            OfferLogic.countdownSeconds(deadline: accepted.payDeadline, serverTime: accepted.serverTime!),
            2 * 3600
        )
    }

    func testEncodeRejectAndCounter() throws {
        let reject = try encoder.encode(RejectOfferRequest(reason: .other, note: "已售意向"))
        let robj = try JSONSerialization.jsonObject(with: reject) as? [String: Any]
        XCTAssertEqual(robj?["reason"] as? String, "other")
        XCTAssertEqual(robj?["note"] as? String, "已售意向")

        let counter = try encoder.encode(CounterOfferRequest(price: 88_000))
        let cobj = try JSONSerialization.jsonObject(with: counter) as? [String: Any]
        XCTAssertEqual(cobj?["price"] as? Int, 88_000)
    }

    func testDecodeFavoritePriceSnapshot() throws {
        let json = """
        {"price_snapshot": 128000, "listing_id": "7", "favorited": true}
        """.data(using: .utf8)!
        let fav = try decoder.decode(FavoriteListingResult.self, from: json)
        XCTAssertEqual(fav.priceSnapshot, 128_000)
        XCTAssertEqual(fav.listingId, 7)

        let empty = try decoder.decode(FavoriteListingResult.self, from: Data("{}".utf8))
        XCTAssertNil(empty.priceSnapshot)
    }

    func testSortPendingByExpiry() {
        let now = Date()
        let a = Offer(
            id: 1, listingId: 1, buyerId: 2, sellerId: 3, round: 1,
            initiator: .buyer, price: 100, status: .pendingSeller,
            expiresAt: now.addingTimeInterval(3600)
        )
        let b = Offer(
            id: 2, listingId: 1, buyerId: 4, sellerId: 3, round: 1,
            initiator: .buyer, price: 200, status: .pendingBuyer,
            expiresAt: now.addingTimeInterval(600)
        )
        let rejected = Offer(
            id: 3, listingId: 1, buyerId: 5, sellerId: 3, round: 1,
            initiator: .buyer, price: 150, status: .rejected,
            expiresAt: now.addingTimeInterval(100)
        )
        XCTAssertEqual(OfferLogic.sortPendingByExpiry([a, b, rejected]).map(\.id), [2, 1])
    }

    func testErrorMessages() {
        XCTAssertTrue(OfferErrorCode.offerBelowMin.message(minPriceFen: 5_000).contains("¥50"))
        XCTAssertEqual(OfferErrorCode.stockInsufficient.fallbackMessage, "商品已被锁定，请稍后再试或等待释放")
        XCTAssertTrue(OfferErrorCode.offerUnpaidBanned.opensLogin == false)
        XCTAssertTrue(OfferErrorCode.unauthorized.opensLogin)
    }
}
