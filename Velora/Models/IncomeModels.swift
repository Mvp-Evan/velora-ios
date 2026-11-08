import Foundation

// MARK: - Fee quote / income / profit / tax invoice (DES-v1.3-08-04 FIN-01～08 / D32 — app mirror of VeloraCore)

/// Product defaults (design §6 / B-02 / 8.1). Hot-config on server; client mirrors for UX + tests.
enum IncomeConfigDefaults {
    static let meEntryKey = "profit"
    static let launchGateServiceFeeInvoice = "launch_gate.service_fee_invoice"
    static let flagFeeMatrixV13 = "fee.matrix_v13"

    static let personalFixedBp = 100
    static let personalAuctionBp = 200
    static let proxyTier1GmvFen: Int64 = 100_000_000 // ¥10 万
    static let proxyTier1Bp = 900
    static let proxyTier2GmvFen: Int64 = 500_000_000 // ¥50 万
    static let proxyTier2Bp = 700
    static let proxyTier3Bp = 500
    static let brandDefaultBp = 300
    static let channelBp = 60
    static let channelBearer = ChannelFeeBearer.platform

    static let costImportMaxRows = 500
    static let incomeExportType = "income"
    static let notifyIncomeExportCode = "N-35"
    static let shanghaiTimeZoneID = "Asia/Shanghai"
    static let missingProfitDisplay = "—"
    static let serviceFeeInvoiceLaunchDefault = false
}

// MARK: - Channel fee bearer

enum ChannelFeeBearer: String, Codable, Sendable, CaseIterable, Equatable {
    case platform
    case seller

    static func normalize(_ raw: String?) -> ChannelFeeBearer {
        guard let raw, !raw.isEmpty else { return .platform }
        return ChannelFeeBearer(rawValue: raw.lowercased()) ?? .platform
    }

    var displayLabel: String {
        switch self {
        case .platform: return "平台承担"
        case .seller: return "卖家承担"
        }
    }
}

// MARK: - Error codes (design §6 / §7)

enum IncomeErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case feeRuleMissing = "fee_rule_missing"
    case notLaunched = "not_launched"
    case forbidden = "forbidden"
    case periodEmpty = "period_empty"
    case taxNoInvalid = "tax_no_invalid"
    case notFound = "not_found"

    static func normalize(_ raw: String?) -> IncomeErrorCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = IncomeErrorCode(rawValue: s) { return exact }
        switch s {
        case "http_404", "404":
            return .notFound
        case "http_403", "403", "access_denied":
            return .forbidden
        case "launch_gate_closed", "service_fee_invoice_not_launched":
            return .notLaunched
        case "fee_missing", "no_fee_rule":
            return .feeRuleMissing
        case "empty_period", "no_settled_fee":
            return .periodEmpty
        case "invalid_tax_no", "tax_number_invalid":
            return .taxNoInvalid
        default:
            return nil
        }
    }

    var fallbackMessage: String {
        switch self {
        case .feeRuleMissing: return IncomeCopy.feeRuleMissing
        case .notLaunched: return IncomeCopy.invoiceNotLaunched
        case .forbidden: return IncomeCopy.forbidden
        case .periodEmpty: return IncomeCopy.periodEmpty
        case .taxNoInvalid: return IncomeCopy.taxNoInvalid
        case .notFound: return IncomeCopy.costNotFound
        }
    }
}

// MARK: - Fee matrix quote (FIN-01 / 5.8 / 5.11)

/// Integer round-half-up fee quote shared by estimate + deal snapshot (design §5.1 / §5.8).
enum FeeMatrixQuoteLogic {
    /// `(amount * rate_bp + 5000) / 10000` — 0.5 分进 1 分；运费不计费基。
    static func platformFeeFen(amountFen: Int64, rateBp: Int) -> Int64 {
        let amount = max(Int64(0), amountFen)
        let bp = max(0, rateBp)
        return (amount * Int64(bp) + 5_000) / 10_000
    }

    static func channelFeeFen(payAmountFen: Int64, channelBp: Int = IncomeConfigDefaults.channelBp) -> Int64 {
        platformFeeFen(amountFen: payAmountFen, rateBp: channelBp)
    }

