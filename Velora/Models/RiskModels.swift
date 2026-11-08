import Foundation

// MARK: - Bounty report / related accounts / penalties (DES-v1.3-10-02 RISK-04～08 / D36 — app mirror of VeloraCore)

/// Product defaults (design §3). Hot-config on server; client mirrors for UX + gates.
enum RiskConfigDefaults {
    static let offlineFineFirstCents = 20_000
    static let offlineFineRepeatRateBps = 1_000
    static let offlineFineRepeatMinCents = 50_000
    static let offlineFineRepeatMaxCents = 500_000
    static let bountyRateBps = 5_000
    static let launchGateBountyPayoutKey = "launch_gate.bounty_payout"
    static let launchGateBountyPayoutDefault = false
    static let hideBlockedListingsKey = "risk.block.hide_listings"
    static let hideBlockedListingsDefault = false
    static let relatedFailOpenKey = "risk.related.fail_open"
    static let relatedFailOpenDefault = false
    static let relatedStrongConfidence = 70
    static let relatedIdNoConfidence = 100
    static let relatedDeviceConfidence = 80
    static let relatedPayAccountConfidence = 90
    static let relatedAddressConfidence = 70
    static let relatedIPWeakConfidence = 40
    static let denyBidCacheTTLSeconds = 3
    static let evidencePhotosMax = 9
    static let evidencePhotosMinBounty = 1
    static let reportDedupHours = 48
    static let fakeReportRestrictDays = 30
    static let fakeReportRejectThreshold = 3
    static let reviewSLAWorkdays = 5
    static let notifyCodePenalty = "N-27"
    static let penaltyLadderWindowDays = 365
    static let searchDownrankWeight = 0.2
    static let searchDownrankDaysFirst = 7
    static let banPublishDaysRepeat = 30
    static let creditDeltaInduceOffline = -15
}

// MARK: - Report target / reason / status

/// `reports.target_type` (design §3 / §5.4 / §5.12).
enum ReportTargetType: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case listing
    case question
    case post
    case comment
    case user
    case message
    case sellerOffline = "seller_offline"

    var id: String { rawValue }

    static func normalize(_ raw: String?) -> ReportTargetType? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ReportTargetType(rawValue: s) { return exact }
        switch s {
        case "lot", "item", "goods", "product":
            return .listing
        case "qa", "q_and_a", "listing_question":
            return .question
        case "feed", "community_post", "article":
            return .post
        case "reply":
            return .comment
        case "seller", "peer", "account", "profile":
            return .user
        case "im", "chat", "dm", "msg":
            return .message
        case "offline", "induce_offline", "induce_pay", "bounty":
            return .sellerOffline
        default:
            return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .listing: return "商品"
        case .question: return "问答"
        case .post: return "帖子"
        case .comment: return "评论"
        case .user: return "用户"
        case .message: return "私信"
        case .sellerOffline: return "诱导线下"
        }
    }

    /// Bounty path requires order_id + buyer (design §5.1 / §5.7).
    var isBountyTarget: Bool { self == .sellerOffline }

    /// Reasons shown in the general report picker for this target.
    var selectableReasons: [ReportReason] {
        switch self {
        case .sellerOffline:
            return [.induceOffline]
        case .user, .message:
            return [.induceOffline, .spam, .abuse, .fraud, .illegal, .other]
        case .listing, .question, .post, .comment:
            return [.spam, .fake, .fraud, .illegal, .abuse, .other]
        }
    }
}

/// Client reason codes submitted as `reason` (design §5.4 / §5.12 / §9).
enum ReportReason: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case induceOffline = "induce_offline"
    case spam
    case fake
    case fraud
    case abuse
    case illegal
    case other

    var id: String { rawValue }

    static func normalize(_ raw: String?) -> ReportReason? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ReportReason(rawValue: s) { return exact }
        switch s {
        case "induce_pay", "seller_offline", "offline", "诱导线下":
            return .induceOffline
        case "ad", "advertisement", "广告", "骚扰营销":
            return .spam
        case "counterfeit", "suspected_fake", "假货":
            return .fake
        case "scam", "cheat", "诈骗":
            return .fraud
        case "harassment", "insult", "辱骂":
            return .abuse
        case "porn", "violence", "违禁":
            return .illegal
        case "misc", "else", "其他":
            return .other
        default:
            return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .induceOffline: return "诱导线下交易"
        case .spam: return "垃圾广告"
        case .fake: return "假货/仿品"
        case .fraud: return "欺诈行为"
        case .abuse: return "辱骂骚扰"
        case .illegal: return "违法违规"
        case .other: return "其他"
        }
    }

    var requiresEvidenceHint: Bool { self == .induceOffline }
}

