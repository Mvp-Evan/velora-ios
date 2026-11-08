import Foundation

// MARK: - IM sensitive lexicon + image diversion (DES-v1.3-10-01 RISK-01/02/03 / D35)

/// Product defaults (design §3). Hot-config on server; client mirrors for UX + gates.
public enum IMRiskConfigDefaults {
    public static let interceptWindowDays = 7
    public static let interceptThreshold = 3
    public static let muteHours = 72
    public static let pureAmountRegex = #"^[¥￥]?\d{1,8}([.．]\d{1,2})?[元块]?$"#
    public static let imageScanEnabledKey = "risk.image_scan.enabled"
    public static let imageScanEnabledDefault = false
    public static let imEnabledKey = "risk.im.enabled"
    public static let remuteRequiresNewWindowKey = "risk.im.remute_requires_new_window"
    public static let remuteRequiresNewWindowDefault = true
    public static let warnBannerDedupeMinutes = 10
    public static let maxFilterChars = 2_000
    public static let notifyCode = "N-24"
    public static let creditReasonMute = "im_sensitive_mute"
    public static let creditDeltaMute = -5
    public static let riskQueueReasonLexicon = "lexicon_block"
    /// Structured card types that skip the text lexicon (design §5.3 / §5.7 / T-07).
    public static let whitelistMessageTypes: Set<String> = [
        "offer",
        "offer_card",
        "listing_card",
        "order_card",
        "lot_card",
    ]
}

// MARK: - Filter decision / action / category

/// Sync filter outcome (design §4).
public enum RiskFilterDecision: String, Codable, Sendable, CaseIterable, Equatable {
    case allow
    case allowWithWarn = "allow_with_warn"
    case drop

    public static func normalize(_ raw: String?) -> RiskFilterDecision? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = RiskFilterDecision(rawValue: s) { return exact }
        switch s {
        case "allow-with-warn", "warn_allow", "pass_with_warn":
            return .allowWithWarn
        case "block", "blocked", "reject":
            return .drop
        case "pass", "ok":
            return .allow
        default:
            return nil
        }
    }
}

/// Message / hit `risk_action` (design §5.2 / §6).
public enum RiskAction: String, Codable, Sendable, CaseIterable, Equatable {
    case none
    case log
    case warn
    case block

    public static func normalize(_ raw: String?) -> RiskAction? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = RiskAction(rawValue: s) { return exact }
        switch s {
        case "blocked", "drop", "intercept":
            return .block
        case "warning", "tip", "hint", "allow_with_warn":
            // DES-v1.3-11-02 `risk_level=hint` maps to warn strip (N-24).
            return .warn
        case "record", "logged":
            return .log
        case "ok", "pass", "allowed", "none":
            return RiskAction.none
        default:
            return nil
        }
    }

    /// Severity for multi-hit merge: `block > warn > log > none`.
    public var severity: Int {
        switch self {
        case .block: return 3
        case .warn: return 2
        case .log: return 1
        case .none: return 0
        }
    }

    public static func stricter(_ a: RiskAction, _ b: RiskAction) -> RiskAction {
        a.severity >= b.severity ? a : b
    }

    public var filterDecision: RiskFilterDecision {
        switch self {
        case .block: return .drop
        case .warn: return .allowWithWarn
        case .log, .none: return .allow
        }
    }

    public var showsSenderInterceptBanner: Bool { self == .block }
    public var showsWarnBanner: Bool { self == .warn }
    public var showsUI: Bool { self == .block || self == .warn }
}

/// Lexicon / hit category (design §3 / §5.2).
public enum RiskCategory: String, Codable, Sendable, CaseIterable, Equatable {
    case inducePay = "induce_pay"
    case contact
    case abuse
    case amountOnly = "amount_only"

