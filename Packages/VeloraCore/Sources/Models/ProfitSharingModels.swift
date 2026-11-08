import Foundation

// MARK: - Profit sharing / sub-merchant (DES-v1.3-08-01 PAY-01/02/03 / D29)

/// Product defaults (design §6 / §15). Hot-config on server; client mirrors for UX.
public enum ProfitSharingConfigDefaults {
    public static let launchGateKey = "launch_gate.profit_sharing"
    public static let signedByKey = "gate.profit_sharing.signed_by"
    public static let shareRetryMax = 3
    public static let shareRetryBackoffSec = [60, 300, 1_800]
    public static let settleModeDefault = ProfitShareSettleMode.onConfirm
    public static let paymentStalePayingSec = 120
    public static let onboardingSignTimeoutDays = 7
    public static let shareQueryAfterSec = 60
    public static let notifySettledCode = "N-20"
    public static let meEntryKey = "sub_merchant"
    public static let platformFeeDescription = "毂毂平台服务费"
    /// Channel sign page stub when server has not yet returned `sign_url`.
    public static let channelSignStubURL = "https://pay.example.velora/sub-merchant/sign"
}

// MARK: - Sub-merchant status (PAY-02)

/// `sub_merchants.status` (design §4): draft → submitted → channel_reviewing → to_sign → finished; failed side-path.
public enum SubMerchantStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case draft
    case submitted
    case channelReviewing = "channel_reviewing"
    case toSign = "to_sign"
    case finished
    case failed

    /// Normalize API / legacy aliases (`reviewing`, `applying`, `pending_sign`, …).
    public static func normalize(_ raw: String?) -> SubMerchantStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = SubMerchantStatus(rawValue: s) { return exact }
        switch s {
        case "reviewing", "applying", "processing", "pending", "pending_review":
            return .channelReviewing
        case "pending_sign", "signing":
            return .toSign
        case "succeeded", "active", "done", "skipped_dev":
            return .finished
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .draft: return "未提交"
        case .submitted: return "已提交"
        case .channelReviewing: return "审核中"
        case .toSign: return "待签约"
        case .finished: return "已完成"
        case .failed: return "失败"
        }
    }

    public var isTerminalSuccess: Bool { self == .finished }
    public var isTerminalFailure: Bool { self == .failed }
    public var isTerminal: Bool { isTerminalSuccess || isTerminalFailure }
    public var allowsResubmit: Bool { self == .failed || self == .draft }
    public var blocksPublish: Bool { self != .finished }
    public var needsChannelSign: Bool { self == .toSign }
    public var isInReview: Bool { self == .submitted || self == .channelReviewing }

    /// Progress strip index into `SubMerchantProgressStep.allCases` (nil when failed / unknown).
    public var progressStepIndex: Int? {
        switch self {
        case .draft: return 0
        case .submitted: return 0
        case .channelReviewing: return 1
        case .toSign: return 2
        case .finished: return 3
        case .failed: return nil
        }
    }
}

/// Progress strip titles (design §9): 提交 / 审核 / 待签约 / 完成.
public enum SubMerchantProgressStep: String, Sendable, CaseIterable, Equatable {
    case submit
    case review
    case sign
    case done

    public var title: String {
        switch self {
        case .submit: return "提交"
        case .review: return "审核"
        case .sign: return "待签约"
        case .done: return "完成"
        }
    }

    public var statusWhenCurrent: SubMerchantStatus {
        switch self {
        case .submit: return .submitted
        case .review: return .channelReviewing
        case .sign: return .toSign
        case .done: return .finished
        }
    }
}

public enum SubMerchantProgressLogic {
    /// 0…3 for happy path; when failed, returns the step that failed (or 0).
    public static func currentIndex(status: SubMerchantStatus, failedAt: SubMerchantProgressStep? = nil) -> Int {
        if status == .failed {
            return failedAt.map { SubMerchantProgressStep.allCases.firstIndex(of: $0) ?? 0 } ?? 1
        }
        return status.progressStepIndex ?? 0
    }

    public static func isStepComplete(_ step: SubMerchantProgressStep, status: SubMerchantStatus) -> Bool {
        guard status != .failed else { return false }
        guard let idx = status.progressStepIndex else { return false }
        guard let stepIdx = SubMerchantProgressStep.allCases.firstIndex(of: step) else { return false }
        if status == .finished { return true }
        return stepIdx < idx
    }