/// `reports.status` (design §4).
enum ReportStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case open
    case rejected
    case confirmed

    static func normalize(_ raw: String?) -> ReportStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ReportStatus(rawValue: s) { return exact }
        switch s {
        case "pending", "reviewing", "in_review", "submitted":
            return .open
        case "deny", "denied", "dismissed":
            return .rejected
        case "approved", "upheld", "done_confirmed":
            return .confirmed
        default:
            return nil
        }
    }

    var isTerminal: Bool {
        switch self {
        case .rejected, .confirmed: return true
        case .open: return false
        }
    }

    var displayLabel: String {
        switch self {
        case .open: return RiskCopy.bountyProgressReviewing
        case .rejected: return "已驳回"
        case .confirmed: return "已查实"
        }
    }
}

// MARK: - Bounty payout

/// `bounty_payouts.status` (design §3 / §4 / §9).
enum BountyPayoutStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pending
    case paying
    case paid
    case failed
    case held

    static func normalize(_ raw: String?) -> BountyPayoutStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = BountyPayoutStatus(rawValue: s) { return exact }
        switch s {
        case "queued", "created":
            return .pending
        case "processing", "in_flight":
            return .paying
        case "success", "settled", "completed":
            return .paid
        case "error", "retry_exhausted":
            return .failed
        case "gate_closed", "awaiting_finance", "launch_gate":
            return .held
        default:
            return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .pending, .paying, .held:
            return RiskCopy.bountyProgressHeld
        case .paid:
            return RiskCopy.bountyProgressPaid
        case .failed:
            return "打款失败"
        }
    }

    var isAwaitingPayout: Bool {
        switch self {
        case .pending, .paying, .held, .failed: return true
        case .paid: return false
        }
    }
}

// MARK: - Penalties / content review

/// `penalties.type` (design §5.2 / §5.11).
enum PenaltyType: String, Codable, Sendable, CaseIterable, Equatable {
    case searchDownrank = "search_downrank"
    case removeHome = "remove_home"
    case banPublishNdays = "ban_publish_ndays"
    case banBidNdays = "ban_bid_ndays"
    case freeze

    static func normalize(_ raw: String?) -> PenaltyType? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = PenaltyType(rawValue: s) { return exact }
        switch s {
        case "downrank", "search_weight":
            return .searchDownrank
        case "home_ineligible", "remove_from_home":
            return .removeHome
        case "ban_publish", "publish_forbidden":
            return .banPublishNdays
        case "ban_bid", "bid_forbidden", "bidding_banned":
            return .banBidNdays
        case "account_frozen", "frozen":
            return .freeze
        default:
            return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .searchDownrank: return "搜索降权"
        case .removeHome: return "移出首页"
        case .banPublishNdays: return "禁止发布"
        case .banBidNdays: return "禁止竞拍"
        case .freeze: return "账号冻结"
        }
    }
}

enum PenaltyStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case active
    case expired
    case revoked

    static func normalize(_ raw: String?) -> PenaltyStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = PenaltyStatus(rawValue: s) { return exact }
        switch s {
        case "alive", "running":
            return .active
        case "ended", "done":
            return .expired
        case "cancelled", "canceled", "lifted":
            return .revoked
        default:
            return nil
        }
    }
}

/// Content-review reject labels (design §5.10).
enum ContentReviewRejectReason: String, Codable, Sendable, CaseIterable, Equatable {
    case porn
    case illegal
    case contact
    case ad
    case other

    static func normalize(_ raw: String?) -> ContentReviewRejectReason? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ContentReviewRejectReason(rawValue: s) { return exact }
        switch s {
        case "sexual", "nsfw":
            return .porn
        case "law", "banned":
            return .illegal
        case "phone", "wechat", "qr", "引流":
            return .contact
        case "spam", "promo", "广告":
            return .ad
        case "misc", "else":
            return .other
        default:
            return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .porn: return "色情低俗"
        case .illegal: return "违法违规"
        case .contact: return "站外联系方式"
        case .ad: return "广告营销"
        case .other: return "其他"
        }
    }

    /// User-facing reject copy (design §9).
    var userMessage: String {
        "\(RiskCopy.contentRejectedPrefix)\(displayLabel)"
    }
}

