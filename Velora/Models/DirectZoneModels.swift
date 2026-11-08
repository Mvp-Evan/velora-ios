import Foundation

// MARK: - Direct zone + buy-now (DES-v1.3-04-01 — app mirror of VeloraCore)

// MARK: - Direct zone + buy-now (DES-v1.3-04-01 DIR-01/02/04 / D17)

/// Product defaults (design §3 / §5). Hot-config on server; client mirrors for UX.
enum DirectZoneConfigDefaults {
    static let lockMinutes: Int = 15
    static let minPriceFen: Int64 = 100
    static let shippingFeeMaxFen: Int64 = 50_000
    static let hotStockThreshold: Int = 20
    static let priceDropDays: Int = 7
    static let personalStockMax: Int = 1
    static let proxyStockMax: Int = 1
    static let brandStockMax: Int = 9999
    static let brandMaxQtyPerOrder: Int = 5
    static let featuredSlotMax: Int = 3
    static let soldPublicDays: Int = 30
    static let listingsPageSize: Int = 20
    static let listingsPageSizeMax: Int = 50
    static let shipHours: Int = 72
    static let creditMinToBuy: Int = 60
    static let bootstrapFlagKey = "direct_zone.enabled"
}

enum DirectZoneSectionKey: String, Codable, Sendable, CaseIterable, Equatable {
    case new
    case featured
    case priceDrop = "price_drop"
    case brand
    case sold

    var defaultTitle: String {
        switch self {
        case .new: return "最新"
        case .featured: return "精选"
        case .priceDrop: return "降价"
        case .brand: return "品牌直营"
        case .sold: return "已售"
        }
    }

    /// Direct zone listings are personal-only; featured/brand sections are retired.
    var defaultSellerTypes: [DirectZoneSellerType] {
        switch self {
        case .new, .priceDrop, .sold: return [.personal]
        case .featured, .brand: return []
        }
    }

    /// Active zone sections (no featured / 品牌直营).
    var isActiveZoneSection: Bool {
        switch self {
        case .new, .priceDrop, .sold: return true
        case .featured, .brand: return false
        }
    }
}

enum DirectZoneSellerType: String, Codable, Sendable, CaseIterable, Equatable {
    case personal
    case proxyAgent = "proxy_agent"
    case brand

    var isPromotable: Bool { false }

    var stockMax: Int { DirectZoneConfigDefaults.personalStockMax }

    var maxQtyPerOrderCap: Int { 1 }

    /// Direct-zone cards no longer show seller-identity badges (personal-only).
    var showsIdentityBadge: Bool { false }

    var badgeLabel: String? { nil }
}

enum DirectZoneSlotLabel: String, Codable, Sendable, CaseIterable, Equatable {
    case recommend
    case ad

    var displayText: String { self == .ad ? "广告" : "推荐" }
}

enum DirectZoneFilterKey: String, Codable, Sendable, CaseIterable, Equatable {
    case freeShipping = "free_shipping"
    case negotiable
    case brandNew = "brand_new"
    case brandOfficial = "brand_official" // retired quick filter; kept for decode
    case priceRange = "price_range"
    case brandSeries = "brand_series"

    var defaultTitle: String {
        switch self {
        case .freeShipping: return "包邮"
        case .negotiable: return "可议价"
        case .brandNew: return "全新未拆"
        case .brandOfficial: return "品牌直营"
        case .priceRange: return "价格区间"
        case .brandSeries: return "品牌/系列"
        }
    }

