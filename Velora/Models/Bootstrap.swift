import Foundation

// MARK: - /me/bootstrap (DES-v1.3-00-02)

/// Response payload for `GET /me/bootstrap` (optional auth).
struct MeBootstrap: Codable, Equatable, Sendable {
    let navSchema: NavSchema
    let publishActions: [PublishAction]
    let me: BootstrapMe?
    let seller: BootstrapSeller?
    let flags: [String: Bool]
    /// Server unix time in milliseconds.
    let serverTime: Int64

    enum CodingKeys: String, CodingKey {
        case navSchema
        case nav
        case publishActions
        case me
        case seller
        case flags
        case serverTime
    }

    init(
        navSchema: NavSchema,
        publishActions: [PublishAction],
        me: BootstrapMe?,
        seller: BootstrapSeller?,
        flags: [String: Bool],
        serverTime: Int64
    ) {
        self.navSchema = navSchema
        self.publishActions = publishActions
        self.me = me
        self.seller = seller
        self.flags = flags
        self.serverTime = serverTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let schema = try c.decodeIfPresent(NavSchema.self, forKey: .navSchema) {
            navSchema = schema
        } else if let schema = try c.decodeIfPresent(NavSchema.self, forKey: .nav) {
            navSchema = schema
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.navSchema,
                .init(codingPath: c.codingPath, debugDescription: "missing nav_schema / nav")
            )
        }
        publishActions = try c.decodeIfPresent([PublishAction].self, forKey: .publishActions) ?? []
        me = try c.decodeIfPresent(BootstrapMe.self, forKey: .me)
        seller = try c.decodeIfPresent(BootstrapSeller.self, forKey: .seller)
        flags = try c.decodeIfPresent([String: Bool].self, forKey: .flags) ?? [:]
        serverTime = Self.decodeServerTimeMs(from: c, forKey: .serverTime)
    }

    /// Accepts unix-ms Int64 or ISO8601 / RFC3339 string (Go `time.Time`).
    private static func decodeServerTimeMs(
        from c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int64 {
        if let ms = try? c.decode(Int64.self, forKey: key) { return ms }
        if let s = try? c.decode(String.self, forKey: key) {
            if let ms = Int64(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return ms
            }
            if let date = APIClient.parseDate(s) {
                return Int64(date.timeIntervalSince1970 * 1000)
            }
        }
        return 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(navSchema, forKey: .navSchema)
        try c.encode(publishActions, forKey: .publishActions)
        try c.encodeIfPresent(me, forKey: .me)
        try c.encodeIfPresent(seller, forKey: .seller)
        try c.encode(flags, forKey: .flags)
        try c.encode(serverTime, forKey: .serverTime)
    }

    var isSeller: Bool { seller != nil }
    var creditScore: Int { me?.creditScore ?? 0 }
    func flag(_ key: String) -> Bool { flags[key] ?? false }
}

struct NavSchema: Codable, Equatable, Sendable {
    let version: Int
    let tabs: [NavTab]
    let meBuyerEntries: [MeEntry]
    let meSellerEntries: [MeEntry]

    enum CodingKeys: String, CodingKey {
        case version, tabs, meBuyerEntries, meSellerEntries
    }

    init(version: Int, tabs: [NavTab], meBuyerEntries: [MeEntry] = [], meSellerEntries: [MeEntry] = []) {
        self.version = version
        self.tabs = tabs
        self.meBuyerEntries = meBuyerEntries
        self.meSellerEntries = meSellerEntries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = Self.decodeVersion(from: c)
        tabs = try c.decodeIfPresent([NavTab].self, forKey: .tabs) ?? []
        meBuyerEntries = try c.decodeIfPresent([MeEntry].self, forKey: .meBuyerEntries) ?? []
        meSellerEntries = try c.decodeIfPresent([MeEntry].self, forKey: .meSellerEntries) ?? []
    }

    /// Accepts Int (`13`) or version strings like `"v13"` / `"13"`.
    private static func decodeVersion(from c: KeyedDecodingContainer<CodingKeys>) -> Int {
        if let v = try? c.decode(Int.self, forKey: .version) { return v }
        if let s = try? c.decode(String.self, forKey: .version) {
            let digits = s.filter(\.isNumber)
            if let n = Int(digits), !digits.isEmpty { return n }
        }
        return 1
    }
}

struct NavTab: Codable, Equatable, Identifiable, Sendable {
    var id: String { key }
    let key: String
    let title: String
    let icon: String?

    init(key: String, title: String, icon: String? = nil) {
        self.key = key
        self.title = title
        self.icon = icon
    }
}

struct PublishAction: Codable, Equatable, Identifiable, Sendable {
    var id: String { key }
    let key: String
    let title: String
    let enabled: Bool
    let requiresCapability: String?

    init(key: String, title: String, enabled: Bool, requiresCapability: String? = nil) {
        self.key = key
        self.title = title
        self.enabled = enabled
        self.requiresCapability = requiresCapability
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        requiresCapability = try c.decodeIfPresent(String.self, forKey: .requiresCapability)
    }
}

