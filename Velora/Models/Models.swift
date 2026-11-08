import Foundation

/// 金额单位：分
typealias Money = Int64

extension Money {
    var yuan: Double { Double(self) / 100 }
    /// ¥1,234 或 ¥1,234.50
    var display: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = self % 100 == 0 ? 0 : 2
        f.maximumFractionDigits = 2
        return "¥" + (f.string(from: NSNumber(value: yuan)) ?? "\(yuan)")
    }
    var displayNoSymbol: String { String(display.dropFirst()) }
    var displayFixed: String { String(format: "¥%.2f", yuan) }
}

// MARK: - Envelope / Paging

struct Envelope<T: Decodable>: Decodable {
    let data: T?
    let error: APIErrorBody?
}

struct APIErrorBody: Decodable, Error {
    let code: String
    let message: String
}

struct Page<T: Decodable>: Decodable {
    var items: [T]
    let page: Int
    let pageSize: Int
    let total: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items, page, pageSize, size, total, hasMore
    }

    init(items: [T] = [], page: Int = 1, pageSize: Int = 20, total: Int = 0, hasMore: Bool = false) {
        self.items = items
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.hasMore = hasMore
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([T].self, forKey: .items) ?? []
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        let size = try c.decodeIfPresent(Int.self, forKey: .pageSize)
            ?? c.decodeIfPresent(Int.self, forKey: .size)
            ?? max(items.count, 1)
        pageSize = size
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? items.count
        if let hm = try c.decodeIfPresent(Bool.self, forKey: .hasMore) {
            hasMore = hm
        } else {
            hasMore = page * pageSize < total
        }
    }
}

struct Empty: Decodable {}

// MARK: - User

struct User: Codable, Identifiable, Hashable {
    let id: Int64
    var nickname: String
    var avatar: String
    var bio: String?
    var location: String?
    var creditScore: Int
    var soldCount: Int
    var wonCount: Int
    var lotCount: Int
    var phoneMasked: String?
    var createdAt: Date?
    /// `active` | `rate_limited` | `ban_publish` | `ban_bid` | `frozen` | `pending_deletion` (DES-v1.3-01)
    var status: String?
    var realNameStatus: String?
    var frozenAt: Date?
    var frozenReason: String?

    var isPendingDeletion: Bool { status == "pending_deletion" }
    var isFrozen: Bool { status == AccountStatus.frozen.rawValue }
    var isBanBid: Bool { status == AccountStatus.banBid.rawValue }

    /// Minimal counterpart when list/detail omits embedded user (DES-v1.3-07-01).
    static func placeholder(id: Int64) -> User {
        User(
            id: id,
            nickname: "用户\(id % 10000)",
            avatar: "",
            bio: nil,
            location: nil,
            creditScore: 0,
            soldCount: 0,
            wonCount: 0,
            lotCount: 0,
            phoneMasked: nil,
            createdAt: nil,
            status: nil,
            realNameStatus: nil,
            frozenAt: nil,
            frozenReason: nil
        )
    }
}

struct TokenPair: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: User
    let isNew: Bool
    let deletion: AuthDeletionHint?

    enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, expiresAt, user, isNew, deletion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try c.decode(String.self, forKey: .refreshToken)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        user = try c.decode(User.self, forKey: .user)
        isNew = try c.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
        deletion = try c.decodeIfPresent(AuthDeletionHint.self, forKey: .deletion)
    }
}

struct Address: Codable, Identifiable, Hashable {
    var id: Int64 = 0
    var name: String
    var phone: String
    var province: String
    var city: String
    var district: String
    var detail: String
    var isDefault: Bool

    var oneLine: String { "\(province)\(city)\(district)\(detail)" }
    static let blank = Address(name: "", phone: "", province: "", city: "", district: "", detail: "", isDefault: false)
}

// MARK: - Lot

enum LotStatus: String, Codable {
    case draft, scheduled, live, ended, unsold, cancelled

    var label: String {
        switch self {
        case .draft: return "草稿"
        case .scheduled: return "预展中"
        case .live: return "竞拍中"
        case .ended: return "已结拍"
        case .unsold: return "流拍"
        case .cancelled: return "已撤拍"
        }
    }
}

struct MyBidStatus: Codable, Hashable {
    var hasBid: Bool = false
    var leading: Bool = false
    var maxAmount: Money = 0
}

