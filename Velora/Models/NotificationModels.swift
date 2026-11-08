import Foundation

// MARK: - Notification center + offline push (DES-v1.3-11-01 MSG-01/03/05/06 / D37 — app mirror of VeloraCore)

/// Product defaults (design §3 / §5.9 / §15). Hot-config on server; client mirrors for UX + gates.
enum NotifyConfigDefaults {
    static let dedupWindowSec = 600
    static let onlinePongSec = 45
    static let clientPingSec = 20
    static let apnsEnabledKey = "push.apns"
    static let apnsEnabledDefault = true
    static let smsEnabledKey = "push.sms"
    static let smsEnabledDefault = true
    static let retainDays = 180
    static let smsMaxPerMin = 2
    static let smsRegionKey = "sms.region"
    static let smsRegionDefault = "CN_mainland"
    static let pageSizeDefault = 20
    static let pageSizeMax = 50
    static let titleMaxLen = 64
    static let bodyMaxLen = 256
    static let counterReconcileSec = 300
    static let apnsTimeoutSec = 8
    static let smsTimeoutSec = 5
    static let pushRetryMax = 3
    static let marketingPushFlag = "feature_flags.marketing_push"
    static let marketingPushDefault = false
    static let pushEvenWhenOnlineDefault = false
    static let platformIOSAPNs = "ios_apns"
    static let deeplinkScheme = "paddock43"
    static let quietHoursTimezone = "Asia/Shanghai"
    /// Subscribe-class mute window start hour (inclusive), local Asia/Shanghai.
    static let quietHoursStartHour = 22
    /// Subscribe-class mute window end hour (exclusive), local Asia/Shanghai.
    static let quietHoursEndHour = 8
    static let inboxTabsOrdered: [InboxTab] = InboxTab.allCases
}

// MARK: - Five inbox tabs (MSG-01)

/// Notification center tabs: 交易 / 关注 / 竞拍 / 私聊 / 系统 (design §5.1).
enum InboxTab: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case trade
    case follow
    case auction
    case chat
    case system

    var id: String { rawValue }

    static func normalize(_ raw: String?) -> InboxTab? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = InboxTab(rawValue: s) { return exact }
        switch s {
        case "交易", "order", "orders":
            return .trade
        case "关注", "subscribe", "subscription":
            return .follow
        case "竞拍", "bid", "bidding", "lot":
            return .auction
        case "私聊", "im", "dm", "message", "messages", "conversation", "conversations":
            return .chat
        case "系统", "account", "sys":
            return .system
        default:
            return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .trade: return "交易"
        case .follow: return "关注"
        case .auction: return "竞拍"
        case .chat: return "私聊"
        case .system: return "系统"
        }
    }

    var emptyTitle: String { NotifyCopy.emptyTitle }

    var emptyMessage: String {
        switch self {
        case .trade: return NotifyCopy.emptyTrade
        case .follow: return NotifyCopy.emptyFollow
        case .auction: return NotifyCopy.emptyAuction
        case .chat: return NotifyCopy.emptyChat
        case .system: return NotifyCopy.emptySystem
        }
    }

    var systemImage: String {
        switch self {
        case .trade: return "bag"
        case .follow: return "heart"
        case .auction: return "hammer"
        case .chat: return "bubble.left.and.bubble.right"
        case .system: return "gearshape"
        }
    }

    /// Chat tab reads conversations, not `notifications` (design §5.1).
    var usesConversationsAPI: Bool { self == .chat }

    /// API `category` query; nil for chat (uses conversations).
    var apiCategory: NotificationCategory? {
        switch self {
        case .trade: return .trade
        case .follow: return .follow
        case .auction: return .auction
        case .system: return .system
        case .chat: return nil
        }
    }
}

/// `notifications.category` — private chat never lands in this table (design §3).
enum NotificationCategory: String, Codable, Sendable, CaseIterable, Equatable {
    case trade
    case follow
    case auction
    case system

    static func normalize(_ raw: String?) -> NotificationCategory? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = NotificationCategory(rawValue: s) { return exact }
        return InboxTab.normalize(s)?.apiCategory
    }

    var inboxTab: InboxTab {
        switch self {
        case .trade: return .trade
        case .follow: return .follow
        case .auction: return .auction
        case .system: return .system
        }
    }

    var displayLabel: String { inboxTab.displayLabel }
}

