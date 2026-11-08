import Foundation

// MARK: - Brand merchant store + authorization (DES-v1.3-05-03 BRD-01/02/03 / D21 — app mirror of VeloraCore)

/// Product defaults (design §3 / §5 / §15). Hot-config on server; client mirrors for UX.
enum BrandStoreConfigDefaults {
    static let depositFen: Int64 = 1_000_000
    static let depositYuan: Int = 10_000
    static let sellerType = "brand"
    static let inviteSellerType = "brand"
    static let badgeOfficial = "brand_official"
    static let badgeOfficialLabel = "品牌官方"
    static let followTargetType = "brand_store"
    static let followLimit = 200
    static let storeNameMaxLen = 20
    static let announcementMaxLen = 500
    static let introMaxLen = 2_000
    static let logoAspect: Double = 1.0
    static let bannerAspect: Double = 3.0
    static let calendarHorizonDays = 90
    static let n10LeadMinutes = 5
    static let n22DedupeMinutes = 10
    static let authRemindDays: [Int] = [30, 7, 1]
    static let renewMinCoverDays = 90
    static let authDocMaxFiles = 6
    static let inviteRequired = true
    static let followPushOptional = true
    static let n10RespectMuteDefault = false
    static let storePageCacheSeconds = 5
    static let launchGateKey = "launch_gate.brand_merchant"
    static let notifyN10 = "N-10"
    static let notifyN22 = "N-22"
    static let meEntryStore = "store"
    static let forbiddenDictOther = "其他"
    static let shanghaiTimeZoneID = "Asia/Shanghai"
    static let expiresAtUTCHour = 16 // expires_at = day 16:00 UTC (= next 00:00 CST)
}

// MARK: - Store / auth status

/// `brand_profile.status` (design §4).
enum BrandStoreStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pending
    case live
    case frozen

    var displayLabel: String {
        switch self {
        case .pending: return "待上线"
        case .live: return "营业中"
        case .frozen: return "已冻结"
        }
    }

    /// Frozen store is read-only; listing new / reminders stop (design §4 / §13).
    var isReadOnly: Bool { self == .frozen }
    var allowsFollowReminders: Bool { self == .live }
    var showsAsPublicStore: Bool { self == .live || self == .frozen }
}

/// `brand_authorization.status` (design §4).
enum BrandAuthorizationStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pendingReview = "pending_review"
    case active
    case expired
    case revoked

    var displayLabel: String {
        switch self {
        case .pendingReview: return "审核中"
        case .active: return "有效"
        case .expired: return "已过期"
        case .revoked: return "已撤销"
        }
    }

    var allowsPublish: Bool { self == .active }
}

/// `brand_authorization.proof_type` (design §3 / B-17).
enum BrandProofType: String, Codable, Sendable, CaseIterable, Equatable {
    case authLetter = "auth_letter"
    case trademark

    var displayLabel: String {
        switch self {
        case .authLetter: return "品牌授权书"
        case .trademark: return "商标注册证"
        }
    }
}

/// Capability keys for brand merchants (design §3 / 4.2).
enum BrandCapabilityKey: String, Codable, Sendable, CaseIterable, Equatable {
    case canFixed = "can_fixed"
    case canAuction = "can_auction"
    case canSpecialNo = "can_special_no"
    case canSpotRelease = "can_spot_release"
    case canLottery = "can_lottery"
    case canPresale = "can_presale"
    case canStore = "can_store"
    case canVip = "can_vip"
    case canPromote = "can_promote"
    case canBatchList = "can_batch_list"

    var title: String {
        switch self {
        case .canFixed: return "一口价"
        case .canAuction: return "拍卖"
        case .canSpecialNo: return "特殊号拍卖"
        case .canSpotRelease: return "现货发售"
        case .canLottery: return "抽签"
        case .canPresale: return "预售"
        case .canStore: return "品牌店铺"
        case .canVip: return "会员管理"
        case .canPromote: return "推荐位"
        case .canBatchList: return "批量上架"
        }
    }
}

