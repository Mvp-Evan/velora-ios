import Foundation

// MARK: - Presale lifecycle / balance pay (DES-v1.3-06-03 REL-06/07/08/14/15 / D25)

/// Product defaults (design §3 / §5 / §13 / §15).
public enum PresaleConfigDefaults {
    public static let depositRatioMax = 0.30
    public static let balanceWindowMinHours = 72
    public static let nudgeMax = 3
    public static let nudgeIntervalHours = 24
    public static let delayMax = 3
    public static let compensationBP = 1_000 // 10% of deposit
    public static let linkTTLDays = 7
    public static let depositPaySec = 900 // 15m
    public static let delayChoiceDefaultHours = 72
    public static let creditMin = 60
    public static let orderTypeDeposit = "presale_deposit"
    public static let orderTypeBalance = "presale_balance"
    public static let launchGateKey = "launch_gate.presale"
    public static let meEntryKey = "balance"
    public static let universalPathPrefix = "/pay/balance"
    public static let shortLinkPathPrefix = "/b"
    public static let defaultUniversalHost = "u.velora.test"
    /// N-15 offsets relative to balance deadline (design §5.9).
    public static let n15Offset24hSec = 86_400
    public static let n15Offset2hSec = 7_200
}

// MARK: - Status / kinds / modes

/// Buyer-visible `presale_order.biz_status` (design §4). Never surface `fund_status` as order failure.
public enum PresaleBizStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case depositPending = "deposit_pending"
    case depositPaid = "deposit_paid"
    case balancePending = "balance_pending"
    case balancePaid = "balance_paid"
    case shipped
    case expired
    case merchantCancelled = "merchant_cancelled"
    case buyerRefunded = "buyer_refunded"
    /// Occupancy alias used by REL-13 convert (not a primary buyer list filter).
    case completed

    public var displayLabel: String {
        switch self {
        case .depositPending: return "待付定金"
        case .depositPaid: return "已付定金"
        case .balancePending: return "待补款"
        case .balancePaid: return "已补款"
        case .shipped: return "已发货"
        case .expired: return "已逾期"
        case .merchantCancelled: return "商家已取消"
        case .buyerRefunded: return "已退定金"
        case .completed: return "已完成"
        }
    }

    public var showsBalanceCountdown: Bool { self == .balancePending }
    public var showsDepositPayCTA: Bool { self == .depositPending }
    public var showsBalancePayCTA: Bool { self == .balancePending }
    public var showsDelayChoice: Bool {
        self == .depositPaid || self == .balancePending
    }

    public var isTerminal: Bool {
        switch self {
        case .expired, .merchantCancelled, .buyerRefunded, .completed:
            return true
        default:
            return false
        }
    }

    /// Illegal buyer-visible transitions (design §4).
    public func canTransition(to next: PresaleBizStatus) -> Bool {
        switch (self, next) {
        case (.depositPending, .depositPaid): return true
        case (.depositPaid, .balancePending): return true
        case (.balancePending, .balancePaid), (.balancePending, .expired): return true
        case (.balancePaid, .shipped): return true
        case (.depositPaid, .merchantCancelled),
             (.balancePending, .merchantCancelled),
             (.balancePaid, .merchantCancelled): return true
        case (.depositPaid, .buyerRefunded), (.balancePending, .buyerRefunded): return true
        case (.shipped, .completed): return true
        // Forbidden: expired → balance_paid; buyer_refunded → deposit_paid
        case (.expired, .balancePaid), (.buyerRefunded, .depositPaid): return false
        default: return false
        }
    }
}

/// Fund sub-status — merchant / reconciliation only (design §3 / §4). Never show alone as「订单失败」.
public enum PresaleFundStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case depositHeld = "deposit_held"
    case balanceHeld = "balance_held"
    case settling
    case settled
    case refunding
    case refunded
    case forfeitPending = "forfeit_pending"
}

public enum PresaleLegalDepositKind: String, Codable, Sendable, CaseIterable, Equatable {
    case dingjin
    case orderingDeposit = "ordering_deposit"

    /// Product-page / detail disclosure (design §3 / §9).
    public var displayCopy: String {
        switch self {
        case .dingjin: return PresaleCopy.legalDingjin
        case .orderingDeposit: return PresaleCopy.legalOrderingDeposit
        }
    }

    public var shortLabel: String {
        switch self {
        case .dingjin: return "定金"
        case .orderingDeposit: return "订金"
        }
    }
}

public enum PresaleBalanceMode: String, Codable, Sendable, CaseIterable, Equatable {
    case scheduled
    case manual

    public var displayLabel: String {
        switch self {
        case .scheduled: return "定时开启"
        case .manual: return "商家发起"
        }
    }
}

public enum PresaleSettleMode: String, Codable, Sendable, CaseIterable, Equatable {
    case confirmReceipt = "confirm_receipt"
    case onShip = "on_ship"

    public var displayLabel: String {
        switch self {
        case .confirmReceipt: return "确认收货后分账"
        case .onShip: return "发货即结算"
        }
    }

    public var requiresDisclosure: Bool { self == .onShip }
}

public enum PresaleDelayChoice: String, Codable, Sendable, CaseIterable, Equatable {
    case continueWaiting = "continue"
    case refund

    public var displayLabel: String {
        switch self {
        case .continueWaiting: return PresaleCopy.delayContinue
        case .refund: return PresaleCopy.delayRefund
        }
    }
}

public enum PresaleTimelineActor: String, Codable, Sendable, CaseIterable, Equatable {
    case buyer
    case merchant
    case system

    public var displayLabel: String {
        switch self {
        case .buyer: return "买家"
        case .merchant: return "商家"
        case .system: return "系统"
        }
    }
}

/// Buyer-visible timeline event keys (design §3). Fund sub-states must never appear.
public enum PresaleTimelineEventKey: String, Codable, Sendable, CaseIterable, Equatable {
    case depositPaid = "deposit_paid"
    case balanceOpened = "balance_opened"
    case balancePaid = "balance_paid"
    case delayNotice = "delay_notice"
    case estDelivery = "est_delivery"
    case shipped
    case confirmReceipt = "confirm_receipt"

    public var defaultTitle: String {
        switch self {
        case .depositPaid: return "定金支付成功"
        case .balanceOpened: return "补款开启"
        case .balancePaid: return "尾款支付成功"
        case .delayNotice: return "延期公告"
        case .estDelivery: return "预计发货"
        case .shipped: return "实际发货"
        case .confirmReceipt: return "确认收货"
        }
    }

    public static let buyerVisibleKeys: Set<String> = Set(allCases.map(\.rawValue))

    public static func isBuyerVisible(_ key: String?) -> Bool {
        guard let key, !key.isEmpty else { return true }
        if PresaleFundStatus(rawValue: key) != nil { return false }
        let banned = ["settling", "settled", "refunding", "refunded", "forfeit_pending", "deposit_held", "balance_held"]
        if banned.contains(key) { return false }
        return buyerVisibleKeys.contains(key) || !banned.contains(key)
    }
}

// MARK: - Eligibility / CTA

public struct PresaleEligibility: Codable, Equatable, Sendable {
    public let realNamed: Bool?
    public let creditOk: Bool?
    public let creditScore: Int?
    public let vipLevel: Int?
    public let vipOk: Bool?
    public let addressReady: Bool?
    public let launchGateOpen: Bool?
    public let alreadyOrdered: Bool?
    public let presaleOrderId: Int64?

    public init(
        realNamed: Bool? = nil,
        creditOk: Bool? = nil,
        creditScore: Int? = nil,
        vipLevel: Int? = nil,
        vipOk: Bool? = nil,
        addressReady: Bool? = nil,
        launchGateOpen: Bool? = nil,
        alreadyOrdered: Bool? = nil,
        presaleOrderId: Int64? = nil
    ) {
        self.realNamed = realNamed
        self.creditOk = creditOk
        self.creditScore = creditScore
        self.vipLevel = vipLevel
        self.vipOk = vipOk
        self.addressReady = addressReady
        self.launchGateOpen = launchGateOpen
        self.alreadyOrdered = alreadyOrdered
        self.presaleOrderId = presaleOrderId
    }

