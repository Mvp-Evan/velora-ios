import Foundation
import CryptoKit

// MARK: - Proxy invoice service (DES-v1.3-05-02 PXY-04 / 7.8 / D20 — app mirror of VeloraCore)

/// Product defaults (design §3 / §5 / §15). Hot-config on server; client mirrors for UX.
enum InvoiceConfigDefaults {
    static let basis = InvoiceBasis.platformFee
    static let invoiceType = InvoiceType.vatESpecial
    static let taxRate: Double = 0.06
    static let dualReviewFen: Int64 = 1_000_000
    static let allowWithdrawDefault = false
    static let allowZeroOffsetOnly = true
    static let allowIdAsTaxNoDefault = false
    static let maxTitlesPerSeller = 3
    static let maxOrdersPerRequest = 100
    static let fileURLTTLMinutes = 10
    static let issuingStallHours = 1
    static let issuingAlertHours = 24
    static let launchGateKey = "launch_gate.proxy_invoice"
    static let notifyIssuedCode = "N-34"
    static let meEntryKey = "invoice"
    static let providerMock = "mock"
    static let fileNamePrefix = "毂毂_发票_"
    static let testingWatermark = "TESTING"
    static let shanghaiTimeZoneID = "Asia/Shanghai"
}

// MARK: - Enums

/// `invoice.basis` / basis_snapshot.basis (design §3).
enum InvoiceBasis: String, Codable, Sendable, CaseIterable, Equatable {
    case platformFee = "platform_fee"
    case gmv

    var label: String {
        switch self {
        case .platformFee: return "按平台服务费"
        case .gmv: return "按成交额"
        }
    }

    var plainExplanation: String {
        switch self {
        case .platformFee:
            return InvoiceCopy.basisPlatformFee
        case .gmv:
            return InvoiceCopy.basisGMV
        }
    }
}

/// `invoice.type` (design §3).
enum InvoiceType: String, Codable, Sendable, CaseIterable, Equatable {
    case vatESpecial = "vat_e_special"
    case vatENormal = "vat_e_normal"

    var displayLabel: String {
        switch self {
        case .vatESpecial: return "增值税电子专用发票"
        case .vatENormal: return "增值税电子普通发票"
        }
    }
}

/// Apply mode (design §5.11).
enum InvoiceMode: String, Codable, Sendable, CaseIterable, Equatable {
    case monthly
    case perOrder = "per_order"

    var displayLabel: String {
        switch self {
        case .monthly: return "按月开票"
        case .perOrder: return "按单开票"
        }
    }
}

/// `invoice_request.status` (design §4 / 7.8).
enum InvoiceRequestStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case draft
    case submitted
    case issuing
    case issued
    case rejected

    var displayLabel: String {
        switch self {
        case .draft: return "草稿"
        case .submitted: return "待审核"
        case .issuing: return "开具中"
        case .issued: return "已开具"
        case .rejected: return "已驳回"
        }
    }

    var isTerminal: Bool {
        self == .issued || self == .rejected
    }

    var locksPeriod: Bool {
        self == .submitted || self == .issuing
    }

    var canDownloadFile: Bool {
        self == .issued
    }

    var allowsTitleEdit: Bool {
        self == .draft || self == .rejected
    }
}

/// `invoice_request_item.lock_status` (design §5.6).
enum InvoiceItemLockStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case locked
    case invoiced
}

/// `invoice_offset.status` (design §3).
enum InvoiceOffsetStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pending
    case applied

    var displayLabel: String {
        switch self {
        case .pending: return "待冲减"
        case .applied: return "已核销"
        }
    }
}

/// Timeline step for App status strip (design §9).
enum InvoiceTimelineStep: String, Sendable, CaseIterable, Equatable {
    case submitted
    case review
    case issuing
    case downloadable

    var title: String {
        switch self {
        case .submitted: return "提交"
        case .review: return "审核"
        case .issuing: return "开具"
        case .downloadable: return "可下载"
        }
    }
}

// MARK: - Error codes

