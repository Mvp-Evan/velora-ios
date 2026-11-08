import Foundation

// MARK: - Me view / browse history / settings (DES-v1.3-12-01 ME-01～07 / D39)

/// Product defaults (design §3 / §15). Hot-config on server; client mirrors for UX + gates.
public enum MeConfigDefaults {
    public static let showPhase2EntriesKey = "me.show_phase2_entries"
    public static let showPhase2EntriesDefault = false
    public static let historyDays = 90
    public static let historyThrottleSec = 30
    public static let historyExposureSec = 2
    public static let overviewBadgeCacheSec = 5
    public static let overviewBadgeTimeoutMs = 200
    public static let historyPageSize = 20
    public static let badgeCap = 99
    public static let legalLicensesConfigKey = "legal.licenses"
    public static let historyTargetTypeListing = "listing"
    public static let brandDisplayName = "毂毂"
    public static let licensesFooter = "平台不开展官方寄售，不接收实物"
    public static let idempotencyHeader = "Idempotency-Key"
}

// MARK: - View mode (ME-01)

/// `user_prefs.me_view` — buyer | seller.
public enum MeViewMode: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case buyer
    case seller

    public var id: String { rawValue }

    public static func normalize(_ raw: String?) -> MeViewMode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = MeViewMode(rawValue: s) { return exact }
        switch s {
        case "buy", "buyer_view", "me_buyer":
            return .buyer
        case "sell", "seller_view", "me_seller", "merchant":
            return .seller
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .buyer: return MeCopy.buyerTab
        case .seller: return MeCopy.sellerTab
        }
    }
}

// MARK: - Entry codes (ME-02～05 / §5.7)

/// Stable entry `code` — client layouts by code, not title (design §5.7).
public enum MeEntryCode: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    // Buyer
    case fav
    case bought
    case bids
    case balanceDue = "balance_due"
    case lottery
    case subs
    case history
    case afterSaleBuy = "after_sale_buy"
    case depositsBuy = "deposits_buy"
    // Personal / proxy / brand seller
    case onsale
    case auctions
    case sold
    case wallet
    case income
    case afterSaleSell = "after_sale_sell"
    case sellerDeposit = "seller_deposit"
    // Proxy
    case invoice
    case proxyKpi = "proxy_kpi"
    // Brand
    case store
    case releases
    case presaleBooks = "presale_books"
    case vip
    case mergeShip = "merge_ship"

    public var id: String { rawValue }

    /// Normalize design codes + bootstrap legacy keys (`favorites`, `balance`, `on_sale`, …).
    public static func normalize(_ raw: String?) -> MeEntryCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = MeEntryCode(rawValue: s) { return exact }
        switch s {
        case "favorites", "favorite", "favs", "收藏":
            return .fav
        case "orders", "my_bought", "买到的":
            return .bought
        case "my_bids", "bidding", "竞拍":
            return .bids
        case "balance", "balance_pay", "补款":
            return .balanceDue
        case "抽签":
            return .lottery
        case "subscriptions", "subscription", "subscribe", "订阅":
            return .subs
        case "足迹", "browse_history":
            return .history
        case "after_sale", "aftersale", "after_sale_buyer", "售后":
            return .afterSaleBuy
        case "deposit", "deposits", "deposits_buyer", "保证金":
            return .depositsBuy
        case "on_sale", "on-sale", "listing_onsale", "在售":
            return .onsale
        case "auction", "my_auctions", "拍卖":
            return .auctions
        case "售出", "sold_orders":
            return .sold
        case "钱包":
            return .wallet
        case "profit", "利润", "income_profit":
            return .income
        case "after_sale_seller", "售后卖家":
            return .afterSaleSell
        case "卖家保证金", "brand_deposit":
            return .sellerDeposit
        case "开票":
            return .invoice
        case "proxy_assessment", "kpi", "代拍考核":
            return .proxyKpi
        case "店铺", "brand_store":
            return .store
        case "spot_release", "新品发售":
            return .releases
        case "presale_orders", "presale", "预定单":
            return .presaleBooks
        case "brand_vip", "vip_manage":
            return .vip
        case "merge_shipping", "合并发货":
            return .mergeShip
        default:
            return nil
        }
    }

    public var defaultTitle: String {
        switch self {
        case .fav: return "我收藏的"
        case .bought: return "我买到的"
        case .bids: return "我的竞拍"
        case .balanceDue: return "我的补款"
        case .lottery: return "我的抽签"
        case .subs: return "我的订阅"
        case .history: return "浏览足迹"
        case .afterSaleBuy: return "退款售后"
        case .depositsBuy: return "我的保证金"
        case .onsale: return "我的在售"
        case .auctions: return "我的拍卖"
        case .sold: return "我售出的"
        case .wallet: return "我的钱包"
        case .income: return "收入利润"
        case .afterSaleSell: return "退款售后"
        case .sellerDeposit: return "卖家保证金"
        case .invoice: return "开票申请"
        case .proxyKpi: return "代拍考核"
        case .store: return "店铺管理"
        case .releases: return "新品发售"
        case .presaleBooks: return "预定单与补款"
        case .vip: return "VIP 管理"
        case .mergeShip: return "合并发货"
        }
    }

    public var defaultSystemImage: String {
        switch self {
        case .fav: return "heart"
        case .bought: return "bag"
        case .bids: return "hammer"
        case .balanceDue: return "yensign.circle"
        case .lottery: return "ticket"
        case .subs: return "bell"
        case .history: return "clock"
        case .afterSaleBuy, .afterSaleSell: return "wrench.and.screwdriver"
        case .depositsBuy, .sellerDeposit: return "lock.shield"
        case .onsale: return "tag"
        case .auctions: return "flag.checkered"
        case .sold: return "checkmark.seal"
        case .wallet: return "wallet.pass"
        case .income: return "chart.line.uptrend.xyaxis"
        case .invoice: return "doc.text"
        case .proxyKpi: return "chart.bar"
        case .store: return "storefront"
        case .releases: return "sparkles"
        case .presaleBooks: return "list.clipboard"
        case .vip: return "crown"
        case .mergeShip: return "shippingbox"
        }
    }

    /// Buyer matrix column (design §5.7) — always present for all seller types as buyer view.
    public var isBuyerEntry: Bool {
        switch self {
        case .fav, .bought, .bids, .balanceDue, .lottery, .subs, .history, .afterSaleBuy, .depositsBuy:
            return true
        default:
            return false
        }
    }

    public var isPersonalSellerEntry: Bool {
        switch self {
        case .onsale, .auctions, .sold, .wallet, .income, .afterSaleSell, .sellerDeposit:
            return true
        default:
            return false
        }
    }

    public var isProxyOnlyEntry: Bool {
        self == .invoice || self == .proxyKpi
    }

    public var isBrandOnlyEntry: Bool {
        switch self {
        case .store, .releases, .presaleBooks, .vip, .mergeShip:
            return true
        default:
            return false
        }
    }

    /// Phase 2 capability entries that may show「即将开放」when flag off.
    public var isPhase2CapabilityEntry: Bool {
        switch self {
        case .balanceDue, .lottery, .invoice, .proxyKpi, .store, .releases, .presaleBooks, .vip, .mergeShip:
            return true
        default:
            return false
        }
    }
}