    /// Proxy whole-order rate from last-month GMV (design §5.8 / B-02) — not progressive brackets.
    static func proxyRateBp(gmvLastMonthFen: Int64) -> Int {
        if gmvLastMonthFen < IncomeConfigDefaults.proxyTier1GmvFen {
            return IncomeConfigDefaults.proxyTier1Bp
        }
        if gmvLastMonthFen < IncomeConfigDefaults.proxyTier2GmvFen {
            return IncomeConfigDefaults.proxyTier2Bp
        }
        return IncomeConfigDefaults.proxyTier3Bp
    }

    static func defaultRateBp(sellerType: String, tradeType: String) -> Int? {
        switch sellerType.lowercased() {
        case "personal":
            switch tradeType.lowercased() {
            case "auction": return IncomeConfigDefaults.personalAuctionBp
            case "fixed", "fixed_price", "buy_now": return IncomeConfigDefaults.personalFixedBp
            default: return IncomeConfigDefaults.personalFixedBp
            }
        case "proxy_agent", "proxy":
            return nil // needs gmv_last_month
        case "brand", "merchant":
            return IncomeConfigDefaults.brandDefaultBp
        default:
            return nil
        }
    }

    static func quote(
        amountFen: Int64,
        rateBp: Int,
        buyerShippingFen: Int64 = 0,
        refundedFen: Int64 = 0,
        payAmountFen: Int64? = nil,
        channelBp: Int = IncomeConfigDefaults.channelBp,
        channelBearer: ChannelFeeBearer = IncomeConfigDefaults.channelBearer
    ) -> FeeMatrixQuote {
        let fee = platformFeeFen(amountFen: amountFen, rateBp: rateBp)
        let pay = payAmountFen ?? (amountFen + max(0, buyerShippingFen))
        let channel = channelFeeFen(payAmountFen: pay, channelBp: channelBp)
        let sellerChannelDeduction = channelBearer == .seller ? channel : 0
        let sellerNet = amountFen + max(0, buyerShippingFen) - fee - max(0, refundedFen) - sellerChannelDeduction
        let platformNet = fee - (channelBearer == .platform ? channel : 0)
        return FeeMatrixQuote(
            amountFen: amountFen,
            rateBp: rateBp,
            platformFeeFen: fee,
            buyerShippingFen: buyerShippingFen,
            refundedFen: refundedFen,
            channelFeeFen: channel,
            channelFeeBearer: channelBearer,
            sellerNetFen: sellerNet,
            platformNetFen: platformNet
        )
    }
}

struct FeeMatrixQuote: Equatable, Sendable, Hashable {
    let amountFen: Int64
    let rateBp: Int
    let platformFeeFen: Int64
    let buyerShippingFen: Int64
    let refundedFen: Int64
    let channelFeeFen: Int64
    let channelFeeBearer: ChannelFeeBearer
    let sellerNetFen: Int64
    let platformNetFen: Int64

    init(
        amountFen: Int64,
        rateBp: Int,
        platformFeeFen: Int64,
        buyerShippingFen: Int64 = 0,
        refundedFen: Int64 = 0,
        channelFeeFen: Int64,
        channelFeeBearer: ChannelFeeBearer,
        sellerNetFen: Int64,
        platformNetFen: Int64
    ) {
        self.amountFen = amountFen
        self.rateBp = rateBp
        self.platformFeeFen = platformFeeFen
        self.buyerShippingFen = buyerShippingFen
        self.refundedFen = refundedFen
        self.channelFeeFen = channelFeeFen
        self.channelFeeBearer = channelFeeBearer
        self.sellerNetFen = sellerNetFen
        self.platformNetFen = platformNetFen
    }

    var rate: Double { Double(rateBp) / 10_000.0 }
}

// MARK: - Deal fee_rule_snapshot (FIN-01)

/// Deal-time fee snapshot fields beyond list-safe rule meta (design §3 / §5.11).
struct FeeDealSnapshot: Codable, Equatable, Sendable, Hashable {
    let ruleId: String?
    let rateBp: Int?
    let sellerType: String?
    let tradeType: String?
    let category: String?
    let campaignId: String?
    let tierBasis: String?
    let gmvLastMonth: Int64?
    let channelFeeBearer: String?
    let channelFeeBp: Int?
    let ruleVersion: String?
    let platformFee: Int64?
    let channelFee: Int64?
    let sellerNet: Int64?
    let shippingFee: Int64?

