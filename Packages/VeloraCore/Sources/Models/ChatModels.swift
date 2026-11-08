import Foundation

// MARK: - Private chat + reminder scheduling (DES-v1.3-11-02 MSG-02/04 / N-23/N-24 / T-04 / D38)

/// Product defaults (design §3 / §5.8 / §15). Hot-config on server; client mirrors for UX + gates.
public enum ChatConfigDefaults {
    public static let lotEndingLeadSec = 5 * 60
    public static let payLeadSec = 2 * 60 * 60
    public static let lotteryPayLeadSec = 30 * 60
    public static let balanceLead24hSec = 24 * 60 * 60
    public static let balanceLead2hSec = 2 * 60 * 60
    public static let shipTimeoutLeadSec = 12 * 60 * 60
    public static let autoConfirmLeadSec = 24 * 60 * 60
    public static let subscribeEndingLeadSec = 30 * 60
    /// N-23 same-conversation offline push merge window.
    public static let mergeSec = 60
    public static let ratePerMin = 30
    public static let maxText = 1_000
    public static let imageMaxMB = 5
    public static let retainYears = 3
    public static let lastMessagePreviewMax = 256
    public static let cardMinTapHeightPt = 44
    public static let firingTimeoutSec = 30
    public static let idempotencyTTLHours = 72
    public static let brandProtectionURL = "paddock43://help/trade-protection"
    public static let deeplinkScheme = "paddock43"
    public static let featureFlagOfferCard = "chat.offer_card"
    public static let featureFlagLotEnding = "reminders.lot_ending"
    public static let pureAmountRegex = #"^\d+(\.\d{1,2})?元?$"#
    /// Five user-visible content kinds (MSG-02) — excludes system / risk_banner.
    public static let fiveContentKinds: [ChatMessageKind] = [
        .text, .image, .listingCard, .orderCard, .offerCard,
    ]
}

// MARK: - Conversation subject (MSG-02)

/// `conversations.subject_type` (design §3). Legacy `lot_id` backfills to `lot`.
public enum ConversationSubjectType: String, Codable, Sendable, CaseIterable, Equatable {
    case lot
    case listing
    case order

    public static func normalize(_ raw: String?) -> ConversationSubjectType? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ConversationSubjectType(rawValue: s) { return exact }
        switch s {
        case "拍品", "auction", "lot_id":
            return .lot
        case "商品", "fixed", "buy_now", "listing_id":
            return .listing
        case "订单", "order_id":
            return .order
        default:
            return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .lot: return "拍品"
        case .listing: return "商品"
        case .order: return "订单"
        }
    }
}

// MARK: - Five (+ system / risk) message kinds (MSG-02)

/// `messages.type` (design §3). Read path maps legacy `lot_card` → `listing_card`.
public enum ChatMessageKind: String, Codable, Sendable, CaseIterable, Equatable {
    case text
    case image
    case listingCard = "listing_card"
    case orderCard = "order_card"
    case offerCard = "offer_card"
    case system
    case riskBanner = "risk_banner"

    public static func normalize(_ raw: String?) -> ChatMessageKind? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        // Legacy lot_card → listing_card (design §3).
        if s == "lot_card" || s == "lotcard" || s == "商品卡" { return .listingCard }
        if let exact = ChatMessageKind(rawValue: s) { return exact }
        switch s {
        case "txt", "plain":
            return .text
        case "img", "pic", "photo":
            return .image
        case "product_card", "goods_card":
            return .listingCard
        case "订单卡":
            return .orderCard
        case "报价卡", "offer":
            return .offerCard
        case "sys":
            return .system
        case "risk", "risk_bar", "n24":
            return .riskBanner
        default:
            return nil
        }
    }

    /// Wire value after legacy mapping (never emits `lot_card`).
    public var wireValue: String { rawValue }

    /// MSG-02 content kinds the client may attempt to send (offer_card is server-only).
    public var isUserContentKind: Bool {
        switch self {
        case .text, .image, .listingCard, .orderCard, .offerCard:
            return true
        case .system, .riskBanner:
            return false
        }
    }

    /// Client must not POST forged offer cards (design §5.2 / §6).
    public var clientMaySend: Bool {
        switch self {
        case .text, .image, .listingCard, .orderCard:
            return true
        case .offerCard, .system, .riskBanner:
            return false
        }
    }

    /// Structured cards skip text lexicon (T-07) — shared with IM risk whitelist.
    public var skipsRiskLexicon: Bool {
        switch self {
        case .listingCard, .orderCard, .offerCard:
            return true
        case .text, .image, .system, .riskBanner:
            return false
        }
    }

    public var displayLabel: String {
        switch self {
        case .text: return "文字"
        case .image: return "图片"
        case .listingCard: return "商品卡"
        case .orderCard: return "订单卡"
        case .offerCard: return "报价卡"
        case .system: return "系统"
        case .riskBanner: return "风险提示"
        }
    }

    public var listPreviewPrefix: String {
        switch self {
        case .text: return ""
        case .image: return "[图片]"
        case .listingCard: return "[商品]"
        case .orderCard: return "[订单]"
        case .offerCard: return "[报价]"
        case .system: return ""
        case .riskBanner: return "[提示]"
        }
    }
}