struct Lot: Codable, Identifiable, Hashable {
    let id: Int64
    var sellerId: Int64
    var title: String
    var description: String
    var images: [String]
    var category: String
    var brand: String
    var scale: String
    var series: String
    var condition: String
    var boxStatus: String
    var location: String
    var startPrice: Money
    var depositAmount: Money
    var bidIncrement: Money
    var currentPrice: Money
    var currentBidderId: Int64?
    var bidCount: Int
    var startAt: Date
    var endAt: Date
    var durationSeconds: Int
    var antiSnipeSeconds: Int
    var extensionCount: Int
    var status: LotStatus
    var followCount: Int
    var viewCount: Int
    var winnerId: Int64?
    var orderId: Int64?
    var createdAt: Date

    var seller: User
    var currentBidder: User?
    var cover: String
    var displayPrice: Money
    var minNextBid: Money
    var isFollowing: Bool
    var myBid: MyBidStatus
    var recentBids: [Bid]?
    var hasReserve: Bool
    var reserveMet: Bool
    /// Monotonic bid sequence for WS / snapshot alignment (DES-v1.3-03-02).
    var seq: Int64? = nil
    var endAtVersion: Int? = nil
    /// DES-v1.3-03-05: new lot points at prior unsold/cancelled row.
    var relistedFromLotId: Int64? = nil
    /// Outbound link on the old lot after a successful relist.
    var relistedToLotId: Int64? = nil

    var isLive: Bool { status == .live }
    var isUpcoming: Bool { status == .scheduled }
    var isFinished: Bool { status == .ended || status == .unsold || status == .cancelled }
    var tags: [String] { [scale, brand, condition].filter { !$0.isEmpty } }
}

struct Bid: Codable, Identifiable, Hashable {
    let id: Int64
    let lotId: Int64
    let bidderId: Int64
    let amount: Money
    let createdAt: Date
    var leading: Bool
    var bidder: User?
    /// Lot-scoped monotonic seq (DES-v1.3-03-02); optional for legacy payloads.
    var seq: Int64? = nil
    var source: String? = nil

    var bidderName: String { bidder?.nickname ?? "出价者\(bidderId % 1000)" }
    var bidderAvatar: String { bidder?.avatar ?? "" }
}

// MARK: - Order

enum OrderStatus: String, Codable {
    case pendingPayment = "pending_payment"
    case paid, shipped, completed, settled, cancelled, refunded

    var label: String {
        switch self {
        case .pendingPayment: return "待付款"
        case .paid: return "待发货"
        case .shipped: return "待收货"
        case .completed, .settled: return "已完成"
        case .cancelled: return "已取消"
        case .refunded: return "已退款"
        }
    }

    var asCenterStatus: OrderCenterStatus {
        OrderCenterStatus(rawValue: rawValue) ?? .pendingPayment
    }
}

struct TimelineEvent: Codable, Hashable {
    let status: String
    let title: String
    let note: String?
    let at: Date
}

struct LotBrief: Codable, Hashable {
    let id: Int64
    let title: String
    let cover: String
    let scale: String
    let brand: String
}

struct Order: Codable, Identifiable, Hashable {
    let id: Int64
    let orderNo: String
    /// Optional for fixed / release orders (auction keeps lot id).
    var lotId: Int64?
    var listingId: Int64?
    var releaseId: Int64?
    var parentOrderId: Int64?
    let buyerId: Int64
    let sellerId: Int64
    /// Legacy hammer; prefer `amount` when present (DES-v1.3-07-01).
    let hammerPrice: Money
    var amount: Money?
    var shippingFee: Money?
    let buyerPremium: Money
    let buyerTotal: Money
    let sellerCommission: Money
    var platformFee: Money?
    let sellerNet: Money
    var depositApplied: Money = 0
    var amountDue: Money = 0
    var refundedAmount: Money = 0
    var status: OrderStatus
    var tradeType: OrderTradeType = .auction
    var afterSaleStatus: OrderAfterSaleStatus = .none
    var fundStatus: OrderFundStatus?
    var payDeadline: Date
    var shipDeadline: Date?
    var confirmDeadline: Date?
    var confirmDeadlineVersion: Int?
    var confirmPausedAt: Date?
    var payRemainSec: Int?
    var shipRemainSec: Int?
    var confirmRemainSec: Int?
    var serverTime: Date?
    var paidAt: Date?
    var shippedAt: Date?
    var completedAt: Date?
    /// Review window end (DES-v1.3-12-02 / D40). Prefer absolute + `server_time`.
    var reviewDeadline: Date?
    var reviewRemainDays: Int?
    var myReviewStatus: String?
    var myReviewPending: Bool?
    var address: [String: String]?
    var addressSnapshot: OrderAddressSnapshot?
    var itemSnapshot: OrderItemSnapshot?
    /// Detail / seller only — never relied on for list UI.
    var feeRuleSnapshot: OrderFeeRuleSnapshot?
    var shippingCarrier: String?
    var trackingNo: String?
    var shipmentNo: String?
    var shipmentMemberCount: Int?
    var evidenceReady: Bool?
    var insuredRequired: Bool?
    var insured: Bool?
    var insuredAmount: Money?
    var timeline: [TimelineEvent]
    let createdAt: Date
    var lot: LotBrief?
    var buyer: User
    var seller: User
    var role: String

