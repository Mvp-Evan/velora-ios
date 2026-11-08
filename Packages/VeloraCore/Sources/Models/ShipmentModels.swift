import Foundation

// MARK: - Shipping / confirm / merge (DES-v1.3-07-02 ORD-04～10 / D28)

/// Product defaults (design §6). Hot-config on server; client mirrors for UX.
public enum ShipmentConfigDefaults {
    public static let confirmDays = 10
    public static let shipAuctionFixedHours = 72
    public static let shipSpotLotteryHours = 48
    public static let shipGraceHours = 24
    public static let insuredThresholdFen: Int64 = 200_000
    public static let mergeShipMax = 20
    public static let waybillImportMaxRows = 500
    public static let waybillImportMaxBytes = 5 * 1024 * 1024
    public static let confirmResumeMinSec = 3_600
    public static let trackingPollMin = 30
    public static let n19HoursBefore = 24
    public static let n18HoursBefore = 12
    public static let confirmDaySec = confirmDays * 86_400
    /// Do not shorten confirm window via sign when remaining already < 24h.
    public static let confirmSignProtectSec = 86_400
    public static let featureFlagMerge = "order.merge_ship"
    public static let featureFlagMergePay = "order.merge_pay"
    public static let waybillResultRetentionDays = 7
}

// MARK: - Enums

public enum ShipmentStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case created
    case inTransit = "in_transit"
    case signed
    case exception
    case cancelled

    public var displayLabel: String {
        switch self {
        case .created: return "已创建"
        case .inTransit: return "运输中"
        case .signed: return "已签收"
        case .exception: return "异常"
        case .cancelled: return "已取消"
        }
    }

    public var isActive: Bool {
        self == .created || self == .inTransit || self == .signed || self == .exception
    }

    /// Status machine only moves forward; signed ignores earlier transit nodes (design §5.2).
    public var rank: Int {
        switch self {
        case .created: return 0
        case .inTransit: return 1
        case .exception: return 2
        case .signed: return 3
        case .cancelled: return -1
        }
    }

    public func canAdvance(to next: ShipmentStatus) -> Bool {
        if self == next { return true }
        if self == .cancelled || next == .cancelled { return next == .cancelled && self != .signed }
        if self == .signed { return false }
        if self == .exception && next == .inTransit { return true }
        return next.rank >= self.rank
    }
}

public enum CheckoutGroupStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pendingPayment = "pending_payment"
    case paid
    case cancelled
    case partialCheckout = "partial_checkout"
    case stale

    public var displayLabel: String {
        switch self {
        case .pendingPayment: return "待付款"
        case .paid: return "已付款"
        case .cancelled: return "已取消"
        case .partialCheckout: return "部分成交"
        case .stale: return "已失效"
        }
    }
}

public enum WaybillImportJobStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case queued
    case pending
    case running
    case succeeded
    case completed
    case failed
    case partial

    public var displayLabel: String {
        switch self {
        case .queued, .pending: return "排队中"
        case .running: return "处理中"
        case .succeeded, .completed: return "全部成功"
        case .failed: return "失败"
        case .partial: return "部分成功"
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .completed, .failed, .partial: return true
        default: return false
        }
    }
}

