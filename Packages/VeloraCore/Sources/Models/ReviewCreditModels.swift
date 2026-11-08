import Foundation

// MARK: - Reviews & credit (DES-v1.3-12-02 CRD-01/02/03 / D40)

/// Product defaults (design §15). Hot-config on server; client mirrors for UX + gates.
public enum ReviewCreditConfigDefaults {
    public static let creditInitial = 100
    public static let creditCap = 120
    public static let creditFloor = 0
    public static let monthPlusCap = 10
    public static let threshold80 = 80
    public static let threshold60 = 60
    public static let threshold40 = 40
    public static let reviewWindowDays = 15
    public static let reviewMaxImages = 9
    public static let reviewContentMax = 500
    public static let sellerPerfWindowDays = 90
    public static let creditLogsDays = 90
    public static let reviewsPageSize = 20
    public static let idempotencyHeader = "Idempotency-Key"
    public static let arbitrationTagLabel = "经平台仲裁"
    public static let metricEmpty = "—"
}

// MARK: - Rating / role / source / status

public enum ReviewRating: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case good
    case neutral
    case bad

    public var id: String { rawValue }

    public static func normalize(_ raw: String?) -> ReviewRating? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ReviewRating(rawValue: s) { return exact }
        switch s {
        case "positive", "好评", "praise": return .good
        case "mid", "中评", "average": return .neutral
        case "negative", "差评", "poor": return .bad
        default: return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .good: return ReviewCreditCopy.ratingGood
        case .neutral: return ReviewCreditCopy.ratingNeutral
        case .bad: return ReviewCreditCopy.ratingBad
        }
    }

    public var systemImage: String {
        switch self {
        case .good: return "hand.thumbsup.fill"
        case .neutral: return "hand.raised.fill"
        case .bad: return "hand.thumbsdown.fill"
        }
    }

    public var requiresSecondaryConfirm: Bool { self == .bad }
}

public enum ReviewRole: String, Codable, Sendable, CaseIterable, Equatable {
    case buyerToSeller = "buyer_to_seller"
    case sellerToBuyer = "seller_to_buyer"

    public static func normalize(_ raw: String?) -> ReviewRole? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ReviewRole(rawValue: s) { return exact }
        switch s {
        case "buyer", "as_buyer", "buyer_review": return .buyerToSeller
        case "seller", "as_seller", "seller_review": return .sellerToBuyer
        default: return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .buyerToSeller: return ReviewCreditCopy.roleBuyerToSeller
        case .sellerToBuyer: return ReviewCreditCopy.roleSellerToBuyer
        }
    }
}

public enum ReviewSource: String, Codable, Sendable, CaseIterable, Equatable {
    case user
    case autoGood = "auto_good"

    public static func normalize(_ raw: String?) -> ReviewSource? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ReviewSource(rawValue: s) { return exact }
        switch s {
        case "manual", "member": return .user
        case "auto", "system_good", "default_good": return .autoGood
        default: return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .user: return ReviewCreditCopy.sourceUser
        case .autoGood: return ReviewCreditCopy.sourceAutoGood
        }
    }
}

public enum ReviewStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case pending
    case published
    case hidden

    public static func normalize(_ raw: String?) -> ReviewStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ReviewStatus(rawValue: s) { return exact }
        switch s {
        case "open", "awaiting": return .pending
        case "public", "done", "completed": return .published
        case "removed", "violated", "moderated": return .hidden
        default: return nil
        }
    }

    public var isPending: Bool { self == .pending }
    public var isVisiblePublicly: Bool { self == .published }
}

// MARK: - Credit reason codes (8.5)

public enum CreditReasonCode: String, Codable, Sendable, CaseIterable, Equatable {
    case completePay = "complete_pay"
    case completeShip = "complete_ship"
    case reviewGood = "review_good"
    case offerUnpaid = "offer_unpaid"
    case shipLate = "ship_late"
    case lotteryUnpaid = "lottery_unpaid"
    case imPenalty = "im_penalty"
    case auctionDefault = "auction_default"
    case offPlatform = "off_platform"
    case rulingDefect = "ruling_defect"
    case rulingDamage = "ruling_damage"
    case manual
    case capped
    case skippedRelated = "skipped_related"