    var isSeller: Bool { role == "seller" }
    var hasAddress: Bool {
        if let snap = addressSnapshot, snap.hasContent { return true }
        return !(address?["name"] ?? "").isEmpty
    }
    /// 成交金额：`amount` 优先，否则落槌价。
    var displayAmount: Money { amount ?? hammerPrice }
    /// 实际应付（押金抵扣后）；旧数据无字段时回退到 buyerTotal
    var payAmount: Money { amountDue > 0 || depositApplied > 0 ? amountDue : buyerTotal }
    var resolvedAddress: OrderAddressSnapshot? {
        addressSnapshot ?? OrderAddressSnapshot.fromLegacyMap(address)
    }
    var addressLine: String {
        if let snap = resolvedAddress { return snap.oneLine }
        guard let a = address else { return "" }
        return (a["province"] ?? "") + (a["city"] ?? "") + (a["district"] ?? "") + (a["detail"] ?? "")
    }
    var displayTitle: String {
        if let t = itemSnapshot?.title, !t.isEmpty { return t }
        return lot?.title ?? "商品"
    }
    var displayCover: String {
        itemSnapshot?.coverURL ?? lot?.cover ?? ""
    }
    var afterSaleBadge: OrderLogic.AfterSaleBadge {
        OrderLogic.afterSaleBadge(
            status: status.asCenterStatus,
            afterSaleStatus: afterSaleStatus,
            refundedAmount: refundedAmount
        )
    }
    var canEditAddress: Bool {
        OrderLogic.canEditAddress(status: status.asCenterStatus, isBuyer: !isSeller, tradeType: tradeType)
    }

    /// DES-v1.3-07-02 confirm pause / CTA state.
    var confirmPauseState: ConfirmPauseState {
        ConfirmPauseState(
            confirmDeadline: confirmDeadline,
            confirmDeadlineVersion: confirmDeadlineVersion,
            confirmPausedAt: confirmPausedAt,
            confirmRemainingSec: confirmRemainSec,
            afterSaleStatus: afterSaleStatus.rawValue,
            status: status.rawValue
        )
    }

    var needsInsurance: Bool {
        insuredRequired == true || ShipmentLogic.isInsuredRequired(amountFen: displayAmount)
    }

    var isMergedShipment: Bool {
        (shipmentMemberCount ?? 1) > 1
    }

    var mergeShipLabel: String? {
        guard isMergedShipment, let n = shipmentMemberCount else { return nil }
        return ShipmentLogic.mergeShipDisplayLabel(orderCount: n)
    }

    /// Pending review for current party (DES-v1.3-12-02).
    var isReviewPendingForMe: Bool {
        if let myReviewPending { return myReviewPending }
        if let s = ReviewStatus.normalize(myReviewStatus) { return s.isPending }
        if (status == .completed || status == .settled), reviewDeadline != nil {
            return myReviewStatus == nil
        }
        return false
    }

