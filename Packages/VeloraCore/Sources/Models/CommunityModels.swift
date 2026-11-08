import Foundation

// MARK: - Community follow / news / UGC (DES-v1.3-12-03 COM-01～07 / D41)

/// Product defaults (design §15). Hot-config on server; client mirrors for UX + gates.
public enum CommunityConfigDefaults {
    public static let ugcFlagKey = "community.ugc"
    public static let feedFlagKey = "community.feed"
    public static let ugcEnabledDefault = false
    public static let feedEnabledDefault = false
    public static let kolBoostKey = "community.kol_boost"
    public static let kolBoostDefault = 1.2
    public static let newsOpsAutocloseKey = "news.ops_autoclose"
    public static let newsOpsAutocloseDefault = true
    public static let newsReviewSlaHours = 4
    public static let newsPageSize = 20
    public static let followRatePerMin = 30
    public static let rankTopN = 5
    public static let coverAspect: Double = 16.0 / 9.0
    public static let onSaleEmpty = "暂无在售"
    public static let brandDisplayName = "毂毂"
    public static let idempotencyHeader = "Idempotency-Key"
    public static let shanghaiTimeZoneID = "Asia/Shanghai"
}

// MARK: - Followee / identity

/// `follows.followee_type` (design §3).
public enum FolloweeType: String, Codable, Sendable, CaseIterable, Equatable {
    case user
    case brand

    public static func normalize(_ raw: String?) -> FolloweeType? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "user", "seller", "person":
            return .user
        case "brand", "brand_store", "store":
            return .brand
        default:
            return FolloweeType(rawValue: raw.lowercased())
        }
    }
}

/// Public profile identity chip (design §5.1). KOL is Phase 3.
public enum ProfileIdentity: String, Codable, Sendable, CaseIterable, Equatable {
    case personal
    case proxyGold = "proxy_gold"
    case brandOfficial = "brand_official"
    case kol

    public static func normalize(_ raw: String?) -> ProfileIdentity? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "personal", "individual", "user":
            return .personal
        case "proxy_gold", "gold_proxy", "proxy":
            return .proxyGold
        case "brand_official", "brand", "official":
            return .brandOfficial
        case "kol", "kol_badge":
            return .kol
        default:
            return ProfileIdentity(rawValue: raw.lowercased())
        }
    }

    public var displayLabel: String {
        switch self {
        case .personal: return CommunityCopy.identityPersonal
        case .proxyGold: return CommunityCopy.identityProxyGold
        case .brandOfficial: return CommunityCopy.identityBrandOfficial
        case .kol: return CommunityCopy.identityKOL
        }
    }

    /// Maps existing home/listing seller badges when present.
    public static func fromSellerBadge(_ badge: SellerBadge?) -> ProfileIdentity {
        switch badge {
        case .proxyGold, .proxyProbation: return .proxyGold
        case .brandOfficial: return .brandOfficial
        case .personal, .none: return .personal
        }
    }
}

// MARK: - News stubs (Phase 2 / 3 — decode-ready, C 端仅 published)

public enum NewsPostType: String, Codable, Sendable, CaseIterable, Equatable {
    case release
    case inspect
    case lottery
    case preview
    case weeklyRank = "weekly_rank"
    case unknown

    public static func normalize(_ raw: String?) -> NewsPostType {
        guard let raw, !raw.isEmpty else { return .unknown }
        if let exact = NewsPostType(rawValue: raw.lowercased()) { return exact }
        switch raw.lowercased() {
        case "weekly", "rank", "weekly_report":
            return .weeklyRank
        default:
            return .unknown
        }
    }

    /// Unknown types render as plain图文卡 (design §13).
    public var treatsAsPlainCard: Bool { self == .unknown }
}

public enum NewsMountStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case none
    case live
    case invalid

    public static func normalize(_ raw: String?) -> NewsMountStatus {
        guard let raw, !raw.isEmpty else { return .none }
        return NewsMountStatus(rawValue: raw.lowercased()) ?? .none
    }

    public var isPurchaseDisabled: Bool { self == .invalid || self == .none }
}