    public static func normalize(_ raw: String?) -> RiskCategory? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = RiskCategory(rawValue: s) { return exact }
        switch s {
        case "induce", "induce-pay", "offline_pay", "payment_induce":
            return .inducePay
        case "contact_info", "phone", "wechat":
            return .contact
        case "insult", "swear", "profanity":
            return .abuse
        case "amount", "pure_amount", "amount-only":
            return .amountOnly
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .inducePay: return "诱导支付"
        case .contact: return "联系方式"
        case .abuse: return "辱骂"
        case .amountOnly: return "纯金额"
        }
    }
}

// MARK: - Mute state (RISK-02)

/// Client mute lifecycle (design §4): `none → muted → expired`.
public enum IMMuteState: String, Codable, Sendable, CaseIterable, Equatable {
    case none
    case muted
    case expired

    public var canSendIM: Bool { self != .muted }
    public var composerDisabled: Bool { self == .muted }

    public static func normalize(_ raw: String?) -> IMMuteState? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = IMMuteState(rawValue: s) { return exact }
        switch s {
        case "active", "banned", "im_muted", "mute":
            return .muted
        case "cleared", "lifted", "done":
            return .expired
        case "ok", "clear", "inactive":
            return IMMuteState.none
        default:
            return nil
        }
    }
}

/// `user_im_mutes` projection for composer (design §3 / §5.5).
public struct UserIMMute: Codable, Equatable, Sendable {
    public let until: Date?
    public let source: String?
    public let windowHitCount: Int?

    public init(until: Date? = nil, source: String? = nil, windowHitCount: Int? = nil) {
        self.until = until
        self.source = source
        self.windowHitCount = windowHitCount
    }

    public func state(now: Date = Date()) -> IMMuteState {
        IMRiskLogic.muteState(until: until, now: now)
    }
}

// MARK: - Error codes (design §5.11)

public enum IMRiskErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case contentBlocked = "content_blocked"
    case imMuted = "im_muted"
    case blockedByUser = "blocked_by_user"
    case contentReviewPending = "content_review_pending"
    case lexiconRegexInvalid = "lexicon_regex_invalid"
    case featureDisabled = "feature_disabled"

    public static func normalize(_ raw: String?) -> IMRiskErrorCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = IMRiskErrorCode(rawValue: s) { return exact }
        switch s {
        case "blocked", "message_blocked", "risk_blocked", "lexicon_block":
            return .contentBlocked
        case "muted", "im_mute", "mute_active", "user_im_muted":
            return .imMuted
        case "blocked_by_peer", "user_blocked", "peer_blocked":
            return .blockedByUser
        case "review_pending", "filter_timeout_question":
            return .contentReviewPending
        case "regex_invalid", "lexicon_invalid":
            return .lexiconRegexInvalid
        case "image_scan_disabled", "risk_image_scan_disabled":
            return .featureDisabled
        default:
            return nil
        }
    }

    public var fallbackMessage: String {
        switch self {
        case .contentBlocked: return IMRiskCopy.blockedNotice
        case .imMuted: return IMRiskCopy.mutedGeneric
        case .blockedByUser: return IMRiskCopy.blockedByUser
        case .contentReviewPending: return IMRiskCopy.contentReviewPending
        case .lexiconRegexInvalid: return IMRiskCopy.lexiconRegexInvalid
        case .featureDisabled: return IMRiskCopy.imageScanFeatureDisabled
        }
    }

    /// Keep draft / do not clear composer on these failures (design §5.12 / §9).
    public var preservesDraft: Bool {
        switch self {
        case .contentBlocked, .imMuted, .contentReviewPending, .featureDisabled:
            return true
        case .blockedByUser, .lexiconRegexInvalid:
            return true
        }
    }

    public var showsInterceptBanner: Bool { self == .contentBlocked }
    public var showsMuteComposer: Bool { self == .imMuted }
}

// MARK: - Risk envelope on send (design §6)

/// `risk: { action, notice?, category? }` on message send response.
public struct MessageRiskInfo: Codable, Equatable, Hashable, Sendable {
    public let action: RiskAction
    public let notice: String?
    public let category: RiskCategory?

