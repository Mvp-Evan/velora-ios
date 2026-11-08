import Foundation

// MARK: - Spot release / rush (DES-v1.3-06-01 REL-01/10/12/13 / D23)

/// Product defaults (design §5 / §13 / §15). Hot-config on server; client mirrors for UX.
public enum SpotReleaseConfigDefaults {
    public static let payWindowSec = 900
    public static let holdGraceSec = 60
    public static let limitPerUserDefault = 1
    public static let limitPerUserMax = 5
    public static let exclusiveDepositDefaultFen: Int64 = 20_000
    /// Design §5.3 — skew > 2s shows「以服务器时间为准」hint.
    public static let clockSkewWarnMs: Int64 = 2_000
    public static let pollBeforeSaleSec = 30
    public static let pollNearSaleWindowSec = 10
    public static let pollNearSaleSec = 1
    public static let pollLiveSec = 3
    public static let minStartAheadMinutes = 5
    public static let shipHoursAfterPay = 48
    public static let orderType = "spot_release"
    public static let launchGateKey = "feature_flags.spot_release"
}

// MARK: - Status / mode / hold

/// `release.status` (design §4).
public enum SpotReleaseStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case draft
    case scheduled
    case live
    case soldOut = "sold_out"
    case ended
    case converted

    public var displayLabel: String {
        switch self {
        case .draft: return "草稿"
        case .scheduled: return "即将开售"
        case .live: return "抢购中"
        case .soldOut: return "已售罄"
        case .ended: return "已结束"
        case .converted: return "已转现货"
        }
    }

    public var isTerminalEmpty: Bool {
        self == .soldOut || self == .ended
    }
}

/// `release.mode` — this module owns `spot` (design §3).
public enum SpotReleaseMode: String, Codable, Sendable, CaseIterable, Equatable {
    case spot
    case lottery
    case presale

    public var displayLabel: String {
        switch self {
        case .spot: return "现货"
        case .lottery: return "抽签"
        case .presale: return "预售"
        }
    }
}

/// `release_hold.status` (design §3).
public enum SpotReleaseHoldStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case holding
    case confirmed
    case released
    case expired
}

// MARK: - SKU / VIP window / eligibility

public struct SpotReleaseSKU: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let skuCode: String?
    public let style: String?
    public let color: String?
    public let edition: String?
    public let stockTotal: Int?
    public let stockReserved: Int?
    public let stockSold: Int?
    public let remaining: Int?
    public let priceFen: Int64?

    public init(
        id: Int64,
        skuCode: String? = nil,
        style: String? = nil,
        color: String? = nil,
        edition: String? = nil,
        stockTotal: Int? = nil,
        stockReserved: Int? = nil,
        stockSold: Int? = nil,
        remaining: Int? = nil,
        priceFen: Int64? = nil
    ) {
        self.id = id
        self.skuCode = skuCode
        self.style = style
        self.color = color
        self.edition = edition
        self.stockTotal = stockTotal
        self.stockReserved = stockReserved
        self.stockSold = stockSold
        self.remaining = remaining
        self.priceFen = priceFen
    }

    public var displayName: String {
        let parts = [style, color, edition].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        if let code = skuCode, !code.isEmpty { return code }
        return "SKU #\(id)"
    }

    /// Prefer server `remaining`; else stock_total − reserved − sold.
    public var resolvedRemaining: Int {
        if let remaining { return max(0, remaining) }
        let total = stockTotal ?? 0
        let reserved = stockReserved ?? 0
        let sold = stockSold ?? 0
        return max(0, total - reserved - sold)
    }
}

/// `release_vip_window` row (design §3 / §5.6).
public struct SpotReleaseVIPWindow: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let minLevel: Int
    public let openAt: Date
    public let levelName: String?

    public var id: Int { minLevel }

    public init(minLevel: Int, openAt: Date, levelName: String? = nil) {
        self.minLevel = minLevel
        self.openAt = openAt
        self.levelName = levelName
    }

    public var displayLabel: String {
        if let name = levelName, !name.isEmpty {
            return minLevel <= 0 ? "公开场" : "Lv.\(minLevel) \(name)"
        }
        return minLevel <= 0 ? "公开场" : "Lv.\(minLevel)"
    }
}

