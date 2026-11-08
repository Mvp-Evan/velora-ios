import Foundation

// MARK: - Product library / cabinet / badges / atlas (DES-v1.3-12-04 LIB-01～06 / D42 — app mirror of VeloraCore)

/// Product defaults (design §15). Hot-config on server; client mirrors for UX + gates.
/// Phase 3: `library.curve` defaults **off** — hide curve until flag opens.
enum LibraryConfigDefaults {
    static let curveFlagKey = "library.curve"
    static let curveEnabledDefault = false

    static let curveMinSamplesKey = "sku.curve_min_samples"
    static let curveMinSamples = 5

    static let valuationDaysKey = "sku.valuation_days"
    static let valuationDays = 90
    static let valuationMinNKey = "sku.valuation_min_n"
    static let valuationMinN = 3

    static let badgeCopperRatioKey = "badge.copper_ratio"
    static let badgeCopperRatio = 0.3
    static let badgeSilverRatioKey = "badge.silver_ratio"
    static let badgeSilverRatio = 0.6

    static let cabinetPublicDefaultKey = "cabinet.public_default"
    static let cabinetPublicDefault = true

    static let firstScale = "1:43"
    static let wishlistMax = 200
    static let wishlistRatePerMin = 20
    static let cabinetPageSize = 30
    static let skuListPageSize = 20

    static let meEntryCabinet = "cabinet"
    static let meEntryLibrary = "library"
    static let meEntryAtlas = "atlas"

    static let disclaimerCodeReferenceOnly = "reference_only"
    static let disclaimerText = "仅供参考，不构成估价或保值承诺"
    static let idempotencyHeader = "Idempotency-Key"
    static let shanghaiTimeZoneID = "Asia/Shanghai"
}

// MARK: - Enums

enum SkuStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case draft
    case active
    case retired

    static func normalize(_ raw: String?) -> SkuStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        return SkuStatus(rawValue: raw.lowercased())
    }
}

enum WishlistKind: String, Codable, Sendable, CaseIterable, Equatable {
    case wish
    case want

    static func normalize(_ raw: String?) -> WishlistKind? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = WishlistKind(rawValue: s) { return exact }
        switch s {
        case "favorite", "fav", "collect": return .wish
        case "buy_request", "求购": return .want
        default: return nil
        }
    }
}

enum CabinetItemSource: String, Codable, Sendable, CaseIterable, Equatable {
    case orderAuto = "order_auto"
    case manual

    static func normalize(_ raw: String?) -> CabinetItemSource? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = CabinetItemSource(rawValue: s) { return exact }
        switch s {
        case "auto", "order", "platform": return .orderAuto
        case "user", "manual_add": return .manual
        default: return nil
        }
    }

    /// Manual pieces count toward completion but **not** badge thresholds (design §8).
    var countsTowardBadge: Bool { self == .orderAuto }
}

enum CabinetItemStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case `in` = "in"
    case removed

    static func normalize(_ raw: String?) -> CabinetItemStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = CabinetItemStatus(rawValue: s) { return exact }
        switch s {
        case "active", "owned": return .in
        case "out", "deleted": return .removed
        default: return nil
        }
    }
}

enum SeriesBadgeTier: String, Codable, Sendable, CaseIterable, Equatable {
    case copper
    case silver
    case gold

    static func normalize(_ raw: String?) -> SeriesBadgeTier? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = SeriesBadgeTier(rawValue: s) { return exact }
        switch s {
        case "bronze", "铜", "铜章": return .copper
        case "银", "银章": return .silver
        case "金", "金章": return .gold
        default: return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .copper: return LibraryCopy.tierCopper
        case .silver: return LibraryCopy.tierSilver
        case .gold: return LibraryCopy.tierGold
        }
    }

    /// Award order copper → silver → gold (design §5.5).
    var awardOrder: Int {
        switch self {
        case .copper: return 0
        case .silver: return 1
        case .gold: return 2
        }
    }
}

