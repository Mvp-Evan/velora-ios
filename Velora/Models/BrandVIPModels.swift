import Foundation

// MARK: - Brand VIP (DES-v1.3-05-04 VIP-01/02/03 / D22 — app mirror of VeloraCore)
// Buyer-facing loyalty for a single brand store. Not platform paid membership.

/// Product defaults (design §15). Hot-config on server; client mirrors for UX / validation.
enum BrandVIPConfigDefaults {
    static let maxLevels = 6
    static let allowForceDown = false
    static let timezoneID = "Asia/Shanghai"
    static let recalcCron = "03:30"
    static let importMaxRows = 5_000
    static let basisChangeMinIntervalHours = 24
    static let lotteryWeightDefault = 1.0
    static let lotteryWeightMax = 2.0
    static let levelNameMaxLen = 6
    static let adjustReasonMinLen = 5
    static let viewerCacheSeconds = 60
    static let launchGateKey = "feature_flags.brand_vip"
    static let exampleThresholdsFen: [Int64] = [0, 500_000, 2_000_000]
    static let exampleLevelNames = ["银", "金", "钻"]
}

// MARK: - Spend basis / source

/// `vip_rule.basis` (design §3 / VIP-01).
enum BrandVIPSpendBasis: String, Codable, Sendable, CaseIterable, Equatable {
    case allTime = "all_time"
    case calendarYear = "calendar_year"
    case rolling12m = "rolling_12m"

    /// Short UX chips (design §9): 累计 / 本年度 / 近 12 个月.
    var shortLabel: String {
        switch self {
        case .allTime: return "累计"
        case .calendarYear: return "本年度"
        case .rolling12m: return "近 12 个月"
        }
    }

    /// Spend phrase embedded in the store strip (design §5.4 / §9).
    var spendPhrase: String {
        switch self {
        case .allTime: return "累计消费"
        case .calendarYear: return "本年度消费"
        case .rolling12m: return "近 12 个月消费"
        }
    }

    /// Fallback when basis is unknown (legacy strip copy).
    static let fallbackSpendPhrase = "本周期消费"
}

/// `vip_member.source` (design §3 / §5.5).
enum BrandVIPMemberSource: String, Codable, Sendable, CaseIterable, Equatable {
    case computed
    case manual
    case importSource = "import"
    case mixed

    var displayLabel: String {
        switch self {
        case .computed: return "消费计算"
        case .manual: return "手工调级"
        case .importSource: return "导入"
        case .mixed: return "取高混合"
        }
    }
}

// MARK: - Level / perks / rule snapshots (client-side helpers)

/// One row inside `vip_rule.levels_json` (design §3).
struct BrandVIPLevelDef: Codable, Equatable, Sendable, Identifiable, Hashable {
    let level: Int
    let name: String
    let minAmount: Int64
    let perks: BrandVIPPerks?

    var id: Int { level }

    init(level: Int, name: String, minAmount: Int64, perks: BrandVIPPerks? = nil) {
        self.level = level
        self.name = name
        self.minAmount = minAmount
        self.perks = perks
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Lv.\(level)" : trimmed
    }
}

/// Perk bag on a level (design §5.3 / §5.11). Unknown keys ignored by decoder.
struct BrandVIPPerks: Codable, Equatable, Sendable, Hashable {
    let lotteryEligible: Bool?
    let lotteryWeight: Double?
    let presaleWindowMinutes: Int?
    let exclusiveRelease: Bool?

    init(
        lotteryEligible: Bool? = nil,
        lotteryWeight: Double? = nil,
        presaleWindowMinutes: Int? = nil,
        exclusiveRelease: Bool? = nil
    ) {
        self.lotteryEligible = lotteryEligible
        self.lotteryWeight = lotteryWeight
        self.presaleWindowMinutes = presaleWindowMinutes
        self.exclusiveRelease = exclusiveRelease
    }