/// Default capability snapshot after brand onboarding approved (design §3).
struct BrandCapabilities: Codable, Equatable, Sendable {
    var canFixed: Bool
    var canAuction: Bool
    var canSpecialNo: Bool
    var canSpotRelease: Bool
    var canLottery: Bool
    var canPresale: Bool
    var canStore: Bool
    var canVip: Bool
    var canPromote: Bool
    var canBatchList: Bool

    /// Design §3: can_auction=false except special-no path; can_special_no / release / store / vip open.
    /// Fixed is personal-only; brand defaults open release / store / vip (not can_fixed).
    static let brandDefaults = BrandCapabilities(
        canFixed: false,
        canAuction: false,
        canSpecialNo: true,
        canSpotRelease: true,
        canLottery: true,
        canPresale: true,
        canStore: true,
        canVip: true,
        canPromote: true,
        canBatchList: true
    )

    init(
        canFixed: Bool = false,
        canAuction: Bool = false,
        canSpecialNo: Bool = false,
        canSpotRelease: Bool = false,
        canLottery: Bool = false,
        canPresale: Bool = false,
        canStore: Bool = false,
        canVip: Bool = false,
        canPromote: Bool = false,
        canBatchList: Bool = false
    ) {
        self.canFixed = canFixed
        self.canAuction = canAuction
        self.canSpecialNo = canSpecialNo
        self.canSpotRelease = canSpotRelease
        self.canLottery = canLottery
        self.canPresale = canPresale
        self.canStore = canStore
        self.canVip = canVip
        self.canPromote = canPromote
        self.canBatchList = canBatchList
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canFixed = try c.decodeIfPresent(Bool.self, forKey: .canFixed) ?? false
        canAuction = try c.decodeIfPresent(Bool.self, forKey: .canAuction) ?? false
        canSpecialNo = try c.decodeIfPresent(Bool.self, forKey: .canSpecialNo) ?? false
        canSpotRelease = try c.decodeIfPresent(Bool.self, forKey: .canSpotRelease) ?? false
        canLottery = try c.decodeIfPresent(Bool.self, forKey: .canLottery) ?? false
        canPresale = try c.decodeIfPresent(Bool.self, forKey: .canPresale) ?? false
        canStore = try c.decodeIfPresent(Bool.self, forKey: .canStore) ?? false
        canVip = try c.decodeIfPresent(Bool.self, forKey: .canVip) ?? false
        canPromote = try c.decodeIfPresent(Bool.self, forKey: .canPromote) ?? false
        canBatchList = try c.decodeIfPresent(Bool.self, forKey: .canBatchList) ?? false
    }

    func allows(_ key: BrandCapabilityKey) -> Bool {
        switch key {
        case .canFixed: return canFixed
        case .canAuction: return canAuction
        case .canSpecialNo: return canSpecialNo
        case .canSpotRelease: return canSpotRelease
        case .canLottery: return canLottery
        case .canPresale: return canPresale
        case .canStore: return canStore
        case .canVip: return canVip
        case .canPromote: return canPromote
        case .canBatchList: return canBatchList
        }
    }

    /// Release entry (现货/抽签/预售) visible only when verified + capability open (design §5.1).
    var showsReleasePublishEntry: Bool {
        canSpotRelease || canLottery || canPresale
    }
}

// MARK: - AuthorizeBrand / publish gate

/// Result of client-side `AuthorizeBrand` check (design §3 / §5.3 / §5.10).
enum BrandAuthorizeResult: Equatable, Sendable {
    case ok(BrandAuthorization)
    case notAuthorized(selected: String, authorized: [BrandAuthorization])
    case expired(BrandAuthorization)
    case notVerified
    case dictOtherForbidden
    case emptyBrand

