import Foundation

// MARK: - Purchase home feed / slots (DES-v1.3-02-01) — app mirror of VeloraCore

enum HomeFeedTab: String, CaseIterable, Hashable {
    case follow, hot, new

    var title: String {
        switch self {
        case .follow: return "关注"
        case .hot: return "热门"
        case .new: return "上新"
        }
    }
}

enum HomeTradeMode: String, CaseIterable, Hashable {
    case all, auction, fixed, release

    var title: String {
        switch self {
        case .all: return "全部"
        case .auction: return "拍卖"
        case .fixed: return "直购"
        case .release: return "发售"
        }
    }

    var tradeTypeFilter: String? {
        switch self {
        case .all: return nil
        case .auction: return "auction"
        case .fixed: return "fixed"
        case .release: return "release"
        }
    }
}

enum SellerBadge: String, Codable, Hashable {
    case personal
    case proxyGold = "proxy_gold"
    /// Probation proxy chip (DES-v1.3-05-01).
    case proxyProbation = "proxy_probation"
    case brandOfficial = "brand_official"

    var label: String {
        switch self {
        case .personal: return "个人"
        case .proxyGold: return "金牌代拍"
        case .proxyProbation: return "代拍（观察期）"
        case .brandOfficial: return "品牌官方"
        }
    }

    /// Accepts feed wire `proxy_gold` and DB `gold_proxy` (DES-v1.3-05-01 §3).
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "personal", "个人": self = .personal
        case "proxy_gold", "gold_proxy", "金牌代拍": self = .proxyGold
        case "proxy_probation", "代拍（观察期）": self = .proxyProbation
        case "brand_official", "品牌官方": self = .brandOfficial
        default:
            // Search / seller list may emit localized badge text; keep decode resilient.
            self = .personal
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum HomeSlotLabel: String, Codable, Hashable {
    case recommend, ad

    var displayText: String {
        switch self {
        case .recommend: return "推荐"
        case .ad: return "广告"
        }
    }
}

enum HomeSlotKind: String, Codable, Hashable {
    case banner
    case promoCard = "promo_card"
    case sessionEntry = "session_entry"
}

enum HomeSlotBindType: String, Codable, Hashable {
    case listing, seller, session, event
}

enum HomeExposureEventKind: String, Codable, Hashable {
    case impression, click
}

struct HomeFeedCard: Codable, Identifiable, Hashable {
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
    var status: String?
    var endAtVersion: Int?
    var extensionCount: Int?
    var favoriteCount: Int?
    var bidderCount: Int?
    var delayed: Bool = false
    var liveStale: Bool = false

    var id: Int64 { listingId }

    var displayPrice: Money {
        if tradeType == "auction" { return currentPrice ?? price ?? 0 }
        return price ?? currentPrice ?? 0
    }

    var detailRouteId: Int64 { lotId ?? listingId }

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

    private enum CodingKeys: String, CodingKey {
        case listingId, lotId, tradeType, title, cover, condition, sellerBadge
        case currentPrice, bidCount, viewers, endAt, listedAt, price, freeShipping, negotiable
        case releaseMode, releaseStatus, leakBadge, status, endAtVersion, extensionCount
        case favoriteCount, bidderCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listingId = try c.decode(Int64.self, forKey: .listingId)
        lotId = try c.decodeIfPresent(Int64.self, forKey: .lotId)
        tradeType = try c.decode(String.self, forKey: .tradeType)
        title = try c.decode(String.self, forKey: .title)
        // Server omits cover via omitempty; treat missing/null as empty string.
        cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
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
        if let s = try? c.decode(String.self, forKey: .leakBadge) {
            leakBadge = s.isEmpty ? nil : s
        } else if let b = try? c.decode(Bool.self, forKey: .leakBadge) {
            leakBadge = b ? "捡漏" : nil
        } else {
            leakBadge = nil
        }
        status = try c.decodeIfPresent(String.self, forKey: .status)
        endAtVersion = try c.decodeIfPresent(Int.self, forKey: .endAtVersion)
        extensionCount = try c.decodeIfPresent(Int.self, forKey: .extensionCount)
        favoriteCount = try c.decodeIfPresent(Int.self, forKey: .favoriteCount)
        bidderCount = try c.decodeIfPresent(Int.self, forKey: .bidderCount)
        delayed = false
        liveStale = false
    }
}

struct HomeFeedResponse: Codable {
    let items: [HomeFeedCard]
    let nextCursor: String?
    let serverTime: Date?
    let serverTimeMs: Int64?
    let feedVersion: Int64?

