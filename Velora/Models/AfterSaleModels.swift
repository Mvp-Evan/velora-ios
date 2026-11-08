import Foundation

// MARK: - After-sale negotiation / small court / appeal (DES-v1.3-09-02 AFS-04～10 / D34 — app mirror of VeloraCore)

/// Product defaults (design §3). Hot-config on server; client mirrors for UX + gates.
enum AfterSaleConfigDefaults {
    static let sellerRespondHours = 48
    static let appearanceWindowHours = 48
    static let evidenceHours = 72
    static let decideWorkdays = 5
    static let appealHours = 72 // 3 × 24h
    static let returnTrackingDays = 7
    static let buyerOfferRespondHours = 24
    static let evidenceExtendHours = 24
    static let appearanceUnboxPhotosMin = 3
    static let evidencePhotosMax = 9
    static let reasonMinLength = 20
    static let reasonMaxLength = 2000
    static let otherWindowDays = 15
    static let suspectedFakeWindowDays = 15
    static let shipDeadlineFallbackDays = 10
    static let decideDeadlineHourCST = 18
    static let featureFlagSmallCourt = "small_court"
    static let notifyCode = "N-21"
    static let meEntryKey = "after_sale"
    static let calendarSkipWeekends = true
    static let calendarTZ = "Asia/Shanghai"
    /// Default B-11 / 6.15: 70% obligee / 30% platform on deposit forfeit.
    static let penaltyObligeeBp = 7_000
    static let penaltyPlatformBp = 3_000
    static let creditDeltaHiddenFlaw = -20
    static let creditDeltaBuyerDamage = -20
    static let auctionPauseDaysFirst = 30
    static let buyLimitDaysFirst = 30
    static let buyLimitDaysRepeat = 180
}

// MARK: - Type / claim (AFS-04)

/// `after_sales.type` — no `no_reason_return` (B-09).
enum AfterSaleType: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case notReceived = "not_received"
    case notAsDescribed = "not_as_described"
    case transitDamage = "transit_damage"
    case suspectedFake = "suspected_fake"
    case other

    var id: String { rawValue }

    static func normalize(_ raw: String?) -> AfterSaleType? {
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

    var displayLabel: String {
        switch self {
        case .notReceived: return "未收到货"
        case .notAsDescribed: return "品相不符"
        case .transitDamage: return "运输损坏"
        case .suspectedFake: return "疑似假货"
        case .other: return "其他"
        }
    }

    /// 品相类 = 品相不符 + 运输损坏（48h + 开箱照门禁）。
    var isAppearance: Bool {
        self == .notAsDescribed || self == .transitDamage
    }

    var showsInClientPicker: Bool { true }
}

/// `after_sales.claim`
enum AfterSaleClaim: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case refund
    case returnRefund = "return_refund"
    case partial

    var id: String { rawValue }

    static func normalize(_ raw: String?) -> AfterSaleClaim? {
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

    var displayLabel: String {
        switch self {
        case .refund: return "仅退款"
        case .returnRefund: return "退货退款"
        case .partial: return "部分退款"
        }
    }
}

// MARK: - After-sale record status (7.7)

/// Fine-grained `after_sales.status` (parallel to order `after_sale_status`).
enum AfterSaleCaseStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case requested
    case agreed
    case returnShipping = "return_shipping"
    case escalated
    case withdrawn
    case closed

    static func normalize(_ raw: String?) -> AfterSaleCaseStatus? {
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

    var displayLabel: String {
        switch self {
        case .requested: return "待卖家处理"
        case .agreed: return "已同意"
        case .returnShipping: return "退货寄回中"
        case .escalated: return "小法庭处理中"
        case .withdrawn: return "已撤销"
        case .closed: return "已完结"
        }
    }

    var isActive: Bool {
        switch self {
        case .requested, .agreed, .returnShipping, .escalated: return true
        case .withdrawn, .closed: return false
        }
    }

    var isTerminal: Bool {
        self == .withdrawn || self == .closed
    }
}

// MARK: - Seller respond (AFS-05)

enum SellerRespondAction: String, Codable, Sendable, CaseIterable, Equatable {
    case agree
    case reject
    case offer