/// `reason_code` when `enabled=false` (design §5.7).
public enum MeEntryReasonCode: String, Codable, Sendable, CaseIterable, Equatable {
    case capabilityOff = "capability_off"
    case onboardingPending = "onboarding_pending"
    case comingSoon = "coming_soon"
    case frozen
    case realNameRequired = "real_name_required"

    public static func normalize(_ raw: String?) -> MeEntryReasonCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = MeEntryReasonCode(rawValue: s) { return exact }
        switch s {
        case "capability_disabled", "can_publish_off", "publish_off":
            return .capabilityOff
        case "pending", "onboarding", "reviewing":
            return .onboardingPending
        case "phase2", "not_available", "soon":
            return .comingSoon
        case "account_frozen", "restricted":
            return .frozen
        case "kyc_required", "need_real_name":
            return .realNameRequired
        default:
            return nil
        }
    }

    public var displayMessage: String {
        switch self {
        case .capabilityOff: return MeCopy.reasonCapabilityOff
        case .onboardingPending: return MeCopy.reasonOnboardingPending
        case .comingSoon: return MeCopy.reasonComingSoon
        case .frozen: return MeCopy.reasonFrozen
        case .realNameRequired: return MeCopy.reasonRealNameRequired
        }
    }
}

// MARK: - Seller type for entry matrix

public enum MeSellerType: String, Codable, Sendable, CaseIterable, Equatable {
    case personal
    case proxyAgent = "proxy_agent"
    case brand

    public static func normalize(_ raw: String?) -> MeSellerType? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = MeSellerType(rawValue: s) { return exact }
        switch s {
        case "individual", "person", "c2c":
            return .personal
        case "proxy", "agent", "代拍":
            return .proxyAgent
        case "official", "merchant_brand", "品牌":
            return .brand
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .personal: return "个人卖家"
        case .proxyAgent: return "专职代拍"
        case .brand: return "品牌官方"
        }
    }
}

// MARK: - Overview entry + response (GET /me/overview)

public struct MeOverviewEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { code }
    public let code: String
    public let title: String
    public let badge: Int
    public let enabled: Bool
    public let reasonCode: String?
    public let href: String?
    public let icon: String?

    public init(
        code: String,
        title: String,
        badge: Int = 0,
        enabled: Bool = true,
        reasonCode: String? = nil,
        href: String? = nil,
        icon: String? = nil
    ) {
        self.code = code
        self.title = title
        self.badge = badge
        self.enabled = enabled
        self.reasonCode = reasonCode
        self.href = href
        self.icon = icon
    }

    enum CodingKeys: String, CodingKey {
        case code, title, badge, enabled, reasonCode, href, icon
        case key
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(String.self, forKey: .code)
            ?? c.decodeIfPresent(String.self, forKey: .key)
            ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        badge = try c.decodeIfPresent(Int.self, forKey: .badge) ?? 0
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        reasonCode = try c.decodeIfPresent(String.self, forKey: .reasonCode)
        href = try c.decodeIfPresent(String.self, forKey: .href)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(title, forKey: .title)
        try c.encode(badge, forKey: .badge)
        try c.encode(enabled, forKey: .enabled)
        try c.encodeIfPresent(reasonCode, forKey: .reasonCode)
        try c.encodeIfPresent(href, forKey: .href)
        try c.encodeIfPresent(icon, forKey: .icon)
    }

    public var resolvedCode: MeEntryCode? { MeEntryCode.normalize(code) }
    public var resolvedReason: MeEntryReasonCode? { MeEntryReasonCode.normalize(reasonCode) }
    public var badgeText: String? { MeLogic.badgeText(badge) }
    public var systemImage: String {
        icon ?? resolvedCode?.defaultSystemImage ?? "square.grid.2x2"
    }
}