/// Stable API error codes (design §6 / §13).
enum InvoiceErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case launchGateClosed = "launch_gate_closed"
    case invoicePeriodLocked = "invoice_period_locked"
    case invoiceLockConflict = "invoice_lock_conflict"
    case nothingToInvoice = "nothing_to_invoice"
    case capabilityDisabled = "capability_disabled"
    case taxNoInvalid = "tax_no_invalid"
    case invoiceTitlePendingReview = "invoice_title_pending_review"
    case invoiceItemInAfterSale = "invoice_item_in_after_sale"
    case invoiceZeroNotOffset = "invoice_zero_not_offset"
    case invoiceFileNotReady = "invoice_file_not_ready"
    case forbidden
    case unauthorized

    var opensLogin: Bool { self == .unauthorized }

    var fallbackMessage: String {
        switch self {
        case .launchGateClosed: return InvoiceCopy.gateClosed
        case .invoicePeriodLocked: return "该周期已有进行中的开票申请"
        case .invoiceLockConflict: return "部分订单已被其他申请锁定，请刷新后重试"
        case .nothingToInvoice: return "暂无可开票金额"
        case .capabilityDisabled: return "开票能力已关闭，历史发票仍可下载"
        case .taxNoInvalid: return "税号格式不正确"
        case .invoiceTitlePendingReview: return "抬头税号变更审核中，请使用原抬头"
        case .invoiceItemInAfterSale: return "售后中的订单不可开票"
        case .invoiceZeroNotOffset: return "本期无可开票金额"
        case .invoiceFileNotReady: return "发票文件尚未就绪"
        case .forbidden: return "仅专职代拍可申请开票"
        case .unauthorized: return "请先登录"
        }
    }
}

// MARK: - Copy

enum InvoiceCopy {
    static let homeTitle = "代拍开票"
    static let applyTitle = "申请开票"
    static let detailTitle = "开票详情"
    static let titlesTitle = "发票抬头"
    static let gateClosed = "开票服务即将开通"
    static let gateClosedHint = "开通后即可按成交与分账记录申请电子发票"
    static let emptyPool = "本月暂无可开票订单"
    static let emptyPoolHint = "须待订单分账完成后方可开票"
    static let emptyHistory = "暂无开票记录"
    static let basisPlatformFee = "按你在毂毂成交产生的平台服务费开票"
    static let basisGMV = "按成交额开票（不含运费）"
    static let offsetLinePrefix = "上期退款冲减"
    static let rejectNextStep = "下一步：修改抬头/补充材料"
    static let issuingStall = "财务处理中，请稍候"
    static let contactSupport = "联系客服"
    static let offsetOnlyNote = "零金额核销（冲减）"
    static let mailFailedHint = "邮件未达，请下载"
    static let confirmSubmit = "确认提交"
    static let download = "下载发票"
    static let selectOrders = "勾选订单"
    static let monthlyNoPick = "按月开票包含期内全部可开票订单，不可剔除单笔"
    static let capabilityReadOnly = "当前不可新开票，可查看与下载历史发票"
    static let frozenDownloadOk = "账号冻结期间可下载历史发票，不可新开"
    static let taxInclusiveTotal = "价税合计"
    static let amountLabel = "开票金额"
    static let taxLabel = "税额"
    static let submitSuccess = "已提交，等待财务审核"
}

// MARK: - Snapshots / DTOs

/// Copied at submit time (design §3) — finance reads this only.
struct InvoiceBasisSnapshot: Codable, Equatable, Sendable {
    let basis: InvoiceBasis
    let taxRate: Double
    let issuerName: String?
    let invoiceType: InvoiceType?

    init(
        basis: InvoiceBasis = InvoiceConfigDefaults.basis,
        taxRate: Double = InvoiceConfigDefaults.taxRate,
        issuerName: String? = nil,
        invoiceType: InvoiceType? = InvoiceConfigDefaults.invoiceType
    ) {
        self.basis = basis
        self.taxRate = taxRate
        self.issuerName = issuerName
        self.invoiceType = invoiceType
    }

    var basisLabel: String { basis.label }
}

struct InvoiceRequestItem: Codable, Equatable, Sendable, Identifiable {
    var id: Int64 { orderId }
    let orderId: Int64
    let orderNo: String?
    let gmv: Int64
    let platformFee: Int64
    let refundedAmount: Int64
    let invoiceableAmount: Int64
    let lockStatus: InvoiceItemLockStatus?
    let settledAt: Date?
    let selectable: Bool?
    let blockReason: String?

