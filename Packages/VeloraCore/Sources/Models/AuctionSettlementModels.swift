import Foundation

// MARK: - Hammer / lock / default / unsold / cancel (DES-v1.3-03-05 AUC-09/10/11/12/15)

/// Product defaults (design §5 / §13 / B-11). Hot-config on server; client mirrors for UX.
public enum AuctionSettlementConfig {
    /// Default `pay_deadline = hammer_at + payHours` (hours).
    public static let payHoursDefault: Int = 24
    /// N-06 fires at `pay_deadline - payRemindBeforeHours`.
    public static let payRemindBeforeHours: Int = 2
    /// Credit delta on AUC-10 non-payment (`auction_non_payment`).
    public static let creditPenalty: Int = -10
    /// First bidding ban length (days).
    public static let firstBanDays: Int = 30
    /// Second offense ban length (days).
    public static let secondBanDays: Int = 90
    /// Default forfeit seller share in basis points (5000 = 50%).
    public static let defaultForfeitSellerBp: Int = 5000
    /// Admin force-cancel reason minimum length (design §5.4).
    public static let minForceCancelReasonChars: Int = 10
    /// Second-chance offer validity (hours) — Phase 3.
    public static let secondChanceValidHours: Int = 24
    /// Seller may open second-chance within N days after default.
    public static let secondChanceSellerWindowDays: Int = 7
    /// Free-end relist: new `end_at` must be ≥ published_at + this many hours.
    public static let minRelistEndHours: Int = 24
}

/// Stable settlement API error codes (design §6).
public enum AuctionSettlementErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case priceLocked = "price_locked"
    case lotHasBids = "lot_has_bids"
    case notUnsold = "not_unsold"
    case noSecondBidder = "no_second_bidder"
    case offerExpired = "offer_expired"
    case auctionPayOverdue = "auction_pay_overdue"
    case reasonRequired = "reason_required"
    case secondChanceOpen = "second_chance_open"

    public var fallbackMessage: String {
        switch self {
        case .priceLocked:
            return AuctionSettlementCopy.priceLocked
        case .lotHasBids:
            return AuctionSettlementCopy.cancelDisabledHasBids
        case .notUnsold:
            return "仅流拍拍品可重新上拍"
        case .noSecondBidder:
            return "没有可邀请的次高出价人"
        case .offerExpired:
            return "邀约已过期"
        case .auctionPayOverdue:
            return "付款已超时，订单已关闭"
        case .reasonRequired:
            return "请填写至少 \(AuctionSettlementConfig.minForceCancelReasonChars) 字撤拍原因"
        case .secondChanceOpen:
            return "有进行中的次高价邀约，暂不可重新上拍"
        }
    }

    public var opensAfterSalesHint: Bool { self == .priceLocked }
    public var blocksSellerCancel: Bool { self == .lotHasBids }
}

/// UX copy (design §9). Never reveal reserve gap or seller forfeit split to the buyer.
public enum AuctionSettlementCopy {
    public static let wonTitle = "恭喜您拍中！"
    public static let wonSubtitle = "成交价已锁定，请在截止前完成付款"
    public static let priceLocked = "成交价已锁定，如需协商请走售后"
    public static let payCountdownLabel = "付款截止"
    public static let payRemindBanner = "付款即将截止，超时将视为违约"
    public static let goPay = "去付款"
    public static let cancelEqualsDefault = "取消即视为违约：将罚没保证金、扣信用并禁竞拍"
    public static let unsoldTitle = "本次流拍"
    public static let unsoldReasonPublic = "未成交"
    public static let unsoldSellerHint = "未达到成交条件，保证金已解冻。可调整参数后重新上拍。"
    public static let relistAction = "一键重新上拍"
    public static let relistNeedNewEnd = "请重新选择结束时间（须距现在至少 24 小时）"
    public static let relistedLink = "已重新上拍"
    public static let unsoldEmpty = "暂无流拍拍品"
    public static let cancelDisabledHasBids = "已有出价不可撤回"
    public static let defaultBuyerTitle = "未付款已关闭"
    public static let defaultBuyerHint = "超时未付款已按违约处理"
    public static let defaultCreditLine = "信用分 −10"
    public static let defaultBanLabel = "禁竞拍至"
    public static let defaultBanPermanent = "永久禁竞拍"
    public static let defaultSellerTitle = "买家违约关单"
    public static let defaultSellerDepositHint = "保证金赔付处理中，到账后可在钱包查看"
    public static let secondChanceAction = "邀请第二名" // Phase 3 entry; hide when unavailable
    public static let reserveNotMetBuyer = "未达保留价未成交"
}