public struct MeOverviewFlags: Codable, Equatable, Sendable {
    public let showPhase2Entries: Bool

    public init(showPhase2Entries: Bool = MeConfigDefaults.showPhase2EntriesDefault) {
        self.showPhase2Entries = showPhase2Entries
    }

    enum CodingKeys: String, CodingKey {
        case showPhase2Entries
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showPhase2Entries = try c.decodeIfPresent(Bool.self, forKey: .showPhase2Entries)
            ?? MeConfigDefaults.showPhase2EntriesDefault
    }
}

public struct MeOverviewResponse: Decodable, Equatable, Sendable {
    public let view: String
    public let sellerType: String?
    public let entries: [MeOverviewEntry]
    public let badges: [String: Int]?
    public let creditScore: Int
    public let realNameStatus: String?
    public let sellerOnboarding: String?
    public let flags: MeOverviewFlags?
    public let partial: Bool
    public let partialBadges: [String]?
    public let saveBrowseHistory: Bool?
    public let sellerRequired: Bool?

    public init(
        view: String,
        sellerType: String? = nil,
        entries: [MeOverviewEntry] = [],
        badges: [String: Int]? = nil,
        creditScore: Int = 0,
        realNameStatus: String? = nil,
        sellerOnboarding: String? = nil,
        flags: MeOverviewFlags? = nil,
        partial: Bool = false,
        partialBadges: [String]? = nil,
        saveBrowseHistory: Bool? = nil,
        sellerRequired: Bool? = nil
    ) {
        self.view = view
        self.sellerType = sellerType
        self.entries = entries
        self.badges = badges
        self.creditScore = creditScore
        self.realNameStatus = realNameStatus
        self.sellerOnboarding = sellerOnboarding
        self.flags = flags
        self.partial = partial
        self.partialBadges = partialBadges
        self.saveBrowseHistory = saveBrowseHistory
        self.sellerRequired = sellerRequired
    }

    enum CodingKeys: String, CodingKey {
        case view, sellerType, entries, badges, creditScore, realNameStatus
        case sellerOnboarding, flags, partial, partialBadges, saveBrowseHistory, sellerRequired
        case meView
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        view = try c.decodeIfPresent(String.self, forKey: .view)
            ?? c.decodeIfPresent(String.self, forKey: .meView)
            ?? MeViewMode.buyer.rawValue
        sellerType = try c.decodeIfPresent(String.self, forKey: .sellerType)
        entries = try c.decodeIfPresent([MeOverviewEntry].self, forKey: .entries) ?? []
        badges = try c.decodeIfPresent([String: Int].self, forKey: .badges)
        creditScore = try c.decodeIfPresent(Int.self, forKey: .creditScore) ?? 0
        realNameStatus = try c.decodeIfPresent(String.self, forKey: .realNameStatus)
        sellerOnboarding = try c.decodeIfPresent(String.self, forKey: .sellerOnboarding)
        flags = try c.decodeIfPresent(MeOverviewFlags.self, forKey: .flags)
        partial = try c.decodeIfPresent(Bool.self, forKey: .partial) ?? false
        partialBadges = try c.decodeIfPresent([String].self, forKey: .partialBadges)
        saveBrowseHistory = try c.decodeIfPresent(Bool.self, forKey: .saveBrowseHistory)
        sellerRequired = try c.decodeIfPresent(Bool.self, forKey: .sellerRequired)
    }

    public var resolvedView: MeViewMode { MeViewMode.normalize(view) ?? .buyer }
    public var resolvedSellerType: MeSellerType? { MeSellerType.normalize(sellerType) }
    public var showPhase2Entries: Bool {
        flags?.showPhase2Entries ?? MeConfigDefaults.showPhase2EntriesDefault
    }
}

// MARK: - Prefs (PUT /me/prefs)

public struct MePrefs: Decodable, Equatable, Sendable {
    public let meView: String
    public let saveBrowseHistory: Bool
    public let updatedAt: Date?

    public init(meView: String, saveBrowseHistory: Bool = true, updatedAt: Date? = nil) {
        self.meView = meView
        self.saveBrowseHistory = saveBrowseHistory
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case meView, saveBrowseHistory, updatedAt
        case preferredMeView
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meView = try c.decodeIfPresent(String.self, forKey: .meView)
            ?? c.decodeIfPresent(String.self, forKey: .preferredMeView)
            ?? MeViewMode.buyer.rawValue
        saveBrowseHistory = try c.decodeIfPresent(Bool.self, forKey: .saveBrowseHistory) ?? true
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public var resolvedView: MeViewMode { MeViewMode.normalize(meView) ?? .buyer }
}

public struct MePrefsUpdateRequest: Equatable, Sendable {
    public let meView: String?
    public let saveBrowseHistory: Bool?

