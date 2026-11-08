import Foundation
import CryptoKit

// MARK: - Publish / image norms (DES-v1.3-02-05 / PUB-01～06)

/// Stable publish error codes (DES §6).
public enum PublishErrorCode: String, Codable, Sendable, CaseIterable {
    case loginRequired = "login_required"
    case realNameRequired = "real_name_required"
    case sellerRequired = "seller_required"
    case publishForbidden = "publish_forbidden"
    case subMerchantRequired = "sub_merchant_required"
    case scaleNotEnabled = "scale_not_enabled"
    case imageCountInvalid = "image_count_invalid"
    case flawRequired = "flaw_required"
    case contactInfoForbidden = "contact_info_forbidden"
    case incrementTooSmall = "increment_too_small"
    /// DES-v1.3-03-01 §6 alias of increment floor.
    case incrementBelowTier = "increment_below_tier"
    case endAtTooSoon = "end_at_too_soon"
    case endAtTooFar = "end_at_too_far"
    case feeQuoteExpired = "fee_quote_expired"
    case depositTooLow = "deposit_too_low"
    /// DES-v1.3-03-01 §6 alias when client deposit < system floor.
    case depositBelowFloor = "deposit_below_floor"
    case draftLimitExceeded = "draft_limit_exceeded"
    case imagesNotDistinct = "images_not_distinct"
    case reserveTooLow = "reserve_too_low"
    case reserveBelowStart = "reserve_below_start"
    case invalidStock = "invalid_stock"
    case imageTooLarge = "image_too_large"
    case capabilityDisabled = "capability_disabled"
    case feeUnavailable = "fee_unavailable"
    case auctionKindNotAllowed = "auction_kind_not_allowed"
    case editionRequired = "edition_required"
    case paramsLocked = "params_locked"
    case sessionNotAllowed = "session_not_allowed"
    /// DES-v1.3-08-02 / PAY-07 — seller deposit gap blocks publish.
    case sellerDepositInsufficient = "seller_deposit_insufficient"

    public var fallbackMessage: String {
        switch self {
        case .loginRequired: return "去登录"
        case .realNameRequired: return "去实名"
        case .sellerRequired: return "去开通卖家"
        case .publishForbidden: return "账号禁发布"
        case .subMerchantRequired: return ProfitSharingCopy.publishGateTitle
        case .scaleNotEnabled: return "该比例暂未开放发布"
        case .imageCountInvalid: return "商品图需 5–9 张"
        case .flawRequired: return "有瑕成色须填写瑕疵说明并上传瑕疵图"
        case .contactInfoForbidden: return "不可填写联系方式"
        case .incrementTooSmall, .incrementBelowTier: return "加价幅度低于平台档位"
        case .endAtTooSoon: return "结束时间须至少在 24 小时后"
        case .endAtTooFar: return "结束时间不可超过发布后 14 天"
        case .feeQuoteExpired: return "费率预估已过期，请重新估算"
        case .depositTooLow, .depositBelowFloor: return "保证金不可低于系统默认值"
        case .draftLimitExceeded: return "云端草稿已达上限（20 条）"
        case .imagesNotDistinct: return "商品图不能全部相同"
        case .reserveTooLow, .reserveBelowStart: return "保留价不可低于起拍价"
        case .invalidStock: return "库存数量无效"
        case .imageTooLarge: return "单张图片过大（压缩前 ≤8MB）"
        case .capabilityDisabled: return "平台已限制你的发布权限"
        case .feeUnavailable: return "费率服务暂不可用"
        case .auctionKindNotAllowed: return "当前身份不可选择该拍卖类型"
        case .editionRequired: return "特殊号须填写限量编号"
        case .paramsLocked: return "已有出价，参数已锁定"
        case .sessionNotAllowed: return "个人拍品不可加入专场"
        case .sellerDepositInsufficient: return DepositCopy.sellerGapTitle
        }
    }

    public var opensSellerDeposit: Bool { self == .sellerDepositInsufficient }
}

public enum PublishTradeType: String, Codable, Sendable, CaseIterable {
    case fixed
    case auction

    public var title: String {
        switch self {
        case .fixed: return "直购"
        case .auction: return "拍卖"
        }
    }

    public var requiresCapability: String {
        switch self {
        case .fixed: return "can_fixed"
        case .auction: return "can_auction"
        }
    }
}