/// Buyer eligibility on detail (`user_eligibility`, design §5.5 / §6).
public struct SpotReleaseEligibility: Codable, Equatable, Sendable {
    public let realNamed: Bool?
    public let depositFrozen: Bool?
    public let quotaLeft: Int?
    public let vipLevel: Int?
    public let reserved: Bool?
    public let purchasedQty: Int?

    public init(
        realNamed: Bool? = nil,
        depositFrozen: Bool? = nil,
        quotaLeft: Int? = nil,
        vipLevel: Int? = nil,
        reserved: Bool? = nil,
        purchasedQty: Int? = nil
    ) {
        self.realNamed = realNamed
        self.depositFrozen = depositFrozen
        self.quotaLeft = quotaLeft
        self.vipLevel = vipLevel
        self.reserved = reserved
        self.purchasedQty = purchasedQty
    }

    public var isRealNamed: Bool { realNamed == true }
    public var isDepositFrozen: Bool { depositFrozen == true }
    public var isReserved: Bool { reserved == true }
    public var resolvedVipLevel: Int { vipLevel ?? 0 }
}

/// `next_window` when VIP window not yet open (design §5.4 / §5.6).
public struct SpotReleaseNextWindow: Codable, Equatable, Sendable {
    public let openAt: Date?
    public let minLevel: Int?
    public let levelName: String?
    public let message: String?

    public init(
        openAt: Date? = nil,
        minLevel: Int? = nil,
        levelName: String? = nil,
        message: String? = nil
    ) {
        self.openAt = openAt
        self.minLevel = minLevel
        self.levelName = levelName
        self.message = message
    }
}

/// One step in the exclusive checklist (design §5.5 / §9).
public enum SpotReleaseExclusiveStep: String, Sendable, Equatable, CaseIterable {
    case login
    case realName
    case deposit

    public var title: String {
        switch self {
        case .login: return "登录"
        case .realName: return "实名认证"
        case .deposit: return "冻结保证金"
        }
    }

    public var actionTitle: String {
        switch self {
        case .login: return "去登录"
        case .realName: return "去实名"
        case .deposit: return "去冻结保证金"
        }
    }
}

public struct SpotReleaseExclusiveChecklistItem: Equatable, Sendable, Identifiable {
    public let step: SpotReleaseExclusiveStep
    public let done: Bool

    public var id: String { step.rawValue }

    public init(step: SpotReleaseExclusiveStep, done: Bool) {
        self.step = step
        self.done = done
    }
}

/// Primary bottom CTA mode (design §9).
public enum SpotReleaseCTA: String, Sendable, Equatable {
    case login
    case reserve
    case reservedWaiting
    case waitSaleOpen
    case completeEligibility
    case waitVIPWindow
    case rush
    case soldOut
    case ended
    case converting

    public var buttonTitle: String {
        switch self {
        case .login: return "登录后预约"
        case .reserve: return "预约提醒"
        case .reservedWaiting: return "已预约"
        case .waitSaleOpen: return "即将开售"
        case .completeEligibility: return SpotReleaseCopy.completeEligibility
        case .waitVIPWindow: return SpotReleaseCopy.waitVIPWindow
        case .rush: return SpotReleaseCopy.rush
        case .soldOut: return SpotReleaseCopy.soldOut
        case .ended: return SpotReleaseCopy.ended
        case .converting: return "预售剩余"
        }
    }

    public var isPrimaryAction: Bool {
        switch self {
        case .login, .reserve, .completeEligibility, .rush: return true
        default: return false
        }
    }
}

// MARK: - Detail (GET /api/v1/releases/{id})

