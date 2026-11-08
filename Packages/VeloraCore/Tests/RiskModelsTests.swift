import XCTest
@testable import VeloraCore

final class RiskModelsTests: XCTestCase {
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

    // MARK: Config (design §3)

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(RiskConfigDefaults.offlineFineFirstCents, 20_000)
        XCTAssertEqual(RiskConfigDefaults.offlineFineRepeatRateBps, 1_000)
        XCTAssertEqual(RiskConfigDefaults.offlineFineRepeatMinCents, 50_000)
        XCTAssertEqual(RiskConfigDefaults.offlineFineRepeatMaxCents, 500_000)
        XCTAssertEqual(RiskConfigDefaults.bountyRateBps, 5_000)
        XCTAssertEqual(RiskConfigDefaults.launchGateBountyPayoutKey, "launch_gate.bounty_payout")
        XCTAssertFalse(RiskConfigDefaults.launchGateBountyPayoutDefault)
        XCTAssertFalse(RiskConfigDefaults.hideBlockedListingsDefault)
        XCTAssertEqual(RiskConfigDefaults.relatedStrongConfidence, 70)
        XCTAssertEqual(RiskConfigDefaults.evidencePhotosMax, 9)
        XCTAssertEqual(RiskConfigDefaults.fakeReportRejectThreshold, 3)
        XCTAssertEqual(RiskConfigDefaults.notifyCodePenalty, "N-27")
        XCTAssertEqual(RiskConfigDefaults.creditDeltaInduceOffline, -15)
        XCTAssertEqual(RiskConfigDefaults.searchDownrankDaysFirst, 7)
        XCTAssertEqual(RiskConfigDefaults.banPublishDaysRepeat, 30)
    }

    // MARK: Report reasons / targets

    func testReportReasonsAndTargets() {
        XCTAssertEqual(ReportReason.induceOffline.displayLabel, "诱导线下交易")
        XCTAssertEqual(ReportReason.normalize("induce_pay"), .induceOffline)
        XCTAssertEqual(ReportReason.normalize("广告"), .spam)
        XCTAssertEqual(ReportTargetType.normalize("seller_offline"), .sellerOffline)
        XCTAssertEqual(ReportTargetType.normalize("lot"), .listing)
        XCTAssertTrue(ReportTargetType.sellerOffline.isBountyTarget)
        XCTAssertEqual(ReportTargetType.sellerOffline.selectableReasons, [.induceOffline])
        XCTAssertTrue(ReportTargetType.listing.selectableReasons.contains(.fake))
        XCTAssertFalse(ReportTargetType.listing.selectableReasons.contains(.induceOffline))
    }

    func testBountyStatusCopy() {
        XCTAssertEqual(BountyPayoutStatus.held.displayLabel, RiskCopy.bountyProgressHeld)
        XCTAssertEqual(BountyPayoutStatus.paid.displayLabel, RiskCopy.bountyProgressPaid)
        XCTAssertEqual(BountyPayoutStatus.normalize("awaiting_finance"), .held)
        XCTAssertEqual(ReportStatus.open.displayLabel, RiskCopy.bountyProgressReviewing)
        XCTAssertEqual(
            RiskLogic.bountyProgressLabel(status: .open, bountyStatus: nil),
            RiskCopy.bountyProgressReviewing
        )
        XCTAssertEqual(
            RiskLogic.bountyProgressLabel(status: .confirmed, bountyStatus: .held),
            RiskCopy.bountyProgressHeld
        )
        XCTAssertEqual(
            RiskLogic.bountyProgressLabel(status: .confirmed, bountyStatus: .paid),
            RiskCopy.bountyProgressPaid
        )
        XCTAssertEqual(
            RiskLogic.bountyProgressLabel(status: .rejected, bountyStatus: nil, rejectReason: "证据不足"),
            "证据不足"
        )
        XCTAssertEqual(RiskCopy.reportSuccess, "我们将在 5 个工作日内处理")
        XCTAssertEqual(RiskCopy.bountyHeld, "查实，奖励将在财务开闸后到账")
        XCTAssertEqual(RiskCopy.blockSuccess, "已无法收到对方私信，对方也不能再对你的商品出价")
        XCTAssertEqual(RiskCopy.blockListEmpty, "还没有拉黑任何人")
        XCTAssertEqual(RiskCopy.bidNotAllowed, "当前账号无法对该拍品出价")
        XCTAssertEqual(RiskCopy.penaltyExpired, "限制已解除")
        XCTAssertTrue(RiskCopy.penaltyNotice(reason: "降权", windowText: "7天").contains("申诉请回复工单"))
    }

    // MARK: Fine / bounty math (§5.1)

    func testOfflineFineLadderAndBountySplit() {
        XCTAssertEqual(RiskLogic.offlineFineCents(priorConfirmedCount: 0, dealPriceCents: 2_500_00), 20_000)
        // 10% of 2500 = 250, clamp to min 500
        XCTAssertEqual(RiskLogic.offlineFineCents(priorConfirmedCount: 1, dealPriceCents: 250_000), 50_000)
        // 10% of 8000 = 800 within [500, 5000]
        XCTAssertEqual(RiskLogic.offlineFineCents(priorConfirmedCount: 1, dealPriceCents: 800_000), 80_000)
        // 10% of 80000 = 8000 clamp max 5000
        XCTAssertEqual(RiskLogic.offlineFineCents(priorConfirmedCount: 1, dealPriceCents: 8_000_000), 500_000)
        XCTAssertNil(RiskLogic.offlineFineCents(priorConfirmedCount: 2, dealPriceCents: 100_000))

        let split = RiskLogic.fineSplit(fineCents: 20_000)
        XCTAssertEqual(split.bountyCents, 10_000)
        XCTAssertEqual(split.platformFeeCents, 10_000)
        XCTAssertEqual(split.platformFeeCents + split.bountyCents, 20_000)
    }

    // MARK: Gates / errors

    func testReportAndBlockGates() {
        XCTAssertEqual(
            RiskLogic.createReportGate(
                targetType: .listing,
                reason: .spam,
                evidenceCount: 0,
                attachConversation: false,
                orderId: nil,
                isLoggedIn: false,
                isRealNamed: false,
                accountFrozen: false
            ),
            .unauthenticated
        )
        XCTAssertEqual(
            RiskLogic.createReportGate(
                targetType: .sellerOffline,
                reason: .induceOffline,
                evidenceCount: 0,
                attachConversation: false,
                orderId: 1,
                isLoggedIn: true,
                isRealNamed: true,
                accountFrozen: false,
                isOrderBuyer: true
            ),
            .evidenceRequired
        )
        XCTAssertNil(
            RiskLogic.createReportGate(
                targetType: .sellerOffline,
                reason: .induceOffline,
                evidenceCount: 0,
                attachConversation: true,
                orderId: 9,
                isLoggedIn: true,
                isRealNamed: true,
                accountFrozen: false,
                isOrderBuyer: true
            )
        )
        XCTAssertEqual(
            RiskLogic.createReportGate(
                targetType: .sellerOffline,
                reason: .induceOffline,
                evidenceCount: 1,
                attachConversation: false,
                orderId: 1,
                isLoggedIn: true,
                isRealNamed: false,
                accountFrozen: false
            ),
            .realNameRequired
        )
        XCTAssertEqual(
            RiskLogic.createReportGate(
                targetType: .sellerOffline,
                reason: .induceOffline,
                evidenceCount: 1,
                attachConversation: false,
                orderId: 1,
                isLoggedIn: true,
                isRealNamed: true,
                accountFrozen: false,
                isOrderBuyer: false
            ),
            .bountyNotBuyer
        )
        XCTAssertTrue(
            RiskLogic.canSubmitReport(
                targetType: .user,
                reason: .abuse,
                evidenceCount: 0,
                attachConversation: false,
                orderId: nil,
                isLoggedIn: true,
                isRealNamed: false,
                accountFrozen: false
            )
        )
        XCTAssertEqual(RiskLogic.createBlockGate(blockerId: 1, blockedId: 1, isLoggedIn: true), .cannotBlockSelf)
        XCTAssertNil(RiskLogic.createBlockGate(blockerId: 1, blockedId: 2, isLoggedIn: true))
    }

    func testErrorCodeNormalizeAndBidCopy() {
        XCTAssertEqual(RiskErrorCode.normalize("related_account_forbidden"), .relatedAccountBid)
        XCTAssertEqual(RiskErrorCode.normalize("blocked_by_seller"), .blockedBySeller)
        XCTAssertEqual(RiskErrorCode.normalize("bid_not_allowed"), .bidNotAllowed)
        XCTAssertTrue(RiskErrorCode.bidNotAllowed.isBidDenied)
        XCTAssertTrue(RiskErrorCode.blockedBySeller.isBidDenied)
        XCTAssertEqual(RiskErrorCode.blockedBySeller.fallbackMessage, RiskCopy.bidNotAllowed)
        XCTAssertEqual(RiskLogic.bidDenyMessage(code: "related_account_bid"), RiskCopy.bidNotAllowed)
        XCTAssertFalse(RiskCopy.bidNotAllowed.contains("关联"))
        XCTAssertEqual(ContentReviewRejectReason.contact.userMessage, "含违规信息，请修改：站外联系方式")
        XCTAssertEqual(PenaltyType.normalize("ban_publish"), .banPublishNdays)
    }

    // MARK: Decode

    func testReportAndBlockDecode() throws {
        let reportJSON = """
        {
          "id": 11,
          "reporter_id": 2,
          "target_type": "seller_offline",
          "target_id": 7,
          "order_id": 99,
          "reason": "induce_offline",
          "evidence_urls": ["https://cdn.example/a.jpg"],
          "status": "confirmed",
          "reward_cents": 10000,
          "bounty_status": "held",
          "created_at": "2026-11-05T01:00:00Z"
        }
        """.data(using: .utf8)!
        let report = try decoder.decode(Report.self, from: reportJSON)
        XCTAssertEqual(report.targetType, .sellerOffline)
        XCTAssertEqual(report.status, .confirmed)
        XCTAssertEqual(report.rewardCents, 10_000)
        XCTAssertEqual(report.bountyStatus, .held)
        XCTAssertEqual(report.progressLabel, RiskCopy.bountyProgressHeld)
        XCTAssertEqual(report.rewardDisplayCents, 10_000)

        let blockJSON = """
        {
          "items": [
            {
              "blocker_id": 1,
              "blocked_id": 8,
              "created_at": "2026-11-05T02:00:00Z",
              "blocked_user": {"id": 8, "nickname": "卖家甲", "avatar": ""}
            }
          ],
          "next_cursor": "c2"
        }
        """.data(using: .utf8)!
        let page = try decoder.decode(UserBlockPage.self, from: blockJSON)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].blockedUser?.displayName, "卖家甲")
        XCTAssertEqual(page.nextCursor, "c2")
    }

    func testCreateReportRequestBody() {
        let req = CreateReportRequest(
            targetType: .sellerOffline,
            targetId: 7,
            reason: .induceOffline,
            evidenceUrls: ["u1"],
            orderId: 99,
            attachConversation: true
        )
        XCTAssertEqual(req.body["target_type"] as? String, "seller_offline")
        XCTAssertEqual(req.body["order_id"] as? Int64, 99)
        XCTAssertEqual(req.body["attach_conversation"] as? Bool, true)
        XCTAssertEqual((req.body["evidence"] as? [String])?.first, "u1")
    }

    func testRelatedEdgeHelpers() {
        XCTAssertTrue(
            RiskLogic.relatedStrongOverlap(
                left: [("id_no", 100), ("ip", 40)],
                right: [("id_no", 100)]
            )
        )
        XCTAssertTrue(
            RiskLogic.isWeakIPOnly(edges: [("ip", 40)])
        )
        XCTAssertFalse(
            RiskLogic.isWeakIPOnly(edges: [("ip", 40), ("device", 80)])
        )
    }
}