public enum PublishListingStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case pendingReview = "pending_review"
    case rejected
    case onSale = "on_sale"
    case scheduled
    case live
    case sold
    case offShelf = "off_shelf"

    public var isPreModeration: Bool { self == .pendingReview }

    public var submitSuccessCopy: String {
        switch self {
        case .pendingReview: return "前 5 件需审核，通过后上架"
        case .onSale: return "已上架"
        case .scheduled: return "已定时上拍"
        case .live: return "已上拍，祝一拍即中"
        case .draft: return "草稿已保存"
        case .rejected: return "审核未通过"
        case .sold, .offShelf: return "已提交"
        }
    }
}

public enum PublishConditionGrade: String, Codable, Sendable, CaseIterable {
    case newSealed = "new_sealed"
    case unpackedMint = "unpacked_mint"
    case flawed

    public var label: String {
        switch self {
        case .newSealed: return "全新未拆"
        case .unpackedMint: return "已拆无瑕"
        case .flawed: return "有瑕疵"
        }
    }

    public var requiresFlaw: Bool { self == .flawed }

    public static func normalize(_ raw: String?) -> PublishConditionGrade? {
        guard let raw, !raw.isEmpty else { return nil }
        if let g = PublishConditionGrade(rawValue: raw) { return g }
        switch raw {
        case "全新未拆": return .newSealed
        case "已拆无瑕", "99新", "95新": return .unpackedMint
        case "有瑕疵", "9成新", "8成新": return .flawed
        default: return nil
        }
    }
}

public enum PublishMaterial: String, Codable, Sendable, CaseIterable {
    case resin
    case alloy
    case other

    public var label: String {
        switch self {
        case .resin: return "树脂"
        case .alloy: return "合金"
        case .other: return "其他"
        }
    }
}

public enum PublishImageRole: String, Codable, Sendable, CaseIterable {
    case cover
    case gallery
    case flaw
}

public enum PublishLimits {
    public static let titleMin = 5
    public static let titleMax = 40
    public static let descriptionMax = 1000
    public static let flawDescMax = 200
    public static let productImageMin = 5
    public static let productImageMax = 9
    public static let flawImageMinWhenRequired = 1
    public static let flawImageMax = 6
    public static let maxSidePx: Double = 2048
    public static let maxBytesBeforeCompress = 8 * 1024 * 1024
    public static let recommendedBytesAfterCompress = Int(1.5 * 1024 * 1024)
    public static let jpegQuality: Double = 0.85
    public static let cloudDraftMax = 20
    public static let feeDebounceMs = 300
    public static let feeQuoteTTLSeconds: TimeInterval = 30 * 60
    public static let minPriceFen: Int64 = 100
    public static let depositRate = 0.10
    public static let depositRateBp = AuctionDepositFormula.rateBp
    public static let depositMinFen: Int64 = AuctionDepositFormula.minFen
    public static let depositMaxFen: Int64 = AuctionDepositFormula.maxFen
    public static let minEndAfterPublishSeconds: TimeInterval = 24 * 3600
    public static let personalMaxDays = 14
    public static let personalMaxEndSeconds: TimeInterval = TimeInterval(personalMaxDays) * 86_400
    public static let defaultScale = "1:43"
    public static let auctionDurationDays: [Int] = AuctionDurationCode.whitelistDays
    public static let personalStock = 1
    /// Identical product-image hashes exceeding this count → `images_not_distinct`.
    public static let maxIdenticalProductHashes = 4
}

// MARK: - Image norms (PUB-03)

/// Pure image-norm helpers (DES §5.4). Compression lives in the app (UIKit).
public enum PublishImageNorms {
    /// SHA-256 hex of raw bytes (used after client JPEG compress).
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func validateRawSize(_ byteCount: Int) -> PublishErrorCode? {
        if byteCount > PublishLimits.maxBytesBeforeCompress { return .imageTooLarge }
        return nil
    }

    /// Product images must be 5–9; all-identical hash sets of size ≥5 rejected.
    public static func validateProductImages(count: Int, hashes: [String]) -> PublishErrorCode? {
        if count < PublishLimits.productImageMin || count > PublishLimits.productImageMax {
            return .imageCountInvalid
        }
        if !hashes.isEmpty {
            var freq: [String: Int] = [:]
            for h in hashes { freq[h, default: 0] += 1 }
            if let max = freq.values.max(), max >= PublishLimits.productImageMin {
                return .imagesNotDistinct
            }
        }
        return nil
    }