    init(
        ruleId: String? = nil,
        rateBp: Int? = nil,
        sellerType: String? = nil,
        tradeType: String? = nil,
        category: String? = nil,
        campaignId: String? = nil,
        tierBasis: String? = nil,
        gmvLastMonth: Int64? = nil,
        channelFeeBearer: String? = nil,
        channelFeeBp: Int? = nil,
        ruleVersion: String? = nil,
        platformFee: Int64? = nil,
        channelFee: Int64? = nil,
        sellerNet: Int64? = nil,
        shippingFee: Int64? = nil
    ) {
        self.ruleId = ruleId
        self.rateBp = rateBp
        self.sellerType = sellerType
        self.tradeType = tradeType
        self.category = category
        self.campaignId = campaignId
        self.tierBasis = tierBasis
        self.gmvLastMonth = gmvLastMonth
        self.channelFeeBearer = channelFeeBearer
        self.channelFeeBp = channelFeeBp
        self.ruleVersion = ruleVersion
        self.platformFee = platformFee
        self.channelFee = channelFee
        self.sellerNet = sellerNet
        self.shippingFee = shippingFee
    }

    var bearer: ChannelFeeBearer {
        ChannelFeeBearer.normalize(channelFeeBearer)
    }

    /// Buyer / ops without cost-read: strip rule internals that are not needed for display.
    func strippedForBuyer() -> FeeDealSnapshot {
        FeeDealSnapshot(
            ruleId: nil,
            rateBp: rateBp,
            sellerType: sellerType,
            tradeType: tradeType,
            category: category,
            campaignId: campaignId,
            tierBasis: nil,
            gmvLastMonth: nil,
            channelFeeBearer: channelFeeBearer,
            channelFeeBp: channelFeeBp,
            ruleVersion: ruleVersion,
            platformFee: platformFee,
            channelFee: channelFee,
            sellerNet: sellerNet,
            shippingFee: shippingFee
        )
    }
}

// MARK: - Order cost (FIN-02)

/// `order_costs` — seller-private; never enters profit-share (design §3 / §5.2 / §5.9).
struct OrderCost: Codable, Equatable, Sendable, Hashable, Identifiable {
    var id: Int64 { orderId }
    let orderId: Int64
    let costPrice: Int64?
    let actualShippingCost: Int64?
    let updatedBy: Int64?
    let updatedAt: Date?
    let version: Int64?

    init(
        orderId: Int64,
        costPrice: Int64? = nil,
        actualShippingCost: Int64? = nil,
        updatedBy: Int64? = nil,
        updatedAt: Date? = nil,
        version: Int64? = nil
    ) {
        self.orderId = orderId
        self.costPrice = costPrice
        self.actualShippingCost = actualShippingCost
        self.updatedBy = updatedBy
        self.updatedAt = updatedAt
        self.version = version
    }

    var hasCostPrice: Bool { costPrice != nil }
}

struct OrderCostUpdateRequest: Equatable, Sendable {
    var costPrice: Int64?
    var actualShippingCost: Int64?

    init(costPrice: Int64? = nil, actualShippingCost: Int64? = nil) {
        self.costPrice = costPrice
        self.actualShippingCost = actualShippingCost
    }

    var body: [String: Any] {
        var map: [String: Any] = [:]
        if let costPrice { map["cost_price"] = costPrice }
        if let actualShippingCost { map["actual_shipping_cost"] = actualShippingCost }
        return map
    }
}

struct CostImportResult: Codable, Equatable, Sendable {
    let imported: Int
    let skipped: Int
    let failed: [CostImportFailure]

    init(imported: Int = 0, skipped: Int = 0, failed: [CostImportFailure] = []) {
        self.imported = imported
        self.skipped = skipped
        self.failed = failed
    }
}

struct CostImportFailure: Codable, Equatable, Sendable, Hashable {
    let orderNo: String?
    let error: String?

    init(orderNo: String? = nil, error: String? = nil) {
        self.orderNo = orderNo
        self.error = error
    }
}

// MARK: - Income / profit views (FIN-02)

