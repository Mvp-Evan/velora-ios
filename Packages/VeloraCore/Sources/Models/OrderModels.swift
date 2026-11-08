import Foundation

// MARK: - Unified order center + snapshots (DES-v1.3-07-01 ORD-01/02/03 / D27)

/// Product defaults (design §5 / §6 / §13). Hot-config on server; client mirrors for UX.
public enum OrderCenterConfigDefaults {
    public static let payWindowAuctionSec = 86_400
    public static let payWindowFixedSec = 900
    public static let payWindowOfferSec = 7_200
    public static let payWindowSpotSec = 900
    public static let payWindowLotterySec = 7_200
    public static let payWindowPresaleDepositSec = 900
    public static let addressMax = 20
    public static let listPageSizeDefault = 20
    public static let listPageSizeMax = 50
    public static let idempotencyTTLH = 72
    public static let shipHoursAuctionFixed = 72
    public static let shipHoursSpotLottery = 48
    /// Emphasize countdown when remain < 1h (design §9).
    public static let countdownUrgentSec = 3_600
    public static let meBuyerEntryKey = "bought"
    public static let meSellerEntryKey = "sold"
}

// MARK: - Trade type (six kinds)

/// `orders.trade_type` (design §3). Legacy `type=spot_release` maps to `.spot`.
public enum OrderTradeType: String, Codable, Sendable, CaseIterable, Equatable {
    case auction
    case fixed
    case spot
    case lottery
    case presaleDeposit = "presale_deposit"
    case presaleBalance = "presale_balance"

    /// Normalize API / legacy `type` values; unknown → auction (design §13 readonly fallback).
    public init(rawOrLegacy value: String?) {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "", "auction": self = .auction
        case "fixed": self = .fixed
        case "spot", "spot_release": self = .spot
        case "lottery": self = .lottery
        case "presale_deposit": self = .presaleDeposit
        case "presale_balance": self = .presaleBalance
        default:
            if let known = OrderTradeType(rawValue: raw) {
                self = known
            } else {
                self = .auction
            }
        }
    }

    public var displayLabel: String {
        switch self {
        case .auction: return "拍卖"
        case .fixed: return "一口价"
        case .spot: return "现货发售"
        case .lottery: return "抽签"
        case .presaleDeposit: return "预售定金"
        case .presaleBalance: return "预售尾款"
        }
    }

    public var defaultPayWindowSec: Int {
        switch self {
        case .auction: return OrderCenterConfigDefaults.payWindowAuctionSec
        case .fixed: return OrderCenterConfigDefaults.payWindowFixedSec
        case .spot: return OrderCenterConfigDefaults.payWindowSpotSec
        case .lottery: return OrderCenterConfigDefaults.payWindowLotterySec
        case .presaleDeposit: return OrderCenterConfigDefaults.payWindowPresaleDepositSec
        case .presaleBalance: return 0 // balance window owned by REL
        }
    }

    /// Presale deposit has no physical ship deadline (design §5.7).
    public var hasShipDeadline: Bool { self != .presaleDeposit }

    public var isPresale: Bool {
        self == .presaleDeposit || self == .presaleBalance
    }
}

// MARK: - Main status machine (7.2)

/// Main order status. `settled` is post-`completed` bookkeeping (design §3 / §4).
public enum OrderCenterStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pendingPayment = "pending_payment"
    case paid
    case shipped
    case completed
    case settled
    case cancelled
    case refunded

    public var displayLabel: String {
        switch self {
        case .pendingPayment: return "待付款"
        case .paid: return "待发货"
        case .shipped: return "待收货"
        case .completed: return "已完成"
        case .settled: return "已结算"
        case .cancelled: return "已取消"
        case .refunded: return "已退款"
        }
    }

    public var isTerminal: Bool {
        self == .cancelled || self == .refunded || self == .settled
    }

    /// Buyer-facing list label: settled shows as 已完成.
    public var listLabel: String {
        switch self {
        case .settled: return OrderCenterStatus.completed.displayLabel
        default: return displayLabel
        }
    }
}

// MARK: - After-sale / fund (parallel to main status)

public enum OrderAfterSaleStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case none
    case processing
    case closed

    public init(rawOrLegacy value: String?) {
        let raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.isEmpty { self = .none; return }
        self = OrderAfterSaleStatus(rawValue: raw) ?? .none
    }
}