// MARK: - Fee rule snapshot (orders.fee_rule_snapshot)

/// Locked at `CreateFromLot` (design §3). Personal vs proxy may differ at same hammer.
public struct FeeRuleSnapshot: Codable, Equatable, Sendable {
    public let sellerType: String?
    public let tradeType: String?
    public let rateBp: Int?
    public let ruleId: String?
    public let snappedAt: Date?
    public let shippingFee: Int64?
    public let platformFee: Int64?
    public let sellerNet: Int64?

    public init(
        sellerType: String? = nil,
        tradeType: String? = nil,
        rateBp: Int? = nil,
        ruleId: String? = nil,
        snappedAt: Date? = nil,
        shippingFee: Int64? = nil,
        platformFee: Int64? = nil,
        sellerNet: Int64? = nil
    ) {
        self.sellerType = sellerType
        self.tradeType = tradeType
        self.rateBp = rateBp
        self.ruleId = ruleId
        self.snappedAt = snappedAt
        self.shippingFee = shippingFee
        self.platformFee = platformFee
        self.sellerNet = sellerNet
    }

    public var ratePercentText: String? {
        guard let rateBp else { return nil }
        return String(format: "%.1f%%", Double(rateBp) / 100)
    }
}

// MARK: - Outcome / eligibility

/// Client-facing settlement outcome for a finished lot + optional order.
public enum AuctionSettlementOutcome: String, Sendable, Equatable {
    case won
    case lost
    case unsold
    case cancelled
    case defaulted

    public var displayTitle: String {
        switch self {
        case .won: return AuctionSettlementCopy.wonTitle
        case .lost: return "很遗憾，与它擦肩而过"
        case .unsold: return AuctionSettlementCopy.unsoldTitle
        case .cancelled: return "拍卖已取消"
        case .defaulted: return AuctionSettlementCopy.defaultBuyerTitle
        }
    }
}

public enum AuctionSettlementLogic {
    /// Design §5.1: `reserveMet = reserve==nil || current>=reserve`.
    public static func reserveMet(currentPrice: Int64, reservePrice: Int64?) -> Bool {
        guard let reservePrice else { return true }
        return currentPrice >= reservePrice
    }

    /// Sold path when there is a winner and reserve is met.
    public static func shouldCreateOrder(hasWinner: Bool, reserveMet: Bool) -> Bool {
        hasWinner && reserveMet
    }

    /// Seller cancel allowed only for `scheduled`/`live` with zero bids (design §5.4).
    public static func canSellerCancel(status: String, bidCount: Int) -> Bool {
        guard bidCount == 0 else { return false }
        return status == "scheduled" || status == "live"
    }

    public static func sellerCancelBlockedReason(bidCount: Int) -> String? {
        bidCount > 0 ? AuctionSettlementCopy.cancelDisabledHasBids : nil
    }

    /// Relist only when `unsold` (or cancelled without ban) and no pending second-chance (design §5.3 / §5.5).
    public static func canRelist(status: String, secondChancePending: Bool = false) -> Bool {
        if secondChancePending { return false }
        return status == "unsold" || status == "cancelled"
    }

    public static func relistBlockedReason(status: String, secondChancePending: Bool) -> AuctionSettlementErrorCode? {
        if secondChancePending { return .secondChanceOpen }
        if status != "unsold" && status != "cancelled" { return .notUnsold }
        return nil
    }