    public static func normalize(_ raw: String?) -> CreditReasonCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = CreditReasonCode(rawValue: s) { return exact }
        switch s {
        case "auction_non_payment", "auction_default_unpaid": return .auctionDefault
        case "offer_unpaid_close", "dir_offer_unpaid": return .offerUnpaid
        case "lottery_forfeit", "lottery_unpaid_close": return .lotteryUnpaid
        case "im_sensitive_mute", "im_penalty_mute": return .imPenalty
        case "induce_offline", "off_platform_induce": return .offPlatform
        case "hidden_flaw", "ruling_hidden_flaw": return .rulingDefect
        case "intentional_damage", "ruling_intentional_damage": return .rulingDamage
        case "month_capped", "plus_capped": return .capped
        case "related_skip", "self_trade_skip": return .skippedRelated
        default: return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .completePay: return ReviewCreditCopy.reasonCompletePay
        case .completeShip: return ReviewCreditCopy.reasonCompleteShip
        case .reviewGood: return ReviewCreditCopy.reasonReviewGood
        case .offerUnpaid: return ReviewCreditCopy.reasonOfferUnpaid
        case .shipLate: return ReviewCreditCopy.reasonShipLate
        case .lotteryUnpaid: return ReviewCreditCopy.reasonLotteryUnpaid
        case .imPenalty: return ReviewCreditCopy.reasonImPenalty
        case .auctionDefault: return ReviewCreditCopy.reasonAuctionDefault
        case .offPlatform: return ReviewCreditCopy.reasonOffPlatform
        case .rulingDefect: return ReviewCreditCopy.reasonRulingDefect
        case .rulingDamage: return ReviewCreditCopy.reasonRulingDamage
        case .manual: return ReviewCreditCopy.reasonManual
        case .capped: return ReviewCreditCopy.reasonCapped
        case .skippedRelated: return ReviewCreditCopy.reasonSkippedRelated
        }
    }

    /// Positive events that share the natural-month +10 cap (design §5.2 / §5.6).
    public var countsTowardMonthPlusCap: Bool {
        switch self {
        case .completePay, .completeShip, .reviewGood, .manual:
            return true
        default:
            return false
        }
    }
}

// MARK: - Error codes (design §15)

public enum ReviewCreditErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case orderNotCompleted = "order_not_completed"
    case reviewWindowClosed = "review_window_closed"
    case reviewAlreadyClosed = "review_already_closed"
    case reviewForbidden = "review_forbidden"
    case contentRejected = "content_rejected"
    case creditBelow80 = "credit_below_80"
    case creditBelow60 = "credit_below_60"
    case creditBelow40 = "credit_below_40"
    case approvalRequired = "approval_required"
    case skippedRelated = "skipped_related"
    case missingIdempotencyKey = "missing_idempotency_key"
    case unauthorized
    case realNameRequired = "real_name_required"

    public static func normalize(_ raw: String?) -> ReviewCreditErrorCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ReviewCreditErrorCode(rawValue: s) { return exact }
        switch s {
        case "credit_too_low":
            // Legacy umbrella — client must not invent threshold; treat as 80 gate.
            return .creditBelow80
        case "order_not_completable", "not_completed":
            return .orderNotCompleted
        case "window_closed", "review_expired":
            return .reviewWindowClosed
        case "already_reviewed", "review_closed":
            return .reviewAlreadyClosed
        case "forbidden", "not_party":
            return .reviewForbidden
        case "content_blocked", "abuse_content":
            return .contentRejected
        case "401", "unauthenticated":
            return .unauthorized
        case "need_real_name", "kyc_required":
            return .realNameRequired
        default:
            return nil
        }
    }

    public var isCreditBlock: Bool {
        switch self {
        case .creditBelow80, .creditBelow60, .creditBelow40: return true
        default: return false
        }
    }

    public var blockThreshold: Int? {
        switch self {
        case .creditBelow80: return ReviewCreditConfigDefaults.threshold80
        case .creditBelow60: return ReviewCreditConfigDefaults.threshold60
        case .creditBelow40: return ReviewCreditConfigDefaults.threshold40
        default: return nil
        }
    }

    public var fallbackMessage: String {
        switch self {
        case .orderNotCompleted: return ReviewCreditCopy.errOrderNotCompleted
        case .reviewWindowClosed: return ReviewCreditCopy.errWindowClosed
        case .reviewAlreadyClosed: return ReviewCreditCopy.errAlreadyClosed
        case .reviewForbidden: return ReviewCreditCopy.errForbidden
        case .contentRejected: return ReviewCreditCopy.errContentRejected
        case .creditBelow80, .creditBelow60, .creditBelow40:
            return ReviewCreditCopy.errCreditGeneric
        case .approvalRequired: return ReviewCreditCopy.errApprovalRequired
        case .skippedRelated: return ReviewCreditCopy.errSkippedRelated
        case .missingIdempotencyKey: return ReviewCreditCopy.errRetry
        case .unauthorized: return ReviewCreditCopy.errLogin
        case .realNameRequired: return ReviewCreditCopy.errRealName
        }
    }
}

// MARK: - Review DTO