    public init(action: RiskAction, notice: String? = nil, category: RiskCategory? = nil) {
        self.action = action
        self.notice = notice
        self.category = category
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .action)
        action = RiskAction.normalize(raw) ?? .none
        notice = try c.decodeIfPresent(String.self, forKey: .notice)
            ?? c.decodeIfPresent(String.self, forKey: .message)
        let catRaw = try c.decodeIfPresent(String.self, forKey: .category)
        category = RiskCategory.normalize(catRaw)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(action.rawValue, forKey: .action)
        try c.encodeIfPresent(notice, forKey: .notice)
        try c.encodeIfPresent(category?.rawValue, forKey: .category)
    }

    private enum CodingKeys: String, CodingKey {
        case action, notice, message, category
    }

    public var displayNotice: String {
        if let notice, !notice.isEmpty { return notice }
        switch action {
        case .block: return IMRiskCopy.blockedNotice
        case .warn: return IMRiskCopy.warnBanner
        case .log, .none: return ""
        }
    }
}

/// Image-scan short path when flag off (design §5.6) — Phase 3 placeholder.
public enum RiskImageScanStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case skipped
    case pending
    case done
    case failed

    public static func normalize(_ raw: String?) -> RiskImageScanStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = RiskImageScanStatus(rawValue: s) { return exact }
        switch s {
        case "skip", "disabled", "feature_disabled":
            return .skipped
        case "processing", "queued":
            return .pending
        case "complete", "completed", "ok":
            return .done
        case "error", "timeout":
            return .failed
        default:
            return nil
        }
    }
}

public struct RiskImageScanResult: Codable, Equatable, Sendable {
    public let status: RiskImageScanStatus
    public let action: RiskAction?
    public let errorCode: String?

    public init(status: RiskImageScanStatus, action: RiskAction? = nil, errorCode: String? = nil) {
        self.status = status
        self.action = action
        self.errorCode = errorCode
    }

    public var isFeatureDisabledPlaceholder: Bool {
        status == .skipped || errorCode == IMRiskErrorCode.featureDisabled.rawValue
    }
}

// MARK: - Copy (N-24 / T-07 / §5.12 / §9)

public enum IMRiskCopy {
    public static let blockedNotice = "该内容疑似诱导站外交易，未发送"
    public static let blockedCTA = "请使用报价卡片议价"
    public static let blockedImageNotice = "图片含站外联系方式"
    public static let warnBanner = "请勿站外交易，平台无法保护"
    public static let mutedGeneric = "私聊已被禁言"
    public static let mutedContactSupport = "如有疑问联系客服"
    public static let blockedByUser = "对方已将你拉黑，无法发送私信"
    public static let contentReviewPending = "内容审核中，请稍后再试"
    public static let lexiconRegexInvalid = "词库配置无效"
    public static let imageScanFeatureDisabled = "图片引流识别暂未开放"
    public static let accessibilityRiskLabel = "风险提示"
    public static let offerWhitelistHint = "议价请使用报价卡片，卡片内容不经敏感词拦截"
    public static let offerWhitelistSkipNote = "报价卡片已白名单，跳过词库"
    public static let pureAmountHint = "纯金额文本可发送；涉及联系方式将被拦截"
    public static let answerHidden = "回答含违规信息已隐藏"
    public static let learnProtection = "了解平台交易保护"
    public static let serverTimeHint = "以服务器时间为准"

    public static func mutedUntilPlaceholder(_ untilText: String) -> String {
        "禁言至 \(untilText)"
    }

    public static func mutedBanner(untilText: String) -> String {
        "\(mutedUntilPlaceholder(untilText)) · \(mutedContactSupport)"
    }

    /// Intercept strip: N-24 + actionable CTA (design §9).
    public static var blockedBannerFull: String {
        "\(blockedNotice)。\(blockedCTA)"
    }
}

// MARK: - Banner / composer presentation

public enum IMRiskBannerKind: String, Sendable, Equatable {
    case intercept
    case warn
    case mute
}

public struct IMRiskBanner: Equatable, Sendable, Identifiable {
    public let kind: IMRiskBannerKind
    public let text: String
    public let category: RiskCategory?
    public let showsOfferCTA: Bool