/// Spot release detail aggregate (design §6).
public struct SpotReleaseDetail: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let merchantId: Int64?
    public let listingId: Int64?
    public let brandId: Int64?
    public let title: String?
    public let cover: String?
    public let mode: SpotReleaseMode?
    public let status: SpotReleaseStatus?
    public let startAt: Date?
    public let endAt: Date?
    public let startAtVersion: Int64?
    public let limitPerUser: Int?
    public let exclusive: Bool?
    public let exclusiveQuota: Int?
    public let exclusiveDepositFen: Int64?
    public let exclusivePin: Bool?
    public let inventoryPoolId: Int64?
    public let convertedFromReleaseId: Int64?
    public let skus: [SpotReleaseSKU]
    public let vipWindows: [SpotReleaseVIPWindow]
    public let eligibility: SpotReleaseEligibility?
    public let nextWindow: SpotReleaseNextWindow?
    public let remaining: Int?
    public let saleOpen: Bool?
    public let reserved: Bool?
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
        mode: SpotReleaseMode? = nil,
        status: SpotReleaseStatus? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        startAtVersion: Int64? = nil,
        limitPerUser: Int? = nil,
        exclusive: Bool? = nil,
        exclusiveQuota: Int? = nil,
        exclusiveDepositFen: Int64? = nil,
        exclusivePin: Bool? = nil,
        inventoryPoolId: Int64? = nil,
        convertedFromReleaseId: Int64? = nil,
        skus: [SpotReleaseSKU] = [],
        vipWindows: [SpotReleaseVIPWindow] = [],
        eligibility: SpotReleaseEligibility? = nil,
        nextWindow: SpotReleaseNextWindow? = nil,
        remaining: Int? = nil,
        saleOpen: Bool? = nil,
        reserved: Bool? = nil,
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
        self.startAt = startAt
        self.endAt = endAt
        self.startAtVersion = startAtVersion
        self.limitPerUser = limitPerUser
        self.exclusive = exclusive
        self.exclusiveQuota = exclusiveQuota
        self.exclusiveDepositFen = exclusiveDepositFen
        self.exclusivePin = exclusivePin
        self.inventoryPoolId = inventoryPoolId
        self.convertedFromReleaseId = convertedFromReleaseId
        self.skus = skus
        self.vipWindows = vipWindows
        self.eligibility = eligibility
        self.nextWindow = nextWindow
        self.remaining = remaining
        self.saleOpen = saleOpen
        self.reserved = reserved
        self.serverNow = serverNow
        self.serverNowMs = serverNowMs
        self.serverTime = serverTime
        self.serverTimeMs = serverTimeMs
        self.version = version
    }

    enum CodingKeys: String, CodingKey {
        case id, merchantId, listingId, brandId, title, cover, mode, status
        case startAt, endAt, startAtVersion, limitPerUser
        case exclusive, exclusiveQuota, exclusiveDepositFen, exclusivePin
        case inventoryPoolId, convertedFromReleaseId
        case skus, vipWindows, eligibility, userEligibility, nextWindow
        case remaining, saleOpen, reserved, viewerReserved
        case serverNow, serverNowMs, serverTime, serverTimeMs, version
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        merchantId = try c.decodeIfPresent(Int64.self, forKey: .merchantId)
        listingId = try c.decodeIfPresent(Int64.self, forKey: .listingId)
        brandId = try c.decodeIfPresent(Int64.self, forKey: .brandId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        mode = try c.decodeIfPresent(SpotReleaseMode.self, forKey: .mode)
        status = try c.decodeIfPresent(SpotReleaseStatus.self, forKey: .status)
        startAt = try c.decodeIfPresent(Date.self, forKey: .startAt)
        endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        startAtVersion = try c.decodeIfPresent(Int64.self, forKey: .startAtVersion)
        limitPerUser = try c.decodeIfPresent(Int.self, forKey: .limitPerUser)
        exclusive = try c.decodeIfPresent(Bool.self, forKey: .exclusive)
        exclusiveQuota = try c.decodeIfPresent(Int.self, forKey: .exclusiveQuota)
        exclusiveDepositFen = try c.decodeIfPresent(Int64.self, forKey: .exclusiveDepositFen)
        exclusivePin = try c.decodeIfPresent(Bool.self, forKey: .exclusivePin)
        inventoryPoolId = try c.decodeIfPresent(Int64.self, forKey: .inventoryPoolId)
        convertedFromReleaseId = try c.decodeIfPresent(Int64.self, forKey: .convertedFromReleaseId)
        skus = try c.decodeIfPresent([SpotReleaseSKU].self, forKey: .skus) ?? []
        vipWindows = try c.decodeIfPresent([SpotReleaseVIPWindow].self, forKey: .vipWindows) ?? []
        eligibility = try c.decodeIfPresent(SpotReleaseEligibility.self, forKey: .eligibility)
            ?? c.decodeIfPresent(SpotReleaseEligibility.self, forKey: .userEligibility)
        nextWindow = try c.decodeIfPresent(SpotReleaseNextWindow.self, forKey: .nextWindow)
        remaining = try c.decodeIfPresent(Int.self, forKey: .remaining)
        saleOpen = try c.decodeIfPresent(Bool.self, forKey: .saleOpen)
        reserved = try c.decodeIfPresent(Bool.self, forKey: .reserved)
            ?? c.decodeIfPresent(Bool.self, forKey: .viewerReserved)
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
        try c.encodeIfPresent(startAt, forKey: .startAt)
        try c.encodeIfPresent(endAt, forKey: .endAt)
        try c.encodeIfPresent(startAtVersion, forKey: .startAtVersion)
        try c.encodeIfPresent(limitPerUser, forKey: .limitPerUser)
        try c.encodeIfPresent(exclusive, forKey: .exclusive)
        try c.encodeIfPresent(exclusiveQuota, forKey: .exclusiveQuota)
        try c.encodeIfPresent(exclusiveDepositFen, forKey: .exclusiveDepositFen)
        try c.encodeIfPresent(exclusivePin, forKey: .exclusivePin)
        try c.encodeIfPresent(inventoryPoolId, forKey: .inventoryPoolId)
        try c.encodeIfPresent(convertedFromReleaseId, forKey: .convertedFromReleaseId)
        try c.encode(skus, forKey: .skus)
        try c.encode(vipWindows, forKey: .vipWindows)
        try c.encodeIfPresent(eligibility, forKey: .eligibility)
        try c.encodeIfPresent(nextWindow, forKey: .nextWindow)
        try c.encodeIfPresent(remaining, forKey: .remaining)
        try c.encodeIfPresent(saleOpen, forKey: .saleOpen)
        try c.encodeIfPresent(reserved, forKey: .reserved)
        try c.encodeIfPresent(serverNow, forKey: .serverNow)
        try c.encodeIfPresent(serverNowMs, forKey: .serverNowMs)
        try c.encodeIfPresent(serverTime, forKey: .serverTime)
        try c.encodeIfPresent(serverTimeMs, forKey: .serverTimeMs)
        try c.encodeIfPresent(version, forKey: .version)
    }

    public var displayTitle: String {
        (title?.isEmpty == false) ? title! : "现货发售"
    }

    public var isExclusive: Bool { exclusive == true }

    public var isConvertedFromPresale: Bool { convertedFromReleaseId != nil }

    public var resolvedLimitPerUser: Int {
        max(1, min(limitPerUser ?? SpotReleaseConfigDefaults.limitPerUserDefault, SpotReleaseConfigDefaults.limitPerUserMax))
    }

    public var resolvedDepositFen: Int64 {
        exclusiveDepositFen ?? SpotReleaseConfigDefaults.exclusiveDepositDefaultFen
    }

    public var resolvedRemaining: Int {
        if let remaining { return max(0, remaining) }
        return skus.reduce(0) { $0 + $1.resolvedRemaining }
    }

    public var defaultSKU: SpotReleaseSKU? {
        skus.first
    }

    public var isViewerReserved: Bool {
        if let reserved { return reserved }
        return eligibility?.isReserved == true
    }

    /// Prefer explicit ms / date fields from the payload (design §5.3 / §6).
    public var resolvedServerNowMs: Int64? {
        if let serverNowMs, serverNowMs > 0 { return serverNowMs }
        if let serverTimeMs, serverTimeMs > 0 { return serverTimeMs }
        if let serverNow { return Int64(serverNow.timeIntervalSince1970 * 1000) }
        if let serverTime { return Int64(serverTime.timeIntervalSince1970 * 1000) }
        return nil
    }

    public var resolvedServerNow: Date? {
        if let ms = resolvedServerNowMs { return Date(timeIntervalSince1970: Double(ms) / 1000) }
        return nil
    }
}

