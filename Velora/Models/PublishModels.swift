import Foundation
import CryptoKit

// MARK: - Publish / image norms (DES-v1.3-02-05) — app mirror of VeloraCore

// MARK: - Publish / image norms (DES-v1.3-02-05 / PUB-01～06)

/// Stable publish error codes (DES §6).
enum PublishErrorCode: String, Codable, Sendable, CaseIterable {
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

    var fallbackMessage: String {
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

    var opensSellerDeposit: Bool { self == .sellerDepositInsufficient }
}

enum PublishTradeType: String, Codable, Sendable, CaseIterable {
    case fixed
    case auction

    var title: String {
        switch self {
        case .fixed: return "直购"
        case .auction: return "拍卖"
        }
    }

    var requiresCapability: String {
        switch self {
        case .fixed: return "can_fixed"
        case .auction: return "can_auction"
        }
    }
}

enum PublishListingStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case pendingReview = "pending_review"
    case rejected
    case onSale = "on_sale"
    case scheduled
    case live
    case sold
    case offShelf = "off_shelf"

    var isPreModeration: Bool { self == .pendingReview }

    var submitSuccessCopy: String {
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

enum PublishConditionGrade: String, Codable, Sendable, CaseIterable {
    case newSealed = "new_sealed"
    case unpackedMint = "unpacked_mint"
    case flawed

    var label: String {
        switch self {
        case .newSealed: return "全新未拆"
        case .unpackedMint: return "已拆无瑕"
        case .flawed: return "有瑕疵"
        }
    }

    var requiresFlaw: Bool { self == .flawed }

    static func normalize(_ raw: String?) -> PublishConditionGrade? {
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

enum PublishMaterial: String, Codable, Sendable, CaseIterable {
    case resin
    case alloy
    case other

    var label: String {
        switch self {
        case .resin: return "树脂"
        case .alloy: return "合金"
        case .other: return "其他"
        }
    }
}

enum PublishImageRole: String, Codable, Sendable, CaseIterable {
    case cover
    case gallery
    case flaw
}

enum PublishLimits {
    static let titleMin = 5
    static let titleMax = 40
    static let descriptionMax = 1000
    static let flawDescMax = 200
    static let productImageMin = 5
    static let productImageMax = 9
    static let flawImageMinWhenRequired = 1
    static let flawImageMax = 6
    static let maxSidePx: Double = 2048
    static let maxBytesBeforeCompress = 8 * 1024 * 1024
    static let recommendedBytesAfterCompress = Int(1.5 * 1024 * 1024)
    static let jpegQuality: Double = 0.85
    static let cloudDraftMax = 20
    static let feeDebounceMs = 300
    static let feeQuoteTTLSeconds: TimeInterval = 30 * 60
    static let minPriceFen: Int64 = 100
    static let depositRate = 0.10
    static let depositRateBp = AuctionDepositFormula.rateBp
    static let depositMinFen: Int64 = AuctionDepositFormula.minFen
    static let depositMaxFen: Int64 = AuctionDepositFormula.maxFen
    static let minEndAfterPublishSeconds: TimeInterval = 24 * 3600
    static let personalMaxDays = 14
    static let personalMaxEndSeconds: TimeInterval = TimeInterval(personalMaxDays) * 86_400
    static let defaultScale = "1:43"
    static let auctionDurationDays: [Int] = AuctionDurationCode.whitelistDays
    static let personalStock = 1
    /// Identical product-image hashes exceeding this count → `images_not_distinct`.
    static let maxIdenticalProductHashes = 4
}

// MARK: - Image norms (PUB-03)

/// Pure image-norm helpers (DES §5.4). Compression lives in the app (UIKit).
enum PublishImageNorms {
    /// SHA-256 hex of raw bytes (used after client JPEG compress).
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func validateRawSize(_ byteCount: Int) -> PublishErrorCode? {
        if byteCount > PublishLimits.maxBytesBeforeCompress { return .imageTooLarge }
        return nil
    }

    /// Product images must be 5–9; all-identical hash sets of size ≥5 rejected.
    static func validateProductImages(count: Int, hashes: [String]) -> PublishErrorCode? {
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

    static func validateFlawImages(count: Int, condition: PublishConditionGrade?) -> PublishErrorCode? {
        if count > PublishLimits.flawImageMax { return .imageCountInvalid }
        if condition?.requiresFlaw == true {
            if count < PublishLimits.flawImageMinWhenRequired { return .flawRequired }
        }
        return nil
    }

    /// Remaining product slots copy: 「再拍 N 张」.
    static func remainingProductCopy(current: Int) -> String {
        let need = max(0, PublishLimits.productImageMin - current)
        if need > 0 { return "再拍 \(need) 张" }
        let room = PublishLimits.productImageMax - current
        if room > 0 { return "还可添加 \(room) 张" }
        return "已达上限"
    }
}

// MARK: - Deposit / duration (PUB / 8.3)

enum PublishDeposit {
    /// Default deposit = clamp(start×10%, 50–2000 元) in fen. Seller may raise, not lower.
    static func defaultAmount(startPriceFen: Int64) -> Int64 {
        AuctionDepositFormula.systemFloor(startPriceFen: startPriceFen)
    }

    static func validate(depositFen: Int64, startPriceFen: Int64) -> PublishErrorCode? {
        if let err = AuctionDepositFormula.validate(depositFen: depositFen, startPriceFen: startPriceFen) {
            return err == .depositBelowFloor ? .depositTooLow : err
        }
        return nil
    }

    static func previewCopy(startPriceFen: Int64?) -> String {
        AuctionDepositFormula.previewCopy(startPriceFen: startPriceFen)
    }
}

enum PublishAuctionDuration {
    static func endAt(days: Int, from now: Date = Date()) -> Date {
        now.addingTimeInterval(TimeInterval(days) * 86400)
    }

    static func durationCode(days: Int) -> String? {
        AuctionDurationCode.from(days: days)?.rawValue
    }

    static func validateEndAt(_ endAt: Date, now: Date = Date()) -> PublishErrorCode? {
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
enum PublishContactGuard {
    static func containsContactInfo(_ text: String) -> Bool {
        ListingQAContactGuard.containsContactInfo(text)
    }

    static func firstHit(in fields: [(name: String, text: String)]) -> String? {
        for f in fields where containsContactInfo(f.text) {
            return f.name
        }
        return nil
    }
}

// MARK: - Fee quote (PUB-06)

/// Server fee estimate — client must not multiply rates locally (DES §5.7).
struct FeeQuoteEstimate: Codable, Equatable, Sendable {
    let feeQuoteId: String
    let rate: Double
    let platformFee: Int64
    let sellerNet: Int64
    let quoteHash: String
    let ruleVersion: String
    let expiresAt: Date?
    /// Hammer / list price used for the quote (fen).
    let price: Int64?
    let shippingFee: Int64?

    init(
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

    var ratePercentText: String {
        String(format: "%.1f%%", rate * 100)
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    var disclaimer: String {
        "以成交当时费率为准，规则变了可能不同"
    }
}

struct FeeEstimateRequest: Equatable, Sendable {
    var tradeType: PublishTradeType
    var price: Int64
    var shippingFee: Int64

    init(tradeType: PublishTradeType, price: Int64, shippingFee: Int64 = 0) {
        self.tradeType = tradeType
        self.price = price
        self.shippingFee = shippingFee
    }

    var body: [String: Any] {
        [
            "trade_type": tradeType.rawValue,
            "price": price,
            "shipping_fee": shippingFee,
        ]
    }
}

/// Reference formula used only in tests / docs (DES §5.7 example). Production UI uses server quote.
enum FeeQuoteFormula {
    /// Round half-up to fen: fee = price × rate; net = price + shipping − fee (platform channel fee).
    static func estimate(priceFen: Int64, rate: Double, shippingFeeFen: Int64 = 0) -> (platformFee: Int64, sellerNet: Int64) {
        let fee = Int64((Double(priceFen) * rate).rounded())
        let net = priceFen + shippingFeeFen - fee
        return (fee, net)
    }
}

// MARK: - Draft payload (PUB-04)

struct PublishImageSlot: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var imageId: String?
    var url: String?
    var sha256: String?
    var role: PublishImageRole
    var localUpdatedAt: Date

    init(
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

    var remoteRef: String? { imageId ?? url }
}

struct PublishDraftPayload: Codable, Equatable, Sendable {
    var tradeType: PublishTradeType
    var title: String
    var description: String
    var brand: String
    var customBrand: String?
    var series: String
    var customSeries: String?
    var model: String
    var customModel: String?
    var scale: String
    var color: String
    var material: String
    var customMaterial: String?
    var limitedNo: String
    var condition: String
    var flawDesc: String
    var productImages: [PublishImageSlot]
    var flawImages: [PublishImageSlot]
    var freeShipping: Bool
    var shippingFeeYuan: String
    var shipProvince: String
    var shipCity: String
    var costPriceYuan: String
    /// Fixed-price
    var priceYuan: String
    var stock: Int
    var negotiable: Bool
    /// Auction
    var auctionKind: String
    var startPriceYuan: String
    var depositYuan: String
    var reservePriceYuan: String
    var incrementYuan: String
    var durationDays: Int
    var useCustomEndAt: Bool
    var endAt: Date
    var startNow: Bool
    var startAt: Date
    var feeQuoteId: String?
    var cloudListingId: Int64?
    var updatedAt: Date

    init(tradeType: PublishTradeType = .auction) {
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

    var effectiveBrand: String {
        brand.isEmpty ? (customBrand ?? "") : brand
    }

    var effectiveSeries: String {
        series.isEmpty ? (customSeries ?? "") : series
    }

    var effectiveCondition: PublishConditionGrade? {
        PublishConditionGrade.normalize(condition)
    }

    var priceFen: Int64? {
        let raw = tradeType == .fixed ? priceYuan : startPriceYuan
        return Self.yuanToFen(raw)
    }

    var shippingFeeFen: Int64 {
        if freeShipping { return 0 }
        return Self.yuanToFen(shippingFeeYuan) ?? 0
    }

    static func yuanToFen(_ yuan: String) -> Int64? {
        let t = yuan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let v = Double(t) else { return nil }
        return Int64((v * 100).rounded())
    }

    mutating func touch() { updatedAt = Date() }
}

/// Cloud draft row from `POST/GET /listings` with `status=draft`.
struct CloudPublishDraft: Codable, Equatable, Sendable, Identifiable {
    let id: Int64
    let status: String
    let tradeType: String?
    let title: String?
    let updatedAt: Date
    let payload: PublishDraftPayload?

    init(
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

enum PublishDraftConflictResolution: String, Sendable {
    case keepLocal
    case useCloud
}

enum PublishDraftSync {
    /// Newer `updatedAt` wins; equal timestamps prefer cloud (server authority).
    static func preferCloud(local: Date, cloud: Date) -> Bool {
        cloud >= local
    }
}

// MARK: - Publish result

struct PublishSubmitResult: Codable, Equatable, Sendable {
    let listingId: Int64
    let lotId: Int64?
    let status: String
    let publishedSeq: Int?

    init(listingId: Int64, lotId: Int64? = nil, status: String, publishedSeq: Int? = nil) {
        self.listingId = listingId
        self.lotId = lotId
        self.status = status
        self.publishedSeq = publishedSeq
    }

    var listingStatus: PublishListingStatus? {
        PublishListingStatus(rawValue: status)
    }

    enum CodingKeys: String, CodingKey {
        case listingId, lotId, status, publishedSeq, id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        publishedSeq = try c.decodeIfPresent(Int.self, forKey: .publishedSeq)
        let listing = try c.decodeIfPresent(Int64.self, forKey: .listingId)
        let lot = try c.decodeIfPresent(Int64.self, forKey: .lotId)
        let id = try c.decodeIfPresent(Int64.self, forKey: .id)
        listingId = listing ?? id ?? 0
        lotId = lot ?? id
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(listingId, forKey: .listingId)
        try c.encodeIfPresent(lotId, forKey: .lotId)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(publishedSeq, forKey: .publishedSeq)
    }
}

// MARK: - Entry gate (PUB-01)

enum PublishEntryGate: Equatable, Sendable {
    case ok
    case loginRequired
    case frozen
    case realNameRequired
    case sellerRequired
    case publishForbidden
    case capabilityDisabled(String)
    case comingSoon(String)

    var errorCode: PublishErrorCode? {
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

    var message: String {
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

enum PublishEntryResolver {
    /// Validation order: login → frozen → real-name → seller → capability → create readiness (DES §5.1).
    /// Release/spot_release: capabilityDisabled before comingSoon when create UX is not ready.
    static func resolve(
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

enum PublishValidator {
    private static let limitedNoPattern = try! NSRegularExpression(pattern: #"^[0-9]+/[0-9]+$"#)

    static func validateTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count >= PublishLimits.titleMin && t.count <= PublishLimits.titleMax
    }

    /// Client preflight before submit. Title length is checked separately via `validateTitle`.
    static func validate(
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