// MARK: - Counters (MSG-01)

/// `inbox_counters` projection + WS `notification.unread` (design §3 / §5.7).
struct InboxCounters: Codable, Equatable, Sendable {
    var unreadTrade: Int
    var unreadFollow: Int
    var unreadAuction: Int
    var unreadChat: Int
    var unreadSystem: Int
    /// Prefer server `unread_total`; client may recompute via `recomputedTotal`.
    var unreadTotal: Int

    init(
        unreadTrade: Int = 0,
        unreadFollow: Int = 0,
        unreadAuction: Int = 0,
        unreadChat: Int = 0,
        unreadSystem: Int = 0,
        unreadTotal: Int? = nil
    ) {
        self.unreadTrade = max(0, unreadTrade)
        self.unreadFollow = max(0, unreadFollow)
        self.unreadAuction = max(0, unreadAuction)
        self.unreadChat = max(0, unreadChat)
        self.unreadSystem = max(0, unreadSystem)
        let sum = self.unreadTrade + self.unreadFollow + self.unreadAuction + self.unreadChat + self.unreadSystem
        self.unreadTotal = max(0, unreadTotal ?? sum)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let alt = try? decoder.container(keyedBy: AltKeys.self)
        func pick(_ key: CodingKeys, _ short: AltKeys) -> Int {
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
            return (try? alt?.decodeIfPresent(Int.self, forKey: short)) ?? 0
        }
        self.init(
            unreadTrade: pick(.unreadTrade, .trade),
            unreadFollow: pick(.unreadFollow, .follow),
            unreadAuction: pick(.unreadAuction, .auction),
            unreadChat: pick(.unreadChat, .chat),
            unreadSystem: pick(.unreadSystem, .system),
            unreadTotal: (try? c.decodeIfPresent(Int.self, forKey: .unreadTotal))
                ?? (try? alt?.decodeIfPresent(Int.self, forKey: .total))
                ?? nil
        )
    }

    private enum CodingKeys: String, CodingKey {
        case unreadTrade, unreadFollow, unreadAuction, unreadChat, unreadSystem, unreadTotal
    }

    private enum AltKeys: String, CodingKey {
        case trade, follow, auction, chat, system, total
    }

    var recomputedTotal: Int {
        unreadTrade + unreadFollow + unreadAuction + unreadChat + unreadSystem
    }

    /// Five-tab sum must equal total (MSG-01 / §14).
    var isConsistent: Bool { unreadTotal == recomputedTotal }

    func unread(for tab: InboxTab) -> Int {
        switch tab {
        case .trade: return unreadTrade
        case .follow: return unreadFollow
        case .auction: return unreadAuction
        case .chat: return unreadChat
        case .system: return unreadSystem
        }
    }

    mutating func setUnread(_ value: Int, for tab: InboxTab) {
        let v = max(0, value)
        switch tab {
        case .trade: unreadTrade = v
        case .follow: unreadFollow = v
        case .auction: unreadAuction = v
        case .chat: unreadChat = v
        case .system: unreadSystem = v
        }
        unreadTotal = recomputedTotal
    }

    /// Apply WS `unread` overlay — never locally ±1 (design §5.7).
    static func fromWSUnread(_ dict: [String: Int]) -> InboxCounters {
        InboxCounters(
            unreadTrade: dict["trade"] ?? dict["unread_trade"] ?? 0,
            unreadFollow: dict["follow"] ?? dict["unread_follow"] ?? 0,
            unreadAuction: dict["auction"] ?? dict["unread_auction"] ?? 0,
            unreadChat: dict["chat"] ?? dict["unread_chat"] ?? 0,
            unreadSystem: dict["system"] ?? dict["unread_system"] ?? 0,
            unreadTotal: dict["total"] ?? dict["unread_total"]
        )
    }

    /// Guests have no notification center; badge 0 (design §5.1).
    static let guestZero = InboxCounters()
}

// MARK: - Channel class / event matrix (MSG-05 / 9.1)

/// Push / inbox switch class (design §5.5).
enum PushChannelClass: String, Codable, Sendable, CaseIterable, Equatable {
    case trade
    case subscribe
    case marketing
    case social
    case account

