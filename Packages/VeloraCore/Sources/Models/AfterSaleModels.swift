import Foundation

// MARK: - After-sale negotiation / small court / appeal (DES-v1.3-09-02 AFS-04～10 / D34)

/// Product defaults (design §3). Hot-config on server; client mirrors for UX + gates.
public enum AfterSaleConfigDefaults {
    public static let sellerRespondHours = 48
    public static let appearanceWindowHours = 48
    public static let evidenceHours = 72
    public static let decideWorkdays = 5
    public static let appealHours = 72 // 3 × 24h
    public static let returnTrackingDays = 7
    public static let buyerOfferRespondHours = 24
    public static let evidenceExtendHours = 24
    public static let appearanceUnboxPhotosMin = 3
    public static let evidencePhotosMax = 9
    public static let reasonMinLength = 20
    public static let reasonMaxLength = 2000
    public static let otherWindowDays = 15
    public static let suspectedFakeWindowDays = 15
    public static let shipDeadlineFallbackDays = 10
    public static let decideDeadlineHourCST = 18
    public static let featureFlagSmallCourt = "small_court"
    public static let notifyCode = "N-21"
    public static let meEntryKey = "after_sale"
    public static let calendarSkipWeekends = true
    public static let calendarTZ = "Asia/Shanghai"
    /// Default B-11 / 6.15: 70% obligee / 30% platform on deposit forfeit.
    public static let penaltyObligeeBp = 7_000
    public static let penaltyPlatformBp = 3_000
    public static let creditDeltaHiddenFlaw = -20
    public static let creditDeltaBuyerDamage = -20
    public static let auctionPauseDaysFirst = 30
    public static let buyLimitDaysFirst = 30
    public static let buyLimitDaysRepeat = 180
}

// MARK: - Type / claim (AFS-04)

/// `after_sales.type` — no `no_reason_return` (B-09).
public enum AfterSaleType: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case notReceived = "not_received"
    case notAsDescribed = "not_as_described"
    case transitDamage = "transit_damage"
    case suspectedFake = "suspected_fake"
    case other

    public var id: String { rawValue }

    public static func normalize(_ raw: String?) -> AfterSaleType? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = AfterSaleType(rawValue: s) { return exact }
        switch s {
        case "not-received", "undelivered", "missing":
            return .notReceived
        case "not-as-described", "condition", "appearance", "品相":
            return .notAsDescribed
        case "transit-damage", "damage_in_transit", "运输损坏":
            return .transitDamage
        case "suspected-fake", "fake", "counterfeit", "假货":
            return .suspectedFake
        case "misc", "else":
            return .other
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .notReceived: return "未收到货"
        case .notAsDescribed: return "品相不符"
        case .transitDamage: return "运输损坏"
        case .suspectedFake: return "疑似假货"
        case .other: return "其他"
        }
    }

    /// 品相类 = 品相不符 + 运输损坏（48h + 开箱照门禁）。
    public var isAppearance: Bool {
        self == .notAsDescribed || self == .transitDamage
    }

    public var showsInClientPicker: Bool { true }
}

/// `after_sales.claim`
public enum AfterSaleClaim: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case refund
    case returnRefund = "return_refund"
    case partial

    public var id: String { rawValue }

    public static func normalize(_ raw: String?) -> AfterSaleClaim? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = AfterSaleClaim(rawValue: s) { return exact }
        switch s {
        case "full_refund", "full", "refund_only":
            return .refund
        case "return", "return_and_refund", "return-refund":
            return .returnRefund
        case "partial_refund", "part":
            return .partial
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .refund: return "仅退款"
        case .returnRefund: return "退货退款"
        case .partial: return "部分退款"
        }
    }
}

// MARK: - After-sale record status (7.7)

/// Fine-grained `after_sales.status` (parallel to order `after_sale_status`).
public enum AfterSaleCaseStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case requested
    case agreed
    case returnShipping = "return_shipping"
    case escalated
    case withdrawn
    case closed

    public static func normalize(_ raw: String?) -> AfterSaleCaseStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = AfterSaleCaseStatus(rawValue: s) { return exact }
        switch s {
        case "pending", "waiting_seller", "open":
            return .requested
        case "accepted", "approved", "timeout_agreed":
            return .agreed
        case "returning", "buyer_shipping", "return-shipping":
            return .returnShipping
        case "court", "arbitration", "small_court":
            return .escalated
        case "cancelled", "canceled", "revoked":
            return .withdrawn
        case "done", "finished", "resolved":
            return .closed
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .requested: return "待卖家处理"
        case .agreed: return "已同意"
        case .returnShipping: return "退货寄回中"
        case .escalated: return "小法庭处理中"
        case .withdrawn: return "已撤销"
        case .closed: return "已完结"
        }
    }

    public var isActive: Bool {
        switch self {
        case .requested, .agreed, .returnShipping, .escalated: return true
        case .withdrawn, .closed: return false
        }
    }

    public var isTerminal: Bool {
        self == .withdrawn || self == .closed
    }
}

// MARK: - Seller respond (AFS-05)

public enum SellerRespondAction: String, Codable, Sendable, CaseIterable, Equatable {
    case agree
    case reject
    case offer

    public static func normalize(_ raw: String?) -> SellerRespondAction? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = SellerRespondAction(rawValue: s) { return exact }
        switch s {
        case "accept", "approve": return .agree
        case "refuse", "deny": return .reject
        case "counter", "proposal", "scheme": return .offer
        default: return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .agree: return "同意"
        case .reject: return "拒绝"
        case .offer: return "提出方案"
        }
    }
}

// MARK: - Arbitration (AFS-06)