struct IncomeSummary: Codable, Equatable, Sendable, Hashable {
    let gmv: Int64
    let serviceFee: Int64
    let refund: Int64
    let shippingFee: Int64
    let channelFee: Int64
    let sellerNet: Int64
    /// Sum only over orders with cost filled; null when none have cost (design §5.2).
    let profit: Int64?
    let ordersMissingCost: Int
    let ordersWithCost: Int
    let ordersCount: Int

    init(
        gmv: Int64 = 0,
        serviceFee: Int64 = 0,
        refund: Int64 = 0,
        shippingFee: Int64 = 0,
        channelFee: Int64 = 0,
        sellerNet: Int64 = 0,
        profit: Int64? = nil,
        ordersMissingCost: Int = 0,
        ordersWithCost: Int = 0,
        ordersCount: Int = 0
    ) {
        self.gmv = gmv
        self.serviceFee = serviceFee
        self.refund = refund
        self.shippingFee = shippingFee
        self.channelFee = channelFee
        self.sellerNet = sellerNet
        self.profit = profit
        self.ordersMissingCost = ordersMissingCost
        self.ordersWithCost = ordersWithCost
        self.ordersCount = ordersCount
    }

    var missingCostHint: String? {
        guard ordersMissingCost > 0 else { return nil }
        return IncomeCopy.missingCostCount(ordersMissingCost)
    }
}

struct IncomeOrderLine: Codable, Equatable, Sendable, Hashable, Identifiable {
    let orderId: Int64
    let orderNo: String?
    let tradeType: String?
    let status: String?
    let title: String?
    let amount: Int64
    let shippingFee: Int64
    let platformFee: Int64
    let channelFee: Int64
    let channelFeeBearer: String?
    let refundedAmount: Int64
    let sellerNet: Int64
    /// Seller-only; omitted for buyer / unauthorized (design §5.9).
    let costPrice: Int64?
    let actualShippingCost: Int64?
    /// Null when cost empty → UI「—」.
    let profit: Int64?
    let feeRuleSnapshot: FeeDealSnapshot?
    let settledAt: Date?

    var id: Int64 { orderId }

    init(
        orderId: Int64,
        orderNo: String? = nil,
        tradeType: String? = nil,
        status: String? = nil,
        title: String? = nil,
        amount: Int64 = 0,
        shippingFee: Int64 = 0,
        platformFee: Int64 = 0,
        channelFee: Int64 = 0,
        channelFeeBearer: String? = nil,
        refundedAmount: Int64 = 0,
        sellerNet: Int64 = 0,
        costPrice: Int64? = nil,
        actualShippingCost: Int64? = nil,
        profit: Int64? = nil,
        feeRuleSnapshot: FeeDealSnapshot? = nil,
        settledAt: Date? = nil
    ) {
        self.orderId = orderId
        self.orderNo = orderNo
        self.tradeType = tradeType
        self.status = status
        self.title = title
        self.amount = amount
        self.shippingFee = shippingFee
        self.platformFee = platformFee
        self.channelFee = channelFee
        self.channelFeeBearer = channelFeeBearer
        self.refundedAmount = refundedAmount
        self.sellerNet = sellerNet
        self.costPrice = costPrice
        self.actualShippingCost = actualShippingCost
        self.profit = profit
        self.feeRuleSnapshot = feeRuleSnapshot
        self.settledAt = settledAt
    }