    static func normalize(_ raw: String?) -> PushChannelClass? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = PushChannelClass(rawValue: s) { return exact }
        switch s {
        case "交易": return .trade
        case "订阅", "follow": return .subscribe
        case "营销": return .marketing
        case "社交": return .social
        case "账号", "system": return .account
        default: return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .trade: return "交易"
        case .subscribe: return "订阅"
        case .marketing: return "营销"
        case .social: return "社交"
        case .account: return "账号"
        }
    }

    /// Trade inbox is forced on (design §5.5 / MSG-05).
    var inboxForcedOn: Bool { self == .trade }

    /// Quiet-hours sound mute applies to subscribe (+ marketing) only (design §9).
    var respectsQuietHours: Bool {
        self == .subscribe || self == .marketing
    }
}

/// Matrix event codes N-01…N-35 (design §5.2).
enum NotificationEventCode: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    case n01 = "N-01"
    case n02 = "N-02"
    case n03 = "N-03"
    case n04 = "N-04"
    case n05 = "N-05"
    case n06 = "N-06"
    case n07 = "N-07"
    case n08 = "N-08"
    case n09 = "N-09"
    case n10 = "N-10"
    case n11 = "N-11"
    case n12 = "N-12"
    case n13 = "N-13"
    case n14 = "N-14"
    case n15 = "N-15"
    case n16 = "N-16"
    case n17 = "N-17"
    case n18 = "N-18"
    case n19 = "N-19"
    case n20 = "N-20"
    case n21 = "N-21"
    case n22 = "N-22"
    case n23 = "N-23"
    case n24 = "N-24"
    case n25 = "N-25"
    case n26 = "N-26"
    case n27 = "N-27"
    case n28 = "N-28"
    case n29 = "N-29"
    case n30 = "N-30"
    case n31 = "N-31"
    case n32 = "N-32"
    case n33 = "N-33"
    case n34 = "N-34"
    case n35 = "N-35"

    var id: String { rawValue }

    static func normalize(_ raw: String?) -> NotificationEventCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.uppercased().replacingOccurrences(of: "_", with: "-")
        if let exact = NotificationEventCode(rawValue: s) { return exact }
        // Accept "n01" / "N01"
        if s.hasPrefix("N"), s.count <= 4, !s.contains("-") {
            let padded = "N-" + String(format: "%02d", Int(s.dropFirst()) ?? -1)
            return NotificationEventCode(rawValue: padded)
        }
        return nil
    }

    /// Inbox tab / category for stand-in notifications. Chat events do not write `notifications`.
    var inboxTab: InboxTab? {
        switch self {
        case .n01, .n02, .n03, .n32:
            return .auction
        case .n04:
            return nil // room WS only
        case .n05, .n06, .n07, .n08, .n09, .n11, .n12, .n13, .n14, .n15, .n16, .n17, .n18, .n19, .n20, .n21, .n33:
            return .trade
        case .n10, .n22, .n28, .n29, .n30, .n31:
            return .follow
        case .n23, .n24:
            return .chat
        case .n25, .n26, .n27, .n34, .n35:
            return .system
        }
    }

    var notificationCategory: NotificationCategory? {
        guard let tab = inboxTab, tab != .chat else { return nil }
        return tab.apiCategory
    }

    var channelClass: PushChannelClass {
        switch self {
        case .n05, .n06, .n07, .n08, .n09, .n11, .n12, .n13, .n14, .n15, .n16, .n17, .n18, .n19, .n20, .n21, .n33:
            return .trade
        case .n02, .n03, .n10, .n28, .n29, .n30, .n31:
            return .subscribe
        case .n22:
            return .social
        case .n25, .n26, .n27, .n34, .n35:
            return .account
        case .n01, .n04, .n23, .n24, .n32:
            // Auction / chat alerts: not subscribe-class → no quiet-hours mute (design §5.5 / §9).
            return .account
        }
    }

    /// Inbox-only by default — no system push (design §5.2).
    var inboxOnlyDefault: Bool {
        switch self {
        case .n19, .n20, .n31, .n34, .n35:
            return true
        default:
            return false
        }
    }

    /// Never inserts into `notifications` (design §5.2).
    var skipsInboxTable: Bool {
        switch self {
        case .n04, .n23, .n24:
            return true
        default:
            return false
        }
    }

    /// Lifetime dedup (not 10-minute window) — N-02 (design §5.4).
    var lifetimeDedup: Bool { self == .n02 }

    /// Extra 24h cap — N-29 (design §5.4).
    var hasDailyCap: Bool { self == .n29 }

    /// Matrix SMS events (MSG-06).
    var smsRequiredByMatrix: Bool {
        switch self {
        case .n05, .n06, .n11, .n12, .n13, .n14, .n15, .n21, .n33:
            return true
        default:
            return false
        }
    }
}