    static func normalize(_ raw: String?) -> SellerRespondAction? {
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

    var displayLabel: String {
        switch self {
        case .agree: return "同意"
        case .reject: return "拒绝"
        case .offer: return "提出方案"
        }
    }
}

// MARK: - Arbitration (AFS-06)

/// Case machine: open → evidence → deciding → closed; closed → appeal_review → closed(final).
enum ArbitrationStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case open
    case evidence
    case deciding
    case closed
    case appealReview = "appeal_review"
    case unassigned

    static func normalize(_ raw: String?) -> ArbitrationStatus? {
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

    var displayLabel: String {
        switch self {
        case .open: return "立案中"
        case .evidence: return "举证中"
        case .deciding: return "裁定中"
        case .closed: return "已裁定"
        case .appealReview: return "申诉复核中"
        case .unassigned: return "待指派"
        }
    }

    var allowsPartyEvidence: Bool { self == .evidence }

    var isClosedLike: Bool { self == .closed || self == .appealReview }
}

/// Ruling templates (AFS-07 / AFS-10).
enum RulingTemplate: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case hiddenFlaw = "hidden_flaw"
    case buyerDamage = "buyer_damage"
    case noFault = "no_fault"
    case settlement

    var id: String { rawValue }

    static func normalize(_ raw: String?) -> RulingTemplate? {
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

    var displayLabel: String {
        switch self {
        case .hiddenFlaw: return "藏匿瑕疵"
        case .buyerDamage: return "买家损坏"
        case .noFault: return "双方无责"
        case .settlement: return "和解结案"
        }
    }
}

/// Orchestrator steps (design §5.12).
enum PenaltyExecutionStep: String, Codable, Sendable, CaseIterable, Equatable {
    case refund
    case shareReturn = "share_return"
    case depositDeduct = "deposit_deduct"
    case credit
    case capability
    case blacklist

    var displayLabel: String {
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

enum PenaltyExecutionStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pending
    case succeeded
    case failed
    case skipped

    static func normalize(_ raw: String?) -> PenaltyExecutionStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        return PenaltyExecutionStatus(rawValue: raw.lowercased())
    }

    var displayLabel: String {
        switch self {
        case .pending: return "待执行"
        case .succeeded: return "已成功"
        case .failed: return "失败"
        case .skipped: return "已跳过"
        }
    }
}

// MARK: - Error codes (design §5.13)

enum AfterSaleErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
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

