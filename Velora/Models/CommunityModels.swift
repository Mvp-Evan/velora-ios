import Foundation

// MARK: - Community follow / news / UGC (DES-v1.3-12-03 COM-01～07 / D41 — app mirror of VeloraCore)

/// Product defaults (design §15). Hot-config on server; client mirrors for UX + gates.
enum CommunityConfigDefaults {
    static let ugcFlagKey = "community.ugc"
    static let feedFlagKey = "community.feed"
    static let ugcEnabledDefault = false
    static let feedEnabledDefault = false
    static let kolBoostKey = "community.kol_boost"
    static let kolBoostDefault = 1.2
    static let newsOpsAutocloseKey = "news.ops_autoclose"
    static let newsOpsAutocloseDefault = true
    static let newsReviewSlaHours = 4
    static let newsPageSize = 20
    static let followRatePerMin = 30
    static let rankTopN = 5
    static let coverAspect: Double = 16.0 / 9.0
    static let onSaleEmpty = "暂无在售"
    static let brandDisplayName = "毂毂"
    static let idempotencyHeader = "Idempotency-Key"
    static let shanghaiTimeZoneID = "Asia/Shanghai"
}

// MARK: - Followee / identity

/// `follows.followee_type` (design §3).
enum FolloweeType: String, Codable, Sendable, CaseIterable, Equatable {
    case user
    case brand