// MARK: - Push status / tokens / settings

enum NotificationPushStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case skippedOnline = "skipped_online"
    case skippedQuiet = "skipped_quiet"
    case skippedUser = "skipped_user"
    case skippedInboxOnly = "skipped_inbox_only"
    case dryRun = "dry_run"
    case queued
    case sent
    case failed

    static func normalize(_ raw: String?) -> NotificationPushStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = NotificationPushStatus(rawValue: s) { return exact }
        switch s {
        case "skip_online", "online_skip", "ws":
            return .skippedOnline
        case "skip_quiet", "quiet_skip", "quiet_hours":
            return .skippedQuiet
        case "skip_user", "user_skip", "disabled_by_user", "push_disabled_by_user":
            return .skippedUser
        case "skip_inbox_only", "inbox_only", "inbox_only_skip":
            return .skippedInboxOnly
        case "dryrun", "dry-run":
            return .dryRun
        default:
            return nil
        }
    }
}

enum NotificationSMSStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case none
    case queued
    case sent
    case failed

    static func normalize(_ raw: String?) -> NotificationSMSStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        return NotificationSMSStatus(rawValue: raw.lowercased())
    }
}

enum PushTokenPlatform: String, Codable, Sendable, CaseIterable, Equatable {
    case iosAPNs = "ios_apns"

    static func normalize(_ raw: String?) -> PushTokenPlatform? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if s == "ios_apns" || s == "ios" || s == "apns" || s == "iphone" {
            return .iosAPNs
        }
        return nil
    }

    static func validate(_ raw: String?) -> PushTokenPlatform? {
        normalize(raw)
    }
}

struct PushTokenRegistration: Codable, Equatable, Sendable {
    var platform: String
    var token: String
    var brand: String?
    var bundleId: String?

    init(platform: String = NotifyConfigDefaults.platformIOSAPNs, token: String, brand: String? = "apple", bundleId: String? = nil) {
        self.platform = platform
        self.token = token
        self.brand = brand
        self.bundleId = bundleId
    }

    var body: [String: Any?] {
        [
            "platform": platform,
            "token": token,
            "brand": brand,
            "bundle_id": bundleId,
        ]
    }

    var isValidPlatform: Bool {
        PushTokenPlatform.validate(platform) != nil
    }
}

/// Per-event switch row (design §5.5 / §6).
struct PushSetting: Codable, Equatable, Sendable, Identifiable {
    var eventCode: String
    var inboxEnabled: Bool
    var pushEnabled: Bool
    var smsEnabled: Bool

    var id: String { eventCode }

    init(eventCode: String, inboxEnabled: Bool = true, pushEnabled: Bool = true, smsEnabled: Bool = false) {
        self.eventCode = eventCode
        self.inboxEnabled = inboxEnabled
        self.pushEnabled = pushEnabled
        self.smsEnabled = smsEnabled
    }

    var resolvedEvent: NotificationEventCode? {
        NotificationEventCode.normalize(eventCode)
    }

    var channelClass: PushChannelClass {
        resolvedEvent?.channelClass ?? .account
    }
}

struct PushSettingsPayload: Codable, Equatable, Sendable {
    var items: [PushSetting]
    /// Optional user preference: still receive APNs while any device has live WS (design §5.7).
    var pushEvenWhenOnline: Bool

    init(items: [PushSetting] = [], pushEvenWhenOnline: Bool = NotifyConfigDefaults.pushEvenWhenOnlineDefault) {
        self.items = items
        self.pushEvenWhenOnline = pushEvenWhenOnline
    }

    enum CodingKeys: String, CodingKey {
        case items, pushEvenWhenOnline
    }