// MARK: - Error codes (design §5.8)

enum RiskErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case bountyNotBuyer = "bounty_not_buyer"
    case reportDuplicate = "report_duplicate"
    case bountyReporterRestricted = "bounty_reporter_restricted"
    case approvalRequired = "approval_required"
    case launchGateClosed = "launch_gate_closed"
    case cannotBlockSelf = "cannot_block_self"
    case bidNotAllowed = "bid_not_allowed"
    case relatedAccountLottery = "related_account_lottery"
    case relatedAccountBid = "related_account_bid"
    case blockedBySeller = "blocked_by_seller"
    case blockedByUser = "blocked_by_user"
    case penaltyNotActive = "penalty_not_active"
    case unauthenticated = "unauthenticated"
    case realNameRequired = "real_name_required"
    case accountFrozen = "account_frozen"
    case evidenceRequired = "evidence_required"

    static func normalize(_ raw: String?) -> RiskErrorCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = RiskErrorCode(rawValue: s) { return exact }
        switch s {
        case "not_buyer", "order_buyer_required":
            return .bountyNotBuyer
        case "duplicate_report", "report_exists":
            return .reportDuplicate
        case "bounty_restricted", "reporter_restricted":
            return .bountyReporterRestricted
        case "need_approver", "dual_approval":
            return .approvalRequired
        case "bounty_gate_closed", "gate_closed":
            return .launchGateClosed
        case "block_self", "self_block":
            return .cannotBlockSelf
        case "related_account_forbidden", "related_account":
            return .relatedAccountBid
        case "blocked_by_peer", "user_blocked", "peer_blocked":
            return .blockedByUser
        case "login_required", "unauthorized":
            return .unauthenticated
        case "need_real_name":
            return .realNameRequired
        case "frozen":
            return .accountFrozen
        case "evidence_missing", "need_evidence":
            return .evidenceRequired
        default:
            return nil
        }
    }

    /// Outward bid deny codes share neutral copy (design §5.6 / §8 / §9).
    var isBidDenied: Bool {
        switch self {
        case .bidNotAllowed, .relatedAccountBid, .blockedBySeller:
            return true
        default:
            return false
        }
    }

    var fallbackMessage: String {
        switch self {
        case .bountyNotBuyer: return RiskCopy.bountyNotBuyer
        case .reportDuplicate: return RiskCopy.reportDuplicate
        case .bountyReporterRestricted: return RiskCopy.bountyReporterRestricted
        case .approvalRequired: return RiskCopy.approvalRequired
        case .launchGateClosed: return RiskCopy.bountyHeld
        case .cannotBlockSelf: return RiskCopy.cannotBlockSelf
        case .bidNotAllowed, .relatedAccountBid, .blockedBySeller:
            return RiskCopy.bidNotAllowed
        case .relatedAccountLottery: return RiskCopy.relatedAccountLottery
        case .blockedByUser: return RiskCopy.blockedByUser
        case .penaltyNotActive: return RiskCopy.penaltyNotActive
        case .unauthenticated: return RiskCopy.unauthenticated
        case .realNameRequired: return RiskCopy.realNameRequired
        case .accountFrozen: return RiskCopy.accountFrozen
        case .evidenceRequired: return RiskCopy.evidenceRequired
        }
    }
}

// MARK: - DTOs

struct UserBlock: Codable, Equatable, Sendable, Identifiable, Hashable {
    let blockerId: Int64?
    let blockedId: Int64
    let createdAt: Date?
    let blockedUser: UserSummary?

    var id: Int64 { blockedId }

    init(
        blockerId: Int64? = nil,
        blockedId: Int64,
        createdAt: Date? = nil,
        blockedUser: UserSummary? = nil
    ) {
        self.blockerId = blockerId
        self.blockedId = blockedId
        self.createdAt = createdAt
        self.blockedUser = blockedUser
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockerId = try c.decodeIfPresent(Int64.self, forKey: .blockerId)
        blockedId = try c.decodeIfPresent(Int64.self, forKey: .blockedId)
            ?? c.decodeIfPresent(Int64.self, forKey: .userId)
            ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        blockedUser = try c.decodeIfPresent(UserSummary.self, forKey: .blockedUser)
            ?? c.decodeIfPresent(UserSummary.self, forKey: .user)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(blockerId, forKey: .blockerId)
        try c.encode(blockedId, forKey: .blockedId)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(blockedUser, forKey: .blockedUser)
    }