    public var isRealNamed: Bool { realNamed == true }
    public var isCreditOk: Bool {
        if let creditOk { return creditOk }
        if let creditScore { return creditScore >= PresaleConfigDefaults.creditMin }
        return false
    }
    public var isVipOk: Bool { vipOk != false }
    public var isLaunchGateOpen: Bool { launchGateOpen != false }
    public var hasOrdered: Bool { alreadyOrdered == true || presaleOrderId != nil }
    public var resolvedVipLevel: Int { vipLevel ?? 0 }
}

public enum PresaleDepositStep: String, Sendable, Equatable, CaseIterable {
    case login
    case realName
    case credit
    case address

    public var title: String {
        switch self {
        case .login: return "登录"
        case .realName: return "实名认证"
        case .credit: return "信用分"
        case .address: return "收货地址"
        }
    }

    public var actionTitle: String {
        switch self {
        case .login: return "去登录"
        case .realName: return "去实名"
        case .credit: return "信用不足"
        case .address: return "去设置地址"
        }
    }
}

public struct PresaleDepositChecklistItem: Equatable, Sendable, Identifiable {
    public let step: PresaleDepositStep
    public let done: Bool
    public var id: String { step.rawValue }

    public init(step: PresaleDepositStep, done: Bool) {
        self.step = step
        self.done = done
    }
}

public enum PresaleCTA: String, Sendable, Equatable {
    case login
    case completeEligibility
    case waitDepositOpen
    case payDeposit
    case depositPaidWaiting
    case payBalance
    case delayChoice
    case balancePaid
    case shipped
    case expired
    case cancelled
    case refunded
    case gated
    case ended

    public var buttonTitle: String {
        switch self {
        case .login: return "登录后付定金"
        case .completeEligibility: return PresaleCopy.completeEligibility
        case .waitDepositOpen: return "定金未开始"
        case .payDeposit: return PresaleCopy.payDeposit
        case .depositPaidWaiting: return PresaleCopy.depositPaidWaiting
        case .payBalance: return PresaleCopy.payBalance
        case .delayChoice: return PresaleCopy.delayChoiceCTA
        case .balancePaid: return PresaleCopy.balancePaid
        case .shipped: return PresaleCopy.shipped
        case .expired: return PresaleCopy.expired
        case .cancelled: return PresaleCopy.cancelled
        case .refunded: return PresaleCopy.refunded
        case .gated: return PresaleCopy.gated
        case .ended: return PresaleCopy.ended
        }
    }

    public var isPrimaryAction: Bool {
        switch self {
        case .login, .completeEligibility, .payDeposit, .payBalance, .delayChoice:
            return true
        default:
            return false
        }
    }
}

// MARK: - Timeline / delay / amounts

public struct PresaleTimelineEvent: Codable, Equatable, Sendable, Identifiable {
    public let eventId: Int64?
    public let at: Date?
    public let title: String?
    public let actorType: PresaleTimelineActor?
    public let eventKey: String?

    public var id: Int64 {
        eventId ?? Int64((at?.timeIntervalSince1970 ?? 0) * 1000)
    }

    public init(
        id: Int64? = nil,
        at: Date? = nil,
        title: String? = nil,
        actorType: PresaleTimelineActor? = nil,
        eventKey: String? = nil
    ) {
        self.eventId = id
        self.at = at
        self.title = title
        self.actorType = actorType
        self.eventKey = eventKey
    }

    enum CodingKeys: String, CodingKey {
        case eventId = "id"
        case at, title, actorType, eventKey
    }

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let key = eventKey, let known = PresaleTimelineEventKey(rawValue: key) {
            return known.defaultTitle
        }
        return "节点"
    }

    public var isBuyerVisible: Bool {
        PresaleTimelineEventKey.isBuyerVisible(eventKey)
    }
}

public struct PresaleDelayNotice: Codable, Equatable, Sendable, Identifiable {
    public let noticeId: Int64?
    public let releaseId: Int64?
    public let oldDelivery: Date?
    public let newDelivery: Date?
    public let body: String?
    public let choiceDeadline: Date?
    public let seq: Int?

    public var id: Int64 { noticeId ?? 0 }

    public init(
        id: Int64? = nil,
        releaseId: Int64? = nil,
        oldDelivery: Date? = nil,
        newDelivery: Date? = nil,
        body: String? = nil,
        choiceDeadline: Date? = nil,
        seq: Int? = nil
    ) {
        self.noticeId = id
        self.releaseId = releaseId
        self.oldDelivery = oldDelivery
        self.newDelivery = newDelivery
        self.body = body
        self.choiceDeadline = choiceDeadline
        self.seq = seq
    }

    enum CodingKeys: String, CodingKey {
        case noticeId = "id"
        case releaseId, oldDelivery, newDelivery, body, choiceDeadline, seq
    }

    public var displayBody: String {
        (body?.isEmpty == false) ? body! : "发货时间已延期，请选择继续等待或申请退定金。"
    }
}

/// Deposit / balance amount helpers (fen).
public struct PresaleAmountSnapshot: Codable, Equatable, Sendable {
    public let depositPriceFen: Int64?
    public let balancePriceFen: Int64?
    public let qty: Int?

    public init(depositPriceFen: Int64? = nil, balancePriceFen: Int64? = nil, qty: Int? = nil) {
        self.depositPriceFen = depositPriceFen
        self.balancePriceFen = balancePriceFen
        self.qty = qty
    }

    public var resolvedQty: Int { max(1, qty ?? 1) }

    public var depositTotalFen: Int64 {
        (depositPriceFen ?? 0) * Int64(resolvedQty)
    }

    public var balanceTotalFen: Int64 {
        (balancePriceFen ?? 0) * Int64(resolvedQty)
    }

    public var totalFen: Int64 { depositTotalFen + balanceTotalFen }

    public var depositRatio: Double {
        let total = Double(totalFen)
        guard total > 0 else { return 0 }
        return Double(depositTotalFen) / total
    }
}

// MARK: - Release detail (mode=presale)

