import Foundation

// MARK: - Deposit preauth & penalty (DES-v1.3-08-02 PAY-05/06/07/08 / D30)

/// Product defaults (design §6 / §15). Hot-config on server; client mirrors for UX.
public enum DepositConfigDefaults {
    public static let bidRateBp = 1_000
    public static let bidMinFen: Int64 = 5_000
    public static let bidMaxFen: Int64 = 200_000
    public static let lotteryDefaultFen: Int64 = 20_000
    public static let sellerPersonalFen: Int64 = 50_000
    public static let sellerProxyFen: Int64 = 500_000
    public static let sellerBrandFen: Int64 = 1_000_000
    public static let sellerPresaleExtraFen: Int64 = 500_000
    public static let sellerExitDays = 30
    public static let preauthEnabledKey = "payment.preauth.enabled"
    public static let preauthEnabledDefault = false
    public static let penaltyObligeeBp = 8_000
    public static let penaltyPlatformBp = 2_000
    public static let notifyCode = "N-26"
    public static let meEntryKey = "deposit"
    public static let meSellerEntryKey = "seller_deposit"
    public static let pendingTimeoutMinutes = 15
    public static let creditBidFloor = 80
}

// MARK: - Status (design §3 / §4)

/// `deposits.status`: pending → frozen → released / deducted / partially_deducted.
/// Legacy: held→frozen, forfeited→deducted, refunded→released, applied→released (no longer offsets goods).
public enum DepositStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pending
    case frozen
    case released
    case deducted
    case partiallyDeducted = "partially_deducted"

    public static func normalize(_ raw: String?) -> DepositStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = DepositStatus(rawValue: s) { return exact }
        switch s {
        case "held", "holding", "authorized", "captured":
            return .frozen
        case "forfeited", "forfeit":
            return .deducted
        case "refunded", "refund", "cancelled", "canceled", "closed":
            return .released
        case "applied", "legacy_applied_to_order", "applied_to_order":
            return .released
        case "partial", "partial_deducted", "partially-deducted":
            return .partiallyDeducted
        case "deposit_pending", "paying", "processing":
            return .pending
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .pending: return "处理中"
        case .frozen: return "已冻结"
        case .released: return "已解冻"
        case .deducted: return "已扣除"
        case .partiallyDeducted: return "部分扣除"
        }
    }

    /// PlaceBid / enroll / publish gate — only frozen counts (design §5.9).
    public var allowsBidding: Bool { self == .frozen }
    public var allowsPublish: Bool { self == .frozen }
    public var isTerminal: Bool {
        switch self {
        case .released, .deducted, .partiallyDeducted: return true
        case .pending, .frozen: return false
        }
    }
    public var isActiveFreeze: Bool { self == .frozen || self == .partiallyDeducted }
    public var showsProcessing: Bool { self == .pending }
}

// MARK: - Type & method

public enum DepositType: String, Codable, Sendable, CaseIterable, Equatable {
    case bid
    case lottery
    case seller

    public static func normalize(_ raw: String?) -> DepositType? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = DepositType(rawValue: s) { return exact }
        switch s {
        case "lot", "auction", "bidding", "lot_deposit":
            return .bid
        case "draw", "raffle":
            return .lottery
        case "seller_deposit", "onboarding", "merchant":
            return .seller
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .bid: return "参拍保证金"
        case .lottery: return "抽签保证金"
        case .seller: return "卖家保证金"
        }
    }
}

/// Channel path (design §5.2): preauth vs independent payment. UX copy is unified — never expose tech diff.
public enum DepositMethod: String, Codable, Sendable, CaseIterable, Equatable {
    case preauth
    case payment

    public static func normalize(_ raw: String?) -> DepositMethod? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = DepositMethod(rawValue: s) { return exact }
        switch s {
        case "auth", "authorization", "pre_auth", "pre-authorization", "freeze":
            return .preauth
        case "pay", "order", "deposit", "independent", "escrow":
            return .payment
        default:
            return nil
        }
    }

    /// Design §5.2 / §9 — both paths read as「冻结保证金」.
    public var userFacingVerb: String { DepositCopy.freezeVerb }

    public var displayLabel: String { DepositCopy.freezeVerb }
}