    enum CodingKeys: String, CodingKey {
        case orderId, orderNo, tradeType, status, title, amount
        case shippingFee, platformFee, channelFee, channelFeeBearer
        case refundedAmount, sellerNet, sellerReceipt, costPrice, actualShippingCost
        case profit, feeRuleSnapshot, settledAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orderId = try c.decode(Int64.self, forKey: .orderId)
        orderNo = try c.decodeIfPresent(String.self, forKey: .orderNo)
        tradeType = try c.decodeIfPresent(String.self, forKey: .tradeType)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        amount = try c.decodeIfPresent(Int64.self, forKey: .amount) ?? 0
        shippingFee = try c.decodeIfPresent(Int64.self, forKey: .shippingFee) ?? 0
        platformFee = try c.decodeIfPresent(Int64.self, forKey: .platformFee) ?? 0
        channelFee = try c.decodeIfPresent(Int64.self, forKey: .channelFee) ?? 0
        channelFeeBearer = try c.decodeIfPresent(String.self, forKey: .channelFeeBearer)
        refundedAmount = try c.decodeIfPresent(Int64.self, forKey: .refundedAmount) ?? 0
        sellerNet = try c.decodeIfPresent(Int64.self, forKey: .sellerNet)
            ?? c.decodeIfPresent(Int64.self, forKey: .sellerReceipt)
            ?? 0
        costPrice = try c.decodeIfPresent(Int64.self, forKey: .costPrice)
        actualShippingCost = try c.decodeIfPresent(Int64.self, forKey: .actualShippingCost)
        profit = try c.decodeIfPresent(Int64.self, forKey: .profit)
        feeRuleSnapshot = try c.decodeIfPresent(FeeDealSnapshot.self, forKey: .feeRuleSnapshot)
        settledAt = try c.decodeIfPresent(Date.self, forKey: .settledAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(orderId, forKey: .orderId)
        try c.encodeIfPresent(orderNo, forKey: .orderNo)
        try c.encodeIfPresent(tradeType, forKey: .tradeType)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(amount, forKey: .amount)
        try c.encode(shippingFee, forKey: .shippingFee)
        try c.encode(platformFee, forKey: .platformFee)
        try c.encode(channelFee, forKey: .channelFee)
        try c.encodeIfPresent(channelFeeBearer, forKey: .channelFeeBearer)
        try c.encode(refundedAmount, forKey: .refundedAmount)
        try c.encode(sellerNet, forKey: .sellerNet)
        try c.encodeIfPresent(costPrice, forKey: .costPrice)
        try c.encodeIfPresent(actualShippingCost, forKey: .actualShippingCost)
        try c.encodeIfPresent(profit, forKey: .profit)
        try c.encodeIfPresent(feeRuleSnapshot, forKey: .feeRuleSnapshot)
        try c.encodeIfPresent(settledAt, forKey: .settledAt)
    }

    var hasCost: Bool { costPrice != nil }
    var profitDisplay: String {
        IncomeProfitLogic.profitDisplay(profit)
    }

    var bearer: ChannelFeeBearer {
        ChannelFeeBearer.normalize(channelFeeBearer ?? feeRuleSnapshot?.channelFeeBearer)
    }
}

struct IncomePage: Codable, Equatable, Sendable {
    let period: String
    let summary: IncomeSummary
    let items: [IncomeOrderLine]
    let page: Int
    let pageSize: Int
    let total: Int
    let sellerType: String?

    init(
        period: String,
        summary: IncomeSummary = IncomeSummary(),
        items: [IncomeOrderLine] = [],
        page: Int = 1,
        pageSize: Int = 20,
        total: Int = 0,
        sellerType: String? = nil
    ) {
        self.period = period
        self.summary = summary
        self.items = items
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.sellerType = sellerType
    }

    enum CodingKeys: String, CodingKey {
        case period, summary, items, page, pageSize, total, sellerType
        case gmv, serviceFee, refund, profit, missingCostN, ordersCount, shippingFee, channelFee, sellerNet
        case ordersMissingCost, ordersWithCost
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        period = try c.decodeIfPresent(String.self, forKey: .period) ?? ""
        items = try c.decodeIfPresent([IncomeOrderLine].self, forKey: .items) ?? []
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        pageSize = try c.decodeIfPresent(Int.self, forKey: .pageSize) ?? 20
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? items.count
        sellerType = try c.decodeIfPresent(String.self, forKey: .sellerType)
        if let nested = try c.decodeIfPresent(IncomeSummary.self, forKey: .summary) {
            summary = nested
        } else {
            let missing = try c.decodeIfPresent(Int.self, forKey: .missingCostN)
                ?? c.decodeIfPresent(Int.self, forKey: .ordersMissingCost)
                ?? 0
            let count = try c.decodeIfPresent(Int.self, forKey: .ordersCount) ?? 0
            summary = IncomeSummary(
                gmv: try c.decodeIfPresent(Int64.self, forKey: .gmv) ?? 0,
                serviceFee: try c.decodeIfPresent(Int64.self, forKey: .serviceFee) ?? 0,
                refund: try c.decodeIfPresent(Int64.self, forKey: .refund) ?? 0,
                shippingFee: try c.decodeIfPresent(Int64.self, forKey: .shippingFee) ?? 0,
                channelFee: try c.decodeIfPresent(Int64.self, forKey: .channelFee) ?? 0,
                sellerNet: try c.decodeIfPresent(Int64.self, forKey: .sellerNet) ?? 0,
                profit: try c.decodeIfPresent(Int64.self, forKey: .profit),
                ordersMissingCost: missing,
                ordersWithCost: try c.decodeIfPresent(Int.self, forKey: .ordersWithCost) ?? max(0, count - missing),
                ordersCount: count
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(period, forKey: .period)
        try c.encode(summary, forKey: .summary)
        try c.encode(items, forKey: .items)
        try c.encode(page, forKey: .page)
        try c.encode(pageSize, forKey: .pageSize)
        try c.encode(total, forKey: .total)
        try c.encodeIfPresent(sellerType, forKey: .sellerType)
    }

    var isEmpty: Bool { total == 0 && items.isEmpty && summary.ordersCount == 0 }
    var isProxyAgent: Bool {
        let t = (sellerType ?? "").lowercased()
        return t == "proxy_agent" || t == "proxy"
    }
}

struct IncomeExportRequest: Equatable, Sendable {
    var period: String
    var format: String

