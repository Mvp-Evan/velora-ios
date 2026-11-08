import Foundation

// MARK: - Search / filter / sold (DES-v1.3-02-02 / HOME-02/03/08/10/12/13)

/// Stable search error codes from the API (DES §6).
public enum SearchErrorCode: String, Codable, Sendable {
    case loginRequired = "login_required"
    case savedSearchLimitExceeded = "saved_search_limit_exceeded"
    case shortcutLimitExceeded = "shortcut_limit_exceeded"
    case filterConflict = "filter_conflict"
    case invalidPriceRange = "invalid_price_range"
    case contactInfoForbidden = "contact_info_forbidden"
    case listingNotPublic = "listing_not_public"
    case savedSearchNotFound = "saved_search_not_found"

    public var fallbackMessage: String {
        switch self {
        case .loginRequired: return "请先登录"
        case .savedSearchLimitExceeded: return "最多保存 20 条订阅"
        case .shortcutLimitExceeded: return "最多 12 个快捷词"
        case .filterConflict: return "已成交与即将结束不可同时筛选"
        case .invalidPriceRange: return "最低价不能高于最高价"
        case .contactInfoForbidden: return "快捷词不能包含联系方式"
        case .listingNotPublic: return "该商品已退出公开检索"
        case .savedSearchNotFound: return "订阅不存在"
        }
    }
}

public enum EndingWithin: String, Codable, Sendable, CaseIterable, Hashable {
    case oneHour = "1h"
    case tonight
    case twentyFourHours = "24h"

    public var title: String {
        switch self {
        case .oneHour: return "1小时内"
        case .tonight: return "今晚结束"
        case .twentyFourHours: return "24小时内"
        }
    }
}

public enum ListingSearchSort: String, Codable, Sendable, CaseIterable, Hashable {
    case comprehensive
    case endingSoon = "ending_soon"
    case heat
    case newest
    case priceAsc = "price_asc"
    case priceDesc = "price_desc"

    public var title: String {
        switch self {
        case .comprehensive: return "综合"
        case .endingSoon: return "即将结束"
        case .heat: return "最热"
        case .newest: return "最新"
        case .priceAsc: return "价格↑"
        case .priceDesc: return "价格↓"
        }
    }
}

public enum SavedSearchNotifyType: String, Codable, Sendable, CaseIterable, Hashable {
    case newList = "new_list"
    case newLive = "new_live"
    case priceDrop = "price_drop"
    case endingSoon = "ending_soon"

    public var title: String {
        switch self {
        case .newList: return "新上架"
        case .newLive: return "开拍"
        case .priceDrop: return "降价"
        case .endingSoon: return "即将结束"
        }
    }
}

public enum SavedSearchStatus: String, Codable, Sendable {
    case active, paused, deleted
}

public enum SoldPriceDisplayKind: String, Codable, Sendable {
    case hammer
    case list
}

/// Limits from DES §5 / §6.
public enum SearchLimits {
    public static let maxShortcuts = 12
    public static let maxSavedSearches = 20
    public static let shortcutWordMin = 1
    public static let shortcutWordMax = 20
    public static let historyMax = 20
    public static let pageSizeMax = 50
    public static let soldPublicDays = 30
    public static let endingSoonMinutes = 30
    public static let savedSearchSoftWarnAt = 18
}

/// Query for `GET /api/v1/listings` (DES §6). All filters AND; time windows mutually exclusive.
public struct ListingSearchQuery: Equatable, Sendable, Hashable {
    public var q: String?
    public var brand: String?
    public var series: String?
    public var scale: String?
    public var condition: String?
    public var tradeType: String?
    public var status: String?
    public var priceMin: Int64?
    public var priceMax: Int64?
    public var freeShipping: Bool?
    public var endingWithin: EndingWithin?
    public var maxBidCount: Int?
    public var noReserve: Bool?
    public var sold: Bool?
    public var sort: ListingSearchSort?
    public var page: Int
    public var pageSize: Int