/// `messages.risk_level` (design §3).
public enum ChatRiskLevel: String, Codable, Sendable, CaseIterable, Equatable {
    case none
    case record
    case hint
    case block

    public static func normalize(_ raw: String?) -> ChatRiskLevel? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ChatRiskLevel(rawValue: s) { return exact }
        switch s {
        case "warn", "warning", "allow_with_warn":
            return .hint
        case "blocked", "drop", "intercept":
            return .block
        case "log", "audit":
            return .record
        case "ok", "allow", "pass":
            return ChatRiskLevel.none
        default:
            return nil
        }
    }

    public var showsSenderBanner: Bool {
        self == .hint || self == .block
    }

    /// Hint banners are visible to both peers (N-24); block only to sender.
    public var visibleToPeer: Bool {
        self == .hint
    }
}

// MARK: - Card payloads (design §5.6) — amounts in fen

public struct ChatListingCardPayload: Codable, Equatable, Sendable, Identifiable {
    public var listingId: Int64
    public var title: String
    public var cover: String?
    public var price: Int64
    public var status: String?

    public var id: Int64 { listingId }

    public init(
        listingId: Int64,
        title: String,
        cover: String? = nil,
        price: Int64,
        status: String? = nil
    ) {
        self.listingId = listingId
        self.title = title
        self.cover = cover
        self.price = price
        self.status = status
    }

    public var isInactive: Bool {
        guard let status else { return false }
        let s = status.lowercased()
        return s == "delisted" || s == "off" || s == "sold" || s == "removed"
            || s == "下架" || s == "已售" || s == "失效"
    }
}

public struct ChatOrderCardPayload: Codable, Equatable, Sendable, Identifiable {
    public var orderId: Int64
    public var orderNo: String?
    public var amount: Int64
    public var status: String?
    public var title: String?

    public var id: Int64 { orderId }

    public init(
        orderId: Int64,
        orderNo: String? = nil,
        amount: Int64,
        status: String? = nil,
        title: String? = nil
    ) {
        self.orderId = orderId
        self.orderNo = orderNo
        self.amount = amount
        self.status = status
        self.title = title
    }
}

public struct ChatOfferCardPayload: Codable, Equatable, Sendable, Identifiable {
    public var offerId: Int64
    public var price: Int64
    public var round: Int
    public var expiresAt: Date?
    public var status: String?

    public var id: Int64 { offerId }

    public init(
        offerId: Int64,
        price: Int64,
        round: Int = 1,
        expiresAt: Date? = nil,
        status: String? = nil
    ) {
        self.offerId = offerId
        self.price = price
        self.round = round
        self.expiresAt = expiresAt
        self.status = status
    }

    /// Client countdown is advisory; expiry is always server `expires_at` (design §5.2 / §9).
    public func isExpired(serverNow: Date) -> Bool {
        if let status, ["expired", "superseded", "cancelled", "rejected", "已失效", "已过期"].contains(status.lowercased()) {
            return true
        }
        guard let expiresAt else { return false }
        return expiresAt <= serverNow
    }
}

public struct ChatImagePayload: Codable, Equatable, Sendable {
    public var url: String
    public var width: Int?
    public var height: Int?
    public var sha256: String?

    public init(url: String, width: Int? = nil, height: Int? = nil, sha256: String? = nil) {
        self.url = url
        self.width = width
        self.height = height
        self.sha256 = sha256
    }
}