    static func normalize(_ raw: String?) -> FolloweeType? {
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
enum ProfileIdentity: String, Codable, Sendable, CaseIterable, Equatable {
    case personal
    case proxyGold = "proxy_gold"
    case brandOfficial = "brand_official"
    case kol

    static func normalize(_ raw: String?) -> ProfileIdentity? {
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

    var displayLabel: String {
        switch self {
        case .personal: return CommunityCopy.identityPersonal
        case .proxyGold: return CommunityCopy.identityProxyGold
        case .brandOfficial: return CommunityCopy.identityBrandOfficial
        case .kol: return CommunityCopy.identityKOL
        }
    }

    /// Maps existing home/listing seller badges when present.
    static func fromSellerBadge(_ badge: SellerBadge?) -> ProfileIdentity {
        switch badge {
        case .proxyGold, .proxyProbation: return .proxyGold
        case .brandOfficial: return .brandOfficial
        case .personal, .none: return .personal
        }
    }
}

// MARK: - News stubs (Phase 2 / 3 — decode-ready, C 端仅 published)

enum NewsPostType: String, Codable, Sendable, CaseIterable, Equatable {
    case release
    case inspect
    case lottery
    case preview
    case weeklyRank = "weekly_rank"
    case unknown

    static func normalize(_ raw: String?) -> NewsPostType {
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
    var treatsAsPlainCard: Bool { self == .unknown }
}

enum NewsMountStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case none
    case live
    case invalid

    static func normalize(_ raw: String?) -> NewsMountStatus {
        guard let raw, !raw.isEmpty else { return .none }
        return NewsMountStatus(rawValue: raw.lowercased()) ?? .none
    }

    var isPurchaseDisabled: Bool { self == .invalid || self == .none }
}

enum NewsPostStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case draft
    case inReview = "in_review"
    case rejected
    case published
    case offline

    /// C 端永远不能读到 status!=published (design §15).
    var isVisibleToConsumer: Bool { self == .published }
}

// MARK: - Error codes

enum CommunityErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
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

    static func normalize(_ raw: String?) -> CommunityErrorCode? {
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

    var opensLogin: Bool {
        self == .unauthorized || self == .loginRequired || self == .followLoginRequired
    }

    /// Client rolls back optimistic follow on these (design § client duties / 403·409).
    var requiresFollowRollback: Bool {
        switch self {
        case .cannotFollowSelf, .blockedByPeer, .accountRestricted, .followRateLimited:
            return true
        default:
            return false
        }
    }

    var fallbackMessage: String {
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

enum CommunityCopy {
    static let tabTitle = "社区"
    static let emptyPreview = "本周预展即将上线"
    static let emptyHint = "发售、验牌与抽签资讯将在此呈现"
    static let skeletonHint = "资讯加载中"
    static let composeHidden = "发帖入口即将开放"
    static let follow = "关注"
    static let following = "已关注"
    static let unfollow = "取消关注"
    static let unfollowConfirm = "确定取消关注？"
    static let onSaleSection = "在售"
    static let onSaleEmpty = CommunityConfigDefaults.onSaleEmpty
    static let onSaleSeeAll = "查看在售"
    static let followersLabel = "粉丝"
    static let identityPersonal = "个人"
    static let identityProxyGold = "金牌代拍"
    static let identityBrandOfficial = "品牌官方"
    static let identityKOL = "KOL"
    static let cannotFollowSelf = "不能关注自己"
    static let blockedByPeer = "对方已将你拉黑，无法关注"
    static let newsNotFound = "资讯不存在或已下线"
    static let invalidTransition = "当前状态不可操作"
    static let ugcDisabled = "社区发帖暂未开放"
    static let commentDepthExceeded = "评论最多两级"
    static let followersPrivate = "粉丝列表不可见"
    static let accountRestricted = "账号受限，暂无法关注"
    static let followLoginRequired = "登录后即可关注"
    static let followRateLimited = "操作过于频繁，请稍后再试"
    static let userNotFound = "用户不存在"
    static let mountInvalid = "已下架或结束"
    static let weeklyDisclaimer = "数据不含退款完成订单"

    static func followerCountLabel(_ count: Int) -> String {
        if count >= 10_000 {
            let wan = Double(count) / 10_000.0
            return String(format: "%.1f万粉丝", wan)
        }
        return "\(count) 粉丝"
    }
}

// MARK: - Follow logic (optimistic UI)

enum CommunityFollowLogic {
    /// Guest → login wall; self-follow blocked client-side (design §5.1 / §7).
    static func canFollow(
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
    static func shouldRollbackFollow(httpStatus: Int, code: String? = nil) -> Bool {
        if httpStatus == 403 || httpStatus == 409 { return true }
        if let err = CommunityErrorCode.normalize(code), err.requiresFollowRollback { return true }
        return false
    }

    /// Optimistic toggle: flip following + adjust count.
    static func applyOptimistic(
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

    static func rollback(
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
    static func applyFollowSuccess(
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

    static func applyUnfollowSuccess(
        following: Bool,
        followerCount: Int
    ) -> (following: Bool, followerCount: Int) {
        let next = following ? max(0, followerCount - 1) : max(0, followerCount)
        return (false, next)
    }

    static func followButtonTitle(following: Bool) -> String {
        following ? CommunityCopy.following : CommunityCopy.follow
    }

    /// Phase 3 compose visible only when `community.ugc` is on (design §5.8).
    static func showsComposeButton(ugcEnabled: Bool) -> Bool { ugcEnabled }

    /// Tab empty vs skeleton: Phase 1 empty copy; skeleton while feed loading.
    static func tabPlaceholder(
        isLoading: Bool,
        hasItems: Bool,
        feedEnabled: Bool
    ) -> CommunityTabPlaceholder {
        if hasItems { return .feed }
        if isLoading && feedEnabled { return .skeleton }
        return .emptyPreview
    }
}

enum CommunityTabPlaceholder: String, Sendable, Equatable {
    case emptyPreview
    case skeleton
    case feed
}

// MARK: - DTOs

/// Shared follow write response (users + brands COM-01).
struct CommunityFollowResponse: Codable, Equatable, Sendable {
    let alreadyFollowing: Bool?
    let followerCount: Int?
    let following: Bool?

    init(
        alreadyFollowing: Bool? = nil,
        followerCount: Int? = nil,
        following: Bool? = true
    ) {
        self.alreadyFollowing = alreadyFollowing
        self.followerCount = followerCount
        self.following = following
    }
}

/// On-sale card on profile (design §5.1) — no PII.
struct ProfileOnSaleItem: Codable, Equatable, Sendable, Identifiable, Hashable {
    let listingId: Int64
    let title: String?
    let cover: String?
    let price: Int64?
    let tradeType: String?
    let status: String?

    var id: Int64 { listingId }

    init(
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

    var displayTitle: String {
        (title?.isEmpty == false) ? title! : "商品"
    }

    enum CodingKeys: String, CodingKey {
        case listingId, title, cover, price, tradeType, status, id, listing
    }

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(listingId, forKey: .listingId)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(cover, forKey: .cover)
        try c.encodeIfPresent(price, forKey: .price)
        try c.encodeIfPresent(tradeType, forKey: .tradeType)
        try c.encodeIfPresent(status, forKey: .status)
    }
}

/// `GET /api/v1/users/{id}` homepage (COM-01). Never includes phone/address.
struct PublicUserProfile: Codable, Equatable, Sendable, Identifiable {
    let id: Int64
    var nickname: String
    var avatar: String
    var bio: String?
    var location: String?
    var creditScore: Int
    var soldCount: Int
    var wonCount: Int
    var lotCount: Int
    var identity: ProfileIdentity?
    var kolBadge: Bool?
    var followerCount: Int
    var followingCount: Int?
    var viewerFollowing: Bool?
    var onSaleCount: Int?
    var onSaleItems: [ProfileOnSaleItem]
    var createdAt: Date?

    init(
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

    var resolvedIdentity: ProfileIdentity {
        if kolBadge == true { return .kol }
        return identity ?? .personal
    }

    var isFollowing: Bool { viewerFollowing == true }

    var followTitle: String {
        CommunityFollowLogic.followButtonTitle(following: isFollowing)
    }

    var displayOnSaleCount: Int {
        onSaleCount ?? onSaleItems.count
    }

    /// Coding surface must not expose phone / address (design §5.1 / §8).
    static let forbiddenPublicKeys: Set<String> = [
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

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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
struct NewsPostCard: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: Int64
    let type: String?
    let title: String?
    let cover: String?
    let mountStatus: String?
    let publishedAt: Date?

    init(
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

    var resolvedType: NewsPostType { NewsPostType.normalize(type) }
    var resolvedMountStatus: NewsMountStatus { NewsMountStatus.normalize(mountStatus) }
    var showsInvalidOverlay: Bool { resolvedMountStatus == .invalid }
}

struct NewsFeedResponse: Codable, Equatable, Sendable {
    let items: [NewsPostCard]
    let nextCursor: String?
    let page: Int?
    let total: Int?

    init(
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

    var isEmpty: Bool { items.isEmpty }
}
