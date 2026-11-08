import XCTest
@testable import VeloraCore

final class BrandVIPModelsTests: XCTestCase {
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

    private var sampleLevels: [BrandVIPLevelDef] {
        [
            BrandVIPLevelDef(level: 1, name: "银", minAmount: 0),
            BrandVIPLevelDef(level: 2, name: "金", minAmount: 500_000),
            BrandVIPLevelDef(
                level: 3,
                name: "钻",
                minAmount: 2_000_000,
                perks: BrandVIPPerks(lotteryEligible: true, lotteryWeight: 1.5, presaleWindowMinutes: 30)
            ),
        ]
    }

    // MARK: Defaults / copy

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(BrandVIPConfigDefaults.maxLevels, 6)
        XCTAssertFalse(BrandVIPConfigDefaults.allowForceDown)
        XCTAssertEqual(BrandVIPConfigDefaults.timezoneID, "Asia/Shanghai")
        XCTAssertEqual(BrandVIPConfigDefaults.importMaxRows, 5_000)
        XCTAssertEqual(BrandVIPConfigDefaults.basisChangeMinIntervalHours, 24)
        XCTAssertEqual(BrandVIPConfigDefaults.lotteryWeightMax, 2.0, accuracy: 1e-9)
        XCTAssertEqual(BrandVIPConfigDefaults.adjustReasonMinLen, 5)
        XCTAssertEqual(BrandVIPConfigDefaults.exampleThresholdsFen, [0, 500_000, 2_000_000])
        XCTAssertEqual(BrandVIPConfigDefaults.launchGateKey, "feature_flags.brand_vip")
    }

    func testSpendBasisCopy() {
        XCTAssertEqual(BrandVIPSpendBasis.allTime.shortLabel, "累计")
        XCTAssertEqual(BrandVIPSpendBasis.calendarYear.shortLabel, "本年度")
        XCTAssertEqual(BrandVIPSpendBasis.rolling12m.shortLabel, "近 12 个月")
        XCTAssertEqual(BrandVIPSpendBasis.allTime.spendPhrase, "累计消费")
        XCTAssertEqual(BrandVIPSpendBasis.calendarYear.spendPhrase, "本年度消费")
        XCTAssertEqual(BrandVIPSpendBasis.rolling12m.spendPhrase, "近 12 个月消费")
        XCTAssertEqual(BrandVIPSpendBasis.fallbackSpendPhrase, "本周期消费")
    }

    func testNoPlatformPaywallCopy() {
        XCTAssertEqual(BrandVIPCopy.nonMemberCTA, "下单即可成为会员")
        for phrase in BrandVIPCopy.forbiddenPlatformPaywallPhrases {
            XCTAssertFalse(BrandVIPCopy.nonMemberCTA.contains(phrase))
            XCTAssertFalse(phrase.isEmpty)
        }
    }

    // MARK: Take-high effective (§3 / §5.5)

    func testEffectiveLevelTakeHighTable() {
        // computed | override | effective
        XCTAssertEqual(BrandVIPLogic.effectiveLevel(computed: 2, override: nil), 2)
        XCTAssertEqual(BrandVIPLogic.effectiveLevel(computed: 1, override: 3), 3)
        XCTAssertEqual(BrandVIPLogic.effectiveLevel(computed: 4, override: 2), 4)
        XCTAssertEqual(BrandVIPLogic.effectiveLevel(computed: 0, override: 2), 2)
        XCTAssertEqual(BrandVIPLogic.effectiveLevel(computed: 3, override: 3), 3)
        XCTAssertEqual(BrandVIPLogic.effectiveLevel(computed: nil, override: nil), 0)
        XCTAssertEqual(BrandVIPLogic.effectiveLevel(computed: nil, override: 2), 2)
    }

    func testResolveSource() {
        XCTAssertEqual(BrandVIPLogic.resolveSource(computed: 2, override: nil), .computed)
        XCTAssertEqual(BrandVIPLogic.resolveSource(computed: 1, override: 3), .mixed)
        XCTAssertEqual(BrandVIPLogic.resolveSource(computed: 4, override: 2), .mixed)
        XCTAssertEqual(BrandVIPLogic.resolveSource(computed: 0, override: 2), .manual)
        XCTAssertEqual(
            BrandVIPLogic.resolveSource(computed: 0, override: 2, overrideOrigin: .importSource),
            .importSource
        )
        XCTAssertEqual(BrandVIPLogic.resolveSource(computed: 3, override: 3), .mixed)
    }

    func testPreviewAdjustUsesTakeHigh() {
        // Merchant proposes lower override — effective stays at computed (design §5.5 / allow_force_down=false UX).
        XCTAssertEqual(BrandVIPLogic.previewEffectiveAfterAdjust(computed: 4, proposedOverride: 2), 4)
        XCTAssertEqual(BrandVIPLogic.previewEffectiveAfterAdjust(computed: 1, proposedOverride: 3), 3)
    }

    // MARK: Levels / distance

    func testComputedLevelFromSpend() {
        XCTAssertEqual(BrandVIPLogic.computedLevel(spendFen: -1, levels: sampleLevels), 0)
        XCTAssertEqual(BrandVIPLogic.computedLevel(spendFen: 0, levels: sampleLevels), 1)
        XCTAssertEqual(BrandVIPLogic.computedLevel(spendFen: 499_999, levels: sampleLevels), 1)
        XCTAssertEqual(BrandVIPLogic.computedLevel(spendFen: 500_000, levels: sampleLevels), 2)
        XCTAssertEqual(BrandVIPLogic.computedLevel(spendFen: 2_000_000, levels: sampleLevels), 3)
    }

    func testDistanceToNextLevel() {
        let mid = BrandVIPLogic.distanceToNextLevel(spendFen: 100_000, effectiveLevel: 1, levels: sampleLevels)
        XCTAssertEqual(mid?.nextLevel, 2)
        XCTAssertEqual(mid?.nextName, "金")
        XCTAssertEqual(mid?.remainingFen, 400_000)
        XCTAssertTrue(mid!.progressCopy.contains("再消费"))
        XCTAssertTrue(mid!.progressCopy.contains("Lv.2"))

        let top = BrandVIPLogic.distanceToNextLevel(spendFen: 3_000_000, effectiveLevel: 3, levels: sampleLevels)
        XCTAssertNil(top)

        let alreadyPast = BrandVIPLogic.distanceToNextLevel(spendFen: 600_000, effectiveLevel: 1, levels: sampleLevels)
        XCTAssertEqual(alreadyPast?.remainingFen, 0)
    }

    func testValidateLevelsAndReason() {
        XCTAssertNil(BrandVIPLogic.validateLevels(sampleLevels))
        XCTAssertEqual(
            BrandVIPLogic.validateLevels([
                BrandVIPLevelDef(level: 1, name: "银", minAmount: 100),
                BrandVIPLevelDef(level: 2, name: "金", minAmount: 50),
            ]),
            .vipRuleLevelsNotMonotonic
        )
        XCTAssertEqual(
            BrandVIPLogic.validateLevels([
                BrandVIPLevelDef(level: 2, name: "金", minAmount: 0),
            ]),
            .vipRuleLevelsNotMonotonic
        )
        XCTAssertEqual(BrandVIPLogic.validateAdjustReason("abcd"), .reasonRequired)
        XCTAssertEqual(BrandVIPLogic.validateAdjustReason("跨店"), .reasonRequired)
        XCTAssertNil(BrandVIPLogic.validateAdjustReason("跨店会员迁移导入"))
        XCTAssertEqual(BrandVIPLogic.exampleTemplateLevels().map(\.minAmount), [0, 500_000, 2_000_000])
    }

    func testPerksWeightClamp() {
        let high = BrandVIPPerks(lotteryWeight: 9)
        XCTAssertEqual(high.resolvedLotteryWeight, 2.0, accuracy: 1e-9)
        let low = BrandVIPPerks(lotteryWeight: nil)
        XCTAssertEqual(low.resolvedLotteryWeight, 1.0, accuracy: 1e-9)
    }

    // MARK: Strip modes / decode

    func testGuestAndNonMemberStripModes() {
        XCTAssertEqual(BrandViewerVIP().stripMode, .hidden)

        let nonMember = BrandViewerVIP(
            level: 0,
            effectiveLevel: 0,
            isMember: false,
            rulesConfigured: true
        )
        XCTAssertEqual(nonMember.stripMode, .nonMemberCTA)
        XCTAssertEqual(nonMember.stripPrimaryText, BrandVIPCopy.nonMemberCTA)
        XCTAssertTrue(nonMember.shouldDisplay)

        let member = BrandViewerVIP(
            level: 2,
            levelName: "银卡",
            spendFen: 50_000,
            basis: .calendarYear,
            isMember: true,
            rulesConfigured: true
        )
        XCTAssertEqual(member.stripMode, .member)
        XCTAssertEqual(member.displayLine, "Lv.2 银卡 · 本年度消费 ¥500")
        XCTAssertTrue(member.displayLine.contains("本年度消费"))
        XCTAssertFalse(member.displayLine.contains("开通"))
    }

    func testDecodeViewerVIPOnStoreAggregate() throws {
        let json = """
        {
          "id": 42,
          "store_name": "示例品牌店",
          "viewer_vip": {
            "effective_level": 2,
            "level": 2,
            "level_name": "金",
            "spend_fen": 50000,
            "basis": "calendar_year",
            "computed_level": 1,
            "override_level": 2,
            "source": "mixed",
            "is_member": true,
            "rules_configured": true,
            "next_level": 3,
            "next_level_name": "钻",
            "next_min_amount_fen": 2000000,
            "distance_fen": 1950000
          }
        }
        """.data(using: .utf8)!
        let page = try decoder.decode(BrandStorePage.self, from: json)
        XCTAssertTrue(page.showsVipStrip)
        let vip = try XCTUnwrap(page.viewerVip)
        XCTAssertEqual(vip.resolvedEffectiveLevel, 2)
        XCTAssertEqual(vip.basis, .calendarYear)
        XCTAssertEqual(vip.source, .mixed)
        XCTAssertEqual(vip.stripMode, .member)
        XCTAssertTrue(vip.displayLine.contains("本年度消费"))
        XCTAssertEqual(vip.distance?.remainingFen, 1_950_000)
        XCTAssertTrue(vip.distance!.progressCopy.contains("Lv.3"))
    }

    func testDecodeNonMemberViewerVIP() throws {
        let json = """
        {
          "id": 7,
          "store_name": "新店",
          "viewer_vip": {
            "effective_level": 0,
            "is_member": false,
            "rules_configured": true,
            "basis": "all_time",
            "spend_fen": 0
          }
        }
        """.data(using: .utf8)!
        let page = try decoder.decode(BrandStorePage.self, from: json)
        XCTAssertTrue(page.showsVipStrip)
        XCTAssertEqual(page.viewerVip?.stripMode, .nonMemberCTA)
        XCTAssertEqual(page.viewerVip?.stripPrimaryText, "下单即可成为会员")
    }

    func testDecodeMeVIPEndpoint() throws {
        let json = """
        {
          "effective_level": 3,
          "level_name": "钻",
          "spend_fen": 2500000,
          "basis": "rolling_12m",
          "computed_level": 3,
          "override_level": null,
          "source": "computed",
          "is_member": true,
          "rules_configured": true,
          "computed_at": "2026-11-05T03:30:00Z"
        }
        """.data(using: .utf8)!
        let vip = try decoder.decode(BrandBuyerVIP.self, from: json)
        XCTAssertEqual(vip.resolvedEffectiveLevel, 3)
        XCTAssertEqual(vip.basis, .rolling12m)
        XCTAssertEqual(vip.source, .computed)
        XCTAssertTrue(vip.displayLine.contains("近 12 个月消费"))
        XCTAssertNotNil(vip.computedAt)
    }

    func testLegacyStubDecodeStillWorks() throws {
        let json = #"{"level":2,"level_name":"银卡","spend_fen":50000}"#.data(using: .utf8)!
        let vip = try decoder.decode(BrandViewerVIP.self, from: json)
        XCTAssertEqual(vip.stripMode, .member)
        XCTAssertTrue(vip.displayLine.contains("Lv.2"))
        XCTAssertTrue(vip.displayLine.contains("本周期消费"))
    }
}