    public init(
        q: String? = nil,
        brand: String? = nil,
        series: String? = nil,
        scale: String? = nil,
        condition: String? = nil,
        tradeType: String? = nil,
        status: String? = nil,
        priceMin: Int64? = nil,
        priceMax: Int64? = nil,
        freeShipping: Bool? = nil,
        endingWithin: EndingWithin? = nil,
        maxBidCount: Int? = nil,
        noReserve: Bool? = nil,
        sold: Bool? = nil,
        sort: ListingSearchSort? = nil,
        page: Int = 1,
        pageSize: Int = 20
    ) {
        self.q = q
        self.brand = brand
        self.series = series
        self.scale = scale
        self.condition = condition
        self.tradeType = tradeType
        self.status = status
        self.priceMin = priceMin
        self.priceMax = priceMax
        self.freeShipping = freeShipping
        self.endingWithin = endingWithin
        self.maxBidCount = maxBidCount
        self.noReserve = noReserve
        self.sold = sold
        self.sort = sort
        self.page = page
        self.pageSize = pageSize
    }

    public var hasActiveFilters: Bool {
        brand != nil || series != nil || scale != nil || condition != nil
            || tradeType != nil || (status != nil && status != "all")
            || priceMin != nil || priceMax != nil || freeShipping == true
            || endingWithin != nil || maxBidCount != nil || noReserve == true
    }

    /// Query items for GET (nil values omitted by client).
    public var queryItems: [String: String?] {
        [
            "q": q.flatMap { $0.isEmpty ? nil : $0 },
            "brand": brand,
            "series": series,
            "scale": scale,
            "condition": condition,
            "trade_type": tradeType,
            "status": status == "all" ? nil : status,
            "price_min": priceMin.map(String.init),
            "price_max": priceMax.map(String.init),
            "free_shipping": freeShipping.map { $0 ? "true" : "false" },
            "ending_within": endingWithin?.rawValue,
            "max_bid_count": maxBidCount.map(String.init),
            "no_reserve": noReserve == true ? "true" : nil,
            "sold": sold == true ? "true" : nil,
            "sort": sort?.rawValue,
            "page": "\(max(page, 1))",
            "page_size": "\(min(max(pageSize, 1), SearchLimits.pageSizeMax))",
        ]
    }

    /// Snapshot stored in `saved_search.filters_json` (no paging).
    public var filtersSnapshot: [String: String] {
        var out: [String: String] = [:]
        if let brand { out["brand"] = brand }
        if let series { out["series"] = series }
        if let scale { out["scale"] = scale }
        if let condition { out["condition"] = condition }
        if let tradeType { out["trade_type"] = tradeType }
        if let status, status != "all" { out["status"] = status }
        if let priceMin { out["price_min"] = String(priceMin) }
        if let priceMax { out["price_max"] = String(priceMax) }
        if freeShipping == true { out["free_shipping"] = "true" }
        if let endingWithin { out["ending_within"] = endingWithin.rawValue }
        if let maxBidCount { out["max_bid_count"] = String(maxBidCount) }
        if noReserve == true { out["no_reserve"] = "true" }
        if sold == true { out["sold"] = "true" }
        if let sort { out["sort"] = sort.rawValue }
        return out
    }

    /// Clearing time window when switching to sold tab (DES §9).
    public mutating func applySoldTab(_ on: Bool) {
        sold = on ? true : nil
        if on { endingWithin = nil }
    }
}

public enum ListingSearchValidator {
    /// Client-side preflight matching DES §5.2 failure codes.
    public static func validate(_ q: ListingSearchQuery) -> SearchErrorCode? {
        if q.sold == true, q.endingWithin != nil { return .filterConflict }
        if let min = q.priceMin, let max = q.priceMax, min > max { return .invalidPriceRange }
        if let bid = q.maxBidCount, bid != 0 && bid != 1 { return .invalidPriceRange }
        return nil
    }
}

/// Leak badge is server-computed; client only renders (DES §5.2).
/// `no_reserve` alone never grants a badge.
public enum LeakBadgePolicy {
    public static let voiceOverLabel = "捡漏"