    init(
        orderId: Int64,
        orderNo: String? = nil,
        gmv: Int64 = 0,
        platformFee: Int64 = 0,
        refundedAmount: Int64 = 0,
        invoiceableAmount: Int64 = 0,
        lockStatus: InvoiceItemLockStatus? = nil,
        settledAt: Date? = nil,
        selectable: Bool? = true,
        blockReason: String? = nil
    ) {
        self.orderId = orderId
        self.orderNo = orderNo
        self.gmv = gmv
        self.platformFee = platformFee
        self.refundedAmount = refundedAmount
        self.invoiceableAmount = invoiceableAmount
        self.lockStatus = lockStatus
        self.settledAt = settledAt
        self.selectable = selectable
        self.blockReason = blockReason
    }

    var isSelectable: Bool { selectable ?? (lockStatus == nil && blockReason == nil) }
}

struct InvoiceOffset: Codable, Equatable, Sendable, Identifiable {
    let id: Int64
    let sellerId: Int64?
    let sourceOrderId: Int64?
    let amount: Int64
    let targetPeriod: String?
    let status: InvoiceOffsetStatus

    init(
        id: Int64,
        sellerId: Int64? = nil,
        sourceOrderId: Int64? = nil,
        amount: Int64,
        targetPeriod: String? = nil,
        status: InvoiceOffsetStatus = .pending
    ) {
        self.id = id
        self.sellerId = sellerId
        self.sourceOrderId = sourceOrderId
        self.amount = amount
        self.targetPeriod = targetPeriod
        self.status = status
    }
}

struct InvoiceTitle: Codable, Equatable, Sendable, Identifiable {
    let id: Int64
    let sellerId: Int64?
    let title: String
    let taxNoMasked: String?
    let email: String?
    let emailMasked: String?
    let isDefault: Bool
    let pendingReview: Bool?

    init(
        id: Int64,
        sellerId: Int64? = nil,
        title: String,
        taxNoMasked: String? = nil,
        email: String? = nil,
        emailMasked: String? = nil,
        isDefault: Bool = false,
        pendingReview: Bool? = false
    ) {
        self.id = id
        self.sellerId = sellerId
        self.title = title
        self.taxNoMasked = taxNoMasked
        self.email = email
        self.emailMasked = emailMasked
        self.isDefault = isDefault
        self.pendingReview = pendingReview
    }

    var displayEmail: String {
        emailMasked ?? email ?? ""
    }

    var isPendingReview: Bool { pendingReview == true }
}

struct InvoiceRequest: Codable, Equatable, Sendable, Identifiable {
    let id: Int64
    let sellerId: Int64?
    let mode: InvoiceMode
    let period: String
    let basisSnapshot: InvoiceBasisSnapshot?
    let amount: Int64
    let taxAmount: Int64
    let title: String?
    let taxNoMasked: String?
    let email: String?
    let emailMasked: String?
    let status: InvoiceRequestStatus
    let invoiceNo: String?
    let rejectReason: String?
    let offsetOnly: Bool?
    let mailDelivered: Bool?
    let items: [InvoiceRequestItem]?
    let offsets: [InvoiceOffset]?
    let submittedAt: Date?
    let issuedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    init(
        id: Int64,
        sellerId: Int64? = nil,
        mode: InvoiceMode,
        period: String,
        basisSnapshot: InvoiceBasisSnapshot? = nil,
        amount: Int64,
        taxAmount: Int64 = 0,
        title: String? = nil,
        taxNoMasked: String? = nil,
        email: String? = nil,
        emailMasked: String? = nil,
        status: InvoiceRequestStatus,
        invoiceNo: String? = nil,
        rejectReason: String? = nil,
        offsetOnly: Bool? = nil,
        mailDelivered: Bool? = nil,
        items: [InvoiceRequestItem]? = nil,
        offsets: [InvoiceOffset]? = nil,
        submittedAt: Date? = nil,
        issuedAt: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.sellerId = sellerId
        self.mode = mode
        self.period = period
        self.basisSnapshot = basisSnapshot
        self.amount = amount
        self.taxAmount = taxAmount
        self.title = title
        self.taxNoMasked = taxNoMasked
        self.email = email
        self.emailMasked = emailMasked
        self.status = status
        self.invoiceNo = invoiceNo
        self.rejectReason = rejectReason
        self.offsetOnly = offsetOnly
        self.mailDelivered = mailDelivered
        self.items = items
        self.offsets = offsets
        self.submittedAt = submittedAt
        self.issuedAt = issuedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var total: Int64 { amount + taxAmount }

    var isOffsetOnly: Bool { offsetOnly == true || (amount == 0 && status == .issued && invoiceNo == nil) }

    var canDownload: Bool {
        status.canDownloadFile && !isOffsetOnly && invoiceNo != nil
    }

    var displayEmail: String { emailMasked ?? email ?? "" }

    var fileDownloadName: String? {
        guard let invoiceNo, !invoiceNo.isEmpty else { return nil }
        return "\(InvoiceConfigDefaults.fileNamePrefix)\(invoiceNo).pdf"
    }
}

/// Preview response (design §6).
struct InvoicePreview: Codable, Equatable, Sendable {
    let mode: InvoiceMode?
    let period: String?
    let basis: InvoiceBasis
    let basisLabel: String?
    let taxRate: Double?
    let invoiceType: InvoiceType?
    let issuerName: String?
    let items: [InvoiceRequestItem]
    let offsets: [InvoiceOffset]
    let amount: Int64
    let taxAmount: Int64
    let total: Int64
    let lockWarning: String?
    let launchGateOpen: Bool?
    let canSubmit: Bool?
    let offsetOnly: Bool?