/// PaymentKind additions (design §3) — client labels only; server owns routing.
public enum DepositPaymentKind: String, Codable, Sendable, CaseIterable, Equatable {
    case deposit
    case depositPreauth = "deposit_preauth"
    case depositCapture = "deposit_capture"
    case sellerDeposit = "seller_deposit"

    public var displayLabel: String {
        switch self {
        case .deposit, .depositPreauth, .sellerDeposit:
            return DepositCopy.freezeVerb
        case .depositCapture:
            return "保证金扣除"
        }
    }
}

// MARK: - Penalty events (PAY-08)

public enum PenaltyEventCode: String, Codable, Sendable, CaseIterable, Equatable {
    case buyerNonPayAuction = "buyer_non_pay_auction"
    case buyerNonPayLottery = "buyer_non_pay_lottery"
    case sellerRefuseShip = "seller_refuse_ship"
    case sellerConcealFlaw = "seller_conceal_flaw"
    case buyerMaliciousDamage = "buyer_malicious_damage"

    public static func normalize(_ raw: String?) -> PenaltyEventCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = PenaltyEventCode(rawValue: s) { return exact }
        switch s {
        case "buyer_non_pay", "auction_default", "non_pay_auction":
            return .buyerNonPayAuction
        case "lottery_default", "non_pay_lottery":
            return .buyerNonPayLottery
        case "refuse_ship", "induce_offline":
            return .sellerRefuseShip
        case "conceal_flaw", "hidden_defect":
            return .sellerConcealFlaw
        case "malicious_damage", "buyer_damage":
            return .buyerMaliciousDamage
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .buyerNonPayAuction: return "拍卖逾期未付"
        case .buyerNonPayLottery: return "抽签中签逾期未付"
        case .sellerRefuseShip: return "卖家拒发/诱导线下"
        case .sellerConcealFlaw: return "卖家隐瞒瑕疵"
        case .buyerMaliciousDamage: return "买家恶意损毁"
        }
    }

    /// Short reason line for N-26 style notices (no internal bp ratios — design §9).
    public var noticeReason: String {
        switch self {
        case .buyerNonPayAuction: return "因逾期未付，参拍保证金已按规则扣除"
        case .buyerNonPayLottery: return "因中签后逾期未付，抽签保证金已按规则扣除"
        case .sellerRefuseShip: return "因拒发或诱导线下成交，卖家保证金已按规则扣除"
        case .sellerConcealFlaw: return "因隐瞒瑕疵，卖家保证金已按规则扣除"
        case .buyerMaliciousDamage: return "因恶意损毁，保证金已按规则扣除"
        }
    }

    public var deductsBuyer: Bool {
        switch self {
        case .buyerNonPayAuction, .buyerNonPayLottery, .buyerMaliciousDamage: return true
        case .sellerRefuseShip, .sellerConcealFlaw: return false
        }
    }
}

// MARK: - Error codes (design §6 / §7)

public enum DepositErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case depositNotFrozen = "deposit_not_frozen"
    case realNameRequired = "real_name_required"
    case creditTooLow = "credit_too_low"
    case sellerDepositInsufficient = "seller_deposit_insufficient"
    case alreadySufficient = "already_sufficient"
    case openOrdersExist = "open_orders_exist"
    case exitCooling = "exit_cooling"
    case payoutPending = "payout_pending"
    case mockNotAllowed = "mock_not_allowed"
    case missingIdempotencyKey = "missing_idempotency_key"

    public var fallbackMessage: String {
        switch self {
        case .depositNotFrozen: return DepositCopy.needFreezeFirst
        case .realNameRequired: return "请先完成实名认证"
        case .creditTooLow: return DepositCopy.creditTooLow
        case .sellerDepositInsufficient: return DepositCopy.sellerGapTitle
        case .alreadySufficient: return DepositCopy.alreadySufficient
        case .openOrdersExist: return DepositCopy.openOrdersExist
        case .exitCooling: return DepositCopy.exitCooling
        case .payoutPending: return DepositCopy.payoutPending
        case .mockNotAllowed: return "当前环境不可用模拟支付缴纳保证金"
        case .missingIdempotencyKey: return "请重试"
        }
    }

    public var opensDepositSheet: Bool { self == .depositNotFrozen }
    public var opensRealName: Bool { self == .realNameRequired }
    public var opensSellerDeposit: Bool { self == .sellerDepositInsufficient }
    public var opensCreditHelp: Bool { self == .creditTooLow }
}