    var isAllowed: Bool {
        if case .ok = self { return true }
        return false
    }

    var errorCode: BrandStoreErrorCode? {
        switch self {
        case .ok: return nil
        case .notAuthorized: return .brandNotAuthorized
        case .expired: return .brandAuthExpired
        case .notVerified: return .brandNotVerified
        case .dictOtherForbidden: return .brandNotAuthorized
        case .emptyBrand: return .brandNotAuthorized
        }
    }

    var message: String {
        switch self {
        case .ok:
            return ""
        case .notAuthorized(let selected, let authorized):
            let list = authorized.map(\.displayName).joined(separator: "、")
            let names = list.isEmpty ? "（暂无）" : list
            return BrandStoreCopy.notAuthorized(selected: selected, list: names)
        case .expired(let row):
            return BrandStoreCopy.authExpired(brand: row.displayName, date: row.expiresAtDisplay)
        case .notVerified:
            return BrandStoreErrorCode.brandNotVerified.fallbackMessage
        case .dictOtherForbidden:
            return BrandStoreCopy.dictOtherForbidden
        case .emptyBrand:
            return BrandStoreCopy.emptyBrand
        }
    }
}

/// Pure `AuthorizeBrand(seller_id, brand_dict_id, at)` helper (design §3 / §14).
enum BrandAuthorizeLogic {
    /// Active window: `status=active` and `starts_at ≤ at < expires_at` (design §3).
    static func authorize(
        brandDictId: Int64?,
        brandName: String?,
        at: Date,
        authorizations: [BrandAuthorization],
        isBrandVerified: Bool,
        forbidDictOther: Bool = true
    ) -> BrandAuthorizeResult {
        guard isBrandVerified else { return .notVerified }

        let trimmed = (brandName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if brandDictId == nil && trimmed.isEmpty { return .emptyBrand }
        if forbidDictOther, trimmed == BrandStoreConfigDefaults.forbiddenDictOther {
            return .dictOtherForbidden
        }

        let matching: [BrandAuthorization]
        if let id = brandDictId {
            matching = authorizations.filter { $0.brandDictId == id }
        } else {
            matching = authorizations.filter {
                $0.brandName.caseInsensitiveCompare(trimmed) == .orderedSame
            }
        }

        if matching.isEmpty {
            let active = authorizations.filter { $0.status == .active }
            return .notAuthorized(selected: trimmed.isEmpty ? "#\(brandDictId ?? 0)" : trimmed, authorized: active)
        }

        // Prefer an active in-window row; else surface the most recent expired/revoked.
        if let ok = matching.first(where: { $0.isActive(at: at) }) {
            return .ok(ok)
        }
        if let expired = matching.first(where: { $0.status == .expired || $0.isPastExpiry(at: at) }) {
            return .expired(expired)
        }
        if let revoked = matching.first(where: { $0.status == .revoked }) {
            return .notAuthorized(selected: revoked.displayName, authorized: authorizations.filter { $0.status == .active })
        }
        // Not yet started
        let active = authorizations.filter { $0.status == .active }
        return .notAuthorized(selected: trimmed.isEmpty ? "#\(brandDictId ?? 0)" : trimmed, authorized: active)
    }

    /// Dropdown source: only active authorizations (design §6).
    static func activeForForm(_ rows: [BrandAuthorization], at: Date = Date()) -> [BrandAuthorization] {
        rows.filter { $0.isActive(at: at) }.sorted { $0.displayName < $1.displayName }
    }

    /// Auth remind band for merchant home (design §9): T-30 yellow, T-7 red.
    static func remindBand(daysUntilExpiry: Int?) -> BrandAuthRemindBand? {
        guard let days = daysUntilExpiry, days >= 0 else { return nil }
        if days <= 7 { return .red }
        if days <= 30 { return .yellow }
        return nil
    }
}

enum BrandAuthRemindBand: String, Sendable, Equatable {
    case yellow
    case red

