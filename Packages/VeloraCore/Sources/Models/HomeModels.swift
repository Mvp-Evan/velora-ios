import Foundation

// MARK: - Purchase home feed / slots (DES-v1.3-02-01 / HOME-01/04/05/07)

/// Channel tab for `GET /home/feed`.
public enum HomeFeedTab: String, Codable, Sendable, CaseIterable {
    case follow
    case hot
    case new

    public var title: String {
        switch self {
        case .follow: return "关注"
        case .hot: return "热门"
        case .new: return "上新"
        }
    }
}

/// Trade-mode first-level switch on Purchase Tab (DES §1).
public enum HomeTradeMode: String, Codable, Sendable, CaseIterable {
    case all
    case auction
    case fixed
    case release

    public var title: String {
        switch self {
        case .all: return "全部"
        case .auction: return "拍卖"
        case .fixed: return "直购"
        case .release: return "发售"
        }
    }

    /// Maps to feed card `trade_type` when filtering the「全部」channel stream.
    public var tradeTypeFilter: String? {
        switch self {
        case .all: return nil
        case .auction: return "auction"
        case .fixed: return "fixed"
        case .release: return "release"
        }
    }
}

public enum SellerBadge: String, Codable, Sendable {
    case personal
    case proxyGold = "proxy_gold"
    /// Probation proxy chip (DES-v1.3-05-01).
    case proxyProbation = "proxy_probation"
    case brandOfficial = "brand_official"

    public var label: String {
        switch self {
        case .personal: return "个人"
        case .proxyGold: return "金牌代拍"
        case .proxyProbation: return "代拍（观察期）"
        case .brandOfficial: return "品牌官方"
        }
    }

    /// Accepts feed wire `proxy_gold` and DB `gold_proxy` (DES-v1.3-05-01 §3).
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "personal": self = .personal
        case "proxy_gold", "gold_proxy": self = .proxyGold
        case "proxy_probation": self = .proxyProbation
        case "brand_official": self = .brandOfficial
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown SellerBadge \(raw)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum HomeSlotLabel: String, Codable, Sendable {
    case recommend
    case ad

    /// Client must render server label verbatim (DES §5.3 / §9).
    public var displayText: String {
        switch self {
        case .recommend: return "推荐"
        case .ad: return "广告"
        }
    }
}

public enum HomeSlotKind: String, Codable, Sendable {
    case banner
    case promoCard = "promo_card"
    case sessionEntry = "session_entry"
}

public enum HomeSlotBindType: String, Codable, Sendable {
    case listing
    case seller
    case session
    case event
}

public enum HomeExposureEventKind: String, Codable, Sendable {
    case impression
    case click
}

/// Shared feed card DTO (DES §5.1). Missing fields decode as nil.
public struct HomeFeedCard: Codable, Equatable, Sendable, Identifiable, Hashable {
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

    public var id: Int64 { listingId }

    public var displayPrice: Int64 {
        if tradeType == "auction" { return currentPrice ?? price ?? 0 }
        return price ?? currentPrice ?? 0
    }

    public var detailRouteId: Int64 { lotId ?? listingId }

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
        leakBadge: String? = nil
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
    }

    enum CodingKeys: String, CodingKey {
        case listingId, lotId, tradeType, title, cover, condition, sellerBadge
        case currentPrice, bidCount, viewers, endAt, listedAt, price, freeShipping, negotiable
        case releaseMode, releaseStatus, leakBadge
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listingId = try c.decode(Int64.self, forKey: .listingId)
        lotId = try c.decodeIfPresent(Int64.self, forKey: .lotId)
        tradeType = try c.decode(String.self, forKey: .tradeType)
        title = try c.decode(String.self, forKey: .title)
        // Server omits cover via omitempty; treat missing/null as empty string.
        cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
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
    }
}