    public init(meView: String? = nil, saveBrowseHistory: Bool? = nil) {
        self.meView = meView
        self.saveBrowseHistory = saveBrowseHistory
    }

    public var body: [String: Any?] {
        var dict: [String: Any?] = [:]
        if let meView { dict["me_view"] = meView }
        if let saveBrowseHistory { dict["save_browse_history"] = saveBrowseHistory }
        return dict
    }
}

/// Prefs write response may echo prefs and/or full overview (design §4 / §6).
/// Live PUT `/me/prefs` often returns a flat `MeOverview` (`view`/`entries`) instead of `{overview:…}`.
public struct MePrefsUpdateResponse: Decodable, Equatable, Sendable {
    public let prefs: MePrefs?
    public let overview: MeOverviewResponse?
    public let meView: String?
    public let saveBrowseHistory: Bool?
    public let sellerRequired: Bool?

    public init(
        prefs: MePrefs? = nil,
        overview: MeOverviewResponse? = nil,
        meView: String? = nil,
        saveBrowseHistory: Bool? = nil,
        sellerRequired: Bool? = nil
    ) {
        self.prefs = prefs
        self.overview = overview
        self.meView = meView
        self.saveBrowseHistory = saveBrowseHistory
        self.sellerRequired = sellerRequired
    }

    public enum CodingKeys: String, CodingKey {
        case prefs, overview, meView, saveBrowseHistory, sellerRequired
        case view, entries
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prefs = try c.decodeIfPresent(MePrefs.self, forKey: .prefs)
        saveBrowseHistory = try c.decodeIfPresent(Bool.self, forKey: .saveBrowseHistory)
        sellerRequired = try c.decodeIfPresent(Bool.self, forKey: .sellerRequired)

        if let nested = try c.decodeIfPresent(MeOverviewResponse.self, forKey: .overview) {
            overview = nested
        } else if c.contains(.view) || c.contains(.entries) {
            overview = try MeOverviewResponse(from: decoder)
        } else {
            overview = nil
        }

        meView = try c.decodeIfPresent(String.self, forKey: .meView)
            ?? c.decodeIfPresent(String.self, forKey: .view)
            ?? overview?.view
    }

    public var resolvedView: MeViewMode {
        if let overview { return overview.resolvedView }
        if let prefs { return prefs.resolvedView }
        return MeViewMode.normalize(meView) ?? .buyer
    }

    public var isSellerRequired: Bool {
        sellerRequired == true || overview?.sellerRequired == true
    }
}

// MARK: - Browse history (ME-06)

public struct BrowseHistorySoldSnapshot: Codable, Equatable, Sendable {
    public let price: Int64?
    public let soldAt: Date?
    public let tradeType: String?

    public init(price: Int64? = nil, soldAt: Date? = nil, tradeType: String? = nil) {
        self.price = price
        self.soldAt = soldAt
        self.tradeType = tradeType
    }
}

public struct BrowseHistoryItem: Decodable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let targetType: String
    public let targetId: Int64
    public let lastViewedAt: Date?
    public let titleSnapshot: String?
    public let cover: String?
    public let priceSnapshot: Int64?
    public let tradeType: String?
    public let statusSnapshot: String?
    public let soldSnapshot: BrowseHistorySoldSnapshot?
    public let available: Bool?

    public init(
        id: Int64,
        targetType: String = MeConfigDefaults.historyTargetTypeListing,
        targetId: Int64,
        lastViewedAt: Date? = nil,
        titleSnapshot: String? = nil,
        cover: String? = nil,
        priceSnapshot: Int64? = nil,
        tradeType: String? = nil,
        statusSnapshot: String? = nil,
        soldSnapshot: BrowseHistorySoldSnapshot? = nil,
        available: Bool? = true
    ) {
        self.id = id
        self.targetType = targetType
        self.targetId = targetId
        self.lastViewedAt = lastViewedAt
        self.titleSnapshot = titleSnapshot
        self.cover = cover
        self.priceSnapshot = priceSnapshot
        self.tradeType = tradeType
        self.statusSnapshot = statusSnapshot
        self.soldSnapshot = soldSnapshot
        self.available = available
    }

    enum CodingKeys: String, CodingKey {
        case id, targetType, targetId, lastViewedAt, titleSnapshot, cover
        case priceSnapshot, tradeType, statusSnapshot, soldSnapshot, available
        case listingId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        targetType = try c.decodeIfPresent(String.self, forKey: .targetType)
            ?? MeConfigDefaults.historyTargetTypeListing
        targetId = try c.decodeIfPresent(Int64.self, forKey: .targetId)
            ?? c.decodeIfPresent(Int64.self, forKey: .listingId)
            ?? 0
        lastViewedAt = try c.decodeIfPresent(Date.self, forKey: .lastViewedAt)
        titleSnapshot = try c.decodeIfPresent(String.self, forKey: .titleSnapshot)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        priceSnapshot = try c.decodeIfPresent(Int64.self, forKey: .priceSnapshot)
        tradeType = try c.decodeIfPresent(String.self, forKey: .tradeType)
        statusSnapshot = try c.decodeIfPresent(String.self, forKey: .statusSnapshot)
        soldSnapshot = try c.decodeIfPresent(BrowseHistorySoldSnapshot.self, forKey: .soldSnapshot)
        available = try c.decodeIfPresent(Bool.self, forKey: .available)
    }

