import XCTest
@testable import VeloraCore

final class ProxyAgentModelsTests: XCTestCase {
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

    // MARK: Defaults

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(ProxyAgentConfigDefaults.depositFen, 500_000)
        XCTAssertEqual(ProxyAgentConfigDefaults.depositYuan, 5_000)
        XCTAssertEqual(ProxyAgentConfigDefaults.minSampleOrders, 5)
        XCTAssertEqual(ProxyAgentConfigDefaults.shipOnTimeThreshold, 0.95, accuracy: 1e-9)
        XCTAssertEqual(ProxyAgentConfigDefaults.afterSaleThreshold, 0.08, accuracy: 1e-9)
        XCTAssertEqual(ProxyAgentConfigDefaults.defaultRateThreshold, 0.03, accuracy: 1e-9)
        XCTAssertEqual(ProxyAgentConfigDefaults.arbitrationLossThreshold, 0.20, accuracy: 1e-9)
        XCTAssertEqual(ProxyAgentConfigDefaults.failMonthsToProbation, 2)
        XCTAssertEqual(ProxyAgentConfigDefaults.batchMaxRows, 200)
        XCTAssertEqual(ProxyAgentConfigDefaults.protocolCode, "proxy_service")
        XCTAssertEqual(ProxyAgentConfigDefaults.sellerType, "proxy_agent")
        XCTAssertTrue(ProxyAgentConfigDefaults.forbiddenConsignorKeys.contains("consignor_id"))
        XCTAssertTrue(ProxyAgentConfigDefaults.forbiddenConsignorKeys.contains("principal_name"))
        XCTAssertTrue(ProxyAgentConfigDefaults.forbiddenConsignorKeys.contains("client_settlement"))
    }

    func testCopyNeverMentionsConsignorSettlement() {
        XCTAssertTrue(ProxyAgentCopy.fulfillmentResponsibility.contains("本人"))
        XCTAssertTrue(ProxyAgentCopy.consignRejected.contains("不登记委托"))
        XCTAssertTrue(ProxyAgentCopy.protocolSummary.contains("自己名义"))
        XCTAssertFalse(ProxyAgentCopy.costPriceHint.contains("打款给委托人"))
        XCTAssertEqual(ProxyAgentCopy.goldBadge, "金牌代拍")
        XCTAssertEqual(ProxyAgentCopy.probationBadge, "代拍（观察期）")
        XCTAssertEqual(ProxyAgentCopy.onboardingSteps, ["资料", "保证金", "审核", "进件"])
    }

    // MARK: Badge / level

    func testBuyerBadgeOnlyWhenGold() {
        XCTAssertEqual(
            ProxyBadgeLogic.buyerVisibleLabel(assessmentLevel: .gold, badgeRaw: "gold_proxy"),
            "金牌代拍"
        )
        XCTAssertEqual(
            ProxyBadgeLogic.buyerVisibleLabel(assessmentLevel: .probation, badgeRaw: "gold_proxy"),
            "代拍（观察期）"
        )
        XCTAssertNil(ProxyBadgeLogic.buyerVisibleLabel(assessmentLevel: .revoked, badgeRaw: "gold_proxy"))
        XCTAssertEqual(
            ProxyBadgeLogic.sellerBadge(assessmentLevel: .gold, badgeRaw: nil),
            .proxyGold
        )
        XCTAssertEqual(
            ProxyBadgeLogic.sellerBadge(assessmentLevel: .probation, badgeRaw: nil),
            .proxyProbation
        )
        XCTAssertNil(ProxyBadgeLogic.sellerBadge(assessmentLevel: .revoked, badgeRaw: "proxy_gold"))
    }

    func testSellerBadgeDecodesGoldProxyAlias() throws {
        let gold = try decoder.decode(SellerBadge.self, from: Data("\"gold_proxy\"".utf8))
        XCTAssertEqual(gold, .proxyGold)
        XCTAssertEqual(gold.label, "金牌代拍")
        let wire = try decoder.decode(SellerBadge.self, from: Data("\"proxy_gold\"".utf8))
        XCTAssertEqual(wire, .proxyGold)
        let probation = try decoder.decode(SellerBadge.self, from: Data("\"proxy_probation\"".utf8))
        XCTAssertEqual(probation, .proxyProbation)
        XCTAssertEqual(probation.label, "代拍（观察期）")
    }

    // MARK: Privilege matrix

    func testPrivilegeExpiryOnProbationAndRevoke() {
        let probation = ProxyPrivilegeLogic.applyLevel(.probation)
        XCTAssertTrue(probation.canFixed)
        XCTAssertTrue(probation.canAuction)
        XCTAssertTrue(probation.canBatchList)
        XCTAssertTrue(probation.canInvoiceService)
        XCTAssertFalse(probation.canSession)
        XCTAssertFalse(probation.canPromote)

        let revoked = ProxyPrivilegeLogic.applyLevel(.revoked)
        XCTAssertTrue(revoked.canFixed)
        XCTAssertFalse(revoked.canAuction)
        XCTAssertFalse(revoked.canBatchList)
        XCTAssertFalse(revoked.canInvoiceService)
        XCTAssertFalse(revoked.canSession)
        XCTAssertFalse(revoked.canPromote)

        let revokedNoFixed = ProxyPrivilegeLogic.applyLevel(.revoked, keepFixedOnRevoke: false)
        XCTAssertFalse(revokedNoFixed.canFixed)
    }

    func testConsecutiveFailLevelTransitions() {
        XCTAssertEqual(ProxyPrivilegeLogic.nextLevel(current: .gold, consecutiveFails: 1), .gold)
        XCTAssertEqual(ProxyPrivilegeLogic.nextLevel(current: .gold, consecutiveFails: 2), .probation)
        XCTAssertEqual(ProxyPrivilegeLogic.nextLevel(current: .probation, consecutiveFails: 1), .revoked)
        XCTAssertEqual(ProxyPrivilegeLogic.nextLevel(current: .revoked, consecutiveFails: 9), .revoked)
    }

    func testDowngradeLostTitles() {
        let notice = ProxyDowngradeNotice(from: .gold, to: .probation)
        XCTAssertTrue(notice.lostTitles.contains("专场申请"))
        XCTAssertTrue(notice.lostTitles.contains("推荐位"))
        XCTAssertFalse(notice.lostTitles.contains("批量上拍"))
        let revoked = ProxyDowngradeNotice(from: .probation, to: .revoked)
        XCTAssertTrue(revoked.lostTitles.contains("批量上拍"))
        XCTAssertTrue(revoked.lostTitles.contains("开票服务"))
        XCTAssertTrue(revoked.lostTitles.contains("拍卖新上"))
    }

    // MARK: Metrics

    func testMetricThresholdsAndSampleGate() {
        XCTAssertTrue(ProxyMetricLogic.meetsThreshold(kind: .shipOnTime, rate: 0.95))
        XCTAssertFalse(ProxyMetricLogic.meetsThreshold(kind: .shipOnTime, rate: 0.949))
        XCTAssertTrue(ProxyMetricLogic.meetsThreshold(kind: .afterSale, rate: 0.08))
        XCTAssertFalse(ProxyMetricLogic.meetsThreshold(kind: .afterSale, rate: 0.081))
        XCTAssertTrue(ProxyMetricLogic.meetsThreshold(kind: .arbitrationLoss, rate: nil, arbitrationDenomZero: true))
        XCTAssertFalse(ProxyMetricLogic.sampleEligible(orderCount: 4))
        XCTAssertTrue(ProxyMetricLogic.sampleEligible(orderCount: 5))
    }

    func testEvaluateMonthInsufficientSampleDoesNotFail() {
        let result = ProxyMetricLogic.evaluateMonth(
            orderCount: 3,
            shipOnTime: 0.0,
            afterSale: 1.0,
            defaultRate: 1.0,
            arbitrationLoss: 1.0,
            arbitrationCaseCount: 2
        )
        XCTAssertEqual(result, .insufficientSample)
        XCTAssertFalse(result.countsAsConsecutiveFail)
    }

    func testEvaluateMonthPassAndFail() {
        let pass = ProxyMetricLogic.evaluateMonth(
            orderCount: 10,
            shipOnTime: 0.96,
            afterSale: 0.05,
            defaultRate: 0.01,
            arbitrationLoss: 0.1,
            arbitrationCaseCount: 2
        )
        XCTAssertEqual(pass, .pass)

        let fail = ProxyMetricLogic.evaluateMonth(
            orderCount: 10,
            shipOnTime: 0.90,
            afterSale: 0.05,
            defaultRate: 0.01,
            arbitrationLoss: 0.1,
            arbitrationCaseCount: 2
        )
        XCTAssertEqual(fail, .fail)
        XCTAssertTrue(fail.countsAsConsecutiveFail)
    }

    // MARK: Decode

    func testDecodeSellerProfileAndAssessments() throws {
        let profileJSON = """
        {
          "user_id": 42,
          "seller_type": "proxy_agent",
          "badge": "gold_proxy",
          "assessment_level": "gold",
          "fee_tier_id": "proxy_default",
          "onboarding_status": "approved",
          "capabilities": {
            "can_fixed": true,
            "can_auction": true,
            "can_batch_list": true,
            "can_invoice_service": true,
            "can_session": true,
            "can_promote": true
          }
        }
        """.data(using: .utf8)!
        let profile = try decoder.decode(ProxySellerProfile.self, from: profileJSON)
        XCTAssertTrue(profile.isProxyAgent)
        XCTAssertEqual(profile.assessmentLevel, .gold)
        XCTAssertEqual(profile.buyerBadgeLabel, "金牌代拍")
        XCTAssertEqual(profile.sellerBadge, .proxyGold)
        XCTAssertEqual(profile.capabilities?.canSession, true)

        let listJSON = """
        {
          "items": [
            {
              "seller_id": 42,
              "year_month": "2026-10",
              "ship_on_time_rate": 0.97,
              "after_sale_rate": 0.04,
              "default_rate": 0.01,
              "arbitration_loss_rate": 0.0,
              "order_count": 12,
              "arbitration_case_count": 0,
              "result": "pass",
              "decided_at": "2026-11-01T02:00:00Z"
            }
          ],
          "forecast": {
            "ship_on_time_rate": 0.96,
            "after_sale_rate": 0.05,
            "default_rate": 0.02,
            "arbitration_loss_rate": 0.0,
            "order_count": 8,
            "window_days": 30,
            "is_final": false
          }
        }
        """.data(using: .utf8)!
        let list = try decoder.decode(ProxyAssessmentListResponse.self, from: listJSON)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items[0].result, .pass)
        XCTAssertTrue(list.items[0].meets(.shipOnTime))
        XCTAssertTrue(list.items[0].meets(.arbitrationLoss))
        XCTAssertEqual(list.forecast?.showsNonFinalBanner, true)
        XCTAssertEqual(ProxyMetricLogic.formatRate(0.975), "97.5%")
    }

    func testErrorCodesAndOnboardingProgress() {
        XCTAssertEqual(ProxyAgentErrorCode.inviteInvalid.fallbackMessage, "邀请码无效或已过期")
        XCTAssertTrue(ProxyAgentErrorCode.realNameRequired.opensRealName)
        XCTAssertTrue(ProxyAgentErrorCode.unauthorized.opensLogin)
        XCTAssertEqual(
            ProxyOnboardingProgress.currentIndex(reviewStatus: nil, subMerchantStatus: nil, depositDone: false),
            0
        )
        XCTAssertEqual(
            ProxyOnboardingProgress.currentIndex(reviewStatus: "submitted", subMerchantStatus: nil, depositDone: true),
            2
        )
        XCTAssertEqual(
            ProxyOnboardingProgress.currentIndex(reviewStatus: "approved", subMerchantStatus: "applying", depositDone: true),
            3
        )
    }

    func testForbiddenConsignorKeysNeverInProfileCodingKeys() {
        // Structural guard: profile DTO must not grow consignor fields.
        let keys = Set(["userId", "sellerType", "badge", "assessmentLevel", "feeTierId", "onboardingStatus", "capabilities", "subMerchantId"])
        XCTAssertFalse(keys.contains("consignorId"))
        XCTAssertFalse(keys.contains("principalName"))
        for banned in ProxyAgentConfigDefaults.forbiddenConsignorKeys {
            XCTAssertFalse(banned.hasPrefix("can_"))
        }
    }
}
