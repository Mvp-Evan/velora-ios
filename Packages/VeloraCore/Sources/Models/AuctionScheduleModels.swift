import Foundation

// MARK: - Anti-snipe / closing remind / sessions (DES-v1.3-03-03 AUC-04/05/13)

/// Product invariants: window and extend amplitude are locked at 120s (design §3 / §13).
public enum AntiSnipeConfig {
    /// Seconds before `end_at` that trigger extension on a successful bid.
    public static let windowSeconds: Int = 120
    /// Seconds added to the **original** `end_at` (not `now + window`).
    public static let extendSeconds: Int = 120
    /// Closing remind fires at `end_at - remindBeforeSeconds` (AUC-13).
    public static let remindBeforeSeconds: Int = 300
    /// Default session daily lot cap (AUC-05).
    public static let sessionDailyCap: Int = 30
    /// Allowed `interval_seconds` inclusive range for sessions.
    public static let sessionIntervalRange: ClosedRange<Int> = 60...120
    /// `0` = unlimited extensions (server default).
    public static let defaultMaxExtensions: Int = 0
}

/// Pure client mirror of server `MaybeExtend` (design §5.1).
/// Mutates in-memory fields only; caller persists. Does **not** expose remaining extension budget.
public enum AntiSnipeLogic {
    public struct LotState: Equatable, Sendable {
        public var endAt: Date
        public var endAtVersion: Int
        public var extensionCount: Int
        public var antiSnipeSeconds: Int

        public init(
            endAt: Date,
            endAtVersion: Int = 1,
            extensionCount: Int = 0,
            antiSnipeSeconds: Int = AntiSnipeConfig.windowSeconds
        ) {
            self.endAt = endAt
            self.endAtVersion = endAtVersion
            self.extensionCount = extensionCount
            self.antiSnipeSeconds = antiSnipeSeconds
        }
    }

    /// Returns whether `end_at` was extended. `maxExtensions == 0` means unlimited.
    @discardableResult
    public static func maybeExtend(
        _ lot: inout LotState,
        now: Date,
        maxExtensions: Int = AntiSnipeConfig.defaultMaxExtensions
    ) -> Bool {
        var secs = lot.antiSnipeSeconds
        if secs <= 0 { secs = AntiSnipeConfig.windowSeconds }
        let remaining = lot.endAt.timeIntervalSince(now)
        if remaining < 0 || remaining > TimeInterval(secs) { return false }
        if maxExtensions > 0, lot.extensionCount >= maxExtensions { return false }
        lot.endAt = lot.endAt.addingTimeInterval(TimeInterval(secs))
        lot.antiSnipeSeconds = secs
        lot.extensionCount += 1
        if lot.endAtVersion < 1 { lot.endAtVersion = 1 }
        lot.endAtVersion += 1
        return true
    }

    /// `run_at` for `closing_remind` job = `end_at - 300s`.
    public static func closingRemindRunAt(endAt: Date) -> Date {
        endAt.addingTimeInterval(-TimeInterval(AntiSnipeConfig.remindBeforeSeconds))
    }
}

/// UX copy for delay toast / remind (design §9). Never mentions remaining extension count.
public enum AntiSnipeCopy {
    public static let extendToastTitle = "已延时 2 分钟"
    public static let extendToastSubtitlePrefix = "新的结束时间"
    public static let delayedBadge = "已延时"
    public static let closingRemindAction = "结拍提醒"
    public static let closingRemindSubscribed = "已订阅提醒"
    public static let closingRemindSuccess = "已订阅结拍提醒，结束前 5 分钟通知您"
    public static let sessionPreviewing = "预展中"
    public static let sessionClosingTonight = "今晚结拍"
    public static let sessionStaggerHint = "错峰结束"
    public static let sessionEmpty = "本场排期中"
    public static let sessionFullHint = "本场已满 30 件，请关注下一日专场"