public enum ShippingErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case evidenceRequired = "evidence_required"
    case insuranceProofRequired = "insurance_proof_required"
    case addressRequired = "address_required"
    case trackingInvalid = "tracking_invalid"
    case alreadyShipped = "already_shipped"
    case afterSaleActive = "after_sale_active"
    case shipNotOverdue = "ship_not_overdue"
    case addressMismatch = "address_mismatch"
    case cannotMergeInTransit = "cannot_merge_in_transit"
    case importInProgress = "import_in_progress"
    case checkoutStale = "checkout_stale"
    case carrierUnknown = "carrier_unknown"
    case mergeLimitExceeded = "merge_limit_exceeded"
    case buyerMismatch = "buyer_mismatch"
    case statusNotPaid = "status_not_paid"
    case insuredAmountTooLow = "insured_amount_too_low"
    case importTooLarge = "import_too_large"
    case fileTypeInvalid = "file_type_invalid"
    case featureDisabled = "feature_disabled"
    case forbidden = "forbidden"
    case missingIdempotencyKey = "missing_idempotency_key"

    public var fallbackMessage: String {
        switch self {
        case .evidenceRequired: return "发货取证未完备，请先完成拍照/验车视频"
        case .insuranceProofRequired: return "高价值订单须上传保价凭证"
        case .addressRequired: return "收货地址缺失，无法发货"
        case .trackingInvalid: return "运单号格式无效"
        case .alreadyShipped: return "订单已发货"
        case .afterSaleActive: return "售后处理中，确认收货已暂停"
        case .shipNotOverdue: return "尚未超过发货宽限期，无法无责取消"
        case .addressMismatch: return "收货地址不一致，无法合并发货"
        case .cannotMergeInTransit: return "已揽收运单不可再合并"
        case .importInProgress: return "已有运单导入任务进行中"
        case .checkoutStale: return "合并付款组已失效，请重建"
        case .carrierUnknown: return "承运商未知或未启用"
        case .mergeLimitExceeded: return "合并发货最多 \(ShipmentConfigDefaults.mergeShipMax) 单"
        case .buyerMismatch: return "买家不一致，无法合并发货"
        case .statusNotPaid: return "仅待发货订单可合并发货"
        case .insuredAmountTooLow: return "保价金额不可低于成交价"
        case .importTooLarge: return "导入上限 \(ShipmentConfigDefaults.waybillImportMaxRows) 行 / 5MB"
        case .fileTypeInvalid: return "仅支持 xlsx / csv，禁止 xls 宏文件"
        case .featureDisabled: return "功能未开放"
        case .forbidden: return "无权操作"
        case .missingIdempotencyKey: return "缺少幂等键"
        }
    }
}

// MARK: - UX copy (design §9)

public enum ShipmentCopy {
    public static let shipFormTitle = "填写发货信息"
    public static let shipFormHint = "模型请使用足量缓冲材料包装；高价值订单须保价。"
    public static let shipSubmit = "确认发货"
    public static let insuredRequiredBanner = "成交价 ≥ ¥2,000，须填写保价金额并上传保价凭证"
    public static let insuredSuggestedPrefix = "建议保价"
    public static let trackingEmpty = "暂无轨迹，已向承运商查询"
    public static let trackingUpdatedPrefix = "更新于"
    public static let trackingExceptionEmpty = "暂无轨迹（已超过 72 小时）"
    public static let confirmTitle = "确认收货"
    public static let confirmHint = "可拍摄开箱视频留证，但不强制"
    public static let confirmPausedHint = "售后结束后恢复倒计时"
    public static let confirmPausedButton = "售后处理中"
    public static let autoConfirmPrefix = "自动确认剩余"
    public static let cancelUnshippedTitle = "取消未发货订单"
    public static let cancelUnshippedConfirm = "全额退款且记卖家发货超时，确认取消？"
    public static let cancelUnshippedCTA = "超时取消"
    public static let cancelUnshippedGraceHint = "宽限期内不可取消"
    public static let mergeShipPrefix = "合并发货，共"
    public static let mergeShipSuffix = "件"
    public static let partialCancelledHint = "部分商品已取消"
    public static let sellerOnlyShip = "仅卖家能发货"
    public static let goEvidence = "去取证"
    public static let serverTimeHint = "以服务器时间为准"
    public static let checkoutGroupStubTitle = "合并付款"
    public static let checkoutGroupFeeHint = "运费取各单最高首件，续件免运费"
}

// MARK: - Domain models