public enum OrderFundStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case unpaid
    case held
    case settling
    case settled
    case refunding
    case refunded
    case depositHeld = "deposit_held"
    case balanceHeld = "balance_held"

    /// Buyer-facing fund copy (design §5.7). Never use as main status.
    public var buyerDisplayLabel: String {
        switch self {
        case .unpaid: return "待支付"
        case .held, .depositHeld, .balanceHeld: return "已托管"
        case .settling: return "结算中"
        case .settled: return "已到账"
        case .refunding: return "退款中"
        case .refunded: return "已退款"
        }
    }

    /// Seller may see settled; buyer should not be shown 「已到账」 as order status.
    public var sellerDisplayLabel: String { buyerDisplayLabel }
}

// MARK: - Error codes (design §5.10)

public enum OrderCenterErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case missingIdempotencyKey = "missing_idempotency_key"
    case idempotencyConflict = "idempotency_conflict"
    case realNameRequired = "real_name_required"
    case purchaseForbidden = "purchase_forbidden"
    case accountFrozen = "account_frozen"
    case selfTradeForbidden = "self_trade_forbidden"
    case subMerchantRequired = "sub_merchant_required"
    case priceLocked = "price_locked"
    case addressLocked = "address_locked"
    case addressRequired = "address_required"
    case addressLimit = "address_limit"
    case addressInUse = "address_in_use"
    case invalidOrderTransition = "invalid_order_transition"
    case queryTooBroad = "query_too_broad"
    case feeRuleMissing = "fee_rule_missing"
    case forbidden = "forbidden"
    case featureDisabled = "feature_disabled"

    public var fallbackMessage: String {
        switch self {
        case .missingIdempotencyKey: return "请重试"
        case .idempotencyConflict: return "请求冲突，请稍后重试"
        case .realNameRequired: return "请先完成实名认证"
        case .purchaseForbidden: return "当前账号暂不可购买"
        case .accountFrozen: return "账号已冻结"
        case .selfTradeForbidden: return "不可自买自卖"
        case .subMerchantRequired: return "卖家尚未完成进件"
        case .priceLocked: return "成交价已锁定"
        case .addressLocked: return "发货后不可修改地址"
        case .addressRequired: return "请先填写收货地址"
        case .addressLimit: return "地址簿最多 \(OrderCenterConfigDefaults.addressMax) 条"
        case .addressInUse: return "该地址仍被未发货订单引用"
        case .invalidOrderTransition: return "订单状态不可变更"
        case .queryTooBroad: return "请缩小查询条件"
        case .feeRuleMissing: return "费率规则缺失"
        case .forbidden: return "无权查看该订单"
        case .featureDisabled: return "功能维护中"
        }
    }
}

// MARK: - UX copy (design §9)

public enum OrderCenterCopy {
    public static let centerTitle = "订单中心"
    public static let buyerTitle = "我买到的"
    public static let sellerTitle = "我卖出的"
    public static let emptyTitle = "还没有订单"
    public static let emptyHintBuyer = "去购买心仪的宝贝"
    public static let emptyHintSeller = "成交后订单会出现在这里"
    public static let emptyAction = "去购买"
    public static let afterSaleBadge = "售后中"
    public static let afterSaleProcessing = "售后处理中"
    public static let partialRefundBadge = "已部分退"
    public static let serverTimeHint = "以服务器时间为准"
    public static let needAddressBanner = "请填写收货地址"
    public static let sellerAwaitingAddress = "待买家补地址"
    public static let staleCacheHint = "可能不是最新"
    public static let priceLocked = "成交价已锁定，如需协商请走售后"
    public static let addressLocked = "发货后不可修改地址"
    public static let depositSeparate = "保证金另计，货款全额"
}

// MARK: - Center tabs (buyer / seller share filter set per App deliverable)

public enum OrderCenterTab: String, Codable, Sendable, CaseIterable, Equatable {
    case all
    case pendingPayment = "pending_payment"
    case pendingShip = "pending_ship"
    case pendingReceive = "pending_receive"
    case pendingReview = "pending_review"
    case afterSale = "after_sale"

