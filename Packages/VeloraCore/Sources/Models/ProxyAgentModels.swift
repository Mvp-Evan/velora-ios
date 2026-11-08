import Foundation

// MARK: - Dedicated proxy agent (DES-v1.3-05-01 PXY-01/02/05/06 / D19)

/// Product defaults (design §3 / §5.5 / §8.3). Hot-config on server; client mirrors for UX.
public enum ProxyAgentConfigDefaults {
    public static let depositFen: Int64 = 500_000
    public static let depositYuan: Int = 5_000
    public static let minSampleOrders: Int = 5
    public static let shipOnTimeThreshold: Double = 0.95
    public static let afterSaleThreshold: Double = 0.08
    public static let defaultRateThreshold: Double = 0.03
    public static let arbitrationLossThreshold: Double = 0.20
    public static let failMonthsToProbation: Int = 2
    public static let failMonthsOnProbationToRevoke: Int = 1
    public static let batchMaxRows: Int = 200
    public static let batchImportPollSeconds: Int = 3
    public static let privilegeLagAlertSeconds: Int = 30
    public static let feeTierMinPercent: Double = 5
    public static let feeTierMaxPercent: Double = 9
    public static let protocolCode = "proxy_service"
    public static let sellerType = "proxy_agent"
    public static let badgeGoldWire = "proxy_gold"
    public static let badgeGoldDB = "gold_proxy"
    public static let badgeProbation = "proxy_probation"
    public static let inviteSellerType = "proxy_agent"
    public static let revokeKeepFixedKey = "pxy.revoke_keep_fixed"
    public static let revokeKeepFixedDefault = true
    public static let forecastWindowDays: Int = 30
    public static let meEntryInvoice = "invoice"
    public static let meEntryKPI = "proxy_kpi"
    /// Forbidden consignor fields (B-04 / §5.7) — client must never send or render.
    public static let forbiddenConsignorKeys: [String] = [
        "consignor_id", "principal_name", "client_settlement",
    ]
}

// MARK: - Assessment level / result / badge

/// `seller_profile.assessment_level` (design §3).
public enum ProxyAssessmentLevel: String, Codable, Sendable, CaseIterable, Equatable {
    case gold
    case probation
    case revoked

    public var displayLabel: String {
        switch self {
        case .gold: return "金牌"
        case .probation: return "观察期"
        case .revoked: return "已取消"
        }
    }

    /// Buyer-facing identity chip (design §3 / §14).
    public var buyerBadgeLabel: String? {
        switch self {
        case .gold: return "金牌代拍"
        case .probation: return "代拍（观察期）"
        case .revoked: return nil
        }
    }

    public var showsGoldBadge: Bool { self == .gold }

    public var isProxyIdentity: Bool { self == .gold || self == .probation }
}

/// Monthly `proxy_assessment.result` (design §4 / §5.5).
public enum ProxyAssessmentResult: String, Codable, Sendable, CaseIterable, Equatable {
    case pass
    case warn
    case fail
    case insufficientSample = "insufficient_sample"

    public var displayLabel: String {
        switch self {
        case .pass: return "达标"
        case .warn: return "预警"
        case .fail: return "不达标"
        case .insufficientSample: return "样本不足"
        }
    }

    /// Counts toward consecutive-fail window (design §5.5).
    public var countsAsConsecutiveFail: Bool { self == .fail }
}

/// Wire / DB badge tokens for proxy agents (design §3; home feed uses `proxy_gold`).
public enum ProxyAgentBadgeToken: String, Codable, Sendable, CaseIterable, Equatable {
    case goldProxy = "gold_proxy"
    case proxyGold = "proxy_gold"
    case proxyProbation = "proxy_probation"

    public var isGold: Bool { self == .goldProxy || self == .proxyGold }
    public var isProbation: Bool { self == .proxyProbation }

    public var displayLabel: String {
        switch self {
        case .goldProxy, .proxyGold: return "金牌代拍"
        case .proxyProbation: return "代拍（观察期）"
        }
    }