public struct ShippingCarrier: Codable, Equatable, Sendable, Identifiable, Hashable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let reg: String?
    public let enabled: Bool

    public init(code: String, name: String, reg: String? = nil, enabled: Bool = true) {
        self.code = code
        self.name = name
        self.reg = reg
        self.enabled = enabled
    }

    public static let builtIn: [ShippingCarrier] = [
        ShippingCarrier(code: "SF", name: "顺丰速运", reg: #"^SF\d{10,}$"#),
        ShippingCarrier(code: "JD", name: "京东物流", reg: #"^JD[A-Z0-9]{8,}$"#),
        ShippingCarrier(code: "EMS", name: "EMS", reg: #"^[A-Z]{2}\d{9}[A-Z]{2}$"#),
        ShippingCarrier(code: "ZTO", name: "中通快递"),
        ShippingCarrier(code: "YTO", name: "圆通速递"),
        ShippingCarrier(code: "YD", name: "韵达快递"),
        ShippingCarrier(code: "STO", name: "申通快递"),
        ShippingCarrier(code: "DB", name: "德邦快递"),
        ShippingCarrier(code: "OTHER", name: "其他"),
    ]
}

public struct ShipmentOrderMember: Codable, Equatable, Sendable, Hashable {
    public let orderId: Int64
    public let orderNo: String?
    public let amount: Int64?
    public let status: String?
    public let evidenceReady: Bool?
    public let insuredRequired: Bool?
    public let cancelled: Bool?

    public init(
        orderId: Int64,
        orderNo: String? = nil,
        amount: Int64? = nil,
        status: String? = nil,
        evidenceReady: Bool? = nil,
        insuredRequired: Bool? = nil,
        cancelled: Bool? = nil
    ) {
        self.orderId = orderId
        self.orderNo = orderNo
        self.amount = amount
        self.status = status
        self.evidenceReady = evidenceReady
        self.insuredRequired = insuredRequired
        self.cancelled = cancelled
    }
}

public struct Shipment: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let shipmentNo: String
    public let sellerId: Int64
    public let buyerId: Int64
    public let addressHash: String?
    public let carrier: String
    public let trackingNo: String
    public let insured: Bool
    public let insuredAmount: Int64?
    public let signedAt: Date?
    public let status: ShipmentStatus
    public let trackSyncedAt: Date?
    public let orders: [ShipmentOrderMember]?
    public let exceptionNote: String?

    public init(
        id: Int64,
        shipmentNo: String,
        sellerId: Int64,
        buyerId: Int64,
        addressHash: String? = nil,
        carrier: String,
        trackingNo: String,
        insured: Bool = false,
        insuredAmount: Int64? = nil,
        signedAt: Date? = nil,
        status: ShipmentStatus = .created,
        trackSyncedAt: Date? = nil,
        orders: [ShipmentOrderMember]? = nil,
        exceptionNote: String? = nil
    ) {
        self.id = id
        self.shipmentNo = shipmentNo
        self.sellerId = sellerId
        self.buyerId = buyerId
        self.addressHash = addressHash
        self.carrier = carrier
        self.trackingNo = trackingNo
        self.insured = insured
        self.insuredAmount = insuredAmount
        self.signedAt = signedAt
        self.status = status
        self.trackSyncedAt = trackSyncedAt
        self.orders = orders
        self.exceptionNote = exceptionNote
    }

    public var memberCount: Int {
        max(1, orders?.count ?? 1)
    }

    public var isMerged: Bool { memberCount > 1 }

    public var cancelledOrderNos: [String] {
        (orders ?? []).compactMap { m in
            guard m.cancelled == true else { return nil }
            return m.orderNo
        }
    }
}

public struct TrackEvent: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let eventId: Int64?
    public let shipmentId: Int64?
    public let occurredAt: Date
    public let location: String?
    public let description: String
    public let raw: String?

    public var id: String {
        if let eventId { return "\(eventId)" }
        return "\(occurredAt.timeIntervalSince1970)-\(description)"
    }

    enum CodingKeys: String, CodingKey {
        case eventId = "id"
        case shipmentId, occurredAt, location, description, raw
    }

    public init(
        eventId: Int64? = nil,
        shipmentId: Int64? = nil,
        occurredAt: Date,
        location: String? = nil,
        description: String,
        raw: String? = nil
    ) {
        self.eventId = eventId
        self.shipmentId = shipmentId
        self.occurredAt = occurredAt
        self.location = location
        self.description = description
        self.raw = raw
    }
}