    public static func validateFlawImages(count: Int, condition: PublishConditionGrade?) -> PublishErrorCode? {
        if count > PublishLimits.flawImageMax { return .imageCountInvalid }
        if condition?.requiresFlaw == true {
            if count < PublishLimits.flawImageMinWhenRequired { return .flawRequired }
        }
        return nil
    }

    /// Remaining product slots copy: 「再拍 N 张」.
    public static func remainingProductCopy(current: Int) -> String {
        let need = max(0, PublishLimits.productImageMin - current)
        if need > 0 { return "再拍 \(need) 张" }
        let room = PublishLimits.productImageMax - current
        if room > 0 { return "还可添加 \(room) 张" }
        return "已达上限"
    }
}

// MARK: - Deposit / duration (PUB / 8.3)

public enum PublishDeposit {
    /// Default deposit = clamp(start×10%, 50–2000 元) in fen. Seller may raise, not lower.
    public static func defaultAmount(startPriceFen: Int64) -> Int64 {
        AuctionDepositFormula.systemFloor(startPriceFen: startPriceFen)
    }

    public static func validate(depositFen: Int64, startPriceFen: Int64) -> PublishErrorCode? {
        if let err = AuctionDepositFormula.validate(depositFen: depositFen, startPriceFen: startPriceFen) {
            return err == .depositBelowFloor ? .depositTooLow : err
        }
        return nil
    }

    public static func previewCopy(startPriceFen: Int64?) -> String {
        AuctionDepositFormula.previewCopy(startPriceFen: startPriceFen)
    }
}

public enum PublishAuctionDuration {
    public static func endAt(days: Int, from now: Date = Date()) -> Date {
        now.addingTimeInterval(TimeInterval(days) * 86400)
    }

    public static func durationCode(days: Int) -> String? {
        AuctionDurationCode.from(days: days)?.rawValue
    }

    public static func validateEndAt(_ endAt: Date, now: Date = Date()) -> PublishErrorCode? {
        let delta = endAt.timeIntervalSince(now)
        if delta < PublishLimits.minEndAfterPublishSeconds {
            return .endAtTooSoon
        }
        if delta > PublishLimits.personalMaxEndSeconds {
            return .endAtTooFar
        }
        return nil
    }
}

// MARK: - Contact guard (PUB-05)

/// Title / description / flaw_desc contact scan (DES §5.6). Amounts alone are OK (T-07).
public enum PublishContactGuard {
    public static func containsContactInfo(_ text: String) -> Bool {
        ListingQAContactGuard.containsContactInfo(text)
    }

    public static func firstHit(in fields: [(name: String, text: String)]) -> String? {
        for f in fields where containsContactInfo(f.text) {
            return f.name
        }
        return nil
    }
}

// MARK: - Fee quote (PUB-06)

/// Server fee estimate — client must not multiply rates locally (DES §5.7).
public struct FeeQuoteEstimate: Codable, Equatable, Sendable {
    public let feeQuoteId: String
    public let rate: Double
    public let platformFee: Int64
    public let sellerNet: Int64
    public let quoteHash: String
    public let ruleVersion: String
    public let expiresAt: Date?
    /// Hammer / list price used for the quote (fen).
    public let price: Int64?
    public let shippingFee: Int64?

    public init(
        feeQuoteId: String,
        rate: Double,
        platformFee: Int64,
        sellerNet: Int64,
        quoteHash: String,
        ruleVersion: String,
        expiresAt: Date? = nil,
        price: Int64? = nil,
        shippingFee: Int64? = nil
    ) {
        self.feeQuoteId = feeQuoteId
        self.rate = rate
        self.platformFee = platformFee
        self.sellerNet = sellerNet
        self.quoteHash = quoteHash
        self.ruleVersion = ruleVersion
        self.expiresAt = expiresAt
        self.price = price
        self.shippingFee = shippingFee
    }

    public var ratePercentText: String {
        String(format: "%.1f%%", rate * 100)
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    public var disclaimer: String {
        "以成交当时费率为准，规则变了可能不同"
    }
}

public struct FeeEstimateRequest: Equatable, Sendable {
    public var tradeType: PublishTradeType
    public var price: Int64
    public var shippingFee: Int64

    public init(tradeType: PublishTradeType, price: Int64, shippingFee: Int64 = 0) {
        self.tradeType = tradeType
        self.price = price
        self.shippingFee = shippingFee
    }