    public static func parse(_ raw: String?) -> ProxyAgentBadgeToken? {
        guard let raw, !raw.isEmpty else { return nil }
        return ProxyAgentBadgeToken(rawValue: raw)
    }
}

// MARK: - Capabilities / privilege expiry

/// Capability keys used by proxy agents (design §3 / 4.2).
public enum ProxyCapabilityKey: String, Codable, Sendable, CaseIterable, Equatable {
    case canFixed = "can_fixed"
    case canAuction = "can_auction"
    case canBatchList = "can_batch_list"
    case canInvoiceService = "can_invoice_service"
    case canSession = "can_session"
    case canPromote = "can_promote"

    public var title: String {
        switch self {
        case .canFixed: return "一口价"
        case .canAuction: return "拍卖新上"
        case .canBatchList: return "批量上拍"
        case .canInvoiceService: return "开票服务"
        case .canSession: return "专场申请"
        case .canPromote: return "推荐位"
        }
    }
}

/// Snapshot of proxy capability flags (design §5.5 table).
public struct ProxyCapabilities: Codable, Equatable, Sendable {
    public var canFixed: Bool
    public var canAuction: Bool
    public var canBatchList: Bool
    public var canInvoiceService: Bool
    public var canSession: Bool
    public var canPromote: Bool

    public static let goldDefaults = ProxyCapabilities(
        canFixed: true, canAuction: true, canBatchList: true,
        canInvoiceService: true, canSession: true, canPromote: true
    )

    public init(
        canFixed: Bool = false,
        canAuction: Bool = false,
        canBatchList: Bool = false,
        canInvoiceService: Bool = false,
        canSession: Bool = false,
        canPromote: Bool = false
    ) {
        self.canFixed = canFixed
        self.canAuction = canAuction
        self.canBatchList = canBatchList
        self.canInvoiceService = canInvoiceService
        self.canSession = canSession
        self.canPromote = canPromote
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canFixed = try c.decodeIfPresent(Bool.self, forKey: .canFixed) ?? false
        canAuction = try c.decodeIfPresent(Bool.self, forKey: .canAuction) ?? false
        canBatchList = try c.decodeIfPresent(Bool.self, forKey: .canBatchList) ?? false
        canInvoiceService = try c.decodeIfPresent(Bool.self, forKey: .canInvoiceService) ?? false
        canSession = try c.decodeIfPresent(Bool.self, forKey: .canSession) ?? false
        canPromote = try c.decodeIfPresent(Bool.self, forKey: .canPromote) ?? false
    }

    public func allows(_ key: ProxyCapabilityKey) -> Bool {
        switch key {
        case .canFixed: return canFixed
        case .canAuction: return canAuction
        case .canBatchList: return canBatchList
        case .canInvoiceService: return canInvoiceService
        case .canSession: return canSession
        case .canPromote: return canPromote
        }
    }
}

/// Pure privilege matrix after assessment_level change (design §5.5 / §5.12).
public enum ProxyPrivilegeLogic {
    /// Capabilities that close on probation (降级).
    public static let closedOnProbation: [ProxyCapabilityKey] = [.canPromote, .canSession]

    /// Extra capabilities that close on revoke (取消资格), beyond probation.
    public static let closedOnRevoke: [ProxyCapabilityKey] = [
        .canPromote, .canSession, .canBatchList, .canInvoiceService, .canAuction,
    ]

    public static func applyLevel(
        _ level: ProxyAssessmentLevel,
        base: ProxyCapabilities = .goldDefaults,
        keepFixedOnRevoke: Bool = ProxyAgentConfigDefaults.revokeKeepFixedDefault
    ) -> ProxyCapabilities {
        var next = base
        switch level {
        case .gold:
            return base
        case .probation:
            next.canPromote = false
            next.canSession = false
            return next
        case .revoked:
            next.canPromote = false
            next.canSession = false
            next.canBatchList = false
            next.canInvoiceService = false
            next.canAuction = false
            if !keepFixedOnRevoke { next.canFixed = false }
            return next
        }
    }