public struct HomeFeedResponse: Codable, Equatable, Sendable {
    public let items: [HomeFeedCard]
    public let nextCursor: String?
    public let serverTime: Date?
    /// Unix ms alternate; prefer when `serverTime` is absent.
    public let serverTimeMs: Int64?
    public let feedVersion: Int64?

    public init(
        items: [HomeFeedCard],
        nextCursor: String? = nil,
        serverTime: Date? = nil,
        serverTimeMs: Int64? = nil,
        feedVersion: Int64? = nil
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.serverTime = serverTime
        self.serverTimeMs = serverTimeMs
        self.feedVersion = feedVersion
    }

    public var resolvedServerTimeMs: Int64? {
        if let serverTimeMs { return serverTimeMs }
        if let serverTime { return Int64(serverTime.timeIntervalSince1970 * 1000) }
        return nil
    }
}

/// Slot payload shared by banners / promo cards / session entries.
public struct HomeSlotItem: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let kind: HomeSlotKind?
    public let label: HomeSlotLabel
    public let bindType: HomeSlotBindType
    public let bindId: Int64
    public let title: String?
    public let cover: String?
    public let sellerId: Int64?
    public let startAt: Date?
    public let endAt: Date?
    public let rank: Int?

    public init(
        id: Int64,
        kind: HomeSlotKind? = nil,
        label: HomeSlotLabel,
        bindType: HomeSlotBindType,
        bindId: Int64,
        title: String? = nil,
        cover: String? = nil,
        sellerId: Int64? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        rank: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.bindType = bindType
        self.bindId = bindId
        self.title = title
        self.cover = cover
        self.sellerId = sellerId
        self.startAt = startAt
        self.endAt = endAt
        self.rank = rank
    }

    /// Drop expired slots client-side (DES §11).
    public func isActive(at now: Date = Date()) -> Bool {
        if let endAt, endAt < now { return false }
        if let startAt, startAt > now { return false }
        return true
    }
}

public struct HomeSlotsResponse: Codable, Equatable, Sendable {
    public let banners: [HomeSlotItem]
    public let cards: [HomeSlotItem]
    public let sessions: [HomeSlotItem]
    public let slotConfigVersion: Int64?
    public let requestId: String?

    public init(
        banners: [HomeSlotItem] = [],
        cards: [HomeSlotItem] = [],
        sessions: [HomeSlotItem] = [],
        slotConfigVersion: Int64? = nil,
        requestId: String? = nil
    ) {
        self.banners = banners
        self.cards = cards
        self.sessions = sessions
        self.slotConfigVersion = slotConfigVersion
        self.requestId = requestId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        banners = try c.decodeIfPresent([HomeSlotItem].self, forKey: .banners) ?? []
        cards = try c.decodeIfPresent([HomeSlotItem].self, forKey: .cards) ?? []
        sessions = try c.decodeIfPresent([HomeSlotItem].self, forKey: .sessions) ?? []
        slotConfigVersion = try c.decodeIfPresent(Int64.self, forKey: .slotConfigVersion)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
    }

    public func filteringExpired(at now: Date = Date()) -> HomeSlotsResponse {
        HomeSlotsResponse(
            banners: banners.filter { $0.isActive(at: now) },
            cards: cards.filter { $0.isActive(at: now) },
            sessions: sessions.filter { $0.isActive(at: now) },
            slotConfigVersion: slotConfigVersion,
            requestId: requestId
        )
    }
}

public struct HomeExposureEvent: Codable, Equatable, Sendable {
    public let slotId: Int64
    public let listingId: Int64?
    public let event: HomeExposureEventKind
    public let visibleMs: Int?

    public init(slotId: Int64, listingId: Int64? = nil, event: HomeExposureEventKind, visibleMs: Int? = nil) {
        self.slotId = slotId
        self.listingId = listingId
        self.event = event
        self.visibleMs = visibleMs
    }
}

public struct HomeExposuresRequest: Codable, Equatable, Sendable {
    public let requestId: String
    public let events: [HomeExposureEvent]
    public let deviceId: String?