// MARK: - Write responses

public struct SpotReleaseReserveResult: Codable, Equatable, Sendable {
    public let releaseId: Int64?
    public let reserved: Bool?
    public let alreadyReserved: Bool?
    public let startAt: Date?
    public let startAtVersion: Int64?

    public init(
        releaseId: Int64? = nil,
        reserved: Bool? = nil,
        alreadyReserved: Bool? = nil,
        startAt: Date? = nil,
        startAtVersion: Int64? = nil
    ) {
        self.releaseId = releaseId
        self.reserved = reserved
        self.alreadyReserved = alreadyReserved
        self.startAt = startAt
        self.startAtVersion = startAtVersion
    }

    public var isReserved: Bool { reserved == true || alreadyReserved == true }
}

public struct SpotReleaseOrderCreateBody: Codable, Equatable, Sendable {
    public let skuId: Int64
    public let qty: Int
    public let addressId: Int64?

    public init(skuId: Int64, qty: Int = 1, addressId: Int64? = nil) {
        self.skuId = skuId
        self.qty = qty
        self.addressId = addressId
    }
}

/// Success payload from `POST /releases/{id}/orders` (design §5.4).
public struct SpotReleaseOrderResult: Codable, Equatable, Sendable {
    public let orderId: Int64
    public let holdId: Int64?
    public let payDeadline: Date?
    public let remaining: Int?
    public let serverTime: Date?