    public var isUnavailable: Bool {
        if let available { return !available }
        let s = (statusSnapshot ?? "").lowercased()
        return s == "offline" || s == "deleted" || s == "removed" || s == "invalid"
    }

    public var displayTitle: String { titleSnapshot?.isEmpty == false ? titleSnapshot! : MeCopy.historyUntitled }
}

public struct BrowseHistoryListResponse: Decodable, Equatable, Sendable {
    public let items: [BrowseHistoryItem]
    public let nextCursor: String?
    public let total: Int?

    public init(items: [BrowseHistoryItem] = [], nextCursor: String? = nil, total: Int? = nil) {
        self.items = items
        self.nextCursor = nextCursor
        self.total = total
    }

    enum CodingKeys: String, CodingKey {
        case items, nextCursor, total, list, data
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try c.decodeIfPresent([BrowseHistoryItem].self, forKey: .items) {
            self.items = items
        } else if let items = try c.decodeIfPresent([BrowseHistoryItem].self, forKey: .list) {
            self.items = items
        } else if let items = try c.decodeIfPresent([BrowseHistoryItem].self, forKey: .data) {
            self.items = items
        } else {
            self.items = []
        }
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
    }
}

public struct BrowseHistoryRecordRequest: Equatable, Sendable {
    public let listingId: Int64

    public init(listingId: Int64) {
        self.listingId = listingId
    }

    public var body: [String: Any?] {
        ["listing_id": listingId]
    }
}

// MARK: - Settings (ME-07 / GET /me/settings)

public struct MeRealNameProjection: Decodable, Equatable, Sendable {
    public let status: String?
    public let maskedName: String?
    public let idLast4: String?

    public init(status: String? = nil, maskedName: String? = nil, idLast4: String? = nil) {
        self.status = status
        self.maskedName = maskedName
        self.idLast4 = idLast4
    }

    enum CodingKeys: String, CodingKey {
        case status, maskedName, idLast4
        case nameMasked, idNoLast4, realNameStatus
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status)
            ?? c.decodeIfPresent(String.self, forKey: .realNameStatus)
        maskedName = try c.decodeIfPresent(String.self, forKey: .maskedName)
            ?? c.decodeIfPresent(String.self, forKey: .nameMasked)
        idLast4 = try c.decodeIfPresent(String.self, forKey: .idLast4)
            ?? c.decodeIfPresent(String.self, forKey: .idNoLast4)
    }

    public var isVerified: Bool {
        let s = (status ?? "").lowercased()
        return s == "verified" || s == "passed" || s == "done" || s == "approved"
    }

    public var summaryLabel: String {
        if isVerified {
            let name = maskedName ?? "已实名"
            if let last4 = idLast4, !last4.isEmpty {
                return "\(name) · \(last4)"
            }
            return name
        }
        return MeCopy.realNameUnset
    }
}

public struct MeProtocolSign: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(protocolCode)-\(version)" }
    public let protocolCode: String
    public let version: String
    public let signedAt: Date?
    public let contentHash: String?

    public init(
        protocolCode: String,
        version: String,
        signedAt: Date? = nil,
        contentHash: String? = nil
    ) {
        self.protocolCode = protocolCode
        self.version = version
        self.signedAt = signedAt
        self.contentHash = contentHash
    }

    public var displayTitle: String {
        switch protocolCode.lowercased() {
        case "privacy", "privacy_policy":
            return MeCopy.privacyPolicy
        case "user", "user_agreement", "tos", "terms":
            return MeCopy.userAgreement
        default:
            return protocolCode
        }
    }
}

public struct MeSettingsResponse: Decodable, Equatable, Sendable {
    public let realName: MeRealNameProjection?
    public let protocols: [MeProtocolSign]
    public let licenses: [LegalLicense]
    public let saveBrowseHistory: Bool
    public let deletionEligible: Bool?
    public let meView: String?

    public init(
        realName: MeRealNameProjection? = nil,
        protocols: [MeProtocolSign] = [],
        licenses: [LegalLicense] = [],
        saveBrowseHistory: Bool = true,
        deletionEligible: Bool? = nil,
        meView: String? = nil
    ) {
        self.realName = realName
        self.protocols = protocols
        self.licenses = licenses
        self.saveBrowseHistory = saveBrowseHistory
        self.deletionEligible = deletionEligible
        self.meView = meView
    }

    enum CodingKeys: String, CodingKey {
        case realName, protocols, licenses, saveBrowseHistory, deletionEligible, meView
        case realNameProjection, protocolSigns, legalLicenses, canDelete
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        realName = try c.decodeIfPresent(MeRealNameProjection.self, forKey: .realName)
            ?? c.decodeIfPresent(MeRealNameProjection.self, forKey: .realNameProjection)
        protocols = try c.decodeIfPresent([MeProtocolSign].self, forKey: .protocols)
            ?? c.decodeIfPresent([MeProtocolSign].self, forKey: .protocolSigns)
            ?? []
        licenses = try c.decodeIfPresent([LegalLicense].self, forKey: .licenses)
            ?? c.decodeIfPresent([LegalLicense].self, forKey: .legalLicenses)
            ?? []
        saveBrowseHistory = try c.decodeIfPresent(Bool.self, forKey: .saveBrowseHistory) ?? true
        deletionEligible = try c.decodeIfPresent(Bool.self, forKey: .deletionEligible)
            ?? c.decodeIfPresent(Bool.self, forKey: .canDelete)
        meView = try c.decodeIfPresent(String.self, forKey: .meView)
    }
}

