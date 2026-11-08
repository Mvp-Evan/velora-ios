import Foundation

// MARK: - Wallet projection / channel withdraw / two-phase refund (DES-v1.3-08-03 PAY-04/09/10 / D31)

/// Product defaults (design §6 / §15). Hot-config on server; client mirrors for UX.
public enum WalletConfigDefaults {
    public static let syncTtlSec = 60
    public static let withdrawMinFen: Int64 = 10_000
    public static let withdrawMaxFen: Int64 = 50_000_000
    public static let withdrawDailyCount = 10
    public static let withdrawFeeFenDefault: Int64 = 0
    public static let reconcileTz = "Asia/Shanghai"
    public static let reconcileHourCst = 2
    public static let refundRetryMax = 3
    public static let projectionOnly = true
    public static let refundShippingDefault = false
    public static let syncStaleHours = 1
    public static let twoPhaseStuckMinutes = 30
    public static let meEntryKey = "wallet"
    public static let notifySettledCode = "N-21"
}

// MARK: - Wallet projection (PAY-09)

/// Channel secondary-merchant balance projection — not platform-held funds (design §3 / §5.1).
public struct WalletProjection: Codable, Equatable, Sendable, Hashable {
    /// 可提现（渠道 available；确认收货前该笔不在内）
    public let available: Int64
    /// 在途 / 待结算（渠道 pending）
    public let pending: Int64
    public let lastSyncedAt: Date?
    public let syncError: String?
    public let channel: String?
    public let subMchId: String?
    /// Review/sandbox watermark (design §9).
    public let sandbox: Bool?
    /// Legacy read-only对照；不得作为可提依据。
    public let legacyTotalIncome: Int64?
    public let legacyTotalWithdrawn: Int64?

    public init(
        available: Int64 = 0,
        pending: Int64 = 0,
        lastSyncedAt: Date? = nil,
        syncError: String? = nil,
        channel: String? = nil,
        subMchId: String? = nil,
        sandbox: Bool? = nil,
        legacyTotalIncome: Int64? = nil,
        legacyTotalWithdrawn: Int64? = nil
    ) {
        self.available = available
        self.pending = pending
        self.lastSyncedAt = lastSyncedAt
        self.syncError = syncError
        self.channel = channel
        self.subMchId = subMchId
        self.sandbox = sandbox
        self.legacyTotalIncome = legacyTotalIncome
        self.legacyTotalWithdrawn = legacyTotalWithdrawn
    }

    enum CodingKeys: String, CodingKey {
        case available, pending, lastSyncedAt, syncError, channel, subMchId, sandbox
        case availableFen, pendingFen, syncAt
        case availableBalance, pendingBalance, totalIncome, totalWithdrawn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = try c.decodeIfPresent(Int64.self, forKey: .available)
            ?? c.decodeIfPresent(Int64.self, forKey: .availableFen)
            ?? c.decodeIfPresent(Int64.self, forKey: .availableBalance)
            ?? 0
        pending = try c.decodeIfPresent(Int64.self, forKey: .pending)
            ?? c.decodeIfPresent(Int64.self, forKey: .pendingFen)
            ?? c.decodeIfPresent(Int64.self, forKey: .pendingBalance)
            ?? 0
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
            ?? c.decodeIfPresent(Date.self, forKey: .syncAt)
        syncError = try c.decodeIfPresent(String.self, forKey: .syncError)
        channel = try c.decodeIfPresent(String.self, forKey: .channel)
        subMchId = try c.decodeIfPresent(String.self, forKey: .subMchId)
        sandbox = try c.decodeIfPresent(Bool.self, forKey: .sandbox)
        legacyTotalIncome = try c.decodeIfPresent(Int64.self, forKey: .totalIncome)
        legacyTotalWithdrawn = try c.decodeIfPresent(Int64.self, forKey: .totalWithdrawn)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(available, forKey: .available)
        try c.encode(pending, forKey: .pending)
        try c.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
        try c.encodeIfPresent(syncError, forKey: .syncError)
        try c.encodeIfPresent(channel, forKey: .channel)
        try c.encodeIfPresent(subMchId, forKey: .subMchId)
        try c.encodeIfPresent(sandbox, forKey: .sandbox)
        try c.encodeIfPresent(legacyTotalIncome, forKey: .totalIncome)
        try c.encodeIfPresent(legacyTotalWithdrawn, forKey: .totalWithdrawn)
    }

