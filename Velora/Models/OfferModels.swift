import Foundation

// MARK: - Structured offer + price-drop (DES-v1.3-04-02 DIR-03/05 / D18 — app mirror of VeloraCore)

/// Product defaults (design §3). Hot-config on server; client mirrors for UX / local checks.
enum OfferConfigDefaults {
    static let minRatio: Double = 0.50
    static let ttlHours: Int = 24
    static let maxRounds: Int = 3
    static let payHours: Int = 2
    static let priceDropCooldownHours: Int = 24
    static let creditMinToOffer: Int = 60
    static let unpaidBanThreshold: Int = 3
    static let unpaidBanDays: Int = 7
    static let rejectOtherMaxChars: Int = 50
    static let priceDropCooldownGCDays: Int = 7
    static let featureFlagPriceDrop = "feature_flags.price_drop_notify"
    static let messageTypeOfferCard = "offer_card"
    static let notifyPriceDropCode = "N-29"
    static let notifyOfferCode = "N-09"
    static let creditReasonUnpaid = "offer_unpaid"
    static let creditDeltaUnpaid = -2
}

// MARK: - Status / initiator / actions

/// `offer.status` (design §3 / §4).
enum OfferStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pendingSeller = "pending_seller"
    case pendingBuyer = "pending_buyer"
    case accepted
    case rejected
    case expired
    case superseded
    case cancelled

    var isPending: Bool {
        self == .pendingSeller || self == .pendingBuyer
    }

    var isTerminal: Bool {
        switch self {
        case .accepted, .rejected, .expired, .superseded, .cancelled: return true
        case .pendingSeller, .pendingBuyer: return false
        }
    }

    /// Gray-out card chrome (design §9).
    var isInactiveChrome: Bool {
        switch self {
        case .expired, .superseded, .rejected, .cancelled: return true
        case .pendingSeller, .pendingBuyer, .accepted: return false
        }
    }

    var displayLabel: String {
        switch self {
        case .pendingSeller: return "待卖家处理"
        case .pendingBuyer: return "待买家处理"
        case .accepted: return "已接受"
        case .rejected: return "已拒绝"
        case .expired: return "已过期"
        case .superseded: return "已失效"
        case .cancelled: return "已取消"
        }
    }
}

enum OfferInitiator: String, Codable, Sendable, CaseIterable, Equatable {
    case buyer
    case seller

    var displayLabel: String {
        self == .buyer ? "买家报价" : "卖家还价"
    }
}

/// Card action keys from server `actions[]` (design §3). Client only renders; ops go via API.
enum OfferCardAction: String, Codable, Sendable, CaseIterable, Equatable {
    case accept
    case reject
    case counter
    case cancel
    case pay

    var title: String {
        switch self {
        case .accept: return "接受"
        case .reject: return "拒绝"
        case .counter: return "还价"
        case .cancel: return "取消报价"
        case .pay: return "去付款"
        }
    }

    var isPrimary: Bool {
        self == .accept || self == .pay
    }
}

enum OfferRejectReasonCode: String, Codable, Sendable, CaseIterable, Equatable {
    case priceNotFit = "price_not_fit"
    case alreadyIntended = "already_intended"
    case other

    var title: String {
        switch self {
        case .priceNotFit: return "价格不合适"
        case .alreadyIntended: return "已有意向"
        case .other: return "其他"
        }
    }

    var requiresNote: Bool { self == .other }
}

enum OfferRole: String, Codable, Sendable, CaseIterable, Equatable {
    case buyer
    case seller
}