    var displayLabel: String {
        switch self {
        case .yellow: return "即将到期"
        case .red: return "紧急续期"
        }
    }
}

// MARK: - Follow / reminder helpers

enum BrandFollowLogic {
    /// Guest cannot follow (design §5.7 / §7).
    static func canFollow(isLoggedIn: Bool) -> BrandStoreErrorCode? {
        isLoggedIn ? nil : .followLoginRequired
    }

    /// Soft cap (design §13).
    static func canAddFollow(currentCount: Int, limit: Int = BrandStoreConfigDefaults.followLimit) -> BrandStoreErrorCode? {
        currentCount >= limit ? .followLimitExceeded : nil
    }

    /// Idempotent follow response merge (design §6).
    static func applyFollowSuccess(
        store: BrandStorePage,
        response: BrandFollowResponse
    ) -> BrandStorePage {
        var next = store
        let wasFollowing = store.viewerFollowing == true
        next.viewerFollowing = true
        if let muted = response.muted {
            next.viewerMuted = muted
        } else if next.viewerMuted == nil {
            next.viewerMuted = false
        }
        if !wasFollowing, response.alreadyFollowing != true {
            next.followerCount = (store.followerCount ?? 0) + 1
        } else if let count = response.followerCount {
            next.followerCount = count
        }
        return next
    }

    static func applyUnfollowSuccess(store: BrandStorePage) -> BrandStorePage {
        var next = store
        let wasFollowing = store.viewerFollowing == true
        next.viewerFollowing = false
        next.viewerMuted = nil
        if wasFollowing {
            next.followerCount = max(0, (store.followerCount ?? 1) - 1)
        }
        return next
    }

    /// Follow button primary label (design §5.2 / §9).
    static func followButtonTitle(following: Bool, muted: Bool?) -> String {
        if !following { return BrandStoreCopy.follow }
        if muted == true { return BrandStoreCopy.followingMuted }
        return BrandStoreCopy.followingReminderOn
    }

    /// N-10 fire_at = start_at − 5min (design §5.9). If already inside window, fire immediately (= now).
    static func n10FireAt(startAt: Date, now: Date = Date(), leadMinutes: Int = BrandStoreConfigDefaults.n10LeadMinutes) -> Date {
        let lead = TimeInterval(leadMinutes * 60)
        let scheduled = startAt.addingTimeInterval(-lead)
        if startAt <= now { return scheduled } // already started — caller should skip send
        return max(scheduled, now)
    }

    /// After start_at, new followers do not get backfilled N-10 (design §5.9).
    static func shouldSendN10(startAt: Date, now: Date = Date()) -> Bool {
        startAt > now
    }
}

/// Store page block order (design §5.8).
enum BrandStoreSection: String, CaseIterable, Sendable, Equatable {
    case banner
    case identity
    case follow
    case announcement
    case onSale
    case calendar
    case intro
    case footer

    var title: String {
        switch self {
        case .banner: return "店招"
        case .identity: return "店名"
        case .follow: return "关注"
        case .announcement: return "公告"
        case .onSale: return "在售"
        case .calendar: return "发售日历"
        case .intro: return "品牌介绍"
        case .footer: return "客服举报"
        }
    }
}

// MARK: - Error codes / copy

enum BrandStoreErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case inviteInvalid = "invite_invalid"
    case inviteQuotaExceeded = "invite_quota_exceeded"
    case brandNotAuthorized = "brand_not_authorized"
    case brandAuthExpired = "brand_auth_expired"
    case brandNotVerified = "brand_not_verified"
    case storeNameTaken = "store_name_taken"
    case storeNameTooSimilar = "store_name_too_similar"
    case storeFrozen = "store_frozen"
    case authorizationRequired = "authorization_required"
    case principalMismatch = "principal_mismatch"
    case followLoginRequired = "follow_login_required"
    case followLimitExceeded = "follow_limit_exceeded"
    case depositRequired = "deposit_required"
    case unauthorized
    case loginRequired = "login_required"

