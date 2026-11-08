import XCTest
@testable import VeloraCore

final class ShipmentModelsTests: XCTestCase {
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

    // MARK: Defaults

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(ShipmentConfigDefaults.confirmDays, 10)
        XCTAssertEqual(ShipmentConfigDefaults.shipAuctionFixedHours, 72)
        XCTAssertEqual(ShipmentConfigDefaults.shipSpotLotteryHours, 48)
        XCTAssertEqual(ShipmentConfigDefaults.shipGraceHours, 24)
        XCTAssertEqual(ShipmentConfigDefaults.insuredThresholdFen, 200_000)
        XCTAssertEqual(ShipmentConfigDefaults.mergeShipMax, 20)
        XCTAssertEqual(ShipmentConfigDefaults.waybillImportMaxRows, 500)
        XCTAssertEqual(ShipmentConfigDefaults.confirmResumeMinSec, 3_600)
        XCTAssertEqual(ShipmentConfigDefaults.confirmDaySec, 10 * 86_400)
        XCTAssertEqual(ShipmentConfigDefaults.confirmSignProtectSec, 86_400)
        XCTAssertEqual(ShipmentConfigDefaults.featureFlagMerge, "order.merge_ship")
        XCTAssertEqual(ShipmentConfigDefaults.featureFlagMergePay, "order.merge_pay")
    }

    // MARK: Tracking normalize / decode

    func testNormalizeTrackingNoStripsSpacesAndUppercases() {
        XCTAssertEqual(ShipmentLogic.normalizeTrackingNo(" sf 123 456 "), "SF123456")
        XCTAssertEqual(ShipmentLogic.normalizeTrackingNo("jd888"), "JD888")
    }

    func testTrackingResultDecodeAndSortNewestFirst() throws {
        let json = """
        {
          "shipment_id": 9,
          "shipment_no": "S20240101",
          "carrier": "SF",
          "tracking_no": "SF1234567890",
          "status": "in_transit",
          "signed_at": null,
          "server_time": "2024-01-10T12:00:00Z",
          "track_synced_at": "2024-01-10T11:55:00Z",
          "member_count": 3,
          "member_cancelled_order_nos": ["P1"],
          "events": [
            {"occurred_at":"2024-01-09T08:00:00Z","location":"上海","description":"已揽收"},
            {"occurred_at":"2024-01-10T10:00:00Z","location":"杭州","description":"运输中"}
          ]
        }
        """.data(using: .utf8)!
        let result = try decoder.decode(TrackingResult.self, from: json)
        XCTAssertEqual(result.shipmentId, 9)
        XCTAssertEqual(result.status, .inTransit)
        XCTAssertEqual(result.memberCount, 3)
        XCTAssertEqual(result.memberCancelledOrderNos, ["P1"])
        XCTAssertEqual(result.eventsNewestFirst.first?.description, "运输中")
        XCTAssertEqual(result.eventsNewestFirst.last?.description, "已揽收")
        XCTAssertEqual(ShipmentLogic.mergeShipDisplayLabel(orderCount: 3), "合并发货，共 3 件")
    }

    func testShipmentStatusDoesNotRegressPastSigned() {
        XCTAssertFalse(ShipmentStatus.signed.canAdvance(to: .inTransit))
        XCTAssertEqual(
            ShipmentLogic.advanceShipmentStatus(from: .signed, reported: .inTransit),
            .signed
        )
        XCTAssertTrue(ShipmentStatus.exception.canAdvance(to: .inTransit))
    }

    // MARK: Confirm countdown with pause (§5.9)

    func testConfirmDeadlineFromShippedAtIsPlus10Days() {
        let shipped = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = ShipmentLogic.confirmDeadline(fromShippedAt: shipped)
        XCTAssertEqual(deadline.timeIntervalSince(shipped), TimeInterval(10 * 86_400))
    }

    func testSignOnDay3ExtendsConfirmWindow() {
        let shipped = Date(timeIntervalSince1970: 1_700_000_000)
        let current = ShipmentLogic.confirmDeadline(fromShippedAt: shipped)
        let signedAt = shipped.addingTimeInterval(3 * 86_400)
        let now = signedAt
        let result = ShipmentLogic.applySignedConfirmDeadline(
            currentDeadline: current,
            signedAt: signedAt,
            now: now
        )
        XCTAssertTrue(result.extended)
        XCTAssertEqual(
            result.confirmDeadline.timeIntervalSince(signedAt),
            TimeInterval(10 * 86_400)
        )
    }

    func testSignDoesNotShortenWhenRemainingUnder24h() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let current = now.addingTimeInterval(3_600) // 1h left
        let signedAt = now
        let result = ShipmentLogic.applySignedConfirmDeadline(
            currentDeadline: current,
            signedAt: signedAt,
            now: now
        )
        // signed+10d is later → still may extend; protect only against shortening
        XCTAssertTrue(result.confirmDeadline >= current)
        // When signed+10d > current, extended is true — that's allowed.
        XCTAssertEqual(result.confirmDeadline, signedAt.addingTimeInterval(TimeInterval(10 * 86_400)))
    }

    func testSignProtectKeepsShortWindowWhenSignedPlusWouldBeEarlier() {
        // Artificial: current far in future, signedAt in past so signed+10d < current and remain < 24h.
        let now = Date(timeIntervalSince1970: 3_000_000_000)
        let current = now.addingTimeInterval(3_600)
        let signedAt = now.addingTimeInterval(-20 * 86_400) // signed+10d is 10d ago ≪ current
        let result = ShipmentLogic.applySignedConfirmDeadline(
            currentDeadline: current,
            signedAt: signedAt,
            now: now
        )
        XCTAssertFalse(result.extended)
        XCTAssertEqual(result.confirmDeadline, current)
    }

    func testPauseAndResumeConfirmCountdown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let deadline = now.addingTimeInterval(2 * 86_400)
        let paused = ShipmentLogic.pauseConfirmDeadline(confirmDeadline: deadline, now: now)
        XCTAssertEqual(paused.confirmRemainingSec, 2 * 86_400)

        let resumeNow = now.addingTimeInterval(2 * 86_400) // after-sale took 2 days
        let resumed = ShipmentLogic.resumeConfirmDeadline(
            remainingSec: paused.confirmRemainingSec,
            now: resumeNow
        )
        XCTAssertEqual(resumed.appliedRemainingSec, 2 * 86_400)
        XCTAssertEqual(resumed.confirmDeadline.timeIntervalSince(resumeNow), TimeInterval(2 * 86_400))
    }

    func testResumeFloorsToOneHour() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let resumed = ShipmentLogic.resumeConfirmDeadline(remainingSec: 600, now: now)
        XCTAssertEqual(resumed.appliedRemainingSec, 3_600)
    }

    func testConfirmBlockedWhileAfterSaleProcessing() {
        let state = ConfirmPauseState(
            confirmDeadline: Date().addingTimeInterval(86_400),
            confirmPausedAt: Date(),
            confirmRemainingSec: 86_400,
            afterSaleStatus: "processing",
            status: "shipped"
        )
        XCTAssertFalse(ShipmentLogic.canConfirmReceipt(state))
        XCTAssertEqual(ShipmentLogic.confirmReceiptError(state), .afterSaleActive)
        XCTAssertTrue(ShipmentLogic.isConfirmPaused(state))
        XCTAssertEqual(
            ShipmentLogic.confirmRemainSeconds(
                state: state,
                serverTime: Date(),
                fetchedAtLocal: Date(),
                nowLocal: Date().addingTimeInterval(3_600)
            ),
            86_400
        )
    }

    func testConfirmRemainDecaysWhenNotPaused() {
        let fetched = Date(timeIntervalSince1970: 100)
        let server = Date(timeIntervalSince1970: 5_000)
        let deadline = server.addingTimeInterval(120)
        let state = ConfirmPauseState(
            confirmDeadline: deadline,
            afterSaleStatus: "none",
            status: "shipped"
        )
        let remain = ShipmentLogic.confirmRemainSeconds(
            state: state,
            serverTime: server,
            fetchedAtLocal: fetched,
            nowLocal: fetched.addingTimeInterval(30)
        )
        XCTAssertEqual(remain, 90)
    }

    // MARK: Insured threshold (ORD-09)

    func testInsuredRequiredAt2000Yuan() {
        XCTAssertFalse(ShipmentLogic.isInsuredRequired(amountFen: 199_999))
        XCTAssertTrue(ShipmentLogic.isInsuredRequired(amountFen: 200_000))
        XCTAssertTrue(ShipmentLogic.isInsuredRequired(amountFen: 250_000))
        XCTAssertEqual(ShipmentLogic.suggestedInsuredAmountFen(250_000), 250_000)
    }

    func testInsuredAmountCannotBeLowerThanDeal() {
        XCTAssertEqual(
            ShipmentLogic.validateInsuredAmount(dealAmountFen: 250_000, insuredAmountFen: 200_000, insuredRequired: true),
            .insuredAmountTooLow
        )
        XCTAssertNil(
            ShipmentLogic.validateInsuredAmount(dealAmountFen: 250_000, insuredAmountFen: 250_000, insuredRequired: true)
        )
        XCTAssertEqual(
            ShipmentLogic.validateInsuredAmount(dealAmountFen: 250_000, insuredAmountFen: nil, insuredRequired: true),
            .insuranceProofRequired
        )
    }

    func testShipRejectsHighValueWithoutInsurance() {
        let body = ShipOrderRequest(carrier: "SF", trackingNo: "SF1234567890")
        let err = ShipmentLogic.validateShipOrderRequest(
            body,
            status: "paid",
            evidenceReady: true,
            hasAddress: true,
            amountFen: 250_000,
            insuredRequired: true,
            hasInsuranceProof: false
        )
        XCTAssertEqual(err, .insuranceProofRequired)
    }

    // MARK: Merge-ship display / constraints (ORD-07)

    func testMergeShipCandidatesSameBuyerAddress() {
        let ok = [
            MergeShipCandidate(id: 1, buyerId: 9, addressHash: "h1", status: "paid", evidenceReady: true),
            MergeShipCandidate(id: 2, buyerId: 9, addressHash: "h1", status: "paid", evidenceReady: true),
        ]
        XCTAssertNil(ShipmentLogic.validateMergeShipCandidates(ok))

        let mismatch = [
            MergeShipCandidate(id: 1, buyerId: 9, addressHash: "h1", status: "paid", evidenceReady: true),
            MergeShipCandidate(id: 2, buyerId: 9, addressHash: "h2", status: "paid", evidenceReady: true),
        ]
        XCTAssertEqual(ShipmentLogic.validateMergeShipCandidates(mismatch), .addressMismatch)

        let inTransit = [
            MergeShipCandidate(id: 1, buyerId: 9, addressHash: "h1", status: "paid", evidenceReady: true, shipmentStatus: .inTransit),
            MergeShipCandidate(id: 2, buyerId: 9, addressHash: "h1", status: "paid", evidenceReady: true),
        ]
        XCTAssertEqual(ShipmentLogic.validateMergeShipCandidates(inTransit), .cannotMergeInTransit)
    }

    func testMergeShipMax20() {
        let many = (1...21).map {
            MergeShipCandidate(id: Int64($0), buyerId: 1, addressHash: "a", status: "paid", evidenceReady: true)
        }
        XCTAssertEqual(ShipmentLogic.validateMergeShipCandidates(many), .mergeLimitExceeded)
        XCTAssertEqual(ShipmentLogic.mergeShipDisplayLabel(orderCount: 3), "合并发货，共 3 件")
    }

    // MARK: Checkout group fee (ORD-10)

    func testMergedShippingFeeTakesMax() {
        XCTAssertEqual(ShipmentLogic.computeMergedShippingFeeFen([1_200, 800, 1_500]), 1_500)
        XCTAssertEqual(ShipmentLogic.computeMergedShippingFeeFen([]), 0)
        let totals = ShipmentLogic.computeCheckoutGroupBuyerTotal(
            goodsTotals: [10_000, 20_000],
            shippingFees: [1_200, 800]
        )
        XCTAssertEqual(totals.goodsTotal, 30_000)
        XCTAssertEqual(totals.mergedShippingFee, 1_200)
        XCTAssertEqual(totals.buyerTotal, 31_200)
    }

    func testCheckoutGroupRejectsNonFixedAndNeedsAddress() {
        XCTAssertEqual(
            ShipmentLogic.validateCheckoutGroupCreate(
                listingIds: [1, 2],
                addressId: 10,
                tradeTypes: ["fixed", "auction"]
            ),
            .forbidden
        )
        XCTAssertEqual(
            ShipmentLogic.validateCheckoutGroupCreate(listingIds: [1, 2], addressId: nil),
            .addressRequired
        )
        XCTAssertNil(
            ShipmentLogic.validateCheckoutGroupCreate(
                listingIds: [1, 2],
                addressId: 10,
                tradeTypes: ["fixed", "fixed"]
            )
        )
        XCTAssertEqual(
            ShipmentLogic.validateCheckoutGroupCreate(
                listingIds: [1, 2],
                addressId: 10,
                mergePayEnabled: false
            ),
            .featureDisabled
        )
    }

    func testCheckoutGroupDecode() throws {
        let json = """
        {
          "id": 7,
          "buyer_id": 1,
          "seller_id": 2,
          "status": "pending_payment",
          "merged_shipping_fee": 1500,
          "goods_total": 30000,
          "buyer_total": 31500,
          "parent_order_id": 99,
          "child_order_ids": [100, 101]
        }
        """.data(using: .utf8)!
        let group = try decoder.decode(CheckoutGroup.self, from: json)
        XCTAssertEqual(group.mergedShippingFee, 1_500)
        XCTAssertEqual(group.buyerTotal, 31_500)
        XCTAssertEqual(group.childOrderIds, [100, 101])
        XCTAssertEqual(group.status, .pendingPayment)
    }

    // MARK: Overdue cancel-unshipped

    func testCancelUnshippedOnlyAfterGrace() {
        let deadline = Date(timeIntervalSince1970: 1_000_000)
        let withinGrace = deadline.addingTimeInterval(12 * 3_600)
        XCTAssertTrue(ShipmentLogic.isWithinShipGrace(shipDeadline: deadline, now: withinGrace))
        XCTAssertFalse(ShipmentLogic.canCancelUnshipped(status: "paid", shipDeadline: deadline, now: withinGrace))
        XCTAssertEqual(
            ShipmentLogic.cancelUnshippedError(status: "paid", shipDeadline: deadline, now: withinGrace),
            .shipNotOverdue
        )

        let afterGrace = deadline.addingTimeInterval(24 * 3_600)
        XCTAssertTrue(ShipmentLogic.canCancelUnshipped(status: "paid", shipDeadline: deadline, now: afterGrace))
        XCTAssertNil(ShipmentLogic.cancelUnshippedError(status: "paid", shipDeadline: deadline, now: afterGrace))
        XCTAssertFalse(ShipmentLogic.canCancelUnshipped(status: "shipped", shipDeadline: deadline, now: afterGrace))
    }

    // MARK: Error codes / copy

    func testShippingErrorCodesIncludeDesignSet() {
        let codes = Set(ShippingErrorCode.allCases.map(\.rawValue))
        for needed in [
            "evidence_required", "insurance_proof_required", "after_sale_active",
            "ship_not_overdue", "address_mismatch", "already_shipped", "carrier_unknown",
            "checkout_stale",
        ] {
            XCTAssertTrue(codes.contains(needed), needed)
        }
        XCTAssertFalse(ShippingErrorCode.afterSaleActive.fallbackMessage.isEmpty)
        XCTAssertTrue(ShipmentCopy.confirmPausedHint.contains("售后"))
        XCTAssertTrue(ShipmentCopy.trackingEmpty.contains("暂无轨迹"))
    }

    func testShipOrderResultDecode() throws {
        let json = """
        {
          "shipment_no": "SHP1",
          "shipment_id": 3,
          "confirm_deadline": "2024-01-20T00:00:00Z",
          "insured": true,
          "insured_amount": 250000,
          "status": "shipped"
        }
        """.data(using: .utf8)!
        let result = try decoder.decode(ShipOrderResult.self, from: json)
        XCTAssertEqual(result.shipmentNo, "SHP1")
        XCTAssertTrue(result.insured)
        XCTAssertEqual(result.insuredAmount, 250_000)
        XCTAssertNotNil(result.confirmDeadline)
    }
}