public struct PresaleReleaseDetail: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let merchantId: Int64?
    public let listingId: Int64?
    public let brandId: Int64?
    public let title: String?
    public let cover: String?
    public let mode: String?
    public let status: String?
    public let depositPriceFen: Int64?
    public let balancePriceFen: Int64?
    public let depositRatio: Double?
    public let limitPerUser: Int?
    public let depositStartAt: Date?
    public let depositEndAt: Date?
    public let balanceMode: PresaleBalanceMode?
    public let balanceStartAt: Date?
    public let balanceEndAt: Date?
    public let estDeliveryAt: Date?
    public let settleMode: PresaleSettleMode?
    public let settleDisclosure: String?
    public let legalDepositKind: PresaleLegalDepositKind?
    public let delayRefundNote: String?
    public let skus: [SpotReleaseSKU]
    public let vipWindows: [SpotReleaseVIPWindow]
    public let eligibility: PresaleEligibility?
    public let nextWindow: SpotReleaseNextWindow?
    public let myOrder: PresaleOrderSummary?
    public let openDelayNotice: PresaleDelayNotice?
    public let remaining: Int?
    public let serverNow: Date?
    public let serverNowMs: Int64?
    public let serverTime: Date?
    public let serverTimeMs: Int64?
    public let version: Int64?

    public init(
        id: Int64,
        merchantId: Int64? = nil,
        listingId: Int64? = nil,
        brandId: Int64? = nil,
        title: String? = nil,
        cover: String? = nil,
        mode: String? = nil,
        status: String? = nil,
        depositPriceFen: Int64? = nil,
        balancePriceFen: Int64? = nil,
        depositRatio: Double? = nil,
        limitPerUser: Int? = nil,
        depositStartAt: Date? = nil,
        depositEndAt: Date? = nil,
        balanceMode: PresaleBalanceMode? = nil,
        balanceStartAt: Date? = nil,
        balanceEndAt: Date? = nil,
        estDeliveryAt: Date? = nil,
        settleMode: PresaleSettleMode? = nil,
        settleDisclosure: String? = nil,
        legalDepositKind: PresaleLegalDepositKind? = nil,
        delayRefundNote: String? = nil,
        skus: [SpotReleaseSKU] = [],
        vipWindows: [SpotReleaseVIPWindow] = [],
        eligibility: PresaleEligibility? = nil,
        nextWindow: SpotReleaseNextWindow? = nil,
        myOrder: PresaleOrderSummary? = nil,
        openDelayNotice: PresaleDelayNotice? = nil,
        remaining: Int? = nil,
        serverNow: Date? = nil,
        serverNowMs: Int64? = nil,
        serverTime: Date? = nil,
        serverTimeMs: Int64? = nil,
        version: Int64? = nil
    ) {
        self.id = id
        self.merchantId = merchantId
        self.listingId = listingId
        self.brandId = brandId
        self.title = title
        self.cover = cover
        self.mode = mode
        self.status = status
        self.depositPriceFen = depositPriceFen
        self.balancePriceFen = balancePriceFen
        self.depositRatio = depositRatio
        self.limitPerUser = limitPerUser
        self.depositStartAt = depositStartAt
        self.depositEndAt = depositEndAt
        self.balanceMode = balanceMode
        self.balanceStartAt = balanceStartAt
        self.balanceEndAt = balanceEndAt
        self.estDeliveryAt = estDeliveryAt
        self.settleMode = settleMode
        self.settleDisclosure = settleDisclosure
        self.legalDepositKind = legalDepositKind
        self.delayRefundNote = delayRefundNote
        self.skus = skus
        self.vipWindows = vipWindows
        self.eligibility = eligibility
        self.nextWindow = nextWindow
        self.myOrder = myOrder
        self.openDelayNotice = openDelayNotice
        self.remaining = remaining
        self.serverNow = serverNow
        self.serverNowMs = serverNowMs
        self.serverTime = serverTime
        self.serverTimeMs = serverTimeMs
        self.version = version
    }

    enum CodingKeys: String, CodingKey {
        case id, merchantId, listingId, brandId, title, cover, mode, status
        case depositPriceFen, balancePriceFen, depositRatio, limitPerUser
        case depositStartAt, depositEndAt, balanceMode, balanceStartAt, balanceEndAt
        case estDeliveryAt, settleMode, settleDisclosure, settleDisclosed
        case legalDepositKind, delayRefundNote
        case skus, vipWindows, eligibility, userEligibility, nextWindow
        case myOrder, myPresaleOrder, openDelayNotice, activeDelayNotice
        case remaining, serverNow, serverNowMs, serverTime, serverTimeMs, version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        merchantId = try c.decodeIfPresent(Int64.self, forKey: .merchantId)
        listingId = try c.decodeIfPresent(Int64.self, forKey: .listingId)
        brandId = try c.decodeIfPresent(Int64.self, forKey: .brandId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        mode = try c.decodeIfPresent(String.self, forKey: .mode)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        depositPriceFen = try c.decodeIfPresent(Int64.self, forKey: .depositPriceFen)
        balancePriceFen = try c.decodeIfPresent(Int64.self, forKey: .balancePriceFen)
        depositRatio = try c.decodeIfPresent(Double.self, forKey: .depositRatio)
        limitPerUser = try c.decodeIfPresent(Int.self, forKey: .limitPerUser)
        depositStartAt = try c.decodeIfPresent(Date.self, forKey: .depositStartAt)
        depositEndAt = try c.decodeIfPresent(Date.self, forKey: .depositEndAt)
        balanceMode = try c.decodeIfPresent(PresaleBalanceMode.self, forKey: .balanceMode)
        balanceStartAt = try c.decodeIfPresent(Date.self, forKey: .balanceStartAt)
        balanceEndAt = try c.decodeIfPresent(Date.self, forKey: .balanceEndAt)
        estDeliveryAt = try c.decodeIfPresent(Date.self, forKey: .estDeliveryAt)
        settleMode = try c.decodeIfPresent(PresaleSettleMode.self, forKey: .settleMode)
        settleDisclosure = try c.decodeIfPresent(String.self, forKey: .settleDisclosure)
        legalDepositKind = try c.decodeIfPresent(PresaleLegalDepositKind.self, forKey: .legalDepositKind)
        delayRefundNote = try c.decodeIfPresent(String.self, forKey: .delayRefundNote)
        skus = try c.decodeIfPresent([SpotReleaseSKU].self, forKey: .skus) ?? []
        vipWindows = try c.decodeIfPresent([SpotReleaseVIPWindow].self, forKey: .vipWindows) ?? []
        eligibility = try c.decodeIfPresent(PresaleEligibility.self, forKey: .eligibility)
            ?? c.decodeIfPresent(PresaleEligibility.self, forKey: .userEligibility)
        nextWindow = try c.decodeIfPresent(SpotReleaseNextWindow.self, forKey: .nextWindow)
        myOrder = try c.decodeIfPresent(PresaleOrderSummary.self, forKey: .myOrder)
            ?? c.decodeIfPresent(PresaleOrderSummary.self, forKey: .myPresaleOrder)
        openDelayNotice = try c.decodeIfPresent(PresaleDelayNotice.self, forKey: .openDelayNotice)
            ?? c.decodeIfPresent(PresaleDelayNotice.self, forKey: .activeDelayNotice)
        remaining = try c.decodeIfPresent(Int.self, forKey: .remaining)
        serverNow = try c.decodeIfPresent(Date.self, forKey: .serverNow)
        serverNowMs = try c.decodeIfPresent(Int64.self, forKey: .serverNowMs)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
        serverTimeMs = try c.decodeIfPresent(Int64.self, forKey: .serverTimeMs)
        version = try c.decodeIfPresent(Int64.self, forKey: .version)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(merchantId, forKey: .merchantId)
        try c.encodeIfPresent(listingId, forKey: .listingId)
        try c.encodeIfPresent(brandId, forKey: .brandId)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(cover, forKey: .cover)
        try c.encodeIfPresent(mode, forKey: .mode)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(depositPriceFen, forKey: .depositPriceFen)
        try c.encodeIfPresent(balancePriceFen, forKey: .balancePriceFen)
        try c.encodeIfPresent(depositRatio, forKey: .depositRatio)
        try c.encodeIfPresent(limitPerUser, forKey: .limitPerUser)
        try c.encodeIfPresent(depositStartAt, forKey: .depositStartAt)
        try c.encodeIfPresent(depositEndAt, forKey: .depositEndAt)
        try c.encodeIfPresent(balanceMode, forKey: .balanceMode)
        try c.encodeIfPresent(balanceStartAt, forKey: .balanceStartAt)
        try c.encodeIfPresent(balanceEndAt, forKey: .balanceEndAt)
        try c.encodeIfPresent(estDeliveryAt, forKey: .estDeliveryAt)
        try c.encodeIfPresent(settleMode, forKey: .settleMode)
        try c.encodeIfPresent(settleDisclosure, forKey: .settleDisclosure)
        try c.encodeIfPresent(legalDepositKind, forKey: .legalDepositKind)
        try c.encodeIfPresent(delayRefundNote, forKey: .delayRefundNote)
        try c.encode(skus, forKey: .skus)
        try c.encode(vipWindows, forKey: .vipWindows)
        try c.encodeIfPresent(eligibility, forKey: .eligibility)
        try c.encodeIfPresent(nextWindow, forKey: .nextWindow)
        try c.encodeIfPresent(myOrder, forKey: .myOrder)
        try c.encodeIfPresent(openDelayNotice, forKey: .openDelayNotice)
        try c.encodeIfPresent(remaining, forKey: .remaining)
        try c.encodeIfPresent(serverNow, forKey: .serverNow)
        try c.encodeIfPresent(serverNowMs, forKey: .serverNowMs)
        try c.encodeIfPresent(serverTime, forKey: .serverTime)
        try c.encodeIfPresent(serverTimeMs, forKey: .serverTimeMs)
        try c.encodeIfPresent(version, forKey: .version)
    }

    public var isPresaleMode: Bool {
        (mode ?? "").lowercased() == SpotReleaseMode.presale.rawValue
    }

    public var displayTitle: String {
        (title?.isEmpty == false) ? title! : "预售"
    }

    public var amounts: PresaleAmountSnapshot {
        PresaleAmountSnapshot(
            depositPriceFen: depositPriceFen,
            balancePriceFen: balancePriceFen,
            qty: 1
        )
    }

    public var legalCopy: String? {
        legalDepositKind?.displayCopy
    }

    public var settleDisclosureText: String? {
        if let settleDisclosure, !settleDisclosure.isEmpty { return settleDisclosure }
        if settleMode?.requiresDisclosure == true {
            return PresaleCopy.settleOnShipDisclosure
        }
        return nil
    }

    public var defaultSKU: SpotReleaseSKU? { skus.first }

    public var resolvedServerNow: Date? {
        if let serverNow { return serverNow }
        if let serverTime { return serverTime }
        if let ms = serverNowMs ?? serverTimeMs {
            return Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        return nil
    }
}

// MARK: - Presale order (buyer)

/// List / summary row — buyer sees `biz_status` only (design §3 / §5.10).
public struct PresaleOrderSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let releaseId: Int64?
    public let skuId: Int64?
    public let qty: Int?
    public let bizStatus: PresaleBizStatus?
    public let depositOrderId: Int64?
    public let balanceOrderId: Int64?
    public let depositPriceFen: Int64?
    public let balancePriceFen: Int64?
    public let estDeliveryAt: Date?
    public let estDeliveryAtSnapshot: Date?
    public let balanceDeadline: Date?
    public let delayChoiceDeadline: Date?
    public let delayChoice: PresaleDelayChoice?
    public let legalDepositKind: PresaleLegalDepositKind?
    public let title: String?
    public let cover: String?
    public let skuLabel: String?
    public let openDelayNotice: PresaleDelayNotice?
    public let serverNow: Date?
    public let serverNowMs: Int64?

    public init(
        id: Int64,
        releaseId: Int64? = nil,
        skuId: Int64? = nil,
        qty: Int? = nil,
        bizStatus: PresaleBizStatus? = nil,
        depositOrderId: Int64? = nil,
        balanceOrderId: Int64? = nil,
        depositPriceFen: Int64? = nil,
        balancePriceFen: Int64? = nil,
        estDeliveryAt: Date? = nil,
        estDeliveryAtSnapshot: Date? = nil,
        balanceDeadline: Date? = nil,
        delayChoiceDeadline: Date? = nil,
        delayChoice: PresaleDelayChoice? = nil,
        legalDepositKind: PresaleLegalDepositKind? = nil,
        title: String? = nil,
        cover: String? = nil,
        skuLabel: String? = nil,
        openDelayNotice: PresaleDelayNotice? = nil,
        serverNow: Date? = nil,
        serverNowMs: Int64? = nil
    ) {
        self.id = id
        self.releaseId = releaseId
        self.skuId = skuId
        self.qty = qty
        self.bizStatus = bizStatus
        self.depositOrderId = depositOrderId
        self.balanceOrderId = balanceOrderId
        self.depositPriceFen = depositPriceFen
        self.balancePriceFen = balancePriceFen
        self.estDeliveryAt = estDeliveryAt
        self.estDeliveryAtSnapshot = estDeliveryAtSnapshot
        self.balanceDeadline = balanceDeadline
        self.delayChoiceDeadline = delayChoiceDeadline
        self.delayChoice = delayChoice
        self.legalDepositKind = legalDepositKind
        self.title = title
        self.cover = cover
        self.skuLabel = skuLabel
        self.openDelayNotice = openDelayNotice
        self.serverNow = serverNow
        self.serverNowMs = serverNowMs
    }

    enum CodingKeys: String, CodingKey {
        case id, releaseId, skuId, qty, bizStatus
        case depositOrderId, balanceOrderId
        case depositPriceFen, balancePriceFen
        case estDeliveryAt, estDeliveryAtSnapshot, balanceDeadline, deadline
        case delayChoiceDeadline, delayChoice, legalDepositKind
        case title, cover, skuLabel, skuName
        case openDelayNotice, activeDelayNotice
        case serverNow, serverNowMs
        // Intentionally omit fundStatus from public buyer surface.
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        releaseId = try c.decodeIfPresent(Int64.self, forKey: .releaseId)
        skuId = try c.decodeIfPresent(Int64.self, forKey: .skuId)
        qty = try c.decodeIfPresent(Int.self, forKey: .qty)
        bizStatus = try c.decodeIfPresent(PresaleBizStatus.self, forKey: .bizStatus)
        depositOrderId = try c.decodeIfPresent(Int64.self, forKey: .depositOrderId)
        balanceOrderId = try c.decodeIfPresent(Int64.self, forKey: .balanceOrderId)
        depositPriceFen = try c.decodeIfPresent(Int64.self, forKey: .depositPriceFen)
        balancePriceFen = try c.decodeIfPresent(Int64.self, forKey: .balancePriceFen)
        estDeliveryAt = try c.decodeIfPresent(Date.self, forKey: .estDeliveryAt)
            ?? c.decodeIfPresent(Date.self, forKey: .estDeliveryAtSnapshot)
        estDeliveryAtSnapshot = try c.decodeIfPresent(Date.self, forKey: .estDeliveryAtSnapshot)
        balanceDeadline = try c.decodeIfPresent(Date.self, forKey: .balanceDeadline)
            ?? c.decodeIfPresent(Date.self, forKey: .deadline)
        delayChoiceDeadline = try c.decodeIfPresent(Date.self, forKey: .delayChoiceDeadline)
        delayChoice = try c.decodeIfPresent(PresaleDelayChoice.self, forKey: .delayChoice)
        legalDepositKind = try c.decodeIfPresent(PresaleLegalDepositKind.self, forKey: .legalDepositKind)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        skuLabel = try c.decodeIfPresent(String.self, forKey: .skuLabel)
            ?? c.decodeIfPresent(String.self, forKey: .skuName)
        openDelayNotice = try c.decodeIfPresent(PresaleDelayNotice.self, forKey: .openDelayNotice)
            ?? c.decodeIfPresent(PresaleDelayNotice.self, forKey: .activeDelayNotice)
        serverNow = try c.decodeIfPresent(Date.self, forKey: .serverNow)
        serverNowMs = try c.decodeIfPresent(Int64.self, forKey: .serverNowMs)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(releaseId, forKey: .releaseId)
        try c.encodeIfPresent(skuId, forKey: .skuId)
        try c.encodeIfPresent(qty, forKey: .qty)
        try c.encodeIfPresent(bizStatus, forKey: .bizStatus)
        try c.encodeIfPresent(depositOrderId, forKey: .depositOrderId)
        try c.encodeIfPresent(balanceOrderId, forKey: .balanceOrderId)
        try c.encodeIfPresent(depositPriceFen, forKey: .depositPriceFen)
        try c.encodeIfPresent(balancePriceFen, forKey: .balancePriceFen)
        try c.encodeIfPresent(estDeliveryAt, forKey: .estDeliveryAt)
        try c.encodeIfPresent(estDeliveryAtSnapshot, forKey: .estDeliveryAtSnapshot)
        try c.encodeIfPresent(balanceDeadline, forKey: .balanceDeadline)
        try c.encodeIfPresent(delayChoiceDeadline, forKey: .delayChoiceDeadline)
        try c.encodeIfPresent(delayChoice, forKey: .delayChoice)
        try c.encodeIfPresent(legalDepositKind, forKey: .legalDepositKind)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(cover, forKey: .cover)
        try c.encodeIfPresent(skuLabel, forKey: .skuLabel)
        try c.encodeIfPresent(openDelayNotice, forKey: .openDelayNotice)
        try c.encodeIfPresent(serverNow, forKey: .serverNow)
        try c.encodeIfPresent(serverNowMs, forKey: .serverNowMs)
    }

    public var resolvedStatus: PresaleBizStatus { bizStatus ?? .depositPending }

    public var displayTitle: String {
        (title?.isEmpty == false) ? title! : "预售订单"
    }

    public var amounts: PresaleAmountSnapshot {
        PresaleAmountSnapshot(
            depositPriceFen: depositPriceFen,
            balancePriceFen: balancePriceFen,
            qty: qty
        )
    }

    public var resolvedDeliveryAt: Date? {
        estDeliveryAt ?? estDeliveryAtSnapshot
    }

    public var resolvedServerNow: Date? {
        if let serverNow { return serverNow }
        if let ms = serverNowMs {
            return Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        return nil
    }
}

/// Buyer detail — timeline + amounts; `fund_status` must not drive UI failure copy.
public struct PresaleOrderDetail: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let releaseId: Int64?
    public let skuId: Int64?
    public let qty: Int?
    public let bizStatus: PresaleBizStatus?
    public let depositOrderId: Int64?
    public let balanceOrderId: Int64?
    public let depositPriceFen: Int64?
    public let balancePriceFen: Int64?
    public let estDeliveryAt: Date?
    public let estDeliveryAtSnapshot: Date?
    public let settleModeSnapshot: PresaleSettleMode?
    public let settleDisclosure: String?
    public let balanceDeadline: Date?
    public let delayChoiceDeadline: Date?
    public let delayChoice: PresaleDelayChoice?
    public let legalDepositKind: PresaleLegalDepositKind?
    public let title: String?
    public let cover: String?
    public let skuLabel: String?
    public let openDelayNotice: PresaleDelayNotice?
    public let timeline: [PresaleTimelineEvent]
    public let overdueReasonCopy: String?
    public let serverNow: Date?
    public let serverNowMs: Int64?
    public let version: Int64?

    public init(
        id: Int64,
        releaseId: Int64? = nil,
        skuId: Int64? = nil,
        qty: Int? = nil,
        bizStatus: PresaleBizStatus? = nil,
        depositOrderId: Int64? = nil,
        balanceOrderId: Int64? = nil,
        depositPriceFen: Int64? = nil,
        balancePriceFen: Int64? = nil,
        estDeliveryAt: Date? = nil,
        estDeliveryAtSnapshot: Date? = nil,
        settleModeSnapshot: PresaleSettleMode? = nil,
        settleDisclosure: String? = nil,
        balanceDeadline: Date? = nil,
        delayChoiceDeadline: Date? = nil,
        delayChoice: PresaleDelayChoice? = nil,
        legalDepositKind: PresaleLegalDepositKind? = nil,
        title: String? = nil,
        cover: String? = nil,
        skuLabel: String? = nil,
        openDelayNotice: PresaleDelayNotice? = nil,
        timeline: [PresaleTimelineEvent] = [],
        overdueReasonCopy: String? = nil,
        serverNow: Date? = nil,
        serverNowMs: Int64? = nil,
        version: Int64? = nil
    ) {
        self.id = id
        self.releaseId = releaseId
        self.skuId = skuId
        self.qty = qty
        self.bizStatus = bizStatus
        self.depositOrderId = depositOrderId
        self.balanceOrderId = balanceOrderId
        self.depositPriceFen = depositPriceFen
        self.balancePriceFen = balancePriceFen
        self.estDeliveryAt = estDeliveryAt
        self.estDeliveryAtSnapshot = estDeliveryAtSnapshot
        self.settleModeSnapshot = settleModeSnapshot
        self.settleDisclosure = settleDisclosure
        self.balanceDeadline = balanceDeadline
        self.delayChoiceDeadline = delayChoiceDeadline
        self.delayChoice = delayChoice
        self.legalDepositKind = legalDepositKind
        self.title = title
        self.cover = cover
        self.skuLabel = skuLabel
        self.openDelayNotice = openDelayNotice
        self.timeline = timeline
        self.overdueReasonCopy = overdueReasonCopy
        self.serverNow = serverNow
        self.serverNowMs = serverNowMs
        self.version = version
    }

    enum CodingKeys: String, CodingKey {
        case id, releaseId, skuId, qty, bizStatus
        case depositOrderId, balanceOrderId
        case depositPriceFen, balancePriceFen
        case estDeliveryAt, estDeliveryAtSnapshot
        case settleModeSnapshot, settleDisclosure
        case balanceDeadline, deadline
        case delayChoiceDeadline, delayChoice, legalDepositKind
        case title, cover, skuLabel, skuName
        case openDelayNotice, activeDelayNotice
        case timeline, events
        case overdueReasonCopy, overdueReason
        case serverNow, serverNowMs, version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        releaseId = try c.decodeIfPresent(Int64.self, forKey: .releaseId)
        skuId = try c.decodeIfPresent(Int64.self, forKey: .skuId)
        qty = try c.decodeIfPresent(Int.self, forKey: .qty)
        bizStatus = try c.decodeIfPresent(PresaleBizStatus.self, forKey: .bizStatus)
        depositOrderId = try c.decodeIfPresent(Int64.self, forKey: .depositOrderId)
        balanceOrderId = try c.decodeIfPresent(Int64.self, forKey: .balanceOrderId)
        depositPriceFen = try c.decodeIfPresent(Int64.self, forKey: .depositPriceFen)
        balancePriceFen = try c.decodeIfPresent(Int64.self, forKey: .balancePriceFen)
        estDeliveryAt = try c.decodeIfPresent(Date.self, forKey: .estDeliveryAt)
            ?? c.decodeIfPresent(Date.self, forKey: .estDeliveryAtSnapshot)
        estDeliveryAtSnapshot = try c.decodeIfPresent(Date.self, forKey: .estDeliveryAtSnapshot)
        settleModeSnapshot = try c.decodeIfPresent(PresaleSettleMode.self, forKey: .settleModeSnapshot)
        settleDisclosure = try c.decodeIfPresent(String.self, forKey: .settleDisclosure)
        balanceDeadline = try c.decodeIfPresent(Date.self, forKey: .balanceDeadline)
            ?? c.decodeIfPresent(Date.self, forKey: .deadline)
        delayChoiceDeadline = try c.decodeIfPresent(Date.self, forKey: .delayChoiceDeadline)
        delayChoice = try c.decodeIfPresent(PresaleDelayChoice.self, forKey: .delayChoice)
        legalDepositKind = try c.decodeIfPresent(PresaleLegalDepositKind.self, forKey: .legalDepositKind)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        skuLabel = try c.decodeIfPresent(String.self, forKey: .skuLabel)
            ?? c.decodeIfPresent(String.self, forKey: .skuName)
        openDelayNotice = try c.decodeIfPresent(PresaleDelayNotice.self, forKey: .openDelayNotice)
            ?? c.decodeIfPresent(PresaleDelayNotice.self, forKey: .activeDelayNotice)
        let rawTimeline = try c.decodeIfPresent([PresaleTimelineEvent].self, forKey: .timeline)
            ?? c.decodeIfPresent([PresaleTimelineEvent].self, forKey: .events)
            ?? []
        timeline = PresaleLogic.buyerVisibleTimeline(rawTimeline)
        overdueReasonCopy = try c.decodeIfPresent(String.self, forKey: .overdueReasonCopy)
            ?? c.decodeIfPresent(String.self, forKey: .overdueReason)
        serverNow = try c.decodeIfPresent(Date.self, forKey: .serverNow)
        serverNowMs = try c.decodeIfPresent(Int64.self, forKey: .serverNowMs)
        version = try c.decodeIfPresent(Int64.self, forKey: .version)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(releaseId, forKey: .releaseId)
        try c.encodeIfPresent(skuId, forKey: .skuId)
        try c.encodeIfPresent(qty, forKey: .qty)
        try c.encodeIfPresent(bizStatus, forKey: .bizStatus)
        try c.encodeIfPresent(depositOrderId, forKey: .depositOrderId)
        try c.encodeIfPresent(balanceOrderId, forKey: .balanceOrderId)
        try c.encodeIfPresent(depositPriceFen, forKey: .depositPriceFen)
        try c.encodeIfPresent(balancePriceFen, forKey: .balancePriceFen)
        try c.encodeIfPresent(estDeliveryAt, forKey: .estDeliveryAt)
        try c.encodeIfPresent(estDeliveryAtSnapshot, forKey: .estDeliveryAtSnapshot)
        try c.encodeIfPresent(settleModeSnapshot, forKey: .settleModeSnapshot)
        try c.encodeIfPresent(settleDisclosure, forKey: .settleDisclosure)
        try c.encodeIfPresent(balanceDeadline, forKey: .balanceDeadline)
        try c.encodeIfPresent(delayChoiceDeadline, forKey: .delayChoiceDeadline)
        try c.encodeIfPresent(delayChoice, forKey: .delayChoice)
        try c.encodeIfPresent(legalDepositKind, forKey: .legalDepositKind)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(cover, forKey: .cover)
        try c.encodeIfPresent(skuLabel, forKey: .skuLabel)
        try c.encodeIfPresent(openDelayNotice, forKey: .openDelayNotice)
        try c.encode(timeline, forKey: .timeline)
        try c.encodeIfPresent(overdueReasonCopy, forKey: .overdueReasonCopy)
        try c.encodeIfPresent(serverNow, forKey: .serverNow)
        try c.encodeIfPresent(serverNowMs, forKey: .serverNowMs)
        try c.encodeIfPresent(version, forKey: .version)
    }

    public var resolvedStatus: PresaleBizStatus { bizStatus ?? .depositPending }

    public var displayTitle: String {
        (title?.isEmpty == false) ? title! : "预售订单"
    }

    public var amounts: PresaleAmountSnapshot {
        PresaleAmountSnapshot(
            depositPriceFen: depositPriceFen,
            balancePriceFen: balancePriceFen,
            qty: qty
        )
    }

    public var resolvedDeliveryAt: Date? {
        estDeliveryAt ?? estDeliveryAtSnapshot
    }

    public var asSummary: PresaleOrderSummary {
        PresaleOrderSummary(
            id: id,
            releaseId: releaseId,
            skuId: skuId,
            qty: qty,
            bizStatus: bizStatus,
            depositOrderId: depositOrderId,
            balanceOrderId: balanceOrderId,
            depositPriceFen: depositPriceFen,
            balancePriceFen: balancePriceFen,
            estDeliveryAt: estDeliveryAt,
            estDeliveryAtSnapshot: estDeliveryAtSnapshot,
            balanceDeadline: balanceDeadline,
            delayChoiceDeadline: delayChoiceDeadline,
            delayChoice: delayChoice,
            legalDepositKind: legalDepositKind,
            title: title,
            cover: cover,
            skuLabel: skuLabel,
            openDelayNotice: openDelayNotice,
            serverNow: serverNow,
            serverNowMs: serverNowMs
        )
    }

    public var resolvedServerNow: Date? {
        if let serverNow { return serverNow }
        if let ms = serverNowMs {
            return Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        return nil
    }
}

// MARK: - Create / pay / refund DTOs

public struct PresaleOrderCreateBody: Codable, Equatable, Sendable {
    public let skuId: Int64
    public let qty: Int
    public let addressId: Int64?

    public init(skuId: Int64, qty: Int = 1, addressId: Int64? = nil) {
        self.skuId = skuId
        self.qty = qty
        self.addressId = addressId
    }
}

public struct PresaleOrderCreateResult: Codable, Equatable, Sendable {
    public let presaleOrderId: Int64?
    public let id: Int64?
    public let depositOrderId: Int64?
    public let bizStatus: PresaleBizStatus?
    public let payDeadline: Date?
    public let depositPriceFen: Int64?
    public let balancePriceFen: Int64?
    public let qty: Int?
    public let alreadyExists: Bool?

    public init(
        presaleOrderId: Int64? = nil,
        id: Int64? = nil,
        depositOrderId: Int64? = nil,
        bizStatus: PresaleBizStatus? = nil,
        payDeadline: Date? = nil,
        depositPriceFen: Int64? = nil,
        balancePriceFen: Int64? = nil,
        qty: Int? = nil,
        alreadyExists: Bool? = nil
    ) {
        self.presaleOrderId = presaleOrderId
        self.id = id
        self.depositOrderId = depositOrderId
        self.bizStatus = bizStatus
        self.payDeadline = payDeadline
        self.depositPriceFen = depositPriceFen
        self.balancePriceFen = balancePriceFen
        self.qty = qty
        self.alreadyExists = alreadyExists
    }

    public var resolvedPresaleOrderId: Int64? { presaleOrderId ?? id }
}

/// GET `/api/v1/pay/balance/{order_id}` landing probe (design §5.3 / §6).
public struct BalancePayLanding: Codable, Equatable, Sendable {
    public let orderId: Int64?
    public let balanceOrderId: Int64?
    public let presaleOrderId: Int64?
    public let buyerId: Int64?
    public let amountFen: Int64?
    public let balancePriceFen: Int64?
    public let qty: Int?
    public let deadline: Date?
    public let bizStatus: PresaleBizStatus?
    public let title: String?
    public let cover: String?
    public let tokenValid: Bool?
    public let requiresLogin: Bool?
    public let buyerMismatch: Bool?
    public let expired: Bool?
    public let serverNow: Date?
    public let serverNowMs: Int64?

    public init(
        orderId: Int64? = nil,
        balanceOrderId: Int64? = nil,
        presaleOrderId: Int64? = nil,
        buyerId: Int64? = nil,
        amountFen: Int64? = nil,
        balancePriceFen: Int64? = nil,
        qty: Int? = nil,
        deadline: Date? = nil,
        bizStatus: PresaleBizStatus? = nil,
        title: String? = nil,
        cover: String? = nil,
        tokenValid: Bool? = nil,
        requiresLogin: Bool? = nil,
        buyerMismatch: Bool? = nil,
        expired: Bool? = nil,
        serverNow: Date? = nil,
        serverNowMs: Int64? = nil
    ) {
        self.orderId = orderId
        self.balanceOrderId = balanceOrderId
        self.presaleOrderId = presaleOrderId
        self.buyerId = buyerId
        self.amountFen = amountFen
        self.balancePriceFen = balancePriceFen
        self.qty = qty
        self.deadline = deadline
        self.bizStatus = bizStatus
        self.title = title
        self.cover = cover
        self.tokenValid = tokenValid
        self.requiresLogin = requiresLogin
        self.buyerMismatch = buyerMismatch
        self.expired = expired
        self.serverNow = serverNow
        self.serverNowMs = serverNowMs
    }

    public var resolvedBalanceOrderId: Int64? { balanceOrderId ?? orderId }

    public var payAmountFen: Int64 {
        if let amountFen { return amountFen }
        let unit = balancePriceFen ?? 0
        return unit * Int64(max(1, qty ?? 1))
    }

    public var canPay: Bool {
        bizStatus == .balancePending && expired != true && buyerMismatch != true
    }
}

public struct BalancePaymentCreateBody: Codable, Equatable, Sendable {
    public let provider: String

    public init(provider: String) {
        self.provider = provider
    }
}

public struct PresaleRefundDepositResult: Codable, Equatable, Sendable {
    public let presaleOrderId: Int64?
    public let bizStatus: PresaleBizStatus?
    public let refundFen: Int64?

    public init(
        presaleOrderId: Int64? = nil,
        bizStatus: PresaleBizStatus? = nil,
        refundFen: Int64? = nil
    ) {
        self.presaleOrderId = presaleOrderId
        self.bizStatus = bizStatus
        self.refundFen = refundFen
    }
}

// MARK: - Universal Link / deep link

/// Parses `https://{host}/pay/balance/{id}?t=` and short `/b/{code}` (design §5.3).
public struct BalancePayDeepLink: Equatable, Sendable {
    public let balanceOrderId: Int64?
    public let token: String?
    public let shortCode: String?
    public let rawURL: URL

    public init(
        balanceOrderId: Int64? = nil,
        token: String? = nil,
        shortCode: String? = nil,
        rawURL: URL
    ) {
        self.balanceOrderId = balanceOrderId
        self.token = token
        self.shortCode = shortCode
        self.rawURL = rawURL
    }

    public var hasOrderTarget: Bool { balanceOrderId != nil }
    public var hasShortCode: Bool { shortCode.map { !$0.isEmpty } ?? false }

    public static func parse(url: URL) -> BalancePayDeepLink? {
        let scheme = (url.scheme ?? "").lowercased()
        let host = (url.host ?? "").lowercased()
        let path = url.path
        let lowerPath = path.lowercased()
        let isAppScheme = scheme == "paddock43" || scheme == "velora"

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ names: String...) -> String? {
            for name in names {
                if let v = items.first(where: { $0.name.lowercased() == name.lowercased() })?.value,
                   !v.isEmpty {
                    return v
                }
            }
            return nil
        }

        let parts = path.split(separator: "/").map(String.init)
        let lowerParts = parts.map { $0.lowercased() }

        // /pay/balance/{order_id} or app host pay + path /balance/{id}
        if let payIdx = lowerParts.firstIndex(of: "pay"),
           payIdx + 1 < lowerParts.count,
           lowerParts[payIdx + 1] == "balance",
           payIdx + 2 < parts.count {
            let idStr = parts[payIdx + 2]
            let id = Int64(idStr)
            let matchesUniversal = lowerPath.contains("/pay/balance")
            let matchesApp = isAppScheme && (host == "pay" || matchesUniversal || lowerPath.contains("balance"))
            guard matchesUniversal || matchesApp || scheme == "https" || scheme == "http" else { return nil }
            guard id != nil || q("t", "token") != nil else { return nil }
            return BalancePayDeepLink(
                balanceOrderId: id,
                token: q("t", "token"),
                shortCode: nil,
                rawURL: url
            )
        }

        // Short link /b/{code}
        if let bIdx = lowerParts.firstIndex(of: "b"),
           bIdx + 1 < parts.count {
            let code = parts[bIdx + 1]
            guard code.count >= 6, code.count <= 8 else { return nil }
            let matches = lowerPath.contains("/b/") || (isAppScheme && host == "b")
            guard matches || scheme == "https" || scheme == "http" else { return nil }
            return BalancePayDeepLink(
                balanceOrderId: nil,
                token: q("t", "token"),
                shortCode: code,
                rawURL: url
            )
        }

        // App scheme: velora://pay/balance/{id}?t=
        if isAppScheme, host == "pay" || lowerPath.contains("balance") {
            if let idPart = parts.last, let id = Int64(idPart), parts.count >= 1 {
                return BalancePayDeepLink(
                    balanceOrderId: id,
                    token: q("t", "token"),
                    shortCode: nil,
                    rawURL: url
                )
            }
        }

        return nil
    }
}