    public static func isStepCurrent(_ step: SubMerchantProgressStep, status: SubMerchantStatus) -> Bool {
        if status == .failed { return false }
        if status == .draft { return step == .submit }
        guard let idx = status.progressStepIndex,
              let stepIdx = SubMerchantProgressStep.allCases.firstIndex(of: step) else { return false }
        if status == .finished { return step == .done }
        return stepIdx == idx
    }
}

// MARK: - Fail reasons (human-readable; never expose channel internal codes)

/// Mapped fail reasons for App (design §5.2 / §5.6 / §9).
public enum SubMerchantFailReason: String, Codable, Sendable, CaseIterable, Equatable {
    case blurryDocs = "blurry_docs"
    case nameMismatch = "name_mismatch"
    case signTimeout = "sign_timeout"
    case idNoConflict = "id_no_conflict"
    case onboardingFailed = "onboarding_failed"
    case kycRequired = "kyc_required"
    case other

    public static func normalize(_ raw: String?) -> SubMerchantFailReason? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = SubMerchantFailReason(rawValue: s) { return exact }
        // Heuristic map from free-text / ops templates.
        if s.contains("模糊") || s.contains("blur") || s.contains("unclear") { return .blurryDocs }
        if s.contains("名称") || s.contains("不符") || s.contains("mismatch") || s.contains("name") { return .nameMismatch }
        if s.contains("协议") || s.contains("签约") || s.contains("sign") || s.contains("timeout") { return .signTimeout }
        if s.contains("证件") || s.contains("id_no") || s.contains("conflict") { return .idNoConflict }
        if s.contains("实名") || s.contains("kyc") { return .kycRequired }
        if s.contains("进件") || s.contains("onboard") { return .onboardingFailed }
        return .other
    }

    public var displayMessage: String {
        switch self {
        case .blurryDocs: return "资料不清晰，请重新拍摄后提交"
        case .nameMismatch: return "名称与实名信息不符，请核对后重提"
        case .signTimeout: return "未在期限内完成渠道协议签约"
        case .idNoConflict: return "该证件已用于其他收款账户"
        case .onboardingFailed: return "进件未通过，请按提示修改资料"
        case .kycRequired: return "请先完成实名认证"
        case .other: return "进件未通过，可修改资料后重提"
        }
    }

    public var nextStepHint: String {
        switch self {
        case .signTimeout: return "请重新提交并完成签约"
        case .kycRequired: return "去实名"
        default: return ProfitSharingCopy.modifyMaterials
        }
    }
}

public enum SubMerchantType: String, Codable, Sendable, CaseIterable, Equatable {
    case personal
    case sole
    case enterprise

    public var displayLabel: String {
        switch self {
        case .personal: return "个人"
        case .sole: return "个体工商户"
        case .enterprise: return "企业"
        }
    }
}

// MARK: - Profit-share status (PAY-03 / T-05) — seller-facing labels

/// `profit_shares.status` (design §4): processing / partial / succeeded / failed (+ pending before channel submit).
public enum ProfitShareStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pending
    case processing
    case partial
    case succeeded
    case failed

    public static func normalize(_ raw: String?) -> ProfitShareStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ProfitShareStatus(rawValue: s) { return exact }
        switch s {
        case "creating", "queued": return .pending
        case "success", "settled", "done": return .succeeded
        case "error": return .failed
        default: return nil
        }
    }

    /// Seller-facing label (design §9): partial still 「结算中」; desk 「结算处理中，无需重试」.
    public var sellerLabel: String {
        sellerLabel(inReconcileDesk: false)
    }

    public func sellerLabel(inReconcileDesk: Bool) -> String {
        if inReconcileDesk || self == .failed {
            return ProfitSharingCopy.sellerSettlingManual
        }
        switch self {
        case .pending, .processing, .partial:
            return ProfitSharingCopy.sellerSettling
        case .succeeded:
            return ProfitSharingCopy.sellerSettled
        case .failed:
            return ProfitSharingCopy.sellerSettlingManual
        }
    }

    /// Never expose which receiver failed (design §9).
    public var exposesReceiverFailureToSeller: Bool { false }

    public var isSettlingForSeller: Bool {
        self == .pending || self == .processing || self == .partial || self == .failed
    }
}

public enum ProfitShareSettleMode: String, Codable, Sendable, CaseIterable, Equatable {
    case onConfirm = "on_confirm"
    case onShip = "on_ship"

