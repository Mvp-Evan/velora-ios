import Foundation

// MARK: - Search / filter / sold (DES-v1.3-02-02) — app mirror of VeloraCore

enum SearchErrorCode: String {
    case loginRequired = "login_required"
    case savedSearchLimitExceeded = "saved_search_limit_exceeded"
    case shortcutLimitExceeded = "shortcut_limit_exceeded"
    case filterConflict = "filter_conflict"
    case invalidPriceRange = "invalid_price_range"
    case contactInfoForbidden = "contact_info_forbidden"
    case listingNotPublic = "listing_not_public"
    case savedSearchNotFound = "saved_search_not_found"

    var fallbackMessage: String {
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

enum EndingWithin: String, CaseIterable, Hashable {
    case oneHour = "1h"
    case tonight
    case twentyFourHours = "24h"

    var title: String {
        switch self {
        case .oneHour: return "1小时内"
        case .tonight: return "今晚结束"
        case .twentyFourHours: return "24小时内"
        }
    }
}

enum ListingSearchSort: String, CaseIterable, Hashable {
    case comprehensive
    case endingSoon = "ending_soon"
    case heat
    case newest
    case priceAsc = "price_asc"
    case priceDesc = "price_desc"

    var title: String {
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

enum SavedSearchNotifyType: String, CaseIterable, Hashable, Codable {
    case newList = "new_list"
    case newLive = "new_live"
    case priceDrop = "price_drop"
    case endingSoon = "ending_soon"

    var title: String {
        switch self {
        case .newList: return "新上架"
        case .newLive: return "开拍"
        case .priceDrop: return "降价"
        case .endingSoon: return "即将结束"
        }
    }
}

enum SavedSearchStatus: String, Codable {
    case active, paused, deleted
}

enum SoldPriceDisplayKind: String, Codable {
    case hammer, list
}

enum SearchLimits {
    static let maxShortcuts = 12
    static let maxSavedSearches = 20
    static let shortcutWordMin = 1
    static let shortcutWordMax = 20
    static let historyMax = 20
    static let pageSizeMax = 50
    static let savedSearchSoftWarnAt = 18
}

struct ListingSearchQuery: Equatable, Hashable {
    var q: String?
    var brand: String?
    var series: String?
    var scale: String?
    var condition: String?
    var tradeType: String?
    var status: String?
    var sellerId: Int64?
    var priceMin: Money?
    var priceMax: Money?
    var freeShipping: Bool?
    var endingWithin: EndingWithin?
    var maxBidCount: Int?
    var noReserve: Bool?
    var sold: Bool?
    var sort: ListingSearchSort?
    var page = 1
    var pageSize = 20

    var hasActiveFilters: Bool {
        brand != nil || series != nil || scale != nil || condition != nil
            || tradeType != nil || (status != nil && status != "all")
            || sellerId != nil
            || priceMin != nil || priceMax != nil || freeShipping == true
            || endingWithin != nil || maxBidCount != nil || noReserve == true
    }

    var queryItems: [String: String?] {
        [
            "q": q.flatMap { $0.isEmpty ? nil : $0 },
            "brand": brand,
            "series": series,
            "scale": scale,
            "condition": condition,
            "trade_type": tradeType,
            "status": status == "all" ? nil : status,
            "seller_id": sellerId.map(String.init),
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

    var filtersSnapshot: [String: String] {
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

    mutating func applySoldTab(_ on: Bool) {
        sold = on ? true : nil
        if on { endingWithin = nil }
    }

    func validating() -> SearchErrorCode? {
        if sold == true, endingWithin != nil { return .filterConflict }
        if let min = priceMin, let max = priceMax, min > max { return .invalidPriceRange }
        return nil
    }
}

enum LeakBadgePolicy {
    static let voiceOverLabel = "捡漏"
}

enum SearchContactGuard {
    private static let phonePattern = try! NSRegularExpression(
        pattern: #"(?:\+?86)?1[3-9]\d{9}|\d{3,4}-?\d{7,8}"#
    )
    private static let wechatPattern = try! NSRegularExpression(
        pattern: #"(?i)(?:微信(?:号)?|wx|wechat|v信|薇信)[:：\s\-]*[a-zA-Z0-9_\-]{5,20}"#
    )

    static func containsContactInfo(_ word: String) -> Bool {
        let s = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        if phonePattern.firstMatch(in: s, range: range) != nil { return true }
        if wechatPattern.firstMatch(in: s, range: range) != nil { return true }
        return false
    }
}

struct SearchListingCard: Decodable, Identifiable, Hashable {
    let listingId: Int64
    let lotId: Int64?
    let tradeType: String
    let title: String
    let cover: String
    let condition: String?
    let sellerBadge: SellerBadge?
    var currentPrice: Money?
    var bidCount: Int?
    var viewers: Int?
    var endAt: Date?
    let listedAt: Date?
    let price: Money?
    let freeShipping: Bool?
    let negotiable: Bool?
    let releaseMode: String?
    let releaseStatus: String?
    let leakBadge: String?
    let hasReserve: Bool?
    let soldPricePublic: Money?
    let soldAt: Date?
    let brand: String?
    let series: String?
    let scale: String?
    var status: String?
    /// Client / tick fields (DES-v1.3-02-03).
    var endAtVersion: Int?
    var extensionCount: Int?
    var favoriteCount: Int?
    var bidderCount: Int?
    var delayed: Bool
    var liveStale: Bool

    var id: Int64 { listingId }
    var detailRouteId: Int64 { lotId ?? listingId }

    var displayPrice: Money {
        if let soldPricePublic { return soldPricePublic }
        if tradeType == "auction" { return currentPrice ?? price ?? 0 }
        return price ?? currentPrice ?? 0
    }

    var soldPriceKind: SoldPriceDisplayKind {
        tradeType == "auction" ? .hammer : .list
    }

    var soldPriceLabel: String {
        soldPriceKind == .hammer ? "成交价" : "标价"
    }

    var isSoldCard: Bool { soldAt != nil || soldPricePublic != nil }

    var tags: [String] {
        [scale, brand, condition].compactMap { $0 }.filter { !$0.isEmpty }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
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
        currentPrice = try c.decodeIfPresent(Money.self, forKey: .currentPrice)
        bidCount = try c.decodeIfPresent(Int.self, forKey: .bidCount)
        viewers = try c.decodeIfPresent(Int.self, forKey: .viewers)
        endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        listedAt = try c.decodeIfPresent(Date.self, forKey: .listedAt)
        price = try c.decodeIfPresent(Money.self, forKey: .price)
        freeShipping = try c.decodeIfPresent(Bool.self, forKey: .freeShipping)
        negotiable = try c.decodeIfPresent(Bool.self, forKey: .negotiable)
        releaseMode = try c.decodeIfPresent(String.self, forKey: .releaseMode)
        releaseStatus = try c.decodeIfPresent(String.self, forKey: .releaseStatus)
        // Server may emit bool (`false`) or string badge text.
        if let s = try? c.decode(String.self, forKey: .leakBadge) {
            leakBadge = s.isEmpty ? nil : s
        } else if let b = try? c.decode(Bool.self, forKey: .leakBadge) {
            leakBadge = b ? LeakBadgePolicy.voiceOverLabel : nil
        } else {
            leakBadge = nil
        }
        hasReserve = try c.decodeIfPresent(Bool.self, forKey: .hasReserve)
        soldPricePublic = try c.decodeIfPresent(Money.self, forKey: .soldPricePublic)
        soldAt = try c.decodeIfPresent(Date.self, forKey: .soldAt)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        series = try c.decodeIfPresent(String.self, forKey: .series)
        scale = try c.decodeIfPresent(String.self, forKey: .scale)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        endAtVersion = try c.decodeIfPresent(Int.self, forKey: .endAtVersion)
        extensionCount = try c.decodeIfPresent(Int.self, forKey: .extensionCount)
        favoriteCount = try c.decodeIfPresent(Int.self, forKey: .favoriteCount)
        bidderCount = try c.decodeIfPresent(Int.self, forKey: .bidderCount)
        delayed = false
        liveStale = false
    }

    private enum CodingKeys: String, CodingKey {
        case listingId, id, lotId, tradeType, title, cover, images, condition, sellerBadge
        case currentPrice, bidCount, viewers, endAt, listedAt, price, freeShipping, negotiable
        case releaseMode, releaseStatus, leakBadge, hasReserve, soldPricePublic, soldAt
        case brand, series, scale, status, endAtVersion, extensionCount, favoriteCount, bidderCount
    }

    /// Apply in-place live tick without changing list index (HOME-11).
    mutating func applyLive(_ live: LotCardLiveFields) {
        if let v = live.currentPrice { currentPrice = v }
        if let v = live.bidCount { bidCount = v }
        if let v = live.endAt { endAt = v }
        if let v = live.endAtVersion { endAtVersion = v }
        if let v = live.extensionCount { extensionCount = v }
        if live.delayed { delayed = true }
        if let v = live.status { status = v }
        if let v = live.viewers { viewers = v }
        if let v = live.favoriteCount { favoriteCount = v }
        if let v = live.bidderCount { bidderCount = v }
        if live.isTerminalStatus { liveStale = true }
    }

    var heatLine: String {
        LotCardHeatCopy.line(viewers: viewers, favoriteCount: favoriteCount, bidderCount: bidderCount)
    }

    var showsEndedBadge: Bool {
        liveStale || status == "ended" || status == "unsold" || status == "cancelled"
    }
}

struct SearchListingsPage: Decodable {
    let items: [SearchListingCard]
    let page: Int
    let pageSize: Int
    let total: Int
    let hasMore: Bool
    let serverTime: Date?
    let serverTimeMs: Int64?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([SearchListingCard].self, forKey: .items) ?? []
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        pageSize = try c.decodeIfPresent(Int.self, forKey: .pageSize) ?? 20
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? items.count
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore) ?? (page * pageSize < total)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
        serverTimeMs = try c.decodeIfPresent(Int64.self, forKey: .serverTimeMs)
    }

    var resolvedServerTimeMs: Int64? {
        if let serverTimeMs { return serverTimeMs }
        if let serverTime { return Int64(serverTime.timeIntervalSince1970 * 1000) }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case items, page, pageSize, total, hasMore, serverTime, serverTimeMs
    }
}

struct HotWord: Codable, Identifiable, Hashable {
    let word: String
    let weight: Int?
    let locked: Bool?
    let synonyms: [String]?

    var id: String { word }
}

struct HotWordsResponse: Decodable {
    let items: [HotWord]

    init(items: [HotWord]) { self.items = items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try c.decodeIfPresent([HotWord].self, forKey: .items) {
            self.items = items
        } else if let words = try c.decodeIfPresent([String].self, forKey: .words) {
            self.items = words.map { HotWord(word: $0, weight: nil, locked: nil, synonyms: nil) }
        } else {
            self.items = []
        }
    }

    static let presetFallback = HotWordsResponse(items: [
        HotWord(word: "EMP", weight: 100, locked: true, synonyms: nil),
        HotWord(word: "BBR", weight: 90, locked: true, synonyms: nil),
        HotWord(word: "Make Up", weight: 80, locked: true, synonyms: ["Makeup"]),
    ])

    private enum CodingKeys: String, CodingKey { case items, words }
}

struct UserShortcutWord: Codable, Identifiable, Hashable {
    var word: String
    var rank: Int
    var id: String { word }
}

struct UserShortcutsResponse: Codable {
    var words: [UserShortcutWord]

    init(words: [UserShortcutWord] = []) { self.words = words }

    var sorted: [UserShortcutWord] { words.sorted { $0.rank < $1.rank } }

    mutating func upsert(_ word: String) -> SearchErrorCode? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= SearchLimits.shortcutWordMin,
              trimmed.count <= SearchLimits.shortcutWordMax else {
            return .shortcutLimitExceeded
        }
        if SearchContactGuard.containsContactInfo(trimmed) { return .contactInfoForbidden }
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

    mutating func remove(_ word: String) {
        words.removeAll { $0.word == word }
        renumber()
    }

    private mutating func renumber() {
        for i in words.indices { words[i].rank = i }
    }
}

struct PutShortcutsRequest: Encodable {
    let words: [UserShortcutWord]
}

struct SavedSearch: Decodable, Identifiable, Hashable {
    let id: Int64
    let query: String?
    let filtersJson: [String: String]?
    let notifyTypes: [SavedSearchNotifyType]?
    let endingSoon: Bool?
    let status: SavedSearchStatus?
    let lastMatchedAt: Date?

    init(from decoder: Decoder) throws {
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

struct SavedSearchesResponse: Decodable {
    let items: [SavedSearch]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([SavedSearch].self, forKey: .items) ?? []
    }

    var activeCount: Int {
        items.filter { $0.status != .deleted }.count
    }

    private enum CodingKeys: String, CodingKey { case items }
}

struct CreateSavedSearchRequest: Encodable {
    let query: String?
    let filters: [String: String]
    let notifyTypes: [SavedSearchNotifyType]
}

enum SearchBusinessTimezone {
    static let identifier = "Asia/Shanghai"

    static var shanghai: TimeZone {
        TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 8 * 3600)!
    }

    static func tonightCaption(from now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = shanghai
        let day = cal.component(.day, from: now)
        let month = cal.component(.month, from: now)
        return "今晚（\(month)/\(day)）"
    }
}

enum SearchHistoryStore {
    static func parse(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func encode(_ items: [String]) -> String {
        Array(items.prefix(SearchLimits.historyMax)).joined(separator: "\n")
    }

    static func push(_ keyword: String, into raw: inout String) {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        var h = parse(raw).filter { $0 != q }
        h.insert(q, at: 0)
        raw = encode(h)
    }
}
