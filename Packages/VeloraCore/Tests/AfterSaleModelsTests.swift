import XCTest
@testable import VeloraCore

final class AfterSaleModelsTests: XCTestCase {
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
        XCTAssertEqual(AfterSaleConfigDefaults.sellerRespondHours, 48)
        XCTAssertEqual(AfterSaleConfigDefaults.appearanceWindowHours, 48)
        XCTAssertEqual(AfterSaleConfigDefaults.evidenceHours, 72)
        XCTAssertEqual(AfterSaleConfigDefaults.decideWorkdays, 5)
        XCTAssertEqual(AfterSaleConfigDefaults.appealHours, 72)
        XCTAssertEqual(AfterSaleConfigDefaults.returnTrackingDays, 7)
        XCTAssertEqual(AfterSaleConfigDefaults.appearanceUnboxPhotosMin, 3)
        XCTAssertEqual(AfterSaleConfigDefaults.evidencePhotosMax, 9)
        XCTAssertEqual(AfterSaleConfigDefaults.reasonMinLength, 20)
        XCTAssertEqual(AfterSaleConfigDefaults.featureFlagSmallCourt, "small_court")
        XCTAssertEqual(AfterSaleConfigDefaults.penaltyObligeeBp, 7_000)
        XCTAssertEqual(AfterSaleConfigDefaults.penaltyPlatformBp, 3_000)
        XCTAssertEqual(AfterSaleConfigDefaults.meEntryKey, "after_sale")
        XCTAssertTrue(AfterSaleConfigDefaults.calendarSkipWeekends)
    }

    // MARK: Types / claims

    func testTypesExcludeNoReasonReturn() {
        XCTAssertFalse(AfterSaleType.allCases.map(\.rawValue).contains("no_reason_return"))
        XCTAssertEqual(AfterSaleLogic.selectableTypes().count, 5)
        XCTAssertTrue(AfterSaleType.notAsDescribed.isAppearance)
        XCTAssertTrue(AfterSaleType.transitDamage.isAppearance)
        XCTAssertFalse(AfterSaleType.suspectedFake.isAppearance)
        XCTAssertEqual(AfterSaleType.normalize("condition"), .notAsDescribed)
        XCTAssertEqual(AfterSaleClaim.normalize("return_and_refund"), .returnRefund)
    }

    func testCaseAndArbitrationStatusLabels() {
        XCTAssertEqual(AfterSaleCaseStatus.requested.displayLabel, "待卖家处理")
        XCTAssertEqual(AfterSaleCaseStatus.normalize("timeout_agreed"), .agreed)
        XCTAssertTrue(AfterSaleCaseStatus.requested.isActive)
        XCTAssertTrue(AfterSaleCaseStatus.closed.isTerminal)
        XCTAssertEqual(ArbitrationStatus.evidence.displayLabel, "举证中")
        XCTAssertEqual(ArbitrationStatus.normalize("appeal"), .appealReview)
        XCTAssertTrue(ArbitrationStatus.evidence.allowsPartyEvidence)
        XCTAssertFalse(ArbitrationStatus.deciding.allowsPartyEvidence)
        XCTAssertEqual(RulingTemplate.hiddenFlaw.displayLabel, "藏匿瑕疵")
        XCTAssertEqual(RulingTemplate.normalize("conceal"), .hiddenFlaw)
    }

    // MARK: Windows / create gate (AFS-04)

    func testAppearanceWindow48h() {
        let signed = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(AfterSaleLogic.appearanceWindowOpen(
            signedAt: signed,
            now: signed.addingTimeInterval(24 * 3600)
        ))
        XCTAssertFalse(AfterSaleLogic.appearanceWindowOpen(
            signedAt: signed,
            now: signed.addingTimeInterval(49 * 3600)
        ))
        XCTAssertFalse(AfterSaleLogic.appearanceWindowOpen(signedAt: nil, now: Date()))
    }

    func testSuspectedFakeAllowedAfterAppearanceWindow() {
        let signed = Date(timeIntervalSince1970: 1_700_000_000)
        let at49h = signed.addingTimeInterval(49 * 3600)
        XCTAssertFalse(AfterSaleLogic.appearanceWindowOpen(signedAt: signed, now: at49h))
        XCTAssertTrue(AfterSaleLogic.suspectedFakeWindowOpen(signedAt: signed, now: at49h))
        let gate = AfterSaleLogic.createGate(
            type: .suspectedFake,
            orderStatus: "completed",
            afterSaleStatus: "none",
            signedAt: signed,
            shipDeadline: nil,
            unboxPhotoCount: 0,
            claim: .refund,
            claimAmountCents: 10_000,
            remainingPayableCents: 10_000,
            isLoggedIn: true,
            isRealNamed: true,
            accountRestricted: false,
            now: at49h
        )
        XCTAssertNil(gate)
    }

    func testAppearanceNeedsThreeUnboxPhotos() {
        let signed = Date()
        let err = AfterSaleLogic.createGate(
            type: .notAsDescribed,
            orderStatus: "shipped",
            afterSaleStatus: "none",
            signedAt: signed,
            shipDeadline: nil,
            unboxPhotoCount: 2,
            claim: .refund,
            claimAmountCents: 100,
            remainingPayableCents: 100,
            isLoggedIn: true,
            isRealNamed: true,
            accountRestricted: false
        )
        XCTAssertEqual(err, .unboxPhotosRequired)
        XCTAssertNil(
            AfterSaleLogic.createGate(
                type: .notAsDescribed,
                orderStatus: "shipped",
                afterSaleStatus: "none",
                signedAt: signed,
                shipDeadline: nil,
                unboxPhotoCount: 3,
                claim: .refund,
                claimAmountCents: 100,
                remainingPayableCents: 100,
                isLoggedIn: true,
                isRealNamed: true,
                accountRestricted: false
            )
        )
    }

    func testClaimAmountRules() {
        XCTAssertEqual(
            AfterSaleLogic.claimAmountError(claim: .refund, claimAmountCents: 99, remainingPayableCents: 100),
            .claimAmountInvalid
        )
        XCTAssertNil(
            AfterSaleLogic.claimAmountError(claim: .refund, claimAmountCents: 100, remainingPayableCents: 100)
        )
        XCTAssertEqual(
            AfterSaleLogic.claimAmountError(claim: .partial, claimAmountCents: 100, remainingPayableCents: 100),
            .claimAmountInvalid
        )
        XCTAssertNil(
            AfterSaleLogic.claimAmountError(claim: .partial, claimAmountCents: 50, remainingPayableCents: 100)
        )
    }

    // MARK: Escalate / appeal

    func testSellerCannotEscalateAfterTimeoutAgree() {
        XCTAssertEqual(
            AfterSaleLogic.canEscalate(status: .requested, timeoutAgree: true, actorIsSeller: true),
            .cannotEscalate
        )
        XCTAssertNil(
            AfterSaleLogic.canEscalate(status: .requested, timeoutAgree: false, actorIsSeller: true)
        )
        XCTAssertNil(
            AfterSaleLogic.canEscalate(status: .requested, timeoutAgree: true, actorIsSeller: false)
        )
        XCTAssertEqual(
            AfterSaleLogic.canEscalate(status: .requested, timeoutAgree: false, actorIsSeller: false, courtEnabled: false),
            .courtNotEnabled
        )
    }

    func testAppealWindow3DaysOnce() {
        let decided = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = AfterSaleLogic.appealDeadline(from: decided)
        XCTAssertEqual(deadline.timeIntervalSince(decided), 72 * 3600, accuracy: 0.1)
        XCTAssertNil(
            AfterSaleLogic.canAppeal(
                status: .closed,
                final: false,
                appealOf: nil,
                appealDeadline: deadline,
                now: decided.addingTimeInterval(24 * 3600)
            )
        )
        XCTAssertEqual(
            AfterSaleLogic.canAppeal(
                status: .closed,
                final: false,
                appealOf: nil,
                appealDeadline: deadline,
                now: decided.addingTimeInterval(73 * 3600)
            ),
            .appealWindowElapsed
        )
        XCTAssertEqual(
            AfterSaleLogic.canAppeal(
                status: .closed,
                final: true,
                appealOf: nil,
                appealDeadline: deadline,
                now: decided
            ),
            .appealAlreadyUsed
        )
        XCTAssertEqual(
            AfterSaleLogic.canAppeal(
                status: .closed,
                final: false,
                appealOf: 9,
                appealDeadline: deadline,
                now: decided
            ),
            .appealAlreadyUsed
        )
    }

    func testEvidenceClosedInDeciding() {
        XCTAssertEqual(AfterSaleLogic.canSubmitEvidence(status: .deciding), .evidencePeriodClosed)
        XCTAssertNil(AfterSaleLogic.canSubmitEvidence(status: .evidence))
        XCTAssertEqual(AfterSaleLogic.canSubmitEvidence(status: .evidence, partyAbsent: true), .evidencePeriodClosed)
    }

    func testReasonMinLengthAndRejectBare不服() {
        XCTAssertEqual(AfterSaleLogic.reasonLengthError("太短了"), .reasonTooShort)
        XCTAssertEqual(AfterSaleLogic.reasonLengthError("不服"), .reasonTooShort)
        let ok = String(repeating: "申", count: 20)
        XCTAssertNil(AfterSaleLogic.reasonLengthError(ok))
    }

    // MARK: Adverse inference (AFS-07 / B-16)

    func testAdverseInferenceWhenInspectVideoMissing() {
        XCTAssertTrue(
            AfterSaleLogic.shouldSuggestAdverseInference(
                inspectRequired: true,
                shipVideoVerified: false,
                shipVideoPresent: false
            )
        )
        XCTAssertTrue(
            AfterSaleLogic.shouldSuggestAdverseInference(
                inspectRequired: true,
                shipVideoVerified: false,
                shipVideoPresent: true
            )
        )
        XCTAssertFalse(
            AfterSaleLogic.shouldSuggestAdverseInference(
                inspectRequired: true,
                shipVideoVerified: true,
                shipVideoPresent: true
            )
        )
        XCTAssertFalse(
            AfterSaleLogic.shouldSuggestAdverseInference(
                inspectRequired: false,
                shipVideoVerified: false,
                shipVideoPresent: false
            )
        )
        XCTAssertEqual(AfterSaleLogic.defaultTemplateForAdverse(adverse: true), .hiddenFlaw)
        XCTAssertFalse(AfterSaleLogic.buyerUnboxMissingImpliesDamage(true))
        XCTAssertEqual(
            AfterSaleLogic.adverseInferenceCopy(active: true, overridden: false),
            AfterSaleCopy.adverseInferenceBanner
        )
        XCTAssertTrue(AfterSaleCopy.adverseInferenceBanner.contains("藏匿瑕疵"))
        XCTAssertTrue(AfterSaleCopy.noBuyerVideoPresumption.contains("不作损坏推定"))
    }

    func testRulingPenaltyMismatchNoFaultDeposit() {
        XCTAssertTrue(AfterSaleLogic.rulingPenaltyMismatch(template: .noFault, deductsDeposit: true))
        XCTAssertFalse(AfterSaleLogic.rulingPenaltyMismatch(template: .hiddenFlaw, deductsDeposit: true))
        XCTAssertFalse(AfterSaleLogic.rulingPenaltyMismatch(template: .noFault, deductsDeposit: false))
    }

    // MARK: Workday helper

    func testAddWorkdaysSkipsWeekend() {
        // Friday 2026-11-06 → +1 workday = Monday 2026-11-09 18:00 CST
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 6; comps.hour = 10
        let friday = cal.date(from: comps)!
        let deadline = AfterSaleLogic.addWorkdays(from: friday, workdays: 1, calendar: cal)
        let wd = cal.component(.weekday, from: deadline)
        XCTAssertEqual(wd, 2) // Monday
        XCTAssertEqual(cal.component(.hour, from: deadline), 18)
        // +5 from Friday should land next Friday (skip Sat/Sun)
        let plus5 = AfterSaleLogic.addWorkdays(from: friday, workdays: 5, calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: plus5), 6) // Friday
    }

    // MARK: Decode

    func testAfterSaleDecode() throws {
        let json = """
        {
          "id": 11,
          "order_id": 77,
          "type": "not_as_described",
          "claim": "partial",
          "claim_amount_cents": 5000,
          "reason": "右后角磕碰",
          "status": "requested",
          "seller_due_at": "2026-11-05T12:00:00Z",
          "seller_offer": {"claim":"partial","amount_cents":3000,"note":"补差"},
          "timeout_agree": false,
          "server_time": "2026-11-05T10:00:00Z"
        }
        """.data(using: .utf8)!
        let a = try decoder.decode(AfterSale.self, from: json)
        XCTAssertEqual(a.id, 11)
        XCTAssertEqual(a.type, .notAsDescribed)
        XCTAssertEqual(a.claim, .partial)
        XCTAssertEqual(a.claimAmountCents, 5_000)
        XCTAssertEqual(a.status, .requested)
        XCTAssertEqual(a.sellerOffer?.amountCents, 3_000)
        XCTAssertEqual(a.statusLabel, "待卖家处理")
    }

    func testArbitrationDecodeWithAdverseAndPenalties() throws {
        let json = """
        {
          "id": 3,
          "order_id": 77,
          "after_sale_id": 11,
          "status": "closed",
          "ruling_template": "hidden_flaw",
          "ruling_reason": "发货视频缺失且瑕疵与描述不符，构成藏匿瑕疵。",
          "adverse_inference": true,
          "final": false,
          "appeal_deadline": "2026-11-08T12:00:00Z",
          "penalties": [
            {"step":"refund","status":"succeeded"},
            {"step":"deposit_deduct","status":"failed","detail":"channel timeout"}
          ],
          "server_time": "2026-11-05T12:00:00Z"
        }
        """.data(using: .utf8)!
        let arb = try decoder.decode(Arbitration.self, from: json)
        XCTAssertEqual(arb.status, .closed)
        XCTAssertEqual(arb.rulingTemplate, .hiddenFlaw)
        XCTAssertTrue(arb.showsAdverseBanner)
        XCTAssertEqual(arb.penalties?.count, 2)
        XCTAssertEqual(arb.penalties?.last?.status, .failed)
        XCTAssertTrue(arb.canPartyAppeal)
        XCTAssertEqual(arb.templateLabel, "藏匿瑕疵")
    }

    func testErrorCodeNormalizeAndCopy() {
        XCTAssertEqual(AfterSaleErrorCode.normalize("window_elapsed"), .afterSaleWindowElapsed)
        XCTAssertEqual(AfterSaleErrorCode.normalize("already_appealed"), .appealAlreadyUsed)
        XCTAssertEqual(AfterSaleErrorCode.afterSaleWindowElapsed.fallbackMessage, AfterSaleCopy.windowElapsed)
        XCTAssertTrue(AfterSaleErrorCode.afterSaleWindowElapsed.suggestsSuspectedFake)
        XCTAssertTrue(AfterSaleErrorCode.unboxPhotosRequired.opensUnboxCapture)
        XCTAssertEqual(AfterSaleLogic.message(for: "court_not_enabled"), AfterSaleCopy.courtNotEnabled)
    }

    func testTimeoutsHelpers() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            AfterSaleLogic.sellerDueAt(from: t0).timeIntervalSince(t0),
            48 * 3600,
            accuracy: 0.1
        )
        XCTAssertEqual(
            AfterSaleLogic.evidenceDeadline(from: t0).timeIntervalSince(t0),
            72 * 3600,
            accuracy: 0.1
        )
        let remain = AfterSaleLogic.remainSeconds(
            deadline: t0.addingTimeInterval(100),
            serverTime: t0,
            fetchedAtLocal: t0,
            nowLocal: t0
        )
        XCTAssertEqual(remain, 100)
        XCTAssertFalse(AfterSaleLogic.formatCountdown(90_000).isEmpty)
    }
}