// MARK: - Error codes / copy

public enum PresaleErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case missingIdempotencyKey = "missing_idempotency_key"
    case authRequired = "auth_required"
    case unauthorized
    case loginRequired = "login_required"
    case realNameRequired = "real_name_required"
    case creditTooLow = "credit_too_low"
    case accountRestricted = "account_restricted"
    case vipWindowClosed = "vip_window_closed"
    case saleNotStarted = "sale_not_started"
    case saleEnded = "sale_ended"
    case soldOut = "sold_out"
    case limitExceeded = "limit_exceeded"
    case addressRequired = "address_required"
    case presaleLaunchGated = "presale_launch_gated"
    case depositRatioExceeded = "deposit_ratio_exceeded"
    case balanceWindowTooShort = "balance_window_too_short"
    case notBalancePending = "not_balance_pending"
    case delayChoiceClosed = "delay_choice_closed"
    case delayLimitExceeded = "delay_limit_exceeded"
    case settleModeUndisclosed = "settle_mode_undisclosed"
    case balanceLinkExpired = "balance_link_expired"
    case overduePolicyNotReady = "overdue_policy_not_ready"
    case legalDepositKindRequired = "legal_deposit_kind_required"
    case illegalPresaleTransition = "illegal_presale_transition"
    case buyerMismatch = "buyer_mismatch"
    case rateLimited = "rate_limited"
    case capabilityDisabled = "capability_disabled"
    case featureDisabled = "feature_disabled"

    public var opensLogin: Bool {
        self == .authRequired || self == .unauthorized || self == .loginRequired
    }

    public var opensRealName: Bool { self == .realNameRequired }

    public var opensAddress: Bool { self == .addressRequired }

    public var fallbackMessage: String {
        switch self {
        case .missingIdempotencyKey: return "请重试"
        case .authRequired, .unauthorized, .loginRequired: return "请先登录"
        case .realNameRequired: return "请先完成实名认证"
        case .creditTooLow: return PresaleCopy.creditTooLow
        case .accountRestricted: return "账号受限，暂不可预售"
        case .vipWindowClosed: return PresaleCopy.vipWindowClosed
        case .saleNotStarted: return "定金尚未开始"
        case .saleEnded: return "定金已截止"
        case .soldOut: return "名额已满"
        case .limitExceeded: return "已达限购数量"
        case .addressRequired: return "请先设置收货地址"
        case .presaleLaunchGated: return PresaleCopy.gated
        case .depositRatioExceeded: return "定金比例超限"
        case .balanceWindowTooShort: return "补款窗口过短"
        case .notBalancePending: return PresaleCopy.notBalancePending
        case .delayChoiceClosed: return PresaleCopy.delayChoiceClosed
        case .delayLimitExceeded: return "延期次数已达上限"
        case .settleModeUndisclosed: return "结算方式未披露"
        case .balanceLinkExpired: return PresaleCopy.linkExpired
        case .overduePolicyNotReady: return PresaleCopy.gated
        case .legalDepositKindRequired: return "须选择定金/订金口径"
        case .illegalPresaleTransition: return "订单状态已变更，请刷新"
        case .buyerMismatch: return PresaleCopy.buyerMismatch
        case .rateLimited: return "操作过于频繁，请稍后再试"
        case .capabilityDisabled, .featureDisabled: return PresaleCopy.gated
        }
    }
}