    private enum CodingKeys: String, CodingKey {
        case blockerId, blockedId, createdAt, blockedUser, user, userId
    }
}

/// Minimal user projection for block / report lists.
struct UserSummary: Codable, Equatable, Sendable, Hashable, Identifiable {
    let id: Int64
    let nickname: String?
    let avatar: String?

    init(id: Int64, nickname: String? = nil, avatar: String? = nil) {
        self.id = id
        self.nickname = nickname
        self.avatar = avatar
    }

    var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        return "用户\(id % 10_000)"
    }
}

struct Report: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: Int64
    let reporterId: Int64?
    let targetType: ReportTargetType
    let targetId: Int64
    let orderId: Int64?
    let reason: String?
    let evidenceUrls: [String]?
    let status: ReportStatus
    let fineCents: Int64?
    let rewardCents: Int64?
    let bountyPayoutId: Int64?
    let bountyStatus: BountyPayoutStatus?
    let rejectReason: String?
    let createdAt: Date?
    let updatedAt: Date?

    init(
        id: Int64,
        reporterId: Int64? = nil,
        targetType: ReportTargetType,
        targetId: Int64,
        orderId: Int64? = nil,
        reason: String? = nil,
        evidenceUrls: [String]? = nil,
        status: ReportStatus = .open,
        fineCents: Int64? = nil,
        rewardCents: Int64? = nil,
        bountyPayoutId: Int64? = nil,
        bountyStatus: BountyPayoutStatus? = nil,
        rejectReason: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.reporterId = reporterId
        self.targetType = targetType
        self.targetId = targetId
        self.orderId = orderId
        self.reason = reason
        self.evidenceUrls = evidenceUrls
        self.status = status
        self.fineCents = fineCents
        self.rewardCents = rewardCents
        self.bountyPayoutId = bountyPayoutId
        self.bountyStatus = bountyStatus
        self.rejectReason = rejectReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        reporterId = try c.decodeIfPresent(Int64.self, forKey: .reporterId)
        let typeRaw = try c.decodeIfPresent(String.self, forKey: .targetType)
        targetType = ReportTargetType.normalize(typeRaw) ?? .user
        targetId = try c.decodeIfPresent(Int64.self, forKey: .targetId) ?? 0
        orderId = try c.decodeIfPresent(Int64.self, forKey: .orderId)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        evidenceUrls = try c.decodeIfPresent([String].self, forKey: .evidenceUrls)
            ?? c.decodeIfPresent([String].self, forKey: .evidence)
        let statusRaw = try c.decodeIfPresent(String.self, forKey: .status)
        status = ReportStatus.normalize(statusRaw) ?? .open
        fineCents = try c.decodeIfPresent(Int64.self, forKey: .fineCents)
        rewardCents = try c.decodeIfPresent(Int64.self, forKey: .rewardCents)
            ?? c.decodeIfPresent(Int64.self, forKey: .bountyCents)
        bountyPayoutId = try c.decodeIfPresent(Int64.self, forKey: .bountyPayoutId)
        let bountyRaw = try c.decodeIfPresent(String.self, forKey: .bountyStatus)
            ?? c.decodeIfPresent(String.self, forKey: .payoutStatus)
        bountyStatus = BountyPayoutStatus.normalize(bountyRaw)
        rejectReason = try c.decodeIfPresent(String.self, forKey: .rejectReason)
            ?? c.decodeIfPresent(String.self, forKey: .rejectionReason)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(reporterId, forKey: .reporterId)
        try c.encode(targetType.rawValue, forKey: .targetType)
        try c.encode(targetId, forKey: .targetId)
        try c.encodeIfPresent(orderId, forKey: .orderId)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encodeIfPresent(evidenceUrls, forKey: .evidenceUrls)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(fineCents, forKey: .fineCents)
        try c.encodeIfPresent(rewardCents, forKey: .rewardCents)
        try c.encodeIfPresent(bountyPayoutId, forKey: .bountyPayoutId)
        try c.encodeIfPresent(bountyStatus?.rawValue, forKey: .bountyStatus)
        try c.encodeIfPresent(rejectReason, forKey: .rejectReason)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, reporterId, targetType, targetId, orderId, reason
        case evidenceUrls, evidence, status, fineCents, rewardCents, bountyCents
        case bountyPayoutId, bountyStatus, payoutStatus, rejectReason, rejectionReason
        case createdAt, updatedAt
    }

    /// Progress label for bounty / me-reports (design §9). Reject shows reason, no amount.
    var progressLabel: String {
        RiskLogic.bountyProgressLabel(status: status, bountyStatus: bountyStatus, rejectReason: rejectReason)
    }

    /// Reporter may see reward amount after confirm; never surface full fine strategy as primary (design §6 GET).
    var rewardDisplayCents: Int64? {
        guard status == .confirmed else { return nil }
        return rewardCents
    }
}