public struct OrderReview: Decodable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let orderId: Int64
    public let fromUserId: Int64?
    public let toUserId: Int64?
    public let role: String
    public let rating: String?
    public let content: String?
    public let imageUrls: [String]
    public let source: String?
    public let arbitrationTag: Bool
    public let status: String
    public let version: Int?
    public let createdAt: Date?
    public let publishedAt: Date?
    public let fromNicknameMasked: String?
    public let hiddenReason: String?
    public let serverTime: Date?

    public init(
        id: Int64,
        orderId: Int64,
        fromUserId: Int64? = nil,
        toUserId: Int64? = nil,
        role: String,
        rating: String? = nil,
        content: String? = nil,
        imageUrls: [String] = [],
        source: String? = nil,
        arbitrationTag: Bool = false,
        status: String = ReviewStatus.pending.rawValue,
        version: Int? = nil,
        createdAt: Date? = nil,
        publishedAt: Date? = nil,
        fromNicknameMasked: String? = nil,
        hiddenReason: String? = nil,
        serverTime: Date? = nil
    ) {
        self.id = id
        self.orderId = orderId
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.role = role
        self.rating = rating
        self.content = content
        self.imageUrls = imageUrls
        self.source = source
        self.arbitrationTag = arbitrationTag
        self.status = status
        self.version = version
        self.createdAt = createdAt
        self.publishedAt = publishedAt
        self.fromNicknameMasked = fromNicknameMasked
        self.hiddenReason = hiddenReason
        self.serverTime = serverTime
    }

    enum CodingKeys: String, CodingKey {
        case id, orderId, fromUserId, toUserId, role, rating, content
        case imageUrls, source, arbitrationTag, status, version
        case createdAt, publishedAt, fromNicknameMasked, hiddenReason, serverTime
        case images, nickMasked, nicknameMasked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        orderId = try c.decodeIfPresent(Int64.self, forKey: .orderId) ?? 0
        fromUserId = try c.decodeIfPresent(Int64.self, forKey: .fromUserId)
        toUserId = try c.decodeIfPresent(Int64.self, forKey: .toUserId)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ReviewRole.buyerToSeller.rawValue
        rating = try c.decodeIfPresent(String.self, forKey: .rating)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        if let urls = try c.decodeIfPresent([String].self, forKey: .imageUrls) {
            imageUrls = urls
        } else if let urls = try c.decodeIfPresent([String].self, forKey: .images) {
            imageUrls = urls
        } else {
            imageUrls = []
        }
        source = try c.decodeIfPresent(String.self, forKey: .source)
        arbitrationTag = try c.decodeIfPresent(Bool.self, forKey: .arbitrationTag) ?? false
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ReviewStatus.pending.rawValue
        version = try c.decodeIfPresent(Int.self, forKey: .version)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        publishedAt = try c.decodeIfPresent(Date.self, forKey: .publishedAt)
        fromNicknameMasked = try c.decodeIfPresent(String.self, forKey: .fromNicknameMasked)
            ?? c.decodeIfPresent(String.self, forKey: .nickMasked)
            ?? c.decodeIfPresent(String.self, forKey: .nicknameMasked)
        hiddenReason = try c.decodeIfPresent(String.self, forKey: .hiddenReason)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
    }

    public var resolvedRole: ReviewRole { ReviewRole.normalize(role) ?? .buyerToSeller }
    public var resolvedRating: ReviewRating? { ReviewRating.normalize(rating) }
    public var resolvedSource: ReviewSource? { ReviewSource.normalize(source) }
    public var resolvedStatus: ReviewStatus { ReviewStatus.normalize(status) ?? .pending }

    public var isPending: Bool { resolvedStatus.isPending }
    public var isHidden: Bool { resolvedStatus == .hidden }
    public var showsArbitrationTag: Bool { arbitrationTag }

    /// Arbitration tag is display-only — never dismissible (client duty).
    public var arbitrationTagDismissible: Bool { false }

    public var displayContent: String {
        if isHidden { return ReviewCreditCopy.hiddenByModeration }
        if let content, !content.isEmpty { return content }
        if resolvedSource == .autoGood { return ReviewCreditCopy.autoGoodContent }
        return ""
    }

    public var displayAuthor: String {
        if let fromNicknameMasked, !fromNicknameMasked.isEmpty { return fromNicknameMasked }
        return ReviewCreditCopy.anonymousReviewer
    }
}

public struct OrderReviewsResponse: Decodable, Equatable, Sendable {
    public let orderId: Int64
    public let buyerToSeller: OrderReview?
    public let sellerToBuyer: OrderReview?
    public let items: [OrderReview]
    public let reviewDeadline: Date?
    public let myPending: Bool?
    public let serverTime: Date?

    public init(
        orderId: Int64 = 0,
        buyerToSeller: OrderReview? = nil,
        sellerToBuyer: OrderReview? = nil,
        items: [OrderReview] = [],
        reviewDeadline: Date? = nil,
        myPending: Bool? = nil,
        serverTime: Date? = nil
    ) {
        self.orderId = orderId
        self.buyerToSeller = buyerToSeller
        self.sellerToBuyer = sellerToBuyer
        self.items = items
        self.reviewDeadline = reviewDeadline
        self.myPending = myPending
        self.serverTime = serverTime
    }