    /// Backward-compatible aliases used by older screens.
    public var availableBalance: Int64 { available }
    public var pendingBalance: Int64 { pending }
    public var totalIncome: Int64 { legacyTotalIncome ?? 0 }
    public var totalWithdrawn: Int64 { legacyTotalWithdrawn ?? 0 }

    public var hasSyncError: Bool { syncError.map { !$0.isEmpty } ?? false }
    public var showsSandboxWatermark: Bool { sandbox == true }

    public func isStale(now: Date = Date(), ttlSec: Int = WalletConfigDefaults.syncTtlSec) -> Bool {
        guard let lastSyncedAt else { return true }
        return now.timeIntervalSince(lastSyncedAt) > TimeInterval(ttlSec)
    }
}

/// Typealias kept for call sites that still say `Wallet`.
public typealias Wallet = WalletProjection

// MARK: - Withdraw status / errors (PAY-09)

/// `withdrawals.status`: created → channel_pending → succeeded | failed (design §4 / §6).
/// Legacy approve/pay path maps into channel statuses; platform approve is abolished.
public enum WithdrawalStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case created
    case channelPending = "channel_pending"
    case succeeded
    case failed

    public static func normalize(_ raw: String?) -> WithdrawalStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = WithdrawalStatus(rawValue: s) { return exact }
        switch s {
        case "pending", "submitted", "requested":
            return .created
        case "approved", "processing", "paying", "in_flight", "channel_processing":
            return .channelPending
        case "paid", "success", "done", "completed":
            return .succeeded
        case "rejected", "cancelled", "canceled", "error":
            return .failed
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .created: return "已提交"
        case .channelPending: return "渠道处理中"
        case .succeeded: return "已到账"
        case .failed: return "失败"
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed: return true
        case .created, .channelPending: return false
        }
    }

    public var isInFlight: Bool {
        switch self {
        case .created, .channelPending: return true
        case .succeeded, .failed: return false
        }
    }
}

public enum WalletErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case subMerchantRequired = "sub_merchant_required"
    case withdrawNotWhitelisted = "withdraw_not_whitelisted"
    case insufficientAvailable = "insufficient_available"
    case belowMin = "below_min"
    case withdrawForbidden = "withdraw_forbidden"
    case refundExceeds = "refund_exceeds"
    case shareNotReady = "share_not_ready"
    case accountFrozen = "account_frozen"
    case approvalRequired = "approval_required"
    case realNameRequired = "real_name_required"
    case forbidden = "forbidden"
    case missingIdempotencyKey = "missing_idempotency_key"
    case dailyLimit = "daily_withdraw_limit"

    public static func normalize(_ raw: String?) -> WalletErrorCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = WalletErrorCode(rawValue: s) { return exact }
        switch s {
        case "insufficient_balance", "balance_insufficient", "insufficient":
            return .insufficientAvailable
        case "amount_too_small", "min_amount", "below_minimum":
            return .belowMin
        case "withdraw_blocked", "frozen":
            return .accountFrozen
        case "need_sub_merchant", "sub_mch_required":
            return .subMerchantRequired
        case "share_processing", "profit_share_not_ready":
            return .shareNotReady
        case "refund_amount_exceeds", "exceeds_refundable":
            return .refundExceeds
        case "daily_count", "withdraw_daily_limit":
            return .dailyLimit
        default:
            return nil
        }
    }

    public var fallbackMessage: String {
        switch self {
        case .subMerchantRequired: return WalletCopy.subMerchantRequired
        case .withdrawNotWhitelisted: return "当前账号未在提现白名单"
        case .insufficientAvailable: return WalletCopy.insufficientAvailable
        case .belowMin: return WalletCopy.belowMin
        case .withdrawForbidden: return WalletCopy.withdrawForbidden
        case .refundExceeds: return WalletCopy.refundExceeds
        case .shareNotReady: return WalletCopy.shareNotReady
        case .accountFrozen: return WalletCopy.accountFrozen
        case .approvalRequired: return WalletCopy.approvalRequired
        case .realNameRequired: return "请先完成实名认证"
        case .forbidden: return WalletCopy.buyerForbidden
        case .missingIdempotencyKey: return "请重试"
        case .dailyLimit: return WalletCopy.dailyLimit
        }
    }

    public var opensSubMerchant: Bool { self == .subMerchantRequired }
    public var opensRealName: Bool { self == .realNameRequired }
}