    init(from decoder: Decoder) throws {
        if let arr = try? decoder.singleValueContainer().decode([PushSetting].self) {
            items = arr
            pushEvenWhenOnline = NotifyConfigDefaults.pushEvenWhenOnlineDefault
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([PushSetting].self, forKey: .items) ?? []
        pushEvenWhenOnline = try c.decodeIfPresent(Bool.self, forKey: .pushEvenWhenOnline)
            ?? NotifyConfigDefaults.pushEvenWhenOnlineDefault
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encode(pushEvenWhenOnline, forKey: .pushEvenWhenOnline)
    }

    func setting(for code: NotificationEventCode) -> PushSetting? {
        items.first { NotificationEventCode.normalize($0.eventCode) == code }
    }
}

struct UpdatePushSettingsRequest: Equatable, Sendable {
    var items: [PushSetting]
    var pushEvenWhenOnline: Bool?

    init(items: [PushSetting], pushEvenWhenOnline: Bool? = nil) {
        self.items = items
        self.pushEvenWhenOnline = pushEvenWhenOnline
    }

    var body: [String: Any?] {
        var dict: [String: Any?] = [
            "items": items.map { s -> [String: Any] in
                [
                    "event_code": s.eventCode,
                    "inbox_enabled": s.inboxEnabled,
                    "push_enabled": s.pushEnabled,
                    "sms_enabled": s.smsEnabled,
                ]
            },
        ]
        if let pushEvenWhenOnline {
            dict["push_even_when_online"] = pushEvenWhenOnline
        }
        return dict
    }
}

// MARK: - Quiet hours (design §9)

/// Asia/Shanghai 22:00–08:00 mute for subscribe-class push sound (inbox never muted).
struct QuietHours: Equatable, Sendable {
    var startHour: Int
    var endHour: Int
    var timeZoneIdentifier: String

    init(
        startHour: Int = NotifyConfigDefaults.quietHoursStartHour,
        endHour: Int = NotifyConfigDefaults.quietHoursEndHour,
        timeZoneIdentifier: String = NotifyConfigDefaults.quietHoursTimezone
    ) {
        self.startHour = startHour
        self.endHour = endHour
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    static let shanghaiNight = QuietHours()

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 8 * 3600)!
    }

    /// Whether `date` falls inside the overnight quiet window.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        var cal = calendar
        cal.timeZone = timeZone
        let hour = cal.component(.hour, from: date)
        if startHour > endHour {
            // e.g. 22 → 08 overnight
            return hour >= startHour || hour < endHour
        }
        return hour >= startHour && hour < endHour
    }

    /// Mute APNs sound for this event at `date` (trade always unmuted).
    func shouldMuteSound(
        channelClass: PushChannelClass,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard channelClass.respectsQuietHours else { return false }
        return contains(date, calendar: calendar)
    }

    func shouldMuteSound(
        eventCode: NotificationEventCode,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        shouldMuteSound(channelClass: eventCode.channelClass, at: date, calendar: calendar)
    }
}

// MARK: - Notification row / list / read

struct InboxNotification: Codable, Equatable, Sendable, Identifiable {
    var id: Int64
    var category: NotificationCategory
    var eventCode: String
    var title: String
    var body: String
    var refType: String?
    var refId: String?
    var deeplink: String?
    var readAt: Date?
    var createdAt: Date?
    var pushStatus: NotificationPushStatus?
    var smsStatus: NotificationSMSStatus?

    init(
        id: Int64,
        category: NotificationCategory,
        eventCode: String,
        title: String,
        body: String,
        refType: String? = nil,
        refId: String? = nil,
        deeplink: String? = nil,
        readAt: Date? = nil,
        createdAt: Date? = nil,
        pushStatus: NotificationPushStatus? = nil,
        smsStatus: NotificationSMSStatus? = nil
    ) {
        self.id = id
        self.category = category
        self.eventCode = eventCode
        self.title = title
        self.body = body
        self.refType = refType
        self.refId = refId
        self.deeplink = deeplink
        self.readAt = readAt
        self.createdAt = createdAt
        self.pushStatus = pushStatus
        self.smsStatus = smsStatus
    }