public enum NewsPostStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case draft
    case inReview = "in_review"
    case rejected
    case published
    case offline

    /// C 端永远不能读到 status!=published (design §15).
    public var isVisibleToConsumer: Bool { self == .published }
}

// MARK: - Error codes

public enum CommunityErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case cannotFollowSelf = "cannot_follow_self"
    case blockedByPeer = "blocked_by_peer"
    case newsNotFound = "news_not_found"
    case invalidTransition = "invalid_transition"
    case ugcDisabled = "ugc_disabled"
    case commentDepthExceeded = "comment_depth_exceeded"
    case followersPrivate = "followers_private"
    case accountRestricted = "account_restricted"
    case followLoginRequired = "follow_login_required"
    case followRateLimited = "follow_rate_limited"
    case userNotFound = "user_not_found"
    case unauthorized
    case loginRequired = "login_required"

    public static func normalize(_ raw: String?) -> CommunityErrorCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = CommunityErrorCode(rawValue: s) { return exact }
        switch s {
        case "self_follow", "follow_self", "cannot_follow_own":
            return .cannotFollowSelf
        case "user_blocked", "peer_blocked", "blocked_by_user", "blocked":
            return .blockedByPeer
        case "ugc_off", "community_ugc_disabled", "posts_disabled":
            return .ugcDisabled
        case "rate_limited", "follow_rate_exceeded", "too_many_requests":
            return .followRateLimited
        case "login_required", "unauthenticated":
            return .followLoginRequired
        case "frozen", "account_frozen":
            return .accountRestricted
        default:
            return nil
        }
    }

    public var opensLogin: Bool {
        self == .unauthorized || self == .loginRequired || self == .followLoginRequired
    }

    /// Client rolls back optimistic follow on these (design § client duties / 403·409).
    public var requiresFollowRollback: Bool {
        switch self {
        case .cannotFollowSelf, .blockedByPeer, .accountRestricted, .followRateLimited:
            return true
        default:
            return false
        }
    }

    public var fallbackMessage: String {
        switch self {
        case .cannotFollowSelf: return CommunityCopy.cannotFollowSelf
        case .blockedByPeer: return CommunityCopy.blockedByPeer
        case .newsNotFound: return CommunityCopy.newsNotFound
        case .invalidTransition: return CommunityCopy.invalidTransition
        case .ugcDisabled: return CommunityCopy.ugcDisabled
        case .commentDepthExceeded: return CommunityCopy.commentDepthExceeded
        case .followersPrivate: return CommunityCopy.followersPrivate
        case .accountRestricted: return CommunityCopy.accountRestricted
        case .followLoginRequired, .unauthorized, .loginRequired:
            return CommunityCopy.followLoginRequired
        case .followRateLimited: return CommunityCopy.followRateLimited
        case .userNotFound: return CommunityCopy.userNotFound
        }
    }
}

// MARK: - Copy

public enum CommunityCopy {
    public static let tabTitle = "社区"
    public static let emptyPreview = "本周预展即将上线"
    public static let emptyHint = "发售、验牌与抽签资讯将在此呈现"
    public static let skeletonHint = "资讯加载中"
    public static let composeHidden = "发帖入口即将开放"
    public static let follow = "关注"
    public static let following = "已关注"
    public static let unfollow = "取消关注"
    public static let unfollowConfirm = "确定取消关注？"
    public static let onSaleSection = "在售"
    public static let onSaleEmpty = CommunityConfigDefaults.onSaleEmpty
    public static let onSaleSeeAll = "查看在售"
    public static let followersLabel = "粉丝"
    public static let identityPersonal = "个人"
    public static let identityProxyGold = "金牌代拍"
    public static let identityBrandOfficial = "品牌官方"
    public static let identityKOL = "KOL"
    public static let cannotFollowSelf = "不能关注自己"
    public static let blockedByPeer = "对方已将你拉黑，无法关注"
    public static let newsNotFound = "资讯不存在或已下线"
    public static let invalidTransition = "当前状态不可操作"
    public static let ugcDisabled = "社区发帖暂未开放"
    public static let commentDepthExceeded = "评论最多两级"
    public static let followersPrivate = "粉丝列表不可见"
    public static let accountRestricted = "账号受限，暂无法关注"
    public static let followLoginRequired = "登录后即可关注"
    public static let followRateLimited = "操作过于频繁，请稍后再试"
    public static let userNotFound = "用户不存在"
    public static let mountInvalid = "已下架或结束"
    public static let weeklyDisclaimer = "数据不含退款完成订单"