    var reviewPendingInfo: OrderReviewPendingInfo {
        OrderReviewPendingInfo(
            reviewDeadline: reviewDeadline,
            myReviewStatus: myReviewStatus,
            reviewRemainDays: reviewRemainDays,
            completedAt: completedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, orderNo, lotId, listingId, releaseId, parentOrderId
        case buyerId, sellerId, hammerPrice, amount, shippingFee
        case buyerPremium, buyerTotal, sellerCommission, platformFee, sellerNet
        case depositApplied, amountDue, refundedAmount, status
        case tradeType, type, afterSaleStatus, fundStatus
        case payDeadline, shipDeadline, confirmDeadline, confirmDeadlineVersion, confirmPausedAt
        case payRemainSec, shipRemainSec, confirmRemainSec, serverTime
        case paidAt, shippedAt, completedAt
        case reviewDeadline, reviewRemainDays, myReviewStatus, myReviewPending
        case address, addressSnapshot, itemSnapshot, feeRuleSnapshot
        case shippingCarrier, trackingNo, shipmentNo, shipmentMemberCount
        case evidenceReady, insuredRequired, insured, insuredAmount
        case timeline, createdAt
        case lot, buyer, seller, role
        case title, cover
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        orderNo = try c.decode(String.self, forKey: .orderNo)
        lotId = try c.decodeIfPresent(Int64.self, forKey: .lotId)
        listingId = try c.decodeIfPresent(Int64.self, forKey: .listingId)
        releaseId = try c.decodeIfPresent(Int64.self, forKey: .releaseId)
        parentOrderId = try c.decodeIfPresent(Int64.self, forKey: .parentOrderId)
        buyerId = try c.decodeIfPresent(Int64.self, forKey: .buyerId) ?? 0
        sellerId = try c.decodeIfPresent(Int64.self, forKey: .sellerId) ?? 0
        let hammer = try c.decodeIfPresent(Money.self, forKey: .hammerPrice) ?? 0
        amount = try c.decodeIfPresent(Money.self, forKey: .amount)
        hammerPrice = amount ?? hammer
        shippingFee = try c.decodeIfPresent(Money.self, forKey: .shippingFee)
        buyerPremium = try c.decodeIfPresent(Money.self, forKey: .buyerPremium) ?? 0
        buyerTotal = try c.decodeIfPresent(Money.self, forKey: .buyerTotal) ?? (amount ?? hammer)
        sellerCommission = try c.decodeIfPresent(Money.self, forKey: .sellerCommission) ?? 0
        platformFee = try c.decodeIfPresent(Money.self, forKey: .platformFee)
        sellerNet = try c.decodeIfPresent(Money.self, forKey: .sellerNet) ?? 0
        depositApplied = try c.decodeIfPresent(Money.self, forKey: .depositApplied) ?? 0
        amountDue = try c.decodeIfPresent(Money.self, forKey: .amountDue) ?? 0
        refundedAmount = try c.decodeIfPresent(Money.self, forKey: .refundedAmount) ?? 0
        let statusRaw = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending_payment"
        status = OrderStatus(rawValue: statusRaw) ?? .pendingPayment
        let tradeRaw = try c.decodeIfPresent(String.self, forKey: .tradeType)
            ?? c.decodeIfPresent(String.self, forKey: .type)
        tradeType = OrderTradeType(rawOrLegacy: tradeRaw)
        afterSaleStatus = OrderAfterSaleStatus(
            rawOrLegacy: try c.decodeIfPresent(String.self, forKey: .afterSaleStatus)
        )
        if let fundRaw = try c.decodeIfPresent(String.self, forKey: .fundStatus) {
            fundStatus = OrderFundStatus(rawValue: fundRaw)
        }
        payDeadline = try c.decodeIfPresent(Date.self, forKey: .payDeadline) ?? .distantPast
        shipDeadline = try c.decodeIfPresent(Date.self, forKey: .shipDeadline)
        confirmDeadline = try c.decodeIfPresent(Date.self, forKey: .confirmDeadline)
        confirmDeadlineVersion = try c.decodeIfPresent(Int.self, forKey: .confirmDeadlineVersion)
        confirmPausedAt = try c.decodeIfPresent(Date.self, forKey: .confirmPausedAt)
        payRemainSec = try c.decodeIfPresent(Int.self, forKey: .payRemainSec)
        shipRemainSec = try c.decodeIfPresent(Int.self, forKey: .shipRemainSec)
        confirmRemainSec = try c.decodeIfPresent(Int.self, forKey: .confirmRemainSec)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
        paidAt = try c.decodeIfPresent(Date.self, forKey: .paidAt)
        shippedAt = try c.decodeIfPresent(Date.self, forKey: .shippedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        reviewDeadline = try c.decodeIfPresent(Date.self, forKey: .reviewDeadline)
        reviewRemainDays = try c.decodeIfPresent(Int.self, forKey: .reviewRemainDays)
        myReviewStatus = try c.decodeIfPresent(String.self, forKey: .myReviewStatus)
        myReviewPending = try c.decodeIfPresent(Bool.self, forKey: .myReviewPending)
        address = try c.decodeIfPresent([String: String].self, forKey: .address)
        addressSnapshot = try c.decodeIfPresent(OrderAddressSnapshot.self, forKey: .addressSnapshot)
            ?? OrderAddressSnapshot.fromLegacyMap(address)
        if let snap = try c.decodeIfPresent(OrderItemSnapshot.self, forKey: .itemSnapshot) {
            itemSnapshot = snap
        } else {
            let listTitle = try c.decodeIfPresent(String.self, forKey: .title)
            let listCover = try c.decodeIfPresent(String.self, forKey: .cover)
            if listTitle != nil || listCover != nil {
                itemSnapshot = OrderItemSnapshot(title: listTitle, coverURL: listCover)
            } else {
                itemSnapshot = nil
            }
        }
        // Soft-fail fee snapshot so Int/String rule_version mismatches never blank the whole detail.
        feeRuleSnapshot = try? c.decode(OrderFeeRuleSnapshot.self, forKey: .feeRuleSnapshot)
        shippingCarrier = try c.decodeIfPresent(String.self, forKey: .shippingCarrier)
        trackingNo = try c.decodeIfPresent(String.self, forKey: .trackingNo)
        shipmentNo = try c.decodeIfPresent(String.self, forKey: .shipmentNo)
        shipmentMemberCount = try c.decodeIfPresent(Int.self, forKey: .shipmentMemberCount)
        evidenceReady = try c.decodeIfPresent(Bool.self, forKey: .evidenceReady)
        insuredRequired = try c.decodeIfPresent(Bool.self, forKey: .insuredRequired)
        insured = try c.decodeIfPresent(Bool.self, forKey: .insured)
        insuredAmount = try c.decodeIfPresent(Money.self, forKey: .insuredAmount)
        timeline = try c.decodeIfPresent([TimelineEvent].self, forKey: .timeline) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        lot = try c.decodeIfPresent(LotBrief.self, forKey: .lot)
        buyer = try c.decodeIfPresent(User.self, forKey: .buyer) ?? User.placeholder(id: buyerId)
        seller = try c.decodeIfPresent(User.self, forKey: .seller) ?? User.placeholder(id: sellerId)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "buyer"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(orderNo, forKey: .orderNo)
        try c.encodeIfPresent(lotId, forKey: .lotId)
        try c.encodeIfPresent(listingId, forKey: .listingId)
        try c.encodeIfPresent(releaseId, forKey: .releaseId)
        try c.encodeIfPresent(parentOrderId, forKey: .parentOrderId)
        try c.encode(buyerId, forKey: .buyerId)
        try c.encode(sellerId, forKey: .sellerId)
        try c.encode(hammerPrice, forKey: .hammerPrice)
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(shippingFee, forKey: .shippingFee)
        try c.encode(buyerPremium, forKey: .buyerPremium)
        try c.encode(buyerTotal, forKey: .buyerTotal)
        try c.encode(sellerCommission, forKey: .sellerCommission)
        try c.encodeIfPresent(platformFee, forKey: .platformFee)
        try c.encode(sellerNet, forKey: .sellerNet)
        try c.encode(depositApplied, forKey: .depositApplied)
        try c.encode(amountDue, forKey: .amountDue)
        try c.encode(refundedAmount, forKey: .refundedAmount)
        try c.encode(status, forKey: .status)
        try c.encode(tradeType.rawValue, forKey: .tradeType)
        try c.encode(afterSaleStatus.rawValue, forKey: .afterSaleStatus)
        try c.encodeIfPresent(fundStatus?.rawValue, forKey: .fundStatus)
        try c.encode(payDeadline, forKey: .payDeadline)
        try c.encodeIfPresent(shipDeadline, forKey: .shipDeadline)
        try c.encodeIfPresent(confirmDeadline, forKey: .confirmDeadline)
        try c.encodeIfPresent(confirmDeadlineVersion, forKey: .confirmDeadlineVersion)
        try c.encodeIfPresent(confirmPausedAt, forKey: .confirmPausedAt)
        try c.encodeIfPresent(payRemainSec, forKey: .payRemainSec)
        try c.encodeIfPresent(shipRemainSec, forKey: .shipRemainSec)
        try c.encodeIfPresent(confirmRemainSec, forKey: .confirmRemainSec)
        try c.encodeIfPresent(serverTime, forKey: .serverTime)
        try c.encodeIfPresent(paidAt, forKey: .paidAt)
        try c.encodeIfPresent(shippedAt, forKey: .shippedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(reviewDeadline, forKey: .reviewDeadline)
        try c.encodeIfPresent(reviewRemainDays, forKey: .reviewRemainDays)
        try c.encodeIfPresent(myReviewStatus, forKey: .myReviewStatus)
        try c.encodeIfPresent(myReviewPending, forKey: .myReviewPending)
        try c.encodeIfPresent(address, forKey: .address)
        try c.encodeIfPresent(addressSnapshot, forKey: .addressSnapshot)
        try c.encodeIfPresent(itemSnapshot, forKey: .itemSnapshot)
        try c.encodeIfPresent(feeRuleSnapshot, forKey: .feeRuleSnapshot)
        try c.encodeIfPresent(shippingCarrier, forKey: .shippingCarrier)
        try c.encodeIfPresent(trackingNo, forKey: .trackingNo)
        try c.encodeIfPresent(shipmentNo, forKey: .shipmentNo)
        try c.encodeIfPresent(shipmentMemberCount, forKey: .shipmentMemberCount)
        try c.encodeIfPresent(evidenceReady, forKey: .evidenceReady)
        try c.encodeIfPresent(insuredRequired, forKey: .insuredRequired)
        try c.encodeIfPresent(insured, forKey: .insured)
        try c.encodeIfPresent(insuredAmount, forKey: .insuredAmount)
        try c.encode(timeline, forKey: .timeline)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lot, forKey: .lot)
        try c.encode(buyer, forKey: .buyer)
        try c.encode(seller, forKey: .seller)
        try c.encode(role, forKey: .role)
    }
}

struct OrderDetail: Decodable {
    let order: Order
    let payments: [Payment]
    /// Two-phase refund progress (DES-v1.3-08-03); absent on older payloads.
    var refunds: [RefundProgress]
    var serverTime: Date?

    enum CodingKeys: String, CodingKey {
        case order, payments, refunds, serverTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        order = try c.decode(Order.self, forKey: .order)
        payments = try c.decodeIfPresent([Payment].self, forKey: .payments) ?? []
        refunds = try c.decodeIfPresent([RefundProgress].self, forKey: .refunds) ?? []
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime) ?? order.serverTime
    }
}

// MARK: - Payment

enum PaymentStatus: String, Codable { case created, paying, succeeded, failed, closed, refunded }

struct Payment: Codable, Identifiable, Hashable {
    let id: Int64
    let orderId: Int64
    let provider: String
    let outTradeNo: String
    let amount: Money
    var status: PaymentStatus
    var clientPayload: [String: AnyCodable]?
    var failReason: String?
    var paidAt: Date?
}

struct PaymentMethod: Codable, Identifiable, Hashable {
    var id: String { provider }
    let provider: String
    let name: String
    let description: String
    let icon: String
    let enabled: Bool
}

// MARK: - Commission / Wallet / Tax

struct FeeBreakdown: Codable, Hashable {
    let hammerPrice: Money
    let buyerPremium: Money
    let buyerTotal: Money
    let sellerCommission: Money
    let sellerNet: Money
    let ruleName: String
    let sellerRateBp: Int
    let buyerPremiumBp: Int