    /// Local preview of whether a live lot would earn a badge (tests / offline).
    public static func shouldShow(
        endAt: Date?,
        now: Date,
        bidCount: Int?,
        belowMedianEnabled: Bool = false,
        currentPriceBelowMedian: Bool = false
    ) -> Bool {
        guard let endAt else { return false }
        let within24h = endAt.timeIntervalSince(now) <= 24 * 3600 && endAt > now
        guard within24h else { return false }
        let bids = bidCount ?? 0
        if bids == 0 || bids <= 1 { return true }
        if belowMedianEnabled && currentPriceBelowMedian { return true }
        return false
    }
}

/// Contact-info guard for shortcuts / search words (T-07). Pure amounts are allowed.
public enum SearchContactGuard {
    private static let phonePattern = try! NSRegularExpression(
        pattern: #"(?:\+?86)?1[3-9]\d{9}|\d{3,4}-?\d{7,8}"#
    )
    private static let wechatPattern = try! NSRegularExpression(
        pattern: #"(?i)(?:微信(?:号)?|wx|wechat|v信|薇信)[:：\s\-]*[a-zA-Z0-9_\-]{5,20}"#
    )

    public static func containsContactInfo(_ word: String) -> Bool {
        let s = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        if phonePattern.firstMatch(in: s, range: range) != nil { return true }
        if wechatPattern.firstMatch(in: s, range: range) != nil { return true }
        return false
    }

    /// Returns `contact_info_forbidden` when the word embeds phone / WeChat handles.
    /// Length is enforced by callers against `SearchLimits.shortcutWordMin/Max`.
    public static func validateShortcutWord(_ word: String) -> SearchErrorCode? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        if containsContactInfo(trimmed) { return .contactInfoForbidden }
        return nil
    }
}

// MARK: - DTOs

/// Search / listings card (home feed card + sold fields). DES §3 / §6.
public struct SearchListingCard: Decodable, Equatable, Sendable, Identifiable, Hashable {
    public let listingId: Int64
    public let lotId: Int64?
    public let tradeType: String
    public let title: String
    public let cover: String
    public let condition: String?
    public let sellerBadge: SellerBadge?
    public let currentPrice: Int64?
    public let bidCount: Int?
    public let viewers: Int?
    public let endAt: Date?
    public let listedAt: Date?
    public let price: Int64?
    public let freeShipping: Bool?
    public let negotiable: Bool?
    public let releaseMode: String?
    public let releaseStatus: String?
    public let leakBadge: String?
    public let hasReserve: Bool?
    public let soldPricePublic: Int64?
    public let soldAt: Date?
    public let brand: String?
    public let series: String?
    public let scale: String?
    public let status: String?
    public let endAtVersion: Int?
    public let favoriteCount: Int?
    public let bidderCount: Int?

    public var id: Int64 { listingId }

    public var detailRouteId: Int64 { lotId ?? listingId }

    public var isSold: Bool {
        if soldAt != nil { return true }
        if let status, status == "sold" || status == "ended" { return soldPricePublic != nil || soldAt != nil }
        return false
    }

    /// Auction hammer or fixed list price for public display (never negotiated paid amount).
    public var displayPrice: Int64 {
        if let soldPricePublic { return soldPricePublic }
        if tradeType == "auction" { return currentPrice ?? price ?? 0 }
        return price ?? currentPrice ?? 0
    }

    public var soldPriceKind: SoldPriceDisplayKind {
        tradeType == "auction" ? .hammer : .list
    }

    public var soldPriceLabel: String {
        switch soldPriceKind {
        case .hammer: return "成交价"
        case .list: return "标价"
        }
    }