    public init(
        orderId: Int64,
        holdId: Int64? = nil,
        payDeadline: Date? = nil,
        remaining: Int? = nil,
        serverTime: Date? = nil
    ) {
        self.orderId = orderId
        self.holdId = holdId
        self.payDeadline = payDeadline
        self.remaining = remaining
        self.serverTime = serverTime
    }
}

/// Stub response for `POST /releases/{id}/exclusive-deposit` (design §5.5 / T-08).
public struct SpotReleaseExclusiveDepositResult: Codable, Equatable, Sendable {
    public let depositId: Int64?
    public let paymentId: Int64?
    public let amountFen: Int64?
    public let status: String?
    public let channel: String?
    public let payParams: [String: String]?

    public init(
        depositId: Int64? = nil,
        paymentId: Int64? = nil,
        amountFen: Int64? = nil,
        status: String? = nil,
        channel: String? = nil,
        payParams: [String: String]? = nil
    ) {
        self.depositId = depositId
        self.paymentId = paymentId
        self.amountFen = amountFen
        self.status = status
        self.channel = channel
        self.payParams = payParams
    }

    public var isFrozen: Bool {
        let s = (status ?? "").lowercased()
        return s == "frozen" || s == "success" || s == "succeeded" || s == "paid"
    }
}

// MARK: - Error codes / copy