    var sellerRateText: String { String(format: "%.1f%%", Double(sellerRateBp) / 100) }
}

// Wallet / LedgerEntry / WithdrawalRequest → WalletModels.swift (DES-v1.3-08-03 / D31)

enum TaxpayerType: String, Codable, CaseIterable, Identifiable {
    case individual, soleProprietor = "sole_proprietor", enterprise
    var id: String { rawValue }
    var label: String {
        switch self {
        case .individual: return "自然人"
        case .soleProprietor: return "个体工商户"
        case .enterprise: return "企业"
        }
    }
}

struct TaxProfile: Codable, Hashable {
    let taxpayerType: TaxpayerType
    let realName: String
    let idType: String
    let idNumberMasked: String?
    let uscc: String?
    let taxRegion: String
    let bankName: String?
    let bankAccountMasked: String?
    let verifiedAt: Date?
}

struct TaxRecord: Codable, Identifiable, Hashable {
    let id: Int64
    let orderId: Int64
    let incomeType: String
    let grossIncome: Money
    let platformFee: Money
    let netIncome: Money
    let vatApplicable: Bool
    let withheldAmount: Money
    let period: String
    let quarter: String
    let settledAt: Date

    var incomeTypeLabel: String { incomeType == "business" ? "经营所得" : "财产转让所得" }
}

struct TaxReport: Codable, Identifiable, Hashable {
    let id: Int64
    let quarter: String
    let recordsCount: Int
    let totalIncome: Money
    let totalFee: Money
    let totalNet: Money
    let totalWithheld: Money
    let status: String
    let submissionRef: String?
    let submittedAt: Date?