    public var title: String {
        switch self {
        case .all: return "全部"
        case .pendingPayment: return "待付款"
        case .pendingShip: return "待发货"
        case .pendingReceive: return "待收货"
        case .pendingReview: return "待评价"
        case .afterSale: return "退款售后"
        }
    }

    /// Query params for `GET /me/orders` (design §5.6 / §6).
    public var listQuery: OrderListQuery {
        switch self {
        case .all:
            return OrderListQuery()
        case .pendingPayment:
            return OrderListQuery(status: OrderCenterStatus.pendingPayment.rawValue)
        case .pendingShip:
            return OrderListQuery(status: OrderCenterStatus.paid.rawValue)
        case .pendingReceive:
            return OrderListQuery(status: OrderCenterStatus.shipped.rawValue)
        case .pendingReview:
            return OrderListQuery(status: OrderCenterStatus.completed.rawValue)
        case .afterSale:
            return OrderListQuery(tab: OrderCenterTab.afterSale.rawValue)
        }
    }

    public static func from(initialStatus: String?) -> OrderCenterTab {
        switch (initialStatus ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
        case "", "all": return .all
        case "pending_payment": return .pendingPayment
        case "paid", "pending_ship": return .pendingShip
        case "shipped", "pending_receive": return .pendingReceive
        case "completed", "pending_review", "settled": return .pendingReview
        case "after_sale", "refunded", "refund": return .afterSale
        default: return .all
        }
    }
}

public struct OrderListQuery: Equatable, Sendable {
    public var role: String?
    public var status: String?
    public var tradeType: String?
    public var afterSaleStatus: String?
    public var tab: String?
    public var page: Int
    public var pageSize: Int

    public init(
        role: String? = nil,
        status: String? = nil,
        tradeType: String? = nil,
        afterSaleStatus: String? = nil,
        tab: String? = nil,
        page: Int = 1,
        pageSize: Int = OrderCenterConfigDefaults.listPageSizeDefault
    ) {
        self.role = role
        self.status = status
        self.tradeType = tradeType
        self.afterSaleStatus = afterSaleStatus
        self.tab = tab
        self.page = max(1, page)
        self.pageSize = min(
            max(pageSize, 1),
            OrderCenterConfigDefaults.listPageSizeMax
        )
    }

    /// Flatten for API client query dict (nil values omitted by client).
    public var asQueryItems: [String: String?] {
        [
            "role": role,
            "status": status,
            "trade_type": tradeType,
            "after_sale_status": afterSaleStatus,
            "tab": tab,
            "page": "\(page)",
            "page_size": "\(pageSize)",
        ]
    }
}

// MARK: - Snapshots

/// `item_snapshot` (design §3). List may carry title/cover scalars only.
public struct OrderItemSnapshot: Codable, Equatable, Sendable, Hashable {
    public let title: String?
    public let condition: String?
    public let defectSummary: String?
    public let coverURL: String?
    public let category: String?
    public let brand: String?
    public let scale: String?
    public let stockNote: String?

    public init(
        title: String? = nil,
        condition: String? = nil,
        defectSummary: String? = nil,
        coverURL: String? = nil,
        category: String? = nil,
        brand: String? = nil,
        scale: String? = nil,
        stockNote: String? = nil
    ) {
        self.title = title
        self.condition = condition
        self.defectSummary = defectSummary
        self.coverURL = coverURL
        self.category = category
        self.brand = brand
        self.scale = scale
        self.stockNote = stockNote
    }

    enum CodingKeys: String, CodingKey {
        case title, condition, defectSummary, coverURL, category, brand, scale, stockNote
        case cover, coverUrl, mainImage, image
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        condition = try c.decodeIfPresent(String.self, forKey: .condition)
        defectSummary = try c.decodeIfPresent(String.self, forKey: .defectSummary)
        let coverA = try c.decodeIfPresent(String.self, forKey: .coverURL)
        let coverB = try c.decodeIfPresent(String.self, forKey: .coverUrl)
        let coverC = try c.decodeIfPresent(String.self, forKey: .cover)
        let coverD = try c.decodeIfPresent(String.self, forKey: .mainImage)
        let coverE = try c.decodeIfPresent(String.self, forKey: .image)
        coverURL = coverA ?? coverB ?? coverC ?? coverD ?? coverE
        category = try c.decodeIfPresent(String.self, forKey: .category)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        scale = try c.decodeIfPresent(String.self, forKey: .scale)
        stockNote = try c.decodeIfPresent(String.self, forKey: .stockNote)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(condition, forKey: .condition)
        try c.encodeIfPresent(defectSummary, forKey: .defectSummary)
        try c.encodeIfPresent(coverURL, forKey: .coverURL)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(brand, forKey: .brand)
        try c.encodeIfPresent(scale, forKey: .scale)
        try c.encodeIfPresent(stockNote, forKey: .stockNote)
    }
}