    var isActiveQuickFilter: Bool {
        switch self {
        case .freeShipping, .negotiable, .brandNew, .priceRange, .brandSeries: return true
        case .brandOfficial: return false
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "free_shipping": self = .freeShipping
        case "negotiable": self = .negotiable
        case "brand_new", "new_sealed": self = .brandNew
        case "brand_official": self = .brandOfficial
        case "price_range": self = .priceRange
        case "brand_series": self = .brandSeries
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "unknown filter key \(raw)")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Sort inside new / price_drop / brand; featured is heat-only.
enum DirectZoneSort: String, Codable, Sendable, CaseIterable, Equatable {
    case newest
    case priceAsc = "price_asc"
    case priceDesc = "price_desc"
    case heat

    var title: String {
        switch self {
        case .newest: return "最新"
        case .priceAsc: return "价格从低到高"
        case .priceDesc: return "价格从高到低"
        case .heat: return "热度"
        }
    }
}

enum DirectOrderSource: String, Codable, Sendable, CaseIterable, Equatable {
    case directZone = "direct_zone"
    case search
    case detail
    case offer
}

enum ListingLockStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case active, released, consumed
}

/// Stable API error codes (design §6 / §7).
enum DirectZoneErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case invalidSection = "invalid_section"
    case stockInsufficient = "stock_insufficient"
    case listingSoldOut = "listing_sold_out"
    case listingHasPendingOrder = "listing_has_pending_order"
    case promoteNotAllowed = "promote_not_allowed"
    case stockMustBeOne = "stock_must_be_one"
    case selfTradeForbidden = "self_trade_forbidden"
    case priceChanged = "price_changed"
    case realNameRequired = "real_name_required"
    case creditTooLow = "credit_too_low"
    case accountRestricted = "account_restricted"
    case orderNotCancellable = "order_not_cancellable"
    case publishForbidden = "publish_forbidden"
    case unauthorized

    var fallbackMessage: String {
        switch self {
        case .invalidSection:
            return "分区无效"
        case .stockInsufficient:
            return DirectZoneCopy.stockTaken
        case .listingSoldOut:
            return "已售罄"
        case .listingHasPendingOrder:
            return DirectZoneCopy.pendingOrderBlock
        case .promoteNotAllowed:
            return "直购专区不提供精选推荐位"
        case .stockMustBeOne:
            return "直购仅个人卖家且数量须为 1 件"
        case .selfTradeForbidden:
            return "不可购买自己的商品"
        case .priceChanged:
            return DirectZoneCopy.priceChanged
        case .realNameRequired:
            return "请先完成实名认证"
        case .creditTooLow:
            return "信用分不足，暂不可购买"
        case .accountRestricted:
            return "账号受限，暂不可购买"
        case .orderNotCancellable:
            return "订单当前不可取消"
        case .publishForbidden:
            return "当前账号禁止发布"
        case .unauthorized:
            return "请先登录"
        }
    }
}

/// UX copy (design §5.5 / §9). User-visible wording uses 直购 / 立即购买 — never 一口价.
enum DirectZoneCopy {
    static let zoneTitle = "直购专区"
    static let searchPlaceholder = "在直购中搜索"
    static let buyNow = "立即购买"
    static let buyShort = "购买"
    static let submitOrder = "提交订单"
    static let publishFixed = "发布直购"
    static let tradeTypeLabel = "直购"
    static let emptyFilters = "换个条件试试"
    static let clearFilters = "清空筛选"
    static let emptyZone = "暂无直购商品"
    static let emptyZoneHint = "去拍卖看看"
    static let stockTaken = "已被他人拍下，15 分钟内未付款会重新上架"
    static let pendingOrderBlock = "有买家正在付款，请稍后再试"
    static let priceChanged = "价格已变动，请确认后重新提交"
    static let weakNetRetry = "未扣款，可放心重试"
    static let payCountdownHint = "以服务器时间为准"
    static let lockRule = "付款时限 15 分钟"
    static let shipRule = "发货时限 72 小时"
    static let remainingStockPrefix = "仅剩"
    static let priceDropBadge = "降价"
    static let soldOut = "已售罄"
    static let offShelf = "已下架"
    static let goToZone = "去直购专区查看"
}

// MARK: - Config / sections / filters / slots

struct DirectZoneSection: Codable, Equatable, Sendable, Identifiable {
    var id: String { key.rawValue }
    var key: DirectZoneSectionKey
    var title: String
    var enabled: Bool
    var sortOrder: Int
    var sellerTypes: [DirectZoneSellerType]
    var updatedBy: String?

    init(
        key: DirectZoneSectionKey,
        title: String? = nil,
        enabled: Bool = true,
        sortOrder: Int,
        sellerTypes: [DirectZoneSellerType]? = nil,
        updatedBy: String? = nil
    ) {
        self.key = key
        self.title = title ?? key.defaultTitle
        self.enabled = enabled
        self.sortOrder = sortOrder
        self.sellerTypes = sellerTypes ?? key.defaultSellerTypes
        self.updatedBy = updatedBy
    }
}

struct DirectZoneFilterOption: Codable, Equatable, Sendable, Identifiable {
    var id: String { key.rawValue }
    var key: DirectZoneFilterKey
    var title: String
    var enabled: Bool
    var sortOrder: Int