    /// Admin force-cancel reason ≥ 10 chars (design §5.4 / matrix).
    public static func isForceCancelReasonValid(_ reason: String) -> Bool {
        reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= AuctionSettlementConfig.minForceCancelReasonChars
    }

    public static func payDeadline(hammerAt: Date, payHours: Int = AuctionSettlementConfig.payHoursDefault) -> Date {
        hammerAt.addingTimeInterval(TimeInterval(payHours * 3600))
    }

    /// N-06 run-at. If window shorter than 2h (审核短窗), fire immediately after create.
    public static func payRemindAt(payDeadline: Date, hammerAt: Date, remindBeforeHours: Int = AuctionSettlementConfig.payRemindBeforeHours) -> Date {
        let candidate = payDeadline.addingTimeInterval(-TimeInterval(remindBeforeHours * 3600))
        return candidate <= hammerAt ? hammerAt : candidate
    }

    public static func isPayRemindWindow(now: Date, payDeadline: Date, hammerAt: Date) -> Bool {
        let remind = payRemindAt(payDeadline: payDeadline, hammerAt: hammerAt)
        return now >= remind && now < payDeadline
    }

    /// Free-end relist: `endAt >= now + 24h`.
    public static func isRelistEndAtValid(_ endAt: Date, now: Date = Date(), minHours: Int = AuctionSettlementConfig.minRelistEndHours) -> Bool {
        endAt.timeIntervalSince(now) >= TimeInterval(minHours * 3600)
    }

    /// Offense count → ban end (`nil` = permanent). 1→30d, 2→90d, ≥3→permanent (design §13).
    public static func biddingBanUntil(offenseCount: Int, now: Date = Date()) -> Date? {
        switch max(0, offenseCount) {
        case 0: return now
        case 1: return now.addingTimeInterval(TimeInterval(AuctionSettlementConfig.firstBanDays * 86_400))
        case 2: return now.addingTimeInterval(TimeInterval(AuctionSettlementConfig.secondBanDays * 86_400))
        default: return nil
        }
    }

    public static func forfeitSellerAmount(depositFen: Int64, sellerBp: Int = AuctionSettlementConfig.defaultForfeitSellerBp) -> Int64 {
        max(0, depositFen * Int64(sellerBp) / 10_000)
    }

    public static func forfeitPlatformAmount(depositFen: Int64, sellerBp: Int = AuctionSettlementConfig.defaultForfeitSellerBp) -> Int64 {
        max(0, depositFen - forfeitSellerAmount(depositFen: depositFen, sellerBp: sellerBp))
    }

    /// Resolve UX outcome from lot status + viewer role + order cancel reason.
    public static func outcome(
        lotStatus: String,
        viewerIsWinner: Bool,
        viewerHadBid: Bool,
        orderCancelledAsDefault: Bool
    ) -> AuctionSettlementOutcome {
        if orderCancelledAsDefault {
            return .defaulted
        }
        switch lotStatus {
        case "ended":
            if viewerIsWinner { return .won }
            if viewerHadBid { return .lost }
            return .won // spectator sees sold
        case "unsold":
            return .unsold
        case "cancelled":
            return .cancelled
        default:
            return .unsold
        }
    }

    /// Public unsold reason — never expose how far below reserve (design §8 / matrix).
    public static func publicUnsoldReason(reserveNotMet: Bool) -> String {
        if reserveNotMet { return AuctionSettlementCopy.unsoldReasonPublic }
        return AuctionSettlementCopy.unsoldReasonPublic
    }
}

// MARK: - Relist API (POST /lots/{id}/relist)

/// Body for seller relist (design §5.8 / §6). Session slots are never copied.
public struct RelistLotRequest: Codable, Equatable, Sendable {
    public var endAt: Date?
    public var startPrice: Int64?
    public var bidIncrement: Int64?
    public var reservePrice: Int64?
    public var depositAmount: Int64?
    public var title: String?
    public var description: String?