    var resolvedLotteryWeight: Double {
        let w = lotteryWeight ?? BrandVIPConfigDefaults.lotteryWeightDefault
        return min(max(w, BrandVIPConfigDefaults.lotteryWeightDefault), BrandVIPConfigDefaults.lotteryWeightMax)
    }
}

/// Distance / gap to the next configured level (design §9).
struct BrandVIPDistance: Equatable, Sendable {
    let nextLevel: Int
    let nextName: String?
    let nextMinAmountFen: Int64
    let remainingFen: Int64

    init(nextLevel: Int, nextName: String?, nextMinAmountFen: Int64, remainingFen: Int64) {
        self.nextLevel = nextLevel
        self.nextName = nextName
        self.nextMinAmountFen = nextMinAmountFen
        self.remainingFen = remainingFen
    }

    var isMaxLevel: Bool { remainingFen <= 0 && nextLevel <= 0 }

    var progressCopy: String {
        guard remainingFen > 0, nextLevel > 0 else { return BrandVIPCopy.atMaxLevel }
        let yuan = BrandVIPLogic.formatYuan(remainingFen)
        let name = (nextName?.isEmpty == false) ? " \(nextName!)" : ""
        return "再消费 ¥\(yuan) 升至 Lv.\(nextLevel)\(name)"
    }
}

// MARK: - Pure logic (design §3 / §5.5 / §9)

enum BrandVIPLogic {
    /// `effective_level = max(computed_level, override_level)`; nil treated as 0 (design §3).
    static func effectiveLevel(computed: Int?, override: Int?) -> Int {
        max(computed ?? 0, override ?? 0)
    }

    /// Source labelling after take-high (design §5.5 table).
    static func resolveSource(
        computed: Int?,
        override: Int?,
        overrideOrigin: BrandVIPMemberSource? = nil
    ) -> BrandVIPMemberSource {
        let c = computed ?? 0
        let o = override ?? 0
        if o <= 0 { return .computed }
        if c <= 0 {
            return overrideOrigin == .importSource ? .importSource : .manual
        }
        if c == o { return .mixed }
        return .mixed
    }

    /// Map spend fen → highest level whose `min_amount <= spend` (design §5.2).
    static func computedLevel(spendFen: Int64, levels: [BrandVIPLevelDef]) -> Int {
        let sorted = levels.sorted { $0.level < $1.level }
        var best = 0
        for row in sorted where row.minAmount <= spendFen {
            best = row.level
        }
        return best
    }

    /// Gap to the next level above `effective` (design §9). `nil` when already at top.
    static func distanceToNextLevel(
        spendFen: Int64,
        effectiveLevel: Int,
        levels: [BrandVIPLevelDef]
    ) -> BrandVIPDistance? {
        let sorted = levels.sorted { $0.level < $1.level }
        guard let next = sorted.first(where: { $0.level > effectiveLevel }) else { return nil }
        let remaining = max(0, next.minAmount - spendFen)
        return BrandVIPDistance(
            nextLevel: next.level,
            nextName: next.name,
            nextMinAmountFen: next.minAmount,
            remainingFen: remaining
        )
    }

    /// Validate merchant level rows (design §5.1): 1…N continuous, N≤6, strict min_amount↑, name ≤6.
    static func validateLevels(_ levels: [BrandVIPLevelDef]) -> BrandVIPErrorCode? {
        guard !levels.isEmpty else { return .vipRuleLevelsNotMonotonic }
        guard levels.count <= BrandVIPConfigDefaults.maxLevels else { return .levelInvalid }
        let sorted = levels.sorted { $0.level < $1.level }
        for (idx, row) in sorted.enumerated() {
            if row.level != idx + 1 { return .vipRuleLevelsNotMonotonic }
            if row.minAmount < 0 { return .vipRuleLevelsNotMonotonic }
            if idx > 0, row.minAmount <= sorted[idx - 1].minAmount {
                return .vipRuleLevelsNotMonotonic
            }
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.count > BrandVIPConfigDefaults.levelNameMaxLen { return .levelInvalid }
        }
        return nil
    }