public struct TrackingResult: Codable, Equatable, Sendable, Hashable {
    public let shipmentId: Int64?
    public let shipmentNo: String?
    public let carrier: String?
    public let trackingNo: String?
    public let status: ShipmentStatus
    public let signedAt: Date?
    public let events: [TrackEvent]
    public let serverTime: Date?
    public let trackSyncedAt: Date?
    public let exception: Bool?
    public let memberCancelledOrderNos: [String]?
    public let memberCount: Int?

    public init(
        shipmentId: Int64? = nil,
        shipmentNo: String? = nil,
        carrier: String? = nil,
        trackingNo: String? = nil,
        status: ShipmentStatus = .created,
        signedAt: Date? = nil,
        events: [TrackEvent] = [],
        serverTime: Date? = nil,
        trackSyncedAt: Date? = nil,
        exception: Bool? = nil,
        memberCancelledOrderNos: [String]? = nil,
        memberCount: Int? = nil
    ) {
        self.shipmentId = shipmentId
        self.shipmentNo = shipmentNo
        self.carrier = carrier
        self.trackingNo = trackingNo
        self.status = status
        self.signedAt = signedAt
        self.events = events
        self.serverTime = serverTime
        self.trackSyncedAt = trackSyncedAt
        self.exception = exception
        self.memberCancelledOrderNos = memberCancelledOrderNos
        self.memberCount = memberCount
    }

    /// Newest first for timeline UI.
    public var eventsNewestFirst: [TrackEvent] {
        events.sorted { $0.occurredAt > $1.occurredAt }
    }

    public var isEmptyTrack: Bool { events.isEmpty }

    public var showsExceptionEmpty: Bool {
        (exception == true || status == .exception) && events.isEmpty
    }
}

public struct ShipOrderRequest: Codable, Equatable, Sendable {
    public var carrier: String
    public var trackingNo: String
    public var insured: Bool?
    public var insuredAmount: Int64?

    public init(carrier: String, trackingNo: String, insured: Bool? = nil, insuredAmount: Int64? = nil) {
        self.carrier = carrier
        self.trackingNo = trackingNo
        self.insured = insured
        self.insuredAmount = insuredAmount
    }
}

public struct ShipOrderResult: Codable, Equatable, Sendable {
    public let shipmentNo: String
    public let shipmentId: Int64?
    public let confirmDeadline: Date?
    public let insured: Bool
    public let insuredAmount: Int64?
    public let status: String?

    public init(
        shipmentNo: String,
        shipmentId: Int64? = nil,
        confirmDeadline: Date? = nil,
        insured: Bool = false,
        insuredAmount: Int64? = nil,
        status: String? = nil
    ) {
        self.shipmentNo = shipmentNo
        self.shipmentId = shipmentId
        self.confirmDeadline = confirmDeadline
        self.insured = insured
        self.insuredAmount = insuredAmount
        self.status = status
    }
}

public struct ConfirmOrderResult: Codable, Equatable, Sendable {
    public let status: String?
    public let completedAt: Date?
    public let profitShareId: String?
    public let profitShareStatus: String?

    public init(
        status: String? = "completed",
        completedAt: Date? = nil,
        profitShareId: String? = nil,
        profitShareStatus: String? = nil
    ) {
        self.status = status
        self.completedAt = completedAt
        self.profitShareId = profitShareId
        self.profitShareStatus = profitShareStatus
    }
}