    enum CodingKeys: String, CodingKey {
        case id, category, eventCode, title, body, refType, refId, deeplink
        case readAt, createdAt, pushStatus, smsStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        // Prefer string→normalize so unknown categories fail the row (list is lossy),
        // while unknown push/sms statuses become nil instead of failing the row.
        if let cat = try? c.decode(NotificationCategory.self, forKey: .category) {
            category = cat
        } else if let raw = try c.decodeIfPresent(String.self, forKey: .category),
                  let normalized = NotificationCategory.normalize(raw) {
            category = normalized
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .category,
                in: c,
                debugDescription: "missing or unknown notification category"
            )
        }
        eventCode = try c.decodeIfPresent(String.self, forKey: .eventCode) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        refType = try c.decodeIfPresent(String.self, forKey: .refType)
        refId = try c.decodeIfPresent(String.self, forKey: .refId)
        deeplink = try c.decodeIfPresent(String.self, forKey: .deeplink)
        readAt = try c.decodeIfPresent(Date.self, forKey: .readAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        if let status = try? c.decode(NotificationPushStatus.self, forKey: .pushStatus) {
            pushStatus = status
        } else {
            pushStatus = NotificationPushStatus.normalize(try c.decodeIfPresent(String.self, forKey: .pushStatus))
        }
        if let status = try? c.decode(NotificationSMSStatus.self, forKey: .smsStatus) {
            smsStatus = status
        } else {
            smsStatus = NotificationSMSStatus.normalize(try c.decodeIfPresent(String.self, forKey: .smsStatus))
        }
    }

    var isUnread: Bool { readAt == nil }

    var resolvedEvent: NotificationEventCode? {
        NotificationEventCode.normalize(eventCode)
    }

    var inboxTab: InboxTab { category.inboxTab }
}

struct NotificationListPage: Decodable, Equatable, Sendable {
    var items: [InboxNotification]
    var page: Int?
    var pageSize: Int?
    var total: Int?
    var nextCursor: String?

    init(items: [InboxNotification], page: Int? = nil, pageSize: Int? = nil, total: Int? = nil, nextCursor: String? = nil) {
        self.items = items
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.nextCursor = nextCursor
    }

    enum CodingKeys: String, CodingKey {
        case items, page, pageSize, total, nextCursor
        case list, notifications, data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let items = Self.decodeLossyItems(from: c, forKey: .items) {
            self.items = items
        } else if let items = Self.decodeLossyItems(from: c, forKey: .list) {
            self.items = items
        } else if let items = Self.decodeLossyItems(from: c, forKey: .notifications) {
            self.items = items
        } else if let items = Self.decodeLossyItems(from: c, forKey: .data) {
            self.items = items
        } else {
            self.items = []
        }
        page = try c.decodeIfPresent(Int.self, forKey: .page)
        pageSize = try c.decodeIfPresent(Int.self, forKey: .pageSize)
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
    }

    /// Per-item tolerant decode so one bad row does not fail the whole tab.
    private static func decodeLossyItems(
        from c: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [InboxNotification]? {
        guard var arr = try? c.nestedUnkeyedContainer(forKey: key) else { return nil }
        var items: [InboxNotification] = []
        while !arr.isAtEnd {
            if let item = try? arr.decode(InboxNotification.self) {
                items.append(item)
            } else {
                // Advance past the bad element; break if we cannot consume it.
                if (try? arr.decode(NotifyLossyJSONValue.self)) == nil { break }
            }
        }
        return items
    }
}

/// Consumes an arbitrary JSON value so lossy array decoding can skip bad rows.
private struct NotifyLossyJSONValue: Decodable {
    init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer() {
            if c.decodeNil() { return }
            if (try? c.decode(Bool.self)) != nil { return }
            if (try? c.decode(Int64.self)) != nil { return }
            if (try? c.decode(Double.self)) != nil { return }
            if (try? c.decode(String.self)) != nil { return }
            if (try? c.decode([NotifyLossyJSONValue].self)) != nil { return }
            if (try? c.decode([String: NotifyLossyJSONValue].self)) != nil { return }
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            while !unkeyed.isAtEnd {
                _ = try? unkeyed.decode(NotifyLossyJSONValue.self)
            }
            return
        }
        _ = try? decoder.container(keyedBy: NotifyDynamicCodingKey.self)
    }
}

private struct NotifyDynamicCodingKey: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

struct MarkNotificationsReadRequest: Equatable, Sendable {
    var ids: [Int64]?
    var category: String?
    var all: Bool?