    var statusLabel: String {
        switch status {
        case "draft": return "草稿"
        case "generated": return "已生成"
        case "submitted": return "已报送"
        case "accepted": return "已受理"
        case "rejected": return "被退回"
        default: return status
        }
    }
}

// MARK: - Chat

struct LotSummary: Codable, Hashable {
    let id: Int64
    let title: String
    let cover: String
    let currentPrice: Money
    let status: LotStatus
    let endAt: Date
}

struct Conversation: Codable, Identifiable, Hashable {
    let id: Int64
    /// Legacy lot-scoped id; 0 when subject is listing/order (DES-v1.3-11-02).
    let lotId: Int64
    /// `lot` / `listing` / `order` — backfilled from `lot_id` when absent.
    let subjectType: ConversationSubjectType?
    let subjectId: Int64?
    let buyerId: Int64
    let sellerId: Int64
    var lastMessage: String
    var lastMessageAt: Date?
    let peer: User
    let lot: LotSummary?
    var unread: Int
    var blockedByBuyer: Bool?
    var blockedBySeller: Bool?
    var offerId: Int64?

    init(
        id: Int64,
        lotId: Int64 = 0,
        subjectType: ConversationSubjectType? = nil,
        subjectId: Int64? = nil,
        buyerId: Int64,
        sellerId: Int64,
        lastMessage: String = "",
        lastMessageAt: Date? = nil,
        peer: User,
        lot: LotSummary? = nil,
        unread: Int = 0,
        blockedByBuyer: Bool? = nil,
        blockedBySeller: Bool? = nil,
        offerId: Int64? = nil
    ) {
        self.id = id
        self.lotId = lotId
        let resolvedType = subjectType ?? (lotId > 0 ? .lot : nil)
        self.subjectType = resolvedType
        self.subjectId = subjectId ?? (resolvedType == .lot && lotId > 0 ? lotId : nil)
        self.buyerId = buyerId
        self.sellerId = sellerId
        self.lastMessage = lastMessage
        self.lastMessageAt = lastMessageAt
        self.peer = peer
        self.lot = lot
        self.unread = unread
        self.blockedByBuyer = blockedByBuyer
        self.blockedBySeller = blockedBySeller
        self.offerId = offerId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        let decodedLotId = try c.decodeIfPresent(Int64.self, forKey: .lotId) ?? 0
        lotId = decodedLotId
        let rawSubject = try c.decodeIfPresent(String.self, forKey: .subjectType)
        let parsed = ConversationSubjectType.normalize(rawSubject)
        subjectType = parsed ?? (decodedLotId > 0 ? .lot : nil)
        subjectId = try c.decodeIfPresent(Int64.self, forKey: .subjectId)
            ?? (subjectType == .lot && decodedLotId > 0 ? decodedLotId : nil)
        buyerId = try c.decode(Int64.self, forKey: .buyerId)
        sellerId = try c.decode(Int64.self, forKey: .sellerId)
        lastMessage = try c.decodeIfPresent(String.self, forKey: .lastMessage) ?? ""
        lastMessageAt = try c.decodeIfPresent(Date.self, forKey: .lastMessageAt)
        peer = try c.decode(User.self, forKey: .peer)
        lot = try c.decodeIfPresent(LotSummary.self, forKey: .lot)
        unread = try c.decodeIfPresent(Int.self, forKey: .unread) ?? 0
        blockedByBuyer = try c.decodeIfPresent(Bool.self, forKey: .blockedByBuyer)
        blockedBySeller = try c.decodeIfPresent(Bool.self, forKey: .blockedBySeller)
        offerId = try c.decodeIfPresent(Int64.self, forKey: .offerId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(lotId, forKey: .lotId)
        try c.encodeIfPresent(subjectType?.rawValue, forKey: .subjectType)
        try c.encodeIfPresent(subjectId, forKey: .subjectId)
        try c.encode(buyerId, forKey: .buyerId)
        try c.encode(sellerId, forKey: .sellerId)
        try c.encode(lastMessage, forKey: .lastMessage)
        try c.encodeIfPresent(lastMessageAt, forKey: .lastMessageAt)
        try c.encode(peer, forKey: .peer)
        try c.encodeIfPresent(lot, forKey: .lot)
        try c.encode(unread, forKey: .unread)
        try c.encodeIfPresent(blockedByBuyer, forKey: .blockedByBuyer)
        try c.encodeIfPresent(blockedBySeller, forKey: .blockedBySeller)
        try c.encodeIfPresent(offerId, forKey: .offerId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, lotId, subjectType, subjectId, buyerId, sellerId
        case lastMessage, lastMessageAt, peer, lot, unread
        case blockedByBuyer, blockedBySeller, offerId
    }

    /// Resolved subject for banners / open Conversation (DES-v1.3-11-02).
    var resolvedSubjectType: ConversationSubjectType {
        subjectType ?? (lotId > 0 ? .lot : .listing)
    }

    var resolvedSubjectId: Int64 {
        subjectId ?? lotId
    }
}

/// Wire `messages.type` (DES-v1.3-11-02). Legacy `lot_card` decodes as `listing_card`.
enum MessageType: String, Codable {
    case text
    case image
    case listingCard = "listing_card"
    case orderCard = "order_card"
    case offerCard = "offer_card"
    case system
    case riskBanner = "risk_banner"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let kind = ChatMessageKind.normalize(raw) {
            self.init(kind: kind)
        } else {
            self = .text
        }
    }

    init(kind: ChatMessageKind) {
        switch kind {
        case .text: self = .text
        case .image: self = .image
        case .listingCard: self = .listingCard
        case .orderCard: self = .orderCard
        case .offerCard: self = .offerCard
        case .system: self = .system
        case .riskBanner: self = .riskBanner
        }
    }

    /// Convenience for WS / raw strings.
    init?(rawValueLegacy raw: String) {
        guard let kind = ChatMessageKind.normalize(raw) else { return nil }
        self.init(kind: kind)
    }

    var chatKind: ChatMessageKind {
        switch self {
        case .text: return .text
        case .image: return .image
        case .listingCard: return .listingCard
        case .orderCard: return .orderCard
        case .offerCard: return .offerCard
        case .system: return .system
        case .riskBanner: return .riskBanner
        }
    }

    /// Lexicon whitelist (DES-v1.3-10-01 T-07 / §5.7 + 11-02).
    var skipsRiskLexicon: Bool { chatKind.skipsRiskLexicon }
}

struct Message: Codable, Identifiable, Hashable {
    let id: Int64
    let conversationId: Int64
    let senderId: Int64
    let type: MessageType
    let content: String
    let payload: [String: AnyCodable]?
    let createdAt: Date
    /// Nested `risk` envelope from send / list (DES-v1.3-10-01 §6).
    let risk: MessageRiskInfo?
    /// Audit-only blocked row (sender may see intercept UX; peer never lists it).
    let blocked: Bool?
    let offerId: Int64?