    init(
        key: DirectZoneFilterKey,
        title: String? = nil,
        enabled: Bool = true,
        sortOrder: Int
    ) {
        self.key = key
        self.title = title ?? key.defaultTitle
        self.enabled = enabled
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case key, title, label, enabled, sortOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(DirectZoneFilterKey.self, forKey: .key)
        title = try c.decodeIfPresent(String.self, forKey: .title)
            ?? c.decodeIfPresent(String.self, forKey: .label)
            ?? key.defaultTitle
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(title, forKey: .title)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

struct DirectZoneSlotPublic: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let listingId: Int64
    let position: Int
    let label: DirectZoneSlotLabel
    let startAt: Date?
    let endAt: Date?

    init(
        id: String,
        listingId: Int64,
        position: Int,
        label: DirectZoneSlotLabel,
        startAt: Date? = nil,
        endAt: Date? = nil
    ) {
        self.id = id
        self.listingId = listingId
        self.position = position
        self.label = label
        self.startAt = startAt
        self.endAt = endAt
    }

    enum CodingKeys: String, CodingKey {
        case id, listingId, position, label, startAt, endAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        listingId = try Self.decodeID(c, forKey: .listingId)
        position = try c.decode(Int.self, forKey: .position)
        label = try c.decode(DirectZoneSlotLabel.self, forKey: .label)
        startAt = try c.decodeIfPresent(Date.self, forKey: .startAt)
        endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(listingId, forKey: .listingId)
        try c.encode(position, forKey: .position)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(startAt, forKey: .startAt)
        try c.encodeIfPresent(endAt, forKey: .endAt)
    }

    private static func decodeID(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int64 {
        if let v = try? c.decode(Int64.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int64(s) { return v }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "expected listing id")
    }
}

struct DirectZoneConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var configVersion: String
    var sections: [DirectZoneSection]
    var filters: [DirectZoneFilterOption]
    var featuredSlots: [DirectZoneSlotPublic]
    var lockMinutes: Int?
    var priceDropDays: Int?
    var minPriceFen: Int64?
    var serverTime: Date?

    init(
        enabled: Bool = true,
        configVersion: String = "0",
        sections: [DirectZoneSection] = DirectZoneDefaults.sections,
        filters: [DirectZoneFilterOption] = DirectZoneDefaults.filters,
        featuredSlots: [DirectZoneSlotPublic] = [],
        lockMinutes: Int? = DirectZoneConfigDefaults.lockMinutes,
        priceDropDays: Int? = DirectZoneConfigDefaults.priceDropDays,
        minPriceFen: Int64? = DirectZoneConfigDefaults.minPriceFen,
        serverTime: Date? = nil
    ) {
        self.enabled = enabled
        self.configVersion = configVersion
        self.sections = sections
        self.filters = filters
        self.featuredSlots = featuredSlots
        self.lockMinutes = lockMinutes
        self.priceDropDays = priceDropDays
        self.minPriceFen = minPriceFen
        self.serverTime = serverTime
    }

    enum CodingKeys: String, CodingKey {
        case enabled, configVersion, sections, filters, featuredSlots
        case lockMinutes, priceDropDays, minPriceFen, serverTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        if let s = try? c.decode(String.self, forKey: .configVersion) {
            configVersion = s
        } else if let n = try? c.decode(Int64.self, forKey: .configVersion) {
            configVersion = String(n)
        } else {
            configVersion = "0"
        }
        sections = try c.decodeIfPresent([DirectZoneSection].self, forKey: .sections) ?? DirectZoneDefaults.sections
        filters = try c.decodeIfPresent([DirectZoneFilterOption].self, forKey: .filters) ?? DirectZoneDefaults.filters
        featuredSlots = try c.decodeIfPresent([DirectZoneSlotPublic].self, forKey: .featuredSlots) ?? []
        lockMinutes = try c.decodeIfPresent(Int.self, forKey: .lockMinutes)
        priceDropDays = try c.decodeIfPresent(Int.self, forKey: .priceDropDays)
        minPriceFen = try c.decodeIfPresent(Int64.self, forKey: .minPriceFen)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
    }

    var enabledSections: [DirectZoneSection] {
        sections
            .filter(\.enabled)
            .filter { $0.key.isActiveZoneSection }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var enabledFilters: [DirectZoneFilterOption] {
        filters
            .filter(\.enabled)
            .filter { $0.key.isActiveQuickFilter }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var resolvedLockMinutes: Int {
        lockMinutes ?? DirectZoneConfigDefaults.lockMinutes
    }
}

enum DirectZoneDefaults {
    static let sections: [DirectZoneSection] = [
        DirectZoneSection(key: .new, sortOrder: 1),
        DirectZoneSection(key: .priceDrop, sortOrder: 2),
        DirectZoneSection(key: .sold, sortOrder: 3),
    ]

    static let filters: [DirectZoneFilterOption] = [
        DirectZoneFilterOption(key: .freeShipping, sortOrder: 1),
        DirectZoneFilterOption(key: .negotiable, sortOrder: 2),
        DirectZoneFilterOption(key: .brandNew, sortOrder: 3),
        DirectZoneFilterOption(key: .priceRange, sortOrder: 4),
        DirectZoneFilterOption(key: .brandSeries, sortOrder: 5),
    ]
}

// MARK: - Listings

struct DirectZoneListingsQuery: Equatable, Sendable {
    var section: DirectZoneSectionKey?
    var sort: DirectZoneSort?
    var cursor: String?
    var pageSize: Int
    var q: String?
    var freeShipping: Bool?
    var negotiable: Bool?
    var brandNew: Bool?
    var brandOfficial: Bool?
    var priceMin: Int64?
    var priceMax: Int64?
    var brand: String?
    var series: String?
    var sellerId: Int64?

    init(
        section: DirectZoneSectionKey? = .new,
        sort: DirectZoneSort? = .newest,
        cursor: String? = nil,
        pageSize: Int = DirectZoneConfigDefaults.listingsPageSize,
        q: String? = nil,
        freeShipping: Bool? = nil,
        negotiable: Bool? = nil,
        brandNew: Bool? = nil,
        brandOfficial: Bool? = nil,
        priceMin: Int64? = nil,
        priceMax: Int64? = nil,
        brand: String? = nil,
        series: String? = nil,
        sellerId: Int64? = nil
    ) {
        self.section = section
        self.sort = sort
        self.cursor = cursor
        self.pageSize = pageSize
        self.q = q
        self.freeShipping = freeShipping
        self.negotiable = negotiable
        self.brandNew = brandNew
        self.brandOfficial = brandOfficial
        self.priceMin = priceMin
        self.priceMax = priceMax
        self.brand = brand
        self.series = series
        self.sellerId = sellerId
    }

    var queryItems: [String: String?] {
        [
            "trade_type": "fixed",
            "section": section?.rawValue,
            "sort": sort?.rawValue,
            "cursor": cursor,
            "page_size": "\(min(max(pageSize, 1), DirectZoneConfigDefaults.listingsPageSizeMax))",
            "q": q.flatMap { $0.isEmpty ? nil : $0 },
            "free_shipping": freeShipping == true ? "true" : nil,
            "negotiable": negotiable == true ? "true" : nil,
            "brand_new": brandNew == true ? "true" : nil,
            "brand_official": brandOfficial == true ? "true" : nil,
            "price_min": priceMin.map(String.init),
            "price_max": priceMax.map(String.init),
            "brand": brand.flatMap { $0.isEmpty ? nil : $0 },
            "series": series.flatMap { $0.isEmpty ? nil : $0 },
            "seller_id": sellerId.map(String.init),
        ]
    }

    var hasActiveFilters: Bool {
        freeShipping == true
            || negotiable == true
            || brandNew == true
            || brandOfficial == true
            || priceMin != nil
            || priceMax != nil
            || !(brand ?? "").isEmpty
            || !(series ?? "").isEmpty
            || !(q ?? "").isEmpty
    }

    mutating func clearFilters() {
        freeShipping = nil
        negotiable = nil
        brandNew = nil
        brandOfficial = nil
        priceMin = nil
        priceMax = nil
        brand = nil
        series = nil
        q = nil
    }
}

struct DirectZoneListingCard: Codable, Equatable, Sendable, Identifiable {
    var id: Int64 { listingId }
    let listingId: Int64
    let title: String
    let cover: String?
    let condition: String?
    let price: Int64
    let originalPrice: Int64?
    let freeShipping: Bool?
    let negotiable: Bool?
    let sellerType: DirectZoneSellerType?
    let availableQty: Int?
    let priceDropped: Bool?
    let status: String?
    let slotLabel: DirectZoneSlotLabel?

    init(
        listingId: Int64,
        title: String,
        cover: String? = nil,
        condition: String? = nil,
        price: Int64,
        originalPrice: Int64? = nil,
        freeShipping: Bool? = nil,
        negotiable: Bool? = nil,
        sellerType: DirectZoneSellerType? = nil,
        availableQty: Int? = nil,
        priceDropped: Bool? = nil,
        status: String? = nil,
        slotLabel: DirectZoneSlotLabel? = nil
    ) {
        self.listingId = listingId
        self.title = title
        self.cover = cover
        self.condition = condition
        self.price = price
        self.originalPrice = originalPrice
        self.freeShipping = freeShipping
        self.negotiable = negotiable
        self.sellerType = sellerType
        self.availableQty = availableQty
        self.priceDropped = priceDropped
        self.status = status
        self.slotLabel = slotLabel
    }

    enum CodingKeys: String, CodingKey {
        case listingId, id, title, cover, condition, price, originalPrice
        case freeShipping, negotiable, sellerType, availableQty, priceDropped, status, slotLabel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(Int64.self, forKey: .listingId) {
            listingId = v
        } else if let s = try? c.decode(String.self, forKey: .listingId), let v = Int64(s) {
            listingId = v
        } else if let v = try? c.decode(Int64.self, forKey: .id) {
            listingId = v
        } else if let s = try? c.decode(String.self, forKey: .id), let v = Int64(s) {
            listingId = v
        } else {
            throw DecodingError.dataCorruptedError(forKey: .listingId, in: c, debugDescription: "bad listing id")
        }
        title = try c.decode(String.self, forKey: .title)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        condition = try c.decodeIfPresent(String.self, forKey: .condition)
        price = try c.decode(Int64.self, forKey: .price)
        originalPrice = try c.decodeIfPresent(Int64.self, forKey: .originalPrice)
        freeShipping = try c.decodeIfPresent(Bool.self, forKey: .freeShipping)
        negotiable = try c.decodeIfPresent(Bool.self, forKey: .negotiable)
        sellerType = try c.decodeIfPresent(DirectZoneSellerType.self, forKey: .sellerType)
        availableQty = try c.decodeIfPresent(Int.self, forKey: .availableQty)
        priceDropped = try c.decodeIfPresent(Bool.self, forKey: .priceDropped)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        slotLabel = try c.decodeIfPresent(DirectZoneSlotLabel.self, forKey: .slotLabel)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(listingId, forKey: .listingId)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(cover, forKey: .cover)
        try c.encodeIfPresent(condition, forKey: .condition)
        try c.encode(price, forKey: .price)
        try c.encodeIfPresent(originalPrice, forKey: .originalPrice)
        try c.encodeIfPresent(freeShipping, forKey: .freeShipping)
        try c.encodeIfPresent(negotiable, forKey: .negotiable)
        try c.encodeIfPresent(sellerType, forKey: .sellerType)
        try c.encodeIfPresent(availableQty, forKey: .availableQty)
        try c.encodeIfPresent(priceDropped, forKey: .priceDropped)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(slotLabel, forKey: .slotLabel)
    }

    var showsPriceDrop: Bool {
        priceDropped == true || (originalPrice.map { $0 > price } ?? false)
    }

    /// Brand multi-stock: show 「仅剩 N 件」 when N ≤ 5 (design §5.2).
    var lowStockText: String? {
        guard let qty = availableQty, qty > 1, qty <= 5 else { return nil }
        return "\(DirectZoneCopy.remainingStockPrefix) \(qty) 件"
    }

    var isSold: Bool { status == "sold" || availableQty == 0 }
    var isPurchasable: Bool { status == "on_sale" || (status == nil && !isSold) }
}

struct DirectZoneListingsPage: Decodable, Equatable, Sendable {
    var items: [DirectZoneListingCard]
    var nextCursor: String?
    var total: Int?
    var section: DirectZoneSectionKey?
    var configVersion: String?
    var serverTime: Date?

    init(
        items: [DirectZoneListingCard],
        nextCursor: String? = nil,
        total: Int? = nil,
        section: DirectZoneSectionKey? = nil,
        configVersion: String? = nil,
        serverTime: Date? = nil
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.total = total
        self.section = section
        self.configVersion = configVersion
        self.serverTime = serverTime
    }

    enum CodingKeys: String, CodingKey {
        case items, nextCursor, total, section, configVersion, serverTime, listings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try c.decodeIfPresent([DirectZoneListingCard].self, forKey: .items) {
            self.items = items
        } else if let items = try c.decodeIfPresent([DirectZoneListingCard].self, forKey: .listings) {
            self.items = items
        } else {
            self.items = []
        }
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        section = try c.decodeIfPresent(DirectZoneSectionKey.self, forKey: .section)
        if let s = try? c.decode(String.self, forKey: .configVersion) {
            configVersion = s
        } else if let n = try? c.decode(Int64.self, forKey: .configVersion) {
            configVersion = String(n)
        } else {
            configVersion = nil
        }
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
    }

    var hasMore: Bool { !(nextCursor ?? "").isEmpty }
}

// MARK: - Order preview / create (DIR-02)

struct FixedOrderPreviewRequest: Codable, Equatable, Sendable {
    var qty: Int
    var addressId: Int64
    var expectedPriceFen: Int64?

    init(qty: Int, addressId: Int64, expectedPriceFen: Int64? = nil) {
        self.qty = qty
        self.addressId = addressId
        self.expectedPriceFen = expectedPriceFen
    }
}

struct FixedOrderPreview: Codable, Equatable, Sendable {
    let listingId: Int64
    let qty: Int
    let unitPriceFen: Int64
    let shippingFeeFen: Int64
    let amountFen: Int64
    let availableQty: Int
    let maxQty: Int
    let lockMinutes: Int
    let shipHours: Int
    let title: String?
    let cover: String?
    let condition: String?
    let sellerId: Int64?
    let sellerName: String?
    let sellerType: DirectZoneSellerType?
    let addressId: Int64?
    let serverTime: Date?

    init(
        listingId: Int64,
        qty: Int,
        unitPriceFen: Int64,
        shippingFeeFen: Int64,
        amountFen: Int64,
        availableQty: Int,
        maxQty: Int,
        lockMinutes: Int = DirectZoneConfigDefaults.lockMinutes,
        shipHours: Int = DirectZoneConfigDefaults.shipHours,
        title: String? = nil,
        cover: String? = nil,
        condition: String? = nil,
        sellerId: Int64? = nil,
        sellerName: String? = nil,
        sellerType: DirectZoneSellerType? = nil,
        addressId: Int64? = nil,
        serverTime: Date? = nil
    ) {
        self.listingId = listingId
        self.qty = qty
        self.unitPriceFen = unitPriceFen
        self.shippingFeeFen = shippingFeeFen
        self.amountFen = amountFen
        self.availableQty = availableQty
        self.maxQty = maxQty
        self.lockMinutes = lockMinutes
        self.shipHours = shipHours
        self.title = title
        self.cover = cover
        self.condition = condition
        self.sellerId = sellerId
        self.sellerName = sellerName
        self.sellerType = sellerType
        self.addressId = addressId
        self.serverTime = serverTime
    }

    enum CodingKeys: String, CodingKey {
        case listingId, qty, unitPriceFen, shippingFeeFen, amountFen
        case availableQty, maxQty, lockMinutes, shipHours
        case title, cover, condition, sellerId, sellerName, sellerType, addressId, serverTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listingId = try Self.decodeID(c, .listingId)
        qty = try c.decode(Int.self, forKey: .qty)
        unitPriceFen = try c.decode(Int64.self, forKey: .unitPriceFen)
        shippingFeeFen = try c.decode(Int64.self, forKey: .shippingFeeFen)
        amountFen = try c.decode(Int64.self, forKey: .amountFen)
        availableQty = try c.decode(Int.self, forKey: .availableQty)
        maxQty = try c.decode(Int.self, forKey: .maxQty)
        lockMinutes = try c.decodeIfPresent(Int.self, forKey: .lockMinutes) ?? DirectZoneConfigDefaults.lockMinutes
        shipHours = try c.decodeIfPresent(Int.self, forKey: .shipHours) ?? DirectZoneConfigDefaults.shipHours
        title = try c.decodeIfPresent(String.self, forKey: .title)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        condition = try c.decodeIfPresent(String.self, forKey: .condition)
        sellerId = try? Self.decodeID(c, .sellerId)
        sellerName = try c.decodeIfPresent(String.self, forKey: .sellerName)
        sellerType = try c.decodeIfPresent(DirectZoneSellerType.self, forKey: .sellerType)
        addressId = try? Self.decodeID(c, .addressId)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
    }

    private static func decodeID(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Int64 {
        if let v = try? c.decode(Int64.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int64(s) { return v }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "expected id")
    }

    /// Direct buy is always qty 1 (personal listings only).
    var showsQtyStepper: Bool { false }
}

struct FixedOrderCreateRequest: Codable, Equatable, Sendable {
    var qty: Int
    var addressId: Int64
    var source: DirectOrderSource
    var expectedPriceFen: Int64?

    init(qty: Int, addressId: Int64, source: DirectOrderSource, expectedPriceFen: Int64? = nil) {
        self.qty = qty
        self.addressId = addressId
        self.source = source
        self.expectedPriceFen = expectedPriceFen
    }
}

struct FixedOrderCreateResult: Codable, Equatable, Sendable {
    let orderId: Int64
    let payDeadline: Date
    let serverTime: Date
    let amount: Int64
    let shippingFee: Int64?
    let qty: Int?
    let listingId: Int64?

    init(
        orderId: Int64,
        payDeadline: Date,
        serverTime: Date,
        amount: Int64,
        shippingFee: Int64? = nil,
        qty: Int? = nil,
        listingId: Int64? = nil
    ) {
        self.orderId = orderId
        self.payDeadline = payDeadline
        self.serverTime = serverTime
        self.amount = amount
        self.shippingFee = shippingFee
        self.qty = qty
        self.listingId = listingId
    }

    enum CodingKeys: String, CodingKey {
        case orderId, payDeadline, serverTime, amount, shippingFee, qty, listingId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(Int64.self, forKey: .orderId) {
            orderId = v
        } else if let s = try? c.decode(String.self, forKey: .orderId), let v = Int64(s) {
            orderId = v
        } else {
            throw DecodingError.dataCorruptedError(forKey: .orderId, in: c, debugDescription: "bad order id")
        }
        payDeadline = try c.decode(Date.self, forKey: .payDeadline)
        serverTime = try c.decode(Date.self, forKey: .serverTime)
        amount = try c.decode(Int64.self, forKey: .amount)
        shippingFee = try c.decodeIfPresent(Int64.self, forKey: .shippingFee)
        qty = try c.decodeIfPresent(Int.self, forKey: .qty)
        if let v = try? c.decode(Int64.self, forKey: .listingId) {
            listingId = v
        } else if let s = try? c.decode(String.self, forKey: .listingId), let v = Int64(s) {
            listingId = v
        } else {
            listingId = nil
        }
    }
}

struct ListingStockEvent: Codable, Equatable, Sendable {
    let listingId: Int64
    let availableQty: Int
    let price: Int64
    let status: String
    let version: Int64

    init(listingId: Int64, availableQty: Int, price: Int64, status: String, version: Int64) {
        self.listingId = listingId
        self.availableQty = availableQty
        self.price = price
        self.status = status
        self.version = version
    }
}

struct StockColumns: Equatable, Sendable {
    var stock: Int
    var availableQty: Int
    var reservedQty: Int
    var soldQty: Int

    init(stock: Int, availableQty: Int, reservedQty: Int, soldQty: Int) {
        self.stock = stock
        self.availableQty = availableQty
        self.reservedQty = reservedQty
        self.soldQty = soldQty
    }
}

// MARK: - Logic

enum DirectZoneLogic {
    static func sectionAllows(sellerType: DirectZoneSellerType, section: DirectZoneSectionKey) -> Bool {
        let allowed = section.defaultSellerTypes
        if allowed.isEmpty { return true }
        return allowed.contains(sellerType)
    }

    static func isPromotable(_ sellerType: DirectZoneSellerType?) -> Bool {
        sellerType?.isPromotable == true
    }

    static func maxQtyPerOrder(sellerType: DirectZoneSellerType, availableQty: Int) -> Int {
        max(0, min(sellerType.maxQtyPerOrderCap, availableQty))
    }

    static func stockMax(for sellerType: DirectZoneSellerType) -> Int {
        sellerType.stockMax
    }

    /// stock = available + reserved + sold (design §3 / §5.8).
    static func isStockBalanced(_ cols: StockColumns) -> Bool {
        guard cols.stock >= 0, cols.availableQty >= 0, cols.reservedQty >= 0, cols.soldQty >= 0 else {
            return false
        }
        return cols.stock == cols.availableQty + cols.reservedQty + cols.soldQty
    }

    static func canChangePriceOrOffShelf(reservedQty: Int) -> Bool {
        reservedQty <= 0
    }

    static func computeAmountFen(unitPriceFen: Int64, qty: Int, shippingFeeFen: Int64) -> Int64 {
        unitPriceFen * Int64(qty) + shippingFeeFen
    }

    static func sorts(for section: DirectZoneSectionKey) -> [DirectZoneSort] {
        switch section {
        case .featured: return [.heat]
        case .sold: return [.newest]
        case .new, .priceDrop, .brand: return [.newest, .priceAsc, .priceDesc]
        }
    }

    static func defaultSort(for section: DirectZoneSectionKey) -> DirectZoneSort {
        sorts(for: section).first ?? .newest
    }

    /// Countdown from `pay_deadline - server_time` (design §5.5).
    static func countdownSeconds(payDeadline: Date, serverTime: Date) -> Int {
        max(0, Int(payDeadline.timeIntervalSince(serverTime)))
    }

    static func formatPayCountdown(seconds: Int) -> String {
        let total = max(0, seconds)
        let mm = total / 60
        let ss = total % 60
        return String(format: "%02d:%02d", mm, ss)
    }

    static func payCountdownLine(seconds: Int) -> String {
        "剩余 \(formatPayCountdown(seconds: seconds)) · \(DirectZoneCopy.payCountdownHint)"
    }

    static func validateListingsQuery(_ q: DirectZoneListingsQuery) -> String? {
        if let section = q.section, DirectZoneSectionKey(rawValue: section.rawValue) == nil {
            return "invalid_section"
        }
        if let sort = q.sort {
            let allowed = DirectZoneSort.allCases.map(\.rawValue)
            if !allowed.contains(sort.rawValue) { return "invalid_sort" }
            if let section = q.section, !sorts(for: section).contains(sort) {
                return "invalid_sort"
            }
        }
        let pageSize = q.pageSize
        if pageSize < 1 || pageSize > DirectZoneConfigDefaults.listingsPageSizeMax {
            return "invalid_page_size"
        }
        if let min = q.priceMin, let max = q.priceMax, min > max {
            return "invalid_price_range"
        }
        return nil
    }

    static func validatePublishFixedQty(sellerType: DirectZoneSellerType, qty: Int) -> DirectZoneErrorCode? {
        guard sellerType == .personal, qty == 1 else { return .stockMustBeOne }
        return nil
    }

    static func validateFixedPriceFen(_ priceFen: Int64) -> String? {
        priceFen < DirectZoneConfigDefaults.minPriceFen ? "invalid_price" : nil
    }

    static func validateShippingFeeFen(_ feeFen: Int64) -> String? {
        if feeFen < 0 || feeFen > DirectZoneConfigDefaults.shippingFeeMaxFen {
            return "invalid_shipping_fee"
        }
        return nil
    }

    static func validateOrderPreview(qty: Int, addressId: Int64, expectedPriceFen: Int64?) -> String? {
        if qty != 1 { return "invalid_qty" }
        if addressId <= 0 { return "missing_address" }
        if let p = expectedPriceFen, p < DirectZoneConfigDefaults.minPriceFen {
            return "invalid_price"
        }
        return nil
    }

    static func validateCreateOrder(
        qty: Int,
        addressId: Int64,
        source: DirectOrderSource,
        expectedPriceFen: Int64?
    ) -> String? {
        if let base = validateOrderPreview(qty: qty, addressId: addressId, expectedPriceFen: expectedPriceFen) {
            return base
        }
        _ = source
        return nil
    }

    /// Guest may browse; buy requires login → real-name → credit ≥ 60 (design §5.11).
    static func purchaseGate(
        isLoggedIn: Bool,
        realNameDone: Bool,
        creditScore: Int,
        isRestricted: Bool
    ) -> DirectZoneErrorCode? {
        if !isLoggedIn { return .unauthorized }
        if isRestricted { return .accountRestricted }
        if !realNameDone { return .realNameRequired }
        if creditScore < DirectZoneConfigDefaults.creditMinToBuy { return .creditTooLow }
        return nil
    }
}