    var opensLogin: Bool {
        self == .unauthorized || self == .loginRequired || self == .followLoginRequired
    }

    var fallbackMessage: String {
        switch self {
        case .inviteInvalid: return "邀请码无效或已过期"
        case .inviteQuotaExceeded: return "邀请码名额已用尽"
        case .brandNotAuthorized: return "只能发布授权品牌范围内的商品"
        case .brandAuthExpired: return "品牌授权已到期，请提交续期后再发布"
        case .brandNotVerified: return "品牌商家未通过认证，无法创建发售"
        case .storeNameTaken: return "店铺名称已被占用"
        case .storeNameTooSimilar: return "店铺名称与已有店铺过于近似，需人工复核"
        case .storeFrozen: return "店铺已冻结，暂不可操作"
        case .authorizationRequired: return "请先提交品牌授权材料"
        case .principalMismatch: return "主理人与执照主体不一致，请补充授权委托"
        case .followLoginRequired: return "登录后即可关注店铺并接收开售提醒"
        case .followLimitExceeded: return "关注店铺已达上限"
        case .depositRequired: return "请先缴纳品牌商家保证金"
        case .unauthorized, .loginRequired: return "请先登录"
        }
    }
}

enum BrandStoreCopy {
    static let officialBadge = BrandStoreConfigDefaults.badgeOfficialLabel
    static let storeTitle = "品牌店铺"
    static let follow = "关注"
    static let followingReminderOn = "开售提醒已开启"
    static let followingMuted = "已关注（提醒已关）"
    static let unfollow = "取消关注"
    static let unfollowConfirm = "将不再收到开售提醒"
    static let followerSuffix = "人关注"
    static let calendarEmpty = "暂无发售，关注以免错过"
    static let onSaleEmpty = "暂无在售商品"
    static let announcementEmpty = "暂无公告"
    static let introEmpty = "暂无品牌介绍"
    static let frozenBanner = "店铺已冻结，仅可浏览"
    static let customerService = "联系客服"
    static let report = "举报"
    static let dictOtherForbidden = "品牌商家不可选择字典「其他」"
    static let emptyBrand = "请选择授权品牌"
    static let personalSellerGate = "品牌入驻需邀请"
    static let depositHint = "品牌保证金 10,000 元"
    static let onboardingSteps = ["邀请码", "资质", "店铺", "结算", "保证金"]

    static func notAuthorized(selected: String, list: String) -> String {
        "只能发布授权品牌：\(list)。当前选择 \(selected) 不在范围内。"
    }

    static func authExpired(brand: String, date: String) -> String {
        "\(brand) 授权已于 \(date) 到期，请提交续期后再发布。"
    }

    static func followerCountLabel(_ count: Int) -> String {
        "\(count)\(followerSuffix)"
    }
}

// MARK: - Validation helpers

enum BrandStoreValidation {
    static func storeNameError(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "请填写店铺名称" }
        if trimmed.count > BrandStoreConfigDefaults.storeNameMaxLen {
            return "店铺名称最多 \(BrandStoreConfigDefaults.storeNameMaxLen) 字"
        }
        if looksLikeContact(trimmed) { return "店铺名称不可含联系方式" }
        return nil
    }

    static func announcementError(_ text: String) -> String? {
        if text.count > BrandStoreConfigDefaults.announcementMaxLen {
            return "公告最多 \(BrandStoreConfigDefaults.announcementMaxLen) 字"
        }
        return nil
    }

    /// Lightweight contact-info sniff (aligned with publish norms).
    static func looksLikeContact(_ text: String) -> Bool {
        let patterns = [
            #"1[3-9]\d{9}"#,
            #"微信|v信|wx|QQ|qq"#,
            #"https?://"#,
        ]
        for p in patterns {
            if text.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        }
        return false
    }

    static func shanghaiTimeZone() -> TimeZone {
        TimeZone(identifier: BrandStoreConfigDefaults.shanghaiTimeZoneID) ?? TimeZone(secondsFromGMT: 8 * 3600)!
    }
}