/// Case machine: open → evidence → deciding → closed; closed → appeal_review → closed(final).
public enum ArbitrationStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case open
    case evidence
    case deciding
    case closed
    case appealReview = "appeal_review"
    case unassigned

    public static func normalize(_ raw: String?) -> ArbitrationStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ArbitrationStatus(rawValue: s) { return exact }
        switch s {
        case "opened", "created": return .open
        case "evidencing", "supplement": return .evidence
        case "ruling", "judge", "in_decision": return .deciding
        case "done", "resolved", "finished": return .closed
        case "appeal", "appealing", "appeal-review", "review": return .appealReview
        case "pending_assign", "no_arbitrator": return .unassigned
        default: return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .open: return "立案中"
        case .evidence: return "举证中"
        case .deciding: return "裁定中"
        case .closed: return "已裁定"
        case .appealReview: return "申诉复核中"
        case .unassigned: return "待指派"
        }
    }

    public var allowsPartyEvidence: Bool { self == .evidence }

    public var isClosedLike: Bool { self == .closed || self == .appealReview }
}

/// Ruling templates (AFS-07 / AFS-10).
public enum RulingTemplate: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case hiddenFlaw = "hidden_flaw"
    case buyerDamage = "buyer_damage"
    case noFault = "no_fault"
    case settlement

    public var id: String { rawValue }

    public static func normalize(_ raw: String?) -> RulingTemplate? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = RulingTemplate(rawValue: s) { return exact }
        switch s {
        case "seller_fault", "conceal", "藏匿瑕疵": return .hiddenFlaw
        case "buyer_fault", "damage", "故意损坏": return .buyerDamage
        case "none", "mutual_none", "无责": return .noFault
        case "settle", "和解": return .settlement
        default: return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .hiddenFlaw: return "藏匿瑕疵"
        case .buyerDamage: return "买家损坏"
        case .noFault: return "双方无责"
        case .settlement: return "和解结案"
        }
    }
}

/// Orchestrator steps (design §5.12).
public enum PenaltyExecutionStep: String, Codable, Sendable, CaseIterable, Equatable {
    case refund
    case shareReturn = "share_return"
    case depositDeduct = "deposit_deduct"
    case credit
    case capability
    case blacklist

    public var displayLabel: String {
        switch self {
        case .refund: return "退款"
        case .shareReturn: return "分账回退"
        case .depositDeduct: return "保证金扣划"
        case .credit: return "信用分"
        case .capability: return "能力开关"
        case .blacklist: return "证件地址拉黑"
        }
    }
}

public enum PenaltyExecutionStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pending
    case succeeded
    case failed
    case skipped

    public static func normalize(_ raw: String?) -> PenaltyExecutionStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        return PenaltyExecutionStatus(rawValue: raw.lowercased())
    }

    public var displayLabel: String {
        switch self {
        case .pending: return "待执行"
        case .succeeded: return "已成功"
        case .failed: return "失败"
        case .skipped: return "已跳过"
        }
    }
}

// MARK: - Error codes (design §5.13)

public enum AfterSaleErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case afterSaleWindowElapsed = "after_sale_window_elapsed"
    case unboxPhotosRequired = "unbox_photos_required"
    case afterSaleExists = "after_sale_exists"
    case claimAmountInvalid = "claim_amount_invalid"
    case sellerRespondTimeout = "seller_respond_timeout"
    case cannotEscalate = "cannot_escalate"
    case evidencePeriodClosed = "evidence_period_closed"
    case appealWindowElapsed = "appeal_window_elapsed"
    case appealAlreadyUsed = "appeal_already_used"
    case rulingPenaltyMismatch = "ruling_penalty_mismatch"
    case courtNotEnabled = "court_not_enabled"
    case arbitratorUnavailable = "arbitrator_unavailable"
    case refundAlreadyProcessing = "refund_already_processing"
    case offerExpired = "offer_expired"
    case notReturnClaim = "not_return_claim"
    case missingIdempotencyKey = "missing_idempotency_key"
    case realNameRequired = "real_name_required"
    case accountRestricted = "account_restricted"
    case unauthenticated = "unauthenticated"
    case notOrderParty = "not_order_party"
    case forbidden = "forbidden"
    case reasonTooShort = "reason_too_short"
    case reasonTooLong = "reason_too_long"

    public static func normalize(_ raw: String?) -> AfterSaleErrorCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = AfterSaleErrorCode(rawValue: s) { return exact }
        switch s {
        case "window_elapsed", "appearance_window_elapsed":
            return .afterSaleWindowElapsed
        case "unbox_required", "evidence_photos_incomplete":
            return .unboxPhotosRequired
        case "already_exists", "aftersale_exists", "duplicate_after_sale":
            return .afterSaleExists
        case "invalid_claim_amount", "amount_invalid":
            return .claimAmountInvalid
        case "seller_timeout", "auto_agreed":
            return .sellerRespondTimeout
        case "escalate_forbidden", "cannot_escalate_timeout_agree":
            return .cannotEscalate
        case "evidence_closed", "supplement_closed":
            return .evidencePeriodClosed
        case "appeal_expired", "appeal_timeout":
            return .appealWindowElapsed
        case "already_appealed", "appeal_used":
            return .appealAlreadyUsed
        case "penalty_mismatch", "ruling_mismatch":
            return .rulingPenaltyMismatch
        case "small_court_disabled", "court_disabled":
            return .courtNotEnabled
        case "no_arbitrator", "arbitrator_unavailable":
            return .arbitratorUnavailable
        case "refund_processing", "cannot_withdraw":
            return .refundAlreadyProcessing
        case "http_401", "401":
            return .unauthenticated
        case "http_403", "403":
            return .forbidden
        case "http_404", "404":
            return .notOrderParty
        case "need_real_name", "realname_required":
            return .realNameRequired
        case "account_frozen", "restricted":
            return .accountRestricted
        default:
            return nil
        }
    }

    public var fallbackMessage: String {
        switch self {
        case .afterSaleWindowElapsed: return AfterSaleCopy.windowElapsed
        case .unboxPhotosRequired: return AfterSaleCopy.unboxPhotosRequired
        case .afterSaleExists: return AfterSaleCopy.afterSaleExists
        case .claimAmountInvalid: return AfterSaleCopy.claimAmountInvalid
        case .sellerRespondTimeout: return AfterSaleCopy.sellerRespondTimeout
        case .cannotEscalate: return AfterSaleCopy.cannotEscalate
        case .evidencePeriodClosed: return AfterSaleCopy.evidencePeriodClosed
        case .appealWindowElapsed: return AfterSaleCopy.appealWindowElapsed
        case .appealAlreadyUsed: return AfterSaleCopy.appealAlreadyUsed
        case .rulingPenaltyMismatch: return AfterSaleCopy.rulingPenaltyMismatch
        case .courtNotEnabled: return AfterSaleCopy.courtNotEnabled
        case .arbitratorUnavailable: return AfterSaleCopy.arbitratorUnavailable
        case .refundAlreadyProcessing: return AfterSaleCopy.refundAlreadyProcessing
        case .offerExpired: return AfterSaleCopy.offerExpired
        case .notReturnClaim: return AfterSaleCopy.notReturnClaim
        case .missingIdempotencyKey: return AfterSaleCopy.missingIdempotencyKey
        case .realNameRequired: return AfterSaleCopy.realNameRequired
        case .accountRestricted: return AfterSaleCopy.accountRestricted
        case .unauthenticated: return AfterSaleCopy.unauthenticated
        case .notOrderParty: return AfterSaleCopy.notOrderParty
        case .forbidden: return AfterSaleCopy.forbidden
        case .reasonTooShort: return AfterSaleCopy.reasonTooShort
        case .reasonTooLong: return AfterSaleCopy.reasonTooLong
        }
    }

    public var opensRealName: Bool { self == .realNameRequired }
    public var suggestsSuspectedFake: Bool { self == .afterSaleWindowElapsed }
    public var opensUnboxCapture: Bool { self == .unboxPhotosRequired }
}