/// `fee_rule_snapshot` — detail / seller only; **forbidden on list** (design §5.6 / §12 / DES-v1.3-08-04).
public struct OrderFeeRuleSnapshot: Codable, Equatable, Sendable, Hashable {
    public let sellerType: String?
    public let tradeType: String?
    public let category: String?
    public let campaignId: String?
    public let rateBp: Int?
    public let tier: String?
    /// `monthly_gmv` for proxy whole-order tier (FIN-01 / 5.8); strip for buyer.
    public let tierBasis: String?
    public let gmvLastMonth: Int64?
    public let channelFeeBearer: String?
    public let channelFeeBp: Int?
    public let ruleId: String?
    public let ruleVersion: String?
    /// Internal ranking — strip for buyer detail (design §6).
    public let priority: Int?

    public init(
        sellerType: String? = nil,
        tradeType: String? = nil,
        category: String? = nil,
        campaignId: String? = nil,
        rateBp: Int? = nil,
        tier: String? = nil,
        tierBasis: String? = nil,
        gmvLastMonth: Int64? = nil,
        channelFeeBearer: String? = nil,
        channelFeeBp: Int? = nil,
        ruleId: String? = nil,
        ruleVersion: String? = nil,
        priority: Int? = nil
    ) {
        self.sellerType = sellerType
        self.tradeType = tradeType
        self.category = category
        self.campaignId = campaignId
        self.rateBp = rateBp
        self.tier = tier
        self.tierBasis = tierBasis
        self.gmvLastMonth = gmvLastMonth
        self.channelFeeBearer = channelFeeBearer
        self.channelFeeBp = channelFeeBp
        self.ruleId = ruleId
        self.ruleVersion = ruleVersion
        self.priority = priority
    }

    /// Buyer-facing detail: strip internal `priority` / `rule_id` / tier basis (design §6 / FIN-01).
    public func strippedForBuyer() -> OrderFeeRuleSnapshot {
        OrderFeeRuleSnapshot(
            sellerType: sellerType,
            tradeType: tradeType,
            category: category,
            campaignId: campaignId,
            rateBp: rateBp,
            tier: tier,
            tierBasis: nil,
            gmvLastMonth: nil,
            channelFeeBearer: channelFeeBearer,
            channelFeeBp: channelFeeBp,
            ruleId: nil,
            ruleVersion: ruleVersion,
            priority: nil
        )
    }
}

/// `address_snapshot` — masked display fields (design §3 / §5.3).
public struct OrderAddressSnapshot: Codable, Equatable, Sendable, Hashable {
    public let name: String?
    public let phone: String?
    public let province: String?
    public let city: String?
    public let district: String?
    public let detail: String?
    public let addressHash: String?

    public init(
        name: String? = nil,
        phone: String? = nil,
        province: String? = nil,
        city: String? = nil,
        district: String? = nil,
        detail: String? = nil,
        addressHash: String? = nil
    ) {
        self.name = name
        self.phone = phone
        self.province = province
        self.city = city
        self.district = district
        self.detail = detail
        self.addressHash = addressHash
    }