public struct ConfirmPauseState: Equatable, Sendable {
    public var confirmDeadline: Date?
    public var confirmDeadlineVersion: Int?
    public var confirmPausedAt: Date?
    public var confirmRemainingSec: Int?
    public var afterSaleStatus: String?
    public var status: String?

    public init(
        confirmDeadline: Date? = nil,
        confirmDeadlineVersion: Int? = nil,
        confirmPausedAt: Date? = nil,
        confirmRemainingSec: Int? = nil,
        afterSaleStatus: String? = nil,
        status: String? = nil
    ) {
        self.confirmDeadline = confirmDeadline
        self.confirmDeadlineVersion = confirmDeadlineVersion
        self.confirmPausedAt = confirmPausedAt
        self.confirmRemainingSec = confirmRemainingSec
        self.afterSaleStatus = afterSaleStatus
        self.status = status
    }
}

public struct MergeShipCandidate: Equatable, Sendable {
    public let id: Int64
    public let buyerId: Int64
    public let addressHash: String
    public let status: String
    public let evidenceReady: Bool?
    public let insuredRequired: Bool?
    public let amount: Int64?
    public let shipmentStatus: ShipmentStatus?

    public init(
        id: Int64,
        buyerId: Int64,
        addressHash: String,
        status: String,
        evidenceReady: Bool? = nil,
        insuredRequired: Bool? = nil,
        amount: Int64? = nil,
        shipmentStatus: ShipmentStatus? = nil
    ) {
        self.id = id
        self.buyerId = buyerId
        self.addressHash = addressHash
        self.status = status
        self.evidenceReady = evidenceReady
        self.insuredRequired = insuredRequired
        self.amount = amount
        self.shipmentStatus = shipmentStatus
    }
}

public struct CheckoutGroupCreateRequest: Codable, Equatable, Sendable {
    public let listingIds: [Int64]
    public let addressId: Int64

    public init(listingIds: [Int64], addressId: Int64) {
        self.listingIds = listingIds
        self.addressId = addressId
    }
}

public struct CheckoutGroup: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let buyerId: Int64?
    public let sellerId: Int64?
    public let status: CheckoutGroupStatus
    public let mergedShippingFee: Int64
    public let goodsTotal: Int64?
    public let buyerTotal: Int64?
    public let parentOrderId: Int64?
    public let headOrderId: Int64?
    public let childOrderIds: [Int64]?
    public let payDeadline: Date?

    public init(
        id: Int64,
        buyerId: Int64? = nil,
        sellerId: Int64? = nil,
        status: CheckoutGroupStatus = .pendingPayment,
        mergedShippingFee: Int64 = 0,
        goodsTotal: Int64? = nil,
        buyerTotal: Int64? = nil,
        parentOrderId: Int64? = nil,
        headOrderId: Int64? = nil,
        childOrderIds: [Int64]? = nil,
        payDeadline: Date? = nil
    ) {
        self.id = id
        self.buyerId = buyerId
        self.sellerId = sellerId
        self.status = status
        self.mergedShippingFee = mergedShippingFee
        self.goodsTotal = goodsTotal
        self.buyerTotal = buyerTotal
        self.parentOrderId = parentOrderId
        self.headOrderId = headOrderId
        self.childOrderIds = childOrderIds
        self.payDeadline = payDeadline
    }
}

public struct CancelUnshippedResult: Codable, Equatable, Sendable {
    public let status: String?
    public let refunded: Bool?
    public let orderId: Int64?

    public init(status: String? = "refunded", refunded: Bool? = true, orderId: Int64? = nil) {
        self.status = status
        self.refunded = refunded
        self.orderId = orderId
    }
}

// MARK: - Logic

public enum ShipmentLogic {
    // MARK: Normalize

    /// `tracking_no`: strip spaces + uppercase (design §3).
    public static func normalizeTrackingNo(_ raw: String) -> String {
        raw
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .uppercased()
    }