// MARK: - Two-phase refund (PAY-04)

/// `refunds.status`: created → waiting_share_return? → refunding → succeeded;
/// side paths: refund_failed, blocked_waiting_share (design §4 / §5.8).
public enum RefundPhaseStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case created
    case waitingShareReturn = "waiting_share_return"
    case blockedWaitingShare = "blocked_waiting_share"
    case refunding
    case succeeded
    case refundFailed = "refund_failed"

    public static func normalize(_ raw: String?) -> RefundPhaseStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = RefundPhaseStatus(rawValue: s) { return exact }
        switch s {
        case "pending", "initiated":
            return .created
        case "waiting_return", "share_return", "returning_share":
            return .waitingShareReturn
        case "blocked", "share_not_ready", "waiting_share":
            return .blockedWaitingShare
        case "processing", "channel_refunding", "refund_pending":
            return .refunding
        case "success", "done", "completed", "paid":
            return .succeeded
        case "failed", "error", "refund_error":
            return .refundFailed
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .created: return "退款处理中"
        case .waitingShareReturn: return "分账回退中"
        case .blockedWaitingShare: return "等待分账完成"
        case .refunding: return "退款中"
        case .succeeded: return "已到账"
        case .refundFailed: return "退款失败"
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .refundFailed: return true
        case .created, .waitingShareReturn, .blockedWaitingShare, .refunding: return false
        }
    }

    public var showsBuyerProgress: Bool {
        switch self {
        case .succeeded: return true
        case .created, .waitingShareReturn, .blockedWaitingShare, .refunding, .refundFailed: return true
        }
    }
}

/// Buyer-facing progress strip (design §9): 回退中 / 退款中 / 到账.
public enum RefundProgressStep: String, Sendable, CaseIterable, Equatable {
    case shareReturn
    case refunding
    case arrived

    public var title: String {
        switch self {
        case .shareReturn: return "回退中"
        case .refunding: return "退款中"
        case .arrived: return "到账"
        }
    }
}

public enum RefundProgressLogic {
    /// Index into `RefundProgressStep.allCases` for the current phase.
    public static func currentIndex(status: RefundPhaseStatus, needsShareReturn: Bool = true) -> Int {
        switch status {
        case .created:
            return needsShareReturn ? 0 : 1
        case .waitingShareReturn, .blockedWaitingShare:
            return 0
        case .refunding, .refundFailed:
            return 1
        case .succeeded:
            return 2
        }
    }

    public static func isStepComplete(_ step: RefundProgressStep, status: RefundPhaseStatus, needsShareReturn: Bool = true) -> Bool {
        let idx = currentIndex(status: status, needsShareReturn: needsShareReturn)
        guard let stepIdx = RefundProgressStep.allCases.firstIndex(of: step) else { return false }
        if status == .succeeded { return true }
        return stepIdx < idx
    }

    public static func isStepCurrent(_ step: RefundProgressStep, status: RefundPhaseStatus, needsShareReturn: Bool = true) -> Bool {
        if status == .succeeded { return step == .arrived }
        let idx = currentIndex(status: status, needsShareReturn: needsShareReturn)
        return RefundProgressStep.allCases.firstIndex(of: step) == idx
    }