    public var hasContent: Bool {
        !(name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var oneLine: String {
        [province, city, district, detail]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined()
    }

    /// Decode from either structured snapshot or legacy flat address map.
    public static func fromLegacyMap(_ map: [String: String]?) -> OrderAddressSnapshot? {
        guard let map else { return nil }
        let snap = OrderAddressSnapshot(
            name: map["name"],
            phone: map["phone"],
            province: map["province"],
            city: map["city"],
            district: map["district"],
            detail: map["detail"],
            addressHash: map["address_hash"] ?? map["addressHash"]
        )
        return snap.hasContent || !(snap.oneLine.isEmpty) ? snap : nil
    }
}

// MARK: - List card (whitelist — no fee internals)

/// List card field whitelist (design §5.6). Intentionally omits `fee_rule_snapshot`.
public struct OrderListCard: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let orderNo: String
    public let tradeType: OrderTradeType
    public let coverURL: String?
    public let title: String?
    public let amount: Int64
    public let status: OrderCenterStatus
    public let afterSaleStatus: OrderAfterSaleStatus
    public let payRemainSec: Int?
    public let shipRemainSec: Int?
    public let confirmRemainSec: Int?
    public let serverTime: Date?
    public let refundedAmount: Int64?
    public let role: String?

    public init(
        id: Int64,
        orderNo: String,
        tradeType: OrderTradeType = .auction,
        coverURL: String? = nil,
        title: String? = nil,
        amount: Int64 = 0,
        status: OrderCenterStatus = .pendingPayment,
        afterSaleStatus: OrderAfterSaleStatus = .none,
        payRemainSec: Int? = nil,
        shipRemainSec: Int? = nil,
        confirmRemainSec: Int? = nil,
        serverTime: Date? = nil,
        refundedAmount: Int64? = nil,
        role: String? = nil
    ) {
        self.id = id
        self.orderNo = orderNo
        self.tradeType = tradeType
        self.coverURL = coverURL
        self.title = title
        self.amount = amount
        self.status = status
        self.afterSaleStatus = afterSaleStatus
        self.payRemainSec = payRemainSec
        self.shipRemainSec = shipRemainSec
        self.confirmRemainSec = confirmRemainSec
        self.serverTime = serverTime
        self.refundedAmount = refundedAmount
        self.role = role
    }

    enum CodingKeys: String, CodingKey {
        case id, orderNo, tradeType, type, coverURL, title, amount, status
        case afterSaleStatus, payRemainSec, shipRemainSec, confirmRemainSec
        case serverTime, refundedAmount, role
        case hammerPrice, itemSnapshot, cover, lot
    }

    private struct LotCoverTitle: Decodable {
        let title: String?
        let cover: String?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        orderNo = try c.decode(String.self, forKey: .orderNo)
        let tradeRaw = try c.decodeIfPresent(String.self, forKey: .tradeType)
            ?? c.decodeIfPresent(String.self, forKey: .type)
        tradeType = OrderTradeType(rawOrLegacy: tradeRaw)
        let decodedTitle = try c.decodeIfPresent(String.self, forKey: .title)
        let decodedCover = try c.decodeIfPresent(String.self, forKey: .coverURL)
        let decodedCoverAlt = try c.decodeIfPresent(String.self, forKey: .cover)
        if let snap = try c.decodeIfPresent(OrderItemSnapshot.self, forKey: .itemSnapshot) {
            title = snap.title ?? decodedTitle
            coverURL = snap.coverURL ?? decodedCover ?? decodedCoverAlt
        } else if let lot = try c.decodeIfPresent(LotCoverTitle.self, forKey: .lot) {
            title = lot.title ?? decodedTitle
            coverURL = lot.cover ?? decodedCover ?? decodedCoverAlt
        } else {
            title = decodedTitle
            coverURL = decodedCover ?? decodedCoverAlt
        }
        let decodedAmount = try c.decodeIfPresent(Int64.self, forKey: .amount)
        let decodedHammer = try c.decodeIfPresent(Int64.self, forKey: .hammerPrice)
        amount = decodedAmount ?? decodedHammer ?? 0
        let statusRaw = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending_payment"
        status = OrderCenterStatus(rawValue: statusRaw) ?? .pendingPayment
        afterSaleStatus = OrderAfterSaleStatus(
            rawOrLegacy: try c.decodeIfPresent(String.self, forKey: .afterSaleStatus)
        )
        payRemainSec = try c.decodeIfPresent(Int.self, forKey: .payRemainSec)
        shipRemainSec = try c.decodeIfPresent(Int.self, forKey: .shipRemainSec)
        confirmRemainSec = try c.decodeIfPresent(Int.self, forKey: .confirmRemainSec)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
        refundedAmount = try c.decodeIfPresent(Int64.self, forKey: .refundedAmount)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        // Explicitly ignore fee_rule_snapshot / address / PII if present in payload.
        _ = c.allKeys
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(orderNo, forKey: .orderNo)
        try c.encode(tradeType.rawValue, forKey: .tradeType)
        try c.encodeIfPresent(coverURL, forKey: .coverURL)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(amount, forKey: .amount)
        try c.encode(status.rawValue, forKey: .status)
        try c.encode(afterSaleStatus.rawValue, forKey: .afterSaleStatus)
        try c.encodeIfPresent(payRemainSec, forKey: .payRemainSec)
        try c.encodeIfPresent(shipRemainSec, forKey: .shipRemainSec)
        try c.encodeIfPresent(confirmRemainSec, forKey: .confirmRemainSec)
        try c.encodeIfPresent(serverTime, forKey: .serverTime)
        try c.encodeIfPresent(refundedAmount, forKey: .refundedAmount)
        try c.encodeIfPresent(role, forKey: .role)
    }
}

// MARK: - Detail payload helpers

public struct OrderDetailServerClock: Equatable, Sendable {
    public let serverTime: Date?
    public let fetchedAtLocal: Date