// MARK: - Copy (design §9)

public enum DepositCopy {
    /// Unified user-facing verb for preauth + payment (design §5.2).
    public static let freezeVerb = "冻结保证金"
    public static let freezeTitle = "冻结保证金"
    public static let bidSheetTitle = "参拍保证金"
    public static let bidSheetHint = "未中拍全额退回；中拍付款后解冻，货款另付全额。"
    public static let bidSheetRefundHint = "未中拍全退"
    public static let releaseArriveHint = "解冻到账可能为 T+0～T+1"
    public static let processingHint = "处理中，请稍候"
    public static let emptyTitle = "暂无冻结"
    public static let emptyHint = "参拍或报名时将冻结保证金，未中拍/未中签后解冻"
    public static let needFreezeFirst = "请先冻结保证金"
    public static let creditTooLow = "信用分不足，提升信用后再参拍"
    public static let creditHelpCTA = "提升信用"
    public static let listTitle = "我的保证金"
    public static let sellerPageTitle = "卖家保证金"
    public static let sellerGapTitle = "补缴保证金后可发布"
    public static let sellerGapHint = "被扣后须补足差额才能继续发布"
    public static let sellerTopUpCTA = "补缴保证金"
    public static let sellerExitCTA = "退出卖家并申请退还"
    public static let sellerExitCoolingHint = "退出冷静期剩余"
    public static let sellerExitDaysSuffix = "天"
    public static let alreadySufficient = "保证金已足额"
    public static let openOrdersExist = "仍有进行中订单，暂不可退出"
    public static let exitCooling = "退出冷静期内，期满后自动退还"
    public static let payoutPending = "赔付处理中，资金不会进入平台对公户"
    public static let deductProcessing = "扣除到账可能延迟，展示处理中"
    public static let brandPresaleGap = "品牌预售保障金不足，请先补缴"
    public static let freezeSucceeded = "保证金已冻结，可以出价了"
    public static let topUpSucceeded = "补缴成功"
    public static let exitRequested = "已申请退出，冷静期满后退还"
    public static let amountServerAuthoritative = "冻结金额以服务端为准"
    public static let noTechDiffHint = "渠道将冻结相应金额"
}

// MARK: - Seller gap / required amounts (PAY-07 / B-07)

public enum SellerDepositTier: String, Codable, Sendable, CaseIterable, Equatable {
    case personal
    case proxyAgent = "proxy_agent"
    case brand

    public static func normalize(_ raw: String?) -> SellerDepositTier? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = SellerDepositTier(rawValue: s) { return exact }
        switch s {
        case "individual", "person", "seller_personal":
            return .personal
        case "proxy", "agent", "专职代拍", "proxy-agent":
            return .proxyAgent
        case "merchant", "brand_seller", "企业", "品牌":
            return .brand
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .personal: return "个人卖家"
        case .proxyAgent: return "专职代拍"
        case .brand: return "品牌商家"
        }
    }

    public var requiredFen: Int64 {
        switch self {
        case .personal: return DepositConfigDefaults.sellerPersonalFen
        case .proxyAgent: return DepositConfigDefaults.sellerProxyFen
        case .brand: return DepositConfigDefaults.sellerBrandFen
        }
    }
}

public enum SellerDepositLogic {
    /// Gap that blocks publish (design §5.3 / §5.8).
    public static func gapAmount(required: Int64, held: Int64) -> Int64 {
        max(0, required - max(0, held))
    }

    public static func blocksPublish(required: Int64, held: Int64) -> Bool {
        gapAmount(required: required, held: held) > 0
    }

    public static func gapMessage(required: Int64, held: Int64, isPresaleExtra: Bool = false) -> String {
        let gap = gapAmount(required: required, held: held)
        if gap <= 0 { return DepositCopy.alreadySufficient }
        if isPresaleExtra { return DepositCopy.brandPresaleGap }
        let yuan = DepositLogic.formatYuan(gap)
        return "\(DepositCopy.sellerGapTitle)（缺口 ¥\(yuan)）"
    }

    public static func requiredFen(for tier: SellerDepositTier, includePresaleExtra: Bool = false) -> Int64 {
        let base = tier.requiredFen
        return includePresaleExtra ? base + DepositConfigDefaults.sellerPresaleExtraFen : base
    }