// MARK: - Legal licenses (NFR-08 / GET /legal/licenses)

public enum LegalLicenseStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case active
    case pending

    public static func normalize(_ raw: String?) -> LegalLicenseStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = LegalLicenseStatus(rawValue: s) { return exact }
        switch s {
        case "ok", "valid", "issued", "approved":
            return .active
        case "processing", "办理中", "pending_issue", "missing":
            return .pending
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .active: return "有效"
        case .pending: return MeCopy.licensePending
        }
    }
}

public struct LegalLicense: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { licenseNo ?? name }
    public let name: String
    public let licenseNo: String?
    public let issuer: String?
    public let grantedAt: Date?
    public let expiresAt: Date?
    public let imageUrl: String?
    public let status: String

    public init(
        name: String,
        licenseNo: String? = nil,
        issuer: String? = nil,
        grantedAt: Date? = nil,
        expiresAt: Date? = nil,
        imageUrl: String? = nil,
        status: String = LegalLicenseStatus.pending.rawValue
    ) {
        self.name = name
        self.licenseNo = licenseNo
        self.issuer = issuer
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.imageUrl = imageUrl
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case name, licenseNo, issuer, grantedAt, expiresAt, imageUrl, status
        case imageURL, no
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        let decodedStatus = try c.decodeIfPresent(String.self, forKey: .status)
            ?? LegalLicenseStatus.pending.rawValue
        status = decodedStatus
        let rawNo = try c.decodeIfPresent(String.self, forKey: .licenseNo)
            ?? c.decodeIfPresent(String.self, forKey: .no)
        // pending must not fabricate numbers (design §5.9 / §14)
        if LegalLicenseStatus.normalize(decodedStatus) == .pending {
            licenseNo = nil
        } else {
            licenseNo = rawNo
        }
        issuer = try c.decodeIfPresent(String.self, forKey: .issuer)
        grantedAt = try c.decodeIfPresent(Date.self, forKey: .grantedAt)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
            ?? c.decodeIfPresent(String.self, forKey: .imageURL)
    }

    public var resolvedStatus: LegalLicenseStatus {
        LegalLicenseStatus.normalize(status) ?? .pending
    }

    public var isPending: Bool { resolvedStatus == .pending }

    public var displayLicenseNo: String {
        if isPending { return MeCopy.licensePending }
        if let licenseNo, !licenseNo.isEmpty { return licenseNo }
        return MeCopy.licensePending
    }
}

/// Third-party SDK disclosure row (`GET /legal/sdks`, DES-v1.3-14-02).
public struct LegalSDK: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let vendor: String?
    public let purpose: String?
    public let dataTypes: [String]?
    public let privacyURL: String?
    public let platforms: [String]?

    enum CodingKeys: String, CodingKey {
        case name, vendor, purpose, platforms
        case dataTypes = "data_types"
        case privacyURL = "privacy_url"
    }
}

public struct LegalSDKsResponse: Decodable, Equatable, Sendable {
    public let items: [LegalSDK]

    public init(items: [LegalSDK] = []) { self.items = items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([LegalSDK].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey { case items }
}

public struct LegalLicensesResponse: Decodable, Equatable, Sendable {
    public let items: [LegalLicense]
    public let version: String?

    public init(items: [LegalLicense] = [], version: String? = nil) {
        self.items = items
        self.version = version
    }

    enum CodingKeys: String, CodingKey {
        case items, version, licenses, list
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try c.decodeIfPresent([LegalLicense].self, forKey: .items) {
            self.items = items
        } else if let items = try c.decodeIfPresent([LegalLicense].self, forKey: .licenses) {
            self.items = items
        } else if let items = try c.decodeIfPresent([LegalLicense].self, forKey: .list) {
            self.items = items
        } else {
            self.items = []
        }
        version = try c.decodeIfPresent(String.self, forKey: .version)
    }
}

// MARK: - Deletion precheck (ME-07 / ACC-07 entry)

public enum MeDeletionBlockerCode: String, Codable, Sendable, CaseIterable, Equatable {
    case openOrders = "open_orders"
    case openAfterSales = "open_after_sales"
    case frozenDeposits = "frozen_deposits"
    case walletBalance = "wallet_balance"
    case openLottery = "open_lottery"
    case pendingWithdrawals = "pending_withdrawals"

    public static func normalize(_ raw: String?) -> MeDeletionBlockerCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = MeDeletionBlockerCode(rawValue: s) { return exact }
        switch s {
        case "orders", "open_order", "unfinished_orders":
            return .openOrders
        case "after_sales", "open_aftersale", "aftersale":
            return .openAfterSales
        case "deposits", "deposit_frozen", "frozen_deposit":
            return .frozenDeposits
        case "wallet", "balance", "positive_balance":
            return .walletBalance
        case "lottery", "open_lotteries":
            return .openLottery
        case "withdrawals", "pending_withdraw", "withdraw_pending":
            return .pendingWithdrawals
        default:
            return nil
        }
    }

    public var guideAction: String {
        switch self {
        case .openOrders: return MeCopy.blockerGuideOrders
        case .openAfterSales: return MeCopy.blockerGuideAfterSales
        case .frozenDeposits: return MeCopy.blockerGuideDeposits
        case .walletBalance: return MeCopy.blockerGuideWithdraw
        case .openLottery: return MeCopy.blockerGuideLottery
        case .pendingWithdrawals: return MeCopy.blockerGuidePendingWithdraw
        }
    }
}

public struct MeDeletionBlocker: Codable, Equatable, Identifiable, Sendable {
    public var id: String { code ?? hint ?? "\(count)" }
    public let code: String?
    public let count: Int
    public let hint: String?
    public let message: String?