    init(
        mode: InvoiceMode? = nil,
        period: String? = nil,
        basis: InvoiceBasis = InvoiceConfigDefaults.basis,
        basisLabel: String? = nil,
        taxRate: Double? = InvoiceConfigDefaults.taxRate,
        invoiceType: InvoiceType? = InvoiceConfigDefaults.invoiceType,
        issuerName: String? = nil,
        items: [InvoiceRequestItem] = [],
        offsets: [InvoiceOffset] = [],
        amount: Int64 = 0,
        taxAmount: Int64 = 0,
        total: Int64 = 0,
        lockWarning: String? = nil,
        launchGateOpen: Bool? = nil,
        canSubmit: Bool? = nil,
        offsetOnly: Bool? = nil
    ) {
        self.mode = mode
        self.period = period
        self.basis = basis
        self.basisLabel = basisLabel
        self.taxRate = taxRate
        self.invoiceType = invoiceType
        self.issuerName = issuerName
        self.items = items
        self.offsets = offsets
        self.amount = amount
        self.taxAmount = taxAmount
        self.total = total
        self.lockWarning = lockWarning
        self.launchGateOpen = launchGateOpen
        self.canSubmit = canSubmit
        self.offsetOnly = offsetOnly
    }

    var resolvedBasisLabel: String { basisLabel ?? basis.label }

    var pendingOffsetTotal: Int64 {
        offsets.filter { $0.status == .pending }.reduce(0) { $0 + $1.amount }
    }

    var isGateClosed: Bool { launchGateOpen == false }

    var allowsSubmit: Bool {
        if let canSubmit { return canSubmit }
        if isGateClosed { return false }
        return amount > 0 || (offsetOnly == true && InvoiceConfigDefaults.allowZeroOffsetOnly)
    }
}

struct InvoiceSubmitBody: Codable, Equatable, Sendable {
    let mode: InvoiceMode
    let period: String
    let titleId: Int64
    let orderIds: [Int64]?

    init(mode: InvoiceMode, period: String, titleId: Int64, orderIds: [Int64]? = nil) {
        self.mode = mode
        self.period = period
        self.titleId = titleId
        self.orderIds = orderIds
    }
}

struct InvoiceTitleUpsertBody: Codable, Equatable, Sendable {
    let title: String
    let taxNo: String
    let email: String
    let isDefault: Bool?

    init(title: String, taxNo: String, email: String, isDefault: Bool? = nil) {
        self.title = title
        self.taxNo = taxNo
        self.email = email
        self.isDefault = isDefault
    }
}

struct InvoiceFileResponse: Codable, Equatable, Sendable {
    let url: String?
    let expiresAt: Date?
    let filename: String?