    /// Lost-rights copy for downgrade sheet (design §9).
    public static func lostPrivilegeTitles(from: ProxyAssessmentLevel, to: ProxyAssessmentLevel) -> [String] {
        let before = Set(enabledKeys(applyLevel(from)))
        let after = Set(enabledKeys(applyLevel(to)))
        return ProxyCapabilityKey.allCases
            .filter { before.contains($0) && !after.contains($0) }
            .map(\.title)
    }

    public static func enabledKeys(_ caps: ProxyCapabilities) -> [ProxyCapabilityKey] {
        ProxyCapabilityKey.allCases.filter { caps.allows($0) }
    }

    /// Consecutive fail → next level (design §4).
    public static func nextLevel(
        current: ProxyAssessmentLevel,
        consecutiveFails: Int
    ) -> ProxyAssessmentLevel {
        switch current {
        case .gold:
            return consecutiveFails >= ProxyAgentConfigDefaults.failMonthsToProbation ? .probation : .gold
        case .probation:
            return consecutiveFails >= ProxyAgentConfigDefaults.failMonthsOnProbationToRevoke ? .revoked : .probation
        case .revoked:
            return .revoked
        }
    }
}

// MARK: - Metric thresholds / evaluation

public enum ProxyMetricKind: String, Codable, Sendable, CaseIterable, Equatable {
    case shipOnTime = "ship_on_time_rate"
    case afterSale = "after_sale_rate"
    case defaultRate = "default_rate"
    case arbitrationLoss = "arbitration_loss_rate"

    public var title: String {
        switch self {
        case .shipOnTime: return "发货时效"
        case .afterSale: return "售后率"
        case .defaultRate: return "违约率"
        case .arbitrationLoss: return "仲裁败诉率"
        }
    }

    public var threshold: Double {
        switch self {
        case .shipOnTime: return ProxyAgentConfigDefaults.shipOnTimeThreshold
        case .afterSale: return ProxyAgentConfigDefaults.afterSaleThreshold
        case .defaultRate: return ProxyAgentConfigDefaults.defaultRateThreshold
        case .arbitrationLoss: return ProxyAgentConfigDefaults.arbitrationLossThreshold
        }
    }

    /// Higher-is-better vs lower-is-better (design §5.5).
    public var higherIsBetter: Bool { self == .shipOnTime }

    public var thresholdLabel: String {
        let pct = Int((threshold * 100).rounded())
        return higherIsBetter ? "≥\(pct)%" : "≤\(pct)%"
    }

    public var definition: String {
        switch self {
        case .shipOnTime: return "付款后 72h 内发货订单 / 应发货订单"
        case .afterSale: return "售后期完结订单中发起售后 / 完成订单"
        case .defaultRate: return "卖家责取消+发货超时取消 / 成交订单"
        case .arbitrationLoss: return "败诉案件 / 仲裁案件；分母=0 视为达标"
        }
    }
}

public enum ProxyMetricLogic {
    /// Single metric pass (design §5.5). `nil` rate with arbitration + zero denom → pass.
    public static func meetsThreshold(kind: ProxyMetricKind, rate: Double?, arbitrationDenomZero: Bool = false) -> Bool {
        if kind == .arbitrationLoss, arbitrationDenomZero { return true }
        guard let rate else { return false }
        if kind.higherIsBetter {
            return rate + 1e-12 >= kind.threshold
        }
        return rate - 1e-12 <= kind.threshold
    }

    public static func sampleEligible(orderCount: Int) -> Bool {
        orderCount >= ProxyAgentConfigDefaults.minSampleOrders
    }

    /// Derive month result from four rates (warn unused locally — server may emit warn).
    public static func evaluateMonth(
        orderCount: Int,
        shipOnTime: Double,
        afterSale: Double,
        defaultRate: Double,
        arbitrationLoss: Double?,
        arbitrationCaseCount: Int
    ) -> ProxyAssessmentResult {
        guard sampleEligible(orderCount: orderCount) else { return .insufficientSample }
        let shipOK = meetsThreshold(kind: .shipOnTime, rate: shipOnTime)
        let afterOK = meetsThreshold(kind: .afterSale, rate: afterSale)
        let defaultOK = meetsThreshold(kind: .defaultRate, rate: defaultRate)
        let arbOK = meetsThreshold(
            kind: .arbitrationLoss,
            rate: arbitrationLoss,
            arbitrationDenomZero: arbitrationCaseCount == 0
        )
        return (shipOK && afterOK && defaultOK && arbOK) ? .pass : .fail
    }