    public init(code: String? = nil, count: Int = 0, hint: String? = nil, message: String? = nil) {
        self.code = code
        self.count = count
        self.hint = hint
        self.message = message
    }

    public var resolvedCode: MeDeletionBlockerCode? { MeDeletionBlockerCode.normalize(code) }

    public var displayText: String {
        if let hint, !hint.isEmpty { return hint }
        if let message, !message.isEmpty { return message }
        if let resolved = resolvedCode {
            return "\(resolved.guideAction)（\(count)）"
        }
        return MeCopy.deletionBlockedGeneric
    }
}

public struct MeDeletionPrecheck: Decodable, Equatable, Sendable {
    public let eligible: Bool
    public let blockers: [MeDeletionBlocker]

    public init(eligible: Bool? = nil, blockers: [MeDeletionBlocker] = []) {
        self.blockers = blockers
        if let eligible {
            self.eligible = eligible
        } else {
            self.eligible = blockers.isEmpty
        }
    }

    enum CodingKeys: String, CodingKey {
        case eligible, blockers, canDelete
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockers = try c.decodeIfPresent([MeDeletionBlocker].self, forKey: .blockers) ?? []
        if let eligible = try c.decodeIfPresent(Bool.self, forKey: .eligible) {
            self.eligible = eligible
        } else if let canDelete = try c.decodeIfPresent(Bool.self, forKey: .canDelete) {
            self.eligible = canDelete
        } else {
            self.eligible = blockers.isEmpty
        }
    }

    public var canDelete: Bool { eligible && blockers.isEmpty }
}

// MARK: - Error codes (design §15)

public enum MeErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case sellerRequired = "seller_required"
    case historyNotFound = "history_not_found"
    case listingNotFound = "listing_not_found"
    case deletionBlocked = "deletion_blocked"
    case capabilityOff = "capability_off"
    case comingSoon = "coming_soon"
    case realNameRequired = "real_name_required"
    case accountRestricted = "account_restricted"
    case unauthorized
    case sellerStateChanged = "seller_state_changed"
    case missingIdempotencyKey = "missing_idempotency_key"

    public var fallbackMessage: String {
        switch self {
        case .sellerRequired: return MeCopy.sellerRequired
        case .historyNotFound: return MeCopy.historyNotFound
        case .listingNotFound: return MeCopy.listingNotFound
        case .deletionBlocked: return MeCopy.deletionBlockedGeneric
        case .capabilityOff: return MeCopy.reasonCapabilityOff
        case .comingSoon: return MeCopy.reasonComingSoon
        case .realNameRequired: return MeCopy.reasonRealNameRequired
        case .accountRestricted: return MeCopy.accountRestricted
        case .unauthorized: return MeCopy.loginRequired
        case .sellerStateChanged: return MeCopy.sellerStateChanged
        case .missingIdempotencyKey: return MeCopy.missingIdempotency
        }
    }
}

// MARK: - Copy (design §9)

public enum MeCopy {
    public static let buyerTab = "买家"
    public static let sellerTab = "卖家"
    public static let settingsTitle = "设置"
    public static let historyTitle = "浏览足迹"
    public static let historyEmpty = "还没有浏览记录"
    public static let historyEmptyHint = "去首页逛逛感兴趣的商品"
    public static let historyClear = "清空"
    public static let historyClearConfirm = "确定清空全部足迹？"
    public static let historyDeleteConfirm = "删除这条足迹？"
    public static let historyUnavailable = "已失效"
    public static let historyUntitled = "商品"
    public static let historySaveOffHint = "已保存的记录仍在，可清空"
    public static let saveBrowseHistory = "保存浏览足迹"
    public static let licensesTitle = "资质公示"
    public static let sdkDisclosureTitle = "第三方信息共享"
    public static let sdkDisclosureEmpty = "暂无 SDK 清单"
    public static let licensePending = "办理中"
    public static let licensesFooter = MeConfigDefaults.licensesFooter
    public static let licensesEmpty = "资质信息加载中"
    public static let realNameTitle = "实名信息"
    public static let realNameUnset = "未认证"
    public static let addressTitle = "收货地址"
    public static let pushSettingsTitle = "推送设置"
    public static let blacklistTitle = "黑名单"
    public static let privacyPolicy = "隐私政策"
    public static let userAgreement = "用户协议"
    public static let deletionTitle = "注销账号"
    public static let sellerOnboardingTitle = "开通个人卖家"
    public static let sellerOnboardingHint = "完成实名 → 协议 → 保证金 → 进件后即可发布"
    public static let sellerOnboardingCTA = "去开通"
    public static let upgradeApp = "请升级 App"
    public static let comingSoonSheet = "即将开放"
    public static let partialBadgesHint = "角标可能不完整，下拉刷新"
    public static let sellerRequired = "请先开通卖家"
    public static let historyNotFound = "足迹不存在"
    public static let listingNotFound = "商品不存在"
    public static let deletionBlockedGeneric = "暂时无法注销，请先处理未完事项"
    public static let reasonCapabilityOff = "发布能力已关闭，进行中的订单继续履约"
    public static let reasonOnboardingPending = "审核中"
    public static let reasonComingSoon = "即将开放"
    public static let reasonFrozen = "账号受限，暂不可用"
    public static let reasonRealNameRequired = "请先完成实名认证"
    public static let accountRestricted = "账号受限"
    public static let loginRequired = "请先登录"
    public static let sellerStateChanged = "卖家状态已变更，请刷新"
    public static let missingIdempotency = "请重试"
    public static let viewSwitchFailed = "切换失败，已恢复"
    public static let blockerGuideOrders = "去订单"
    public static let blockerGuideAfterSales = "去售后"
    public static let blockerGuideDeposits = "去保证金"
    public static let blockerGuideWithdraw = "去提现"
    public static let blockerGuideLottery = "去抽签"
    public static let blockerGuidePendingWithdraw = "等待到账"
    public static let protocolSignedPrefix = "你已于 "
    public static let protocolSignedMid = " 同意 v"
}