    enum CodingKeys: String, CodingKey {
        case orderId, buyerToSeller, sellerToBuyer, items, reviews
        case reviewDeadline, myPending, serverTime, list
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orderId = try c.decodeIfPresent(Int64.self, forKey: .orderId) ?? 0
        buyerToSeller = try c.decodeIfPresent(OrderReview.self, forKey: .buyerToSeller)
        sellerToBuyer = try c.decodeIfPresent(OrderReview.self, forKey: .sellerToBuyer)
        if let items = try c.decodeIfPresent([OrderReview].self, forKey: .items) {
            self.items = items
        } else if let items = try c.decodeIfPresent([OrderReview].self, forKey: .reviews) {
            self.items = items
        } else if let items = try c.decodeIfPresent([OrderReview].self, forKey: .list) {
            self.items = items
        } else {
            var merged: [OrderReview] = []
            if let buyerToSeller { merged.append(buyerToSeller) }
            if let sellerToBuyer { merged.append(sellerToBuyer) }
            self.items = merged
        }
        reviewDeadline = try c.decodeIfPresent(Date.self, forKey: .reviewDeadline)
        myPending = try c.decodeIfPresent(Bool.self, forKey: .myPending)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
    }

    public var publishedItems: [OrderReview] {
        items.filter { $0.resolvedStatus.isVisiblePublicly || $0.isHidden }
    }

    public var pendingForMe: Bool {
        if let myPending { return myPending }
        return items.contains { $0.isPending }
    }
}

public struct SubmitOrderReviewRequest: Equatable, Sendable {
    public let rating: ReviewRating
    public let content: String?
    public let imageIds: [String]

    public init(rating: ReviewRating, content: String? = nil, imageIds: [String] = []) {
        self.rating = rating
        self.content = content
        self.imageIds = imageIds
    }

    public var body: [String: Any?] {
        var dict: [String: Any?] = ["rating": rating.rawValue]
        if let content, !content.isEmpty { dict["content"] = content }
        if !imageIds.isEmpty { dict["image_ids"] = imageIds }
        return dict
    }
}

public struct UserReviewsListResponse: Decodable, Equatable, Sendable {
    public let items: [OrderReview]
    public let nextCursor: String?
    public let total: Int?
    public let serverTime: Date?

    public init(
        items: [OrderReview] = [],
        nextCursor: String? = nil,
        total: Int? = nil,
        serverTime: Date? = nil
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.total = total
        self.serverTime = serverTime
    }

    enum CodingKeys: String, CodingKey {
        case items, nextCursor, total, serverTime, list, reviews, data
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let items = try c.decodeIfPresent([OrderReview].self, forKey: .items) {
            self.items = items
        } else if let items = try c.decodeIfPresent([OrderReview].self, forKey: .list) {
            self.items = items
        } else if let items = try c.decodeIfPresent([OrderReview].self, forKey: .reviews) {
            self.items = items
        } else if let items = try c.decodeIfPresent([OrderReview].self, forKey: .data) {
            self.items = items
        } else {
            self.items = []
        }
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
    }
}

// MARK: - Me credit

public struct CreditThresholds: Codable, Equatable, Sendable {
    public let th80: Int
    public let th60: Int
    public let th40: Int

    public init(
        th80: Int = ReviewCreditConfigDefaults.threshold80,
        th60: Int = ReviewCreditConfigDefaults.threshold60,
        th40: Int = ReviewCreditConfigDefaults.threshold40
    ) {
        self.th80 = th80
        self.th60 = th60
        self.th40 = th40
    }

    enum CodingKeys: String, CodingKey {
        case th80, th60, th40
        case threshold80, threshold60, threshold40
        case eighty = "80"
        case sixty = "60"
        case forty = "40"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        th80 = try c.decodeIfPresent(Int.self, forKey: .th80)
            ?? c.decodeIfPresent(Int.self, forKey: .threshold80)
            ?? c.decodeIfPresent(Int.self, forKey: .eighty)
            ?? ReviewCreditConfigDefaults.threshold80
        th60 = try c.decodeIfPresent(Int.self, forKey: .th60)
            ?? c.decodeIfPresent(Int.self, forKey: .threshold60)
            ?? c.decodeIfPresent(Int.self, forKey: .sixty)
            ?? ReviewCreditConfigDefaults.threshold60
        th40 = try c.decodeIfPresent(Int.self, forKey: .th40)
            ?? c.decodeIfPresent(Int.self, forKey: .threshold40)
            ?? c.decodeIfPresent(Int.self, forKey: .forty)
            ?? ReviewCreditConfigDefaults.threshold40
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(th80, forKey: .th80)
        try c.encode(th60, forKey: .th60)
        try c.encode(th40, forKey: .th40)
    }
}