    public static func buyerHeadline(status: RefundPhaseStatus) -> String {
        switch status {
        case .created, .waitingShareReturn, .blockedWaitingShare, .refunding:
            return WalletCopy.refundProcessing
        case .succeeded:
            return WalletCopy.refundArrived
        case .refundFailed:
            return WalletCopy.refundFailed
        }
    }
}

/// Share-return amount split for partial/full refunds (design §5.6).
public enum ShareReturnSplitLogic {
    /// `fee_return = round(R * rate_bp / 10000)`, `seller_return = R - fee_return` (+ shipping when flagged).
    public static func split(
        goodsRefundFen R: Int64,
        rateBp: Int,
        shippingFeeFen: Int64 = 0,
        refundShipping: Bool = false
    ) -> (feeReturn: Int64, sellerReturn: Int64) {
        let r = max(0, R)
        let fee = Int64((Double(r) * Double(rateBp) / 10_000.0).rounded())
        var seller = r - fee
        if refundShipping {
            seller += max(0, shippingFeeFen)
        }
        return (fee, seller)
    }
}

// MARK: - Copy (design §9)

public enum WalletCopy {
    public static let homeTitle = "我的钱包"
    public static let custodyDisclaimer = "余额以微信支付/支付宝为准，毂毂不存放您的货款"
    public static let pendingHint = "确认收货后可提"
    public static let pendingEmpty = "确认收货后货款进入可提现"
    public static let syncing = "同步渠道余额…"
    public static let syncFailed = "同步失败，点刷新重试"
    public static let staleHint = "展示可能已过期"
    public static let availableTitle = "可提现"
    public static let pendingTitle = "在途待结算"
    public static let withdrawCTA = "提现"
    public static let withdrawConfirmTitle = "确认提现"
    public static let withdrawArriveHint = "以渠道为准，通常实时到余额"
    public static let withdrawMinHint = "最低提现 ¥100"
    public static let withdrawFeeHint = "手续费以渠道为准（常为 0）"
    public static let withdrawSubmitted = "已提交渠道提现"
    public static let withdrawLoading = "提交中…"
    public static let ledgerTitle = "资金流水"
    public static let ledgerNotPlatform = "非平台记账余额，为渠道资金事件镜像"
    public static let withdrawalsTitle = "提现记录"
    public static let emptyLedger = "暂无资金流水"
    public static let emptyWithdrawals = "暂无提现记录"
    public static let emptyBalance = "确认收货后货款进入可提现"
    public static let sandboxWatermark = "沙箱余额"
    public static let buyerForbidden = "买家无货款钱包"
    public static let subMerchantRequired = "请先完成收款进件"
    public static let insufficientAvailable = "可提现余额不足"
    public static let belowMin = "未达到最低提现额 ¥100"
    public static let withdrawForbidden = "当前账号不可提现"
    public static let accountFrozen = "账号已冻结，暂不可提现"
    public static let refundExceeds = "退款金额超过可退余额"
    public static let shareNotReady = "分账尚未完成，退款稍后处理"
    public static let approvalRequired = "需要双人复核"
    public static let dailyLimit = "今日提现次数已达上限"
    public static let refundProcessing = "退款处理中"
    public static let refundArrived = "退款已到账"
    public static let refundFailed = "退款失败，请稍后查看"
    public static let reopenChannelWithdraw = "请从钱包重新发起渠道提现"
    public static let guideOnboarding = "开通卖家并完成进件后可查看货款余额"
}

// MARK: - Withdraw validation helpers

public enum WalletWithdrawLogic {
    public static func canSubmit(amountFen: Int64, availableFen: Int64) -> WalletErrorCode? {
        if amountFen < WalletConfigDefaults.withdrawMinFen { return .belowMin }
        if amountFen > availableFen { return .insufficientAvailable }
        if amountFen > WalletConfigDefaults.withdrawMaxFen { return .insufficientAvailable }
        return nil
    }

    /// Client-side gate before POST; max is soft-capped for UX.
    public static func isAmountValid(amountFen: Int64, availableFen: Int64) -> Bool {
        amountFen >= WalletConfigDefaults.withdrawMinFen
            && amountFen <= min(availableFen, WalletConfigDefaults.withdrawMaxFen)
    }

