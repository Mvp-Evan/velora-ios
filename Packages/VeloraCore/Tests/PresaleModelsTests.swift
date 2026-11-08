import XCTest
@testable import VeloraCore

final class PresaleModelsTests: XCTestCase {
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
                return Date(timeIntervalSince1970: Double(ms) / 1000)
            }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date"))
        }
        return d
    }()

    private let t0 = ISO8601DateFormatter().date(from: "2026-11-05T04:00:00Z")!

    // MARK: Defaults / statuses / legal copy

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(PresaleConfigDefaults.depositRatioMax, 0.30, accuracy: 1e-9)
        XCTAssertEqual(PresaleConfigDefaults.balanceWindowMinHours, 72)
        XCTAssertEqual(PresaleConfigDefaults.nudgeMax, 3)
        XCTAssertEqual(PresaleConfigDefaults.nudgeIntervalHours, 24)
        XCTAssertEqual(PresaleConfigDefaults.delayMax, 3)
        XCTAssertEqual(PresaleConfigDefaults.depositPaySec, 900)
        XCTAssertEqual(PresaleConfigDefaults.creditMin, 60)
        XCTAssertEqual(PresaleConfigDefaults.orderTypeDeposit, "presale_deposit")
        XCTAssertEqual(PresaleConfigDefaults.orderTypeBalance, "presale_balance")
        XCTAssertEqual(PresaleConfigDefaults.meEntryKey, "balance")
        XCTAssertEqual(PresaleConfigDefaults.launchGateKey, "launch_gate.presale")
        XCTAssertEqual(PresaleConfigDefaults.universalPathPrefix, "/pay/balance")
    }

    func testBizStatusesBuyerVisibleLabelsAndTransitions() {
        XCTAssertEqual(PresaleBizStatus.allCases.map(\.rawValue), [
            "deposit_pending", "deposit_paid", "balance_pending", "balance_paid",
            "shipped", "expired", "merchant_cancelled", "buyer_refunded", "completed",
        ])
        XCTAssertEqual(PresaleBizStatus.balancePending.displayLabel, "待补款")
        XCTAssertTrue(PresaleBizStatus.balancePending.showsBalanceCountdown)
        XCTAssertTrue(PresaleBizStatus.depositPending.showsDepositPayCTA)
        XCTAssertTrue(PresaleBizStatus.depositPaid.canTransition(to: .balancePending))
        XCTAssertTrue(PresaleBizStatus.balancePending.canTransition(to: .balancePaid))
        XCTAssertFalse(PresaleBizStatus.expired.canTransition(to: .balancePaid))
        XCTAssertFalse(PresaleBizStatus.buyerRefunded.canTransition(to: .depositPaid))
    }

    func testLegalDepositKindCopy() {
        XCTAssertEqual(PresaleLegalDepositKind.dingjin.displayCopy, PresaleCopy.legalDingjin)
        XCTAssertEqual(PresaleLegalDepositKind.orderingDeposit.displayCopy, PresaleCopy.legalOrderingDeposit)
        XCTAssertTrue(PresaleCopy.legalDingjin.contains("定金"))
        XCTAssertTrue(PresaleCopy.legalOrderingDeposit.contains("订金"))
        XCTAssertEqual(
            PresaleLogic.legalDepositCopy(.dingjin),
            "定金，逾期可能被扣除"
        )
    }

    func testDepositBalanceAmountsAndRatio() {
        let snap = PresaleAmountSnapshot(depositPriceFen: 30_000, balancePriceFen: 70_000, qty: 2)
        XCTAssertEqual(snap.depositTotalFen, 60_000)
        XCTAssertEqual(snap.balanceTotalFen, 140_000)
        XCTAssertEqual(snap.totalFen, 200_000)
        XCTAssertEqual(snap.depositRatio, 0.30, accuracy: 1e-9)
        XCTAssertTrue(PresaleLogic.isDepositRatioAllowed(depositFen: 30_000, balanceFen: 70_000))
        XCTAssertFalse(PresaleLogic.isDepositRatioAllowed(depositFen: 31_000, balanceFen: 69_000))
    }

    // MARK: Timeline filtering

    func testBuyerVisibleTimelineFiltersFundStates() {
        let events: [PresaleTimelineEvent] = [
            .init(id: 1, at: t0, title: "定金支付成功", actorType: .buyer, eventKey: "deposit_paid"),
            .init(id: 2, at: t0, title: "托管中", actorType: .system, eventKey: "deposit_held"),
            .init(id: 3, at: t0, title: "补款开启", actorType: .merchant, eventKey: "balance_opened"),
            .init(id: 4, at: t0, title: "分账中", actorType: .system, eventKey: "settling"),
            .init(id: 5, at: t0, title: "预计发货", actorType: .system, eventKey: "est_delivery"),
        ]
        let visible = PresaleLogic.buyerVisibleTimeline(events)
        XCTAssertEqual(visible.map(\.eventKey), ["deposit_paid", "balance_opened", "est_delivery"])
        XCTAssertFalse(PresaleTimelineEventKey.isBuyerVisible("settling"))
        XCTAssertTrue(PresaleTimelineEventKey.isBuyerVisible("delay_notice"))
    }

    // MARK: Decode

    func testDecodePresaleReleaseDetail() throws {
        let json = """
        {
          "id": 42,
          "title": "GT3 预售",
          "mode": "presale",
          "deposit_price_fen": 30000,
          "balance_price_fen": 229900,
          "deposit_ratio": 0.115,
          "deposit_start_at": "2026-11-05T02:00:00Z",
          "deposit_end_at": "2026-11-10T10:00:00Z",
          "balance_mode": "manual",
          "est_delivery_at": "2027-01-15T00:00:00Z",
          "settle_mode": "confirm_receipt",
          "legal_deposit_kind": "dingjin",
          "user_eligibility": {
            "real_named": true,
            "credit_ok": true,
            "credit_score": 88,
            "vip_ok": true,
            "address_ready": true,
            "launch_gate_open": true
          },
          "server_now": "2026-11-05T04:00:00Z"
        }
        """.data(using: .utf8)!

        let detail = try decoder.decode(PresaleReleaseDetail.self, from: json)
        XCTAssertEqual(detail.id, 42)
        XCTAssertTrue(detail.isPresaleMode)
        XCTAssertEqual(detail.depositPriceFen, 30_000)
        XCTAssertEqual(detail.balancePriceFen, 229_900)
        XCTAssertEqual(detail.legalDepositKind, .dingjin)
        XCTAssertEqual(detail.legalCopy, PresaleCopy.legalDingjin)
        XCTAssertEqual(detail.balanceMode, .manual)
        XCTAssertTrue(detail.eligibility?.isCreditOk == true)
        XCTAssertNotNil(detail.resolvedServerNow)
    }

    func testDecodePresaleOrderDetailTimelineStripsFund() throws {
        let json = """
        {
          "id": 900,
          "release_id": 42,
          "biz_status": "balance_pending",
          "deposit_price_fen": 30000,
          "balance_price_fen": 70000,
          "qty": 1,
          "balance_deadline": "2026-11-08T04:00:00Z",
          "delay_choice_deadline": "2026-11-06T04:00:00Z",
          "legal_deposit_kind": "ordering_deposit",
          "timeline": [
            { "id": 1, "at": "2026-11-05T03:00:00Z", "title": "定金支付成功", "actor_type": "buyer", "event_key": "deposit_paid" },
            { "id": 2, "at": "2026-11-05T03:01:00Z", "title": "资金托管", "actor_type": "system", "event_key": "deposit_held" },
            { "id": 3, "at": "2026-11-05T04:00:00Z", "title": "补款开启", "actor_type": "merchant", "event_key": "balance_opened" }
          ],
          "server_now": "2026-11-05T04:00:00Z"
        }
        """.data(using: .utf8)!

        let detail = try decoder.decode(PresaleOrderDetail.self, from: json)
        XCTAssertEqual(detail.resolvedStatus, .balancePending)
        XCTAssertEqual(detail.legalDepositKind, .orderingDeposit)
        XCTAssertEqual(detail.timeline.count, 2)
        XCTAssertEqual(detail.timeline.map(\.eventKey), ["deposit_paid", "balance_opened"])
        XCTAssertEqual(detail.amounts.balanceTotalFen, 70_000)
        // Buyer DTO must not require fund_status to decode.
        XCTAssertNil(detail.delayChoice)
    }

    func testDecodeBalancePayLanding() throws {
        let json = """
        {
          "order_id": 8801,
          "presale_order_id": 900,
          "amount_fen": 70000,
          "biz_status": "balance_pending",
          "token_valid": true,
          "requires_login": false,
          "title": "GT3 预售"
        }
        """.data(using: .utf8)!
        let landing = try decoder.decode(BalancePayLanding.self, from: json)
        XCTAssertEqual(landing.resolvedBalanceOrderId, 8801)
        XCTAssertEqual(landing.payAmountFen, 70_000)
        XCTAssertTrue(landing.canPay)
    }

    // MARK: Delay choice / countdown / CTA

    func testDelayChoiceOpenAndClosed() {
        let order = PresaleOrderSummary(
            id: 1,
            bizStatus: .depositPaid,
            delayChoiceDeadline: t0.addingTimeInterval(3_600)
        )
        let notice = PresaleDelayNotice(
            id: 9,
            body: "交期顺延两周",
            choiceDeadline: t0.addingTimeInterval(3_600)
        )
        XCTAssertTrue(PresaleLogic.isDelayChoiceOpen(notice: notice, order: order, serverNow: t0))
        XCTAssertFalse(
            PresaleLogic.isDelayChoiceOpen(
                notice: notice,
                order: order,
                serverNow: t0.addingTimeInterval(4_000)
            )
        )
        let chosen = PresaleOrderSummary(
            id: 1,
            bizStatus: .depositPaid,
            delayChoiceDeadline: t0.addingTimeInterval(3_600),
            delayChoice: .continueWaiting
        )
        XCTAssertFalse(PresaleLogic.isDelayChoiceOpen(notice: notice, order: chosen, serverNow: t0))
        XCTAssertEqual(PresaleDelayChoice.refund.displayLabel, PresaleCopy.delayRefund)
        XCTAssertEqual(PresaleDelayChoice.continueWaiting.displayLabel, PresaleCopy.delayContinue)
    }

    func testBalancePendingCountdownUsesServerNow() {
        let deadline = t0.addingTimeInterval(72 * 3600)
        XCTAssertEqual(PresaleLogic.countdownSeconds(until: deadline, serverNow: t0), 72 * 3600)
        let line = PresaleLogic.balanceDeadlineCountdownLine(seconds: 65)
        XCTAssertTrue(line.contains(PresaleCopy.serverTimeHint))
        XCTAssertTrue(line.contains("00:01:05"))

        let order = PresaleOrderSummary(
            id: 1,
            bizStatus: .balancePending,
            balancePriceFen: 70_000,
            balanceDeadline: deadline
        )
        XCTAssertEqual(PresaleLogic.resolveOrderCTA(order: order, serverNow: t0), .payBalance)
        let subtitle = PresaleLogic.listSubtitle(order: order, serverNow: t0)
        XCTAssertTrue(subtitle.contains(PresaleCopy.serverTimeHint))
    }

    func testBalanceWindowAndDepositWindow() {
        let start = t0
        let endOk = t0.addingTimeInterval(72 * 3600)
        let endShort = t0.addingTimeInterval(48 * 3600)
        XCTAssertTrue(PresaleLogic.isBalanceWindowLongEnough(start: start, end: endOk))
        XCTAssertFalse(PresaleLogic.isBalanceWindowLongEnough(start: start, end: endShort))
        XCTAssertTrue(PresaleLogic.isDepositWindowOpen(start: t0.addingTimeInterval(-60), end: t0.addingTimeInterval(60), serverNow: t0))
        XCTAssertFalse(PresaleLogic.isDepositWindowOpen(start: t0.addingTimeInterval(60), end: nil, serverNow: t0))
    }

    func testReleaseCTAAndChecklist() {
        let eligibility = PresaleEligibility(
            realNamed: true,
            creditOk: true,
            addressReady: true,
            launchGateOpen: true
        )
        let items = PresaleLogic.depositChecklist(isLoggedIn: true, eligibility: eligibility, hasAddress: true)
        XCTAssertTrue(items.allSatisfy(\.done))

        let gated = PresaleReleaseDetail(
            id: 1,
            mode: "presale",
            depositStartAt: t0.addingTimeInterval(-100),
            depositEndAt: t0.addingTimeInterval(100),
            eligibility: PresaleEligibility(launchGateOpen: false)
        )
        XCTAssertEqual(
            PresaleLogic.resolveReleaseCTA(detail: gated, serverNow: t0, isLoggedIn: true, hasAddress: true),
            .gated
        )

        let open = PresaleReleaseDetail(
            id: 1,
            mode: "presale",
            depositStartAt: t0.addingTimeInterval(-100),
            depositEndAt: t0.addingTimeInterval(100),
            eligibility: eligibility
        )
        XCTAssertEqual(
            PresaleLogic.resolveReleaseCTA(detail: open, serverNow: t0, isLoggedIn: true, hasAddress: true),
            .payDeposit
        )
        XCTAssertEqual(
            PresaleLogic.resolveReleaseCTA(detail: open, serverNow: t0, isLoggedIn: false, hasAddress: false),
            .login
        )
    }

    // MARK: Universal Link parsing

    func testBalancePayUniversalLinkParsing() {
        let url = URL(string: "https://u.velora.test/pay/balance/8801?t=opaqueToken")!
        let link = BalancePayDeepLink.parse(url: url)
        XCTAssertEqual(link?.balanceOrderId, 8801)
        XCTAssertEqual(link?.token, "opaqueToken")
        XCTAssertNil(link?.shortCode)
    }

    func testBalancePayAppSchemeAndShortLink() {
        let app = URL(string: "velora://pay/balance/8802?t=abc")!
        let parsed = BalancePayDeepLink.parse(url: app)
        XCTAssertEqual(parsed?.balanceOrderId, 8802)
        XCTAssertEqual(parsed?.token, "abc")

        let short = URL(string: "https://u.velora.test/b/Ab12Cd34")!
        let shortLink = BalancePayDeepLink.parse(url: short)
        XCTAssertEqual(shortLink?.shortCode, "Ab12Cd34")
        XCTAssertNil(shortLink?.balanceOrderId)

        XCTAssertNil(BalancePayDeepLink.parse(url: URL(string: "https://u.velora.test/kyc/return")!))
        XCTAssertNil(BalancePayDeepLink.parse(url: URL(string: "https://u.velora.test/b/ab")!))
    }

    func testErrorCodes() {
        XCTAssertEqual(PresaleErrorCode.notBalancePending.rawValue, "not_balance_pending")
        XCTAssertEqual(PresaleErrorCode.delayChoiceClosed.fallbackMessage, PresaleCopy.delayChoiceClosed)
        XCTAssertTrue(PresaleErrorCode.authRequired.opensLogin)
        XCTAssertTrue(PresaleErrorCode.realNameRequired.opensRealName)
        XCTAssertEqual(PresaleErrorCode.creditTooLow.fallbackMessage, PresaleCopy.creditTooLow)
        XCTAssertEqual(PresaleErrorCode.balanceLinkExpired.fallbackMessage, PresaleCopy.linkExpired)
    }
}