// MARK: - UX copy (design §9)

public enum AfterSaleCopy {
    public static let applyTitle = "申请售后"
    public static let applyEmptyHint = "签收后 48 小时内可申请品相问题"
    public static let detailTitle = "售后详情"
    public static let courtTitle = "小法庭"
    public static let rulingTitle = "裁定结果"
    public static let appealTitle = "申诉"
    public static let evidenceTitle = "补充举证"
    public static let serverTimeHint = "以服务器时间为准"
    public static let sellerRemainPrefix = "卖家剩余"
    public static let evidenceRemainPrefix = "举证剩余"
    public static let appealRemainPrefix = "申诉剩余"
    public static let decideRemainPrefix = "裁定时限"
    public static let submitLocked = "提交中…"
    public static let escalateCTA = "升级小法庭"
    public static let withdrawCTA = "撤销申请"
    public static let acceptOfferCTA = "接受方案"
    public static let returnTrackingCTA = "填写退货单号"
    public static let appealCTA = "我要申诉"
    public static let attachEvidenceCTA = "补充材料"
    public static let viewRulingCTA = "查看裁定"
    public static let noReasonReturnHidden = "不适用七天无理由退货"
    public static let windowElapsed = "品相申请已超过 48 小时，可改选「疑似假货」或联系客服"
    public static let unboxPhotosRequired = "品相类售后需至少 3 张开箱照片，请先去拍摄"
    public static let afterSaleExists = "该订单已有进行中的售后"
    public static let claimAmountInvalid = "退款金额不符合规则"
    public static let sellerRespondTimeout = "卖家已超时，系统已按买家方案同意"
    public static let cannotEscalate = "当前状态不可升级小法庭"
    public static let evidencePeriodClosed = "举证已结束，无法再补充材料"
    public static let appealWindowElapsed = "申诉窗口已过"
    public static let appealAlreadyUsed = "本案已申诉，不可再次申诉"
    public static let rulingPenaltyMismatch = "裁定模板与处罚勾选不一致"
    public static let courtNotEnabled = "小法庭暂未开放"
    public static let arbitratorUnavailable = "暂无可用仲裁员，请稍后再试"
    public static let refundAlreadyProcessing = "退款处理中，不可撤销"
    public static let offerExpired = "卖家方案已失效"
    public static let notReturnClaim = "非退货退款诉求，无需填写单号"
    public static let missingIdempotencyKey = "缺少幂等键"
    public static let realNameRequired = "请先完成实名认证"
    public static let accountRestricted = "账号受限，暂不可发起售后"
    public static let unauthenticated = "请先登录"
    public static let notOrderParty = "无权查看该售后"
    public static let forbidden = "无权操作"
    public static let reasonTooShort = "理由至少 20 字"
    public static let reasonTooLong = "理由最多 2000 字"
    public static let appealReasonPlaceholder = "请说明不服裁定的理由（至少 20 字）"
    public static let rulingReasonLabel = "裁定理由"
    public static let penaltiesLabel = "处罚执行"
    public static let absentFlagLabel = "缺席认定"
    public static let timeoutAgreeBadge = "超时视同意"
    public static let packetIncomplete = "附卷不完整"
    public static let finalBadge = "终局"

    /// 不利推定条（AFS-07）：强制验车且无一致发货视频。
    public static let adverseInferenceBanner =
        "强制验车订单缺少一致发货视频，系统建议按「藏匿瑕疵」不利推定；仲裁员可推翻但须另写理由。"
    public static let adverseInferenceShort = "不利推定：建议藏匿瑕疵"
    public static let adverseInferenceOverridden = "仲裁员已推翻不利推定"
    /// B-16：买家未录开箱视频不作对称推定。
    public static let noBuyerVideoPresumption = "买家未登记开箱视频不作损坏推定"

    public static let typePickerHint = "请选择售后类型（不含七天无理由）"
    public static let claimPickerHint = "请选择诉求"
    public static let reasonPlaceholder = "请描述问题（纯文本）"
}