enum ValuationStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case ok
    case partial
    case unavailable

    static func normalize(_ raw: String?) -> ValuationStatus {
        guard let raw, !raw.isEmpty else { return .unavailable }
        return ValuationStatus(rawValue: raw.lowercased()) ?? .unavailable
    }
}

/// Phase 3 shell state for library / cabinet / 图鉴 entry points (design §9).
enum LibraryPlaceholderKind: String, Sendable, Equatable {
    case libraryBuilding
    case cabinetComingSoon
    case atlasComingSoon
    case cabinetPrivate
    case curveNotReady
    case curveHiddenByFlag
    case empty
}

// MARK: - Error codes

enum LibraryErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case skuNotFound = "sku_not_found"
    case curveNotReady = "curve_not_ready"
    case cabinetPrivate = "cabinet_private"
    case realNameRequired = "real_name_required"
    case accountRestricted = "account_restricted"
    case wishlistFull = "wishlist_full"
    case libraryNotEnabled = "library_not_enabled"
    case featureDisabled = "feature_disabled"
    case unauthorized
    case loginRequired = "login_required"

    static func normalize(_ raw: String?) -> LibraryErrorCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = LibraryErrorCode(rawValue: s) { return exact }
        switch s {
        case "not_found", "sku_missing":
            return .skuNotFound
        case "sample_insufficient", "curve_disabled", "samples_below_threshold":
            return .curveNotReady
        case "cabinet_hidden", "private_cabinet":
            return .cabinetPrivate
        case "realname_required", "kyc_required":
            return .realNameRequired
        case "frozen", "account_frozen":
            return .accountRestricted
        case "wishlist_limit", "wish_full":
            return .wishlistFull
        case "library_disabled", "library_off", "product_library_disabled":
            return .libraryNotEnabled
        case "capability_disabled", "not_launched":
            return .featureDisabled
        case "unauthenticated":
            return .loginRequired
        default:
            return nil
        }
    }

    var opensLogin: Bool {
        self == .unauthorized || self == .loginRequired
    }

    var fallbackMessage: String {
        switch self {
        case .skuNotFound: return LibraryCopy.skuNotFound
        case .curveNotReady: return LibraryCopy.curveNotReady
        case .cabinetPrivate: return LibraryCopy.cabinetPrivate
        case .realNameRequired: return LibraryCopy.realNameRequired
        case .accountRestricted: return LibraryCopy.accountRestricted
        case .wishlistFull: return LibraryCopy.wishlistFull
        case .libraryNotEnabled, .featureDisabled: return LibraryCopy.libraryNotEnabled
        case .unauthorized, .loginRequired: return LibraryCopy.loginRequired
        }
    }
}

// MARK: - Copy

enum LibraryCopy {
    static let libraryTitle = "产品库"
    static let libraryBuilding = "产品库建设中"
    static let libraryBuildingHint = "品牌、系列与 SKU 图鉴即将上线"
    static let cabinetTitle = "模型柜"
    static let cabinetComingSoon = "模型柜即将开放"
    static let cabinetComingSoonHint = "成交后自动入柜，也可手动收藏展示"
    static let atlasTitle = "图鉴"
    static let atlasComingSoon = "图鉴即将开放"
    static let atlasComingSoonHint = "系列完成度与参考估值即将上线"
    static let curveNotReady = "样本不足，暂不展示曲线"
    static let curveHidden = "成交曲线暂未开放"
    static let curveTitle = "成交曲线"
    static let cabinetPrivate = "该柜未公开"
    static let cabinetEmpty = "柜内暂无藏品"
    static let manualMark = "手动"
    static let manualConfirm = "不代表平台成交，仅作收藏展示"
    static let valuationDisclaimer = LibraryConfigDefaults.disclaimerText
    static let completionFormat = "已收 %d / %d 款"
    static let tierCopper = "铜章"
    static let tierSilver = "银章"
    static let tierGold = "金章"
    static let skuNotFound = "SKU 不存在"
    static let realNameRequired = "完成实名后即可求购"
    static let accountRestricted = "账号受限，暂无法操作"
    static let wishlistFull = "心愿单已满"
    static let libraryNotEnabled = "产品库功能暂未开放"
    static let loginRequired = "登录后即可使用"
    static let wishHitPush = "你心愿中的车型上架了"
    static let autoCabinetHint = "将自动入柜"
    static let badgeRetainedHint = "已获勋章保留，完成度可能下降"