    public static func followerCountLabel(_ count: Int) -> String {
        if count >= 10_000 {
            let wan = Double(count) / 10_000.0
            return String(format: "%.1f万粉丝", wan)
        }
        return "\(count) 粉丝"
    }
}

// MARK: - Follow logic (optimistic UI)

public enum CommunityFollowLogic {
    /// Guest → login wall; self-follow blocked client-side (design §5.1 / §7).
    public static func canFollow(
        isLoggedIn: Bool,
        viewerId: Int64?,
        followeeId: Int64,
        followeeType: FolloweeType = .user
    ) -> CommunityErrorCode? {
        if !isLoggedIn { return .followLoginRequired }
        if followeeType == .user, let viewerId, viewerId == followeeId {
            return .cannotFollowSelf
        }
        if followeeId <= 0 { return .userNotFound }
        return nil
    }

    /// HTTP 403 / 409 force rollback of optimistic follow (design client duties).
    public static func shouldRollbackFollow(httpStatus: Int, code: String? = nil) -> Bool {
        if httpStatus == 403 || httpStatus == 409 { return true }
        if let err = CommunityErrorCode.normalize(code), err.requiresFollowRollback { return true }
        return false
    }

    /// Optimistic toggle: flip following + adjust count.
    public static func applyOptimistic(
        following: Bool,
        followerCount: Int,
        targetFollowing: Bool
    ) -> (following: Bool, followerCount: Int) {
        if following == targetFollowing {
            return (following, max(0, followerCount))
        }
        let nextCount = targetFollowing
            ? followerCount + 1
            : max(0, followerCount - 1)
        return (targetFollowing, nextCount)
    }

    public static func rollback(
        following: Bool,
        followerCount: Int,
        previousFollowing: Bool,
        previousCount: Int
    ) -> (following: Bool, followerCount: Int) {
        _ = following
        _ = followerCount
        return (previousFollowing, max(0, previousCount))
    }

    /// Idempotent follow response merge (design §6 — 200 + already_following).
    public static func applyFollowSuccess(
        following: Bool,
        followerCount: Int,
        response: CommunityFollowResponse
    ) -> (following: Bool, followerCount: Int) {
        let wasFollowing = following
        var nextCount = followerCount
        if let server = response.followerCount {
            nextCount = server
        } else if !wasFollowing, response.alreadyFollowing != true {
            nextCount = followerCount + 1
        }
        return (true, max(0, nextCount))
    }

    public static func applyUnfollowSuccess(
        following: Bool,
        followerCount: Int
    ) -> (following: Bool, followerCount: Int) {
        let next = following ? max(0, followerCount - 1) : max(0, followerCount)
        return (false, next)
    }

    public static func followButtonTitle(following: Bool) -> String {
        following ? CommunityCopy.following : CommunityCopy.follow
    }

    /// Phase 3 compose visible only when `community.ugc` is on (design §5.8).
    public static func showsComposeButton(ugcEnabled: Bool) -> Bool { ugcEnabled }

    /// Tab empty vs skeleton: Phase 1 empty copy; skeleton while feed loading.
    public static func tabPlaceholder(
        isLoading: Bool,
        hasItems: Bool,
        feedEnabled: Bool
    ) -> CommunityTabPlaceholder {
        if hasItems { return .feed }
        if isLoading && feedEnabled { return .skeleton }
        return .emptyPreview
    }
}

public enum CommunityTabPlaceholder: String, Sendable, Equatable {
    case emptyPreview
    case skeleton
    case feed
}

// MARK: - DTOs

/// Shared follow write response (users + brands COM-01).
public struct CommunityFollowResponse: Codable, Equatable, Sendable {
    public let alreadyFollowing: Bool?
    public let followerCount: Int?
    public let following: Bool?