    public static func formatRate(_ rate: Double?) -> String {
        guard let rate else { return "—" }
        let pct = rate * 100
        return String(format: "%.1f%%", pct)
    }
}

// MARK: - Buyer badge resolution (PXY-02 / §14)

public enum ProxyBadgeLogic {
    /// Gold chip only when `assessment_level=gold` (design §14). Server feed badge still authoritative when level absent.
    public static func buyerVisibleLabel(
        assessmentLevel: ProxyAssessmentLevel?,
        badgeRaw: String?
    ) -> String? {
        if let level = assessmentLevel {
            return level.buyerBadgeLabel
        }
        return ProxyAgentBadgeToken.parse(badgeRaw)?.displayLabel
    }

    /// Map profile fields → feed `SellerBadge` (keeps home chip enum in sync).
    public static func sellerBadge(
        assessmentLevel: ProxyAssessmentLevel?,
        badgeRaw: String?
    ) -> SellerBadge? {
        if let level = assessmentLevel {
            switch level {
            case .gold: return .proxyGold
            case .probation: return .proxyProbation
            case .revoked: return nil
            }
        }
        guard let token = ProxyAgentBadgeToken.parse(badgeRaw) else { return nil }
        if token.isGold { return .proxyGold }
        if token.isProbation { return .proxyProbation }
        return nil
    }

    public static func fulfillmentResponsibilityCopy(isProxyAgent: Bool) -> String? {
        isProxyAgent ? ProxyAgentCopy.fulfillmentResponsibility : nil
    }
}

// MARK: - Error codes / copy

public enum ProxyAgentErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case inviteInvalid = "invite_invalid"
    case inviteQuotaExceeded = "invite_quota_exceeded"
    case realNameRequired = "real_name_required"
    case depositRequired = "deposit_required"
    case capabilityDisabled = "capability_disabled"
    case batchRowInvalid = "batch_row_invalid"
    case unauthorized
    case applicationRejected = "application_rejected"
    case consignContractRejected = "consign_contract_rejected"

    public var opensLogin: Bool { self == .unauthorized }
    public var opensRealName: Bool { self == .realNameRequired }

    public var fallbackMessage: String {
        switch self {
        case .inviteInvalid: return "邀请码无效或已过期"
        case .inviteQuotaExceeded: return "邀请码名额已用尽"
        case .realNameRequired: return "请先完成实名认证"
        case .depositRequired: return "请先缴纳代拍保证金"
        case .capabilityDisabled: return "当前身份暂无此能力"
        case .batchRowInvalid: return "部分行未通过校验"
        case .unauthorized: return "请先登录"
        case .applicationRejected: return "资质审核未通过"
        case .consignContractRejected: return ProxyAgentCopy.consignRejected
        }
    }
}

public enum ProxyAgentCopy {
    public static let goldBadge = "金牌代拍"
    public static let probationBadge = "代拍（观察期）"
    public static let fulfillmentResponsibility = "由卖家本人发货并承担售后"
    public static let noConsignorSwitch = "平台不提供「代委托人发货」开关"
    public static let consignRejected = "平台不登记委托关系，请删除后提交"
    public static let protocolSummary = "你以自己名义出售；委托人不是平台用户关系。"
    public static let costPriceHint = "可选，仅自己看利润，平台不对任何人打款"
    public static let batchNeedProxy = "需代拍身份"
    public static let assessmentTitle = "代拍考核"
    public static let forecastHint = "近 30 天预测，非终值"
    public static let downgradeTitle = "代拍权益已调整"
    public static let downgradeOrdersSafe = "在途订单仍由你本人发货售后，不受影响"
    public static let downgradeAppeal = "如有异议可联系运营申诉"
    public static let badgePageTitle = "代拍标识"
    public static let onboardingSteps = ["资料", "保证金", "审核", "进件"]
}

