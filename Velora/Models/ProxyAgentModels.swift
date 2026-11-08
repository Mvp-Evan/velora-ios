import Foundation

// MARK: - Dedicated proxy agent (DES-v1.3-05-01 — app mirror of VeloraCore)

// MARK: - Dedicated proxy agent (DES-v1.3-05-01 PXY-01/02/05/06 / D19)

/// Product defaults (design §3 / §5.5 / §8.3). Hot-config on server; client mirrors for UX.
enum ProxyAgentConfigDefaults {
    static let depositFen: Int64 = 500_000
    static let depositYuan: Int = 5_000
    static let minSampleOrders: Int = 5
    static let shipOnTimeThreshold: Double = 0.95
    static let afterSaleThreshold: Double = 0.08
    static let defaultRateThreshold: Double = 0.03
    static let arbitrationLossThreshold: Double = 0.20
    static let failMonthsToProbation: Int = 2
    static let failMonthsOnProbationToRevoke: Int = 1
    static let batchMaxRows: Int = 200
    static let batchImportPollSeconds: Int = 3
    static let privilegeLagAlertSeconds: Int = 30
    static let feeTierMinPercent: Double = 5
    static let feeTierMaxPercent: Double = 9
    static let protocolCode = "proxy_service"
    static let sellerType = "proxy_agent"
    static let badgeGoldWire = "proxy_gold"
    static let badgeGoldDB = "gold_proxy"
    static let badgeProbation = "proxy_probation"
    static let inviteSellerType = "proxy_agent"
    static let revokeKeepFixedKey = "pxy.revoke_keep_fixed"
    static let revokeKeepFixedDefault = true
    static let forecastWindowDays: Int = 30
    static let meEntryInvoice = "invoice"
    static let meEntryKPI = "proxy_kpi"
    /// Forbidden consignor fields (B-04 / §5.7) — client must never send or render.
    static let forbiddenConsignorKeys: [String] = [
        "consignor_id", "principal_name", "client_settlement",
    ]
}

// MARK: - Assessment level / result / badge

/// `seller_profile.assessment_level` (design §3).
enum ProxyAssessmentLevel: String, Codable, Sendable, CaseIterable, Equatable {
    case gold
    case probation
    case revoked

    var displayLabel: String {
        switch self {
        case .gold: return "金牌"
        case .probation: return "观察期"
        case .revoked: return "已取消"
        }
    }

    /// Buyer-facing identity chip (design §3 / §14).
    var buyerBadgeLabel: String? {
        switch self {
        case .gold: return "金牌代拍"
        case .probation: return "代拍（观察期）"
        case .revoked: return nil
        }
    }

    var showsGoldBadge: Bool { self == .gold }

    var isProxyIdentity: Bool { self == .gold || self == .probation }
}

/// Monthly `proxy_assessment.result` (design §4 / §5.5).
enum ProxyAssessmentResult: String, Codable, Sendable, CaseIterable, Equatable {
    case pass
    case warn
    case fail
    case insufficientSample = "insufficient_sample"

    var displayLabel: String {
        switch self {
        case .pass: return "达标"
        case .warn: return "预警"
        case .fail: return "不达标"
        case .insufficientSample: return "样本不足"
        }
    }

    /// Counts toward consecutive-fail window (design §5.5).
    var countsAsConsecutiveFail: Bool { self == .fail }
}

/// Wire / DB badge tokens for proxy agents (design §3; home feed uses `proxy_gold`).
enum ProxyAgentBadgeToken: String, Codable, Sendable, CaseIterable, Equatable {
    case goldProxy = "gold_proxy"
    case proxyGold = "proxy_gold"
    case proxyProbation = "proxy_probation"

    var isGold: Bool { self == .goldProxy || self == .proxyGold }
    var isProbation: Bool { self == .proxyProbation }

    var displayLabel: String {
        switch self {
        case .goldProxy, .proxyGold: return "金牌代拍"
        case .proxyProbation: return "代拍（观察期）"
        }
    }

    static func parse(_ raw: String?) -> ProxyAgentBadgeToken? {
        guard let raw, !raw.isEmpty else { return nil }
        return ProxyAgentBadgeToken(rawValue: raw)
    }
}

// MARK: - Capabilities / privilege expiry