    public init(
        listingId: Int64,
        lotId: Int64? = nil,
        tradeType: String,
        title: String,
        cover: String,
        condition: String? = nil,
        sellerBadge: SellerBadge? = nil,
        currentPrice: Int64? = nil,
        bidCount: Int? = nil,
        viewers: Int? = nil,
        endAt: Date? = nil,
        listedAt: Date? = nil,
        price: Int64? = nil,
        freeShipping: Bool? = nil,
        negotiable: Bool? = nil,
        releaseMode: String? = nil,
        releaseStatus: String? = nil,
        leakBadge: String? = nil,
        hasReserve: Bool? = nil,
        soldPricePublic: Int64? = nil,
        soldAt: Date? = nil,
        brand: String? = nil,
        series: String? = nil,
        scale: String? = nil,
        status: String? = nil,
        endAtVersion: Int? = nil,
        favoriteCount: Int? = nil,
        bidderCount: Int? = nil
    ) {
        self.listingId = listingId
        self.lotId = lotId
        self.tradeType = tradeType
        self.title = title
        self.cover = cover
        self.condition = condition
        self.sellerBadge = sellerBadge
        self.currentPrice = currentPrice
        self.bidCount = bidCount
        self.viewers = viewers
        self.endAt = endAt
        self.listedAt = listedAt
        self.price = price
        self.freeShipping = freeShipping
        self.negotiable = negotiable
        self.releaseMode = releaseMode
        self.releaseStatus = releaseStatus
        self.leakBadge = leakBadge
        self.hasReserve = hasReserve
        self.soldPricePublic = soldPricePublic
        self.soldAt = soldAt
        self.brand = brand
        self.series = series
        self.scale = scale
        self.status = status
        self.endAtVersion = endAtVersion
        self.favoriteCount = favoriteCount
        self.bidderCount = bidderCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Prefer listing_id; fall back to id for transitional listing payloads.
        if let lid = try c.decodeIfPresent(Int64.self, forKey: .listingId) {
            listingId = lid
        } else {
            listingId = try c.decode(Int64.self, forKey: .id)
        }
        lotId = try c.decodeIfPresent(Int64.self, forKey: .lotId)
        tradeType = try c.decodeIfPresent(String.self, forKey: .tradeType) ?? "auction"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
            ?? (try c.decodeIfPresent([String].self, forKey: .images)?.first)
            ?? ""
        condition = try c.decodeIfPresent(String.self, forKey: .condition)
        sellerBadge = try c.decodeIfPresent(SellerBadge.self, forKey: .sellerBadge)
        currentPrice = try c.decodeIfPresent(Int64.self, forKey: .currentPrice)
        bidCount = try c.decodeIfPresent(Int.self, forKey: .bidCount)
        viewers = try c.decodeIfPresent(Int.self, forKey: .viewers)
        endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        listedAt = try c.decodeIfPresent(Date.self, forKey: .listedAt)
        price = try c.decodeIfPresent(Int64.self, forKey: .price)
        freeShipping = try c.decodeIfPresent(Bool.self, forKey: .freeShipping)
        negotiable = try c.decodeIfPresent(Bool.self, forKey: .negotiable)
        releaseMode = try c.decodeIfPresent(String.self, forKey: .releaseMode)
        releaseStatus = try c.decodeIfPresent(String.self, forKey: .releaseStatus)
        leakBadge = try c.decodeIfPresent(String.self, forKey: .leakBadge)
        hasReserve = try c.decodeIfPresent(Bool.self, forKey: .hasReserve)
        soldPricePublic = try c.decodeIfPresent(Int64.self, forKey: .soldPricePublic)
        soldAt = try c.decodeIfPresent(Date.self, forKey: .soldAt)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        series = try c.decodeIfPresent(String.self, forKey: .series)
        scale = try c.decodeIfPresent(String.self, forKey: .scale)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        endAtVersion = try c.decodeIfPresent(Int.self, forKey: .endAtVersion)
        favoriteCount = try c.decodeIfPresent(Int.self, forKey: .favoriteCount)
        bidderCount = try c.decodeIfPresent(Int.self, forKey: .bidderCount)
    }

    private enum CodingKeys: String, CodingKey {
        case listingId, id, lotId, tradeType, title, cover, images, condition, sellerBadge
        case currentPrice, bidCount, viewers, endAt, listedAt, price, freeShipping, negotiable
        case releaseMode, releaseStatus, leakBadge, hasReserve, soldPricePublic, soldAt
        case brand, series, scale, status, endAtVersion, favoriteCount, bidderCount
    }
}

public struct SearchListingsPage: Decodable, Equatable, Sendable {
    public let items: [SearchListingCard]
    public let page: Int
    public let pageSize: Int
    public let total: Int
    public let hasMore: Bool
    public let serverTime: Date?
    public let serverTimeMs: Int64?