public struct CreditLogItem: Decodable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let delta: Int
    public let scoreAfter: Int?
    public let reasonCode: String
    public let refType: String?
    public let refId: String?
    public let monthKey: String?
    public let capped: Bool?
    public let at: Date?
    public let createdAt: Date?

    public init(
        id: Int64,
        delta: Int,
        scoreAfter: Int? = nil,
        reasonCode: String,
        refType: String? = nil,
        refId: String? = nil,
        monthKey: String? = nil,
        capped: Bool? = nil,
        at: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.delta = delta
        self.scoreAfter = scoreAfter
        self.reasonCode = reasonCode
        self.refType = refType
        self.refId = refId
        self.monthKey = monthKey
        self.capped = capped
        self.at = at
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, delta, scoreAfter, reasonCode, refType, refId, monthKey, capped, at, createdAt
        case reason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        delta = try c.decodeIfPresent(Int.self, forKey: .delta) ?? 0
        scoreAfter = try c.decodeIfPresent(Int.self, forKey: .scoreAfter)
        reasonCode = try c.decodeIfPresent(String.self, forKey: .reasonCode)
            ?? c.decodeIfPresent(String.self, forKey: .reason)
            ?? ""
        refType = try c.decodeIfPresent(String.self, forKey: .refType)
        refId = try c.decodeIfPresent(String.self, forKey: .refId)
        monthKey = try c.decodeIfPresent(String.self, forKey: .monthKey)
        capped = try c.decodeIfPresent(Bool.self, forKey: .capped)
        at = try c.decodeIfPresent(Date.self, forKey: .at)
            ?? c.decodeIfPresent(Date.self, forKey: .createdAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? at
    }

    public var resolvedReason: CreditReasonCode? { CreditReasonCode.normalize(reasonCode) }

    public var eventAt: Date? { at ?? createdAt }

    public var isMonthCapped: Bool {
        if capped == true { return true }
        return resolvedReason == .capped || (delta == 0 && resolvedReason?.countsTowardMonthPlusCap == true)
    }

    public var deltaDisplay: String {
        if delta > 0 { return "+\(delta)" }
        return "\(delta)"
    }

    public var displayTitle: String {
        if isMonthCapped { return ReviewCreditCopy.monthCapReached }
        return resolvedReason?.displayLabel ?? reasonCode
    }
}

public struct MeCreditResponse: Decodable, Equatable, Sendable {
    public let score: Int
    public let monthPlusUsed: Int
    public let monthPlusCap: Int
    public let thresholds: CreditThresholds
    public let logs: [CreditLogItem]
    public let serverTime: Date?

    public init(
        score: Int = ReviewCreditConfigDefaults.creditInitial,
        monthPlusUsed: Int = 0,
        monthPlusCap: Int = ReviewCreditConfigDefaults.monthPlusCap,
        thresholds: CreditThresholds = CreditThresholds(),
        logs: [CreditLogItem] = [],
        serverTime: Date? = nil
    ) {
        self.score = score
        self.monthPlusUsed = monthPlusUsed
        self.monthPlusCap = monthPlusCap
        self.thresholds = thresholds
        self.logs = logs
        self.serverTime = serverTime
    }

    enum CodingKeys: String, CodingKey {
        case score, monthPlusUsed, monthPlusCap, thresholds, logs, serverTime
        case monthPlus, creditScore, creditLogs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = try c.decodeIfPresent(Int.self, forKey: .score)
            ?? c.decodeIfPresent(Int.self, forKey: .creditScore)
            ?? ReviewCreditConfigDefaults.creditInitial
        if let used = try c.decodeIfPresent(Int.self, forKey: .monthPlusUsed) {
            monthPlusUsed = used
        } else if let nested = try c.decodeIfPresent(Int.self, forKey: .monthPlus) {
            monthPlusUsed = nested
        } else {
            monthPlusUsed = 0
        }
        monthPlusCap = try c.decodeIfPresent(Int.self, forKey: .monthPlusCap)
            ?? ReviewCreditConfigDefaults.monthPlusCap
        thresholds = try c.decodeIfPresent(CreditThresholds.self, forKey: .thresholds) ?? CreditThresholds()
        logs = try c.decodeIfPresent([CreditLogItem].self, forKey: .logs)
            ?? c.decodeIfPresent([CreditLogItem].self, forKey: .creditLogs)
            ?? []
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
    }

    public var monthPlusRemaining: Int { max(0, monthPlusCap - monthPlusUsed) }
    public var isMonthPlusExhausted: Bool { monthPlusUsed >= monthPlusCap }

    public var activeTier: ReviewCreditErrorCode? {
        ReviewCreditLogic.blockCode(forScore: score, thresholds: thresholds)
    }
}

// MARK: - Seller card (CRD-03)

public struct SellerCardMetrics: Decodable, Equatable, Sendable {
    public let userId: Int64?
    public let score: Int?
    public let goodRate: Double?
    public let goodRateBps: Int?
    public let soldCount: Int?
    public let avgShipHours: Double?
    public let afterSaleRate: Double?
    public let afterSaleRateBps: Int?
    public let stale: Bool
    public let computedAt: Date?
    public let periodMonth: String?
    public let serverTime: Date?