    static func completionLabel(owned: Int, total: Int) -> String {
        String(format: completionFormat, owned, total)
    }

    static func badgeProgressLabel(tier: SeriesBadgeTier, current: Int, threshold: Int) -> String {
        "已获\(tier.displayLabel)（当前 \(current)/\(threshold)）"
    }
}

// MARK: - Logic

enum LibraryLogic {
    /// Curve visible only when flag on **and** SKU past sample gate (design §5.1 / §5.2 / §13).
    static func showsCurve(
        libraryCurveEnabled: Bool,
        skuCurveEnabled: Bool,
        sampleN: Int,
        minSamples: Int = LibraryConfigDefaults.curveMinSamples
    ) -> Bool {
        guard libraryCurveEnabled else { return false }
        guard skuCurveEnabled else { return false }
        return sampleN >= minSamples
    }

    /// Flag off → hide curve entirely (Phase 3 placeholder).
    static func curvePlaceholder(
        libraryCurveEnabled: Bool,
        skuCurveEnabled: Bool,
        sampleN: Int,
        minSamples: Int = LibraryConfigDefaults.curveMinSamples
    ) -> LibraryPlaceholderKind? {
        if !libraryCurveEnabled { return .curveHiddenByFlag }
        if showsCurve(
            libraryCurveEnabled: libraryCurveEnabled,
            skuCurveEnabled: skuCurveEnabled,
            sampleN: sampleN,
            minSamples: minSamples
        ) {
            return nil
        }
        return .curveNotReady
    }

    static func entryPlaceholder(for entryKey: String) -> LibraryPlaceholderKind {
        switch entryKey.lowercased() {
        case LibraryConfigDefaults.meEntryLibrary, "product_library", "skus", "产品库":
            return .libraryBuilding
        case LibraryConfigDefaults.meEntryCabinet, "model_cabinet", "virtual_cabinet", "模型柜":
            return .cabinetComingSoon
        case LibraryConfigDefaults.meEntryAtlas, "codex", "collection_atlas", "图鉴":
            return .atlasComingSoon
        default:
            return .libraryBuilding
        }
    }

    static func placeholderTitle(_ kind: LibraryPlaceholderKind) -> String {
        switch kind {
        case .libraryBuilding: return LibraryCopy.libraryBuilding
        case .cabinetComingSoon: return LibraryCopy.cabinetComingSoon
        case .atlasComingSoon: return LibraryCopy.atlasComingSoon
        case .cabinetPrivate: return LibraryCopy.cabinetPrivate
        case .curveNotReady: return LibraryCopy.curveNotReady
        case .curveHiddenByFlag: return LibraryCopy.curveHidden
        case .empty: return LibraryCopy.cabinetEmpty
        }
    }

    static func placeholderHint(_ kind: LibraryPlaceholderKind) -> String {
        switch kind {
        case .libraryBuilding: return LibraryCopy.libraryBuildingHint
        case .cabinetComingSoon: return LibraryCopy.cabinetComingSoonHint
        case .atlasComingSoon: return LibraryCopy.atlasComingSoonHint
        case .cabinetPrivate: return LibraryCopy.cabinetPrivate
        case .curveNotReady: return LibraryCopy.curveNotReady
        case .curveHiddenByFlag: return LibraryCopy.libraryNotEnabled
        case .empty: return LibraryCopy.cabinetComingSoonHint
        }
    }