    /// Exit cooling remaining days (ceil); nil when not exiting.
    public static func exitRemainingDays(exitDueAt: Date?, now: Date = Date()) -> Int? {
        guard let due = exitDueAt else { return nil }
        let sec = due.timeIntervalSince(now)
        if sec <= 0 { return 0 }
        return Int(ceil(sec / 86_400))
    }

    public static func exitCoolingMessage(remainingDays: Int) -> String {
        if remainingDays <= 0 { return DepositCopy.exitRequested }
        return "\(DepositCopy.sellerExitCoolingHint) \(remainingDays) \(DepositCopy.sellerExitDaysSuffix)"
    }
}

// MARK: - Shared helpers

public enum DepositLogic {
    public static func formatYuan(_ fen: Int64) -> String {
        let yuan = Double(fen) / 100.0
        if fen % 100 == 0 {
            return String(format: "%.0f", yuan)
        }
        if fen % 10 == 0 {
            return String(format: "%.1f", yuan)
        }
        return String(format: "%.2f", yuan)
    }

    /// Bid deposit floor preview (same as AuctionDepositFormula / 8.3).
    public static func bidRequiredFen(startPriceFen: Int64) -> Int64 {
        let raw = startPriceFen * Int64(DepositConfigDefaults.bidRateBp) / 10_000
        return min(DepositConfigDefaults.bidMaxFen, max(DepositConfigDefaults.bidMinFen, raw))
    }

    public static func methodUserCopy(_ method: DepositMethod?) -> String {
        // Always unified — ignore channel method for display (design §5.2 / §9).
        _ = method
        return DepositCopy.freezeVerb
    }

    public static func isFrozenEnoughForBid(statusRaw: String?) -> Bool {
        DepositStatus.normalize(statusRaw)?.allowsBidding == true
    }
}

// MARK: - DTOs

public struct Deposit: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let userId: Int64?
    public let type: DepositType
    public let refId: Int64?
    public let amount: Int64
    public let method: DepositMethod?
    public let status: DepositStatus
    public let deductedAmount: Int64?
    public let releasedAmount: Int64?
    public let paymentId: Int64?
    public let lotId: Int64?
    public let buyerId: Int64?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let title: String?

    public init(
        id: Int64,
        userId: Int64? = nil,
        type: DepositType = .bid,
        refId: Int64? = nil,
        amount: Int64,
        method: DepositMethod? = nil,
        status: DepositStatus = .pending,
        deductedAmount: Int64? = nil,
        releasedAmount: Int64? = nil,
        paymentId: Int64? = nil,
        lotId: Int64? = nil,
        buyerId: Int64? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.refId = refId
        self.amount = amount
        self.method = method
        self.status = status
        self.deductedAmount = deductedAmount
        self.releasedAmount = releasedAmount
        self.paymentId = paymentId
        self.lotId = lotId
        self.buyerId = buyerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, type, refId, amount, method, status
        case deductedAmount, releasedAmount, paymentId, lotId, buyerId
        case createdAt, updatedAt, title
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        userId = try c.decodeIfPresent(Int64.self, forKey: .userId)
            ?? c.decodeIfPresent(Int64.self, forKey: .buyerId)
        let rawType = try c.decodeIfPresent(String.self, forKey: .type)
        type = DepositType.normalize(rawType) ?? .bid
        refId = try c.decodeIfPresent(Int64.self, forKey: .refId)
            ?? c.decodeIfPresent(Int64.self, forKey: .lotId)
        amount = try c.decode(Int64.self, forKey: .amount)
        method = DepositMethod.normalize(try c.decodeIfPresent(String.self, forKey: .method))
        let rawStatus = try c.decodeIfPresent(String.self, forKey: .status)
        status = DepositStatus.normalize(rawStatus) ?? .pending
        deductedAmount = try c.decodeIfPresent(Int64.self, forKey: .deductedAmount)
        releasedAmount = try c.decodeIfPresent(Int64.self, forKey: .releasedAmount)
        paymentId = try c.decodeIfPresent(Int64.self, forKey: .paymentId)
        lotId = try c.decodeIfPresent(Int64.self, forKey: .lotId) ?? refId
        buyerId = try c.decodeIfPresent(Int64.self, forKey: .buyerId) ?? userId
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        title = try c.decodeIfPresent(String.self, forKey: .title)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encode(type.rawValue, forKey: .type)
        try c.encodeIfPresent(refId, forKey: .refId)
        try c.encode(amount, forKey: .amount)
        try c.encodeIfPresent(method?.rawValue, forKey: .method)
        try c.encode(status.rawValue, forKey: .status)
        try c.encodeIfPresent(deductedAmount, forKey: .deductedAmount)
        try c.encodeIfPresent(releasedAmount, forKey: .releasedAmount)
        try c.encodeIfPresent(paymentId, forKey: .paymentId)
        try c.encodeIfPresent(lotId, forKey: .lotId)
        try c.encodeIfPresent(buyerId, forKey: .buyerId)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(title, forKey: .title)
    }

    /// Method is never shown as tech path — always「冻结保证金」.
    public var methodUserLabel: String { DepositLogic.methodUserCopy(method) }

    public var statusLabel: String { status.displayLabel }

    public var typeLabel: String { type.displayLabel }

    public var allowsBidding: Bool { status.allowsBidding }
}