// MARK: - DTOs

/// `GET /api/v1/me/seller` projection extras for proxy agents (design §6).
public struct ProxySellerProfile: Codable, Equatable, Sendable {
    public let userId: Int64?
    public let sellerType: String?
    public let badge: String?
    public let assessmentLevel: ProxyAssessmentLevel?
    public let feeTierId: String?
    public let onboardingStatus: String?
    public let capabilities: ProxyCapabilities?
    public let subMerchantId: String?

    public init(
        userId: Int64? = nil,
        sellerType: String? = nil,
        badge: String? = nil,
        assessmentLevel: ProxyAssessmentLevel? = nil,
        feeTierId: String? = nil,
        onboardingStatus: String? = nil,
        capabilities: ProxyCapabilities? = nil,
        subMerchantId: String? = nil
    ) {
        self.userId = userId
        self.sellerType = sellerType
        self.badge = badge
        self.assessmentLevel = assessmentLevel
        self.feeTierId = feeTierId
        self.onboardingStatus = onboardingStatus
        self.capabilities = capabilities
        self.subMerchantId = subMerchantId
    }

    public var isProxyAgent: Bool {
        sellerType == ProxyAgentConfigDefaults.sellerType
    }

    public var buyerBadgeLabel: String? {
        ProxyBadgeLogic.buyerVisibleLabel(assessmentLevel: assessmentLevel, badgeRaw: badge)
    }

    public var sellerBadge: SellerBadge? {
        ProxyBadgeLogic.sellerBadge(assessmentLevel: assessmentLevel, badgeRaw: badge)
    }
}

/// One month row from `GET /merchant/v1/assessments` (design §3 / §6).
public struct ProxyAssessmentMonth: Codable, Equatable, Sendable, Identifiable {
    public let sellerId: Int64?
    public let yearMonth: String
    public let shipOnTimeRate: Double?
    public let afterSaleRate: Double?
    public let defaultRate: Double?
    public let arbitrationLossRate: Double?
    public let orderCount: Int?
    public let arbitrationCaseCount: Int?
    public let result: ProxyAssessmentResult?
    public let decidedAt: Date?
    public let manualOverride: Bool?
    public let skipAuto: Bool?

    public var id: String { yearMonth }

    public init(
        sellerId: Int64? = nil,
        yearMonth: String,
        shipOnTimeRate: Double? = nil,
        afterSaleRate: Double? = nil,
        defaultRate: Double? = nil,
        arbitrationLossRate: Double? = nil,
        orderCount: Int? = nil,
        arbitrationCaseCount: Int? = nil,
        result: ProxyAssessmentResult? = nil,
        decidedAt: Date? = nil,
        manualOverride: Bool? = nil,
        skipAuto: Bool? = nil
    ) {
        self.sellerId = sellerId
        self.yearMonth = yearMonth
        self.shipOnTimeRate = shipOnTimeRate
        self.afterSaleRate = afterSaleRate
        self.defaultRate = defaultRate
        self.arbitrationLossRate = arbitrationLossRate
        self.orderCount = orderCount
        self.arbitrationCaseCount = arbitrationCaseCount
        self.result = result
        self.decidedAt = decidedAt
        self.manualOverride = manualOverride
        self.skipAuto = skipAuto
    }

    public func rate(for kind: ProxyMetricKind) -> Double? {
        switch kind {
        case .shipOnTime: return shipOnTimeRate
        case .afterSale: return afterSaleRate
        case .defaultRate: return defaultRate
        case .arbitrationLoss: return arbitrationLossRate
        }
    }

    public func meets(_ kind: ProxyMetricKind) -> Bool {
        ProxyMetricLogic.meetsThreshold(
            kind: kind,
            rate: rate(for: kind),
            arbitrationDenomZero: kind == .arbitrationLoss && (arbitrationCaseCount ?? 0) == 0
        )
    }
}