    static func validateAdjustReason(_ reason: String) -> BrandVIPErrorCode? {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= BrandVIPConfigDefaults.adjustReasonMinLen ? nil : .reasonRequired
    }

    /// Preview effective after a proposed override (design §9 / take-high confirm).
    static func previewEffectiveAfterAdjust(computed: Int?, proposedOverride: Int) -> Int {
        effectiveLevel(computed: computed, override: proposedOverride)
    }

    static func formatYuan(_ fen: Int64) -> String {
        let yuan = Double(fen) / 100.0
        if fen % 100 == 0 {
            return String(format: "%.0f", yuan)
        }
        return String(format: "%.2f", yuan)
    }

    /// Three-level starter template (design §9 / §15).
    static func exampleTemplateLevels() -> [BrandVIPLevelDef] {
        zip(BrandVIPConfigDefaults.exampleThresholdsFen, BrandVIPConfigDefaults.exampleLevelNames)
            .enumerated()
            .map { idx, pair in
                BrandVIPLevelDef(level: idx + 1, name: pair.1, minAmount: pair.0)
            }
    }
}

// MARK: - Strip presentation

/// How the brand-store VIP strip should render (design §5.4 / §5.6 / brand-store §5.8).
enum BrandVIPStripMode: String, Sendable, Equatable {
    /// Guest, or VIP rules not configured — hide strip entirely.
    case hidden
    /// Logged-in non-member of this store — CTA, never a paywall.
    case nonMemberCTA
    /// Member with effective level ≥ 1.
    case member
}

/// Optional VIP strip / `viewer_vip` on store aggregate + `GET …/me/vip` (design §5.4 / §6).
struct BrandViewerVIP: Codable, Equatable, Sendable {
    /// Prefer `effectiveLevel`; `level` kept for aggregate stubs.
    let level: Int?
    let effectiveLevel: Int?
    let levelName: String?
    let spendFen: Int64?
    let basis: BrandVIPSpendBasis?
    let periodLabel: String?
    let computedLevel: Int?
    let overrideLevel: Int?
    let source: BrandVIPMemberSource?
    let isMember: Bool?
    let rulesConfigured: Bool?
    let nextLevel: Int?
    let nextLevelName: String?
    let nextMinAmountFen: Int64?
    let distanceFen: Int64?
    let computedAt: Date?

    init(
        level: Int? = nil,
        effectiveLevel: Int? = nil,
        levelName: String? = nil,
        spendFen: Int64? = nil,
        basis: BrandVIPSpendBasis? = nil,
        periodLabel: String? = nil,
        computedLevel: Int? = nil,
        overrideLevel: Int? = nil,
        source: BrandVIPMemberSource? = nil,
        isMember: Bool? = nil,
        rulesConfigured: Bool? = nil,
        nextLevel: Int? = nil,
        nextLevelName: String? = nil,
        nextMinAmountFen: Int64? = nil,
        distanceFen: Int64? = nil,
        computedAt: Date? = nil
    ) {
        self.level = level
        self.effectiveLevel = effectiveLevel
        self.levelName = levelName
        self.spendFen = spendFen
        self.basis = basis
        self.periodLabel = periodLabel
        self.computedLevel = computedLevel
        self.overrideLevel = overrideLevel
        self.source = source
        self.isMember = isMember
        self.rulesConfigured = rulesConfigured
        self.nextLevel = nextLevel
        self.nextLevelName = nextLevelName
        self.nextMinAmountFen = nextMinAmountFen
        self.distanceFen = distanceFen
        self.computedAt = computedAt
    }

    /// Resolved take-high level for display (design §3).
    var resolvedEffectiveLevel: Int {
        if let e = effectiveLevel { return e }
        if let l = level { return l }
        return BrandVIPLogic.effectiveLevel(computed: computedLevel, override: overrideLevel)
    }

    var resolvedIsMember: Bool {
        if let m = isMember { return m }
        return resolvedEffectiveLevel > 0
    }

