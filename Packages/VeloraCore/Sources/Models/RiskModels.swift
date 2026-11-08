import Foundation

// MARK: - Bounty report / related accounts / penalties (DES-v1.3-10-02 RISK-04～08 / D36)

/// Product defaults (design §3). Hot-config on server; client mirrors for UX + gates.
public enum RiskConfigDefaults {
    public static let offlineFineFirstCents = 20_000
    public static let offlineFineRepeatRateBps = 1_000
    public static let offlineFineRepeatMinCents = 50_000
    public static let offlineFineRepeatMaxCents = 500_000
    public static let bountyRateBps = 5_000
    public static let launchGateBountyPayoutKey = "launch_gate.bounty_payout"
    public static let launchGateBountyPayoutDefault = false
    public static let hideBlockedListingsKey = "risk.block.hide_listings"
    public static let hideBlockedListingsDefault = false
    public static let relatedFailOpenKey = "risk.related.fail_open"
    public static let relatedFailOpenDefault = false
    public static let relatedStrongConfidence = 70
    public static let relatedIdNoConfidence = 100
    public static let relatedDeviceConfidence = 80
    public static let relatedPayAccountConfidence = 90
    public static let relatedAddressConfidence = 70
    public static let relatedIPWeakConfidence = 40
    public static let denyBidCacheTTLSeconds = 3
    public static let evidencePhotosMax = 9
    public static let evidencePhotosMinBounty = 1
    public static let reportDedupHours = 48
    public static let fakeReportRestrictDays = 30
    public static let fakeReportRejectThreshold = 3
    public static let reviewSLAWorkdays = 5
    public static let notifyCodePenalty = "N-27"
    public static let penaltyLadderWindowDays = 365
    public static let searchDownrankWeight = 0.2
    public static let searchDownrankDaysFirst = 7
    public static let banPublishDaysRepeat = 30
    public static let creditDeltaInduceOffline = -15
}

// MARK: - Report target / reason / status