// MARK: - Seller offer snapshot

public struct SellerOffer: Codable, Equatable, Sendable, Hashable {
    public let claim: AfterSaleClaim
    public let amountCents: Int64
    public let note: String?
    public let offeredAt: Date?

    public init(
        claim: AfterSaleClaim,
        amountCents: Int64,
        note: String? = nil,
        offeredAt: Date? = nil
    ) {
        self.claim = claim
        self.amountCents = amountCents
        self.note = note
        self.offeredAt = offeredAt
    }

    enum CodingKeys: String, CodingKey {
        case claim, amountCents, note, offeredAt
        case claimAmountCents, amount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let claimRaw = try c.decodeIfPresent(String.self, forKey: .claim) ?? "partial"
        claim = AfterSaleClaim.normalize(claimRaw) ?? .partial
        amountCents = try c.decodeIfPresent(Int64.self, forKey: .amountCents)
            ?? c.decodeIfPresent(Int64.self, forKey: .claimAmountCents)
            ?? c.decodeIfPresent(Int64.self, forKey: .amount)
            ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note)
        offeredAt = try c.decodeIfPresent(Date.self, forKey: .offeredAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(claim.rawValue, forKey: .claim)
        try c.encode(amountCents, forKey: .amountCents)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(offeredAt, forKey: .offeredAt)
    }
}

// MARK: - After-sale record

public struct AfterSale: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let orderId: Int64
    public let buyerId: Int64?
    public let sellerId: Int64?
    public let type: AfterSaleType
    public let claim: AfterSaleClaim
    public let claimAmountCents: Int64
    public let reason: String?
    public let status: AfterSaleCaseStatus
    public let sellerDueAt: Date?
    public let sellerOffer: SellerOffer?
    public let agreedAmountCents: Int64?
    public let returnTracking: String?
    public let evidencePhotoIds: [Int64]?
    public let unboxSkipped: Bool?
    public let arbitrationId: Int64?
    public let timeoutAgree: Bool?
    public let version: Int64?
    public let serverTime: Date?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: Int64,
        orderId: Int64,
        buyerId: Int64? = nil,
        sellerId: Int64? = nil,
        type: AfterSaleType,
        claim: AfterSaleClaim,
        claimAmountCents: Int64,
        reason: String? = nil,
        status: AfterSaleCaseStatus,
        sellerDueAt: Date? = nil,
        sellerOffer: SellerOffer? = nil,
        agreedAmountCents: Int64? = nil,
        returnTracking: String? = nil,
        evidencePhotoIds: [Int64]? = nil,
        unboxSkipped: Bool? = nil,
        arbitrationId: Int64? = nil,
        timeoutAgree: Bool? = nil,
        version: Int64? = nil,
        serverTime: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.orderId = orderId
        self.buyerId = buyerId
        self.sellerId = sellerId
        self.type = type
        self.claim = claim
        self.claimAmountCents = claimAmountCents
        self.reason = reason
        self.status = status
        self.sellerDueAt = sellerDueAt
        self.sellerOffer = sellerOffer
        self.agreedAmountCents = agreedAmountCents
        self.returnTracking = returnTracking
        self.evidencePhotoIds = evidencePhotoIds
        self.unboxSkipped = unboxSkipped
        self.arbitrationId = arbitrationId
        self.timeoutAgree = timeoutAgree
        self.version = version
        self.serverTime = serverTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, orderId, buyerId, sellerId, type, claim, claimAmountCents, reason, status
        case sellerDueAt, sellerOffer, sellerOfferJson, agreedAmountCents, returnTracking
        case evidencePhotoIds, unboxSkipped, arbitrationId, timeoutAgree, version
        case serverTime, createdAt, updatedAt
        case ruleSnapshot
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        orderId = try c.decode(Int64.self, forKey: .orderId)
        buyerId = try c.decodeIfPresent(Int64.self, forKey: .buyerId)
        sellerId = try c.decodeIfPresent(Int64.self, forKey: .sellerId)
        let typeRaw = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        type = AfterSaleType.normalize(typeRaw) ?? .other
        let claimRaw = try c.decodeIfPresent(String.self, forKey: .claim) ?? "refund"
        claim = AfterSaleClaim.normalize(claimRaw) ?? .refund
        claimAmountCents = try c.decodeIfPresent(Int64.self, forKey: .claimAmountCents) ?? 0
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        let statusRaw = try c.decodeIfPresent(String.self, forKey: .status) ?? "requested"
        status = AfterSaleCaseStatus.normalize(statusRaw) ?? .requested
        sellerDueAt = try c.decodeIfPresent(Date.self, forKey: .sellerDueAt)
        if let offer = try c.decodeIfPresent(SellerOffer.self, forKey: .sellerOffer) {
            sellerOffer = offer
        } else {
            sellerOffer = try c.decodeIfPresent(SellerOffer.self, forKey: .sellerOfferJson)
        }
        agreedAmountCents = try c.decodeIfPresent(Int64.self, forKey: .agreedAmountCents)
        returnTracking = try c.decodeIfPresent(String.self, forKey: .returnTracking)
        evidencePhotoIds = try c.decodeIfPresent([Int64].self, forKey: .evidencePhotoIds)
        unboxSkipped = try c.decodeIfPresent(Bool.self, forKey: .unboxSkipped)
        arbitrationId = try c.decodeIfPresent(Int64.self, forKey: .arbitrationId)
        if let t = try c.decodeIfPresent(Bool.self, forKey: .timeoutAgree) {
            timeoutAgree = t
        } else if let snap = try c.decodeIfPresent([String: Bool].self, forKey: .ruleSnapshot) {
            timeoutAgree = snap["timeout_agree"]
        } else {
            timeoutAgree = nil
        }
        version = try c.decodeIfPresent(Int64.self, forKey: .version)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(orderId, forKey: .orderId)
        try c.encodeIfPresent(buyerId, forKey: .buyerId)
        try c.encodeIfPresent(sellerId, forKey: .sellerId)
        try c.encode(type.rawValue, forKey: .type)
        try c.encode(claim.rawValue, forKey: .claim)
        try c.encode(claimAmountCents, forKey: .claimAmountCents)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(sellerDueAt, forKey: .sellerDueAt)
        try c.encodeIfPresent(sellerOffer, forKey: .sellerOffer)
        try c.encodeIfPresent(agreedAmountCents, forKey: .agreedAmountCents)
        try c.encodeIfPresent(returnTracking, forKey: .returnTracking)
        try c.encodeIfPresent(evidencePhotoIds, forKey: .evidencePhotoIds)
        try c.encodeIfPresent(unboxSkipped, forKey: .unboxSkipped)
        try c.encodeIfPresent(arbitrationId, forKey: .arbitrationId)
        try c.encodeIfPresent(timeoutAgree, forKey: .timeoutAgree)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encodeIfPresent(serverTime, forKey: .serverTime)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    public var statusLabel: String { status.displayLabel }
    public var typeLabel: String { type.displayLabel }
    public var claimLabel: String { claim.displayLabel }
    public var showsTimeoutAgreeBadge: Bool { timeoutAgree == true }
}