    static func normalize(_ raw: String?) -> AfterSaleErrorCode? {
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

    var fallbackMessage: String {
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

    var opensRealName: Bool { self == .realNameRequired }
    var suggestsSuspectedFake: Bool { self == .afterSaleWindowElapsed }
    var opensUnboxCapture: Bool { self == .unboxPhotosRequired }
}

// MARK: - UX copy (design §9)

enum AfterSaleCopy {
    static let applyTitle = "申请售后"
    static let applyEmptyHint = "签收后 48 小时内可申请品相问题"
    static let detailTitle = "售后详情"
    static let courtTitle = "小法庭"
    static let rulingTitle = "裁定结果"
    static let appealTitle = "申诉"
    static let evidenceTitle = "补充举证"
    static let serverTimeHint = "以服务器时间为准"
    static let sellerRemainPrefix = "卖家剩余"
    static let evidenceRemainPrefix = "举证剩余"
    static let appealRemainPrefix = "申诉剩余"
    static let decideRemainPrefix = "裁定时限"
    static let submitLocked = "提交中…"
    static let escalateCTA = "升级小法庭"
    static let withdrawCTA = "撤销申请"
    static let acceptOfferCTA = "接受方案"
    static let returnTrackingCTA = "填写退货单号"
    static let appealCTA = "我要申诉"
    static let attachEvidenceCTA = "补充材料"
    static let viewRulingCTA = "查看裁定"
    static let noReasonReturnHidden = "不适用七天无理由退货"
    static let windowElapsed = "品相申请已超过 48 小时，可改选「疑似假货」或联系客服"
    static let unboxPhotosRequired = "品相类售后需至少 3 张开箱照片，请先去拍摄"
    static let afterSaleExists = "该订单已有进行中的售后"
    static let claimAmountInvalid = "退款金额不符合规则"
    static let sellerRespondTimeout = "卖家已超时，系统已按买家方案同意"
    static let cannotEscalate = "当前状态不可升级小法庭"
    static let evidencePeriodClosed = "举证已结束，无法再补充材料"
    static let appealWindowElapsed = "申诉窗口已过"
    static let appealAlreadyUsed = "本案已申诉，不可再次申诉"
    static let rulingPenaltyMismatch = "裁定模板与处罚勾选不一致"
    static let courtNotEnabled = "小法庭暂未开放"
    static let arbitratorUnavailable = "暂无可用仲裁员，请稍后再试"
    static let refundAlreadyProcessing = "退款处理中，不可撤销"
    static let offerExpired = "卖家方案已失效"
    static let notReturnClaim = "非退货退款诉求，无需填写单号"
    static let missingIdempotencyKey = "缺少幂等键"
    static let realNameRequired = "请先完成实名认证"
    static let accountRestricted = "账号受限，暂不可发起售后"
    static let unauthenticated = "请先登录"
    static let notOrderParty = "无权查看该售后"
    static let forbidden = "无权操作"
    static let reasonTooShort = "理由至少 20 字"
    static let reasonTooLong = "理由最多 2000 字"
    static let appealReasonPlaceholder = "请说明不服裁定的理由（至少 20 字）"
    static let rulingReasonLabel = "裁定理由"
    static let penaltiesLabel = "处罚执行"
    static let absentFlagLabel = "缺席认定"
    static let timeoutAgreeBadge = "超时视同意"
    static let packetIncomplete = "附卷不完整"
    static let finalBadge = "终局"

    /// 不利推定条（AFS-07）：强制验车且无一致发货视频。
    static let adverseInferenceBanner =
        "强制验车订单缺少一致发货视频，系统建议按「藏匿瑕疵」不利推定；仲裁员可推翻但须另写理由。"
    static let adverseInferenceShort = "不利推定：建议藏匿瑕疵"
    static let adverseInferenceOverridden = "仲裁员已推翻不利推定"
    /// B-16：买家未录开箱视频不作对称推定。
    static let noBuyerVideoPresumption = "买家未登记开箱视频不作损坏推定"

    static let typePickerHint = "请选择售后类型（不含七天无理由）"
    static let claimPickerHint = "请选择诉求"
    static let reasonPlaceholder = "请描述问题（纯文本）"
}

// MARK: - Seller offer snapshot

struct SellerOffer: Codable, Equatable, Sendable, Hashable {
    let claim: AfterSaleClaim
    let amountCents: Int64
    let note: String?
    let offeredAt: Date?

    init(
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

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(claim.rawValue, forKey: .claim)
        try c.encode(amountCents, forKey: .amountCents)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(offeredAt, forKey: .offeredAt)
    }
}

// MARK: - After-sale record

struct AfterSale: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: Int64
    let orderId: Int64
    let buyerId: Int64?
    let sellerId: Int64?
    let type: AfterSaleType
    let claim: AfterSaleClaim
    let claimAmountCents: Int64
    let reason: String?
    let status: AfterSaleCaseStatus
    let sellerDueAt: Date?
    let sellerOffer: SellerOffer?
    let agreedAmountCents: Int64?
    let returnTracking: String?
    let evidencePhotoIds: [Int64]?
    let unboxSkipped: Bool?
    let arbitrationId: Int64?
    let timeoutAgree: Bool?
    let version: Int64?
    let serverTime: Date?
    let createdAt: Date?
    let updatedAt: Date?

    init(
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

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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

    var statusLabel: String { status.displayLabel }
    var typeLabel: String { type.displayLabel }
    var claimLabel: String { claim.displayLabel }
    var showsTimeoutAgreeBadge: Bool { timeoutAgree == true }
}

// MARK: - Arbitration case

struct ArbitrationPenaltyItem: Codable, Equatable, Sendable, Hashable, Identifiable {
    var id: String { "\(step.rawValue)-\(status.rawValue)" }
    let step: PenaltyExecutionStep
    let status: PenaltyExecutionStatus
    let label: String?
    let detail: String?

    init(
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

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(step.rawValue, forKey: .step)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(detail, forKey: .detail)
    }

    var displayLabel: String { label ?? step.displayLabel }
}

struct ArbitrationEvidence: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: Int64
    let arbitrationId: Int64?
    let uploaderId: Int64?
    let kind: String?
    let refId: Int64?
    let note: String?
    let absentFlag: Bool?
    let imageUrls: [String]?
    let createdAt: Date?

    init(
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

struct Arbitration: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: Int64
    let afterSaleId: Int64?
    let orderId: Int64
    let status: ArbitrationStatus
    let arbitratorId: Int64?
    let evidenceDeadline: Date?
    let decideDeadline: Date?
    let rulingTemplate: RulingTemplate?
    let rulingReason: String?
    let penalties: [ArbitrationPenaltyItem]?
    let appealOf: Int64?
    let appealedAt: Date?
    let appealDeadline: Date?
    let final: Bool
    let decidedAt: Date?
    let adverseInference: Bool?
    let adverseInferenceOverridden: Bool?
    let buyerAbsent: Bool?
    let sellerAbsent: Bool?
    let packetIncomplete: Bool?
    let evidences: [ArbitrationEvidence]?
    let version: Int64?
    let serverTime: Date?

    init(
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

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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

    var statusLabel: String { status.displayLabel }
    var templateLabel: String? { rulingTemplate?.displayLabel }
    var showsAdverseBanner: Bool {
        adverseInference == true && adverseInferenceOverridden != true
    }
    var canPartyAppeal: Bool {
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

struct CreateAfterSaleRequest: Equatable, Sendable {
    let type: AfterSaleType
    let claim: AfterSaleClaim
    let claimAmountCents: Int64
    let reason: String
    let unboxPhotoIds: [Int64]

    init(
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

    var body: [String: Any?] {
        [
            "type": type.rawValue,
            "claim": claim.rawValue,
            "claim_amount_cents": claimAmountCents,
            "reason": reason,
            "unbox_photo_ids": unboxPhotoIds,
        ]
    }
}

struct SellerRespondRequest: Equatable, Sendable {
    let action: SellerRespondAction
    let claim: AfterSaleClaim?
    let amountCents: Int64?
    let reason: String?

    init(
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

    var body: [String: Any?] {
        var d: [String: Any?] = ["action": action.rawValue]
        if let claim { d["claim"] = claim.rawValue }
        if let amountCents { d["claim_amount_cents"] = amountCents }
        if let reason, !reason.isEmpty { d["reason"] = reason }
        return d
    }
}

struct ArbitrationEvidenceRequest: Equatable, Sendable {
    let note: String?
    let photoIds: [Int64]

    init(note: String? = nil, photoIds: [Int64] = []) {
        self.note = note
        self.photoIds = photoIds
    }

    var body: [String: Any?] {
        [
            "note": note,
            "photo_ids": photoIds,
        ]
    }
}

struct ArbitrationAppealRequest: Equatable, Sendable {
    let reason: String

    init(reason: String) {
        self.reason = reason
    }

    var body: [String: Any?] {
        ["reason": reason]
    }
}

// MARK: - Domain logic

enum AfterSaleLogic {

    // MARK: Windows (AFS-04)

    /// Appearance (品相) window from signed_at + 48h. Missing signedAt → blocked (引导确认签收).
    static func appearanceWindowOpen(
        signedAt: Date?,
        now: Date = Date(),
        windowHours: Int = AfterSaleConfigDefaults.appearanceWindowHours
    ) -> Bool {
        guard let signedAt else { return false }
        return now <= signedAt.addingTimeInterval(TimeInterval(windowHours * 3600))
    }

    static func suspectedFakeWindowOpen(
        signedAt: Date?,
        now: Date = Date(),
        windowDays: Int = AfterSaleConfigDefaults.suspectedFakeWindowDays
    ) -> Bool {
        guard let signedAt else { return false }
        return now <= signedAt.addingTimeInterval(TimeInterval(windowDays * 86_400))
    }

    static func otherWindowOpen(
        signedAt: Date?,
        now: Date = Date(),
        windowDays: Int = AfterSaleConfigDefaults.otherWindowDays
    ) -> Bool {
        guard let signedAt else { return false }
        return now <= signedAt.addingTimeInterval(TimeInterval(windowDays * 86_400))
    }

    /// Client gate before POST create. Server remains authoritative.
    static func createGate(
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

    static func claimAmountError(
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

    static func selectableTypes(excludeNoReasonReturn: Bool = true) -> [AfterSaleType] {
        // B-09: never expose no_reason_return (type does not exist).
        _ = excludeNoReasonReturn
        return AfterSaleType.allCases
    }

    // MARK: Negotiation / escalate (AFS-05 / AFS-06)

    static func canSellerRespond(status: AfterSaleCaseStatus) -> Bool {
        status == .requested
    }

    /// Seller who timed-out into auto-agree cannot escalate to undo.
    static func canEscalate(
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

    static func canWithdraw(
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

    static func canSubmitEvidence(
        status: ArbitrationStatus,
        partyAbsent: Bool = false
    ) -> AfterSaleErrorCode? {
        if status != .evidence { return .evidencePeriodClosed }
        if partyAbsent { return .evidencePeriodClosed }
        return nil
    }

    static func canAppeal(
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

    static func reasonLengthError(_ text: String) -> AfterSaleErrorCode? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < AfterSaleConfigDefaults.reasonMinLength { return .reasonTooShort }
        if trimmed.count > AfterSaleConfigDefaults.reasonMaxLength { return .reasonTooLong }
        if trimmed == "不服" { return .reasonTooShort }
        return nil
    }

    // MARK: Adverse inference (AFS-07)

    /// Force-inspect order missing consistent ship video → suggest hidden_flaw.
    static func shouldSuggestAdverseInference(
        inspectRequired: Bool,
        shipVideoVerified: Bool,
        shipVideoPresent: Bool
    ) -> Bool {
        guard inspectRequired else { return false }
        return !shipVideoPresent || !shipVideoVerified
    }

    static func defaultTemplateForAdverse(adverse: Bool) -> RulingTemplate {
        adverse ? .hiddenFlaw : .noFault
    }

    static func adverseInferenceCopy(active: Bool, overridden: Bool) -> String? {
        if overridden { return AfterSaleCopy.adverseInferenceOverridden }
        if active { return AfterSaleCopy.adverseInferenceBanner }
        return nil
    }

    /// Buyer missing unbox video must NOT imply buyer_damage (B-16).
    static func buyerUnboxMissingImpliesDamage(_: Bool) -> Bool { false }

    // MARK: Countdown

    static func remainSeconds(
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

    static func formatCountdown(_ remainSec: Int) -> String {
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

    static func message(for code: String?) -> String {
        AfterSaleErrorCode.normalize(code)?.fallbackMessage ?? (code ?? "操作失败")
    }

    static func sellerDueAt(
        from createdAt: Date,
        hours: Int = AfterSaleConfigDefaults.sellerRespondHours
    ) -> Date {
        createdAt.addingTimeInterval(TimeInterval(hours * 3600))
    }

    static func evidenceDeadline(
        from evidenceStart: Date,
        hours: Int = AfterSaleConfigDefaults.evidenceHours
    ) -> Date {
        evidenceStart.addingTimeInterval(TimeInterval(hours * 3600))
    }

    static func appealDeadline(
        from decidedAt: Date,
        hours: Int = AfterSaleConfigDefaults.appealHours
    ) -> Date {
        decidedAt.addingTimeInterval(TimeInterval(hours * 3600))
    }

    /// Rough client preview of workday deadline (server calendar authoritative).
    static func addWorkdays(
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

    static func rulingPenaltyMismatch(
        template: RulingTemplate,
        deductsDeposit: Bool
    ) -> Bool {
        // no_fault must not deduct deposit (design §5.5).
        if template == .noFault && deductsDeposit { return true }
        return false
    }
}