    public var body: [String: Any] {
        [
            "trade_type": tradeType.rawValue,
            "price": price,
            "shipping_fee": shippingFee,
        ]
    }
}

/// Reference formula used only in tests / docs (DES §5.7 example). Production UI uses server quote.
public enum FeeQuoteFormula {
    /// Round half-up to fen: fee = price × rate; net = price + shipping − fee (platform channel fee).
    public static func estimate(priceFen: Int64, rate: Double, shippingFeeFen: Int64 = 0) -> (platformFee: Int64, sellerNet: Int64) {
        let fee = Int64((Double(priceFen) * rate).rounded())
        let net = priceFen + shippingFeeFen - fee
        return (fee, net)
    }
}

// MARK: - Draft payload (PUB-04)

public struct PublishImageSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var imageId: String?
    public var url: String?
    public var sha256: String?
    public var role: PublishImageRole
    public var localUpdatedAt: Date

    public init(
        id: String = UUID().uuidString,
        imageId: String? = nil,
        url: String? = nil,
        sha256: String? = nil,
        role: PublishImageRole = .gallery,
        localUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.imageId = imageId
        self.url = url
        self.sha256 = sha256
        self.role = role
        self.localUpdatedAt = localUpdatedAt
    }

    public var remoteRef: String? { imageId ?? url }
}

public struct PublishDraftPayload: Codable, Equatable, Sendable {
    public var tradeType: PublishTradeType
    public var title: String
    public var description: String
    public var brand: String
    public var customBrand: String?
    public var series: String
    public var customSeries: String?
    public var model: String
    public var customModel: String?
    public var scale: String
    public var color: String
    public var material: String
    public var customMaterial: String?
    public var limitedNo: String
    public var condition: String
    public var flawDesc: String
    public var productImages: [PublishImageSlot]
    public var flawImages: [PublishImageSlot]
    public var freeShipping: Bool
    public var shippingFeeYuan: String
    public var shipProvince: String
    public var shipCity: String
    public var costPriceYuan: String
    /// Fixed-price
    public var priceYuan: String
    public var stock: Int
    public var negotiable: Bool
    /// Auction
    public var auctionKind: String
    public var startPriceYuan: String
    public var depositYuan: String
    public var reservePriceYuan: String
    public var incrementYuan: String
    public var durationDays: Int
    public var useCustomEndAt: Bool
    public var endAt: Date
    public var startNow: Bool
    public var startAt: Date
    public var feeQuoteId: String?
    public var cloudListingId: Int64?
    public var updatedAt: Date

    public init(tradeType: PublishTradeType = .auction) {
        self.tradeType = tradeType
        title = ""
        description = ""
        brand = ""
        customBrand = nil
        series = ""
        customSeries = nil
        model = ""
        customModel = nil
        scale = PublishLimits.defaultScale
        color = ""
        material = ""
        customMaterial = nil
        limitedNo = ""
        condition = ""
        flawDesc = ""
        productImages = []
        flawImages = []
        freeShipping = true
        shippingFeeYuan = ""
        shipProvince = ""
        shipCity = ""
        costPriceYuan = ""
        priceYuan = ""
        stock = PublishLimits.personalStock
        negotiable = false
        auctionKind = "personal"
        startPriceYuan = ""
        depositYuan = ""
        reservePriceYuan = ""
        incrementYuan = "50"
        durationDays = 3
        useCustomEndAt = false
        endAt = Date().addingTimeInterval(3 * 86400)
        startNow = true
        startAt = Date().addingTimeInterval(3600)
        feeQuoteId = nil
        cloudListingId = nil
        updatedAt = Date()
    }

    public var effectiveBrand: String {
        brand.isEmpty ? (customBrand ?? "") : brand
    }

    public var effectiveSeries: String {
        series.isEmpty ? (customSeries ?? "") : series
    }

    public var effectiveCondition: PublishConditionGrade? {
        PublishConditionGrade.normalize(condition)
    }

    public var priceFen: Int64? {
        let raw = tradeType == .fixed ? priceYuan : startPriceYuan
        return Self.yuanToFen(raw)
    }

    public var shippingFeeFen: Int64 {
        if freeShipping { return 0 }
        return Self.yuanToFen(shippingFeeYuan) ?? 0
    }

    public static func yuanToFen(_ yuan: String) -> Int64? {
        let t = yuan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let v = Double(t) else { return nil }
        return Int64((v * 100).rounded())
    }