// MARK: - Arbitration case

public struct ArbitrationPenaltyItem: Codable, Equatable, Sendable, Hashable, Identifiable {
    public var id: String { "\(step.rawValue)-\(status.rawValue)" }
    public let step: PenaltyExecutionStep
    public let status: PenaltyExecutionStatus
    public let label: String?
    public let detail: String?

    public init(
        step: PenaltyExecutionStep,
        status: PenaltyExecutionStatus,
        label: String? = nil,
        detail: String? = nil
    ) {
        self.step = step
        self.status = status
        self.label = label
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey {
        case step, status, label, detail, service
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let stepRaw = try c.decodeIfPresent(String.self, forKey: .step)
            ?? c.decodeIfPresent(String.self, forKey: .service)
            ?? "refund"
        step = PenaltyExecutionStep(rawValue: stepRaw) ?? .refund
        let statusRaw = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        status = PenaltyExecutionStatus.normalize(statusRaw) ?? .pending
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? step.displayLabel
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(step.rawValue, forKey: .step)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(detail, forKey: .detail)
    }

    public var displayLabel: String { label ?? step.displayLabel }
}

public struct ArbitrationEvidence: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let arbitrationId: Int64?
    public let uploaderId: Int64?
    public let kind: String?
    public let refId: Int64?
    public let note: String?
    public let absentFlag: Bool?
    public let imageUrls: [String]?
    public let createdAt: Date?

    public init(
        id: Int64,
        arbitrationId: Int64? = nil,
        uploaderId: Int64? = nil,
        kind: String? = nil,
        refId: Int64? = nil,
        note: String? = nil,
        absentFlag: Bool? = nil,
        imageUrls: [String]? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.arbitrationId = arbitrationId
        self.uploaderId = uploaderId
        self.kind = kind
        self.refId = refId
        self.note = note
        self.absentFlag = absentFlag
        self.imageUrls = imageUrls
        self.createdAt = createdAt
    }
}