    init(ids: [Int64]? = nil, category: String? = nil, all: Bool? = nil) {
        self.ids = ids
        self.category = category
        self.all = all
    }

    var body: [String: Any?] {
        var dict: [String: Any?] = [:]
        if let ids { dict["ids"] = ids }
        if let category { dict["category"] = category }
        if let all { dict["all"] = all }
        return dict
    }
}

struct MarkNotificationsReadResponse: Codable, Equatable, Sendable {
    var unread: InboxCounters?
    var marked: Int?

    init(unread: InboxCounters? = nil, marked: Int? = nil) {
        self.unread = unread
        self.marked = marked
    }
}

// MARK: - Error codes (design §5.9 / §15)

enum NotifyErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case missingIdempotencyKey = "missing_idempotency_key"
    case invalidCategory = "invalid_category"
    case tradeInboxCannotDisable = "trade_inbox_cannot_disable"
    case invalidPushToken = "invalid_push_token"
    case notificationNotFound = "notification_not_found"
    case refGone = "ref_gone"
    case pushDisabledByUser = "push_disabled_by_user"
    case smsRateLimited = "sms_rate_limited"
    case unauthorized = "unauthorized"

    static func normalize(_ raw: String?) -> NotifyErrorCode? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let exact = NotifyErrorCode(rawValue: s) { return exact }
        switch s {
        case "idempotency_required", "missing_idempotency":
            return .missingIdempotencyKey
        case "bad_category", "unknown_category":
            return .invalidCategory
        case "cannot_disable_trade_inbox", "trade_inbox_required":
            return .tradeInboxCannotDisable
        case "bad_push_token", "unsupported_push_platform":
            return .invalidPushToken
        case "not_found", "notify_not_found":
            return .notificationNotFound
        case "gone", "target_gone", "deeplink_gone":
            return .refGone
        case "push_skipped", "user_disabled_push":
            return .pushDisabledByUser
        case "sms_limited", "rate_limited_sms":
            return .smsRateLimited
        case "401", "unauthenticated":
            return .unauthorized
        default:
            return nil
        }
    }

    var fallbackMessage: String {
        switch self {
        case .missingIdempotencyKey: return "请重试"
        case .invalidCategory: return "无效的消息分栏"
        case .tradeInboxCannotDisable: return "交易类站内通知无法关闭"
        case .invalidPushToken: return "仅支持 iOS 推送令牌"
        case .notificationNotFound: return "消息不存在"
        case .refGone: return NotifyCopy.refGone
        case .pushDisabledByUser: return "已跳过系统推送"
        case .smsRateLimited: return "短信发送过于频繁"
        case .unauthorized: return "请先登录"
        }
    }

    /// Soft skip — HTTP still 200 (design §5.9).
    var isSoftSkip: Bool { self == .pushDisabledByUser }
}

// MARK: - Copy (design §9)

enum NotifyCopy {
    static let centerTitle = "消息"
    static let emptyTitle = "暂无消息"
    static let emptyTrade = "订单进展会在这里"
    static let emptyFollow = "订阅与降价"
    static let emptyAuction = "出价被超会提醒"
    static let emptyChat = "在拍品页点击「咨询」即可联系卖家"
    static let emptySystem = "审核与处罚"
    static let goShopping = "去购买"
    static let syncFailed = "同步失败，点击重试"
    static let markAllRead = "全部已读"
    static let marking = "处理中…"
    static let refGone = "内容已失效"
    static let backToList = "返回消息列表"
    static let pushSettingsTitle = "推送设置"
    static let tradeInboxLocked = "交易类站内通知无法关闭"
    static let pushAuthDenied = "系统通知未开启，站内消息不受影响"
    static let openSystemSettings = "去系统设置开启"
    static let quietHoursHint = "订阅类推送 22:00–08:00 静音（交易类仍提醒）"
    static let pushEvenWhenOnline = "即使在线也推送"
    static let guestBlocked = "登录后查看消息"
    static let doNotDisturbHint = "免打扰只关声音，交易红点仍会显示"
}

// MARK: - Logic

enum NotifyLogic {
    static func clampPageSize(_ raw: Int?) -> Int {
        let n = raw ?? NotifyConfigDefaults.pageSizeDefault
        return min(max(n, 1), NotifyConfigDefaults.pageSizeMax)
    }