/// Stable API error codes (design §5.10 / §6).
enum OfferErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case offerBelowMin = "offer_below_min"
    case offerRoundExceeded = "offer_round_exceeded"
    case offerExpired = "offer_expired"
    case offerSuperseded = "offer_superseded"
    case listingNotNegotiable = "listing_not_negotiable"
    case chatPriceNotBinding = "chat_price_not_binding"
    case offerUnpaidBanned = "offer_unpaid_banned"
    case offerNotNegotiableUser = "offer_not_negotiable_user"
    case stockInsufficient = "stock_insufficient"
    case realNameRequired = "real_name_required"
    case creditTooLow = "credit_too_low"
    case accountRestricted = "account_restricted"
    case unauthorized
    case selfTradeForbidden = "self_trade_forbidden"

    var opensRealName: Bool { self == .realNameRequired }
    var opensLogin: Bool { self == .unauthorized }

    var retriesSameIdempotencyKey: Bool {
        self == .stockInsufficient
    }

    var fallbackMessage: String {
        switch self {
        case .offerBelowMin:
            return "报价过低"
        case .offerRoundExceeded:
            return "已达最大议价轮次"
        case .offerExpired:
            return "报价已过期"
        case .offerSuperseded:
            return "商品已变更，报价失效"
        case .listingNotNegotiable:
            return "该商品暂不可议价"
        case .chatPriceNotBinding:
            return "请使用报价卡片议价"
        case .offerUnpaidBanned, .offerNotNegotiableUser:
            return "议价暂不可用，可使用立即购买"
        case .stockInsufficient:
            return "商品已被锁定，请稍后再试或等待释放"
        case .realNameRequired:
            return "请先完成实名认证"
        case .creditTooLow:
            return "信用分不足，完成交易可恢复信用"
        case .accountRestricted:
            return "账号受限，暂不可议价"
        case .unauthorized:
            return "请先登录"
        case .selfTradeForbidden:
            return "不可对自己的商品报价"
        }
    }

    func message(minPriceFen: Int64? = nil, banUntilText: String? = nil) -> String {
        switch self {
        case .offerBelowMin:
            if let minPriceFen {
                return "报价不得低于 \(OfferLogic.yuanDisplay(minPriceFen))"
            }
            return fallbackMessage
        case .offerUnpaidBanned, .offerNotNegotiableUser:
            if let banUntilText {
                return "议价暂不可用至 \(banUntilText)，可使用立即购买"
            }
            return fallbackMessage
        default:
            return fallbackMessage
        }
    }
}

// MARK: - Copy

enum OfferCopy {
    static let entryTitle = "议价"
    static let sheetTitle = "发送报价"
    static let counterTitle = "还价"
    static let rejectTitle = "拒绝报价"
    static let emptySeller = "暂无报价"
    static let emptyBuyerPrefix = "该商品可议价，最低"
    static let serverTimeHint = "以服务器时间为准"
    static let roundLabelFormat = "第 %d/%d 轮"
    static let listPriceLabel = "标价"
    static let offerPriceLabel = "报价"
    static let payDeadlineLabel = "付款截止"
    static let offerCountdownLabel = "报价剩余"
    static let expiredHint = "报价已过期"
    static let chatGuide = "请点议价按钮"
    static let chatAmountHint = "聊天金额不能下单，请使用报价卡片"
    static let weakNetRetry = "未成交可重试"
    static let priceDropPushTitle = "你收藏的商品降价了"
    static let submitOffer = "发送报价"
    static let submitCounter = "发送还价"
    static let lockPayRule = "接受后 2 小时内付款"
    static let ttlRule = "报价 24 小时有效"
    static let accessibilityCard = "报价卡片"
    static let pendingButton = "处理中…"

    static func emptyBuyer(minPriceFen: Int64) -> String {
        "\(emptyBuyerPrefix) \(OfferLogic.yuanDisplay(minPriceFen))"
    }

    static func roundLabel(round: Int, maxRounds: Int = OfferConfigDefaults.maxRounds) -> String {
        String(format: roundLabelFormat, Swift.max(1, round), maxRounds)
    }

    static func priceDropBody(oldFen: Int64, newFen: Int64) -> String {
        "由 \(OfferLogic.yuanDisplay(oldFen)) 降至 \(OfferLogic.yuanDisplay(newFen))"
    }
}

// MARK: - DTOs

struct Offer: Codable, Equatable, Sendable, Identifiable {
    let id: Int64
    let listingId: Int64
    let buyerId: Int64
    let sellerId: Int64
    let round: Int
    let buyerQuoteCount: Int?
    let initiator: OfferInitiator
    let price: Int64
    let status: OfferStatus
    let expiresAt: Date
    let orderId: Int64?
    let listingPriceSnapshot: Int64?
    let minRatioSnapshot: Double?
    let minPrice: Int64?
    let version: Int64?
    let rejectReason: String?
    let payDeadline: Date?
    let serverTime: Date?
    let createdAt: Date?
    let updatedAt: Date?