    public static func parseInsuredFlag(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return s == "Y" || s == "YES" || s == "TRUE" || s == "1"
    }

    // MARK: Insured threshold (ORD-09)

    public static func isInsuredRequired(
        amountFen: Int64,
        thresholdFen: Int64 = ShipmentConfigDefaults.insuredThresholdFen
    ) -> Bool {
        amountFen >= thresholdFen
    }

    public static func suggestedInsuredAmountFen(_ dealAmountFen: Int64) -> Int64 {
        max(0, dealAmountFen)
    }

    /// Insured amount may be raised above deal price, never lowered (design §5.6).
    public static func validateInsuredAmount(
        dealAmountFen: Int64,
        insuredAmountFen: Int64?,
        insuredRequired: Bool = false,
        insured: Bool = false
    ) -> ShippingErrorCode? {
        let needs = insuredRequired || insured || isInsuredRequired(amountFen: dealAmountFen)
        guard needs else { return nil }
        guard let insuredAmountFen else { return .insuranceProofRequired }
        if insuredAmountFen < dealAmountFen { return .insuredAmountTooLow }
        return nil
    }

    // MARK: Confirm pause / resume / sign window (ORD-06 / §5.9)

    public static func confirmDeadline(fromShippedAt shippedAt: Date) -> Date {
        shippedAt.addingTimeInterval(TimeInterval(ShipmentConfigDefaults.confirmDaySec))
    }

    public struct SignedConfirmDeadlineResult: Equatable, Sendable {
        public let confirmDeadline: Date
        public let extended: Bool
    }

    /// Sign may extend to signed_at+10d, but must not shorten a window with <24h remaining.
    public static func applySignedConfirmDeadline(
        currentDeadline: Date?,
        signedAt: Date,
        now: Date = Date()
    ) -> SignedConfirmDeadlineResult {
        let signedPlus = signedAt.addingTimeInterval(TimeInterval(ShipmentConfigDefaults.confirmDaySec))
        guard let current = currentDeadline else {
            return SignedConfirmDeadlineResult(confirmDeadline: signedPlus, extended: true)
        }
        let remainingSec = max(0, Int(current.timeIntervalSince(now).rounded(.down)))
        if remainingSec < ShipmentConfigDefaults.confirmSignProtectSec {
            if signedPlus > current {
                return SignedConfirmDeadlineResult(confirmDeadline: signedPlus, extended: true)
            }
            return SignedConfirmDeadlineResult(confirmDeadline: current, extended: false)
        }
        if signedPlus > current {
            return SignedConfirmDeadlineResult(confirmDeadline: signedPlus, extended: true)
        }
        return SignedConfirmDeadlineResult(confirmDeadline: current, extended: false)
    }

    public struct PauseConfirmResult: Equatable, Sendable {
        public let confirmPausedAt: Date
        public let confirmRemainingSec: Int
    }

    public static func pauseConfirmDeadline(
        confirmDeadline: Date,
        now: Date = Date()
    ) -> PauseConfirmResult {
        let remaining = max(0, Int(confirmDeadline.timeIntervalSince(now).rounded(.down)))
        return PauseConfirmResult(confirmPausedAt: now, confirmRemainingSec: remaining)
    }

    public struct ResumeConfirmResult: Equatable, Sendable {
        public let confirmDeadline: Date
        public let appliedRemainingSec: Int
    }

    /// Floor: 1h so closing after-sale doesn't auto-confirm immediately.
    public static func resumeConfirmDeadline(
        remainingSec: Int,
        now: Date = Date(),
        minSec: Int = ShipmentConfigDefaults.confirmResumeMinSec
    ) -> ResumeConfirmResult {
        let applied = max(minSec, remainingSec)
        return ResumeConfirmResult(
            confirmDeadline: now.addingTimeInterval(TimeInterval(applied)),
            appliedRemainingSec: applied
        )
    }