struct UserBlockPage: Codable, Equatable, Sendable {
    let items: [UserBlock]
    let nextCursor: String?
    let page: Int?
    let pageSize: Int?
    let total: Int?
    let hasMore: Bool?

    init(
        items: [UserBlock],
        nextCursor: String? = nil,
        page: Int? = nil,
        pageSize: Int? = nil,
        total: Int? = nil,
        hasMore: Bool? = nil
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.hasMore = hasMore
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([UserBlock].self, forKey: .items)
            ?? c.decodeIfPresent([UserBlock].self, forKey: .blocks)
            ?? c.decodeIfPresent([UserBlock].self, forKey: .list)
            ?? []
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
            ?? c.decodeIfPresent(String.self, forKey: .cursor)
        page = try c.decodeIfPresent(Int.self, forKey: .page)
        pageSize = try c.decodeIfPresent(Int.self, forKey: .pageSize)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(nextCursor, forKey: .nextCursor)
        try c.encodeIfPresent(page, forKey: .page)
        try c.encodeIfPresent(pageSize, forKey: .pageSize)
        try c.encodeIfPresent(total, forKey: .total)
        try c.encodeIfPresent(hasMore, forKey: .hasMore)
    }

    private enum CodingKeys: String, CodingKey {
        case items, blocks, list, nextCursor, cursor, page, pageSize, total, hasMore
    }
}

struct ReportListPage: Codable, Equatable, Sendable {
    let items: [Report]
    let nextCursor: String?

    init(items: [Report], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([Report].self, forKey: .items)
            ?? c.decodeIfPresent([Report].self, forKey: .reports)
            ?? c.decodeIfPresent([Report].self, forKey: .list)
            ?? []
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
            ?? c.decodeIfPresent(String.self, forKey: .cursor)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(nextCursor, forKey: .nextCursor)
    }

    private enum CodingKeys: String, CodingKey {
        case items, reports, list, nextCursor, cursor
    }
}

// MARK: - Requests

struct CreateReportRequest: Equatable, Sendable {
    let targetType: ReportTargetType
    let targetId: Int64
    let reason: ReportReason
    let evidenceUrls: [String]
    let orderId: Int64?
    let attachConversation: Bool

    init(
        targetType: ReportTargetType,
        targetId: Int64,
        reason: ReportReason,
        evidenceUrls: [String] = [],
        orderId: Int64? = nil,
        attachConversation: Bool = false
    ) {
        self.targetType = targetType
        self.targetId = targetId
        self.reason = reason
        self.evidenceUrls = evidenceUrls
        self.orderId = orderId
        self.attachConversation = attachConversation
    }

    var body: [String: Any?] {
        var dict: [String: Any?] = [
            "target_type": targetType.rawValue,
            "target_id": targetId,
            "reason": reason.rawValue,
            "evidence": evidenceUrls,
            "evidence_urls": evidenceUrls,
        ]
        if let orderId { dict["order_id"] = orderId }
        if attachConversation { dict["attach_conversation"] = true }
        return dict
    }
}

struct CreateBlockRequest: Equatable, Sendable {
    let userId: Int64

    init(userId: Int64) {
        self.userId = userId
    }

    var body: [String: Any?] {
        ["user_id": userId]
    }
}

// MARK: - Copy (design §9)