    public init(
        items: [SearchListingCard],
        page: Int = 1,
        pageSize: Int = 20,
        total: Int = 0,
        hasMore: Bool = false,
        serverTime: Date? = nil,
        serverTimeMs: Int64? = nil
    ) {
        self.items = items
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.hasMore = hasMore
        self.serverTime = serverTime
        self.serverTimeMs = serverTimeMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([SearchListingCard].self, forKey: .items) ?? []
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        pageSize = try c.decodeIfPresent(Int.self, forKey: .pageSize) ?? 20
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? items.count
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore)
            ?? (page * pageSize < total)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
        serverTimeMs = try c.decodeIfPresent(Int64.self, forKey: .serverTimeMs)
    }

    public var resolvedServerTimeMs: Int64? {
        if let serverTimeMs { return serverTimeMs }
        if let serverTime { return Int64(serverTime.timeIntervalSince1970 * 1000) }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case items, page, pageSize, total, hasMore, serverTime, serverTimeMs
    }
}

public struct HotWord: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let word: String
    public let weight: Int?
    public let locked: Bool?
    public let synonyms: [String]?
    public let hitFields: [String]?

    public var id: String { word }

    public init(word: String, weight: Int? = nil, locked: Bool? = nil, synonyms: [String]? = nil, hitFields: [String]? = nil) {
        self.word = word
        self.weight = weight
        self.locked = locked
        self.synonyms = synonyms
        self.hitFields = hitFields
    }
}

public struct HotWordsResponse: Decodable, Equatable, Sendable {
    public let items: [HotWord]

    public init(items: [HotWord]) { self.items = items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try c.decodeIfPresent([HotWord].self, forKey: .items) {
            self.items = items
        } else if let words = try c.decodeIfPresent([String].self, forKey: .words) {
            self.items = words.map { HotWord(word: $0) }
        } else {
            self.items = []
        }
    }

    /// Preset 1:43 resin hot words when API unavailable (DES §5.1 / §11).
    public static let presetFallback: HotWordsResponse = HotWordsResponse(items: [
        HotWord(word: "EMP", weight: 100, locked: true),
        HotWord(word: "BBR", weight: 90, locked: true),
        HotWord(word: "Make Up", weight: 80, locked: true, synonyms: ["Makeup"]),
    ])

    private enum CodingKeys: String, CodingKey { case items, words }
}

public struct UserShortcutWord: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var word: String
    public var rank: Int

    public var id: String { word }

    public init(word: String, rank: Int) {
        self.word = word
        self.rank = rank
    }
}

public struct UserShortcutsResponse: Codable, Equatable, Sendable {
    public var words: [UserShortcutWord]

    public init(words: [UserShortcutWord] = []) { self.words = words }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        words = try c.decodeIfPresent([UserShortcutWord].self, forKey: .words) ?? []
    }

    public var sorted: [UserShortcutWord] {
        words.sorted { $0.rank < $1.rank }
    }

    public mutating func upsert(_ word: String) -> SearchErrorCode? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.count
        guard count >= SearchLimits.shortcutWordMin, count <= SearchLimits.shortcutWordMax else {
            return .shortcutLimitExceeded
        }
        if let err = SearchContactGuard.validateShortcutWord(trimmed) { return err }
        if let idx = words.firstIndex(where: { $0.word == trimmed }) {
            words[idx].rank = 0
            renumber()
            return nil
        }
        if words.count >= SearchLimits.maxShortcuts { return .shortcutLimitExceeded }
        words.insert(UserShortcutWord(word: trimmed, rank: 0), at: 0)
        renumber()
        return nil
    }

    public mutating func remove(_ word: String) {
        words.removeAll { $0.word == word }
        renumber()
    }

    private mutating func renumber() {
        for i in words.indices { words[i].rank = i }
    }

    private enum CodingKeys: String, CodingKey { case words }
}

public struct PutShortcutsRequest: Codable, Equatable, Sendable {
    public let words: [UserShortcutWord]
    public init(words: [UserShortcutWord]) { self.words = words }
}