struct MeEntry: Codable, Equatable, Identifiable, Sendable {
    var id: String { key }
    let key: String
    let title: String
    let icon: String?
    let enabled: Bool

    init(key: String, title: String, icon: String? = nil, enabled: Bool = true) {
        self.key = key
        self.title = title
        self.icon = icon
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

struct BootstrapMe: Codable, Equatable, Sendable {
    let status: String?
    let realNameStatus: String?
    let creditScore: Int
    let sellerType: String?

    init(status: String? = nil, realNameStatus: String? = nil, creditScore: Int = 0, sellerType: String? = nil) {
        self.status = status
        self.realNameStatus = realNameStatus
        self.creditScore = creditScore
        self.sellerType = sellerType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        realNameStatus = try c.decodeIfPresent(String.self, forKey: .realNameStatus)
        creditScore = try c.decodeIfPresent(Int.self, forKey: .creditScore) ?? 0
        sellerType = try c.decodeIfPresent(String.self, forKey: .sellerType)
    }
}

struct BootstrapSeller: Codable, Equatable, Sendable {
    let sellerType: String
    let capabilities: SellerCapabilities
    let onboardingStatus: String?
    let badge: String?
    /// DES-v1.3-05-01 — drives buyer-visible 金牌代拍 vs 观察期.
    let assessmentLevel: String?

    init(
        sellerType: String,
        capabilities: SellerCapabilities,
        onboardingStatus: String? = nil,
        badge: String? = nil,
        assessmentLevel: String? = nil
    ) {
        self.sellerType = sellerType
        self.capabilities = capabilities
        self.onboardingStatus = onboardingStatus
        self.badge = badge
        self.assessmentLevel = assessmentLevel
    }

    var proxyAssessmentLevel: ProxyAssessmentLevel? {
        assessmentLevel.flatMap(ProxyAssessmentLevel.init(rawValue:))
    }

    var proxyBuyerBadgeLabel: String? {
        ProxyBadgeLogic.buyerVisibleLabel(assessmentLevel: proxyAssessmentLevel, badgeRaw: badge)
    }
}

/// Capability flags from 4.2. Missing keys decode as `false`.
struct SellerCapabilities: Codable, Equatable, Sendable {
    var canFixed: Bool
    var canAuction: Bool
    var canBatchList: Bool
    var canInvoiceService: Bool
    var canSession: Bool
    var canPromote: Bool
    var canSpotRelease: Bool
    var canLottery: Bool
    var canPresale: Bool
    var canSpecialNo: Bool
    var canStore: Bool
    var canVip: Bool

    static let none = SellerCapabilities(
        canFixed: false, canAuction: false, canBatchList: false, canInvoiceService: false,
        canSession: false, canPromote: false, canSpotRelease: false, canLottery: false,
        canPresale: false, canSpecialNo: false, canStore: false, canVip: false
    )

    init(
        canFixed: Bool = false, canAuction: Bool = false, canBatchList: Bool = false,
        canInvoiceService: Bool = false, canSession: Bool = false, canPromote: Bool = false,
        canSpotRelease: Bool = false, canLottery: Bool = false, canPresale: Bool = false,
        canSpecialNo: Bool = false, canStore: Bool = false, canVip: Bool = false
    ) {
        self.canFixed = canFixed
        self.canAuction = canAuction
        self.canBatchList = canBatchList
        self.canInvoiceService = canInvoiceService
        self.canSession = canSession
        self.canPromote = canPromote
        self.canSpotRelease = canSpotRelease
        self.canLottery = canLottery
        self.canPresale = canPresale
        self.canSpecialNo = canSpecialNo
        self.canStore = canStore
        self.canVip = canVip
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canFixed = try c.decodeIfPresent(Bool.self, forKey: .canFixed) ?? false
        canAuction = try c.decodeIfPresent(Bool.self, forKey: .canAuction) ?? false
        canBatchList = try c.decodeIfPresent(Bool.self, forKey: .canBatchList) ?? false
        canInvoiceService = try c.decodeIfPresent(Bool.self, forKey: .canInvoiceService) ?? false
        canSession = try c.decodeIfPresent(Bool.self, forKey: .canSession) ?? false
        canPromote = try c.decodeIfPresent(Bool.self, forKey: .canPromote) ?? false
        canSpotRelease = try c.decodeIfPresent(Bool.self, forKey: .canSpotRelease) ?? false
        canLottery = try c.decodeIfPresent(Bool.self, forKey: .canLottery) ?? false
        canPresale = try c.decodeIfPresent(Bool.self, forKey: .canPresale) ?? false
        canSpecialNo = try c.decodeIfPresent(Bool.self, forKey: .canSpecialNo) ?? false
        canStore = try c.decodeIfPresent(Bool.self, forKey: .canStore) ?? false
        canVip = try c.decodeIfPresent(Bool.self, forKey: .canVip) ?? false
    }

    func allows(_ key: String) -> Bool {
        switch key {
        case "can_fixed": return canFixed
        case "can_auction": return canAuction
        case "can_batch_list": return canBatchList
        case "can_invoice_service": return canInvoiceService
        case "can_session": return canSession
        case "can_promote": return canPromote
        case "can_spot_release": return canSpotRelease
        case "can_lottery": return canLottery
        case "can_presale": return canPresale
        case "can_special_no": return canSpecialNo
        case "can_store": return canStore
        case "can_vip": return canVip
        default: return false
        }
    }
}

// MARK: - Tab key mapping

enum AppTab: String, Hashable, CaseIterable, Sendable {
    case buy
    case community
    case publish
    case inbox
    case me
    /// Legacy nav.v13=false schema
    case home
    case auctions

    /// Map server `tabs[].key` → client tab. Unknown keys return `nil` (ignored).
    static func from(navKey: String) -> AppTab? {
        switch navKey {
        case "buy": return .buy
        case "community": return .community
        case "publish": return .publish
        case "inbox", "messages": return .inbox
        case "me": return .me
        case "home": return .home
        case "auctions": return .auctions
        default: return nil
        }
    }

    var navKey: String { rawValue }

    /// Tabs that require login before selection (publish handled separately).
    var requiresLogin: Bool {
        switch self {
        case .home, .auctions, .buy, .community: return false
        case .publish, .inbox, .me: return true
        }
    }
}

extension NavSchema {
    /// Built-in fallback when `/me/bootstrap` fails — keeps today's hard-coded five tabs.
    static let legacyFallback = NavSchema(
        version: 0,
        tabs: [
            NavTab(key: "home", title: "首页", icon: "house"),
            NavTab(key: "auctions", title: "拍场", icon: "flag.checkered"),
            NavTab(key: "publish", title: "发布", icon: "plus"),
            NavTab(key: "inbox", title: "消息", icon: "bubble.left.and.bubble.right"),
            NavTab(key: "me", title: "我的", icon: "person"),
        ]
    )

    /// Built-in v13 schema used when server asks for new nav but tabs are empty.
    static let v13Default = NavSchema(
        version: 1,
        tabs: [
            NavTab(key: "buy", title: "购买", icon: "bag"),
            NavTab(key: "community", title: "社区", icon: "person.3"),
            NavTab(key: "publish", title: "发布", icon: "plus"),
            NavTab(key: "inbox", title: "消息", icon: "bubble.left.and.bubble.right"),
            NavTab(key: "me", title: "我的", icon: "person"),
        ],
        meBuyerEntries: [
            MeEntry(key: "favorites", title: "收藏", icon: "heart"),
            MeEntry(key: "bought", title: "买到的", icon: "bag"),
            MeEntry(key: "bids", title: "竞拍", icon: "hammer"),
            MeEntry(key: "balance", title: "补款", icon: "yensign.circle"),
            MeEntry(key: "lottery", title: "抽签", icon: "ticket"),
            MeEntry(key: "subscriptions", title: "订阅", icon: "bell"),
            MeEntry(key: "history", title: "足迹", icon: "clock"),
            MeEntry(key: "after_sale", title: "售后", icon: "wrench.and.screwdriver"),
            MeEntry(key: "deposit", title: "保证金", icon: "lock.shield"),
        ],
        meSellerEntries: [
            MeEntry(key: "on_sale", title: "在售", icon: "tag"),
            MeEntry(key: "auctions", title: "拍卖", icon: "flag.checkered"),
            MeEntry(key: "sold", title: "售出", icon: "checkmark.seal"),
            MeEntry(key: "wallet", title: "钱包", icon: "wallet.pass"),
            MeEntry(key: "profit", title: "利润", icon: "chart.line.uptrend.xyaxis"),
            MeEntry(key: "after_sale", title: "售后", icon: "wrench.and.screwdriver"),
            MeEntry(key: "seller_deposit", title: "卖家保证金", icon: "lock.shield"),
            // DES-v1.3-05-01 / ME-04 — server may omit when seller_type ≠ proxy_agent
            MeEntry(key: "invoice", title: "开票", icon: "doc.text"),
            MeEntry(key: "proxy_kpi", title: "代拍考核", icon: "chart.bar"),
            // DES-v1.3-05-03 / ME-05 — filtered to brand + can_store
            MeEntry(key: "store", title: "店铺", icon: "storefront"),
            // DES-v1.3-06-04 / D26 — brand + can_presale → merchant Web (no App export UI)
            MeEntry(
                key: PresaleSummaryConfigDefaults.meEntryKey,
                title: PresaleSummaryConfigDefaults.meEntryTitle,
                icon: PresaleSummaryConfigDefaults.meEntryIcon
            ),
        ]
    )

    /// Resolve known `AppTab`s in schema order; skip unknown keys.
    var resolvedTabs: [(tab: AppTab, meta: NavTab)] {
        tabs.compactMap { meta in
            guard let tab = AppTab.from(navKey: meta.key) else { return nil }
            return (tab, meta)
        }
    }
}

extension MeBootstrap {
    static let legacyFallback = MeBootstrap(
        navSchema: .legacyFallback,
        publishActions: [
            PublishAction(key: "auction", title: "拍卖", enabled: true, requiresCapability: "can_auction"),
        ],
        me: nil,
        seller: nil,
        flags: [:],
        serverTime: 0
    )
}