public struct Arbitration: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let afterSaleId: Int64?
    public let orderId: Int64
    public let status: ArbitrationStatus
    public let arbitratorId: Int64?
    public let evidenceDeadline: Date?
    public let decideDeadline: Date?
    public let rulingTemplate: RulingTemplate?
    public let rulingReason: String?
    public let penalties: [ArbitrationPenaltyItem]?
    public let appealOf: Int64?
    public let appealedAt: Date?
    public let appealDeadline: Date?
    public let final: Bool
    public let decidedAt: Date?
    public let adverseInference: Bool?
    public let adverseInferenceOverridden: Bool?
    public let buyerAbsent: Bool?
    public let sellerAbsent: Bool?
    public let packetIncomplete: Bool?
    public let evidences: [ArbitrationEvidence]?
    public let version: Int64?
    public let serverTime: Date?

    public init(
        id: Int64,
        afterSaleId: Int64? = nil,
        orderId: Int64,
        status: ArbitrationStatus,
        arbitratorId: Int64? = nil,
        evidenceDeadline: Date? = nil,
        decideDeadline: Date? = nil,
        rulingTemplate: RulingTemplate? = nil,
        rulingReason: String? = nil,
        penalties: [ArbitrationPenaltyItem]? = nil,
        appealOf: Int64? = nil,
        appealedAt: Date? = nil,
        appealDeadline: Date? = nil,
        final: Bool = false,
        decidedAt: Date? = nil,
        adverseInference: Bool? = nil,
        adverseInferenceOverridden: Bool? = nil,
        buyerAbsent: Bool? = nil,
        sellerAbsent: Bool? = nil,
        packetIncomplete: Bool? = nil,
        evidences: [ArbitrationEvidence]? = nil,
        version: Int64? = nil,
        serverTime: Date? = nil
    ) {
        self.id = id
        self.afterSaleId = afterSaleId
        self.orderId = orderId
        self.status = status
        self.arbitratorId = arbitratorId
        self.evidenceDeadline = evidenceDeadline
        self.decideDeadline = decideDeadline
        self.rulingTemplate = rulingTemplate
        self.rulingReason = rulingReason
        self.penalties = penalties
        self.appealOf = appealOf
        self.appealedAt = appealedAt
        self.appealDeadline = appealDeadline
        self.final = final
        self.decidedAt = decidedAt
        self.adverseInference = adverseInference
        self.adverseInferenceOverridden = adverseInferenceOverridden
        self.buyerAbsent = buyerAbsent
        self.sellerAbsent = sellerAbsent
        self.packetIncomplete = packetIncomplete
        self.evidences = evidences
        self.version = version
        self.serverTime = serverTime
    }

    enum CodingKeys: String, CodingKey {
        case id, afterSaleId, orderId, status, arbitratorId
        case evidenceDeadline, decideDeadline, rulingTemplate, rulingReason
        case penalties, penaltiesJson, appealOf, appealedAt, appealDeadline
        case final, decidedAt, adverseInference, adverseInferenceOverridden
        case buyerAbsent, sellerAbsent, packetIncomplete, evidences, version, serverTime
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        afterSaleId = try c.decodeIfPresent(Int64.self, forKey: .afterSaleId)
        orderId = try c.decode(Int64.self, forKey: .orderId)
        let statusRaw = try c.decodeIfPresent(String.self, forKey: .status) ?? "open"
        status = ArbitrationStatus.normalize(statusRaw) ?? .open
        arbitratorId = try c.decodeIfPresent(Int64.self, forKey: .arbitratorId)
        evidenceDeadline = try c.decodeIfPresent(Date.self, forKey: .evidenceDeadline)
        decideDeadline = try c.decodeIfPresent(Date.self, forKey: .decideDeadline)
        if let t = try c.decodeIfPresent(String.self, forKey: .rulingTemplate) {
            rulingTemplate = RulingTemplate.normalize(t)
        } else {
            rulingTemplate = nil
        }
        rulingReason = try c.decodeIfPresent(String.self, forKey: .rulingReason)
        if let p = try c.decodeIfPresent([ArbitrationPenaltyItem].self, forKey: .penalties) {
            penalties = p
        } else {
            penalties = try c.decodeIfPresent([ArbitrationPenaltyItem].self, forKey: .penaltiesJson)
        }
        appealOf = try c.decodeIfPresent(Int64.self, forKey: .appealOf)
        appealedAt = try c.decodeIfPresent(Date.self, forKey: .appealedAt)
        appealDeadline = try c.decodeIfPresent(Date.self, forKey: .appealDeadline)
        final = try c.decodeIfPresent(Bool.self, forKey: .final) ?? false
        decidedAt = try c.decodeIfPresent(Date.self, forKey: .decidedAt)
        adverseInference = try c.decodeIfPresent(Bool.self, forKey: .adverseInference)
        adverseInferenceOverridden = try c.decodeIfPresent(Bool.self, forKey: .adverseInferenceOverridden)
        buyerAbsent = try c.decodeIfPresent(Bool.self, forKey: .buyerAbsent)
        sellerAbsent = try c.decodeIfPresent(Bool.self, forKey: .sellerAbsent)
        packetIncomplete = try c.decodeIfPresent(Bool.self, forKey: .packetIncomplete)
        evidences = try c.decodeIfPresent([ArbitrationEvidence].self, forKey: .evidences)
        version = try c.decodeIfPresent(Int64.self, forKey: .version)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(afterSaleId, forKey: .afterSaleId)
        try c.encode(orderId, forKey: .orderId)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(arbitratorId, forKey: .arbitratorId)
        try c.encodeIfPresent(evidenceDeadline, forKey: .evidenceDeadline)
        try c.encodeIfPresent(decideDeadline, forKey: .decideDeadline)
        try c.encodeIfPresent(rulingTemplate?.rawValue, forKey: .rulingTemplate)
        try c.encodeIfPresent(rulingReason, forKey: .rulingReason)
        try c.encodeIfPresent(penalties, forKey: .penalties)
        try c.encodeIfPresent(appealOf, forKey: .appealOf)
        try c.encodeIfPresent(appealedAt, forKey: .appealedAt)
        try c.encodeIfPresent(appealDeadline, forKey: .appealDeadline)
        try c.encode(final, forKey: .final)
        try c.encodeIfPresent(decidedAt, forKey: .decidedAt)
        try c.encodeIfPresent(adverseInference, forKey: .adverseInference)
        try c.encodeIfPresent(adverseInferenceOverridden, forKey: .adverseInferenceOverridden)
        try c.encodeIfPresent(buyerAbsent, forKey: .buyerAbsent)
        try c.encodeIfPresent(sellerAbsent, forKey: .sellerAbsent)
        try c.encodeIfPresent(packetIncomplete, forKey: .packetIncomplete)
        try c.encodeIfPresent(evidences, forKey: .evidences)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encodeIfPresent(serverTime, forKey: .serverTime)
    }

    public var statusLabel: String { status.displayLabel }
    public var templateLabel: String? { rulingTemplate?.displayLabel }
    public var showsAdverseBanner: Bool {
        adverseInference == true && adverseInferenceOverridden != true
    }
    public var canPartyAppeal: Bool {
        AfterSaleLogic.canAppeal(
            status: status,
            final: final,
            appealOf: appealOf,
            appealDeadline: appealDeadline,
            now: serverTime ?? Date()
        ) == nil
    }
}

// MARK: - Request bodies

public struct CreateAfterSaleRequest: Equatable, Sendable {
    public let type: AfterSaleType
    public let claim: AfterSaleClaim
    public let claimAmountCents: Int64
    public let reason: String
    public let unboxPhotoIds: [Int64]

    public init(
        type: AfterSaleType,
        claim: AfterSaleClaim,
        claimAmountCents: Int64,
        reason: String,
        unboxPhotoIds: [Int64] = []
    ) {
        self.type = type
        self.claim = claim
        self.claimAmountCents = claimAmountCents
        self.reason = reason
        self.unboxPhotoIds = unboxPhotoIds
    }

    public var body: [String: Any?] {
        [
            "type": type.rawValue,
            "claim": claim.rawValue,
            "claim_amount_cents": claimAmountCents,
            "reason": reason,
            "unbox_photo_ids": unboxPhotoIds,
        ]
    }
}

public struct SellerRespondRequest: Equatable, Sendable {
    public let action: SellerRespondAction
    public let claim: AfterSaleClaim?
    public let amountCents: Int64?
    public let reason: String?