    /// Copper / silver / gold thresholds (design §5.5). `N=1` → all tiers = 1.
    static func badgeThresholds(
        seriesSkuCount n: Int,
        copperRatio: Double = LibraryConfigDefaults.badgeCopperRatio,
        silverRatio: Double = LibraryConfigDefaults.badgeSilverRatio
    ) -> (copper: Int, silver: Int, gold: Int) {
        guard n > 0 else { return (0, 0, 0) }
        if n == 1 { return (1, 1, 1) }
        let copper = max(1, Int(ceil(Double(n) * copperRatio)))
        let silver = Int(ceil(Double(n) * silverRatio))
        return (copper, silver, n)
    }

    static func tiersCrossed(
        ownedDistinctSkuCount: Int,
        seriesSkuCount: Int
    ) -> [SeriesBadgeTier] {
        let t = badgeThresholds(seriesSkuCount: seriesSkuCount)
        var out: [SeriesBadgeTier] = []
        if ownedDistinctSkuCount >= t.copper { out.append(.copper) }
        if ownedDistinctSkuCount >= t.silver { out.append(.silver) }
        if ownedDistinctSkuCount >= t.gold { out.append(.gold) }
        return out
    }

    /// Guest may browse SKU index / curve (when ready); want / manual cabinet need login (design §5.3 / §5.6).
    static func canBrowseLibrary(isLoggedIn: Bool) -> Bool {
        _ = isLoggedIn
        return true
    }

    static func canWant(
        isLoggedIn: Bool,
        isRealNamed: Bool,
        accountRestricted: Bool
    ) -> LibraryErrorCode? {
        if !isLoggedIn { return .loginRequired }
        if accountRestricted { return .accountRestricted }
        if !isRealNamed { return .realNameRequired }
        return nil
    }

    static func canManualCabinet(
        isLoggedIn: Bool,
        accountRestricted: Bool
    ) -> LibraryErrorCode? {
        if !isLoggedIn { return .loginRequired }
        if accountRestricted { return .accountRestricted }
        return nil
    }

    /// Curve JSON must never carry listing/order ids (design §6 / LIB-02 / HOME-13).
    static let forbiddenCurveKeys: Set<String> = [
        "listing_id", "listingId", "order_id", "orderId",
        "title", "seller", "seller_id", "sellerId", "cover",
    ]

    static func curvePointIsSafe(_ point: SkuCurvePoint) -> Bool {
        // DTO surface has only date + price (+ optional n).
        _ = point
        return true
    }

    /// Valuation UI must always render disclaimer (design §5.8).
    static func mustRenderDisclaimer(code: String?) -> Bool {
        let c = (code ?? LibraryConfigDefaults.disclaimerCodeReferenceOnly).lowercased()
        return c == LibraryConfigDefaults.disclaimerCodeReferenceOnly || c == "reference"
    }

    static func completionOwnedCount(items: [CabinetItem]) -> Int {
        let active = items.filter { $0.resolvedStatus == .in }
        return Set(active.map(\.skuId)).count
    }
}

// MARK: - DTOs