    public init(
        userId: Int64? = nil,
        score: Int? = nil,
        goodRate: Double? = nil,
        goodRateBps: Int? = nil,
        soldCount: Int? = nil,
        avgShipHours: Double? = nil,
        afterSaleRate: Double? = nil,
        afterSaleRateBps: Int? = nil,
        stale: Bool = false,
        computedAt: Date? = nil,
        periodMonth: String? = nil,
        serverTime: Date? = nil
    ) {
        self.userId = userId
        self.score = score
        self.goodRate = goodRate
        self.goodRateBps = goodRateBps
        self.soldCount = soldCount
        self.avgShipHours = avgShipHours
        self.afterSaleRate = afterSaleRate
        self.afterSaleRateBps = afterSaleRateBps
        self.stale = stale
        self.computedAt = computedAt
        self.periodMonth = periodMonth
        self.serverTime = serverTime
    }

    enum CodingKeys: String, CodingKey {
        case userId, score, goodRate, goodRateBps, soldCount, avgShipHours
        case afterSaleRate, afterSaleRateBps, stale, computedAt, periodMonth, serverTime
        case creditScore, sellerId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(Int64.self, forKey: .userId)
            ?? c.decodeIfPresent(Int64.self, forKey: .sellerId)
        score = try c.decodeIfPresent(Int.self, forKey: .score)
            ?? c.decodeIfPresent(Int.self, forKey: .creditScore)
        goodRate = try c.decodeIfPresent(Double.self, forKey: .goodRate)
        goodRateBps = try c.decodeIfPresent(Int.self, forKey: .goodRateBps)
        soldCount = try c.decodeIfPresent(Int.self, forKey: .soldCount)
        avgShipHours = try c.decodeIfPresent(Double.self, forKey: .avgShipHours)
        afterSaleRate = try c.decodeIfPresent(Double.self, forKey: .afterSaleRate)
        afterSaleRateBps = try c.decodeIfPresent(Int.self, forKey: .afterSaleRateBps)
        stale = try c.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        computedAt = try c.decodeIfPresent(Date.self, forKey: .computedAt)
        periodMonth = try c.decodeIfPresent(String.self, forKey: .periodMonth)
        serverTime = try c.decodeIfPresent(Date.self, forKey: .serverTime)
    }

    public var hasSales: Bool {
        if let soldCount { return soldCount > 0 }
        return false
    }

    public var resolvedGoodRatePercent: Double? {
        if let goodRate {
            return goodRate <= 1.0 ? goodRate * 100 : goodRate
        }
        if let goodRateBps { return Double(goodRateBps) / 100.0 }
        return nil
    }

    public var resolvedAfterSaleRatePercent: Double? {
        if let afterSaleRate {
            return afterSaleRate <= 1.0 ? afterSaleRate * 100 : afterSaleRate
        }
        if let afterSaleRateBps { return Double(afterSaleRateBps) / 100.0 }
        return nil
    }

    public var goodRateDisplay: String {
        guard hasSales, let pct = resolvedGoodRatePercent else {
            return ReviewCreditConfigDefaults.metricEmpty
        }
        return String(format: "%.0f%%", pct)
    }

    public var soldCountDisplay: String {
        guard let soldCount, soldCount > 0 else { return ReviewCreditConfigDefaults.metricEmpty }
        return "\(soldCount)"
    }

    public var avgShipHoursDisplay: String {
        guard hasSales, let hours = avgShipHours else {
            return ReviewCreditConfigDefaults.metricEmpty
        }
        if hours < 10 { return String(format: "%.1f 小时", hours) }
        return String(format: "%.0f 小时", hours)
    }

    public var afterSaleRateDisplay: String {
        guard hasSales, let pct = resolvedAfterSaleRatePercent else {
            return ReviewCreditConfigDefaults.metricEmpty
        }
        return String(format: "%.0f%%", pct)
    }

    public var scoreDisplay: String {
        if let score { return "\(score)" }
        return ReviewCreditConfigDefaults.metricEmpty
    }
}

// MARK: - Order list pending-review projection

/// Optional fields that may ride on order list/detail for pending-review UX (design §9).
public struct OrderReviewPendingInfo: Equatable, Sendable {
    public let reviewDeadline: Date?
    public let myReviewStatus: String?
    public let reviewRemainDays: Int?
    public let completedAt: Date?

    public init(
        reviewDeadline: Date? = nil,
        myReviewStatus: String? = nil,
        reviewRemainDays: Int? = nil,
        completedAt: Date? = nil
    ) {
        self.reviewDeadline = reviewDeadline
        self.myReviewStatus = myReviewStatus
        self.reviewRemainDays = reviewRemainDays
        self.completedAt = completedAt
    }

    public var isMyPending: Bool {
        if let s = ReviewStatus.normalize(myReviewStatus) { return s.isPending }
        if myReviewStatus == nil, reviewDeadline != nil { return true }
        return false
    }
}