enum RiskCopy {
    static let reportTitle = "举报"
    static let bountyReportTitle = "举报诱导线下"
    static let reportSuccess = "我们将在 5 个工作日内处理"
    static let bountyHeld = "查实，奖励将在财务开闸后到账"
    static let bountyConfirmedPrefix = "查实，奖励 "
    static let bountyConfirmedSuffix = " 元"
    static let blockSuccess = "已无法收到对方私信，对方也不能再对你的商品出价"
    static let blockListTitle = "黑名单"
    static let blockListEmpty = "还没有拉黑任何人"
    static let blockConfirmTitle = "拉黑该用户？"
    static let blockConfirmMessage = "拉黑后双方无法私信；对方也不能再对你的商品出价"
    static let blockAction = "拉黑"
    static let unblockAction = "解除拉黑"
    static let unblockSuccess = "已解除拉黑"
    static let bidNotAllowed = "当前账号无法对该拍品出价"
    static let contentRejectedPrefix = "含违规信息，请修改："
    static let penaltyExpired = "限制已解除"
    static let penaltyAppealHint = "申诉请回复工单"
    static let bountyProgressReviewing = "审核中"
    static let bountyProgressHeld = "已奖励待打款"
    static let bountyProgressPaid = "已到账"
    static let attachConversation = "附上本单会话"
    static let evidenceHint = "请上传聊天截图等证据（最多 9 张）"
    static let evidenceRequired = "请至少上传 1 张证据图，或勾选附上本单会话"
    static let reasonPickerHint = "请选择举报原因"
    static let submitLocked = "提交中…"
    static let myReportsTitle = "我的举报"
    static let bountyNotBuyer = "仅本单买家可发起赏金举报"
    static let reportDuplicate = "你已举报过该对象"
    static let bountyReporterRestricted = "赏金举报暂不可用，普通内容仍可举报"
    static let approvalRequired = "处罚待复核"
    static let cannotBlockSelf = "不能拉黑自己"
    static let relatedAccountLottery = "当前账号无法报名该抽签"
    static let blockedByUser = "对方已将你拉黑，无法发送私信"
    static let penaltyNotActive = "处罚已失效，无法撤销"
    static let unauthenticated = "请先登录"
    static let realNameRequired = "赏金举报需先完成实名认证"
    static let accountFrozen = "账号已冻结，暂不可举报"
    static let serverTimeHint = "以服务器时间为准"

    static func bountyRewardNotice(yuanText: String) -> String {
        "\(bountyConfirmedPrefix)\(yuanText)\(bountyConfirmedSuffix)"
    }

    static func penaltyNotice(reason: String, windowText: String) -> String {
        "\(reason)·\(windowText)·\(penaltyAppealHint)"
    }

    static func contentRejected(type: ContentReviewRejectReason) -> String {
        type.userMessage
    }
}

// MARK: - Logic

enum RiskLogic {
    /// Offline fine ladder (design §5.1 / §5.11). `priorConfirmedCount` = seller history before this case.
    static func offlineFineCents(
        priorConfirmedCount: Int,
        dealPriceCents: Int64,
        firstCents: Int = RiskConfigDefaults.offlineFineFirstCents,
        repeatRateBps: Int = RiskConfigDefaults.offlineFineRepeatRateBps,
        repeatMin: Int64 = Int64(RiskConfigDefaults.offlineFineRepeatMinCents),
        repeatMax: Int64 = Int64(RiskConfigDefaults.offlineFineRepeatMaxCents)
    ) -> Int64? {
        if priorConfirmedCount <= 0 { return Int64(firstCents) }
        if priorConfirmedCount == 1 {
            let raw = dealPriceCents * Int64(repeatRateBps) / 10_000
            return min(max(raw, repeatMin), repeatMax)
        }
        return nil // multiple → freeze; no monetary fine computed here
    }

    static func bountyRewardCents(
        fineCents: Int64,
        rateBps: Int = RiskConfigDefaults.bountyRateBps
    ) -> Int64 {
        max(0, fineCents * Int64(rateBps) / 10_000)
    }

    /// Split fine into platform fee + bounty (design §5.1 ledger).
    static func fineSplit(fineCents: Int64, rateBps: Int = RiskConfigDefaults.bountyRateBps) -> (platformFeeCents: Int64, bountyCents: Int64) {
        let bounty = bountyRewardCents(fineCents: fineCents, rateBps: rateBps)
        return (fineCents - bounty, bounty)
    }

