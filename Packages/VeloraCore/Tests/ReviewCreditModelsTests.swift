import XCTest
@testable import VeloraCore

final class ReviewCreditModelsTests: XCTestCase {
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
                return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
            }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date"))
        }
        return d
    }()

    // MARK: Config (design §15)

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(ReviewCreditConfigDefaults.creditInitial, 100)
        XCTAssertEqual(ReviewCreditConfigDefaults.creditCap, 120)
        XCTAssertEqual(ReviewCreditConfigDefaults.creditFloor, 0)
        XCTAssertEqual(ReviewCreditConfigDefaults.monthPlusCap, 10)
        XCTAssertEqual(ReviewCreditConfigDefaults.threshold80, 80)
        XCTAssertEqual(ReviewCreditConfigDefaults.threshold60, 60)
        XCTAssertEqual(ReviewCreditConfigDefaults.threshold40, 40)
        XCTAssertEqual(ReviewCreditConfigDefaults.reviewWindowDays, 15)
        XCTAssertEqual(ReviewCreditConfigDefaults.reviewMaxImages, 9)
        XCTAssertEqual(ReviewCreditConfigDefaults.sellerPerfWindowDays, 90)
        XCTAssertEqual(ReviewCreditConfigDefaults.arbitrationTagLabel, "经平台仲裁")
        XCTAssertEqual(ReviewCreditConfigDefaults.metricEmpty, "—")
    }

    // MARK: Enums

    func testRatingRoleSourceNormalize() {
        XCTAssertEqual(ReviewRating.normalize("好评"), .good)
        XCTAssertEqual(ReviewRating.normalize("BAD"), .bad)
        XCTAssertTrue(ReviewRating.bad.requiresSecondaryConfirm)
        XCTAssertFalse(ReviewRating.good.requiresSecondaryConfirm)
        XCTAssertEqual(ReviewRole.normalize("buyer"), .buyerToSeller)
        XCTAssertEqual(ReviewSource.normalize("auto"), .autoGood)
        XCTAssertEqual(ReviewStatus.normalize("moderated"), .hidden)
    }

    func testCreditReasonNormalizeAndCapMembership() {
        XCTAssertEqual(CreditReasonCode.normalize("auction_non_payment"), .auctionDefault)
        XCTAssertEqual(CreditReasonCode.normalize("im_sensitive_mute"), .imPenalty)
        XCTAssertTrue(CreditReasonCode.reviewGood.countsTowardMonthPlusCap)
        XCTAssertTrue(CreditReasonCode.manual.countsTowardMonthPlusCap)
        XCTAssertFalse(CreditReasonCode.shipLate.countsTowardMonthPlusCap)
    }

    func testErrorCodesBranchByCodeNotCopy() {
        XCTAssertEqual(ReviewCreditErrorCode.normalize("credit_below_60"), .creditBelow60)
        XCTAssertEqual(ReviewCreditErrorCode.normalize("credit_too_low"), .creditBelow80)
        XCTAssertTrue(ReviewCreditErrorCode.creditBelow40.isCreditBlock)
        XCTAssertEqual(ReviewCreditErrorCode.creditBelow80.blockThreshold, 80)
        XCTAssertNil(ReviewCreditErrorCode.orderNotCompleted.blockThreshold)
        let block = ReviewCreditLogic.creditBlock(fromCode: "credit_below_40", score: 39, action: "出价")
        XCTAssertEqual(block?.threshold, 40)
        XCTAssertTrue(block?.message.contains("39") == true)
        XCTAssertTrue(block?.message.contains("出价") == true)
        XCTAssertNil(ReviewCreditLogic.creditBlock(fromCode: "content_rejected"))
    }

    // MARK: Decode reviews

    func testOrderReviewDecodeArbitrationTag() throws {
        let json = """
        {
          "id": 9,
          "order_id": 100,
          "role": "buyer_to_seller",
          "rating": "good",
          "content": "很好",
          "image_urls": ["a.jpg"],
          "source": "user",
          "arbitration_tag": true,
          "status": "published",
          "from_nickname_masked": "买***",
          "published_at": "2026-11-01T08:00:00Z"
        }
        """.data(using: .utf8)!
        let r = try decoder.decode(OrderReview.self, from: json)
        XCTAssertTrue(r.arbitrationTag)
        XCTAssertFalse(r.arbitrationTagDismissible)
        XCTAssertEqual(r.resolvedRating, .good)
        XCTAssertEqual(r.displayAuthor, "买***")
        XCTAssertEqual(ReviewCreditCopy.arbitrationTag, "经平台仲裁")
    }

    func testOrderReviewsResponseMergesSides() throws {
        let json = """
        {
          "order_id": 55,
          "my_pending": true,
          "review_deadline": "2026-11-20T00:00:00Z",
          "server_time": "2026-11-05T00:00:00Z",
          "buyer_to_seller": {
            "id": 1, "order_id": 55, "role": "buyer_to_seller",
            "status": "pending", "arbitration_tag": false
          },
          "seller_to_buyer": {
            "id": 2, "order_id": 55, "role": "seller_to_buyer",
            "rating": "good", "status": "published", "source": "auto_good",
            "arbitration_tag": true
          }
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(OrderReviewsResponse.self, from: json)
        XCTAssertEqual(resp.orderId, 55)
        XCTAssertTrue(resp.pendingForMe)
        XCTAssertEqual(resp.items.count, 2)
        XCTAssertTrue(resp.sellerToBuyer?.showsArbitrationTag == true)
        XCTAssertEqual(resp.sellerToBuyer?.resolvedSource, .autoGood)
    }

    func testHiddenReviewCopy() {
        let r = OrderReview(
            id: 1, orderId: 1, role: "buyer_to_seller",
            status: ReviewStatus.hidden.rawValue
        )
        XCTAssertEqual(r.displayContent, ReviewCreditCopy.hiddenByModeration)
        XCTAssertTrue(ReviewCreditLogic.publicVisible(r))
    }

    func testUserReviewsListDecode() throws {
        let json = """
        {"reviews":[{"id":3,"order_id":1,"role":"buyer_to_seller","rating":"neutral","status":"published","arbitration_tag":false}],"next_cursor":"c1","total":1}
        """.data(using: .utf8)!
        let list = try decoder.decode(UserReviewsListResponse.self, from: json)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.nextCursor, "c1")
        XCTAssertEqual(list.items[0].resolvedRating, .neutral)
    }

    // MARK: Me credit

    func testMeCreditDecode() throws {
        let jsonTh = """
        {
          "score": 92,
          "month_plus_used": 7,
          "month_plus_cap": 10,
          "thresholds": {"th80": 80, "th60": 60, "th40": 40},
          "logs": [
            {"id":1,"delta":1,"reason_code":"review_good","at":"2026-11-01T00:00:00Z","score_after":92},
            {"id":2,"delta":0,"reason_code":"capped","capped":true,"month_key":"2026-11"}
          ],
          "server_time": "2026-11-05T12:00:00Z"
        }
        """.data(using: .utf8)!
        let me = try decoder.decode(MeCreditResponse.self, from: jsonTh)
        XCTAssertEqual(me.score, 92)
        XCTAssertEqual(me.monthPlusUsed, 7)
        XCTAssertEqual(me.monthPlusCap, 10)
        XCTAssertEqual(me.monthPlusRemaining, 3)
        XCTAssertFalse(me.isMonthPlusExhausted)
        XCTAssertEqual(me.logs.count, 2)
        XCTAssertTrue(me.logs[1].isMonthCapped)
        XCTAssertEqual(me.logs[1].displayTitle, ReviewCreditCopy.monthCapReached)
        XCTAssertNil(me.activeTier)

        let jsonNumericKeys = """
        {"score":100,"thresholds":{"80":80,"60":60,"40":40},"logs":[]}
        """.data(using: .utf8)!
        let me2 = try decoder.decode(MeCreditResponse.self, from: jsonNumericKeys)
        XCTAssertEqual(me2.thresholds.th80, 80)
        XCTAssertEqual(me2.thresholds.th60, 60)
        XCTAssertEqual(me2.thresholds.th40, 40)
    }

    func testMeCreditTierAt79() {
        let me = MeCreditResponse(score: 79)
        XCTAssertEqual(me.activeTier, .creditBelow80)
        XCTAssertEqual(MeCreditResponse(score: 59).activeTier, .creditBelow60)
        XCTAssertEqual(MeCreditResponse(score: 39).activeTier, .creditBelow40)
        // Exact thresholds are allowed for that tier (design §7: 80 bid OK, 60 buy OK).
        XCTAssertNil(MeCreditResponse(score: 80).activeTier)
        // Score 60 is still <80 → bid/lottery blocked, but purchase allowed.
        XCTAssertEqual(MeCreditResponse(score: 60).activeTier, .creditBelow80)
    }

    func testCreditLogReasonAlias() throws {
        let json = """
        {"id":8,"delta":-10,"reason":"auction_non_payment","ref_type":"order","ref_id":"99"}
        """.data(using: .utf8)!
        let log = try decoder.decode(CreditLogItem.self, from: json)
        XCTAssertEqual(log.resolvedReason, .auctionDefault)
        XCTAssertEqual(log.deltaDisplay, "-10")
    }

    // MARK: Seller card

    func testSellerCardEmptyShowsDash() throws {
        let json = """
        {"user_id":12,"score":100,"sold_count":0,"stale":false}
        """.data(using: .utf8)!
        let card = try decoder.decode(SellerCardMetrics.self, from: json)
        XCTAssertEqual(card.goodRateDisplay, "—")
        XCTAssertEqual(card.soldCountDisplay, "—")
        XCTAssertEqual(card.avgShipHoursDisplay, "—")
        XCTAssertEqual(card.afterSaleRateDisplay, "—")
        XCTAssertEqual(card.scoreDisplay, "100")
    }

    func testSellerCardRatesFromBpsAndStale() throws {
        let json = """
        {
          "seller_id": 3,
          "credit_score": 105,
          "good_rate_bps": 9650,
          "sold_count": 40,
          "avg_ship_hours": 18.5,
          "after_sale_rate_bps": 420,
          "stale": true
        }
        """.data(using: .utf8)!
        let card = try decoder.decode(SellerCardMetrics.self, from: json)
        XCTAssertEqual(card.userId, 3)
        XCTAssertEqual(card.score, 105)
        XCTAssertEqual(card.goodRateDisplay, "96%") // 9650 bps → 96.5 → rounded
        XCTAssertEqual(card.soldCountDisplay, "40")
        XCTAssertEqual(card.avgShipHoursDisplay, "18 小时") // ≥10h uses whole hours
        XCTAssertEqual(card.afterSaleRateDisplay, "4%")
        XCTAssertTrue(card.stale)
    }

    func testSellerCardRateAsFraction() {
        let card = SellerCardMetrics(goodRate: 0.9, soldCount: 2, afterSaleRate: 0.05)
        XCTAssertEqual(card.goodRateDisplay, "90%")
        XCTAssertEqual(card.afterSaleRateDisplay, "5%")
    }

    // MARK: Countdown with server_time

    func testReviewRemainDaysUsesServerTimeOffset() {
        let deadline = Date(timeIntervalSince1970: 1_700_000_000 + 3 * 86_400)
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        let fetched = Date(timeIntervalSince1970: 1_700_000_000)
        // Local clock 1 day ahead of true; without offset would under-count.
        let localNow = Date(timeIntervalSince1970: 1_700_000_000 + 86_400)
        let days = ReviewCreditLogic.reviewRemainDays(
            deadline: deadline,
            serverRemainDays: nil,
            serverTime: serverTime,
            fetchedAtLocal: fetched,
            nowLocal: localNow
        )
        // elapsed 1d → serverNow = start+1d → remain 2d
        XCTAssertEqual(days, 2)
    }

    func testReviewRemainDaysFromCompletedAt() {
        let completed = Date(timeIntervalSince1970: 1_700_000_000)
        let serverTime = completed
        let fetched = completed
        let now = completed.addingTimeInterval(10 * 86_400)
        let days = ReviewCreditLogic.reviewRemainDays(
            deadline: nil,
            serverRemainDays: nil,
            serverTime: serverTime,
            fetchedAtLocal: fetched,
            nowLocal: now,
            completedAt: completed,
            windowDays: 15
        )
        XCTAssertEqual(days, 5)
    }

    func testPendingBannerText() {
        let t = ReviewCreditLogic.pendingBannerText(remainDays: 3)
        XCTAssertTrue(t.contains("还剩 3 天"))
        XCTAssertTrue(t.contains("待评价"))
    }

    func testBlockMessageDoesNotScare() {
        let msg = ReviewCreditLogic.blockMessage(score: 55, threshold: 60, action: "购买")
        XCTAssertTrue(msg.contains("55"))
        XCTAssertTrue(msg.contains("60"))
        XCTAssertTrue(msg.contains("购买"))
        XCTAssertTrue(msg.contains("完成履约"))
        XCTAssertFalse(msg.lowercased().contains("ban"))
    }

    func testSubmitGate() {
        XCTAssertEqual(
            ReviewCreditLogic.canSubmitReview(
                rating: .good, content: nil, imageCount: 0,
                isLoggedIn: false, isRealNamed: true, windowOpen: true
            ),
            .unauthorized
        )
        XCTAssertEqual(
            ReviewCreditLogic.canSubmitReview(
                rating: .good, content: nil, imageCount: 0,
                isLoggedIn: true, isRealNamed: false, windowOpen: true
            ),
            .realNameRequired
        )
        XCTAssertEqual(
            ReviewCreditLogic.canSubmitReview(
                rating: .good, content: nil, imageCount: 10,
                isLoggedIn: true, isRealNamed: true, windowOpen: true
            ),
            .contentRejected
        )
        XCTAssertNil(
            ReviewCreditLogic.canSubmitReview(
                rating: .neutral, content: "ok", imageCount: 2,
                isLoggedIn: true, isRealNamed: true, windowOpen: true
            )
        )
    }

    func testSubmitRequestBody() {
        let req = SubmitOrderReviewRequest(rating: .bad, content: "慢", imageIds: ["i1", "i2"])
        XCTAssertEqual(req.body["rating"] as? String, "bad")
        XCTAssertEqual(req.body["content"] as? String, "慢")
        XCTAssertEqual(req.body["image_ids"] as? [String], ["i1", "i2"])
    }

    // MARK: FakeAPIClient + ViewModels

    @MainActor
    func testFakeAPIClientSubmitAndMeCredit() async throws {
        let fake = FakeAPIClient()
        await fake.seedOrderReviews(
            OrderReviewsResponse(
                orderId: 7,
                items: [
                    OrderReview(
                        id: 1, orderId: 7, role: "buyer_to_seller",
                        arbitrationTag: true, status: "pending"
                    ),
                ],
                myPending: true
            )
        )
        await fake.seedMeCredit(MeCreditResponse(score: 88, monthPlusUsed: 3, logs: [
            CreditLogItem(id: 1, delta: 1, reasonCode: "complete_pay"),
        ]))

        let vm = ReviewSubmitViewModel(orderId: 7, client: fake)
        vm.setRating(.good)
        vm.setContent("准时")
        let ok = await vm.submit()
        XCTAssertTrue(ok)
        XCTAssertEqual(vm.submittedReview?.rating, "good")
        XCTAssertTrue(vm.submittedReview?.arbitrationTag == true)

        let creditVM = MeCreditViewModel(client: fake)
        await creditVM.load()
        XCTAssertEqual(creditVM.credit?.score, 88)
        XCTAssertEqual(creditVM.credit?.logs.count, 1)
    }

    @MainActor
    func testFakeAPIClientBadRequiresConfirm() async {
        let fake = FakeAPIClient()
        let vm = ReviewSubmitViewModel(orderId: 1, client: fake)
        vm.setRating(.bad)
        let first = await vm.submit()
        XCTAssertFalse(first)
        XCTAssertTrue(vm.needsBadConfirm)
        vm.confirmBad = true
        let second = await vm.submit()
        XCTAssertTrue(second)
    }

    func testFakeAPIClientCreditBlockError() async {
        let fake = FakeAPIClient()
        await fake.reset()
        let block = ReviewCreditLogic.creditBlock(fromCode: "credit_below_60", score: 55, action: "购买")
        XCTAssertEqual(block?.code, .creditBelow60)
        await fake.seedSellerCard(SellerCardMetrics(userId: 9, soldCount: 0), userId: 9)
        let card = try? await fake.sellerCard(userId: 9)
        XCTAssertEqual(card?.goodRateDisplay, "—")
    }

    func testScore80And60Allowed() {
        XCTAssertNil(ReviewCreditLogic.blockCode(forScore: 80))
        // 60 still triggers <80 (bid/lottery); purchase gate is separate (<60).
        XCTAssertEqual(ReviewCreditLogic.blockCode(forScore: 60), .creditBelow80)
        XCTAssertEqual(ReviewCreditLogic.blockCode(forScore: 79), .creditBelow80)
        XCTAssertEqual(ReviewCreditLogic.blockCode(forScore: 59), .creditBelow60)
        XCTAssertEqual(ReviewCreditErrorCode.creditBelow60.blockThreshold, 60)
    }
}