    var resolvedServerTimeMs: Int64? {
        if let serverTimeMs { return serverTimeMs }
        if let serverTime { return Int64(serverTime.timeIntervalSince1970 * 1000) }
        return nil
    }
}

struct HomeSlotItem: Codable, Identifiable, Hashable {
    let id: Int64
    let kind: HomeSlotKind?
    let label: HomeSlotLabel
    let bindType: HomeSlotBindType
    let bindId: Int64
    let title: String?
    let cover: String?
    let sellerId: Int64?
    let startAt: Date?
    let endAt: Date?
    let rank: Int?

    func isActive(at now: Date = Date()) -> Bool {
        if let endAt, endAt < now { return false }
        if let startAt, startAt > now { return false }
        return true
    }
}

struct HomeSlotsResponse: Codable {
    let banners: [HomeSlotItem]
    let cards: [HomeSlotItem]
    let sessions: [HomeSlotItem]
    let slotConfigVersion: Int64?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case banners, cards, sessions, slotConfigVersion, requestId
    }

    init(
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        banners = try c.decodeIfPresent([HomeSlotItem].self, forKey: .banners) ?? []
        cards = try c.decodeIfPresent([HomeSlotItem].self, forKey: .cards) ?? []
        sessions = try c.decodeIfPresent([HomeSlotItem].self, forKey: .sessions) ?? []
        slotConfigVersion = try c.decodeIfPresent(Int64.self, forKey: .slotConfigVersion)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
    }

    func filteringExpired(at now: Date = Date()) -> HomeSlotsResponse {
        HomeSlotsResponse(
            banners: banners.filter { $0.isActive(at: now) },
            cards: cards.filter { $0.isActive(at: now) },
            sessions: sessions.filter { $0.isActive(at: now) },
            slotConfigVersion: slotConfigVersion,
            requestId: requestId
        )
    }
}

struct HomeExposureEvent: Codable, Hashable {
    let slotId: Int64
    let listingId: Int64?
    let event: HomeExposureEventKind
    let visibleMs: Int?
}

struct HomeExposuresRequest: Encodable {
    let requestId: String
    let events: [HomeExposureEvent]
    let deviceId: String?
}

enum HomeFeedRow: Identifiable, Hashable {
    case natural(HomeFeedCard)
    case promo(HomeSlotItem)

    var id: String {
        switch self {
        case .natural(let c): return "n-\(c.listingId)"
        case .promo(let s): return "p-\(s.id)"
        }
    }

    var listingId: Int64? {
        switch self {
        case .natural(let c): return c.listingId
        case .promo(let s): return s.bindType == .listing ? s.bindId : nil
        }
    }
}

enum HomeFeedComposer {
    static func merge(natural: [HomeFeedCard], promos: [HomeSlotItem], window: Int = 10) -> [HomeFeedRow] {
        guard !promos.isEmpty else { return natural.map { .natural($0) } }
        var result: [HomeFeedRow] = []
        var promoQueue = promos.sorted { ($0.rank ?? Int.max) < ($1.rank ?? Int.max) }
        let insertBudget = min(window, natural.count + promoQueue.count)

        for (idx, card) in natural.enumerated() {
            if result.count < insertBudget,
               let next = nextPromo(from: &promoQueue, previousListingId: result.last?.listingId, upcomingListingId: card.listingId) {
                result.append(.promo(next))
            }
            result.append(.natural(card))
            if idx + 1 == natural.count {
                while let next = nextPromo(from: &promoQueue, previousListingId: result.last?.listingId, upcomingListingId: nil) {
                    result.append(.promo(next))
                    if promoQueue.isEmpty { break }
                    if result.count >= natural.count + promos.count { break }
                }
            }
        }

        if natural.isEmpty {
            return promoQueue.map { .promo($0) }
        }
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
        if upcomingListingId == nil, !queue.isEmpty {
            return queue.removeFirst()
        }
        return nil
    }

    static func filter(cards: [HomeFeedCard], tradeMode: HomeTradeMode) -> [HomeFeedCard] {
        guard let want = tradeMode.tradeTypeFilter else { return cards }
        return cards.filter { $0.tradeType == want }
    }
}

enum HomeExposurePolicy {
    static let minVisibleRatio: Double = 0.5
    static let minVisibleMs: Int = 1000
    static let maxBatchSize: Int = 50
    static let clickDedupeMs: Int = 1000
    static let slotsPollIntervalSeconds: TimeInterval = 30
    static let backgroundRefreshThresholdSeconds: TimeInterval = 5 * 60
}