    public var displayLabel: String {
        switch self {
        case .onConfirm: return "确认收货后分账"
        case .onShip: return "发货后分账"
        }
    }
}

public enum ProfitShareReceiverRole: String, Codable, Sendable, CaseIterable, Equatable {
    case seller
    case platform

    public var displayLabel: String {
        switch self {
        case .seller: return "卖家"
        case .platform: return "平台"
        }
    }
}

// MARK: - Error codes & gate messaging

/// Stable API error codes (design §6 / §7).
public enum ProfitSharingErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case missingIdempotencyKey = "missing_idempotency_key"
    case subMerchantRequired = "sub_merchant_required"
    case onboardingFailed = "onboarding_failed"
    case misconfiguredEscrow = "misconfigured_escrow"
    case launchGateClosed = "launch_gate_closed"
    case idNoConflict = "id_no_conflict"
    case alreadySettled = "already_settled"
    case amountMismatch = "amount_mismatch"
    case notifySignInvalid = "notify_sign_invalid"
    case kycRequired = "kyc_required"
    case retryExhausted = "retry_exhausted"
    case approvalRequired = "approval_required"

    public var fallbackMessage: String {
        switch self {
        case .missingIdempotencyKey: return "请重试"
        case .subMerchantRequired: return ProfitSharingCopy.publishGateTitle
        case .onboardingFailed: return SubMerchantFailReason.onboardingFailed.displayMessage
        case .misconfiguredEscrow: return "收款通道配置异常，暂不可付款"
        case .launchGateClosed: return ProfitSharingCopy.gateClosed
        case .idNoConflict: return SubMerchantFailReason.idNoConflict.displayMessage
        case .alreadySettled: return "该订单已结算"
        case .amountMismatch: return "支付金额不符，请稍后重试"
        case .notifySignInvalid: return "支付结果校验失败"
        case .kycRequired: return SubMerchantFailReason.kycRequired.displayMessage
        case .retryExhausted: return ProfitSharingCopy.sellerSettlingManual
        case .approvalRequired: return "需复核后处理"
        }
    }

    /// Publish preflight / submit → half-sheet CTA (design §9).
    public var opensSubMerchantProgress: Bool { self == .subMerchantRequired || self == .onboardingFailed }

    public var opensRealName: Bool { self == .kycRequired }
}

public enum ProfitSharingCopy {
    public static let progressTitle = "收款开户"
    public static let publishGateTitle = "完成收款开户"
    public static let publishGateMessage = "发布收款类商品前须完成二级商户进件。提交资料并签约后即可上架。"
    public static let publishGateCTA = "去开户"
    public static let modifyMaterials = "修改资料"
    public static let openSign = "打开签约页"
    public static let refreshAfterSign = "我已完成签约，刷新"
    public static let submitMaterials = "提交进件"
    public static let resubmit = "重新提交"
    public static let reviewingHint = "渠道审核中，请耐心等待，无需催促"
    public static let toSignHint = "请完成渠道协议签约，签约后状态会自动更新"
    public static let finishedHint = "收款账户已开通，可以发布并收款"
    public static let draftHint = "填写结算资料后提交渠道进件"
    public static let submittedHint = "资料已提交，等待渠道受理"
    public static let gateClosed = "收款通道即将开通"
    public static let gateClosedHint = "收付通验收完成后即可进件收款"
    public static let sellerSettling = "结算中"
    public static let sellerSettlingManual = "结算处理中，无需重试"
    public static let sellerSettled = "已到账"
    public static let weakNetworkHint = "以银行/微信支付宝结果为准"
    public static let emptyPaymentMethods = "暂不可付款"
    public static let channelSignStubTitle = "渠道签约（占位）"
    public static let channelSignStubMessage = "将打开渠道协议页完成签约；当前为占位链接。"
}

/// Publish / payment gate helper (design §5.2 / §9).
public enum ProfitSharingGate {
    /// Block publish when sub-merchant not finished (or missing).
    public static func publishBlocked(status: SubMerchantStatus?) -> Bool {
        guard let status else { return true }
        return status.blocksPublish
    }

    public static func publishBlockMessage(status: SubMerchantStatus?) -> String {
        if status == nil || status == .draft {
            return ProfitSharingCopy.publishGateMessage
        }
        if status == .failed {
            return SubMerchantFailReason.onboardingFailed.displayMessage
        }
        if status?.isInReview == true || status == .submitted {
            return ProfitSharingCopy.reviewingHint
        }
        if status == .toSign {
            return ProfitSharingCopy.toSignHint
        }
        return ProfitSharingCopy.publishGateMessage
    }