struct ProductSKU: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: Int64
    let skuCode: String?
    let brandId: Int64?
    let seriesId: Int64?
    let modelId: Int64?
    let brandName: String?
    let seriesName: String?
    let modelName: String?
    let scale: String?
    let color: String?
    let edition: String?
    let limitedQty: Int?
    let officialImages: [String]?
    let curveEnabled: Bool?
    let status: String?
    let version: Int?

    init(
        id: Int64,
        skuCode: String? = nil,
        brandId: Int64? = nil,
        seriesId: Int64? = nil,
        modelId: Int64? = nil,
        brandName: String? = nil,
        seriesName: String? = nil,
        modelName: String? = nil,
        scale: String? = LibraryConfigDefaults.firstScale,
        color: String? = nil,
        edition: String? = nil,
        limitedQty: Int? = nil,
        officialImages: [String]? = nil,
        curveEnabled: Bool? = false,
        status: String? = SkuStatus.active.rawValue,
        version: Int? = 1
    ) {
        self.id = id
        self.skuCode = skuCode
        self.brandId = brandId
        self.seriesId = seriesId
        self.modelId = modelId
        self.brandName = brandName
        self.seriesName = seriesName
        self.modelName = modelName
        self.scale = scale
        self.color = color
        self.edition = edition
        self.limitedQty = limitedQty
        self.officialImages = officialImages
        self.curveEnabled = curveEnabled
        self.status = status
        self.version = version
    }

    var resolvedStatus: SkuStatus { SkuStatus.normalize(status) ?? .active }
    var isCurveEnabled: Bool { curveEnabled == true }

    var displayName: String {
        let parts = [brandName, seriesName, modelName, color, edition]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return skuCode ?? "SKU \(id)"
    }
}

struct SkuListResponse: Codable, Equatable, Sendable {
    let items: [ProductSKU]
    let nextCursor: String?
    let total: Int?
    let enabled: Bool?

    init(
        items: [ProductSKU] = [],
        nextCursor: String? = nil,
        total: Int? = nil,
        enabled: Bool? = nil
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.total = total
        self.enabled = enabled
    }

    var isEmptyPlaceholder: Bool { items.isEmpty }
}

/// Curve point — **only** date + price (+ optional n). Never listing_id / order_id (design §6).
struct SkuCurvePoint: Codable, Equatable, Sendable, Hashable {
    let date: String
    let price: Int64
    let n: Int?

    init(date: String, price: Int64, n: Int? = nil) {
        self.date = date
        self.price = price
        self.n = n
    }

    enum CodingKeys: String, CodingKey {
        case date, price, n
        // Intentionally omitted: listing_id, order_id, title, seller
    }
}

struct SkuCurveResponse: Codable, Equatable, Sendable {
    let points: [SkuCurvePoint]
    let sampleN: Int?
    let disclaimer: String?

    init(
        points: [SkuCurvePoint] = [],
        sampleN: Int? = nil,
        disclaimer: String? = nil
    ) {
        self.points = points
        self.sampleN = sampleN
        self.disclaimer = disclaimer
    }

    var resolvedSampleN: Int { sampleN ?? points.count }
}

struct WishlistWriteBody: Equatable, Sendable {
    var kind: WishlistKind
    var maxPrice: Int64?

    init(kind: WishlistKind, maxPrice: Int64? = nil) {
        self.kind = kind
        self.maxPrice = maxPrice
    }

    var body: [String: Any?] {
        var map: [String: Any?] = ["kind": kind.rawValue]
        if let maxPrice { map["max_price"] = maxPrice }
        return map
    }
}

struct CabinetItem: Codable, Equatable, Sendable, Identifiable, Hashable {
    let id: Int64
    let skuId: Int64
    let source: String?
    let status: String?
    let slotNo: Int?
    let acquiredAt: Date?
    let note: String?
    let manualImage: String?
    let sku: ProductSKU?

    init(
        id: Int64,
        skuId: Int64,
        source: String? = CabinetItemSource.orderAuto.rawValue,
        status: String? = CabinetItemStatus.in.rawValue,
        slotNo: Int? = nil,
        acquiredAt: Date? = nil,
        note: String? = nil,
        manualImage: String? = nil,
        sku: ProductSKU? = nil
    ) {
        self.id = id
        self.skuId = skuId
        self.source = source
        self.status = status
        self.slotNo = slotNo
        self.acquiredAt = acquiredAt
        self.note = note
        self.manualImage = manualImage
        self.sku = sku
    }

    var resolvedSource: CabinetItemSource {
        CabinetItemSource.normalize(source) ?? .orderAuto
    }

    var resolvedStatus: CabinetItemStatus {
        CabinetItemStatus.normalize(status) ?? .in
    }