    init(
        id: Int64,
        conversationId: Int64,
        senderId: Int64,
        type: MessageType,
        content: String,
        payload: [String: AnyCodable]? = nil,
        createdAt: Date,
        risk: MessageRiskInfo? = nil,
        blocked: Bool? = nil,
        offerId: Int64? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.type = type
        self.content = content
        self.payload = payload
        self.createdAt = createdAt
        self.risk = risk
        self.blocked = blocked
        self.offerId = offerId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        conversationId = try c.decode(Int64.self, forKey: .conversationId)
        senderId = try c.decode(Int64.self, forKey: .senderId)
        type = try c.decode(MessageType.self, forKey: .type)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        payload = try c.decodeIfPresent([String: AnyCodable].self, forKey: .payload)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        risk = try c.decodeIfPresent(MessageRiskInfo.self, forKey: .risk)
        blocked = try c.decodeIfPresent(Bool.self, forKey: .blocked)
        offerId = try c.decodeIfPresent(Int64.self, forKey: .offerId)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(conversationId, forKey: .conversationId)
        try c.encode(senderId, forKey: .senderId)
        try c.encode(type, forKey: .type)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(payload, forKey: .payload)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(risk, forKey: .risk)
        try c.encodeIfPresent(blocked, forKey: .blocked)
        try c.encodeIfPresent(offerId, forKey: .offerId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, conversationId, senderId, type, content, payload, createdAt, risk, blocked, offerId
    }

    var effectiveRiskAction: RiskAction {
        if let risk { return risk.action }
        if blocked == true { return .block }
        return .none
    }
}

// MARK: - Meta

struct SortOption: Codable, Hashable, Identifiable {
    var id: String { key }
    let key: String
    let name: String
}

struct Filters: Codable {
    let categories: [String]
    let brands: [String]
    let scales: [String]
    let series: [String]
    let conditions: [String]
    let boxStatus: [String]
    let durations: [Int]
    let sorts: [SortOption]
    let hotKeywords: [String]
    /// HOME-07: publicly enabled scale ratios; falls back to `scales` when absent.
    let enabledScales: [String]?
    let scaleVersion: Int64?

    static let empty = Filters(
        categories: [], brands: [], scales: [], series: [], conditions: [], boxStatus: [],
        durations: [], sorts: [], hotKeywords: [], enabledScales: nil, scaleVersion: nil
    )

    var effectiveScales: [String] {
        if let enabledScales, !enabledScales.isEmpty { return enabledScales }
        return scales
    }
}

// MARK: - AnyCodable (for free-form payloads)

struct AnyCodable: Codable, Hashable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int64.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([AnyCodable].self) { value = a.map(\.value) }
        else if let o = try? c.decode([String: AnyCodable].self) { value = o.mapValues(\.value) }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let b as Bool: try c.encode(b)
        case let i as Int64: try c.encode(i)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        default: try c.encodeNil()
        }
    }

    static func == (l: AnyCodable, r: AnyCodable) -> Bool { "\(l.value)" == "\(r.value)" }
    func hash(into h: inout Hasher) { h.combine("\(value)") }

    var string: String? { value as? String }
    var int64: Int64? { (value as? Int64) ?? (value as? Int).map(Int64.init) ?? (value as? Double).map(Int64.init) }
    var bool: Bool? { value as? Bool }
}