// MARK: - Push collapse (N-23)

/// `push_collapse` row projection (design §3 / §5.4). Client uses for merge copy + local pending clear.
public struct PushCollapseState: Codable, Equatable, Sendable {
    public var conversationId: Int64
    public var recipientId: Int64
    public var lastPushAt: Date?
    public var pendingCount: Int
    public var pendingUntil: Date?

    public init(
        conversationId: Int64,
        recipientId: Int64,
        lastPushAt: Date? = nil,
        pendingCount: Int = 0,
        pendingUntil: Date? = nil
    ) {
        self.conversationId = conversationId
        self.recipientId = recipientId
        self.lastPushAt = lastPushAt
        self.pendingCount = max(0, pendingCount)
        self.pendingUntil = pendingUntil
    }

    public var hasPending: Bool { pendingCount > 0 }
}

// MARK: - Reminder jobs (MSG-04 / T-04)

/// `reminder_jobs.kind` (design §3 / §5.5). N-15 uses `_24h` / `_2h` suffixes.
public enum ReminderJobKind: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case lotEnding = "lot_ending"
    case payDeadline = "pay_deadline"
    case balanceDeadline = "balance_deadline"
    case balanceDeadline24h = "balance_deadline_24h"
    case balanceDeadline2h = "balance_deadline_2h"
    case lotteryPay = "lottery_pay"
    case subscribeEnding = "subscribe_ending"
    case shipTimeout = "ship_timeout"
    case autoConfirm = "auto_confirm"

    public var id: String { rawValue }

    public static func normalize(_ raw: String?) -> ReminderJobKind? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ReminderJobKind(rawValue: s) { return exact }
        switch s {
        case "n-02", "n02", "closing_remind", "lot_closing":
            return .lotEnding
        case "n-06", "n06", "pay_remind":
            return .payDeadline
        case "n-15", "n15", "balance":
            return .balanceDeadline
        case "n-12", "n12":
            return .lotteryPay
        case "n-28", "n28":
            return .subscribeEnding
        case "n-18", "n18":
            return .shipTimeout
        case "n-19", "n19":
            return .autoConfirm
        default:
            return nil
        }
    }

    public var notifyCode: String {
        switch self {
        case .lotEnding: return "N-02"
        case .payDeadline: return "N-06"
        case .balanceDeadline, .balanceDeadline24h, .balanceDeadline2h: return "N-15"
        case .lotteryPay: return "N-12"
        case .subscribeEnding: return "N-28"
        case .shipTimeout: return "N-18"
        case .autoConfirm: return "N-19"
        }
    }

    public var usesSentOnceKey: Bool { self == .lotEnding }

    public var defaultLeadSec: Int {
        switch self {
        case .lotEnding: return ChatConfigDefaults.lotEndingLeadSec
        case .payDeadline: return ChatConfigDefaults.payLeadSec
        case .lotteryPay: return ChatConfigDefaults.lotteryPayLeadSec
        case .balanceDeadline, .balanceDeadline24h: return ChatConfigDefaults.balanceLead24hSec
        case .balanceDeadline2h: return ChatConfigDefaults.balanceLead2hSec
        case .subscribeEnding: return ChatConfigDefaults.subscribeEndingLeadSec
        case .shipTimeout: return ChatConfigDefaults.shipTimeoutLeadSec
        case .autoConfirm: return ChatConfigDefaults.autoConfirmLeadSec
        }
    }
}

public enum ReminderJobStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case scheduled
    case cancelled
    case firing
    case sent
    case skipped

    public static func normalize(_ raw: String?) -> ReminderJobStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        return ReminderJobStatus(rawValue: raw.lowercased())
    }

    public var isTerminal: Bool {
        switch self {
        case .cancelled, .sent, .skipped: return true
        case .scheduled, .firing: return false
        }
    }
}

public enum ReminderSkipReason: String, Codable, Sendable, CaseIterable, Equatable {
    case stateMismatch = "state_mismatch"
    case alreadySent = "already_sent"
    case userIneligible = "user_ineligible"
    case versionStale = "version_stale"
    case dead