/// GET `/lots/{id}/deposit` (design §6).
public struct LotDepositInfo: Codable, Equatable, Sendable {
    public let deposit: Deposit?
    public let required: Bool?
    public let requiredAmount: Int64?
    public let amount: Int64?
    public let method: DepositMethod?
    public let status: DepositStatus?

    public init(
        deposit: Deposit? = nil,
        required: Bool? = nil,
        requiredAmount: Int64? = nil,
        amount: Int64? = nil,
        method: DepositMethod? = nil,
        status: DepositStatus? = nil
    ) {
        self.deposit = deposit
        self.required = required
        self.requiredAmount = requiredAmount
        self.amount = amount
        self.method = method
        self.status = status
    }

    public var resolvedAmount: Int64 {
        if let a = deposit?.amount, a > 0 { return a }
        if let a = requiredAmount, a > 0 { return a }
        if let a = amount, a > 0 { return a }
        return 0
    }

    public var resolvedStatus: DepositStatus? {
        deposit?.status ?? status
    }

    public var isFrozen: Bool {
        resolvedStatus?.allowsBidding == true
    }

    /// Preferred freeze amount for the half-sheet (server authoritative).
    public var sheetAmount: Int64 { resolvedAmount }
}

/// GET `/me/deposits`.
public struct MeDepositsResponse: Codable, Equatable, Sendable {
    public let items: [Deposit]
    public let sellerAccount: SellerDepositAccount?
    public let nextCursor: String?

    public init(items: [Deposit] = [], sellerAccount: SellerDepositAccount? = nil, nextCursor: String? = nil) {
        self.items = items
        self.sellerAccount = sellerAccount
        self.nextCursor = nextCursor
    }

    enum CodingKeys: String, CodingKey {
        case items, deposits, list, sellerAccount, nextCursor, cursor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try c.decodeIfPresent([Deposit].self, forKey: .items) {
            self.items = items
        } else if let deposits = try c.decodeIfPresent([Deposit].self, forKey: .deposits) {
            self.items = deposits
        } else if let list = try c.decodeIfPresent([Deposit].self, forKey: .list) {
            self.items = list
        } else {
            self.items = []
        }
        sellerAccount = try c.decodeIfPresent(SellerDepositAccount.self, forKey: .sellerAccount)
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
            ?? c.decodeIfPresent(String.self, forKey: .cursor)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encodeIfPresent(sellerAccount, forKey: .sellerAccount)
        try c.encodeIfPresent(nextCursor, forKey: .nextCursor)
    }
}