    var isManual: Bool { resolvedSource == .manual }
    var showsManualMark: Bool { isManual }
}

struct CabinetWallResponse: Codable, Equatable, Sendable {
    let items: [CabinetItem]
    let total: Int?
    let publicVisible: Bool?
    let nextCursor: String?

    init(
        items: [CabinetItem] = [],
        total: Int? = nil,
        publicVisible: Bool? = true,
        nextCursor: String? = nil
    ) {
        self.items = items
        self.total = total
        self.publicVisible = publicVisible
        self.nextCursor = nextCursor
    }
}

struct SeriesBadge: Codable, Equatable, Sendable, Identifiable, Hashable {
    let badgeId: Int64?
    let seriesId: Int64
    let seriesName: String?
    let tier: String
    let awardedAt: Date?
    let triggerCount: Int?

    init(
        badgeId: Int64? = nil,
        seriesId: Int64,
        seriesName: String? = nil,
        tier: String,
        awardedAt: Date? = nil,
        triggerCount: Int? = nil
    ) {
        self.badgeId = badgeId
        self.seriesId = seriesId
        self.seriesName = seriesName
        self.tier = tier
        self.awardedAt = awardedAt
        self.triggerCount = triggerCount
    }

    var resolvedTier: SeriesBadgeTier {
        SeriesBadgeTier.normalize(tier) ?? .copper
    }

    /// Stable id for lists when server omits id.
    var id: String { "\(seriesId)-\(tier)" }

    enum CodingKeys: String, CodingKey {
        case badgeId = "id"
        case seriesId, seriesName, tier, awardedAt, triggerCount
    }
}

struct SeriesCompletion: Codable, Equatable, Sendable, Hashable {
    let seriesId: Int64
    let seriesName: String?
    let owned: Int
    let total: Int

    init(seriesId: Int64, seriesName: String? = nil, owned: Int, total: Int) {
        self.seriesId = seriesId
        self.seriesName = seriesName
        self.owned = owned
        self.total = total
    }

    var label: String { LibraryCopy.completionLabel(owned: owned, total: total) }
}

struct CabinetSummaryResponse: Codable, Equatable, Sendable {
    let completion: [SeriesCompletion]
    let valueFen: Int64?
    let valueStatus: String?
    let disclaimer: String?
    let disclaimerCode: String?
    let badges: [SeriesBadge]?

    init(
        completion: [SeriesCompletion] = [],
        valueFen: Int64? = nil,
        valueStatus: String? = nil,
        disclaimer: String? = LibraryConfigDefaults.disclaimerText,
        disclaimerCode: String? = LibraryConfigDefaults.disclaimerCodeReferenceOnly,
        badges: [SeriesBadge]? = nil
    ) {
        self.completion = completion
        self.valueFen = valueFen
        self.valueStatus = valueStatus
        self.disclaimer = disclaimer
        self.disclaimerCode = disclaimerCode
        self.badges = badges
    }

    var resolvedValueStatus: ValuationStatus {
        ValuationStatus.normalize(valueStatus)
    }

    var displayDisclaimer: String {
        if let disclaimer, !disclaimer.isEmpty { return disclaimer }
        return LibraryCopy.valuationDisclaimer
    }

    var showsDisclaimer: Bool {
        LibraryLogic.mustRenderDisclaimer(code: disclaimerCode)
    }
}

struct ManualCabinetBody: Equatable, Sendable {
    var skuId: Int64
    var note: String?
    var slotNo: Int?

    init(skuId: Int64, note: String? = nil, slotNo: Int? = nil) {
        self.skuId = skuId
        self.note = note
        self.slotNo = slotNo
    }

    var body: [String: Any?] {
        var map: [String: Any?] = [
            "sku_id": skuId,
            "source": CabinetItemSource.manual.rawValue,
        ]
        if let note, !note.isEmpty { map["note"] = note }
        if let slotNo { map["slot_no"] = slotNo }
        return map
    }
}