    public static func formatYuan(_ fen: Int64) -> String {
        let yuan = Double(fen) / 100.0
        if fen % 100 == 0 { return String(format: "%.0f", yuan) }
        if fen % 10 == 0 { return String(format: "%.1f", yuan) }
        return String(format: "%.2f", yuan)
    }

    public static func message(for code: String?, serverMessage: String? = nil) -> String {
        if let normalized = WalletErrorCode.normalize(code) {
            return normalized.fallbackMessage
        }
        if let serverMessage, !serverMessage.isEmpty { return serverMessage }
        return "操作失败，请稍后重试"
    }
}

// MARK: - DTOs

public struct WalletLedgerEntry: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let journalId: String?
    public let orderId: Int64?
    public let orderNo: String?
    public let account: String
    public let direction: String
    public let amount: Int64
    public let memo: String?
    public let createdAt: Date?
    public let eventKind: String?

    public init(
        id: Int64,
        journalId: String? = nil,
        orderId: Int64? = nil,
        orderNo: String? = nil,
        account: String,
        direction: String,
        amount: Int64,
        memo: String? = nil,
        createdAt: Date? = nil,
        eventKind: String? = nil
    ) {
        self.id = id
        self.journalId = journalId
        self.orderId = orderId
        self.orderNo = orderNo
        self.account = account
        self.direction = direction
        self.amount = amount
        self.memo = memo
        self.createdAt = createdAt
        self.eventKind = eventKind
    }

    public var accountLabel: String {
        switch account {
        case "seller_payable", "channel_pending": return "在途货款"
        case "seller_wallet", "seller_channel_available", "seller_receivable": return "可提现变动"
        case "tax_withheld": return "税费预提"
        case "withdrawal": return "提现"
        case "buyer_payment": return "买家付款"
        case "buyer_refund": return "退款"
        case "platform_revenue": return "平台服务费"
        case "share_return": return "分账回退"
        default: return eventKind.flatMap { Self.kindLabel($0) } ?? account
        }
    }

    public var isCredit: Bool { direction == "credit" }

    private static func kindLabel(_ kind: String) -> String? {
        switch kind.lowercased() {
        case "payment", "pay": return "支付入账"
        case "share", "profit_share": return "分账"
        case "refund": return "退款"
        case "withdraw", "withdrawal": return "提现"
        case "share_return": return "分账回退"
        default: return nil
        }
    }
}

/// Alias for existing call sites.
public typealias LedgerEntry = WalletLedgerEntry

public struct WithdrawalRequest: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let amount: Int64
    public let status: WithdrawalStatus
    public let channelWithdrawNo: String?
    public let failReason: String?
    public let note: String?
    public let createdAt: Date?
    public let bankAccount: [String: String]?

    public init(
        id: Int64,
        amount: Int64,
        status: WithdrawalStatus = .created,
        channelWithdrawNo: String? = nil,
        failReason: String? = nil,
        note: String? = nil,
        createdAt: Date? = nil,
        bankAccount: [String: String]? = nil
    ) {
        self.id = id
        self.amount = amount
        self.status = status
        self.channelWithdrawNo = channelWithdrawNo
        self.failReason = failReason
        self.note = note
        self.createdAt = createdAt
        self.bankAccount = bankAccount
    }

    enum CodingKeys: String, CodingKey {
        case id, amount, status, channelWithdrawNo, failReason, note, createdAt, bankAccount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        amount = try c.decode(Int64.self, forKey: .amount)
        let raw = try c.decodeIfPresent(String.self, forKey: .status)
        status = WithdrawalStatus.normalize(raw) ?? .created
        channelWithdrawNo = try c.decodeIfPresent(String.self, forKey: .channelWithdrawNo)
        failReason = try c.decodeIfPresent(String.self, forKey: .failReason)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        bankAccount = try c.decodeIfPresent([String: String].self, forKey: .bankAccount)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(amount, forKey: .amount)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(channelWithdrawNo, forKey: .channelWithdrawNo)
        try c.encodeIfPresent(failReason, forKey: .failReason)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(bankAccount, forKey: .bankAccount)
    }

    public var statusLabel: String { status.displayLabel }

    public var failureDisplay: String? {
        if status != .failed { return nil }
        if let failReason, !failReason.isEmpty { return failReason }
        if let note, !note.isEmpty { return note }
        return WalletCopy.withdrawForbidden
    }

    /// Legacy pending approvals should prompt re-initiate (design §9).
    public var requiresReopenChannelWithdraw: Bool {
        // Only when server still echoes closed legacy pending with that note.
        note == WalletCopy.reopenChannelWithdraw
    }
}