    public var id: String {
        "\(kind.rawValue)-\(category?.rawValue ?? "none")-\(text)"
    }

    public var accessibilityLabel: String { IMRiskCopy.accessibilityRiskLabel }

    public init(
        kind: IMRiskBannerKind,
        text: String,
        category: RiskCategory? = nil,
        showsOfferCTA: Bool = false
    ) {
        self.kind = kind
        self.text = text
        self.category = category
        self.showsOfferCTA = showsOfferCTA
    }
}

public struct IMComposerState: Equatable, Sendable {
    public let mute: IMMuteState
    public let until: Date?
    public let placeholder: String
    public let isEnabled: Bool

    public init(mute: IMMuteState, until: Date?, placeholder: String, isEnabled: Bool) {
        self.mute = mute
        self.until = until
        self.placeholder = placeholder
        self.isEnabled = isEnabled
    }
}

// MARK: - Logic

public enum IMRiskLogic {
    /// T-07 / §5.3 / §5.7 — structured cards skip lexicon.
    public static func isWhitelistMessageType(_ type: String?) -> Bool {
        guard let type, !type.isEmpty else { return false }
        return IMRiskConfigDefaults.whitelistMessageTypes.contains(type.lowercased())
    }

    public static func shouldSkipLexicon(messageType: String?) -> Bool {
        isWhitelistMessageType(messageType)
    }

    public static func muteState(until: Date?, now: Date = Date()) -> IMMuteState {
        guard let until else { return IMMuteState.none }
        if until > now { return .muted }
        return .expired
    }

    public static func composerState(
        muteUntil: Date?,
        serverNow: Date? = nil,
        localNow: Date = Date(),
        defaultPlaceholder: String = "说点什么…"
    ) -> IMComposerState {
        let now = serverNow ?? localNow
        let state = muteState(until: muteUntil, now: now)
        switch state {
        case .muted:
            let untilText = formatMuteUntil(muteUntil!, serverNow: serverNow, localNow: localNow)
            return IMComposerState(
                mute: .muted,
                until: muteUntil,
                placeholder: IMRiskCopy.mutedUntilPlaceholder(untilText),
                isEnabled: false
            )
        case .none, .expired:
            return IMComposerState(
                mute: state == .expired ? .expired : .none,
                until: muteUntil,
                placeholder: defaultPlaceholder,
                isEnabled: true
            )
        }
    }

    /// Localize `until` using server_time skew when available (design §5.12).
    public static func formatMuteUntil(
        _ until: Date,
        serverNow: Date? = nil,
        localNow: Date = Date(),
        locale: Locale = Locale(identifier: "zh_CN")
    ) -> String {
        let fmt = DateFormatter()
        fmt.locale = locale
        fmt.timeZone = TimeZone.current
        let calendar = Calendar.current
        let ref = serverNow ?? localNow
        if calendar.isDate(until, inSameDayAs: ref) {
            fmt.dateFormat = "HH:mm"
            return "今天 \(fmt.string(from: until))"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: ref),
           calendar.isDate(until, inSameDayAs: tomorrow) {
            fmt.dateFormat = "HH:mm"
            return "明天 \(fmt.string(from: until))"
        }
        fmt.dateFormat = "M月d日 HH:mm"
        return fmt.string(from: until)
    }

    /// Same conversation: one warn strip per category within 10 minutes (design §5.12).
    public static func shouldShowWarnBanner(
        category: RiskCategory?,
        lastShownCategory: RiskCategory?,
        lastShownAt: Date?,
        now: Date = Date(),
        dedupeMinutes: Int = IMRiskConfigDefaults.warnBannerDedupeMinutes
    ) -> Bool {
        guard let lastShownAt else { return true }
        let window = TimeInterval(dedupeMinutes * 60)
        if now.timeIntervalSince(lastShownAt) >= window { return true }
        return lastShownCategory != category
    }