    public static func extendToastSubtitle(endAtText: String) -> String {
        "\(extendToastSubtitlePrefix) \(endAtText)"
    }

    public static func remainingMinutesAccessibility(remain: TimeInterval) -> String {
        if remain <= 0 { return "已结束" }
        let mins = max(1, Int(ceil(remain / 60)))
        return "剩余 \(mins) 分钟"
    }
}

// MARK: - Session schedule math (AUC-05)

public enum AuctionSessionSchedule {
    /// Slot index is 1-based: `planned_end_at = first + (i-1)*interval`.
    public static func plannedEndAt(firstEndAt: Date, slotIndex: Int, intervalSeconds: Int) -> Date {
        let i = max(1, slotIndex)
        return firstEndAt.addingTimeInterval(TimeInterval((i - 1) * intervalSeconds))
    }

    public static func validateInterval(_ seconds: Int) -> Bool {
        AntiSnipeConfig.sessionIntervalRange.contains(seconds)
    }

    /// `close_date` must be Thursday…Sunday in the given calendar (design §5.5).
    public static func isValidCloseWeekday(_ date: Date, calendar: Calendar = .init(identifier: .gregorian)) -> Bool {
        let wd = calendar.component(.weekday, from: date) // 1=Sun … 7=Sat
        // Thu=5, Fri=6, Sat=7, Sun=1
        return wd == 5 || wd == 6 || wd == 7 || wd == 1
    }

    public static func wouldExceedDailyCap(existingCount: Int, adding: Int, cap: Int = AntiSnipeConfig.sessionDailyCap) -> Bool {
        existingCount + adding > cap
    }
}

// MARK: - Error codes (design §6)

public enum AuctionScheduleErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case sessionFull = "session_full"
    case intervalOutOfRange = "interval_out_of_range"
    case lotNotEligible = "lot_not_eligible"
    case cannotMoveLiveLot = "cannot_move_live_lot"
    case previewNotBiddable = "preview_not_biddable"
    case auctionNotLive = "auction_not_live"
    case invalidCloseDate = "invalid_close_date"

    public var fallbackMessage: String {
        switch self {
        case .sessionFull: return AntiSnipeCopy.sessionFullHint
        case .intervalOutOfRange: return "专场间隔须在 60–120 秒"
        case .lotNotEligible: return "该拍品不可加入专场"
        case .cannotMoveLiveLot: return "进行中的拍品不可前移结束时间"
        case .previewNotBiddable, .auctionNotLive: return "预展中，开拍后方可出价"
        case .invalidCloseDate: return "结拍日须为周四至周日"
        }
    }
}

// MARK: - DTOs

public enum AuctionSessionStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case draft
    case published
    case live
    case closed

    /// App calendar only shows non-draft sessions (design §5.5).
    public var visibleInAppCalendar: Bool { self != .draft }

    public var displayLabel: String {
        switch self {
        case .draft: return "草稿"
        case .published: return AntiSnipeCopy.sessionPreviewing
        case .live: return AntiSnipeCopy.sessionClosingTonight
        case .closed: return "已结束"
        }
    }
}

public struct AuctionSession: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public var name: String
    public var previewStartAt: Date?
    public var closeDate: Date?
    public var firstEndAt: Date?
    public var intervalSeconds: Int?
    public var dailyCap: Int?
    public var status: AuctionSessionStatus?
    public var lotCount: Int?
    public var subscribed: Bool?

    public init(
        id: Int64,
        name: String,
        previewStartAt: Date? = nil,
        closeDate: Date? = nil,
        firstEndAt: Date? = nil,
        intervalSeconds: Int? = nil,
        dailyCap: Int? = nil,
        status: AuctionSessionStatus? = nil,
        lotCount: Int? = nil,
        subscribed: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.previewStartAt = previewStartAt
        self.closeDate = closeDate
        self.firstEndAt = firstEndAt
        self.intervalSeconds = intervalSeconds
        self.dailyCap = dailyCap
        self.status = status
        self.lotCount = lotCount
        self.subscribed = subscribed
    }

    public var staggerHint: String? {
        guard let interval = intervalSeconds, interval > 0 else { return nil }
        return "\(AntiSnipeCopy.sessionStaggerHint) · 间隔 \(interval) 秒"
    }

    public var statusChip: String {
        status?.displayLabel ?? AntiSnipeCopy.sessionPreviewing
    }
}