    public init(
        action: SellerRespondAction,
        claim: AfterSaleClaim? = nil,
        amountCents: Int64? = nil,
        reason: String? = nil
    ) {
        self.action = action
        self.claim = claim
        self.amountCents = amountCents
        self.reason = reason
    }

    public var body: [String: Any?] {
        var d: [String: Any?] = ["action": action.rawValue]
        if let claim { d["claim"] = claim.rawValue }
        if let amountCents { d["claim_amount_cents"] = amountCents }
        if let reason, !reason.isEmpty { d["reason"] = reason }
        return d
    }
}

public struct ArbitrationEvidenceRequest: Equatable, Sendable {
    public let note: String?
    public let photoIds: [Int64]

    public init(note: String? = nil, photoIds: [Int64] = []) {
        self.note = note
        self.photoIds = photoIds
    }

    public var body: [String: Any?] {
        [
            "note": note,
            "photo_ids": photoIds,
        ]
    }
}

public struct ArbitrationAppealRequest: Equatable, Sendable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public var body: [String: Any?] {
        ["reason": reason]
    }
}

// MARK: - Domain logic

public enum AfterSaleLogic {

    // MARK: Windows (AFS-04)

    /// Appearance (品相) window from signed_at + 48h. Missing signedAt → blocked (引导确认签收).
    public static func appearanceWindowOpen(
        signedAt: Date?,
        now: Date = Date(),
        windowHours: Int = AfterSaleConfigDefaults.appearanceWindowHours
    ) -> Bool {
        guard let signedAt else { return false }
        return now <= signedAt.addingTimeInterval(TimeInterval(windowHours * 3600))
    }

    public static func suspectedFakeWindowOpen(
        signedAt: Date?,
        now: Date = Date(),
        windowDays: Int = AfterSaleConfigDefaults.suspectedFakeWindowDays
    ) -> Bool {
        guard let signedAt else { return false }
        return now <= signedAt.addingTimeInterval(TimeInterval(windowDays * 86_400))
    }

    public static func otherWindowOpen(
        signedAt: Date?,
        now: Date = Date(),
        windowDays: Int = AfterSaleConfigDefaults.otherWindowDays
    ) -> Bool {
        guard let signedAt else { return false }
        return now <= signedAt.addingTimeInterval(TimeInterval(windowDays * 86_400))
    }

    /// Client gate before POST create. Server remains authoritative.
    public static func createGate(
        type: AfterSaleType,
        orderStatus: String,
        afterSaleStatus: String,
        signedAt: Date?,
        shipDeadline: Date?,
        unboxPhotoCount: Int,
        claim: AfterSaleClaim,
        claimAmountCents: Int64,
        remainingPayableCents: Int64,
        isLoggedIn: Bool,
        isRealNamed: Bool,
        accountRestricted: Bool,
        now: Date = Date()
    ) -> AfterSaleErrorCode? {
        if !isLoggedIn { return .unauthenticated }
        if !isRealNamed { return .realNameRequired }
        if accountRestricted { return .accountRestricted }
        if afterSaleStatus == "processing" { return .afterSaleExists }

        let status = orderStatus.lowercased()
        switch type {
        case .notReceived:
            let paidOverdue = status == "paid" && (shipDeadline.map { now > $0 } ?? false)
            let shippedOrDone = status == "shipped" || status == "completed" || status == "settled"
            if !paidOverdue && !shippedOrDone { return .forbidden }
        case .notAsDescribed, .transitDamage:
            if status != "shipped" && status != "completed" && status != "settled" {
                return .forbidden
            }
            if !appearanceWindowOpen(signedAt: signedAt, now: now) {
                return .afterSaleWindowElapsed
            }
            if unboxPhotoCount < AfterSaleConfigDefaults.appearanceUnboxPhotosMin {
                return .unboxPhotosRequired
            }
        case .suspectedFake:
            if status != "shipped" && status != "completed" && status != "settled" {
                return .forbidden
            }
            if !suspectedFakeWindowOpen(signedAt: signedAt, now: now) {
                return .afterSaleWindowElapsed
            }
        case .other:
            if status != "shipped" && status != "completed" && status != "settled" {
                return .forbidden
            }
            if !otherWindowOpen(signedAt: signedAt, now: now) {
                return .afterSaleWindowElapsed
            }
        }

        return claimAmountError(
            claim: claim,
            claimAmountCents: claimAmountCents,
            remainingPayableCents: remainingPayableCents
        )
    }

    public static func claimAmountError(
        claim: AfterSaleClaim,
        claimAmountCents: Int64,
        remainingPayableCents: Int64
    ) -> AfterSaleErrorCode? {
        guard remainingPayableCents > 0 else { return .claimAmountInvalid }
        switch claim {
        case .refund, .returnRefund:
            if claimAmountCents != remainingPayableCents { return .claimAmountInvalid }
        case .partial:
            if claimAmountCents <= 0 || claimAmountCents >= remainingPayableCents {
                return .claimAmountInvalid
            }
        }
        return nil
    }

    public static func selectableTypes(excludeNoReasonReturn: Bool = true) -> [AfterSaleType] {
        // B-09: never expose no_reason_return (type does not exist).
        _ = excludeNoReasonReturn
        return AfterSaleType.allCases
    }

    // MARK: Negotiation / escalate (AFS-05 / AFS-06)

    public static func canSellerRespond(status: AfterSaleCaseStatus) -> Bool {
        status == .requested
    }

    /// Seller who timed-out into auto-agree cannot escalate to undo.
    public static func canEscalate(
        status: AfterSaleCaseStatus,
        timeoutAgree: Bool,
        actorIsSeller: Bool,
        courtEnabled: Bool = true
    ) -> AfterSaleErrorCode? {
        if !courtEnabled { return .courtNotEnabled }
        switch status {
        case .requested:
            if actorIsSeller && timeoutAgree { return .cannotEscalate }
            return nil
        case .agreed:
            // Return path stalemate / reject receive may escalate; timeout refund already executing.
            if timeoutAgree && actorIsSeller { return .cannotEscalate }
            return nil
        case .returnShipping:
            return nil
        case .escalated, .withdrawn, .closed:
            return .cannotEscalate
        }
    }