    init(url: String? = nil, expiresAt: Date? = nil, filename: String? = nil) {
        self.url = url
        self.expiresAt = expiresAt
        self.filename = filename
    }
}

struct InvoiceHomeBootstrap: Codable, Equatable, Sendable {
    let launchGateOpen: Bool
    let canInvoiceService: Bool
    let titles: [InvoiceTitle]
    let recent: [InvoiceRequest]
    let defaultMode: InvoiceMode?
    let defaultPeriod: String?

    init(
        launchGateOpen: Bool = false,
        canInvoiceService: Bool = false,
        titles: [InvoiceTitle] = [],
        recent: [InvoiceRequest] = [],
        defaultMode: InvoiceMode? = .monthly,
        defaultPeriod: String? = nil
    ) {
        self.launchGateOpen = launchGateOpen
        self.canInvoiceService = canInvoiceService
        self.titles = titles
        self.recent = recent
        self.defaultMode = defaultMode
        self.defaultPeriod = defaultPeriod
    }

    var canCreateNew: Bool { launchGateOpen && canInvoiceService }
}

// MARK: - Logic

enum InvoiceLogic {
    // MARK: Amounts

    /// Per-order invoiceable fen before seller-level offsets (design §3 / §5.9).
    static func invoiceableAmount(
        basis: InvoiceBasis,
        gmv: Int64,
        platformFee: Int64,
        refundedAmount: Int64,
        alreadyInvoiced: Int64,
        feeRateSnapshot: Double? = nil
    ) -> Int64 {
        let already = max(0, alreadyInvoiced)
        switch basis {
        case .platformFee:
            let rate = feeRateSnapshot ?? InvoiceConfigDefaults.taxRate
            // Partial goods refund → fee offset = round(refund_goods × fee_rate_snapshot).
            let feeRefund = refundFeeOffset(refundedGoodsFen: refundedAmount, feeRate: rate)
            let netFee = max(0, platformFee - feeRefund)
            return max(0, netFee - already)
        case .gmv:
            return max(0, gmv - max(0, refundedAmount) - already)
        }
    }

    static func refundFeeOffset(refundedGoodsFen: Int64, feeRate: Double) -> Int64 {
        guard refundedGoodsFen > 0, feeRate > 0 else { return 0 }
        return Int64((Double(refundedGoodsFen) * feeRate).rounded())
    }

    /// Seller pool after pending offsets (design §5.4).
    static func poolAmount(itemTotals: Int64, pendingOffsets: Int64) -> Int64 {
        max(0, itemTotals - max(0, pendingOffsets))
    }

    /// Exclusive tax: tax = round(amount × rate); total = amount + tax (design §5.2 价税合计).
    static func taxAmount(amountFen: Int64, taxRate: Double = InvoiceConfigDefaults.taxRate) -> Int64 {
        guard amountFen > 0, taxRate > 0 else { return 0 }
        return Int64((Double(amountFen) * taxRate).rounded())
    }

    static func totalAmount(amountFen: Int64, taxRate: Double = InvoiceConfigDefaults.taxRate) -> Int64 {
        amountFen + taxAmount(amountFen: amountFen, taxRate: taxRate)
    }

    static func buildPreviewTotals(
        items: [InvoiceRequestItem],
        offsets: [InvoiceOffset],
        taxRate: Double = InvoiceConfigDefaults.taxRate,
        allowZeroOffsetOnly: Bool = InvoiceConfigDefaults.allowZeroOffsetOnly
    ) -> (amount: Int64, tax: Int64, total: Int64, offsetOnly: Bool) {
        let itemSum = items.reduce(Int64(0)) { $0 + $1.invoiceableAmount }
        let pending = offsets.filter { $0.status == .pending }.reduce(Int64(0)) { $0 + $1.amount }
        let amount = poolAmount(itemTotals: itemSum, pendingOffsets: pending)
        let offsetOnly = amount == 0 && pending > 0 && allowZeroOffsetOnly
        let tax = taxAmount(amountFen: amount, taxRate: taxRate)
        return (amount, tax, amount + tax, offsetOnly)
    }

    // MARK: Periods

    static func shanghaiTimeZone() -> TimeZone {
        TimeZone(identifier: InvoiceConfigDefaults.shanghaiTimeZoneID) ?? TimeZone(secondsFromGMT: 8 * 3600)!
    }