// MARK: - Credit block interstitial payload

public struct CreditBlockInfo: Equatable, Sendable, Identifiable {
    public let code: ReviewCreditErrorCode
    public let score: Int?
    public let threshold: Int
    public let actionLabel: String

    public var id: String { "\(code.rawValue)-\(threshold)-\(score ?? -1)" }

    public init(
        code: ReviewCreditErrorCode,
        score: Int? = nil,
        threshold: Int? = nil,
        actionLabel: String = ReviewCreditCopy.defaultBlockedAction
    ) {
        self.code = code
        self.score = score
        self.threshold = threshold ?? code.blockThreshold ?? ReviewCreditConfigDefaults.threshold80
        self.actionLabel = actionLabel
    }

    public var title: String { ReviewCreditCopy.blockTitle }

    public var message: String {
        ReviewCreditLogic.blockMessage(score: score, threshold: threshold, action: actionLabel)
    }
}

// MARK: - Copy (design §5.8 / §9)

public enum ReviewCreditCopy {
    public static let ratingGood = "好评"
    public static let ratingNeutral = "中评"
    public static let ratingBad = "差评"
    public static let roleBuyerToSeller = "买家评价卖家"
    public static let roleSellerToBuyer = "卖家评价买家"
    public static let sourceUser = "用户评价"
    public static let sourceAutoGood = "系统默认好评"
    public static let autoGoodContent = "系统默认好评"
    public static let hiddenByModeration = "评价已因违规处理"
    public static let anonymousReviewer = "买***"
    public static let arbitrationTag = ReviewCreditConfigDefaults.arbitrationTagLabel
    public static let arbitrationHint = "该订单曾进入小法庭仲裁，标记不可取消"
    public static let pendingBanner = "待评价"
    public static let pendingDaysPrefix = "还剩 "
    public static let pendingDaysSuffix = " 天"
    public static let emptyReviews = "暂无评价"
    public static let submitTitle = "发表评价"
    public static let submitCTA = "提交评价"
    public static let contentPlaceholder = "选填，说说这次交易体验（最多 500 字）"
    public static let badConfirmTitle = "确认给出差评？"
    public static let badConfirmMessage = "差评会影响对方信用与好评率，请确认属实后提交。"
    public static let badConfirmOK = "确认差评"
    public static let imagesHint = "最多 9 张"
    public static let creditTitle = "我的信用分"
    public static let monthPlusTitle = "本月加分"
    public static let monthCapReached = "本月加分已达上限"
    public static let logsTitle = "近 90 天流水"
    public static let logsEmpty = "暂无流水记录"
    public static let thresholdsTitle = "能力阈值"
    public static let threshold80Hint = "低于 80：不可出价、不可抽签报名"
    public static let threshold60Hint = "低于 60：不可发布、不可新购买"
    public static let threshold40Hint = "低于 40：交易能力全关，进入人工复核"
    public static let nextStepFulfill = "完成履约可缓慢回升"
    public static let nextStepSupport = "或联系客服"
    public static let blockTitle = "信用分不足"
    public static let defaultBlockedAction = "完成该操作"
    public static let sellerMetricsTitle = "履约指标"
    public static let sellerGoodRate = "好评率"
    public static let sellerSoldCount = "成交数"
    public static let sellerAvgShip = "均发货时长"
    public static let sellerAfterSale = "售后率"
    public static let sellerWindowHint = "近 90 天"
    public static let sellerStaleHint = "指标更新中"
    public static let userReviewsTitle = "收到的评价"
    public static let errOrderNotCompleted = "订单未完成，暂不可评价"
    public static let errWindowClosed = "评价窗口已关闭"
    public static let errAlreadyClosed = "评价已结束"
    public static let errForbidden = "无权评价该订单"
    public static let errContentRejected = "评价内容未通过审核，请修改后重试"
    public static let errCreditGeneric = "信用分不足，暂无法完成该操作"
    public static let errApprovalRequired = "调分需审批"
    public static let errSkippedRelated = "关联账号互评不加分"
    public static let errRetry = "请重试"
    public static let errLogin = "请先登录"
    public static let errRealName = "请先完成实名认证"
    public static let reasonCompletePay = "按时付款完成"
    public static let reasonCompleteShip = "按时发货完成"
    public static let reasonReviewGood = "收到好评"
    public static let reasonOfferUnpaid = "议价成交未付"
    public static let reasonShipLate = "发货超时"
    public static let reasonLotteryUnpaid = "中签逾期未付"
    public static let reasonImPenalty = "私聊敏感词处罚"
    public static let reasonAuctionDefault = "拍卖违约不付"
    public static let reasonOffPlatform = "诱导线下交易"
    public static let reasonRulingDefect = "裁定隐瞒瑕疵"
    public static let reasonRulingDamage = "裁定故意损坏"
    public static let reasonManual = "人工调分"
    public static let reasonCapped = "本月加分已达上限"
    public static let reasonSkippedRelated = "关联账号跳过加分"
    public static let draftSaved = "草稿已保存，网络恢复后可继续提交"
    public static let submitSuccess = "评价已提交"
}