    public static func normalize(_ raw: String?) -> ReminderSkipReason? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ReminderSkipReason(rawValue: s) { return exact }
        switch s {
        case "stale_version", "version_mismatch":
            return .versionStale
        case "sent_once", "n02_sent":
            return .alreadySent
        case "ineligible", "unfollowed":
            return .userIneligible
        case "mismatch", "not_live", "paid", "closed":
            return .stateMismatch
        default:
            return nil
        }
    }
}

public struct ReminderJob: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64
    public var kind: ReminderJobKind
    public var userId: Int64
    public var refType: String
    public var refId: String
    public var fireAt: Date
    public var bindVersion: Int64
    public var status: ReminderJobStatus
    public var skipReason: ReminderSkipReason?
    public var sentOnceKey: String?

    public init(
        id: Int64,
        kind: ReminderJobKind,
        userId: Int64,
        refType: String,
        refId: String,
        fireAt: Date,
        bindVersion: Int64 = 0,
        status: ReminderJobStatus = .scheduled,
        skipReason: ReminderSkipReason? = nil,
        sentOnceKey: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.userId = userId
        self.refType = refType
        self.refId = refId
        self.fireAt = fireAt
        self.bindVersion = bindVersion
        self.status = status
        self.skipReason = skipReason
        self.sentOnceKey = sentOnceKey
    }
}

// MARK: - Error codes (design §6 / §15)

public enum ChatErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case conversationForbidden = "conversation_forbidden"
    case blockedByPeer = "blocked_by_peer"
    case riskBlocked = "risk_blocked"
    case riskHint = "risk_hint"
    case realNameRequired = "real_name_required"
    case accountRestricted = "account_restricted"
    case muteUntil = "mute_until"
    case invalidMessageType = "invalid_message_type"
    case invalidImage = "invalid_image"
    case offerExpired = "offer_expired"
    case subjectNotFound = "subject_not_found"
    case orderCardForbidden = "order_card_forbidden"
    case idempotencyConflict = "idempotency_conflict"
    case missingIdempotencyKey = "missing_idempotency_key"
    case imageTooLarge = "image_too_large"
    case unauthorized = "unauthorized"

    public static func normalize(_ raw: String?) -> ChatErrorCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = ChatErrorCode(rawValue: s) { return exact }
        switch s {
        case "forbidden", "not_member", "chat_forbidden":
            return .conversationForbidden
        case "blocked_by_user", "peer_blocked", "blocked":
            return .blockedByPeer
        case "content_blocked", "im_blocked":
            return .riskBlocked
        case "content_warn", "im_warn":
            return .riskHint
        case "kyc_required", "need_real_name":
            return .realNameRequired
        case "frozen", "restricted":
            return .accountRestricted
        case "im_muted", "muted":
            return .muteUntil
        case "bad_message_type", "offer_card_forged":
            return .invalidMessageType
        case "bad_image", "image_invalid":
            return .invalidImage
        case "offer_expired_local":
            return .offerExpired
        case "subject_missing", "lot_not_found", "listing_not_found":
            return .subjectNotFound
        case "order_forbidden", "not_order_party":
            return .orderCardForbidden
        case "idempotency_required", "missing_idempotency":
            return .missingIdempotencyKey
        case "image_size", "too_large":
            return .imageTooLarge
        case "401", "unauthenticated":
            return .unauthorized
        default:
            return nil
        }
    }

    public var fallbackMessage: String {
        switch self {
        case .conversationForbidden: return "无权查看该会话"
        case .blockedByPeer: return ChatCopy.blockedByPeer
        case .riskBlocked: return ChatCopy.riskBlockedSender
        case .riskHint: return ChatCopy.riskHintBoth
        case .realNameRequired: return ChatCopy.realNameRequired
        case .accountRestricted: return "账号受限，暂不可发送"
        case .muteUntil: return "禁言中，暂不可发送"
        case .invalidMessageType: return "不支持的消息类型"
        case .invalidImage: return "仅支持 JPEG/PNG 图片"
        case .offerExpired: return ChatCopy.offerExpired
        case .subjectNotFound: return "关联对象不存在"
        case .orderCardForbidden: return "只能发送自己的订单卡片"
        case .idempotencyConflict: return "请稍后重试"
        case .missingIdempotencyKey: return "请重试"
        case .imageTooLarge: return "图片过大"
        case .unauthorized: return "请先登录"
        }
    }

    /// Soft 200 with risk strip (design §6).
    public var isSoftRiskHint: Bool { self == .riskHint }
}