/// Stable API error codes (design §5.4 / §5.9 / §7).
public enum SpotReleaseErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case missingIdempotencyKey = "missing_idempotency_key"
    case authRequired = "auth_required"
    case unauthorized
    case loginRequired = "login_required"
    case realNameRequired = "real_name_required"
    case accountRestricted = "account_restricted"
    case saleNotStarted = "sale_not_started"
    case saleEnded = "sale_ended"
    case skuNotFound = "sku_not_found"
    case soldOut = "sold_out"
    case purchaseLimitExceeded = "purchase_limit_exceeded"
    case vipWindowClosed = "vip_window_closed"
    case exclusiveEligibilityRequired = "exclusive_eligibility_required"
    case exclusiveQuotaExhausted = "exclusive_quota_exhausted"
    case depositNotFrozen = "deposit_not_frozen"
    case selfPurchaseForbidden = "self_purchase_forbidden"
    case addressRequired = "address_required"
    case holdExpired = "hold_expired"
    case orderCreateFailed = "order_create_failed"
    case invalidQty = "invalid_qty"
    case sellerCapabilityDisabled = "seller_capability_disabled"
    case brandNotAuthorized = "brand_not_authorized"
    case invalidStartAt = "invalid_start_at"
    case vipWindowInvalid = "vip_window_invalid"
    case vipWindowIncomplete = "vip_window_incomplete"
    case rateLimited = "rate_limited"
    case relatedAccountBlocked = "related_account_blocked"
    case nothingToConvert = "nothing_to_convert"
    case alreadyConverted = "already_converted"
    case capabilityDisabled = "capability_disabled"

    public var opensLogin: Bool {
        self == .authRequired || self == .unauthorized || self == .loginRequired
    }

    public var opensRealName: Bool {
        self == .realNameRequired || self == .exclusiveEligibilityRequired
    }

    public var opensExclusiveDeposit: Bool {
        self == .depositNotFrozen || self == .exclusiveEligibilityRequired
    }

    public var fallbackMessage: String {
        switch self {
        case .missingIdempotencyKey: return "请重试"
        case .authRequired, .unauthorized, .loginRequired: return "请先登录"
        case .realNameRequired: return "请先完成实名认证"
        case .accountRestricted: return "账号受限，暂不可抢购"
        case .saleNotStarted: return "尚未开售"
        case .saleEnded: return SpotReleaseCopy.ended
        case .skuNotFound: return "规格不存在"
        case .soldOut: return SpotReleaseCopy.soldOut
        case .purchaseLimitExceeded: return "已达限购数量"
        case .vipWindowClosed: return SpotReleaseCopy.vipWindowClosed
        case .exclusiveEligibilityRequired: return SpotReleaseCopy.completeEligibility
        case .exclusiveQuotaExhausted: return "独家配额已用尽"
        case .depositNotFrozen: return "请先冻结保证金"
        case .selfPurchaseForbidden: return "不可购买本店发售"
        case .addressRequired: return "支付前请填写收货地址"
        case .holdExpired: return "占库存已过期，请重新抢购"
        case .orderCreateFailed: return SpotReleaseCopy.weakNetRetry
        case .invalidQty: return "数量无效"
        case .sellerCapabilityDisabled, .capabilityDisabled: return "未开通现货发售能力"
        case .brandNotAuthorized: return "品牌未授权"
        case .invalidStartAt: return "开售时间无效"
        case .vipWindowInvalid: return "VIP 窗口配置无效"
        case .vipWindowIncomplete: return "VIP 窗口须覆盖公开场"
        case .rateLimited: return "操作过于频繁，请稍后再试"
        case .relatedAccountBlocked: return "关联账号受限"
        case .nothingToConvert: return "无可转现货库存"
        case .alreadyConverted: return "已转现货"
        }
    }
}

public enum SpotReleaseCopy {
    public static let pageTitle = "现货发售"
    public static let rush = "立即抢购"
    public static let reserve = "预约提醒"
    public static let reserved = "已预约"
    public static let soldOut = "已售罄"
    public static let soldOutHint = "已售罄，订阅补货"
    public static let ended = "已结束"
    public static let completeEligibility = "去完成资格"
    public static let waitVIPWindow = "窗口未到"
    public static let vipWindowClosed = "当前会员等级窗口未开放"
    public static let serverTimeHint = "以服务器时间为准"
    public static let weakNetRetry = "以订单页为准，可放心重试"
    public static let payWindowHint = "付款时限 15 分钟"
    public static let shipWindowHint = "付款后 48 小时发货"
    public static let convertedPresaleHint = "预售剩余"
    public static let exclusiveBadge = "独家首发"
    public static let viewVIPRules = "查看店铺会员规则"
    public static let emptySoldOutSubscribe = "订阅补货"
}