// MARK: - DTOs

/// One authorization row (merchant/admin; design §6).
struct BrandAuthorization: Codable, Equatable, Sendable, Identifiable {
    let id: Int64?
    let sellerId: Int64?
    let brandDictId: Int64
    let brandName: String
    let proofType: BrandProofType?
    let docUrls: [String]?
    let startsAt: Date?
    let expiresAt: Date?
    let status: BrandAuthorizationStatus
    let rejectReason: String?

    init(
        id: Int64? = nil,
        sellerId: Int64? = nil,
        brandDictId: Int64,
        brandName: String,
        proofType: BrandProofType? = nil,
        docUrls: [String]? = nil,
        startsAt: Date? = nil,
        expiresAt: Date? = nil,
        status: BrandAuthorizationStatus = .pendingReview,
        rejectReason: String? = nil
    ) {
        self.id = id
        self.sellerId = sellerId
        self.brandDictId = brandDictId
        self.brandName = brandName
        self.proofType = proofType
        self.docUrls = docUrls
        self.startsAt = startsAt
        self.expiresAt = expiresAt
        self.status = status
        self.rejectReason = rejectReason
    }

    var displayName: String { brandName.isEmpty ? "#\(brandDictId)" : brandName }

    var expiresAtDisplay: String {
        guard let expiresAt else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = BrandStoreValidation.shanghaiTimeZone()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: expiresAt)
    }

    func isActive(at date: Date) -> Bool {
        guard status == .active else { return false }
        if let startsAt, date < startsAt { return false }
        if let expiresAt, date >= expiresAt { return false }
        return true
    }

    func isPastExpiry(at date: Date) -> Bool {
        if status == .expired { return true }
        if let expiresAt { return date >= expiresAt }
        return false
    }

    func daysUntilExpiry(at date: Date = Date()) -> Int? {
        guard let expiresAt else { return nil }
        let cal = Calendar(identifier: .gregorian)
        var c = cal
        c.timeZone = BrandStoreValidation.shanghaiTimeZone()
        let start = c.startOfDay(for: date)
        let end = c.startOfDay(for: expiresAt)
        return c.dateComponents([.day], from: start, to: end).day
    }
}

struct BrandAuthorizationListResponse: Codable, Equatable, Sendable {
    let items: [BrandAuthorization]

    init(items: [BrandAuthorization] = []) {
        self.items = items
    }
}

/// Upcoming release row on store aggregate / calendar (design §5.2 / §6).
struct BrandUpcomingRelease: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: Int64
    let title: String?
    let cover: String?
    let startAt: Date?
    let releaseMode: String?
    let releaseStatus: String?

    init(
        id: Int64,
        title: String? = nil,
        cover: String? = nil,
        startAt: Date? = nil,
        releaseMode: String? = nil,
        releaseStatus: String? = nil
    ) {
        self.id = id
        self.title = title
        self.cover = cover
        self.startAt = startAt
        self.releaseMode = releaseMode
        self.releaseStatus = releaseStatus
    }

    var displayTitle: String { (title?.isEmpty == false) ? title! : "未命名发售" }

    var modeLabel: String {
        switch (releaseMode ?? "").lowercased() {
        case "spot", "spot_release": return "现货"
        case "lottery": return "抽签"
        case "presale": return "预售"
        default: return releaseMode ?? "发售"
        }
    }
}

// BrandViewerVIP lives in BrandVIPModels.swift (DES-v1.3-05-04 / D22).

/// On-sale listing card embedded in store aggregate (lightweight; design §5.6).
struct BrandOnSaleItem: Codable, Equatable, Sendable, Identifiable, Hashable {
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