// MARK: - Copy (design §5.4 / §9 / §15)

public enum ChatCopy {
    public static let emptyConversation = "问问成色或包浆"
    public static let emptyList = "在拍品页点击「咨询」即可联系卖家"
    public static let riskBlockedSender = "疑似诱导站外收款，未发送给对方"
    public static let riskHintBoth = "请勿站外交易，平台无法保护"
    public static let learnProtection = "了解平台交易保护"
    public static let offerExpired = "已失效"
    public static let offerServerTimeHint = "以服务器时间为准"
    public static let realNameRequired = "发送私信需先完成实名"
    public static let goRealName = "去实名"
    public static let blockedByPeer = "对方已将你拉黑，无法发送"
    public static let peerDeactivated = "用户已注销"
    public static let mutedContactSupport = "联系客服"
    public static let composerPlaceholder = "说点什么…"
    public static let retrySend = "点击重发"
    public static let listingInvalidOverlay = "已失效"
    public static let orderCardTitle = "订单"
    public static let listingCardTitle = "商品"

    /// N-23 merge push body (design §5.4 / §9).
    public static func mergePushBody(unreadCount: Int) -> String {
        let n = max(1, unreadCount)
        return "你有 \(n) 条未读消息"
    }
}

public enum ReminderCopy {
    public static let lotEndingTitle = "拍品即将结束"
    public static let lotEndingBody = "你关注的拍品将在 5 分钟后结拍"
    public static let payDeadlineTitle = "付款提醒"
    public static let payDeadlineBody = "订单即将超时，请尽快付款"
    public static let lotteryPayTitle = "中签付款提醒"
    public static let lotteryPayBody = "中签订单即将超时，请尽快付款"
    public static let balanceDeadlineTitle = "补款提醒"
    public static let balanceDeadlineBody = "预售补款即将截止"
    public static let subscribeEndingTitle = "订阅即将结束"
    public static let subscribeEndingBody = "你订阅的内容即将结束"
    public static let shipTimeoutTitle = "发货提醒"
    public static let shipTimeoutBody = "订单即将超过发货时限"
    public static let autoConfirmTitle = "确认收货提醒"
    public static let autoConfirmBody = "订单即将自动确认收货"

    public static func title(for kind: ReminderJobKind) -> String {
        switch kind {
        case .lotEnding: return lotEndingTitle
        case .payDeadline: return payDeadlineTitle
        case .lotteryPay: return lotteryPayTitle
        case .balanceDeadline, .balanceDeadline24h, .balanceDeadline2h: return balanceDeadlineTitle
        case .subscribeEnding: return subscribeEndingTitle
        case .shipTimeout: return shipTimeoutTitle
        case .autoConfirm: return autoConfirmTitle
        }
    }

    public static func body(for kind: ReminderJobKind) -> String {
        switch kind {
        case .lotEnding: return lotEndingBody
        case .payDeadline: return payDeadlineBody
        case .lotteryPay: return lotteryPayBody
        case .balanceDeadline, .balanceDeadline24h, .balanceDeadline2h: return balanceDeadlineBody
        case .subscribeEnding: return subscribeEndingBody
        case .shipTimeout: return shipTimeoutBody
        case .autoConfirm: return autoConfirmBody
        }
    }
}

// MARK: - Logic

public enum ChatLogic {
    /// Normalize wire type; never leave `lot_card` as a distinct kind.
    public static func messageKind(from raw: String?) -> ChatMessageKind? {
        ChatMessageKind.normalize(raw)
    }

    public static func isLegacyLotCard(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let s = raw.lowercased()
        return s == "lot_card" || s == "lotcard"
    }

    /// Five MSG-02 content kinds after mapping.
    public static func isFiveContentKind(_ kind: ChatMessageKind) -> Bool {
        ChatConfigDefaults.fiveContentKinds.contains(kind)
    }

    public static func validateClientSend(kind: ChatMessageKind) -> ChatErrorCode? {
        kind.clientMaySend ? nil : .invalidMessageType
    }