    public init(serverTime: Date?, fetchedAtLocal: Date = Date()) {
        self.serverTime = serverTime
        self.fetchedAtLocal = fetchedAtLocal
    }
}

// MARK: - Logic

public enum OrderLogic {
    // MARK: Status machine

    /// Legal main-status transitions (design §4). Terminal states have no outbound edges.
    public static func canTransition(from: OrderCenterStatus, to: OrderCenterStatus) -> Bool {
        if from == to { return true } // re-entry / idempotent
        if from.isTerminal { return false }
        switch (from, to) {
        case (.pendingPayment, .paid),
             (.pendingPayment, .cancelled),
             (.pendingPayment, .refunded):
            return true
        case (.paid, .shipped),
             (.paid, .cancelled),
             (.paid, .refunded):
            return true
        case (.shipped, .completed),
             (.shipped, .refunded):
            return true
        case (.completed, .settled),
             (.completed, .refunded):
            return true
        default:
            return false
        }
    }

    public static func assertTransition(from: OrderCenterStatus, to: OrderCenterStatus) -> OrderCenterErrorCode? {
        canTransition(from: from, to: to) ? nil : .invalidOrderTransition
    }

    // MARK: Address

    /// ORD-03: buyer may edit address while `pending_payment` or `paid` (until shipped).
    public static func canEditAddress(
        status: OrderCenterStatus,
        isBuyer: Bool,
        tradeType: OrderTradeType = .auction
    ) -> Bool {
        guard isBuyer else { return false }
        // Presale deposit may be address-empty; still allow update before ship path.
        switch status {
        case .pendingPayment, .paid:
            return true
        default:
            return false
        }
    }

    public static func addressEditBlockedReason(
        status: OrderCenterStatus,
        isBuyer: Bool
    ) -> OrderCenterErrorCode? {
        guard isBuyer else { return .forbidden }
        if canEditAddress(status: status, isBuyer: isBuyer) { return nil }
        return .addressLocked
    }

    public static func isAddressBookFull(count: Int, max: Int = OrderCenterConfigDefaults.addressMax) -> Bool {
        count >= max
    }

    // MARK: After-sale badge (design §5.4 / §9)

    public enum AfterSaleBadge: Equatable, Sendable {
        case none
        case processing
        case partialRefund
        case refunded

        public var label: String? {
            switch self {
            case .none: return nil
            case .processing: return OrderCenterCopy.afterSaleBadge
            case .partialRefund: return OrderCenterCopy.partialRefundBadge
            case .refunded: return OrderCenterStatus.refunded.displayLabel
            }
        }
    }

    public static func afterSaleBadge(
        status: OrderCenterStatus,
        afterSaleStatus: OrderAfterSaleStatus,
        refundedAmount: Int64 = 0
    ) -> AfterSaleBadge {
        if status == .refunded { return .refunded }
        if afterSaleStatus == .processing { return .processing }
        if refundedAmount > 0 { return .partialRefund }
        return .none
    }