    /// Guests: no center, badge 0.
    static func badgeTotal(isLoggedIn: Bool, counters: InboxCounters) -> Int {
        isLoggedIn ? max(0, counters.unreadTotal) : 0
    }

    static func validateCategoryQuery(_ raw: String?) -> NotifyErrorCode? {
        guard let raw, !raw.isEmpty else { return nil } // default = all
        if InboxTab.normalize(raw) == .chat { return .invalidCategory } // chat not on notifications API
        if NotificationCategory.normalize(raw) == nil { return .invalidCategory }
        return nil
    }

    static func validatePushTokenPlatform(_ platform: String?) -> NotifyErrorCode? {
        PushTokenPlatform.validate(platform) == nil ? .invalidPushToken : nil
    }

    /// MSG-05: trade inbox_enabled must stay true.
    static func validatePushSettingUpdate(_ setting: PushSetting) -> NotifyErrorCode? {
        let cls = setting.channelClass
        if cls.inboxForcedOn && setting.inboxEnabled == false {
            return .tradeInboxCannotDisable
        }
        if let code = setting.resolvedEvent, code.channelClass.inboxForcedOn && !setting.inboxEnabled {
            return .tradeInboxCannotDisable
        }
        return nil
    }

    static func validatePushSettingsUpdate(_ items: [PushSetting]) -> NotifyErrorCode? {
        for item in items {
            if let err = validatePushSettingUpdate(item) { return err }
        }
        return nil
    }

    /// Apply forced trade inbox before PUT.
    static func normalizedSetting(_ setting: PushSetting) -> PushSetting {
        var copy = setting
        if copy.channelClass.inboxForcedOn {
            copy.inboxEnabled = true
        }
        return copy
    }

    static func isDeeplinkAllowed(_ raw: String?) -> Bool {
        guard let raw, !raw.isEmpty else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("javascript:") { return false }
        if lower.hasPrefix("\(NotifyConfigDefaults.deeplinkScheme)://") { return true }
        if lower.hasPrefix("https://") {
            // Official hosts only — keep permissive to paddock43 / velora domains.
            if let host = URL(string: trimmed)?.host?.lowercased() {
                return host == "paddock43.com"
                    || host.hasSuffix(".paddock43.com")
                    || host == "velora.app"
                    || host.hasSuffix(".velora.app")
            }
        }
        return false
    }

    /// Dedup key = event_code + ':' + ref_stable (design §5.4).
    static func dedupKey(eventCode: String, refStable: String) -> String {
        "\(eventCode):\(refStable)"
    }

    static func countersAfterMarking(
        _ counters: InboxCounters,
        tab: InboxTab?,
        all: Bool,
        decreasingBy: Int = 0
    ) -> InboxCounters {
        var next = counters
        if all {
            return .guestZero
        }
        if let tab {
            let current = next.unread(for: tab)
            if decreasingBy > 0 {
                next.setUnread(max(0, current - decreasingBy), for: tab)
            } else {
                next.setUnread(0, for: tab)
            }
        }
        return next
    }

    static func truncateTitle(_ s: String) -> String {
        truncate(s, max: NotifyConfigDefaults.titleMaxLen)
    }

    static func truncateBody(_ s: String) -> String {
        truncate(s, max: NotifyConfigDefaults.bodyMaxLen)
    }

    private static func truncate(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max))
    }

    /// APNs sound: `default` unless quiet hours mute for subscribe class.
    static func apnsSound(
        eventCode: NotificationEventCode,
        at date: Date = Date(),
        quietHours: QuietHours = .shanghaiNight
    ) -> String? {
        if quietHours.shouldMuteSound(eventCode: eventCode, at: date) {
            return nil
        }
        if eventCode.inboxOnlyDefault { return nil }
        return "default"
    }

    static func shouldSkipSystemPush(
        eventCode: NotificationEventCode,
        pushEnabled: Bool,
        userOnline: Bool,
        pushEvenWhenOnline: Bool
    ) -> Bool {
        if eventCode.inboxOnlyDefault { return true }
        if eventCode.skipsInboxTable && eventCode != .n23 { return true }
        if !pushEnabled { return true }
        if userOnline && !pushEvenWhenOnline { return true }
        return false
    }
}