/// Capability keys used by proxy agents (design §3 / 4.2).
enum ProxyCapabilityKey: String, Codable, Sendable, CaseIterable, Equatable {
    case canFixed = "can_fixed"
    case canAuction = "can_auction"
    case canBatchList = "can_batch_list"
    case canInvoiceService = "can_invoice_service"
    case canSession = "can_session"
    case canPromote = "can_promote"

    var title: String {
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
struct ProxyCapabilities: Codable, Equatable, Sendable {
    var canFixed: Bool
    var canAuction: Bool
    var canBatchList: Bool
    var canInvoiceService: Bool
    var canSession: Bool
    var canPromote: Bool

    static let goldDefaults = ProxyCapabilities(
        canFixed: true, canAuction: true, canBatchList: true,
        canInvoiceService: true, canSession: true, canPromote: true
    )

    init(
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

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canFixed = try c.decodeIfPresent(Bool.self, forKey: .canFixed) ?? false
        canAuction = try c.decodeIfPresent(Bool.self, forKey: .canAuction) ?? false
        canBatchList = try c.decodeIfPresent(Bool.self, forKey: .canBatchList) ?? false
        canInvoiceService = try c.decodeIfPresent(Bool.self, forKey: .canInvoiceService) ?? false
        canSession = try c.decodeIfPresent(Bool.self, forKey: .canSession) ?? false
        canPromote = try c.decodeIfPresent(Bool.self, forKey: .canPromote) ?? false
    }

    func allows(_ key: ProxyCapabilityKey) -> Bool {
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
enum ProxyPrivilegeLogic {
    /// Capabilities that close on probation (降级).
    static let closedOnProbation: [ProxyCapabilityKey] = [.canPromote, .canSession]

    /// Extra capabilities that close on revoke (取消资格), beyond probation.
    static let closedOnRevoke: [ProxyCapabilityKey] = [
        .canPromote, .canSession, .canBatchList, .canInvoiceService, .canAuction,
    ]

    static func applyLevel(
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
    static func lostPrivilegeTitles(from: ProxyAssessmentLevel, to: ProxyAssessmentLevel) -> [String] {
        let before = Set(enabledKeys(applyLevel(from)))
        let after = Set(enabledKeys(applyLevel(to)))
        return ProxyCapabilityKey.allCases
            .filter { before.contains($0) && !after.contains($0) }
            .map(\.title)
    }

    static func enabledKeys(_ caps: ProxyCapabilities) -> [ProxyCapabilityKey] {
        ProxyCapabilityKey.allCases.filter { caps.allows($0) }
    }

    /// Consecutive fail → next level (design §4).
    static func nextLevel(
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

enum ProxyMetricKind: String, Codable, Sendable, CaseIterable, Equatable {
    case shipOnTime = "ship_on_time_rate"
    case afterSale = "after_sale_rate"
    case defaultRate = "default_rate"
    case arbitrationLoss = "arbitration_loss_rate"

    var title: String {
        switch self {
        case .shipOnTime: return "发货时效"
        case .afterSale: return "售后率"
        case .defaultRate: return "违约率"
        case .arbitrationLoss: return "仲裁败诉率"
        }
    }

    var threshold: Double {
        switch self {
        case .shipOnTime: return ProxyAgentConfigDefaults.shipOnTimeThreshold
        case .afterSale: return ProxyAgentConfigDefaults.afterSaleThreshold
        case .defaultRate: return ProxyAgentConfigDefaults.defaultRateThreshold
        case .arbitrationLoss: return ProxyAgentConfigDefaults.arbitrationLossThreshold
        }
    }

    /// Higher-is-better vs lower-is-better (design §5.5).
    var higherIsBetter: Bool { self == .shipOnTime }

    var thresholdLabel: String {
        let pct = Int((threshold * 100).rounded())
        return higherIsBetter ? "≥\(pct)%" : "≤\(pct)%"
    }

    var definition: String {
        switch self {
        case .shipOnTime: return "付款后 72h 内发货订单 / 应发货订单"
        case .afterSale: return "售后期完结订单中发起售后 / 完成订单"
        case .defaultRate: return "卖家责取消+发货超时取消 / 成交订单"
        case .arbitrationLoss: return "败诉案件 / 仲裁案件；分母=0 视为达标"
        }
    }
}

enum ProxyMetricLogic {
    /// Single metric pass (design §5.5). `nil` rate with arbitration + zero denom → pass.
    static func meetsThreshold(kind: ProxyMetricKind, rate: Double?, arbitrationDenomZero: Bool = false) -> Bool {
        if kind == .arbitrationLoss, arbitrationDenomZero { return true }
        guard let rate else { return false }
        if kind.higherIsBetter {
            return rate + 1e-12 >= kind.threshold
        }
        return rate - 1e-12 <= kind.threshold
    }

    static func sampleEligible(orderCount: Int) -> Bool {
        orderCount >= ProxyAgentConfigDefaults.minSampleOrders
    }

    /// Derive month result from four rates (warn unused locally — server may emit warn).
    static func evaluateMonth(
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

    static func formatRate(_ rate: Double?) -> String {
        guard let rate else { return "—" }
        let pct = rate * 100
        return String(format: "%.1f%%", pct)
    }
}

// MARK: - Buyer badge resolution (PXY-02 / §14)

enum ProxyBadgeLogic {
    /// Gold chip only when `assessment_level=gold` (design §14). Server feed badge still authoritative when level absent.
    static func buyerVisibleLabel(
        assessmentLevel: ProxyAssessmentLevel?,
        badgeRaw: String?
    ) -> String? {
        if let level = assessmentLevel {
            return level.buyerBadgeLabel
        }
        return ProxyAgentBadgeToken.parse(badgeRaw)?.displayLabel
    }

    /// Map profile fields → feed `SellerBadge` (keeps home chip enum in sync).
    static func sellerBadge(
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

    static func fulfillmentResponsibilityCopy(isProxyAgent: Bool) -> String? {
        isProxyAgent ? ProxyAgentCopy.fulfillmentResponsibility : nil
    }
}

// MARK: - Error codes / copy

enum ProxyAgentErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case inviteInvalid = "invite_invalid"
    case inviteQuotaExceeded = "invite_quota_exceeded"
    case realNameRequired = "real_name_required"
    case depositRequired = "deposit_required"
    case capabilityDisabled = "capability_disabled"
    case batchRowInvalid = "batch_row_invalid"
    case unauthorized
    case applicationRejected = "application_rejected"
    case consignContractRejected = "consign_contract_rejected"

    var opensLogin: Bool { self == .unauthorized }
    var opensRealName: Bool { self == .realNameRequired }

    var fallbackMessage: String {
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

enum ProxyAgentCopy {
    static let goldBadge = "金牌代拍"
    static let probationBadge = "代拍（观察期）"
    static let fulfillmentResponsibility = "由卖家本人发货并承担售后"
    static let noConsignorSwitch = "平台不提供「代委托人发货」开关"
    static let consignRejected = "平台不登记委托关系，请删除后提交"
    static let protocolSummary = "你以自己名义出售；委托人不是平台用户关系。"
    static let costPriceHint = "可选，仅自己看利润，平台不对任何人打款"
    static let batchNeedProxy = "需代拍身份"
    static let assessmentTitle = "代拍考核"
    static let forecastHint = "近 30 天预测，非终值"
    static let downgradeTitle = "代拍权益已调整"
    static let downgradeOrdersSafe = "在途订单仍由你本人发货售后，不受影响"
    static let downgradeAppeal = "如有异议可联系运营申诉"
    static let badgePageTitle = "代拍标识"
    static let onboardingSteps = ["资料", "保证金", "审核", "进件"]
}

// MARK: - DTOs

/// `GET /api/v1/me/seller` projection extras for proxy agents (design §6).
struct ProxySellerProfile: Codable, Equatable, Sendable {
    let userId: Int64?
    let sellerType: String?
    let badge: String?
    let assessmentLevel: ProxyAssessmentLevel?
    let feeTierId: String?
    let onboardingStatus: String?
    let capabilities: ProxyCapabilities?
    let subMerchantId: String?

    init(
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

    var isProxyAgent: Bool {
        sellerType == ProxyAgentConfigDefaults.sellerType
    }

    var buyerBadgeLabel: String? {
        ProxyBadgeLogic.buyerVisibleLabel(assessmentLevel: assessmentLevel, badgeRaw: badge)
    }

    var sellerBadge: SellerBadge? {
        ProxyBadgeLogic.sellerBadge(assessmentLevel: assessmentLevel, badgeRaw: badge)
    }
}

/// One month row from `GET /merchant/v1/assessments` (design §3 / §6).
struct ProxyAssessmentMonth: Codable, Equatable, Sendable, Identifiable {
    let sellerId: Int64?
    let yearMonth: String
    let shipOnTimeRate: Double?
    let afterSaleRate: Double?
    let defaultRate: Double?
    let arbitrationLossRate: Double?
    let orderCount: Int?
    let arbitrationCaseCount: Int?
    let result: ProxyAssessmentResult?
    let decidedAt: Date?
    let manualOverride: Bool?
    let skipAuto: Bool?

    var id: String { yearMonth }

    init(
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

    func rate(for kind: ProxyMetricKind) -> Double? {
        switch kind {
        case .shipOnTime: return shipOnTimeRate
        case .afterSale: return afterSaleRate
        case .defaultRate: return defaultRate
        case .arbitrationLoss: return arbitrationLossRate
        }
    }

    func meets(_ kind: ProxyMetricKind) -> Bool {
        ProxyMetricLogic.meetsThreshold(
            kind: kind,
            rate: rate(for: kind),
            arbitrationDenomZero: kind == .arbitrationLoss && (arbitrationCaseCount ?? 0) == 0
        )
    }
}

struct ProxyAssessmentListResponse: Codable, Equatable, Sendable {
    let items: [ProxyAssessmentMonth]
    let forecast: ProxyAssessmentForecast?

    init(items: [ProxyAssessmentMonth] = [], forecast: ProxyAssessmentForecast? = nil) {
        self.items = items
        self.forecast = forecast
    }
}

/// Near-30-day forecast — labeled non-final (design §9).
struct ProxyAssessmentForecast: Codable, Equatable, Sendable {
    let shipOnTimeRate: Double?
    let afterSaleRate: Double?
    let defaultRate: Double?
    let arbitrationLossRate: Double?
    let orderCount: Int?
    let windowDays: Int?
    let isFinal: Bool?

    init(
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

    var showsNonFinalBanner: Bool { !(isFinal ?? false) }

    func rate(for kind: ProxyMetricKind) -> Double? {
        switch kind {
        case .shipOnTime: return shipOnTimeRate
        case .afterSale: return afterSaleRate
        case .defaultRate: return defaultRate
        case .arbitrationLoss: return arbitrationLossRate
        }
    }
}

/// Downgrade / revoke notice payload for sheet (design §9).
struct ProxyDowngradeNotice: Equatable, Sendable, Identifiable {
    let from: ProxyAssessmentLevel
    let to: ProxyAssessmentLevel
    let lostTitles: [String]

    var id: String { "\(from.rawValue)->\(to.rawValue)" }

    init(from: ProxyAssessmentLevel, to: ProxyAssessmentLevel) {
        self.from = from
        self.to = to
        self.lostTitles = ProxyPrivilegeLogic.lostPrivilegeTitles(from: from, to: to)
    }

    var title: String { ProxyAgentCopy.downgradeTitle }
    var ordersSafe: String { ProxyAgentCopy.downgradeOrdersSafe }
    var appealHint: String { ProxyAgentCopy.downgradeAppeal }
}

/// Onboarding progress steps for proxy application UX (design §9).
enum ProxyOnboardingStep: String, Codable, Sendable, CaseIterable, Equatable {
    case materials
    case deposit
    case review
    case subMerchant = "sub_merchant"

    var title: String {
        switch self {
        case .materials: return "资料"
        case .deposit: return "保证金"
        case .review: return "审核"
        case .subMerchant: return "进件"
        }
    }

    var index: Int { ProxyOnboardingStep.allCases.firstIndex(of: self) ?? 0 }
}

enum ProxyOnboardingProgress {
    static var stepTitles: [String] { ProxyAgentCopy.onboardingSteps }

    /// Map merchant application dual status → current step highlight index (0…3).
    static func currentIndex(reviewStatus: String?, subMerchantStatus: String?, depositDone: Bool) -> Int {
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