    init(
        id: Int64,
        listingId: Int64,
        buyerId: Int64,
        sellerId: Int64,
        round: Int,
        buyerQuoteCount: Int? = nil,
        initiator: OfferInitiator,
        price: Int64,
        status: OfferStatus,
        expiresAt: Date,
        orderId: Int64? = nil,
        listingPriceSnapshot: Int64? = nil,
        minRatioSnapshot: Double? = nil,
        minPrice: Int64? = nil,
        version: Int64? = nil,
        rejectReason: String? = nil,
        payDeadline: Date? = nil,
        serverTime: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.listingId = listingId
        self.buyerId = buyerId
        self.sellerId = sellerId
        self.round = round
        self.buyerQuoteCount = buyerQuoteCount
        self.initiator = initiator
        self.price = price
        self.status = status
        self.expiresAt = expiresAt
        self.orderId = orderId
        self.listingPriceSnapshot = listingPriceSnapshot
        self.minRatioSnapshot = minRatioSnapshot
        self.minPrice = minPrice
        self.version = version
        self.rejectReason = rejectReason
        self.payDeadline = payDeadline
        self.serverTime = serverTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var resolvedMinPrice: Int64 {
        if let minPrice { return minPrice }
        if let snap = listingPriceSnapshot {
            return OfferLogic.minPriceFen(listPriceFen: snap, ratio: minRatioSnapshot ?? OfferConfigDefaults.minRatio)
        }
        return OfferLogic.minPriceFen(listPriceFen: price, ratio: OfferConfigDefaults.minRatio)
    }

    var displayRound: Int { max(1, round) }
}

/// IM / UI card payload (design §3 / §5.1). Read-only; price lives on offer row.
struct OfferCard: Codable, Equatable, Sendable, Identifiable {
    var id: Int64 { offerId }
    let offerId: Int64
    let listingId: Int64?
    let cover: String?
    let title: String?
    let listPrice: Int64
    let offerPrice: Int64
    let expiresAt: Date
    let round: Int
    let maxRounds: Int?
    let status: OfferStatus?
    let actions: [OfferCardAction]
    let orderId: Int64?
    let payDeadline: Date?
    let serverTime: Date?
    let minPrice: Int64?
    let buyerQuoteCount: Int?

    init(
        offerId: Int64,
        listingId: Int64? = nil,
        cover: String? = nil,
        title: String? = nil,
        listPrice: Int64,
        offerPrice: Int64,
        expiresAt: Date,
        round: Int,
        maxRounds: Int? = OfferConfigDefaults.maxRounds,
        status: OfferStatus? = nil,
        actions: [OfferCardAction] = [],
        orderId: Int64? = nil,
        payDeadline: Date? = nil,
        serverTime: Date? = nil,
        minPrice: Int64? = nil,
        buyerQuoteCount: Int? = nil
    ) {
        self.offerId = offerId
        self.listingId = listingId
        self.cover = cover
        self.title = title
        self.listPrice = listPrice
        self.offerPrice = offerPrice
        self.expiresAt = expiresAt
        self.round = round
        self.maxRounds = maxRounds
        self.status = status
        self.actions = actions
        self.orderId = orderId
        self.payDeadline = payDeadline
        self.serverTime = serverTime
        self.minPrice = minPrice
        self.buyerQuoteCount = buyerQuoteCount
    }