    public static func canWithdraw(
        status: AfterSaleCaseStatus,
        refundProcessing: Bool
    ) -> AfterSaleErrorCode? {
        if refundProcessing { return .refundAlreadyProcessing }
        switch status {
        case .requested, .agreed:
            return nil
        default:
            return .cannotEscalate
        }
    }

    // MARK: Evidence / appeal (AFS-06 / AFS-08)

    public static func canSubmitEvidence(
        status: ArbitrationStatus,
        partyAbsent: Bool = false
    ) -> AfterSaleErrorCode? {
        if status != .evidence { return .evidencePeriodClosed }
        if partyAbsent { return .evidencePeriodClosed }
        return nil
    }

    public static func canAppeal(
        status: ArbitrationStatus,
        final: Bool,
        appealOf: Int64?,
        appealDeadline: Date?,
        now: Date = Date()
    ) -> AfterSaleErrorCode? {
        if final { return .appealAlreadyUsed }
        if appealOf != nil { return .appealAlreadyUsed }
        guard status == .closed else { return .cannotEscalate }
        guard let appealDeadline else { return .appealWindowElapsed }
        if now > appealDeadline { return .appealWindowElapsed }
        return nil
    }

    public static func reasonLengthError(_ text: String) -> AfterSaleErrorCode? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < AfterSaleConfigDefaults.reasonMinLength { return .reasonTooShort }
        if trimmed.count > AfterSaleConfigDefaults.reasonMaxLength { return .reasonTooLong }
        if trimmed == "不服" { return .reasonTooShort }
        return nil
    }

    // MARK: Adverse inference (AFS-07)

    /// Force-inspect order missing consistent ship video → suggest hidden_flaw.
    public static func shouldSuggestAdverseInference(
        inspectRequired: Bool,
        shipVideoVerified: Bool,
        shipVideoPresent: Bool
    ) -> Bool {
        guard inspectRequired else { return false }
        return !shipVideoPresent || !shipVideoVerified
    }

    public static func defaultTemplateForAdverse(adverse: Bool) -> RulingTemplate {
        adverse ? .hiddenFlaw : .noFault
    }

    public static func adverseInferenceCopy(active: Bool, overridden: Bool) -> String? {
        if overridden { return AfterSaleCopy.adverseInferenceOverridden }
        if active { return AfterSaleCopy.adverseInferenceBanner }
        return nil
    }

    /// Buyer missing unbox video must NOT imply buyer_damage (B-16).
    public static func buyerUnboxMissingImpliesDamage(_: Bool) -> Bool { false }

    // MARK: Countdown

    public static func remainSeconds(
        deadline: Date?,
        serverTime: Date?,
        fetchedAtLocal: Date,
        nowLocal: Date = Date()
    ) -> Int {
        guard let deadline else { return 0 }
        let serverNow: Date = {
            if let serverTime {
                let elapsed = max(0, nowLocal.timeIntervalSince(fetchedAtLocal))
                return serverTime.addingTimeInterval(elapsed)
            }
            return nowLocal
        }()
        return max(0, Int(deadline.timeIntervalSince(serverNow)))
    }

    public static func formatCountdown(_ remainSec: Int) -> String {
        let s = max(0, remainSec)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h >= 24 {
            let d = h / 24
            let rh = h % 24
            return String(format: "%d天%02d:%02d:%02d", d, rh, m, sec)
        }
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    public static func message(for code: String?) -> String {
        AfterSaleErrorCode.normalize(code)?.fallbackMessage ?? (code ?? "操作失败")
    }

    public static func sellerDueAt(
        from createdAt: Date,
        hours: Int = AfterSaleConfigDefaults.sellerRespondHours
    ) -> Date {
        createdAt.addingTimeInterval(TimeInterval(hours * 3600))
    }

    public static func evidenceDeadline(
        from evidenceStart: Date,
        hours: Int = AfterSaleConfigDefaults.evidenceHours
    ) -> Date {
        evidenceStart.addingTimeInterval(TimeInterval(hours * 3600))
    }

    public static func appealDeadline(
        from decidedAt: Date,
        hours: Int = AfterSaleConfigDefaults.appealHours
    ) -> Date {
        decidedAt.addingTimeInterval(TimeInterval(hours * 3600))
    }

    /// Rough client preview of workday deadline (server calendar authoritative).
    public static func addWorkdays(
        from start: Date,
        workdays: Int = AfterSaleConfigDefaults.decideWorkdays,
        calendar: Calendar = {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: AfterSaleConfigDefaults.calendarTZ) ?? .current
            return c
        }(),
        holidays: Set<DateComponents> = []
    ) -> Date {
        var remaining = max(0, workdays)
        var day = calendar.startOfDay(for: start)
        while remaining > 0 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            let comps = calendar.dateComponents([.year, .month, .day], from: day)
            let isHoliday = holidays.contains {
                $0.year == comps.year && $0.month == comps.month && $0.day == comps.day
            }
            if AfterSaleConfigDefaults.calendarSkipWeekends && (isWeekend || isHoliday) {
                continue
            }
            remaining -= 1
        }
        var endComps = calendar.dateComponents([.year, .month, .day], from: day)
        endComps.hour = AfterSaleConfigDefaults.decideDeadlineHourCST
        endComps.minute = 0
        endComps.second = 0
        return calendar.date(from: endComps) ?? day
    }

    public static func rulingPenaltyMismatch(
        template: RulingTemplate,
        deductsDeposit: Bool
    ) -> Bool {
        // no_fault must not deduct deposit (design §5.5).
        if template == .noFault && deductsDeposit { return true }
        return false
    }
}