    public static func validateTextLength(_ text: String) -> ChatErrorCode? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .invalidMessageType }
        if trimmed.count > ChatConfigDefaults.maxText { return .invalidMessageType }
        return nil
    }

    public static func looksLikePureAmount(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        return t.range(of: ChatConfigDefaults.pureAmountRegex, options: .regularExpression) != nil
    }

    public static func truncatePreview(_ text: String, max: Int = ChatConfigDefaults.lastMessagePreviewMax) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max))
    }

    public static func listPreview(kind: ChatMessageKind, content: String) -> String {
        let prefix = kind.listPreviewPrefix
        if prefix.isEmpty { return truncatePreview(content) }
        if content.isEmpty { return prefix }
        return truncatePreview("\(prefix) \(content)")
    }

    // MARK: N-23 push collapse

    /// Whether an offline push should be suppressed and folded into pending (design §5.4).
    public static func shouldCollapsePush(
        lastPushAt: Date?,
        now: Date,
        mergeSec: Int = ChatConfigDefaults.mergeSec
    ) -> Bool {
        guard let lastPushAt else { return false }
        return now < lastPushAt.addingTimeInterval(TimeInterval(mergeSec))
    }

    public static func nextCollapseState(
        current: PushCollapseState,
        now: Date,
        recipientOnline: Bool,
        mergeSec: Int = ChatConfigDefaults.mergeSec
    ) -> PushCollapseState {
        var next = current
        if recipientOnline {
            next.pendingCount = 0
            next.pendingUntil = nil
            return next
        }
        if shouldCollapsePush(lastPushAt: current.lastPushAt, now: now, mergeSec: mergeSec) {
            next.pendingCount = current.pendingCount + 1
            if let last = current.lastPushAt {
                next.pendingUntil = last.addingTimeInterval(TimeInterval(mergeSec))
            } else {
                next.pendingUntil = now.addingTimeInterval(TimeInterval(mergeSec))
            }
        } else {
            next.lastPushAt = now
            next.pendingCount = 0
            next.pendingUntil = nil
        }
        return next
    }

    public static func mergePushBody(pendingCount: Int) -> String {
        ChatCopy.mergePushBody(unreadCount: pendingCount)
    }

    /// Opening a conversation clears local merge pending (design §9).
    public static func clearLocalPending(_ state: PushCollapseState) -> PushCollapseState {
        var next = state
        next.pendingCount = 0
        next.pendingUntil = nil
        return next
    }

    // MARK: Reminders / T-04

    public static func sentOnceKey(userId: Int64, lotId: Int64) -> String {
        "lot_ending:\(userId):\(lotId)"
    }

    public static func fireAt(deadline: Date, leadSec: Int) -> Date {
        deadline.addingTimeInterval(-TimeInterval(leadSec))
    }

    /// N-02: after `sent_once_key` exists, never insert another lot_ending (design §5.5).
    public static func shouldInsertLotEnding(sentOnceOccupied: Bool) -> Bool {
        !sentOnceOccupied
    }

    /// Reschedule on `end_at_version` bump only when not yet sent.
    public static func shouldRescheduleLotEnding(previousStatus: ReminderJobStatus, sentOnceOccupied: Bool) -> Bool {
        if sentOnceOccupied { return false }
        return previousStatus == .scheduled || previousStatus == .cancelled || previousStatus == .firing
    }

    public static func uniqueJobKey(kind: ReminderJobKind, userId: Int64, refType: String, refId: String, bindVersion: Int64) -> String {
        "\(kind.rawValue):\(userId):\(refType):\(refId):\(bindVersion)"
    }

    /// Offer card actions disabled after server expiry (design §9 / client duties).
    public static func offerActionsEnabled(payload: ChatOfferCardPayload, serverNow: Date) -> Bool {
        !payload.isExpired(serverNow: serverNow)
    }

    /// Risk strip for the current session is not dismissible (design §9).
    public static func riskBannerDismissible(level: ChatRiskLevel) -> Bool {
        _ = level
        return false
    }

    public static func senderBubbleDimmed(blocked: Bool, riskLevel: ChatRiskLevel?) -> Bool {
        blocked || riskLevel == .block
    }

    public static func imageMaxBytes(maxMB: Int = ChatConfigDefaults.imageMaxMB) -> Int {
        maxMB * 1_024 * 1_024
    }

    public static func validateImageSize(bytes: Int, maxMB: Int = ChatConfigDefaults.imageMaxMB) -> ChatErrorCode? {
        bytes > imageMaxBytes(maxMB: maxMB) ? .imageTooLarge : nil
    }
}