public struct AuctionSessionLot: Codable, Equatable, Sendable, Identifiable, Hashable {
    public let lotId: Int64
    public var slotIndex: Int?
    public var plannedEndAt: Date?
    public var title: String?
    public var cover: String?
    public var status: String?
    public var currentPrice: Int64?
    public var endAt: Date?
    public var endAtVersion: Int?

    public var id: Int64 { lotId }

    public init(
        lotId: Int64,
        slotIndex: Int? = nil,
        plannedEndAt: Date? = nil,
        title: String? = nil,
        cover: String? = nil,
        status: String? = nil,
        currentPrice: Int64? = nil,
        endAt: Date? = nil,
        endAtVersion: Int? = nil
    ) {
        self.lotId = lotId
        self.slotIndex = slotIndex
        self.plannedEndAt = plannedEndAt
        self.title = title
        self.cover = cover
        self.status = status
        self.currentPrice = currentPrice
        self.endAt = endAt
        self.endAtVersion = endAtVersion
    }
}

/// `GET /api/v1/auction-sessions` week calendar payload.
public struct AuctionSessionCalendarResponse: Codable, Equatable, Sendable {
    public let items: [AuctionSession]
    public var weekStart: Date?
    public var weekEnd: Date?
    public var serverTime: Date?

    public init(
        items: [AuctionSession],
        weekStart: Date? = nil,
        weekEnd: Date? = nil,
        serverTime: Date? = nil
    ) {
        self.items = items
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.serverTime = serverTime
    }

    /// Prefer server week bounds; never invent a wrong local weekday for display labels.
    public var displaySessions: [AuctionSession] {
        items.filter { ($0.status ?? .published).visibleInAppCalendar }
    }
}

/// `GET /api/v1/auction-sessions/{id}` detail.
public struct AuctionSessionDetailResponse: Codable, Equatable, Sendable {
    public let session: AuctionSession
    public let lots: [AuctionSessionLot]

    public init(session: AuctionSession, lots: [AuctionSessionLot]) {
        self.session = session
        self.lots = lots
    }

    /// Lots ordered by `slot_index` ascending (design §6).
    public var lotsBySlot: [AuctionSessionLot] {
        lots.sorted { ($0.slotIndex ?? Int.max) < ($1.slotIndex ?? Int.max) }
    }
}

/// `POST /lots/{id}/remind` / `POST /auction-sessions/{id}/subscribe` success (idempotent 200).
public struct LotRemindResponse: Codable, Equatable, Sendable {
    public var subscribed: Bool?
    public var lotId: Int64?
    public var sessionId: Int64?

    public init(subscribed: Bool? = true, lotId: Int64? = nil, sessionId: Int64? = nil) {
        self.subscribed = subscribed
        self.lotId = lotId
        self.sessionId = sessionId
    }

    public var isSubscribed: Bool { subscribed ?? true }
}

/// WS / PlaceBid extend event fields used by room toast (design §5.1 broadcast).
public struct AuctionExtendedPayload: Codable, Equatable, Sendable {
    public var lotId: Int64?
    public var endAt: Date?
    public var extensionCount: Int?
    public var endAtVersion: Int?

    public init(
        lotId: Int64? = nil,
        endAt: Date? = nil,
        extensionCount: Int? = nil,
        endAtVersion: Int? = nil
    ) {
        self.lotId = lotId
        self.endAt = endAt
        self.extensionCount = extensionCount
        self.endAtVersion = endAtVersion
    }
}