    static func bountyProgressLabel(
        status: ReportStatus,
        bountyStatus: BountyPayoutStatus?,
        rejectReason: String? = nil
    ) -> String {
        switch status {
        case .open:
            return RiskCopy.bountyProgressReviewing
        case .rejected:
            if let rejectReason, !rejectReason.isEmpty { return rejectReason }
            return "已驳回"
        case .confirmed:
            if let bountyStatus {
                return bountyStatus.displayLabel
            }
            return RiskCopy.bountyProgressHeld
        }
    }

    static func createReportGate(
        targetType: ReportTargetType,
        reason: ReportReason?,
        evidenceCount: Int,
        attachConversation: Bool,
        orderId: Int64?,
        isLoggedIn: Bool,
        isRealNamed: Bool,
        accountFrozen: Bool,
        bountyRestricted: Bool = false,
        isOrderBuyer: Bool = true
    ) -> RiskErrorCode? {
        guard isLoggedIn else { return .unauthenticated }
        if accountFrozen { return .accountFrozen }
        guard reason != nil else { return nil }

        if targetType.isBountyTarget {
            if bountyRestricted { return .bountyReporterRestricted }
            if !isRealNamed { return .realNameRequired }
            if !isOrderBuyer || orderId == nil || (orderId ?? 0) <= 0 {
                return .bountyNotBuyer
            }
            let hasEvidence = evidenceCount >= RiskConfigDefaults.evidencePhotosMinBounty || attachConversation
            if !hasEvidence { return .evidenceRequired }
        }
        return nil
    }

    static func canSubmitReport(
        targetType: ReportTargetType,
        reason: ReportReason?,
        evidenceCount: Int,
        attachConversation: Bool,
        orderId: Int64?,
        isLoggedIn: Bool,
        isRealNamed: Bool,
        accountFrozen: Bool,
        bountyRestricted: Bool = false,
        isOrderBuyer: Bool = true
    ) -> Bool {
        guard reason != nil else { return false }
        if evidenceCount > RiskConfigDefaults.evidencePhotosMax { return false }
        return createReportGate(
            targetType: targetType,
            reason: reason,
            evidenceCount: evidenceCount,
            attachConversation: attachConversation,
            orderId: orderId,
            isLoggedIn: isLoggedIn,
            isRealNamed: isRealNamed,
            accountFrozen: accountFrozen,
            bountyRestricted: bountyRestricted,
            isOrderBuyer: isOrderBuyer
        ) == nil
    }

    static func createBlockGate(
        blockerId: Int64?,
        blockedId: Int64,
        isLoggedIn: Bool
    ) -> RiskErrorCode? {
        guard isLoggedIn else { return .unauthenticated }
        if let blockerId, blockerId == blockedId { return .cannotBlockSelf }
        if blockedId <= 0 { return .cannotBlockSelf }
        return nil
    }

    static func bidDenyMessage(code: String?) -> String {
        if let mapped = RiskErrorCode.normalize(code), mapped.isBidDenied {
            return RiskCopy.bidNotAllowed
        }
        if code == "related_account_forbidden" || code == "blocked_by_seller" || code == "bid_not_allowed" {
            return RiskCopy.bidNotAllowed
        }
        return RiskCopy.bidNotAllowed
    }

    /// Strong-edge related check (design §5.3) — client mirror for explain / tests.
    static func relatedStrongOverlap(
        left: [(kind: String, confidence: Int)],
        right: [(kind: String, confidence: Int)],
        threshold: Int = RiskConfigDefaults.relatedStrongConfidence
    ) -> Bool {
        let strongKinds: Set<String> = ["id_no", "device", "pay_account", "address"]
        let leftHashes = Set(
            left.filter { strongKinds.contains($0.kind) && $0.confidence >= threshold }.map(\.kind)
        )
        // Kind-only client mirror; server intersects on hash. Non-empty shared strong kind ⇒ potential.
        let rightKinds = Set(
            right.filter { strongKinds.contains($0.kind) && $0.confidence >= threshold }.map(\.kind)
        )
        return !leftHashes.intersection(rightKinds).isEmpty
    }

    static func isWeakIPOnly(
        edges: [(kind: String, confidence: Int)],
        threshold: Int = RiskConfigDefaults.relatedStrongConfidence
    ) -> Bool {
        let strong = edges.contains { kind, confidence in
            ["id_no", "device", "pay_account", "address"].contains(kind) && confidence >= threshold
        }
        let hasIP = edges.contains { $0.kind == "ip" }
        return hasIP && !strong
    }
}