    public init(
        alreadyFollowing: Bool? = nil,
        followerCount: Int? = nil,
        following: Bool? = true
    ) {
        self.alreadyFollowing = alreadyFollowing
        self.followerCount = followerCount
        self.following = following
    }
}

/// On-sale card on public profile (design §5.1) — no PII.
public struct ProfileOnSaleItem: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let listingId: Int64
    public let title: String?
    public let cover: String?
    public let price: Int64?
    public let tradeType: String?
    public let status: String?

    public var id: Int64 { listingId }

    public init(
        listingId: Int64,
        title: String? = nil,
        cover: String? = nil,
        price: Int64? = nil,
        tradeType: String? = nil,
        status: String? = nil
    ) {
        self.listingId = listingId
        self.title = title
        self.cover = cover
        self.price = price
        self.tradeType = tradeType
        self.status = status
    }

    public var displayTitle: String {
        (title?.isEmpty == false) ? title! : "商品"
    }

    enum CodingKeys: String, CodingKey {
        case listingId, title, cover, price, tradeType, status, id, listing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listingId = try c.decodeIfPresent(Int64.self, forKey: .listingId)
            ?? c.decodeIfPresent(Int64.self, forKey: .id)
            ?? c.decodeIfPresent(Int64.self, forKey: .listing)
            ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        price = try c.decodeIfPresent(Int64.self, forKey: .price)
        tradeType = try c.decodeIfPresent(String.self, forKey: .tradeType)
        status = try c.decodeIfPresent(String.self, forKey: .status)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(listingId, forKey: .listingId)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(cover, forKey: .cover)
        try c.encodeIfPresent(price, forKey: .price)
        try c.encodeIfPresent(tradeType, forKey: .tradeType)
        try c.encodeIfPresent(status, forKey: .status)
    }
}