/// Two-phase refund record for buyer progress UI (design §5.2 / §5.8 / §9).
public struct RefundProgress: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let orderId: Int64?
    public let amount: Int64
    public let status: RefundPhaseStatus
    public let isPartial: Bool?
    public let shareReturnId: Int64?
    public let channelRefundNo: String?
    public let reason: String?
    public let refundShipping: Bool?
    public let updatedAt: Date?

    public init(
        id: Int64,
        orderId: Int64? = nil,
        amount: Int64,
        status: RefundPhaseStatus = .created,
        isPartial: Bool? = nil,
        shareReturnId: Int64? = nil,
        channelRefundNo: String? = nil,
        reason: String? = nil,
        refundShipping: Bool? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.orderId = orderId
        self.amount = amount
        self.status = status
        self.isPartial = isPartial
        self.shareReturnId = shareReturnId
        self.channelRefundNo = channelRefundNo
        self.reason = reason
        self.refundShipping = refundShipping
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, orderId, amount, status, isPartial, shareReturnId
        case channelRefundNo, reason, refundShipping, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        orderId = try c.decodeIfPresent(Int64.self, forKey: .orderId)
        amount = try c.decode(Int64.self, forKey: .amount)
        let raw = try c.decodeIfPresent(String.self, forKey: .status)
        status = RefundPhaseStatus.normalize(raw) ?? .created
        isPartial = try c.decodeIfPresent(Bool.self, forKey: .isPartial)
        shareReturnId = try c.decodeIfPresent(Int64.self, forKey: .shareReturnId)
        channelRefundNo = try c.decodeIfPresent(String.self, forKey: .channelRefundNo)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        refundShipping = try c.decodeIfPresent(Bool.self, forKey: .refundShipping)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(orderId, forKey: .orderId)
        try c.encode(amount, forKey: .amount)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(isPartial, forKey: .isPartial)
        try c.encodeIfPresent(shareReturnId, forKey: .shareReturnId)
        try c.encodeIfPresent(channelRefundNo, forKey: .channelRefundNo)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encodeIfPresent(refundShipping, forKey: .refundShipping)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    public var needsShareReturn: Bool {
        if shareReturnId != nil { return true }
        switch status {
        case .waitingShareReturn, .blockedWaitingShare: return true
        case .created, .refunding, .succeeded, .refundFailed: return shareReturnId != nil
        }
    }

    public var progressIndex: Int {
        RefundProgressLogic.currentIndex(status: status, needsShareReturn: needsShareReturn)
    }

    public var headline: String { RefundProgressLogic.buyerHeadline(status: status) }
}

/// POST `/api/v1/orders/{id}/refunds` body (design §6).
public struct CreateRefundRequest: Codable, Equatable, Sendable {
    public var amount: Int64
    public var reason: String?
    public var refundShipping: Bool

    public init(amount: Int64, reason: String? = nil, refundShipping: Bool = WalletConfigDefaults.refundShippingDefault) {
        self.amount = amount
        self.reason = reason
        self.refundShipping = refundShipping
    }

    public var body: [String: Any?] {
        var map: [String: Any?] = [
            "amount": amount,
            "refund_shipping": refundShipping,
        ]
        if let reason, !reason.isEmpty { map["reason"] = reason }
        return map
    }
}