public enum PresaleCopy {
    public static let pageTitle = "预售"
    public static let myBalanceTitle = "我的补款"
    public static let detailTitle = "预售详情"
    public static let payDeposit = "支付定金"
    public static let payBalance = "支付尾款"
    public static let confirmBalanceAmount = "确认尾款金额"
    public static let depositPaidWaiting = "已付定金 · 等待补款"
    public static let balancePaid = "已补款"
    public static let shipped = "已发货"
    public static let expired = "已逾期"
    public static let cancelled = "商家已取消"
    public static let refunded = "已退定金"
    public static let gated = "预售暂未开放"
    public static let ended = "预售已结束"
    public static let completeEligibility = "去完成资格"
    public static let creditTooLow = "信用分不足 60，暂不可付定金"
    public static let vipWindowClosed = "会员专属窗口未开放"
    public static let legalDingjin = "定金，逾期可能被扣除"
    public static let legalOrderingDeposit = "订金，逾期按规则退还"
    public static let settleOnShipDisclosure = "本场发货即结算，货款在发货后进入分账流程"
    public static let delayContinue = "继续等待"
    public static let delayRefund = "申请退定金"
    public static let delayChoiceCTA = "处理延期"
    public static let delayChoiceClosed = "延期退定金选择窗已关闭"
    public static let notBalancePending = "当前不可支付尾款"
    public static let linkExpired = "补款链接已过期，请从「我的补款」进入"
    public static let buyerMismatch = "请使用下单账号登录后再支付"
    public static let serverTimeHint = "以服务器时间为准"
    public static let weakNetRetry = "网络不稳定，可放心重试"
    public static let emptyOrders = "暂无预售补款"
    public static let emptyOrdersHint = "关注品牌发售日历"
    public static let addressLockedHint = "收货地址在付定金时已锁定"
    public static let balanceConfirmHint = "请确认尾款金额后再支付"
    public static let overdueHint = "逾期处理按发售规则执行"
}