    static func shanghaiCalendar(now: Date = Date()) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = shanghaiTimeZone()
        _ = now
        return cal
    }

    /// Previous natural month `YYYY-MM` in Asia/Shanghai (design §4).
    static func previousMonthPeriod(now: Date = Date()) -> String {
        let cal = shanghaiCalendar(now: now)
        let comps = cal.dateComponents([.year, .month], from: now)
        guard let year = comps.year, let month = comps.month else {
            return "1970-01"
        }
        var y = year
        var m = month - 1
        if m <= 0 {
            m = 12
            y -= 1
        }
        return String(format: "%04d-%02d", y, m)
    }

    static func currentMonthPeriod(now: Date = Date()) -> String {
        let cal = shanghaiCalendar(now: now)
        let comps = cal.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", comps.year ?? 1970, comps.month ?? 1)
    }

    /// Same-month supplement period `YYYY-MM-supp-n` (design §4).
    static func supplementPeriod(base: String, n: Int) -> String {
        "\(base)-supp-\(max(1, n))"
    }

    /// Per-order period: sorted order_no set hash (design §5.11).
    static func perOrderPeriod(orderNos: [String]) -> String {
        let normalized = orderNos
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        let joined = normalized.joined(separator: ",")
        let digest = SHA256.hash(data: Data(joined.utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "order:\(hex)"
    }

    static func isMonthlyPeriod(_ period: String) -> Bool {
        period.range(of: #"^\d{4}-\d{2}(-supp-\d+)?$"#, options: .regularExpression) != nil
    }

    // MARK: Validation

    /// 18-digit USCC check digit (GB 32100) (design §13).
    static func isValidUSCC(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard s.count == 18 else { return false }
        let charset = Array("0123456789ABCDEFGHJKLMNPQRTUWXY")
        let weights = [1, 3, 9, 27, 81, 243, 729, 2187, 6561, 19683, 59049, 177147, 531441, 1594323, 4782969, 14348907, 43046721]
        var sum = 0
        for (i, ch) in s.prefix(17).enumerated() {
            guard let idx = charset.firstIndex(of: ch) else { return false }
            sum += idx * weights[i]
        }
        let mod = sum % 31
        let checkIdx = mod == 0 ? 0 : 31 - mod
        guard checkIdx < charset.count else { return false }
        return s.last == charset[checkIdx]
    }

    /// Optional 18-digit mainland ID when `invoice.allow_id_as_tax_no` (design §13).
    static func isValidMainlandID(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard s.count == 18 else { return false }
        let pattern = #"^\d{17}[\dX]$"#
        guard s.range(of: pattern, options: .regularExpression) != nil else { return false }
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        let checks = Array("10X98765432")
        var sum = 0
        for (i, ch) in s.prefix(17).enumerated() {
            guard let d = ch.wholeNumberValue else { return false }
            sum += d * weights[i]
        }
        return s.last == checks[sum % 11]
    }

    static func validateTaxNo(
        _ raw: String,
        allowID: Bool = InvoiceConfigDefaults.allowIdAsTaxNoDefault
    ) -> InvoiceErrorCode? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // ID-shaped strings are gated by allow_id_as_tax_no even if USCC checksum collides (design §13).
        if isIDShapedTaxNo(s) {
            guard allowID else { return .taxNoInvalid }
            return isValidMainlandID(s) ? nil : .taxNoInvalid
        }
        return isValidUSCC(s) ? nil : .taxNoInvalid
    }

    /// 18-char mainland ID shape: 17 digits + digit/X (not org USCC with letters).
    static func isIDShapedTaxNo(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return s.range(of: #"^\d{17}[\dX]$"#, options: .regularExpression) != nil
    }

    static func isValidEmail(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Lightweight RFC-ish check (design §13).
        guard s.count >= 5, s.count <= 254 else { return false }
        guard let at = s.firstIndex(of: "@"), at > s.startIndex else { return false }
        let domain = s[s.index(after: at)...]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return s.range(of: #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func validateTitleForm(title: String, taxNo: String, email: String, allowID: Bool = false) -> String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写抬头名称" }
        if validateTaxNo(taxNo, allowID: allowID) != nil { return InvoiceErrorCode.taxNoInvalid.fallbackMessage }
        if !isValidEmail(email) { return "请填写有效邮箱" }
        return nil
    }

    static func validateSubmitSelection(
        mode: InvoiceMode,
        orderIds: [Int64],
        maxOrders: Int = InvoiceConfigDefaults.maxOrdersPerRequest
    ) -> InvoiceErrorCode? {
        switch mode {
        case .monthly:
            return nil
        case .perOrder:
            if orderIds.isEmpty { return .nothingToInvoice }
            if orderIds.count > maxOrders { return .nothingToInvoice }
            return nil
        }
    }

    static func canAddTitle(existingCount: Int, max: Int = InvoiceConfigDefaults.maxTitlesPerSeller) -> Bool {
        existingCount < max
    }

    // MARK: State machine (design §4 / §5.10)

    static func canTransition(from: InvoiceRequestStatus, to: InvoiceRequestStatus) -> Bool {
        switch (from, to) {
        case (.draft, .submitted),
             (.submitted, .issuing),
             (.submitted, .rejected),
             (.issuing, .issued),
             (.issuing, .submitted),
             (.rejected, .submitted):
            return true
        default:
            return false
        }
    }

    static func canEditTitle(status: InvoiceRequestStatus) -> Bool {
        status.allowsTitleEdit
    }

    static func canWithdraw(
        status: InvoiceRequestStatus,
        allowWithdraw: Bool = InvoiceConfigDefaults.allowWithdrawDefault
    ) -> Bool {
        allowWithdraw && status == .submitted
    }

    static func requiresDualReview(
        amountFen: Int64,
        threshold: Int64 = InvoiceConfigDefaults.dualReviewFen
    ) -> Bool {
        amountFen >= threshold
    }

    static func showsIssuingStall(
        status: InvoiceRequestStatus,
        enteredIssuingAt: Date?,
        now: Date = Date(),
        stallHours: Int = InvoiceConfigDefaults.issuingStallHours
    ) -> Bool {
        guard status == .issuing, let entered = enteredIssuingAt else { return false }
        return now.timeIntervalSince(entered) >= TimeInterval(stallHours * 3600)
    }

    static func timeline(for status: InvoiceRequestStatus) -> [(InvoiceTimelineStep, Bool)] {
        let steps = InvoiceTimelineStep.allCases
        let activeIndex: Int
        switch status {
        case .draft:
            return steps.map { ($0, false) }
        case .submitted:
            activeIndex = 0
        case .rejected:
            return [
                (.submitted, true),
                (.review, true),
                (.issuing, false),
                (.downloadable, false),
            ]
        case .issuing:
            activeIndex = 2
        case .issued:
            activeIndex = 3
        }
        return steps.enumerated().map { idx, step in
            (step, idx <= activeIndex)
        }
    }

    static func yuanDisplay(_ fen: Int64) -> String {
        let yuan = Double(fen) / 100.0
        if fen % 100 == 0 {
            return String(format: "¥%.0f", yuan)
        }
        return String(format: "¥%.2f", yuan)
    }

    static func offsetLine(amountFen: Int64) -> String {
        "\(InvoiceCopy.offsetLinePrefix) -\(yuanDisplay(amountFen))"
    }

    static func maskEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let name = parts.first, let domain = parts.last, !name.isEmpty else {
            return email
        }
        let n = String(name)
        let head = n.prefix(1)
        return "\(head)***@\(domain)"
    }

    static func maskTaxNo(_ taxNo: String) -> String {
        let s = taxNo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 8 else { return s }
        return String(s.prefix(4)) + String(repeating: "*", count: max(0, s.count - 8)) + String(s.suffix(4))
    }

    /// Client gate before calling submit (design §5.1 / §5.8).
    static func submitGate(
        isLoggedIn: Bool,
        isProxyAgent: Bool,
        canInvoiceService: Bool,
        launchGateOpen: Bool,
        accountFrozen: Bool
    ) -> InvoiceErrorCode? {
        if !isLoggedIn { return .unauthorized }
        if !isProxyAgent { return .forbidden }
        if accountFrozen { return .capabilityDisabled }
        if !canInvoiceService { return .capabilityDisabled }
        if !launchGateOpen { return .launchGateClosed }
        return nil
    }
}