    public static func interceptBanner(notice: String? = nil) -> IMRiskBanner {
        let text: String
        if let notice, !notice.isEmpty {
            text = notice.contains(IMRiskCopy.blockedCTA) ? notice : "\(notice)。\(IMRiskCopy.blockedCTA)"
        } else {
            text = IMRiskCopy.blockedBannerFull
        }
        return IMRiskBanner(kind: .intercept, text: text, showsOfferCTA: true)
    }

    public static func warnBanner(
        notice: String? = nil,
        category: RiskCategory? = nil
    ) -> IMRiskBanner {
        let text = (notice?.isEmpty == false) ? notice! : IMRiskCopy.warnBanner
        return IMRiskBanner(kind: .warn, text: text, category: category, showsOfferCTA: false)
    }

    public static func muteBanner(until: Date, serverNow: Date? = nil, localNow: Date = Date()) -> IMRiskBanner {
        let untilText = formatMuteUntil(until, serverNow: serverNow, localNow: localNow)
        return IMRiskBanner(kind: .mute, text: IMRiskCopy.mutedBanner(untilText: untilText))
    }

    public static func banner(for risk: MessageRiskInfo) -> IMRiskBanner? {
        switch risk.action {
        case .block:
            return interceptBanner(notice: risk.notice)
        case .warn:
            return warnBanner(notice: risk.notice, category: risk.category)
        case .log, .none:
            return nil
        }
    }

    public static func banner(forErrorCode code: IMRiskErrorCode, notice: String? = nil, muteUntil: Date? = nil, serverNow: Date? = nil) -> IMRiskBanner? {
        switch code {
        case .contentBlocked:
            return interceptBanner(notice: notice)
        case .imMuted:
            if let muteUntil {
                return muteBanner(until: muteUntil, serverNow: serverNow)
            }
            return IMRiskBanner(kind: .mute, text: IMRiskCopy.mutedGeneric)
        default:
            return nil
        }
    }

    /// Client-side pure-amount UX hint only — never blocks send (design §5.3 / §5.12).
    public static func looksLikePureAmount(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        guard t.count <= 32 else { return false }
        return t.range(of: IMRiskConfigDefaults.pureAmountRegex, options: .regularExpression) != nil
    }

    public static func offerWhitelistCopy(messageType: String?) -> String? {
        guard shouldSkipLexicon(messageType: messageType) else { return nil }
        return IMRiskCopy.offerWhitelistHint
    }

    /// Phase 3 stub: flag off → skipped / feature_disabled (design §5.6).
    public static func imageScanPlaceholder(
        enabled: Bool = IMRiskConfigDefaults.imageScanEnabledDefault
    ) -> RiskImageScanResult {
        if enabled {
            return RiskImageScanResult(status: .pending)
        }
        return RiskImageScanResult(
            status: .skipped,
            action: RiskAction.none,
            errorCode: IMRiskErrorCode.featureDisabled.rawValue
        )
    }

    public static func truncateForFilter(_ text: String, maxChars: Int = IMRiskConfigDefaults.maxFilterChars) -> String {
        if text.count <= maxChars { return text }
        let idx = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<idx])
    }

    /// Parse optional `mute_until` from API error message / details ISO8601 or epoch ms.
    public static func parseMuteUntil(from message: String?) -> Date? {
        guard let message, !message.isEmpty else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        // Prefer embedded ISO date.
        let pattern = #"20\d{2}-\d{2}-\d{2}T[0-9:.+-]+Z?"#
        if let range = message.range(of: pattern, options: .regularExpression) {
            let s = String(message[range])
            if let d = withFrac.date(from: s) ?? plain.date(from: s) { return d }
        }
        if let d = withFrac.date(from: message) ?? plain.date(from: message) { return d }
        if let ms = Int64(message.trimmingCharacters(in: .whitespacesAndNewlines)), ms > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        }
        if let sec = TimeInterval(message.trimmingCharacters(in: .whitespacesAndNewlines)), sec > 1_000_000_000 {
            return Date(timeIntervalSince1970: sec)
        }
        return nil
    }
}