/// `GET /api/v1/users/{id}` public homepage (COM-01). Never includes phone/address.
public struct PublicUserProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public var nickname: String
    public var avatar: String
    public var bio: String?
    public var location: String?
    public var creditScore: Int
    public var soldCount: Int
    public var wonCount: Int
    public var lotCount: Int
    public var identity: ProfileIdentity?
    public var kolBadge: Bool?
    public var followerCount: Int
    public var followingCount: Int?
    public var viewerFollowing: Bool?
    public var onSaleCount: Int?
    public var onSaleItems: [ProfileOnSaleItem]
    public var createdAt: Date?

    public init(
        id: Int64,
        nickname: String,
        avatar: String = "",
        bio: String? = nil,
        location: String? = nil,
        creditScore: Int = 100,
        soldCount: Int = 0,
        wonCount: Int = 0,
        lotCount: Int = 0,
        identity: ProfileIdentity? = nil,
        kolBadge: Bool? = nil,
        followerCount: Int = 0,
        followingCount: Int? = nil,
        viewerFollowing: Bool? = nil,
        onSaleCount: Int? = nil,
        onSaleItems: [ProfileOnSaleItem] = [],
        createdAt: Date? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.avatar = avatar
        self.bio = bio
        self.location = location
        self.creditScore = creditScore
        self.soldCount = soldCount
        self.wonCount = wonCount
        self.lotCount = lotCount
        self.identity = identity
        self.kolBadge = kolBadge
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.viewerFollowing = viewerFollowing
        self.onSaleCount = onSaleCount
        self.onSaleItems = onSaleItems
        self.createdAt = createdAt
    }

    public var resolvedIdentity: ProfileIdentity {
        if kolBadge == true { return .kol }
        return identity ?? .personal
    }

    public var isFollowing: Bool { viewerFollowing == true }

    public var followTitle: String {
        CommunityFollowLogic.followButtonTitle(following: isFollowing)
    }

    public var displayOnSaleCount: Int {
        onSaleCount ?? onSaleItems.count
    }

    /// Coding surface must not expose phone / address (design §5.1 / §8).
    public static let forbiddenPublicKeys: Set<String> = [
        "phone", "phone_masked", "phoneMasked", "mobile",
        "address", "addresses", "detail_address",
    ]

    enum CodingKeys: String, CodingKey {
        case id, nickname, avatar, bio, location, creditScore
        case soldCount, wonCount, lotCount
        case identity, identityBadge, sellerBadge, badge
        case kolBadge, followerCount, followingCount
        case viewerFollowing, onSaleCount, onSaleItems, onSale
        case createdAt
        // Intentionally omitted: phone, phoneMasked, address
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? "用户\(id % 10_000)"
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        creditScore = try c.decodeIfPresent(Int.self, forKey: .creditScore) ?? 100
        soldCount = try c.decodeIfPresent(Int.self, forKey: .soldCount) ?? 0
        wonCount = try c.decodeIfPresent(Int.self, forKey: .wonCount) ?? 0
        lotCount = try c.decodeIfPresent(Int.self, forKey: .lotCount) ?? 0
        if let raw = try c.decodeIfPresent(String.self, forKey: .identity) {
            identity = ProfileIdentity.normalize(raw)
        } else if let raw = try c.decodeIfPresent(String.self, forKey: .identityBadge) {
            identity = ProfileIdentity.normalize(raw)
        } else if let raw = try c.decodeIfPresent(String.self, forKey: .sellerBadge) {
            identity = ProfileIdentity.normalize(raw)
        } else if let raw = try c.decodeIfPresent(String.self, forKey: .badge) {
            identity = ProfileIdentity.normalize(raw)
        } else {
            identity = nil
        }
        kolBadge = try c.decodeIfPresent(Bool.self, forKey: .kolBadge)
        followerCount = try c.decodeIfPresent(Int.self, forKey: .followerCount) ?? 0
        followingCount = try c.decodeIfPresent(Int.self, forKey: .followingCount)
        viewerFollowing = try c.decodeIfPresent(Bool.self, forKey: .viewerFollowing)
        onSaleCount = try c.decodeIfPresent(Int.self, forKey: .onSaleCount)
        onSaleItems = try c.decodeIfPresent([ProfileOnSaleItem].self, forKey: .onSaleItems)
            ?? c.decodeIfPresent([ProfileOnSaleItem].self, forKey: .onSale)
            ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(nickname, forKey: .nickname)
        try c.encode(avatar, forKey: .avatar)
        try c.encodeIfPresent(bio, forKey: .bio)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encode(creditScore, forKey: .creditScore)
        try c.encode(soldCount, forKey: .soldCount)
        try c.encode(wonCount, forKey: .wonCount)
        try c.encode(lotCount, forKey: .lotCount)
        try c.encodeIfPresent(identity?.rawValue, forKey: .identity)
        try c.encodeIfPresent(kolBadge, forKey: .kolBadge)
        try c.encode(followerCount, forKey: .followerCount)
        try c.encodeIfPresent(followingCount, forKey: .followingCount)
        try c.encodeIfPresent(viewerFollowing, forKey: .viewerFollowing)
        try c.encodeIfPresent(onSaleCount, forKey: .onSaleCount)
        try c.encode(onSaleItems, forKey: .onSaleItems)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

/// Phase 2 news card (decode stub; feed empty in Phase 1).
public struct NewsPostCard: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let type: String?
    public let title: String?
    public let cover: String?
    public let mountStatus: String?
    public let publishedAt: Date?

    public init(
        id: Int64,
        type: String? = nil,
        title: String? = nil,
        cover: String? = nil,
        mountStatus: String? = nil,
        publishedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.cover = cover
        self.mountStatus = mountStatus
        self.publishedAt = publishedAt
    }

    public var resolvedType: NewsPostType { NewsPostType.normalize(type) }
    public var resolvedMountStatus: NewsMountStatus { NewsMountStatus.normalize(mountStatus) }
    public var showsInvalidOverlay: Bool { resolvedMountStatus == .invalid }
}

public struct NewsFeedResponse: Codable, Equatable, Sendable {
    public let items: [NewsPostCard]
    public let nextCursor: String?
    public let page: Int?
    public let total: Int?

    public init(
        items: [NewsPostCard] = [],
        nextCursor: String? = nil,
        page: Int? = nil,
        total: Int? = nil
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.page = page
        self.total = total
    }

    public var isEmpty: Bool { items.isEmpty }
}