    var displayTitle: String { (title?.isEmpty == false) ? title! : "商品" }

    /// Brand store「在售」shows releases / auctions only (fixed is personal-zone).
    var isStoreOnSaleVisible: Bool {
        let t = (tradeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        if t == "fixed" { return false }
        return t == "auction"
            || t.contains("release")
            || t == "lottery"
            || t == "presale"
            || t == "spot"
    }
}

/// `GET /api/v1/brands/{id}` aggregate (design §6).
struct BrandStorePage: Codable, Equatable, Sendable, Identifiable {
    let id: Int64
    let sellerId: Int64?
    var storeName: String
    let logo: String?
    let banner: String?
    let intro: String?
    let announcement: String?
    let badge: String?
    let status: BrandStoreStatus?
    var followerCount: Int?
    let onSaleCount: Int?
    var upcomingReleases: [BrandUpcomingRelease]
    var onSaleItems: [BrandOnSaleItem]
    var viewerFollowing: Bool?
    var viewerMuted: Bool?
    var viewerVip: BrandViewerVIP?

    init(
        id: Int64,
        sellerId: Int64? = nil,
        storeName: String,
        logo: String? = nil,
        banner: String? = nil,
        intro: String? = nil,
        announcement: String? = nil,
        badge: String? = nil,
        status: BrandStoreStatus? = nil,
        followerCount: Int? = nil,
        onSaleCount: Int? = nil,
        upcomingReleases: [BrandUpcomingRelease] = [],
        onSaleItems: [BrandOnSaleItem] = [],
        viewerFollowing: Bool? = nil,
        viewerMuted: Bool? = nil,
        viewerVip: BrandViewerVIP? = nil
    ) {
        self.id = id
        self.sellerId = sellerId
        self.storeName = storeName
        self.logo = logo
        self.banner = banner
        self.intro = intro
        self.announcement = announcement
        self.badge = badge
        self.status = status
        self.followerCount = followerCount
        self.onSaleCount = onSaleCount
        self.upcomingReleases = upcomingReleases
        self.onSaleItems = onSaleItems
        self.viewerFollowing = viewerFollowing
        self.viewerMuted = viewerMuted
        self.viewerVip = viewerVip
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int64.self, forKey: .id)
            ?? c.decodeIfPresent(Int64.self, forKey: .sellerId)
            ?? 0
        sellerId = try c.decodeIfPresent(Int64.self, forKey: .sellerId)
        storeName = try c.decodeIfPresent(String.self, forKey: .storeName) ?? ""
        logo = try c.decodeIfPresent(String.self, forKey: .logo)
        banner = try c.decodeIfPresent(String.self, forKey: .banner)
        intro = try c.decodeIfPresent(String.self, forKey: .intro)
        announcement = try c.decodeIfPresent(String.self, forKey: .announcement)
        badge = try c.decodeIfPresent(String.self, forKey: .badge)
        status = try c.decodeIfPresent(BrandStoreStatus.self, forKey: .status)
        followerCount = try c.decodeIfPresent(Int.self, forKey: .followerCount)
        onSaleCount = try c.decodeIfPresent(Int.self, forKey: .onSaleCount)
        upcomingReleases = try c.decodeIfPresent([BrandUpcomingRelease].self, forKey: .upcomingReleases) ?? []
        onSaleItems = try c.decodeIfPresent([BrandOnSaleItem].self, forKey: .onSaleItems)
            ?? c.decodeIfPresent([BrandOnSaleItem].self, forKey: .onSale) ?? []
        viewerFollowing = try c.decodeIfPresent(Bool.self, forKey: .viewerFollowing)
        viewerMuted = try c.decodeIfPresent(Bool.self, forKey: .viewerMuted)
        viewerVip = try c.decodeIfPresent(BrandViewerVIP.self, forKey: .viewerVip)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(sellerId, forKey: .sellerId)
        try c.encode(storeName, forKey: .storeName)
        try c.encodeIfPresent(logo, forKey: .logo)
        try c.encodeIfPresent(banner, forKey: .banner)
        try c.encodeIfPresent(intro, forKey: .intro)
        try c.encodeIfPresent(announcement, forKey: .announcement)
        try c.encodeIfPresent(badge, forKey: .badge)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(followerCount, forKey: .followerCount)
        try c.encodeIfPresent(onSaleCount, forKey: .onSaleCount)
        try c.encode(upcomingReleases, forKey: .upcomingReleases)
        try c.encode(onSaleItems, forKey: .onSaleItems)
        try c.encodeIfPresent(viewerFollowing, forKey: .viewerFollowing)
        try c.encodeIfPresent(viewerMuted, forKey: .viewerMuted)
        try c.encodeIfPresent(viewerVip, forKey: .viewerVip)
    }