public struct SavedSearch: Decodable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let query: String?
    public let filtersJson: [String: String]?
    public let notifyTypes: [SavedSearchNotifyType]?
    public let endingSoon: Bool?
    public let status: SavedSearchStatus?
    public let lastMatchedAt: Date?

    public init(
        id: Int64,
        query: String? = nil,
        filtersJson: [String: String]? = nil,
        notifyTypes: [SavedSearchNotifyType]? = nil,
        endingSoon: Bool? = nil,
        status: SavedSearchStatus? = nil,
        lastMatchedAt: Date? = nil
    ) {
        self.id = id
        self.query = query
        self.filtersJson = filtersJson
        self.notifyTypes = notifyTypes
        self.endingSoon = endingSoon
        self.status = status
        self.lastMatchedAt = lastMatchedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        query = try c.decodeIfPresent(String.self, forKey: .query)
        if let dict = try c.decodeIfPresent([String: String].self, forKey: .filtersJson) {
            filtersJson = dict
        } else if let dict = try c.decodeIfPresent([String: String].self, forKey: .filters) {
            filtersJson = dict
        } else {
            filtersJson = nil
        }
        notifyTypes = try c.decodeIfPresent([SavedSearchNotifyType].self, forKey: .notifyTypes)
        endingSoon = try c.decodeIfPresent(Bool.self, forKey: .endingSoon)
            ?? notifyTypes?.contains(.endingSoon)
        status = try c.decodeIfPresent(SavedSearchStatus.self, forKey: .status)
        lastMatchedAt = try c.decodeIfPresent(Date.self, forKey: .lastMatchedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, query, filtersJson, filters, notifyTypes, endingSoon, status, lastMatchedAt
    }
}

public struct SavedSearchesResponse: Decodable, Equatable, Sendable {
    public let items: [SavedSearch]

    public init(items: [SavedSearch] = []) { self.items = items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([SavedSearch].self, forKey: .items) ?? []
    }

    public var activeCount: Int {
        items.filter { $0.status != .deleted && $0.status != .paused }.count
    }

    private enum CodingKeys: String, CodingKey { case items }
}

public struct CreateSavedSearchRequest: Codable, Equatable, Sendable {
    public let query: String?
    public let filters: [String: String]
    public let notifyTypes: [SavedSearchNotifyType]

    public init(query: String?, filters: [String: String], notifyTypes: [SavedSearchNotifyType]) {
        self.query = query
        self.filters = filters
        self.notifyTypes = notifyTypes
    }

    public var endingSoonEnabled: Bool { notifyTypes.contains(.endingSoon) }
}

/// Favorite sold snapshot (DES §3) — write path is server-side; client may decode in「我的收藏」later.
public struct SoldSnapshot: Codable, Equatable, Sendable {
    public let badge: String?
    public let displayPrice: Int64
    public let displayPriceKind: SoldPriceDisplayKind
    public let soldAt: Date?
    public let title: String?
    public let cover: String?

    public init(
        badge: String? = "sold",
        displayPrice: Int64,
        displayPriceKind: SoldPriceDisplayKind,
        soldAt: Date? = nil,
        title: String? = nil,
        cover: String? = nil
    ) {
        self.badge = badge
        self.displayPrice = displayPrice
        self.displayPriceKind = displayPriceKind
        self.soldAt = soldAt
        self.title = title
        self.cover = cover
    }
}

// MARK: - Tonight window (Asia/Shanghai)

public enum SearchBusinessTimezone {
    public static let identifier = "Asia/Shanghai"

    public static var shanghai: TimeZone {
        TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 8 * 3600)!
    }

    /// End of business day (tonight 24:00) for `ending_within=tonight`.
    public static func tonightBound(from now: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = shanghai
        let start = cal.startOfDay(for: now)
        return cal.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(3600)
    }

    public static func tonightCaption(from now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = shanghai
        let day = cal.component(.day, from: now)
        let month = cal.component(.month, from: now)
        return "今晚（\(month)/\(day) 截止）"
    }
}

// MARK: - Local search history

public enum SearchHistoryStore {
    public static func parse(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    public static func encode(_ items: [String]) -> String {
        Array(items.prefix(SearchLimits.historyMax)).joined(separator: "\n")
    }

    public static func push(_ keyword: String, into raw: inout String) {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        var h = parse(raw).filter { $0 != q }
        h.insert(q, at: 0)
        raw = encode(h)
    }
}