    /// After-sale tab membership (design §5.6).
    public static func matchesAfterSaleTab(
        status: OrderCenterStatus,
        afterSaleStatus: OrderAfterSaleStatus
    ) -> Bool {
        afterSaleStatus == .processing || status == .refunded
    }

    // MARK: Countdown / server_time (design §5.8 / NFR-03)

    /// `deadline − serverNow` floored; device clock ignored.
    public static func remainSeconds(deadline: Date?, serverNow: Date) -> Int {
        guard let deadline else { return 0 }
        return max(0, Int(deadline.timeIntervalSince(serverNow).rounded(.down)))
    }

    /// Adjust server-provided remain by local elapsed since the response was received.
    public static func remainSeconds(
        serverRemainSec: Int?,
        fetchedAtLocal: Date,
        nowLocal: Date = Date()
    ) -> Int {
        guard let serverRemainSec else { return 0 }
        let elapsed = max(0, Int(nowLocal.timeIntervalSince(fetchedAtLocal).rounded(.down)))
        return max(0, serverRemainSec - elapsed)
    }

    /// Preferred: use absolute deadline + calibrated server now.
    /// Fallback: decay `*_remain_sec` from fetch instant.
    public static func payRemainSeconds(
        deadline: Date?,
        serverRemainSec: Int?,
        serverTime: Date?,
        fetchedAtLocal: Date,
        nowLocal: Date = Date()
    ) -> Int {
        if let deadline, let serverTime {
            let elapsed = max(0, nowLocal.timeIntervalSince(fetchedAtLocal))
            let serverNow = serverTime.addingTimeInterval(elapsed)
            return remainSeconds(deadline: deadline, serverNow: serverNow)
        }
        return remainSeconds(serverRemainSec: serverRemainSec, fetchedAtLocal: fetchedAtLocal, nowLocal: nowLocal)
    }

    public static func shipRemainSeconds(
        deadline: Date?,
        serverRemainSec: Int?,
        serverTime: Date?,
        fetchedAtLocal: Date,
        nowLocal: Date = Date()
    ) -> Int {
        payRemainSeconds(
            deadline: deadline,
            serverRemainSec: serverRemainSec,
            serverTime: serverTime,
            fetchedAtLocal: fetchedAtLocal,
            nowLocal: nowLocal
        )
    }

    public static func isCountdownUrgent(_ remainSec: Int) -> Bool {
        remainSec > 0 && remainSec < OrderCenterConfigDefaults.countdownUrgentSec
    }

    public static func formatCountdown(_ remainSec: Int) -> String {
        let s = max(0, remainSec)
        let d = s / 86_400
        let h = (s % 86_400) / 3_600
        let m = (s % 3_600) / 60
        let sec = s % 60
        if d > 0 { return String(format: "%d天%02d:%02d:%02d", d, h, m, sec) }
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    // MARK: List safety

    /// True when encoded/decoded list JSON must not expose fee rule internals.
    public static func listPayloadContainsForbiddenFeeKeys(_ jsonObject: Any) -> Bool {
        guard let dict = jsonObject as? [String: Any] else {
            if let arr = jsonObject as? [Any] {
                return arr.contains { listPayloadContainsForbiddenFeeKeys($0) }
            }
            return false
        }
        for (k, v) in dict {
            let key = k.lowercased()
            if key == "fee_rule_snapshot" || key == "feerulesnapshot" { return true }
            if key == "priority" && dict["rate_bp"] != nil { return true }
            if listPayloadContainsForbiddenFeeKeys(v) { return true }
        }
        return false
    }

    public static func displayTitle(card: OrderListCard) -> String {
        let t = (card.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "商品" : t
    }

    public static func statusHeaderTitle(status: OrderCenterStatus, isSeller: Bool) -> String {
        if isSeller {
            switch status {
            case .pendingPayment: return "等待买家付款"
            case .paid: return "买家已付款，请发货"
            case .shipped: return "已发货"
            case .completed, .settled: return "交易完成"
            case .cancelled: return "订单已取消"
            case .refunded: return "已退款"
            }
        }
        switch status {
        case .pendingPayment: return "等待付款"
        case .paid: return "等待卖家发货"
        case .shipped: return "卖家已发货"
        case .completed, .settled: return "交易完成"
        case .cancelled: return "订单已取消"
        case .refunded: return "已退款"
        }
    }
}