/// `seller_deposit_accounts` projection (design §3 / §5.8).
public struct SellerDepositAccount: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64 { userId ?? 0 }
    public let userId: Int64?
    public let requiredAmount: Int64
    public let heldAmount: Int64
    public let gapAmount: Int64
    public let sellerType: SellerDepositTier?
    public let status: DepositStatus?
    public let exitRequestedAt: Date?
    public let exitDueAt: Date?
    public let lastOrderCompletedAt: Date?

    public init(
        userId: Int64? = nil,
        requiredAmount: Int64,
        heldAmount: Int64,
        gapAmount: Int64? = nil,
        sellerType: SellerDepositTier? = nil,
        status: DepositStatus? = nil,
        exitRequestedAt: Date? = nil,
        exitDueAt: Date? = nil,
        lastOrderCompletedAt: Date? = nil
    ) {
        self.userId = userId
        self.requiredAmount = requiredAmount
        self.heldAmount = heldAmount
        self.gapAmount = gapAmount ?? SellerDepositLogic.gapAmount(required: requiredAmount, held: heldAmount)
        self.sellerType = sellerType
        self.status = status
        self.exitRequestedAt = exitRequestedAt
        self.exitDueAt = exitDueAt
        self.lastOrderCompletedAt = lastOrderCompletedAt
    }

    enum CodingKeys: String, CodingKey {
        case userId, requiredAmount, heldAmount, gapAmount, sellerType, status
        case exitRequestedAt, exitDueAt, lastOrderCompletedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(Int64.self, forKey: .userId)
        requiredAmount = try c.decodeIfPresent(Int64.self, forKey: .requiredAmount) ?? 0
        heldAmount = try c.decodeIfPresent(Int64.self, forKey: .heldAmount) ?? 0
        let decodedGap = try c.decodeIfPresent(Int64.self, forKey: .gapAmount)
        gapAmount = decodedGap ?? SellerDepositLogic.gapAmount(required: requiredAmount, held: heldAmount)
        sellerType = SellerDepositTier.normalize(try c.decodeIfPresent(String.self, forKey: .sellerType))
        status = DepositStatus.normalize(try c.decodeIfPresent(String.self, forKey: .status))
        exitRequestedAt = try c.decodeIfPresent(Date.self, forKey: .exitRequestedAt)
        exitDueAt = try c.decodeIfPresent(Date.self, forKey: .exitDueAt)
        lastOrderCompletedAt = try c.decodeIfPresent(Date.self, forKey: .lastOrderCompletedAt)
    }

    public var blocksPublish: Bool { SellerDepositLogic.blocksPublish(required: requiredAmount, held: heldAmount) }

    public var gapMessage: String {
        SellerDepositLogic.gapMessage(required: requiredAmount, held: heldAmount)
    }

    public var isExiting: Bool { exitRequestedAt != nil || exitDueAt != nil }

    public var exitRemainingDays: Int? {
        SellerDepositLogic.exitRemainingDays(exitDueAt: exitDueAt)
    }

    public var exitMessage: String? {
        guard isExiting else { return nil }
        if let days = exitRemainingDays {
            return SellerDepositLogic.exitCoolingMessage(remainingDays: days)
        }
        return DepositCopy.exitCooling
    }
}

public struct SellerDepositPaymentRequest: Codable, Equatable, Sendable {
    public let amount: Int64?
    public let provider: String

    public init(amount: Int64? = nil, provider: String) {
        self.amount = amount
        self.provider = provider
    }
}

public struct SellerDepositExitResponse: Codable, Equatable, Sendable {
    public let status: String?
    public let exitDueAt: Date?
    public let message: String?

    public init(status: String? = nil, exitDueAt: Date? = nil, message: String? = nil) {
        self.status = status
        self.exitDueAt = exitDueAt
        self.message = message
    }

    public var remainingDays: Int? {
        SellerDepositLogic.exitRemainingDays(exitDueAt: exitDueAt)
    }
}

/// Penalty rule row (admin / display; App rarely edits).
public struct PenaltyRule: Codable, Equatable, Sendable, Identifiable {
    public var id: String { eventCode.rawValue }
    public let eventCode: PenaltyEventCode
    public let obligeeBp: Int
    public let platformBp: Int
    public let creditDelta: Int?
    public let minFen: Int64?
    public let enabled: Bool

    public init(
        eventCode: PenaltyEventCode,
        obligeeBp: Int = DepositConfigDefaults.penaltyObligeeBp,
        platformBp: Int = DepositConfigDefaults.penaltyPlatformBp,
        creditDelta: Int? = nil,
        minFen: Int64? = nil,
        enabled: Bool = true
    ) {
        self.eventCode = eventCode
        self.obligeeBp = obligeeBp
        self.platformBp = platformBp
        self.creditDelta = creditDelta
        self.minFen = minFen
        self.enabled = enabled
    }

    public var displayLabel: String { eventCode.displayLabel }
}