    public mutating func touch() { updatedAt = Date() }
}

/// Cloud draft row from `POST/GET /listings` with `status=draft`.
public struct CloudPublishDraft: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let status: String
    public let tradeType: String?
    public let title: String?
    public let updatedAt: Date
    public let payload: PublishDraftPayload?

    public init(
        id: Int64,
        status: String = PublishListingStatus.draft.rawValue,
        tradeType: String? = nil,
        title: String? = nil,
        updatedAt: Date,
        payload: PublishDraftPayload? = nil
    ) {
        self.id = id
        self.status = status
        self.tradeType = tradeType
        self.title = title
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

public enum PublishDraftConflictResolution: String, Sendable {
    case keepLocal
    case useCloud
}

public enum PublishDraftSync {
    /// Newer `updatedAt` wins; equal timestamps prefer cloud (server authority).
    public static func preferCloud(local: Date, cloud: Date) -> Bool {
        cloud >= local
    }
}

// MARK: - Publish result

public struct PublishSubmitResult: Codable, Equatable, Sendable {
    public let listingId: Int64
    public let lotId: Int64?
    public let status: String
    public let publishedSeq: Int?

    public init(listingId: Int64, lotId: Int64? = nil, status: String, publishedSeq: Int? = nil) {
        self.listingId = listingId
        self.lotId = lotId
        self.status = status
        self.publishedSeq = publishedSeq
    }

    public var listingStatus: PublishListingStatus? {
        PublishListingStatus(rawValue: status)
    }

    enum CodingKeys: String, CodingKey {
        case listingId, lotId, status, publishedSeq, id
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        publishedSeq = try c.decodeIfPresent(Int.self, forKey: .publishedSeq)
        let listing = try c.decodeIfPresent(Int64.self, forKey: .listingId)
        let lot = try c.decodeIfPresent(Int64.self, forKey: .lotId)
        let id = try c.decodeIfPresent(Int64.self, forKey: .id)
        listingId = listing ?? id ?? 0
        lotId = lot ?? id
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(listingId, forKey: .listingId)
        try c.encodeIfPresent(lotId, forKey: .lotId)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(publishedSeq, forKey: .publishedSeq)
    }
}

// MARK: - Entry gate (PUB-01)

public enum PublishEntryGate: Equatable, Sendable {
    case ok
    case loginRequired
    case frozen
    case realNameRequired
    case sellerRequired
    case publishForbidden
    case capabilityDisabled(String)
    case comingSoon(String)

    public var errorCode: PublishErrorCode? {
        switch self {
        case .ok: return nil
        case .loginRequired: return .loginRequired
        case .frozen, .publishForbidden: return .publishForbidden
        case .realNameRequired: return .realNameRequired
        case .sellerRequired: return .sellerRequired
        case .capabilityDisabled: return .capabilityDisabled
        case .comingSoon: return nil
        }
    }

    public var message: String {
        switch self {
        case .ok: return ""
        case .loginRequired: return PublishErrorCode.loginRequired.fallbackMessage
        case .frozen, .publishForbidden: return PublishErrorCode.publishForbidden.fallbackMessage
        case .realNameRequired: return PublishErrorCode.realNameRequired.fallbackMessage
        case .sellerRequired: return PublishErrorCode.sellerRequired.fallbackMessage
        case .capabilityDisabled: return PublishErrorCode.capabilityDisabled.fallbackMessage
        case .comingSoon(let title): return "「\(title)」即将开放"
        }
    }
}

public enum PublishEntryResolver {
    /// Validation order: login → frozen → real-name → seller → capability → create readiness (DES §5.1).
    /// Release/spot_release: capabilityDisabled before comingSoon when create UX is not ready.
    public static func resolve(
        isLoggedIn: Bool,
        isFrozen: Bool,
        canPublish: Bool,
        realNameDone: Bool,
        sellerReady: Bool,
        actionKey: String,
        actionEnabled: Bool,
        actionTitle: String,
        requiresCapability: String? = nil,
        capabilityAllows: (String) -> Bool
    ) -> PublishEntryGate {
        if !isLoggedIn { return .loginRequired }
        if isFrozen { return .frozen }
        if !canPublish { return .publishForbidden }
        if !realNameDone { return .realNameRequired }
        if !sellerReady { return .sellerRequired }

        let capKey = PublishTradeType(rawValue: actionKey)?.requiresCapability
            ?? requiresCapability
            ?? ((actionKey == "release" || actionKey == "spot_release") ? "can_spot_release" : nil)
        if let capKey, !capabilityAllows(capKey) {
            return .capabilityDisabled(capKey)
        }

        if !actionEnabled {
            return .comingSoon(actionTitle)
        }
        if actionKey == "post" || actionKey == "community" {
            return .comingSoon(actionTitle)
        }
        if actionKey == "release" || actionKey == "spot_release" {
            return .comingSoon(actionTitle)
        }
        return .ok
    }
}

// MARK: - Client preflight validator (DES §5.8 client mirror)

public enum PublishValidator {
    private static let limitedNoPattern = try! NSRegularExpression(pattern: #"^[0-9]+/[0-9]+$"#)

    public static func validateTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count >= PublishLimits.titleMin && t.count <= PublishLimits.titleMax
    }

    /// Client preflight before submit. Title length is checked separately via `validateTitle`.
    public static func validate(
        _ draft: PublishDraftPayload,
        enabledScales: [String],
        requireFeeQuote: Bool = false
    ) -> PublishErrorCode? {
        if PublishContactGuard.firstHit(in: [
            ("title", draft.title),
            ("description", draft.description),
            ("flaw_desc", draft.flawDesc),
            ("custom_brand", draft.customBrand ?? ""),
            ("custom_series", draft.customSeries ?? ""),
            ("custom_model", draft.customModel ?? ""),
        ]) != nil {
            return .contactInfoForbidden
        }

        let hashes = draft.productImages.compactMap(\.sha256)
        if let err = PublishImageNorms.validateProductImages(count: draft.productImages.count, hashes: hashes) {
            return err
        }

        let condition = draft.effectiveCondition
        if condition?.requiresFlaw == true {
            let descOK = !draft.flawDesc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !descOK || draft.flawImages.count < PublishLimits.flawImageMinWhenRequired {
                return .flawRequired
            }
        }
        if let err = PublishImageNorms.validateFlawImages(count: draft.flawImages.count, condition: condition) {
            return err
        }
        if draft.flawDesc.count > PublishLimits.flawDescMax { return .flawRequired }
        if draft.description.count > PublishLimits.descriptionMax { return .contactInfoForbidden }

        let scale = draft.scale.isEmpty ? PublishLimits.defaultScale : draft.scale
        if !enabledScales.isEmpty {
            if !enabledScales.contains(scale) { return .scaleNotEnabled }
        } else if scale != PublishLimits.defaultScale {
            return .scaleNotEnabled
        }

        if !draft.limitedNo.isEmpty {
            let s = draft.limitedNo
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            if limitedNoPattern.firstMatch(in: s, range: range) == nil {
                return .invalidStock
            }
        }

        guard let price = draft.priceFen, price >= PublishLimits.minPriceFen else {
            return .invalidStock
        }

        switch draft.tradeType {
        case .fixed:
            if draft.stock != PublishLimits.personalStock { return .invalidStock }
        case .auction:
            let kind = AuctionKind(rawValue: draft.auctionKind) ?? .personal
            if kind.requiresEditionNo {
                let edition = draft.limitedNo.trimmingCharacters(in: .whitespacesAndNewlines)
                if edition.isEmpty { return .editionRequired }
            }
            if let reserve = PublishDraftPayload.yuanToFen(draft.reservePriceYuan), reserve < price {
                return .reserveBelowStart
            }
            let deposit = PublishDraftPayload.yuanToFen(draft.depositYuan)
                ?? PublishDeposit.defaultAmount(startPriceFen: price)
            if let err = PublishDeposit.validate(depositFen: deposit, startPriceFen: price) {
                return err
            }
            if kind.usesFreeEndSchedule {
                let end = draft.useCustomEndAt
                    ? draft.endAt
                    : PublishAuctionDuration.endAt(days: draft.durationDays)
                if let err = PublishAuctionDuration.validateEndAt(end) { return err }
            }
            let inc = PublishDraftPayload.yuanToFen(draft.incrementYuan) ?? 0
            if let err = BidIncrementLadder.validateSellerIncrement(incrementFen: inc, startPriceFen: price) {
                return err == .incrementBelowTier ? .incrementTooSmall : err
            }
        }

        if requireFeeQuote, draft.feeQuoteId == nil || draft.feeQuoteId?.isEmpty == true {
            return .feeUnavailable
        }
        return nil
    }
}