    var isOfficialBadge: Bool {
        (badge ?? "") == BrandStoreConfigDefaults.badgeOfficial
            || badge == SellerBadge.brandOfficial.rawValue
    }

    var officialBadgeLabel: String? {
        isOfficialBadge ? BrandStoreCopy.officialBadge : nil
    }

    var isFrozen: Bool { status == .frozen }

    var followTitle: String {
        BrandFollowLogic.followButtonTitle(following: viewerFollowing == true, muted: viewerMuted)
    }

    /// VIP strip for logged-in viewers when rules exist (05-04); guests leave `viewerVip` nil.
    var showsVipStrip: Bool { viewerVip?.shouldDisplay == true }

    var calendarEmpty: Bool { upcomingReleases.isEmpty }

    enum CodingKeys: String, CodingKey {
        case id, sellerId, storeName, logo, banner, intro, announcement, badge, status
        case followerCount, onSaleCount, upcomingReleases, onSaleItems, onSale
        case viewerFollowing, viewerMuted, viewerVip
    }
}

/// `POST /api/v1/brands/{id}/follow` response (design §6).
struct BrandFollowResponse: Codable, Equatable, Sendable {
    let alreadyFollowing: Bool?
    let muted: Bool?
    let followerCount: Int?
    let following: Bool?

    init(
        alreadyFollowing: Bool? = nil,
        muted: Bool? = nil,
        followerCount: Int? = nil,
        following: Bool? = true
    ) {
        self.alreadyFollowing = alreadyFollowing
        self.muted = muted
        self.followerCount = followerCount
        self.following = following
    }
}

/// `GET /api/v1/brands/{id}/releases` calendar payload.
struct BrandReleaseCalendarResponse: Codable, Equatable, Sendable {
    let items: [BrandUpcomingRelease]

    init(items: [BrandUpcomingRelease] = []) {
        self.items = items
    }

    /// Group by Shanghai calendar day for UI (design §5.6).
    func groupedByDay(calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = BrandStoreValidation.shanghaiTimeZone()
        return c
    }()) -> [(day: Date, releases: [BrandUpcomingRelease])] {
        let keyed = Dictionary(grouping: items.filter { $0.startAt != nil }) { item -> Date in
            calendar.startOfDay(for: item.startAt!)
        }
        return keyed.keys.sorted().map { day in
            let list = (keyed[day] ?? []).sorted {
                ($0.startAt ?? .distantFuture) < ($1.startAt ?? .distantFuture)
            }
            return (day, list)
        }
    }
}

/// Seller-facing store settings projection (`PUT /merchant/v1/store` body subset).
struct BrandStoreUpdateBody: Codable, Equatable, Sendable {
    var banner: String?
    var intro: String?
    var announcement: String?
    var logo: String?

    init(banner: String? = nil, intro: String? = nil, announcement: String? = nil, logo: String? = nil) {
        self.banner = banner
        self.intro = intro
        self.announcement = announcement
        self.logo = logo
    }
}