    enum CodingKeys: String, CodingKey {
        case offerId, listingId, cover, title, listPrice, offerPrice, expiresAt
        case round, maxRounds, status, actions, orderId, payDeadline, serverTime, minPrice, buyerQuoteCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offerId = try Self.decodeID(c, forKey: .offerId)
        listingId = try Self.decodeOptionalID(c, forKey: .listingId)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        listPrice = try c.decode(Int64.self, forKey: .listPrice)
        offerPrice = try c.decode(Int64.self, forKey: .offerPrice)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        round = try c.decode(Int.self, forKey: .round)
        maxRounds = try c.decodeIfPresent(Int.self, forKey: .maxRounds)
        status = try c.decodeIfPresent(OfferStatus.self, forKey: .status)
        actions = try c.decodeIfPresent([OfferCardAction].self, forKey: .actions) ?? []
        orderId = try Self.decodeOptionalID(c, forKey: .orderId)
        payDeadline = try c.decodeIfPresent(Date.self, forKey: .payDeadline)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
        minPrice = try c.decodeIfPresent(Int64.self, forKey: .minPrice)
        buyerQuoteCount = try c.decodeIfPresent(Int.self, forKey: .buyerQuoteCount)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(offerId, forKey: .offerId)
        try c.encodeIfPresent(listingId, forKey: .listingId)
        try c.encodeIfPresent(cover, forKey: .cover)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(listPrice, forKey: .listPrice)
        try c.encode(offerPrice, forKey: .offerPrice)
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encode(round, forKey: .round)
        try c.encodeIfPresent(maxRounds, forKey: .maxRounds)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encode(actions, forKey: .actions)
        try c.encodeIfPresent(orderId, forKey: .orderId)
        try c.encodeIfPresent(payDeadline, forKey: .payDeadline)
        try c.encodeIfPresent(serverTime, forKey: .serverTime)
        try c.encodeIfPresent(minPrice, forKey: .minPrice)
        try c.encodeIfPresent(buyerQuoteCount, forKey: .buyerQuoteCount)
    }

    var resolvedMaxRounds: Int { maxRounds ?? OfferConfigDefaults.maxRounds }

    var roundText: String {
        OfferCopy.roundLabel(round: round, maxRounds: resolvedMaxRounds)
    }

    var isExpiredAgainst: (Date) -> Bool {
        { now in expiresAt <= now || status == .expired }
    }

    var showsActions: Bool {
        guard let status else { return !actions.isEmpty }
        return status.isPending && !actions.isEmpty
    }

    var accessibilityLabel: String {
        let titlePart = title.map { "，\($0)" } ?? ""
        return "\(OfferCopy.accessibilityCard)\(titlePart)，\(OfferCopy.listPriceLabel) \(OfferLogic.yuanDisplay(listPrice))，\(OfferCopy.offerPriceLabel) \(OfferLogic.yuanDisplay(offerPrice))"
    }