// MARK: - Pure logic

public enum PresaleLogic {
    public static func countdownSeconds(until target: Date, serverNow: Date) -> Int {
        max(0, Int(target.timeIntervalSince(serverNow).rounded(.down)))
    }

    public static func formatCountdown(seconds: Int) -> String {
        let s = max(0, seconds)
        let d = s / 86400
        let h = (s % 86400) / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if d > 0 { return String(format: "%d天%02d:%02d:%02d", d, h, m, sec) }
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    public static func balanceDeadlineCountdownLine(seconds: Int) -> String {
        "\(formatCountdown(seconds: seconds)) · \(PresaleCopy.serverTimeHint)"
    }

    public static func isDepositWindowOpen(
        start: Date?,
        end: Date?,
        serverNow: Date
    ) -> Bool {
        if let start, serverNow < start { return false }
        if let end, serverNow >= end { return false }
        return true
    }

    public static func depositRatio(
        depositFen: Int64,
        balanceFen: Int64
    ) -> Double {
        let total = depositFen + balanceFen
        guard total > 0 else { return 0 }
        return Double(depositFen) / Double(total)
    }

    public static func isDepositRatioAllowed(
        depositFen: Int64,
        balanceFen: Int64,
        maxRatio: Double = PresaleConfigDefaults.depositRatioMax
    ) -> Bool {
        depositRatio(depositFen: depositFen, balanceFen: balanceFen) <= maxRatio + 1e-9
    }

    public static func balanceWindowHours(start: Date, end: Date) -> Double {
        end.timeIntervalSince(start) / 3600
    }

    public static func isBalanceWindowLongEnough(
        start: Date,
        end: Date,
        minHours: Int = PresaleConfigDefaults.balanceWindowMinHours
    ) -> Bool {
        balanceWindowHours(start: start, end: end) + 1e-9 >= Double(minHours)
    }

    public static func buyerVisibleTimeline(_ events: [PresaleTimelineEvent]) -> [PresaleTimelineEvent] {
        events.filter(\.isBuyerVisible)
    }

    public static func legalDepositCopy(_ kind: PresaleLegalDepositKind?) -> String? {
        kind?.displayCopy
    }

    public static func isDelayChoiceOpen(
        notice: PresaleDelayNotice?,
        order: PresaleOrderSummary?,
        serverNow: Date
    ) -> Bool {
        guard let status = order?.bizStatus, status.showsDelayChoice else { return false }
        if order?.delayChoice != nil { return false }
        let deadline = notice?.choiceDeadline ?? order?.delayChoiceDeadline
        guard let deadline else { return notice != nil }
        return serverNow < deadline
    }

    public static func depositChecklist(
        isLoggedIn: Bool,
        eligibility: PresaleEligibility?,
        hasAddress: Bool
    ) -> [PresaleDepositChecklistItem] {
        [
            .init(step: .login, done: isLoggedIn),
            .init(step: .realName, done: eligibility?.isRealNamed == true),
            .init(step: .credit, done: eligibility?.isCreditOk == true),
            .init(step: .address, done: hasAddress || eligibility?.addressReady == true),
        ]
    }

    public static func nextDepositStep(
        isLoggedIn: Bool,
        eligibility: PresaleEligibility?,
        hasAddress: Bool
    ) -> PresaleDepositStep? {
        depositChecklist(isLoggedIn: isLoggedIn, eligibility: eligibility, hasAddress: hasAddress)
            .first(where: { !$0.done })?
            .step
    }

    public static func resolveReleaseCTA(
        detail: PresaleReleaseDetail,
        serverNow: Date,
        isLoggedIn: Bool,
        hasAddress: Bool
    ) -> PresaleCTA {
        if detail.eligibility?.isLaunchGateOpen == false {
            return .gated
        }
        if let order = detail.myOrder {
            return resolveOrderCTA(order: order, delayNotice: detail.openDelayNotice, serverNow: serverNow)
        }
        if !isLoggedIn { return .login }
        if nextDepositStep(isLoggedIn: isLoggedIn, eligibility: detail.eligibility, hasAddress: hasAddress) != nil {
            return .completeEligibility
        }
        if let start = detail.depositStartAt, serverNow < start {
            return .waitDepositOpen
        }
        if let end = detail.depositEndAt, serverNow >= end {
            return .ended
        }
        return .payDeposit
    }

    public static func resolveOrderCTA(
        order: PresaleOrderSummary,
        delayNotice: PresaleDelayNotice? = nil,
        serverNow: Date
    ) -> PresaleCTA {
        let notice = delayNotice ?? order.openDelayNotice
        if isDelayChoiceOpen(notice: notice, order: order, serverNow: serverNow) {
            return .delayChoice
        }
        switch order.resolvedStatus {
        case .depositPending: return .payDeposit
        case .depositPaid: return .depositPaidWaiting
        case .balancePending: return .payBalance
        case .balancePaid: return .balancePaid
        case .shipped, .completed: return .shipped
        case .expired: return .expired
        case .merchantCancelled: return .cancelled
        case .buyerRefunded: return .refunded
        }
    }

    public static func listSubtitle(
        order: PresaleOrderSummary,
        serverNow: Date
    ) -> String {
        let cta = resolveOrderCTA(order: order, serverNow: serverNow)
        switch cta {
        case .payBalance:
            if let deadline = order.balanceDeadline {
                let sec = countdownSeconds(until: deadline, serverNow: serverNow)
                return balanceDeadlineCountdownLine(seconds: sec)
            }
            return "应付尾款 \(formatFen(order.amounts.balanceTotalFen))"
        case .payDeposit:
            return "应付定金 \(formatFen(order.amounts.depositTotalFen))"
        case .delayChoice:
            return PresaleCopy.delayChoiceCTA
        case .balancePaid, .shipped:
            if let delivery = order.resolvedDeliveryAt {
                return "预计发货 \(shortDate(delivery))"
            }
            return cta.buttonTitle
        case .expired:
            return PresaleCopy.overdueHint
        default:
            return order.resolvedStatus.displayLabel
        }
    }

    public static func formatFen(_ fen: Int64) -> String {
        let yuan = Double(fen) / 100
        if fen % 100 == 0 {
            return String(format: "¥%.0f", yuan)
        }
        return String(format: "¥%.2f", yuan)
    }

    public static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}