/// `reports.target_type` (design §3 / §5.4 / §5.12).
public enum ReportTargetType: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case listing
    case question
    case post
    case comment
    case user
    case message
    case sellerOffline = "seller_offline"

    public var id: String { rawValue }

    public static func normalize(_ raw: String?) -> ReportTargetType? {
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

    public var displayLabel: String {
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
    public var isBountyTarget: Bool { self == .sellerOffline }

    /// Reasons shown in the general report picker for this target.
    public var selectableReasons: [ReportReason] {
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
public enum ReportReason: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case induceOffline = "induce_offline"
    case spam
    case fake
    case fraud
    case abuse
    case illegal
    case other

    public var id: String { rawValue }

    public static func normalize(_ raw: String?) -> ReportReason? {
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

    public var displayLabel: String {
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

    public var requiresEvidenceHint: Bool { self == .induceOffline }
}

/// `reports.status` (design §4).
public enum ReportStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case open
    case rejected
    case confirmed

    public static func normalize(_ raw: String?) -> ReportStatus? {
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

    public var isTerminal: Bool {
        switch self {
        case .rejected, .confirmed: return true
        case .open: return false
        }
    }

    public var displayLabel: String {
        switch self {
        case .open: return RiskCopy.bountyProgressReviewing
        case .rejected: return "已驳回"
        case .confirmed: return "已查实"
        }
    }
}

// MARK: - Bounty payout

/// `bounty_payouts.status` (design §3 / §4 / §9).
public enum BountyPayoutStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pending
    case paying
    case paid
    case failed
    case held

    public static func normalize(_ raw: String?) -> BountyPayoutStatus? {
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

    public var displayLabel: String {
        switch self {
        case .pending, .paying, .held:
            return RiskCopy.bountyProgressHeld
        case .paid:
            return RiskCopy.bountyProgressPaid
        case .failed:
            return "打款失败"
        }
    }

    public var isAwaitingPayout: Bool {
        switch self {
        case .pending, .paying, .held, .failed: return true
        case .paid: return false
        }
    }
}

// MARK: - Penalties / content review

/// `penalties.type` (design §5.2 / §5.11).
public enum PenaltyType: String, Codable, Sendable, CaseIterable, Equatable {
    case searchDownrank = "search_downrank"
    case removeHome = "remove_home"
    case banPublishNdays = "ban_publish_ndays"
    case banBidNdays = "ban_bid_ndays"
    case freeze

    public static func normalize(_ raw: String?) -> PenaltyType? {
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

    public var displayLabel: String {
        switch self {
        case .searchDownrank: return "搜索降权"
        case .removeHome: return "移出首页"
        case .banPublishNdays: return "禁止发布"
        case .banBidNdays: return "禁止竞拍"
        case .freeze: return "账号冻结"
        }
    }
}

public enum PenaltyStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case active
    case expired
    case revoked

    public static func normalize(_ raw: String?) -> PenaltyStatus? {
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
public enum ContentReviewRejectReason: String, Codable, Sendable, CaseIterable, Equatable {
    case porn
    case illegal
    case contact
    case ad
    case other

    public static func normalize(_ raw: String?) -> ContentReviewRejectReason? {
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

    public var displayLabel: String {
        switch self {
        case .porn: return "色情低俗"
        case .illegal: return "违法违规"
        case .contact: return "站外联系方式"
        case .ad: return "广告营销"
        case .other: return "其他"
        }
    }

    /// User-facing reject copy (design §9).
    public var userMessage: String {
        "\(RiskCopy.contentRejectedPrefix)\(displayLabel)"
    }
}

// MARK: - Error codes (design §5.8)

public enum RiskErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
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

    public static func normalize(_ raw: String?) -> RiskErrorCode? {
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
    public var isBidDenied: Bool {
        switch self {
        case .bidNotAllowed, .relatedAccountBid, .blockedBySeller:
            return true
        default:
            return false
        }
    }

    public var fallbackMessage: String {
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

public struct UserBlock: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let blockerId: Int64?
    public let blockedId: Int64
    public let createdAt: Date?
    public let blockedUser: UserSummary?

    public var id: Int64 { blockedId }

    public init(
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockerId = try c.decodeIfPresent(Int64.self, forKey: .blockerId)
        blockedId = try c.decodeIfPresent(Int64.self, forKey: .blockedId)
            ?? c.decodeIfPresent(Int64.self, forKey: .userId)
            ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        blockedUser = try c.decodeIfPresent(UserSummary.self, forKey: .blockedUser)
            ?? c.decodeIfPresent(UserSummary.self, forKey: .user)
    }

    public func encode(to encoder: Encoder) throws {
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
public struct UserSummary: Codable, Equatable, Sendable, Hashable, Identifiable {
    public let id: Int64
    public let nickname: String?
    public let avatar: String?

    public init(id: Int64, nickname: String? = nil, avatar: String? = nil) {
        self.id = id
        self.nickname = nickname
        self.avatar = avatar
    }

    public var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        return "用户\(id % 10_000)"
    }
}

public struct Report: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let reporterId: Int64?
    public let targetType: ReportTargetType
    public let targetId: Int64
    public let orderId: Int64?
    public let reason: String?
    public let evidenceUrls: [String]?
    public let status: ReportStatus
    public let fineCents: Int64?
    public let rewardCents: Int64?
    public let bountyPayoutId: Int64?
    public let bountyStatus: BountyPayoutStatus?
    public let rejectReason: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
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

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
    public var progressLabel: String {
        RiskLogic.bountyProgressLabel(status: status, bountyStatus: bountyStatus, rejectReason: rejectReason)
    }

    /// Reporter may see reward amount after confirm; never surface full fine strategy as primary (design §6 GET).
    public var rewardDisplayCents: Int64? {
        guard status == .confirmed else { return nil }
        return rewardCents
    }
}

public struct UserBlockPage: Codable, Equatable, Sendable {
    public let items: [UserBlock]
    public let nextCursor: String?
    public let page: Int?
    public let pageSize: Int?
    public let total: Int?
    public let hasMore: Bool?

    public init(
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

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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

public struct ReportListPage: Codable, Equatable, Sendable {
    public let items: [Report]
    public let nextCursor: String?

    public init(items: [Report], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([Report].self, forKey: .items)
            ?? c.decodeIfPresent([Report].self, forKey: .reports)
            ?? c.decodeIfPresent([Report].self, forKey: .list)
            ?? []
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
            ?? c.decodeIfPresent(String.self, forKey: .cursor)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(nextCursor, forKey: .nextCursor)
    }

    private enum CodingKeys: String, CodingKey {
        case items, reports, list, nextCursor, cursor
    }
}

// MARK: - Requests

public struct CreateReportRequest: Equatable, Sendable {
    public let targetType: ReportTargetType
    public let targetId: Int64
    public let reason: ReportReason
    public let evidenceUrls: [String]
    public let orderId: Int64?
    public let attachConversation: Bool

    public init(
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

    public var body: [String: Any?] {
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

public struct CreateBlockRequest: Equatable, Sendable {
    public let userId: Int64

    public init(userId: Int64) {
        self.userId = userId
    }

    public var body: [String: Any?] {
        ["user_id": userId]
    }
}

// MARK: - Copy (design §9)

public enum RiskCopy {
    public static let reportTitle = "举报"
    public static let bountyReportTitle = "举报诱导线下"
    public static let reportSuccess = "我们将在 5 个工作日内处理"
    public static let bountyHeld = "查实，奖励将在财务开闸后到账"
    public static let bountyConfirmedPrefix = "查实，奖励 "
    public static let bountyConfirmedSuffix = " 元"
    public static let blockSuccess = "已无法收到对方私信，对方也不能再对你的商品出价"
    public static let blockListTitle = "黑名单"
    public static let blockListEmpty = "还没有拉黑任何人"
    public static let blockConfirmTitle = "拉黑该用户？"
    public static let blockConfirmMessage = "拉黑后双方无法私信；对方也不能再对你的商品出价"
    public static let blockAction = "拉黑"
    public static let unblockAction = "解除拉黑"
    public static let unblockSuccess = "已解除拉黑"
    public static let bidNotAllowed = "当前账号无法对该拍品出价"
    public static let contentRejectedPrefix = "含违规信息，请修改："
    public static let penaltyExpired = "限制已解除"
    public static let penaltyAppealHint = "申诉请回复工单"
    public static let bountyProgressReviewing = "审核中"
    public static let bountyProgressHeld = "已奖励待打款"
    public static let bountyProgressPaid = "已到账"
    public static let attachConversation = "附上本单会话"
    public static let evidenceHint = "请上传聊天截图等证据（最多 9 张）"
    public static let evidenceRequired = "请至少上传 1 张证据图，或勾选附上本单会话"
    public static let reasonPickerHint = "请选择举报原因"
    public static let submitLocked = "提交中…"
    public static let myReportsTitle = "我的举报"
    public static let bountyNotBuyer = "仅本单买家可发起赏金举报"
    public static let reportDuplicate = "你已举报过该对象"
    public static let bountyReporterRestricted = "赏金举报暂不可用，普通内容仍可举报"
    public static let approvalRequired = "处罚待复核"
    public static let cannotBlockSelf = "不能拉黑自己"
    public static let relatedAccountLottery = "当前账号无法报名该抽签"
    public static let blockedByUser = "对方已将你拉黑，无法发送私信"
    public static let penaltyNotActive = "处罚已失效，无法撤销"
    public static let unauthenticated = "请先登录"
    public static let realNameRequired = "赏金举报需先完成实名认证"
    public static let accountFrozen = "账号已冻结，暂不可举报"
    public static let serverTimeHint = "以服务器时间为准"

    public static func bountyRewardNotice(yuanText: String) -> String {
        "\(bountyConfirmedPrefix)\(yuanText)\(bountyConfirmedSuffix)"
    }

    public static func penaltyNotice(reason: String, windowText: String) -> String {
        "\(reason)·\(windowText)·\(penaltyAppealHint)"
    }

    public static func contentRejected(type: ContentReviewRejectReason) -> String {
        type.userMessage
    }
}

// MARK: - Logic

public enum RiskLogic {
    /// Offline fine ladder (design §5.1 / §5.11). `priorConfirmedCount` = seller history before this case.
    public static func offlineFineCents(
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

    public static func bountyRewardCents(
        fineCents: Int64,
        rateBps: Int = RiskConfigDefaults.bountyRateBps
    ) -> Int64 {
        max(0, fineCents * Int64(rateBps) / 10_000)
    }

    /// Split fine into platform fee + bounty (design §5.1 ledger).
    public static func fineSplit(fineCents: Int64, rateBps: Int = RiskConfigDefaults.bountyRateBps) -> (platformFeeCents: Int64, bountyCents: Int64) {
        let bounty = bountyRewardCents(fineCents: fineCents, rateBps: rateBps)
        return (fineCents - bounty, bounty)
    }

    public static func bountyProgressLabel(
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

    public static func createReportGate(
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

    public static func canSubmitReport(
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

    public static func createBlockGate(
        blockerId: Int64?,
        blockedId: Int64,
        isLoggedIn: Bool
    ) -> RiskErrorCode? {
        guard isLoggedIn else { return .unauthenticated }
        if let blockerId, blockerId == blockedId { return .cannotBlockSelf }
        if blockedId <= 0 { return .cannotBlockSelf }
        return nil
    }

    public static func bidDenyMessage(code: String?) -> String {
        if let mapped = RiskErrorCode.normalize(code), mapped.isBidDenied {
            return RiskCopy.bidNotAllowed
        }
        if code == "related_account_forbidden" || code == "blocked_by_seller" || code == "bid_not_allowed" {
            return RiskCopy.bidNotAllowed
        }
        return RiskCopy.bidNotAllowed
    }

    /// Strong-edge related check (design §5.3) — client mirror for explain / tests.
    public static func relatedStrongOverlap(
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

    public static func isWeakIPOnly(
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