// MARK: - Pure logic

public enum SpotReleaseLogic {
    /// Countdown against server clock — never device wall clock alone (design §4 / §5.3).
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

    public static func countdownLine(seconds: Int) -> String {
        "\(formatCountdown(seconds: seconds)) · \(SpotReleaseCopy.serverTimeHint)"
    }

    /// Design §5.3 — show fixed hint when |skew| > 2s.
    public static func shouldShowServerTimeSkewHint(clientSkewMs: Int64) -> Bool {
        abs(clientSkewMs) > SpotReleaseConfigDefaults.clockSkewWarnMs
    }

    /// Poll cadence (design §5.9): before 30s; last 10s → 1s; live → 3s.
    public static func pollIntervalSeconds(remainingToStart: Int?, saleOpen: Bool) -> Int {
        if saleOpen { return SpotReleaseConfigDefaults.pollLiveSec }
        guard let remaining = remainingToStart else {
            return SpotReleaseConfigDefaults.pollBeforeSaleSec
        }
        if remaining <= SpotReleaseConfigDefaults.pollNearSaleWindowSec {
            return SpotReleaseConfigDefaults.pollNearSaleSec
        }
        return SpotReleaseConfigDefaults.pollBeforeSaleSec
    }

    /// Prefer server `sale_open`; never unlock rush on local zero alone (design §5.9).
    public static func isSaleOpen(_ detail: SpotReleaseDetail, serverNow: Date) -> Bool {
        if let flag = detail.saleOpen { return flag }
        // Without an explicit flag, only trust live status — local clock past start_at is insufficient.
        if detail.status == .live {
            if let end = detail.endAt, serverNow > end { return false }
            return true
        }
        return false
    }

    /// Next VIP window for a buyer level (design §5.6). Level 0 = public.
    public static func nextWindow(
        forLevel level: Int,
        windows: [SpotReleaseVIPWindow],
        serverNow: Date
    ) -> SpotReleaseNextWindow? {
        guard !windows.isEmpty else { return nil }
        let sorted = windows.sorted { $0.minLevel > $1.minLevel }
        // Highest window whose min_level ≤ user level.
        let eligible = sorted.filter { $0.minLevel <= level }
        guard let mine = eligible.first else {
            // Should not happen if windows cover level 0; still surface earliest public.
            if let publicRow = windows.sorted(by: { $0.openAt < $1.openAt }).first(where: { $0.minLevel <= 0 }) {
                return SpotReleaseNextWindow(
                    openAt: publicRow.openAt,
                    minLevel: publicRow.minLevel,
                    levelName: publicRow.levelName,
                    message: SpotReleaseCopy.vipWindowClosed
                )
            }
            return SpotReleaseNextWindow(message: SpotReleaseCopy.vipWindowClosed)
        }
        if mine.openAt <= serverNow { return nil }
        return SpotReleaseNextWindow(
            openAt: mine.openAt,
            minLevel: mine.minLevel,
            levelName: mine.levelName,
            message: vipWindowClosedCopy(openAt: mine.openAt, level: level, levelName: mine.levelName)
        )
    }

    public static func vipWindowClosedCopy(openAt: Date?, level: Int, levelName: String? = nil) -> String {
        guard let openAt else { return SpotReleaseCopy.vipWindowClosed }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "HH:mm"
        let name = (levelName?.isEmpty == false) ? levelName! : "Lv.\(level)"
        return "\(name) 开放时间 \(f.string(from: openAt)) · \(SpotReleaseCopy.viewVIPRules)"
    }

    /// Exclusive pipeline checklist (design §5.5).
    public static func exclusiveChecklist(
        isLoggedIn: Bool,
        eligibility: SpotReleaseEligibility?,
        exclusive: Bool
    ) -> [SpotReleaseExclusiveChecklistItem] {
        guard exclusive else { return [] }
        return [
            SpotReleaseExclusiveChecklistItem(step: .login, done: isLoggedIn),
            SpotReleaseExclusiveChecklistItem(step: .realName, done: eligibility?.isRealNamed == true),
            SpotReleaseExclusiveChecklistItem(step: .deposit, done: eligibility?.isDepositFrozen == true),
        ]
    }