    public init(
        endAt: Date? = nil,
        startPrice: Int64? = nil,
        bidIncrement: Int64? = nil,
        reservePrice: Int64? = nil,
        depositAmount: Int64? = nil,
        title: String? = nil,
        description: String? = nil
    ) {
        self.endAt = endAt
        self.startPrice = startPrice
        self.bidIncrement = bidIncrement
        self.reservePrice = reservePrice
        self.depositAmount = depositAmount
        self.title = title
        self.description = description
    }
}

/// Relist success: new lot row; old lot keeps `relisted_from` / outbound link.
public struct RelistLotResponse: Codable, Equatable, Sendable {
    public let lotId: Int64
    public let status: String?
    public let relistedFromLotId: Int64?
    public let endAt: Date?
    public let publishedAt: Date?

    public init(
        lotId: Int64,
        status: String? = nil,
        relistedFromLotId: Int64? = nil,
        endAt: Date? = nil,
        publishedAt: Date? = nil
    ) {
        self.lotId = lotId
        self.status = status
        self.relistedFromLotId = relistedFromLotId
        self.endAt = endAt
        self.publishedAt = publishedAt
    }

    enum CodingKeys: String, CodingKey {
        case lotId, status, relistedFromLotId, endAt, publishedAt
        case id, lot
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(Int64.self, forKey: .lotId) {
            lotId = id
        } else if let id = try c.decodeIfPresent(Int64.self, forKey: .id) {
            lotId = id
        } else if let nested = try c.decodeIfPresent(RelistNestedLot.self, forKey: .lot) {
            lotId = nested.id
            status = nested.status
            relistedFromLotId = nested.relistedFromLotId
            endAt = nested.endAt
            publishedAt = nested.publishedAt
            return
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.lotId,
                .init(codingPath: c.codingPath, debugDescription: "missing lot id")
            )
        }
        status = try c.decodeIfPresent(String.self, forKey: .status)
        relistedFromLotId = try c.decodeIfPresent(Int64.self, forKey: .relistedFromLotId)
        endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        publishedAt = try c.decodeIfPresent(Date.self, forKey: .publishedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lotId, forKey: .lotId)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(relistedFromLotId, forKey: .relistedFromLotId)
        try c.encodeIfPresent(endAt, forKey: .endAt)
        try c.encodeIfPresent(publishedAt, forKey: .publishedAt)
    }

    private struct RelistNestedLot: Decodable {
        let id: Int64
        let status: String?
        let relistedFromLotId: Int64?
        let endAt: Date?
        let publishedAt: Date?
    }
}

// MARK: - Seller / admin cancel

public struct LotCancelRequest: Codable, Equatable, Sendable {
    /// Required for admin force-cancel (≥10 chars). Seller cancel omits.
    public var reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}

public struct LotCancelResponse: Codable, Equatable, Sendable {
    public let lotId: Int64?
    public let status: String?

    public init(lotId: Int64? = nil, status: String? = nil) {
        self.lotId = lotId
        self.status = status
    }
}

// MARK: - Buyer cancel pending auction order (= default)

public struct CancelAuctionOrderRequest: Codable, Equatable, Sendable {
    /// Client must send explicit confirm string (design §5.2).
    public let confirm: String

    public init(confirm: String = "取消即视为违约") {
        self.confirm = confirm
    }

    public static let confirmPhrase = "取消即视为违约"
}

// MARK: - Second-chance offer (AUC-15 Phase 3 — models only)

public enum SecondChanceOfferStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pending
    case accepted
    case rejected
    case expired
    case cancelled

    public var isOpen: Bool { self == .pending }

    public var displayLabel: String {
        switch self {
        case .pending: return "次高价待确认"
        case .accepted: return "已接受"
        case .rejected: return "已拒绝"
        case .expired: return "已过期"
        case .cancelled: return "已撤回"
        }
    }
}

public struct SecondChanceOffer: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let lotId: Int64
    public let fromOrderId: Int64?
    public let inviteeId: Int64?
    public let price: Int64
    public let expiresAt: Date
    public let status: SecondChanceOfferStatus

    public init(
        id: Int64,
        lotId: Int64,
        fromOrderId: Int64? = nil,
        inviteeId: Int64? = nil,
        price: Int64,
        expiresAt: Date,
        status: SecondChanceOfferStatus
    ) {
        self.id = id
        self.lotId = lotId
        self.fromOrderId = fromOrderId
        self.inviteeId = inviteeId
        self.price = price
        self.expiresAt = expiresAt
        self.status = status
    }

    public var isAcceptable: Bool { status == .pending }
}