    public init(requestId: String, events: [HomeExposureEvent], deviceId: String? = nil) {
        self.requestId = requestId
        self.events = events
        self.deviceId = deviceId
    }
}

// MARK: - Feed merge (promo into natural)

public enum HomeFeedRow: Equatable, Sendable, Identifiable, Hashable {
    case natural(HomeFeedCard)
    case promo(HomeSlotItem)

    public var id: String {
        switch self {
        case .natural(let c): return "n-\(c.listingId)"
        case .promo(let s): return "p-\(s.id)"
        }
    }

    public var listingId: Int64? {
        switch self {
        case .natural(let c): return c.listingId
        case .promo(let s): return s.bindType == .listing ? s.bindId : nil
        }
    }
}

public enum HomeFeedComposer {
    /// Insert promo cards among the first `window` natural results.
    /// Skips a promo when it would sit adjacent to the same `listing_id` (DES §5.3).
    public static func merge(
        natural: [HomeFeedCard],
        promos: [HomeSlotItem],
        window: Int = 10
    ) -> [HomeFeedRow] {
        guard !promos.isEmpty else { return natural.map { .natural($0) } }
        var result: [HomeFeedRow] = []
        var promoQueue = promos.sorted { ($0.rank ?? Int.max) < ($1.rank ?? Int.max) }
        let insertBudget = min(window, natural.count + promoQueue.count)

        for (idx, card) in natural.enumerated() {
            if result.count < insertBudget, let next = nextPromo(from: &promoQueue, previousListingId: result.last?.listingId, upcomingListingId: card.listingId) {
                result.append(.promo(next))
            }
            result.append(.natural(card))
            if idx + 1 == natural.count {
                while result.count < insertBudget || !promoQueue.isEmpty {
                    guard let next = nextPromo(from: &promoQueue, previousListingId: result.last?.listingId, upcomingListingId: nil) else { break }
                    result.append(.promo(next))
                    if promoQueue.isEmpty { break }
                    if result.count >= natural.count + promos.count { break }
                }
            }
        }

        if natural.isEmpty {
            return promoQueue.map { .promo($0) }
        }
        // Append any remaining promos that could not fit in the window without adjacency violation.
        while let next = nextPromo(from: &promoQueue, previousListingId: result.last?.listingId, upcomingListingId: nil) {
            result.append(.promo(next))
        }
        return result
    }

    private static func nextPromo(
        from queue: inout [HomeSlotItem],
        previousListingId: Int64?,
        upcomingListingId: Int64?
    ) -> HomeSlotItem? {
        guard !queue.isEmpty else { return nil }
        for (i, slot) in queue.enumerated() {
            let lid = slot.bindType == .listing ? Optional(slot.bindId) : nil
            if let lid, lid == previousListingId { continue }
            if let lid, lid == upcomingListingId { continue }
            queue.remove(at: i)
            return slot
        }
        // All remaining collide with neighbors — defer until later (caller may append at end).
        if upcomingListingId == nil, !queue.isEmpty {
            return queue.removeFirst()
        }
        return nil
    }

    /// Client-side trade-mode filter for「全部」channel cards (server still owns identity filters).
    public static func filter(cards: [HomeFeedCard], tradeMode: HomeTradeMode) -> [HomeFeedCard] {
        guard let want = tradeMode.tradeTypeFilter else { return cards }
        return cards.filter { $0.tradeType == want }
    }
}

// MARK: - Exposure client helpers

public enum HomeExposurePolicy {
    public static let minVisibleRatio: Double = 0.5
    public static let minVisibleMs: Int = 1000
    public static let maxBatchSize: Int = 50
    public static let clickDedupeMs: Int = 1000
    public static let slotsPollIntervalSeconds: TimeInterval = 30
    public static let backgroundRefreshThresholdSeconds: TimeInterval = 5 * 60
}