    /// Dual gate: `launch_gate.profit_sharing` + non-empty `signed_by` (design §5.9).
    public static func realFundsAllowed(launchGateOpen: Bool, signedBy: String?) -> Bool {
        launchGateOpen && !(signedBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func paymentGateError(launchGateOpen: Bool, signedBy: String?) -> ProfitSharingErrorCode? {
        realFundsAllowed(launchGateOpen: launchGateOpen, signedBy: signedBy) ? nil : .launchGateClosed
    }
}

// MARK: - DTOs

public struct SubMerchant: Codable, Equatable, Sendable, Identifiable {
    public var id: String { channelSubMchId ?? "\(status.rawValue)-\(merchantType?.rawValue ?? "unknown")" }
    public let status: SubMerchantStatus
    public let merchantType: SubMerchantType?
    public let channel: String?
    public let channelSubMchId: String?
    public let failReason: String?
    public let failReasonCode: String?
    public let signUrl: String?
    public let signedAt: Date?
    public let nameMasked: String?
    public let updatedAt: Date?

    public init(
        status: SubMerchantStatus = .draft,
        merchantType: SubMerchantType? = nil,
        channel: String? = nil,
        channelSubMchId: String? = nil,
        failReason: String? = nil,
        failReasonCode: String? = nil,
        signUrl: String? = nil,
        signedAt: Date? = nil,
        nameMasked: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.status = status
        self.merchantType = merchantType
        self.channel = channel
        self.channelSubMchId = channelSubMchId
        self.failReason = failReason
        self.failReasonCode = failReasonCode
        self.signUrl = signUrl
        self.signedAt = signedAt
        self.nameMasked = nameMasked
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case status, merchantType, channel, channelSubMchId
        case failReason, failReasonCode, signUrl, signedAt, nameMasked, updatedAt
        case subMchId, vendorId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawStatus = try c.decodeIfPresent(String.self, forKey: .status)
        status = SubMerchantStatus.normalize(rawStatus) ?? .draft
        if let t = try c.decodeIfPresent(String.self, forKey: .merchantType) {
            merchantType = SubMerchantType(rawValue: t)
        } else {
            merchantType = nil
        }
        channel = try c.decodeIfPresent(String.self, forKey: .channel)
        channelSubMchId = try c.decodeIfPresent(String.self, forKey: .channelSubMchId)
            ?? c.decodeIfPresent(String.self, forKey: .subMchId)
            ?? c.decodeIfPresent(String.self, forKey: .vendorId)
        failReason = try c.decodeIfPresent(String.self, forKey: .failReason)
        failReasonCode = try c.decodeIfPresent(String.self, forKey: .failReasonCode)
        signUrl = try c.decodeIfPresent(String.self, forKey: .signUrl)
        signedAt = try c.decodeIfPresent(Date.self, forKey: .signedAt)
        nameMasked = try c.decodeIfPresent(String.self, forKey: .nameMasked)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(merchantType?.rawValue, forKey: .merchantType)
        try c.encodeIfPresent(channel, forKey: .channel)
        try c.encodeIfPresent(channelSubMchId, forKey: .channelSubMchId)
        try c.encodeIfPresent(failReason, forKey: .failReason)
        try c.encodeIfPresent(failReasonCode, forKey: .failReasonCode)
        try c.encodeIfPresent(signUrl, forKey: .signUrl)
        try c.encodeIfPresent(signedAt, forKey: .signedAt)
        try c.encodeIfPresent(nameMasked, forKey: .nameMasked)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    public var resolvedFailReason: SubMerchantFailReason? {
        SubMerchantFailReason.normalize(failReasonCode) ?? SubMerchantFailReason.normalize(failReason)
    }

    public var failDisplayMessage: String? {
        if let code = resolvedFailReason { return code.displayMessage }
        if let failReason, !failReason.isEmpty {
            // Prefer server human text when present; strip obvious internal codes.
            if failReason.contains("_") && failReason == failReason.lowercased() {
                return SubMerchantFailReason.normalize(failReason)?.displayMessage ?? ProfitSharingCopy.publishGateMessage
            }
            return failReason
        }
        return status == .failed ? SubMerchantFailReason.other.displayMessage : nil
    }

    public var statusHint: String {
        switch status {
        case .draft: return ProfitSharingCopy.draftHint
        case .submitted: return ProfitSharingCopy.submittedHint
        case .channelReviewing: return ProfitSharingCopy.reviewingHint
        case .toSign: return ProfitSharingCopy.toSignHint
        case .finished: return ProfitSharingCopy.finishedHint
        case .failed: return failDisplayMessage ?? SubMerchantFailReason.other.displayMessage
        }
    }

    public var effectiveSignURL: URL? {
        if let signUrl, let url = URL(string: signUrl), !signUrl.isEmpty { return url }
        if status.needsChannelSign {
            return URL(string: ProfitSharingConfigDefaults.channelSignStubURL)
        }
        return nil
    }
}

/// POST `/api/v1/me/sub-merchant` body (design §5.6 / §6). Sensitive fields encrypted server-side.
public struct SubMerchantSubmitRequest: Codable, Equatable, Sendable {
    public var merchantType: SubMerchantType
    public var channel: String?
    public var bankCardLast4: String?
    public var bankName: String?
    public var licenseNo: String?
    public var settlementAccountMasked: String?
    /// Opaque client tokens for already-uploaded private-bucket image keys.
    public var imageKeys: [String]?

    public init(
        merchantType: SubMerchantType = .personal,
        channel: String? = nil,
        bankCardLast4: String? = nil,
        bankName: String? = nil,
        licenseNo: String? = nil,
        settlementAccountMasked: String? = nil,
        imageKeys: [String]? = nil
    ) {
        self.merchantType = merchantType
        self.channel = channel
        self.bankCardLast4 = bankCardLast4
        self.bankName = bankName
        self.licenseNo = licenseNo
        self.settlementAccountMasked = settlementAccountMasked
        self.imageKeys = imageKeys
    }

    public var body: [String: Any] {
        var map: [String: Any] = ["merchant_type": merchantType.rawValue]
        if let channel { map["channel"] = channel }
        if let bankCardLast4 { map["bank_card_last4"] = bankCardLast4 }
        if let bankName { map["bank_name"] = bankName }
        if let licenseNo { map["license_no"] = licenseNo }
        if let settlementAccountMasked { map["settlement_account_masked"] = settlementAccountMasked }
        if let imageKeys { map["image_keys"] = imageKeys }
        return map
    }
}

public struct ProfitShareSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String { shareId }
    public let shareId: String
    public let orderId: Int64?
    public let status: ProfitShareStatus
    public let sellerAmount: Int64?
    public let platformAmount: Int64?
    public let settleMode: ProfitShareSettleMode?
    public let retryCount: Int?
    public let inReconcileDesk: Bool?

    public init(
        shareId: String,
        orderId: Int64? = nil,
        status: ProfitShareStatus,
        sellerAmount: Int64? = nil,
        platformAmount: Int64? = nil,
        settleMode: ProfitShareSettleMode? = nil,
        retryCount: Int? = nil,
        inReconcileDesk: Bool? = nil
    ) {
        self.shareId = shareId
        self.orderId = orderId
        self.status = status
        self.sellerAmount = sellerAmount
        self.platformAmount = platformAmount
        self.settleMode = settleMode
        self.retryCount = retryCount
        self.inReconcileDesk = inReconcileDesk
    }

    public var sellerStatusLabel: String {
        status.sellerLabel(inReconcileDesk: inReconcileDesk == true)
    }
}

public enum ProfitShareSellerLogic {
    /// Map confirm / order projection fields to seller copy (design §9).
    public static func label(statusRaw: String?, inReconcileDesk: Bool = false) -> String {
        let status = ProfitShareStatus.normalize(statusRaw) ?? .processing
        return status.sellerLabel(inReconcileDesk: inReconcileDesk)
    }

    public static func label(from confirm: ConfirmOrderResultLike) -> String {
        label(statusRaw: confirm.profitShareStatusRaw, inReconcileDesk: false)
    }
}

/// Narrow surface so Shipment `ConfirmOrderResult` can feed seller labels without circular deps in tests.
public protocol ConfirmOrderResultLike {
    var profitShareStatusRaw: String? { get }
}

extension ConfirmOrderResult: ConfirmOrderResultLike {
    public var profitShareStatusRaw: String? { profitShareStatus }

    public var sellerProfitShareLabel: String {
        ProfitShareSellerLogic.label(statusRaw: profitShareStatus)
    }
}