    init(period: String, format: String = "xlsx") {
        self.period = period
        self.format = format
    }

    var body: [String: Any] {
        ["period": period, "format": format]
    }
}

struct IncomeExportJob: Codable, Equatable, Sendable, Hashable, Identifiable {
    let id: Int64
    let type: String?
    let period: String?
    let status: String?
    let format: String?
    let fileURL: String?
    let expiresAt: Date?

    init(
        id: Int64,
        type: String? = IncomeConfigDefaults.incomeExportType,
        period: String? = nil,
        status: String? = nil,
        format: String? = nil,
        fileURL: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.period = period
        self.status = status
        self.format = format
        self.fileURL = fileURL
        self.expiresAt = expiresAt
    }
}

// MARK: - Service fee invoice (FIN-05) — Phase 3 gated

struct ServiceFeeInvoiceRequest: Codable, Equatable, Sendable, Hashable, Identifiable {
    let id: Int64
    let sellerId: Int64?
    let period: String?
    let amount: Int64
    let title: String?
    let taxNo: String?
    let email: String?
    let status: String?
    let rejectReason: String?

    init(
        id: Int64,
        sellerId: Int64? = nil,
        period: String? = nil,
        amount: Int64 = 0,
        title: String? = nil,
        taxNo: String? = nil,
        email: String? = nil,
        status: String? = nil,
        rejectReason: String? = nil
    ) {
        self.id = id
        self.sellerId = sellerId
        self.period = period
        self.amount = amount
        self.title = title
        self.taxNo = taxNo
        self.email = email
        self.status = status
        self.rejectReason = rejectReason
    }
}

struct ServiceFeeInvoiceSubmitBody: Equatable, Sendable {
    var period: String
    var title: String
    var taxNo: String
    var email: String?

    init(period: String, title: String, taxNo: String, email: String? = nil) {
        self.period = period
        self.title = title
        self.taxNo = taxNo
        self.email = email
    }

    var body: [String: Any] {
        var map: [String: Any] = [
            "period": period,
            "title": title,
            "tax_no": taxNo,
            "kind": "service_fee",
        ]
        if let email, !email.isEmpty { map["email"] = email }
        return map
    }
}

// MARK: - Profit formula (FIN-02 / 8.6)

enum IncomeProfitLogic {
    /// 卖家利润 = 卖家实收 − 实际运费 − 成本价；成本空则 nil（UI「—」）。
    static func profitFen(
        sellerNetFen: Int64,
        actualShippingCostFen: Int64?,
        costPriceFen: Int64?
    ) -> Int64? {
        guard let costPriceFen else { return nil }
        let ship = max(0, actualShippingCostFen ?? 0)
        return sellerNetFen - ship - costPriceFen
    }

    static func sellerNetFen(
        amountFen: Int64,
        buyerShippingFen: Int64,
        platformFeeFen: Int64,
        refundedFen: Int64,
        channelFeeFen: Int64,
        bearer: ChannelFeeBearer
    ) -> Int64 {
        let channelDeduction = bearer == .seller ? max(0, channelFeeFen) : 0
        return amountFen + max(0, buyerShippingFen) - max(0, platformFeeFen) - max(0, refundedFen) - channelDeduction
    }