// MARK: - Logic

public enum MeLogic {
    /// Badge display: nil when 0; `99+` when >99 (design §9).
    public static func badgeText(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        if count > MeConfigDefaults.badgeCap { return "\(MeConfigDefaults.badgeCap)+" }
        return "\(count)"
    }

    public static func shouldRecordHistory(
        isLoggedIn: Bool,
        saveBrowseHistory: Bool,
        isOwnListing: Bool,
        exposureSeconds: TimeInterval
    ) -> Bool {
        guard isLoggedIn, saveBrowseHistory, !isOwnListing else { return false }
        return exposureSeconds >= TimeInterval(MeConfigDefaults.historyExposureSec)
    }

    /// Client-side throttle key helper (server also enforces 30s).
    public static func throttleAllows(
        lastSentAt: Date?,
        now: Date = Date(),
        throttleSec: Int = MeConfigDefaults.historyThrottleSec
    ) -> Bool {
        guard let lastSentAt else { return true }
        return now.timeIntervalSince(lastSentAt) >= TimeInterval(throttleSec)
    }

    public static func entryVisible(
        code: MeEntryCode,
        view: MeViewMode,
        sellerType: MeSellerType?,
        showPhase2Entries: Bool
    ) -> Bool {
        switch view {
        case .buyer:
            return code.isBuyerEntry
        case .seller:
            guard let sellerType else { return false }
            if code.isBuyerEntry { return false }
            if code.isPersonalSellerEntry {
                // Brand hides personal「卖家保证金」wording but still shows deposit status entry.
                return true
            }
            if code.isProxyOnlyEntry {
                return sellerType == .proxyAgent && (showPhase2Entries || true)
                // Phase 1: only render when identity exists (caller filters absent type).
            }
            if code.isBrandOnlyEntry {
                return sellerType == .brand
            }
            return false
        }
    }

    /// Phase 1: proxy/brand-only codes hidden when that identity is absent.
    public static func shouldRenderEntry(
        code: MeEntryCode,
        sellerType: MeSellerType?,
        showPhase2Entries: Bool
    ) -> Bool {
        if code.isProxyOnlyEntry {
            return sellerType == .proxyAgent
        }
        if code.isBrandOnlyEntry {
            return sellerType == .brand && (showPhase2Entries || true)
        }
        if code.isPhase2CapabilityEntry && code.isBuyerEntry && !showPhase2Entries {
            // Still show buyer Phase-2 shells (补款/抽签) with coming_soon — design §5.2.
            return true
        }
        return true
    }

    public static func sellerDepositTitle(sellerType: MeSellerType?) -> String {
        if sellerType == .brand { return "品牌保证金" }
        return MeEntryCode.sellerDeposit.defaultTitle
    }

    public static func protocolSignedCaption(signedAt: Date?, version: String) -> String {
        let time: String
        if let signedAt {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "yyyy-MM-dd HH:mm"
            time = f.string(from: signedAt)
        } else {
            time = "—"
        }
        return "\(MeCopy.protocolSignedPrefix)\(time)\(MeCopy.protocolSignedMid)\(version)"
    }

    public static func unknownEntryMessage(code: String) -> String {
        _ = code
        return MeCopy.upgradeApp
    }

    /// Merge overview badge onto bootstrap-style entry for transitional UI.
    public static func badge(for code: String, in overview: MeOverviewResponse?) -> Int {
        guard let overview else { return 0 }
        if let entry = overview.entries.first(where: {
            MeEntryCode.normalize($0.code) == MeEntryCode.normalize(code) || $0.code == code
        }) {
            return entry.badge
        }
        if let badges = overview.badges {
            if let v = badges[code] { return v }
            if let normalized = MeEntryCode.normalize(code)?.rawValue, let v = badges[normalized] {
                return v
            }
        }
        return 0
    }
}
