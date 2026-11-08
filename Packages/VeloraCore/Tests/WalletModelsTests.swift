import XCTest
@testable import VeloraCore

final class WalletModelsTests: XCTestCase {
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

    // MARK: Config

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(WalletConfigDefaults.syncTtlSec, 60)
        XCTAssertEqual(WalletConfigDefaults.withdrawMinFen, 10_000)
        XCTAssertEqual(WalletConfigDefaults.withdrawMaxFen, 50_000_000)
        XCTAssertEqual(WalletConfigDefaults.withdrawDailyCount, 10)
        XCTAssertEqual(WalletConfigDefaults.withdrawFeeFenDefault, 0)
        XCTAssertEqual(WalletConfigDefaults.reconcileTz, "Asia/Shanghai")
        XCTAssertEqual(WalletConfigDefaults.reconcileHourCst, 2)
        XCTAssertEqual(WalletConfigDefaults.refundRetryMax, 3)
        XCTAssertTrue(WalletConfigDefaults.projectionOnly)
        XCTAssertFalse(WalletConfigDefaults.refundShippingDefault)
        XCTAssertEqual(WalletConfigDefaults.meEntryKey, "wallet")
    }

    // MARK: Projection decode

    func testProjectionDecodesNewFields() throws {
        let json = """
        {"pending":12000,"available":88000,"sync_at":"2026-11-05T01:00:00Z","channel":"wechat","sub_mch_id":"sm_1"}
        """.data(using: .utf8)!
        let w = try decoder.decode(WalletProjection.self, from: json)
        XCTAssertEqual(w.pending, 12_000)
        XCTAssertEqual(w.available, 88_000)
        XCTAssertEqual(w.channel, "wechat")
        XCTAssertEqual(w.subMchId, "sm_1")
        XCTAssertNotNil(w.lastSyncedAt)
        XCTAssertEqual(w.availableBalance, 88_000)
        XCTAssertEqual(w.pendingBalance, 12_000)
    }

    func testProjectionDecodesLegacyBalanceFields() throws {
        let json = """
        {"available_balance":50000,"pending_balance":10000,"total_income":200000,"total_withdrawn":30000}
        """.data(using: .utf8)!
        let w = try decoder.decode(WalletProjection.self, from: json)
        XCTAssertEqual(w.available, 50_000)
        XCTAssertEqual(w.pending, 10_000)
        XCTAssertEqual(w.legacyTotalIncome, 200_000)
        XCTAssertEqual(w.totalIncome, 200_000)
        XCTAssertEqual(w.totalWithdrawn, 30_000)
    }

    func testProjectionDecodesFenAliases() throws {
        let json = """
        {"available_fen":1,"pending_fen":2,"last_synced_at":"2026-11-05T00:00:00Z","sync_error":"timeout","sandbox":true}
        """.data(using: .utf8)!
        let w = try decoder.decode(WalletProjection.self, from: json)
        XCTAssertEqual(w.available, 1)
        XCTAssertEqual(w.pending, 2)
        XCTAssertTrue(w.hasSyncError)
        XCTAssertTrue(w.showsSandboxWatermark)
    }

    func testProjectionStaleWhenOlderThanTtl() {
        let fresh = WalletProjection(available: 1, pending: 0, lastSyncedAt: Date())
        XCTAssertFalse(fresh.isStale(ttlSec: 60))
        let old = WalletProjection(available: 1, pending: 0, lastSyncedAt: Date().addingTimeInterval(-120))
        XCTAssertTrue(old.isStale(ttlSec: 60))
        let missing = WalletProjection(available: 1, pending: 0, lastSyncedAt: nil)
        XCTAssertTrue(missing.isStale())
    }

    // MARK: Withdraw status

    func testWithdrawStatusNormalizeLegacy() {
        XCTAssertEqual(WithdrawalStatus.normalize("created"), .created)
        XCTAssertEqual(WithdrawalStatus.normalize("pending"), .created)
        XCTAssertEqual(WithdrawalStatus.normalize("approved"), .channelPending)
        XCTAssertEqual(WithdrawalStatus.normalize("channel_pending"), .channelPending)
        XCTAssertEqual(WithdrawalStatus.normalize("paid"), .succeeded)
        XCTAssertEqual(WithdrawalStatus.normalize("succeeded"), .succeeded)
        XCTAssertEqual(WithdrawalStatus.normalize("rejected"), .failed)
        XCTAssertEqual(WithdrawalStatus.normalize("failed"), .failed)
        // Unknown / empty enums stay nil / fail-soft rather than crash decode helpers.
        XCTAssertNil(WithdrawalStatus.normalize("totally_unknown_status"))
        XCTAssertNil(WithdrawalStatus.normalize(""))
        XCTAssertNil(WalletErrorCode.normalize("not_a_wallet_error"))
    }

    func testWithdrawStatusLabelsAndTerminal() {
        XCTAssertEqual(WithdrawalStatus.created.displayLabel, "已提交")
        XCTAssertEqual(WithdrawalStatus.channelPending.displayLabel, "渠道处理中")
        XCTAssertEqual(WithdrawalStatus.succeeded.displayLabel, "已到账")
        XCTAssertEqual(WithdrawalStatus.failed.displayLabel, "失败")
        XCTAssertTrue(WithdrawalStatus.succeeded.isTerminal)
        XCTAssertTrue(WithdrawalStatus.channelPending.isInFlight)
        XCTAssertFalse(WithdrawalStatus.created.isTerminal)
    }

    func testWithdrawalRequestDecodesChannelFields() throws {
        let json = """
        {"id":9,"amount":10000,"status":"channel_pending","channel_withdraw_no":"cw_1","fail_reason":null,"created_at":"2026-11-05T02:00:00Z"}
        """.data(using: .utf8)!
        let w = try decoder.decode(WithdrawalRequest.self, from: json)
        XCTAssertEqual(w.status, .channelPending)
        XCTAssertEqual(w.channelWithdrawNo, "cw_1")
        XCTAssertEqual(w.statusLabel, "渠道处理中")
        XCTAssertNil(w.failureDisplay)
    }

    func testWithdrawalRequestLegacyPaid() throws {
        let json = """
        {"id":1,"amount":20000,"status":"paid","note":"ok","bank_account":{"bank_name":"招商银行"}}
        """.data(using: .utf8)!
        let w = try decoder.decode(WithdrawalRequest.self, from: json)
        XCTAssertEqual(w.status, .succeeded)
        XCTAssertEqual(w.bankAccount?["bank_name"], "招商银行")
    }

    // MARK: Errors

    func testErrorCodeNormalizeAndCopy() {
        XCTAssertNil(WalletErrorCode.normalize("payout_account_required"))
        XCTAssertFalse(
            WalletErrorCode.allCases.map(\.rawValue).contains("payout_account_required")
        )
        XCTAssertEqual(WalletErrorCode.normalize("withdraw_not_whitelisted"), .withdrawNotWhitelisted)
        XCTAssertEqual(WalletErrorCode.normalize("below_min"), .belowMin)
        XCTAssertEqual(WalletErrorCode.normalize("insufficient_balance"), .insufficientAvailable)
        XCTAssertEqual(WalletErrorCode.normalize("share_processing"), .shareNotReady)
        XCTAssertEqual(WalletErrorCode.belowMin.fallbackMessage, WalletCopy.belowMin)
        XCTAssertEqual(WalletErrorCode.accountFrozen.fallbackMessage, WalletCopy.accountFrozen)
        XCTAssertTrue(WalletErrorCode.subMerchantRequired.opensSubMerchant)
        XCTAssertTrue(WalletErrorCode.realNameRequired.opensRealName)
        XCTAssertTrue(WalletCopy.custodyDisclaimer.contains("毂毂不存放"))
    }

    func testWithdrawLogicGates() {
        XCTAssertEqual(WalletWithdrawLogic.canSubmit(amountFen: 9_900, availableFen: 100_000), .belowMin)
        XCTAssertEqual(WalletWithdrawLogic.canSubmit(amountFen: 20_000, availableFen: 10_000), .insufficientAvailable)
        XCTAssertNil(WalletWithdrawLogic.canSubmit(amountFen: 10_000, availableFen: 10_000))
        XCTAssertTrue(WalletWithdrawLogic.isAmountValid(amountFen: 10_000, availableFen: 50_000))
        XCTAssertFalse(WalletWithdrawLogic.isAmountValid(amountFen: 99, availableFen: 50_000))
        XCTAssertEqual(WalletWithdrawLogic.message(for: "below_min"), WalletCopy.belowMin)
    }

    // MARK: Two-phase refund progress

    func testRefundPhaseNormalize() {
        XCTAssertEqual(RefundPhaseStatus.normalize("waiting_share_return"), .waitingShareReturn)
        XCTAssertEqual(RefundPhaseStatus.normalize("blocked_waiting_share"), .blockedWaitingShare)
        XCTAssertEqual(RefundPhaseStatus.normalize("refunding"), .refunding)
        XCTAssertEqual(RefundPhaseStatus.normalize("succeeded"), .succeeded)
        XCTAssertEqual(RefundPhaseStatus.normalize("refund_failed"), .refundFailed)
        XCTAssertEqual(RefundPhaseStatus.normalize("failed"), .refundFailed)
        XCTAssertEqual(RefundPhaseStatus.normalize("pending"), .created)
    }

    func testRefundProgressSteps() {
        XCTAssertEqual(RefundProgressStep.allCases.map(\.title), ["回退中", "退款中", "到账"])
        XCTAssertEqual(RefundProgressLogic.currentIndex(status: .waitingShareReturn), 0)
        XCTAssertEqual(RefundProgressLogic.currentIndex(status: .blockedWaitingShare), 0)
        XCTAssertEqual(RefundProgressLogic.currentIndex(status: .refunding), 1)
        XCTAssertEqual(RefundProgressLogic.currentIndex(status: .succeeded), 2)
        XCTAssertEqual(RefundProgressLogic.currentIndex(status: .created, needsShareReturn: false), 1)
        XCTAssertTrue(RefundProgressLogic.isStepCurrent(.shareReturn, status: .waitingShareReturn))
        XCTAssertTrue(RefundProgressLogic.isStepComplete(.shareReturn, status: .refunding))
        XCTAssertTrue(RefundProgressLogic.isStepCurrent(.arrived, status: .succeeded))
        XCTAssertEqual(RefundProgressLogic.buyerHeadline(status: .refunding), WalletCopy.refundProcessing)
        XCTAssertEqual(RefundProgressLogic.buyerHeadline(status: .succeeded), WalletCopy.refundArrived)
    }

    func testRefundProgressDecode() throws {
        let json = """
        {"id":3,"order_id":77,"amount":10000,"status":"waiting_share_return","is_partial":true,"share_return_id":12,"refund_shipping":false}
        """.data(using: .utf8)!
        let r = try decoder.decode(RefundProgress.self, from: json)
        XCTAssertEqual(r.status, .waitingShareReturn)
        XCTAssertEqual(r.isPartial, true)
        XCTAssertTrue(r.needsShareReturn)
        XCTAssertEqual(r.progressIndex, 0)
        XCTAssertEqual(r.headline, WalletCopy.refundProcessing)
    }

    // MARK: Share return split (§5.6)

    func testShareReturnSplitPartialFourPercent() {
        // 部分退 100 元、费率 4% → 平台 4 元、卖家 96 元
        let split = ShareReturnSplitLogic.split(goodsRefundFen: 10_000, rateBp: 400)
        XCTAssertEqual(split.feeReturn, 400)
        XCTAssertEqual(split.sellerReturn, 9_600)
    }

    func testShareReturnSplitWithShipping() {
        let split = ShareReturnSplitLogic.split(
            goodsRefundFen: 10_000,
            rateBp: 400,
            shippingFeeFen: 1_200,
            refundShipping: true
        )
        XCTAssertEqual(split.feeReturn, 400)
        XCTAssertEqual(split.sellerReturn, 10_800)
        let noShip = ShareReturnSplitLogic.split(
            goodsRefundFen: 10_000,
            rateBp: 400,
            shippingFeeFen: 1_200,
            refundShipping: false
        )
        XCTAssertEqual(noShip.sellerReturn, 9_600)
    }

    func testShareReturnSplitRoundsHalfUp() {
        // 101 fen * 4% = 4.04 → round 4
        let a = ShareReturnSplitLogic.split(goodsRefundFen: 101, rateBp: 400)
        XCTAssertEqual(a.feeReturn, 4)
        // 113 fen * 4% = 4.52 → round 5
        let b = ShareReturnSplitLogic.split(goodsRefundFen: 113, rateBp: 400)
        XCTAssertEqual(b.feeReturn, 5)
    }

    // MARK: Ledger

    func testLedgerEntryLabels() throws {
        let json = """
        {"id":1,"journal_id":"j1","order_id":9,"order_no":"P43ABC","account":"seller_channel_available","direction":"credit","amount":240000,"memo":"分账","created_at":"2026-11-05T03:00:00Z","event_kind":"share"}
        """.data(using: .utf8)!
        let e = try decoder.decode(WalletLedgerEntry.self, from: json)
        XCTAssertEqual(e.orderNo, "P43ABC")
        XCTAssertEqual(e.accountLabel, "可提现变动")
        XCTAssertTrue(e.isCredit)
    }

    func testCreateRefundRequestBody() {
        let req = CreateRefundRequest(amount: 5_000, reason: "协商退", refundShipping: true)
        XCTAssertEqual(req.body["amount"] as? Int64, 5_000)
        XCTAssertEqual(req.body["refund_shipping"] as? Bool, true)
        XCTAssertEqual(req.body["reason"] as? String, "协商退")
    }

    func testCustodyCopyAndEmptyStates() {
        XCTAssertTrue(WalletCopy.custodyDisclaimer.contains("微信支付"))
        XCTAssertEqual(WalletCopy.pendingHint, "确认收货后可提")
        XCTAssertEqual(WalletCopy.emptyBalance, "确认收货后货款进入可提现")
        XCTAssertEqual(WalletCopy.withdrawArriveHint, "以渠道为准，通常实时到余额")
    }
}