    static func platformNetFen(
        platformFeeFen: Int64,
        channelFeeFen: Int64,
        bearer: ChannelFeeBearer
    ) -> Int64 {
        platformFeeFen - (bearer == .platform ? max(0, channelFeeFen) : 0)
    }

    /// Design §5.2 / §14 acceptance fixture: 2500 元 / 4% / 包邮 / 实际运费 20 / 成本 2000.
    static func acceptanceExample() -> (
        quote: FeeMatrixQuote,
        costPrice: Int64,
        actualShipping: Int64,
        profit: Int64
    ) {
        let quote = FeeMatrixQuoteLogic.quote(
            amountFen: 250_000,
            rateBp: 400,
            buyerShippingFen: 0,
            refundedFen: 0,
            payAmountFen: 250_000,
            channelBp: IncomeConfigDefaults.channelBp,
            channelBearer: .platform
        )
        let cost: Int64 = 200_000
        let ship: Int64 = 2_000
        let profit = profitFen(
            sellerNetFen: quote.sellerNetFen,
            actualShippingCostFen: ship,
            costPriceFen: cost
        ) ?? 0
        return (quote, cost, ship, profit)
    }

    static func profitDisplay(_ profit: Int64?) -> String {
        guard let profit else { return IncomeConfigDefaults.missingProfitDisplay }
        let yuan = Double(profit) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = profit % 100 == 0 ? 0 : 2
        f.maximumFractionDigits = 2
        let body = f.string(from: NSNumber(value: yuan)) ?? "\(yuan)"
        return "¥" + body
    }

    static func showsServiceFeeInvoiceEntry(launchGateOpen: Bool) -> Bool {
        launchGateOpen
    }

    static func message(for code: String?, serverMessage: String?) -> String {
        if let normalized = IncomeErrorCode.normalize(code) {
            return normalized.fallbackMessage
        }
        if let serverMessage, !serverMessage.isEmpty { return serverMessage }
        return IncomeCopy.loadFailed
    }

    /// Period string `yyyy-MM` in Asia/Shanghai.
    static func currentMonthPeriod(now: Date = Date(), timeZone: TimeZone? = nil) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone ?? TimeZone(identifier: IncomeConfigDefaults.shanghaiTimeZoneID) ?? .current
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        return String(format: "%04d-%02d", y, m)
    }
}

// MARK: - Copy (design §9)

enum IncomeCopy {
    static let homeTitle = "收入与利润"
    static let formulaHint = "利润 = 实收 − 实际运费 − 成本价"
    static let proxyPrivacy = "仅自己可见，平台不按此结算"
    static let emptyOrders = "暂无结算订单"
    static let emptyHint = "结算完成后可在此查看收入与利润"
    static let missingCostGuide = "未填成本价时利润显示为 —，可点订单录入"
    static let costEntryTitle = "录入成本"
    static let costPriceLabel = "成本价"
    static let actualShippingLabel = "实际运费"
    static let costSaved = "成本已保存"
    static let gmvTitle = "成交额"
    static let gmvNotRevenue = "非营收"
    static let serviceFeeTitle = "平台服务费"
    static let sellerNetTitle = "卖家实收"
    static let profitTitle = "利润"
    static let channelFeeTitle = "通道费"
    static let refundTitle = "退款"
    static let exportCTA = "导出明细"
    static let exportQueued = "导出完成后通知你"
    static let importCTA = "批量导入成本"
    static let taxCenterCTA = "税务中心"
    static let serviceFeeInvoiceCTA = "服务费发票"
    static let feeRuleMissing = "暂无可用费率规则，无法成交"
    static let invoiceNotLaunched = "服务费发票尚未开放"
    static let forbidden = "无权查看收入或成本"
    static let periodEmpty = "该期间无可开票服务费"
    static let taxNoInvalid = "税号格式不正确"
    static let costNotFound = "订单不存在或无权录入成本"
    static let loadFailed = "加载失败，请稍后重试"
    static let buyerForbidden = "买家无法查看卖家利润"
    static let periodLabel = "账期"
    static let detailTitle = "订单收入"
    static let snapshotHint = "费率以成交快照为准，规则变更不影响本单"

    static func missingCostCount(_ n: Int) -> String {
        "\(n) 单未填成本"
    }
}