public struct ProxyAssessmentListResponse: Codable, Equatable, Sendable {
    public let items: [ProxyAssessmentMonth]
    public let forecast: ProxyAssessmentForecast?

    public init(items: [ProxyAssessmentMonth] = [], forecast: ProxyAssessmentForecast? = nil) {
        self.items = items
        self.forecast = forecast
    }
}

/// Near-30-day forecast — labeled non-final (design §9).
public struct ProxyAssessmentForecast: Codable, Equatable, Sendable {
    public let shipOnTimeRate: Double?
    public let afterSaleRate: Double?
    public let defaultRate: Double?
    public let arbitrationLossRate: Double?
    public let orderCount: Int?
    public let windowDays: Int?
    public let isFinal: Bool?

    public init(
        shipOnTimeRate: Double? = nil,
        afterSaleRate: Double? = nil,
        defaultRate: Double? = nil,
        arbitrationLossRate: Double? = nil,
        orderCount: Int? = nil,
        windowDays: Int? = ProxyAgentConfigDefaults.forecastWindowDays,
        isFinal: Bool? = false
    ) {
        self.shipOnTimeRate = shipOnTimeRate
        self.afterSaleRate = afterSaleRate
        self.defaultRate = defaultRate
        self.arbitrationLossRate = arbitrationLossRate
        self.orderCount = orderCount
        self.windowDays = windowDays
        self.isFinal = isFinal
    }

    public var showsNonFinalBanner: Bool { !(isFinal ?? false) }

    public func rate(for kind: ProxyMetricKind) -> Double? {
        switch kind {
        case .shipOnTime: return shipOnTimeRate
        case .afterSale: return afterSaleRate
        case .defaultRate: return defaultRate
        case .arbitrationLoss: return arbitrationLossRate
        }
    }
}

/// Downgrade / revoke notice payload for sheet (design §9).
public struct ProxyDowngradeNotice: Equatable, Sendable, Identifiable {
    public let from: ProxyAssessmentLevel
    public let to: ProxyAssessmentLevel
    public let lostTitles: [String]

    public var id: String { "\(from.rawValue)->\(to.rawValue)" }

    public init(from: ProxyAssessmentLevel, to: ProxyAssessmentLevel) {
        self.from = from
        self.to = to
        self.lostTitles = ProxyPrivilegeLogic.lostPrivilegeTitles(from: from, to: to)
    }

    public var title: String { ProxyAgentCopy.downgradeTitle }
    public var ordersSafe: String { ProxyAgentCopy.downgradeOrdersSafe }
    public var appealHint: String { ProxyAgentCopy.downgradeAppeal }
}

/// Onboarding progress steps for proxy application UX (design §9).
public enum ProxyOnboardingStep: String, Codable, Sendable, CaseIterable, Equatable {
    case materials
    case deposit
    case review
    case subMerchant = "sub_merchant"

    public var title: String {
        switch self {
        case .materials: return "资料"
        case .deposit: return "保证金"
        case .review: return "审核"
        case .subMerchant: return "进件"
        }
    }

    public var index: Int { ProxyOnboardingStep.allCases.firstIndex(of: self) ?? 0 }
}

public enum ProxyOnboardingProgress {
    public static var stepTitles: [String] { ProxyAgentCopy.onboardingSteps }

    /// Map merchant application dual status → current step highlight index (0…3).
    public static func currentIndex(reviewStatus: String?, subMerchantStatus: String?, depositDone: Bool) -> Int {
        let review = (reviewStatus ?? "").lowercased()
        let sub = (subMerchantStatus ?? "").lowercased()
        if ["finished", "succeeded", "active", "approved", "passed"].contains(sub) { return 3 }
        if ["applying", "processing", "pending_sign", "to_sign", "failed"].contains(sub) { return 3 }
        if ["approved", "passed"].contains(review) { return depositDone ? 3 : 1 }
        if ["submitted", "pending", "reviewing", "ops_review"].contains(review) { return depositDone ? 2 : 1 }
        if depositDone { return 1 }
        return 0
    }
}