    var resolvedRulesConfigured: Bool {
        if let r = rulesConfigured { return r }
        // Presence of any level / name / member flag implies rules exist on the aggregate.
        return level != nil || effectiveLevel != nil || (levelName?.isEmpty == false) || isMember != nil
    }

    var stripMode: BrandVIPStripMode {
        guard resolvedRulesConfigured else { return .hidden }
        return resolvedIsMember ? .member : .nonMemberCTA
    }

    /// Hide strip when VIP rules not configured (design brand-store §5.8).
    var shouldDisplay: Bool { stripMode != .hidden }

    var spendPhrase: String {
        if let custom = periodLabel, !custom.isEmpty { return custom }
        return basis?.spendPhrase ?? BrandVIPSpendBasis.fallbackSpendPhrase
    }

    /// Member line: `Lv.x 名称 · 本年度消费 ¥…` (design §5.4 / §9).
    var displayLine: String {
        let lv = resolvedEffectiveLevel
        let name = (levelName?.isEmpty == false) ? " \(levelName!)" : ""
        var line = "Lv.\(lv)\(name)"
        if let fen = spendFen {
            line += " · \(spendPhrase) ¥\(BrandVIPLogic.formatYuan(fen))"
        }
        return line
    }

    var stripPrimaryText: String {
        switch stripMode {
        case .hidden: return ""
        case .nonMemberCTA: return BrandVIPCopy.nonMemberCTA
        case .member: return displayLine
        }
    }

    var distance: BrandVIPDistance? {
        guard let next = nextLevel, next > 0 else { return nil }
        let remaining = distanceFen ?? {
            guard let min = nextMinAmountFen, let spend = spendFen else { return nil as Int64? }
            return max(0, min - spend)
        }()
        guard let remaining else { return nil }
        return BrandVIPDistance(
            nextLevel: next,
            nextName: nextLevelName,
            nextMinAmountFen: nextMinAmountFen ?? 0,
            remainingFen: remaining
        )
    }
}

/// `GET /api/v1/brands/{id}/me/vip` payload (design §6). Same shape as enriched `viewer_vip`.
typealias BrandBuyerVIP = BrandViewerVIP

// MARK: - Error codes / copy

enum BrandVIPErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case reasonRequired = "reason_required"
    case levelInvalid = "level_invalid"
    case capabilityDisabled = "capability_disabled"
    case notBrandSeller = "not_brand_seller"
    case basisChangeTooFrequent = "basis_change_too_frequent"
    case vipRuleLevelsNotMonotonic = "vip_rule_levels_not_monotonic"
    case vipImportTooLarge = "vip_import_too_large"
    case vipMemberNotFound = "vip_member_not_found"
    case unauthorized
    case loginRequired = "login_required"

    var opensLogin: Bool {
        self == .unauthorized || self == .loginRequired
    }

    var fallbackMessage: String {
        switch self {
        case .reasonRequired: return "请填写调级原因"
        case .levelInvalid: return "等级无效"
        case .capabilityDisabled: return "未开通品牌会员能力"
        case .notBrandSeller: return "仅品牌商家可配置会员"
        case .basisChangeTooFrequent: return "消费口径改动过于频繁，请稍后再试"
        case .vipRuleLevelsNotMonotonic: return "等级门槛须连续递增"
        case .vipImportTooLarge: return "导入文件过大或行数超限"
        case .vipMemberNotFound: return "未找到该会员"
        case .unauthorized, .loginRequired: return "请先登录"
        }
    }
}

enum BrandVIPCopy {
    static let nonMemberCTA = "下单即可成为会员"
    static let atMaxLevel = "已达最高等级"
    static let stripAccessibilityMember = "品牌会员等级"
    static let stripAccessibilityCTA = "下单即可成为本店会员"
    /// Hard ban: never show platform paid VIP paywall (design §5.6 / §8).
    static let forbiddenPlatformPaywallPhrases: [String] = [
        "开通平台 VIP",
        "开通平台VIP",
        "购买 SVIP",
        "购买SVIP",
        "开通会员支付",
        "/vip/subscribe",
    ]
}