    public static func canConfirmReceipt(_ state: ConfirmPauseState) -> Bool {
        if let status = state.status, status != "shipped" { return false }
        if state.afterSaleStatus == "processing" { return false }
        return true
    }

    public static func confirmReceiptError(_ state: ConfirmPauseState) -> ShippingErrorCode? {
        if let status = state.status, status != "shipped" { return .forbidden }
        if state.afterSaleStatus == "processing" { return .afterSaleActive }
        return nil
    }

    public static func isConfirmPaused(_ state: ConfirmPauseState) -> Bool {
        state.afterSaleStatus == "processing" && state.confirmPausedAt != nil
    }

    /// Effective confirm remain: when paused, freeze on `confirmRemainingSec`; else decay from deadline.
    public static func confirmRemainSeconds(
        state: ConfirmPauseState,
        serverTime: Date?,
        fetchedAtLocal: Date,
        nowLocal: Date = Date()
    ) -> Int {
        if isConfirmPaused(state) {
            return max(0, state.confirmRemainingSec ?? 0)
        }
        if let deadline = state.confirmDeadline, let serverTime {
            let elapsed = max(0, nowLocal.timeIntervalSince(fetchedAtLocal))
            let serverNow = serverTime.addingTimeInterval(elapsed)
            return max(0, Int(deadline.timeIntervalSince(serverNow).rounded(.down)))
        }
        if let remain = state.confirmRemainingSec {
            let elapsed = max(0, Int(nowLocal.timeIntervalSince(fetchedAtLocal).rounded(.down)))
            return max(0, remain - elapsed)
        }
        return 0
    }

    // MARK: Merge ship (ORD-07)

    public static func validateMergeShipCandidates(
        _ candidates: [MergeShipCandidate],
        max: Int = ShipmentConfigDefaults.mergeShipMax
    ) -> ShippingErrorCode? {
        guard !candidates.isEmpty else { return .forbidden }
        if candidates.count > max { return .mergeLimitExceeded }
        let buyer = candidates[0].buyerId
        let addr = candidates[0].addressHash
        guard !addr.isEmpty else { return .addressRequired }
        for c in candidates {
            if c.buyerId != buyer { return .buyerMismatch }
            if c.addressHash != addr { return .addressMismatch }
            if c.status != "paid" { return .statusNotPaid }
            if c.evidenceReady == false { return .evidenceRequired }
            if c.shipmentStatus == .inTransit || c.shipmentStatus == .signed {
                return .cannotMergeInTransit
            }
        }
        return nil
    }

    public static func mergeShipDisplayLabel(orderCount: Int) -> String {
        "\(ShipmentCopy.mergeShipPrefix) \(max(1, orderCount)) \(ShipmentCopy.mergeShipSuffix)"
    }

    // MARK: Single ship (ORD-04)

    public static func validateShipOrderRequest(
        _ body: ShipOrderRequest?,
        status: String? = nil,
        evidenceReady: Bool? = nil,
        hasAddress: Bool? = nil,
        amountFen: Int64 = 0,
        insuredRequired: Bool = false,
        hasInsuranceProof: Bool? = nil,
        carrierEnabled: Bool? = nil,
        trackingMatchesReg: Bool? = nil,
        alreadyShippedTracking: String? = nil,
        hasIdempotencyKey: Bool? = nil
    ) -> ShippingErrorCode? {
        if hasIdempotencyKey == false { return .missingIdempotencyKey }
        guard let body else { return .forbidden }
        if let status, status != "paid" {
            if status == "shipped" {
                let same = alreadyShippedTracking.map {
                    normalizeTrackingNo($0) == normalizeTrackingNo(body.trackingNo)
                } ?? false
                return same ? nil : .alreadyShipped
            }
            return .forbidden
        }
        if hasAddress == false { return .addressRequired }
        if evidenceReady == false { return .evidenceRequired }

        let needInsured = insuredRequired || isInsuredRequired(amountFen: amountFen)
        if needInsured && hasInsuranceProof == false { return .insuranceProofRequired }
        if needInsured || body.insured == true {
            if let err = validateInsuredAmount(
                dealAmountFen: amountFen,
                insuredAmountFen: body.insuredAmount,
                insuredRequired: needInsured,
                insured: body.insured == true
            ) {
                return err
            }
        }

        let carrier = body.carrier.trimmingCharacters(in: .whitespacesAndNewlines)
        if carrier.isEmpty { return .carrierUnknown }
        if carrierEnabled == false { return .carrierUnknown }

        let tracking = normalizeTrackingNo(body.trackingNo)
        if tracking.isEmpty { return .trackingInvalid }
        if trackingMatchesReg == false { return .trackingInvalid }
        return nil
    }