// MARK: - Logic

public enum ReviewCreditLogic {
    /// Branch credit interstitial by `error.code` — never by localized message (client duty).
    public static func creditBlock(fromCode raw: String?, score: Int? = nil, action: String = ReviewCreditCopy.defaultBlockedAction) -> CreditBlockInfo? {
        guard let code = ReviewCreditErrorCode.normalize(raw), code.isCreditBlock else { return nil }
        return CreditBlockInfo(code: code, score: score, actionLabel: action)
    }

    public static func blockCode(forScore score: Int, thresholds: CreditThresholds = CreditThresholds()) -> ReviewCreditErrorCode? {
        if score < thresholds.th40 { return .creditBelow40 }
        if score < thresholds.th60 { return .creditBelow60 }
        if score < thresholds.th80 { return .creditBelow80 }
        return nil
    }

    /// Design §5.8: 「当前信用分 {n}，低于 {th}，暂无法{动作}。完成履约可缓慢回升，或联系客服。」
    public static func blockMessage(score: Int?, threshold: Int, action: String) -> String {
        let scorePart: String
        if let score {
            scorePart = "当前信用分 \(score)，低于 \(threshold)"
        } else {
            scorePart = "当前信用分低于 \(threshold)"
        }
        return "\(scorePart)，暂无法\(action)。\(ReviewCreditCopy.nextStepFulfill)，\(ReviewCreditCopy.nextStepSupport)。"
    }

    /// Remaining whole days until review deadline, calibrated with `server_time` offset (client duty).
    public static func reviewRemainDays(
        deadline: Date?,
        serverRemainDays: Int?,
        serverTime: Date?,
        fetchedAtLocal: Date,
        nowLocal: Date = Date(),
        completedAt: Date? = nil,
        windowDays: Int = ReviewCreditConfigDefaults.reviewWindowDays
    ) -> Int {
        if let deadline {
            let serverNow: Date
            if let serverTime {
                let elapsed = max(0, nowLocal.timeIntervalSince(fetchedAtLocal))
                serverNow = serverTime.addingTimeInterval(elapsed)
            } else {
                serverNow = nowLocal
            }
            let remain = deadline.timeIntervalSince(serverNow)
            return max(0, Int(ceil(remain / 86_400.0)))
        }
        if let serverRemainDays {
            // Decay by local elapsed whole days since fetch (advisory; prefer absolute deadline).
            let elapsedDays = max(0, Int(floor(nowLocal.timeIntervalSince(fetchedAtLocal) / 86_400.0)))
            return max(0, serverRemainDays - elapsedDays)
        }
        if let completedAt {
            let end = completedAt.addingTimeInterval(TimeInterval(windowDays * 86_400))
            return reviewRemainDays(
                deadline: end,
                serverRemainDays: nil,
                serverTime: serverTime,
                fetchedAtLocal: fetchedAtLocal,
                nowLocal: nowLocal
            )
        }
        return 0
    }

    public static func pendingBannerText(remainDays: Int) -> String {
        "\(ReviewCreditCopy.pendingBanner) · \(ReviewCreditCopy.pendingDaysPrefix)\(remainDays)\(ReviewCreditCopy.pendingDaysSuffix)"
    }

    public static func canSubmitReview(
        rating: ReviewRating?,
        content: String?,
        imageCount: Int,
        isLoggedIn: Bool,
        isRealNamed: Bool,
        windowOpen: Bool
    ) -> ReviewCreditErrorCode? {
        if !isLoggedIn { return .unauthorized }
        if !isRealNamed { return .realNameRequired }
        if !windowOpen { return .reviewWindowClosed }
        guard rating != nil else { return .reviewForbidden }
        if imageCount > ReviewCreditConfigDefaults.reviewMaxImages { return .contentRejected }
        if let content, content.count > ReviewCreditConfigDefaults.reviewContentMax {
            return .contentRejected
        }
        return nil
    }

    public static func validateContentLength(_ content: String?) -> Bool {
        guard let content else { return true }
        return content.count <= ReviewCreditConfigDefaults.reviewContentMax
    }

    public static func clampImageCount(_ count: Int) -> Int {
        min(max(0, count), ReviewCreditConfigDefaults.reviewMaxImages)
    }

    /// Public list hides pending; shows published + hidden placeholder.
    public static func publicVisible(_ review: OrderReview) -> Bool {
        review.resolvedStatus == .published || review.resolvedStatus == .hidden
    }

    public static func monthPlusCaption(used: Int, cap: Int) -> String {
        "\(ReviewCreditCopy.monthPlusTitle) \(used)/\(cap)"
    }

    public static func deltaTintIsPositive(_ delta: Int) -> Bool { delta > 0 }
}