    public static func exclusiveReady(
        isLoggedIn: Bool,
        eligibility: SpotReleaseEligibility?,
        exclusive: Bool
    ) -> Bool {
        guard exclusive else { return true }
        return isLoggedIn
            && eligibility?.isRealNamed == true
            && eligibility?.isDepositFrozen == true
    }

    public static func nextExclusiveStep(
        isLoggedIn: Bool,
        eligibility: SpotReleaseEligibility?,
        exclusive: Bool
    ) -> SpotReleaseExclusiveStep? {
        exclusiveChecklist(isLoggedIn: isLoggedIn, eligibility: eligibility, exclusive: exclusive)
            .first { !$0.done }?
            .step
    }

    /// VIP windows must be monotonic: higher level open_at ≤ lower level (design §5.1 / §5.6).
    public static func validateVIPWindows(_ windows: [SpotReleaseVIPWindow]) -> SpotReleaseErrorCode? {
        guard !windows.isEmpty else { return nil }
        let byLevel = windows.sorted { $0.minLevel > $1.minLevel }
        // Must cover level 0 (public).
        if !windows.contains(where: { $0.minLevel <= 0 }) {
            return .vipWindowIncomplete
        }
        for i in 0..<(byLevel.count - 1) {
            let higher = byLevel[i]
            let lower = byLevel[i + 1]
            if higher.openAt > lower.openAt {
                return .vipWindowInvalid
            }
        }
        return nil
    }

    public static func validateStartAt(_ startAt: Date, serverNow: Date) -> SpotReleaseErrorCode? {
        let min = serverNow.addingTimeInterval(TimeInterval(SpotReleaseConfigDefaults.minStartAheadMinutes * 60))
        return startAt >= min ? nil : .invalidStartAt
    }

    public static func validateQty(_ qty: Int, limitPerUser: Int) -> SpotReleaseErrorCode? {
        if qty < 1 { return .invalidQty }
        if qty > max(1, limitPerUser) { return .invalidQty }
        return nil
    }

    /// Resolve bottom CTA. Local countdown hitting 0 without `sale_open` stays wait (design §5.9).
    public static func resolveCTA(
        detail: SpotReleaseDetail,
        serverNow: Date,
        isLoggedIn: Bool
    ) -> SpotReleaseCTA {
        let status = detail.status
        if status == .soldOut { return .soldOut }
        if status == .ended { return .ended }
        if status == .converted { return .converting }

        let saleOpen = isSaleOpen(detail, serverNow: serverNow)
        if saleOpen, detail.resolvedRemaining <= 0 { return .soldOut }

        if !saleOpen {
            if !isLoggedIn { return .login }
            if detail.isViewerReserved { return .reservedWaiting }
            // Countdown may be 0 while open flag not yet written — keep waiting, not rush.
            if let start = detail.startAt, serverNow >= start {
                return .waitSaleOpen
            }
            return .reserve
        }

        // Sale open
        if !isLoggedIn { return .login }

        if detail.isExclusive,
           !exclusiveReady(isLoggedIn: isLoggedIn, eligibility: detail.eligibility, exclusive: true) {
            return .completeEligibility
        }

        let level = detail.eligibility?.resolvedVipLevel ?? 0
        if let closed = detail.nextWindow ?? nextWindow(forLevel: level, windows: detail.vipWindows, serverNow: serverNow),
           let openAt = closed.openAt, openAt > serverNow {
            return .waitVIPWindow
        }

        return .rush
    }

    public static func formatYuan(_ fen: Int64) -> String {
        let yuan = Double(fen) / 100.0
        if fen % 100 == 0 {
            return String(format: "%.0f", yuan)
        }
        return String(format: "%.2f", yuan)
    }
}