public struct CreateSecondChanceRequest: Codable, Equatable, Sendable {
    public init() {}
}

// MARK: - Default / penalty presentation

/// Buyer-facing default summary after AUC-10 (no seller forfeit split amounts).
public struct AuctionDefaultBuyerSummary: Equatable, Sendable {
    public let creditDelta: Int
    public let banUntil: Date?
    public let isPermanentBan: Bool
    public let orderId: Int64?
    public let lotTitle: String?

    public init(
        creditDelta: Int = AuctionSettlementConfig.creditPenalty,
        banUntil: Date?,
        isPermanentBan: Bool = false,
        orderId: Int64? = nil,
        lotTitle: String? = nil
    ) {
        self.creditDelta = creditDelta
        self.banUntil = banUntil
        self.isPermanentBan = isPermanentBan || banUntil == nil
        self.orderId = orderId
        self.lotTitle = lotTitle
    }

    public var creditLine: String {
        creditDelta == AuctionSettlementConfig.creditPenalty
            ? AuctionSettlementCopy.defaultCreditLine
            : "信用分 \(creditDelta)"
    }

    public func banLine(dateText: (Date) -> String) -> String {
        if isPermanentBan { return AuctionSettlementCopy.defaultBanPermanent }
        if let banUntil { return "\(AuctionSettlementCopy.defaultBanLabel) \(dateText(banUntil))" }
        return AuctionSettlementCopy.defaultBanPermanent
    }
}

/// Seller-facing default summary — deposit estimate only (design §9 / §15).
public struct AuctionDefaultSellerSummary: Equatable, Sendable {
    public let depositFen: Int64
    public let estimatedSellerShareFen: Int64
    public let payoutStatus: String
    public let canInviteSecondChance: Bool
    public let secondChanceAvailable: Bool

    public init(
        depositFen: Int64,
        estimatedSellerShareFen: Int64? = nil,
        payoutStatus: String = "processing",
        canInviteSecondChance: Bool = false,
        secondChanceAvailable: Bool = false
    ) {
        self.depositFen = depositFen
        self.estimatedSellerShareFen = estimatedSellerShareFen
            ?? AuctionSettlementLogic.forfeitSellerAmount(depositFen: depositFen)
        self.payoutStatus = payoutStatus
        self.canInviteSecondChance = canInviteSecondChance
        self.secondChanceAvailable = secondChanceAvailable
    }

    public var payoutStatusLabel: String {
        switch payoutStatus {
        case "settled", "paid", "credited": return "已到账"
        case "processing", "pending": return "处理中"
        default: return payoutStatus
        }
    }
}

/// Prefill bag for relist UI (old params; end time must be re-picked).
public struct RelistPrefill: Equatable, Sendable {
    public let sourceLotId: Int64
    public let title: String
    public let startPrice: Int64
    public let bidIncrement: Int64
    public let reservePrice: Int64?
    public let depositAmount: Int64
    public let coverURL: String?

    public init(
        sourceLotId: Int64,
        title: String,
        startPrice: Int64,
        bidIncrement: Int64,
        reservePrice: Int64? = nil,
        depositAmount: Int64,
        coverURL: String? = nil
    ) {
        self.sourceLotId = sourceLotId
        self.title = title
        self.startPrice = startPrice
        self.bidIncrement = bidIncrement
        self.reservePrice = reservePrice
        self.depositAmount = depositAmount
        self.coverURL = coverURL
    }

    public func makeRequest(endAt: Date) -> RelistLotRequest {
        RelistLotRequest(
            endAt: endAt,
            startPrice: startPrice,
            bidIncrement: bidIncrement,
            reservePrice: reservePrice,
            depositAmount: depositAmount,
            title: title
        )
    }
}