    // MARK: Ship deadline / overdue cancel (ORD-04)

    public static func isWithinShipGrace(
        shipDeadline: Date,
        now: Date = Date(),
        graceHours: Int = ShipmentConfigDefaults.shipGraceHours
    ) -> Bool {
        let graceEnd = shipDeadline.addingTimeInterval(TimeInterval(graceHours * 3_600))
        return now > shipDeadline && now < graceEnd
    }

    public static func canCancelUnshipped(
        status: String,
        shipDeadline: Date,
        now: Date = Date(),
        graceHours: Int = ShipmentConfigDefaults.shipGraceHours
    ) -> Bool {
        guard status == "paid" else { return false }
        let graceEnd = shipDeadline.addingTimeInterval(TimeInterval(graceHours * 3_600))
        return now >= graceEnd
    }

    public static func cancelUnshippedError(
        status: String,
        shipDeadline: Date,
        now: Date = Date(),
        graceHours: Int = ShipmentConfigDefaults.shipGraceHours
    ) -> ShippingErrorCode? {
        guard status == "paid" else { return .forbidden }
        if !canCancelUnshipped(status: status, shipDeadline: shipDeadline, now: now, graceHours: graceHours) {
            return .shipNotOverdue
        }
        return nil
    }

    // MARK: Checkout merge pay (ORD-10)

    /// `merged_shipping_fee = max(各单 shipping_fee)`；续件 0 (design §5.7 / §5.14).
    public static func computeMergedShippingFeeFen(_ fees: [Int64]) -> Int64 {
        fees.max() ?? 0
    }

    public static func computeCheckoutGroupBuyerTotal(
        goodsTotals: [Int64],
        shippingFees: [Int64]
    ) -> (goodsTotal: Int64, mergedShippingFee: Int64, buyerTotal: Int64) {
        let goods = goodsTotals.reduce(0, +)
        let ship = computeMergedShippingFeeFen(shippingFees)
        return (goods, ship, goods + ship)
    }

    public static func validateCheckoutGroupCreate(
        listingIds: [Int64],
        addressId: Int64?,
        mergePayEnabled: Bool? = nil,
        tradeTypes: [String]? = nil,
        hasIdempotencyKey: Bool? = nil
    ) -> ShippingErrorCode? {
        if mergePayEnabled == false { return .featureDisabled }
        if hasIdempotencyKey == false { return .missingIdempotencyKey }
        if listingIds.count < 2 { return .forbidden }
        if addressId == nil || addressId == 0 { return .addressRequired }
        if let tradeTypes {
            for t in tradeTypes where t != "fixed" {
                return .forbidden
            }
        }
        return nil
    }

    // MARK: Tracking display

    public static func sortTrackEvents(_ events: [TrackEvent]) -> [TrackEvent] {
        events.sorted { $0.occurredAt > $1.occurredAt }
    }

    public static func advanceShipmentStatus(from: ShipmentStatus, reported: ShipmentStatus) -> ShipmentStatus {
        from.canAdvance(to: reported) ? reported : from
    }
}