    private static func decodeID(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int64 {
        if let v = try? c.decode(Int64.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int64(s) { return v }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "expected id")
    }

    private static func decodeOptionalID(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int64? {
        if let v = try? c.decode(Int64.self, forKey: key) { return v }
        if let s = try? c.decode(String.self, forKey: key), let v = Int64(s) { return v }
        return nil
    }
}

struct CreateOfferRequest: Codable, Equatable, Sendable {
    let price: Int64

    init(price: Int64) {
        self.price = price
    }
}

struct CreateOfferResponse: Codable, Equatable, Sendable {
    let offerId: Int64
    let expiresAt: Date
    let minPrice: Int64
    let round: Int?
    let status: OfferStatus?
    let serverTime: Date?
    let card: OfferCard?

    init(
        offerId: Int64,
        expiresAt: Date,
        minPrice: Int64,
        round: Int? = 1,
        status: OfferStatus? = .pendingSeller,
        serverTime: Date? = nil,
        card: OfferCard? = nil
    ) {
        self.offerId = offerId
        self.expiresAt = expiresAt
        self.minPrice = minPrice
        self.round = round
        self.status = status
        self.serverTime = serverTime
        self.card = card
    }

    enum CodingKeys: String, CodingKey {
        case offerId, expiresAt, minPrice, round, status, serverTime, card
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(Int64.self, forKey: .offerId) {
            offerId = v
        } else if let s = try? c.decode(String.self, forKey: .offerId), let v = Int64(s) {
            offerId = v
        } else {
            throw DecodingError.dataCorruptedError(forKey: .offerId, in: c, debugDescription: "expected offer_id")
        }
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        minPrice = try c.decode(Int64.self, forKey: .minPrice)
        round = try c.decodeIfPresent(Int.self, forKey: .round)
        status = try c.decodeIfPresent(OfferStatus.self, forKey: .status)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
        card = try c.decodeIfPresent(OfferCard.self, forKey: .card)
    }
}

struct CounterOfferRequest: Codable, Equatable, Sendable {
    let price: Int64

    init(price: Int64) {
        self.price = price
    }
}

struct CounterOfferResponse: Codable, Equatable, Sendable {
    let expiresAt: Date
    let round: Int
    let status: OfferStatus?
    let price: Int64?
    let serverTime: Date?
    let card: OfferCard?

    init(
        expiresAt: Date,
        round: Int,
        status: OfferStatus? = nil,
        price: Int64? = nil,
        serverTime: Date? = nil,
        card: OfferCard? = nil
    ) {
        self.expiresAt = expiresAt
        self.round = round
        self.status = status
        self.price = price
        self.serverTime = serverTime
        self.card = card
    }
}

struct RejectOfferRequest: Codable, Equatable, Sendable {
    let reason: OfferRejectReasonCode
    let note: String?

    init(reason: OfferRejectReasonCode, note: String? = nil) {
        self.reason = reason
        self.note = note
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(reason, forKey: .reason)
        try c.encodeIfPresent(note, forKey: .note)
    }

    private enum CodingKeys: String, CodingKey { case reason, note }
}

struct RejectOfferResponse: Codable, Equatable, Sendable {
    let status: OfferStatus

    init(status: OfferStatus = .rejected) {
        self.status = status
    }
}

struct CancelOfferResponse: Codable, Equatable, Sendable {
    let status: OfferStatus

    init(status: OfferStatus = .cancelled) {
        self.status = status
    }
}

/// Accept → lock-price order (design §5.3 / T-01). Pay window = 2h, not 15min.
struct AcceptOfferResponse: Codable, Equatable, Sendable {
    let orderId: Int64
    let payDeadline: Date
    let serverTime: Date?
    let amount: Int64?
    let offerId: Int64?

    init(
        orderId: Int64,
        payDeadline: Date,
        serverTime: Date? = nil,
        amount: Int64? = nil,
        offerId: Int64? = nil
    ) {
        self.orderId = orderId
        self.payDeadline = payDeadline
        self.serverTime = serverTime
        self.amount = amount
        self.offerId = offerId
    }

    enum CodingKeys: String, CodingKey {
        case orderId, payDeadline, serverTime, amount, offerId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(Int64.self, forKey: .orderId) {
            orderId = v
        } else if let s = try? c.decode(String.self, forKey: .orderId), let v = Int64(s) {
            orderId = v
        } else {
            throw DecodingError.dataCorruptedError(forKey: .orderId, in: c, debugDescription: "expected order_id")
        }
        payDeadline = try c.decode(Date.self, forKey: .payDeadline)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
        amount = try c.decodeIfPresent(Int64.self, forKey: .amount)
        if let v = try? c.decode(Int64.self, forKey: .offerId) {
            offerId = v
        } else if let s = try? c.decode(String.self, forKey: .offerId), let v = Int64(s) {
            offerId = v
        } else {
            offerId = nil
        }
    }
}

struct OfferListPage: Codable, Equatable, Sendable {
    let items: [Offer]
    let nextCursor: String?

    init(items: [Offer], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// POST `/listings/{id}/favorite` response (design §6). `price_snapshot` may be absent on older servers.
struct FavoriteListingResult: Codable, Equatable, Sendable {
    let priceSnapshot: Int64?
    let listingId: Int64?
    let favorited: Bool?

    init(priceSnapshot: Int64? = nil, listingId: Int64? = nil, favorited: Bool? = true) {
        self.priceSnapshot = priceSnapshot
        self.listingId = listingId
        self.favorited = favorited
    }

    enum CodingKeys: String, CodingKey {
        case priceSnapshot, listingId, favorited
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        priceSnapshot = try c.decodeIfPresent(Int64.self, forKey: .priceSnapshot)
        if let v = try? c.decode(Int64.self, forKey: .listingId) {
            listingId = v
        } else if let s = try? c.decode(String.self, forKey: .listingId), let v = Int64(s) {
            listingId = v
        } else {
            listingId = nil
        }
        favorited = try c.decodeIfPresent(Bool.self, forKey: .favorited)
    }
}

/// Client-side price-drop cooldown key (design §5.5). Survives unfavorite.
struct PriceDropCooldown: Codable, Equatable, Sendable {
    let userId: Int64
    let listingId: Int64
    let lastNotifiedAt: Date?
    let lastPrice: Int64?

    init(userId: Int64, listingId: Int64, lastNotifiedAt: Date? = nil, lastPrice: Int64? = nil) {
        self.userId = userId
        self.listingId = listingId
        self.lastNotifiedAt = lastNotifiedAt
        self.lastPrice = lastPrice
    }
}

// MARK: - Logic

enum OfferLogic {
    /// `min_price = ceil(listing.price * ratio)` (design §3).
    static func minPriceFen(listPriceFen: Int64, ratio: Double = OfferConfigDefaults.minRatio) -> Int64 {
        guard listPriceFen > 0 else { return 0 }
        let r = max(0, min(1, ratio))
        return Int64((Double(listPriceFen) * r).rounded(.up))
    }

    static func yuanDisplay(_ fen: Int64) -> String {
        let yuan = Double(fen) / 100.0
        if fen % 100 == 0 {
            return String(format: "¥%.0f", yuan)
        }
        return String(format: "¥%.2f", yuan)
    }

    /// Buyer first quote / buyer re-quote: `min ≤ price ≤ list`. Seller counter: `min ≤ price` (may be below buyer ask).
    static func validateOfferPrice(
        priceFen: Int64,
        listPriceFen: Int64,
        minPriceFen: Int64,
        asBuyerQuote: Bool
    ) -> OfferErrorCode? {
        guard priceFen > 0 else { return .offerBelowMin }
        if priceFen < minPriceFen { return .offerBelowMin }
        if asBuyerQuote, priceFen > listPriceFen {
            // No dedicated API code; surface as below-min style client block with list-price copy.
            return .offerBelowMin
        }
        return nil
    }

    static func localPriceMessage(
        priceFen: Int64,
        listPriceFen: Int64,
        minPriceFen: Int64,
        asBuyerQuote: Bool
    ) -> String? {
        guard priceFen > 0 else { return "请输入报价金额" }
        if priceFen < minPriceFen {
            return OfferErrorCode.offerBelowMin.message(minPriceFen: minPriceFen)
        }
        if asBuyerQuote, priceFen > listPriceFen {
            return "报价不得超过标价 \(yuanDisplay(listPriceFen))"
        }
        return nil
    }

    static func canBuyerQuote(buyerQuoteCount: Int, max: Int = OfferConfigDefaults.maxRounds) -> Bool {
        buyerQuoteCount < max
    }

    /// After buyer's 3rd quote, seller may only accept / reject (design §5.2).
    static func canSellerCounter(buyerQuoteCount: Int, max: Int = OfferConfigDefaults.maxRounds) -> Bool {
        buyerQuoteCount < max
    }

    static func nextBuyerQuoteCount(current: Int, isBuyerQuote: Bool) -> Int {
        isBuyerQuote ? current + 1 : current
    }

    static func countdownSeconds(deadline: Date, serverTime: Date) -> Int {
        max(0, Int(deadline.timeIntervalSince(serverTime)))
    }

    static func formatCountdown(seconds: Int) -> String {
        let total = max(0, seconds)
        let d = total / 86_400
        let h = (total % 86_400) / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if d > 0 {
            return String(format: "%d天%02d:%02d:%02d", d, h, m, s)
        }
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    static func offerCountdownLine(seconds: Int) -> String {
        "\(OfferCopy.offerCountdownLabel) \(formatCountdown(seconds: seconds)) · \(OfferCopy.serverTimeHint)"
    }

    static func payCountdownLine(seconds: Int) -> String {
        "\(OfferCopy.payDeadlineLabel) \(formatCountdown(seconds: seconds)) · \(OfferCopy.serverTimeHint)"
    }

    /// Default pay window after accept (2h). Distinct from buy-now 15min.
    static func payDeadline(from now: Date, hours: Int = OfferConfigDefaults.payHours) -> Date {
        now.addingTimeInterval(TimeInterval(hours * 3600))
    }

    static func offerExpiresAt(from now: Date, hours: Int = OfferConfigDefaults.ttlHours) -> Date {
        now.addingTimeInterval(TimeInterval(hours * 3600))
    }

    /// DIR-05: drop only; on_sale; 24h cooldown per user+listing; raise / off-shelf / sold → no push.
    static func shouldNotifyPriceDrop(
        oldPriceFen: Int64,
        newPriceFen: Int64,
        listingOnSale: Bool,
        lastNotifiedAt: Date?,
        now: Date = Date(),
        cooldownHours: Int = OfferConfigDefaults.priceDropCooldownHours
    ) -> Bool {
        guard listingOnSale else { return false }
        guard newPriceFen < oldPriceFen else { return false }
        if let last = lastNotifiedAt {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < TimeInterval(cooldownHours * 3600) { return false }
        }
        return true
    }

    /// Unfavorite does not reset cooldown (design §5.5).
    static func cooldownSurvivesUnfavorite() -> Bool { true }

    static func offerGate(
        isLoggedIn: Bool,
        realNameDone: Bool,
        creditScore: Int,
        isRestricted: Bool,
        isOwner: Bool,
        negotiable: Bool,
        unpaidBanned: Bool = false
    ) -> OfferErrorCode? {
        if !isLoggedIn { return .unauthorized }
        if isRestricted { return .accountRestricted }
        if unpaidBanned { return .offerUnpaidBanned }
        if !realNameDone { return .realNameRequired }
        if creditScore < OfferConfigDefaults.creditMinToOffer { return .creditTooLow }
        if isOwner { return .selfTradeForbidden }
        if !negotiable { return .listingNotNegotiable }
        return nil
    }

    /// Derive counterpart actions when server omits `actions[]` (optimistic UI).
    static func defaultActions(
        status: OfferStatus,
        role: OfferRole,
        buyerQuoteCount: Int = 0,
        hasOrder: Bool = false
    ) -> [OfferCardAction] {
        switch status {
        case .pendingSeller:
            if role == .seller {
                var a: [OfferCardAction] = [.accept, .reject]
                if canSellerCounter(buyerQuoteCount: buyerQuoteCount) { a.append(.counter) }
                return a
            }
            if role == .buyer { return [.cancel] }
            return []
        case .pendingBuyer:
            if role == .buyer {
                var a: [OfferCardAction] = [.accept, .reject]
                if canBuyerQuote(buyerQuoteCount: buyerQuoteCount) { a.append(.counter) }
                return a
            }
            return []
        case .accepted:
            if role == .buyer, hasOrder { return [.pay] }
            return []
        default:
            return []
        }
    }

    /// Sort seller inbox: soonest expiry first (design §9).
    static func sortPendingByExpiry(_ offers: [Offer]) -> [Offer] {
        offers
            .filter(\.status.isPending)
            .sorted { $0.expiresAt < $1.expiresAt }
    }

    /// Chat text that looks like a price offer → guide to structured card (design §5.6).
    static func looksLikePriceOfferText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let patterns = [
            #"^\d{2,7}$"#,
            #"^\d{1,3}(,\d{3})+$"#,
            #"^¥?\s*\d+(\.\d{1,2})?\s*元?$"#,
            #".*(成交|报价|刀|便宜点).*\d+.*"#,
            #".*\d+.*(成交|报价).*"#,
        ]
        for p in patterns {
            if t.range(of: p, options: .regularExpression) != nil { return true }
        }
        return false
    }

    static func validateRejectNote(reason: OfferRejectReasonCode, note: String?) -> String? {
        guard reason.requiresNote else { return nil }
        let n = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return "请填写原因" }
        if n.count > OfferConfigDefaults.rejectOtherMaxChars {
            return "原因不超过 \(OfferConfigDefaults.rejectOtherMaxChars) 字"
        }
        return nil
    }

    /// Illegal transitions (design §4).
    static func canTransition(from: OfferStatus, to: OfferStatus) -> Bool {
        switch (from, to) {
        case (.pendingSeller, .accepted),
             (.pendingSeller, .rejected),
             (.pendingSeller, .pendingBuyer),
             (.pendingSeller, .expired),
             (.pendingSeller, .superseded),
             (.pendingSeller, .cancelled),
             (.pendingBuyer, .accepted),
             (.pendingBuyer, .rejected),
             (.pendingBuyer, .pendingSeller),
             (.pendingBuyer, .expired),
             (.pendingBuyer, .superseded),
             (.pendingBuyer, .cancelled):
            return true
        default:
            return false
        }
    }

    static func lockPayHoursDistinctFromBuyNow(
        offerPayHours: Int = OfferConfigDefaults.payHours,
        buyNowMinutes: Int = 15
    ) -> Bool {
        offerPayHours * 60 != buyNowMinutes
    }
}
