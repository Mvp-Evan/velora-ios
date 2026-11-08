import Foundation

// MARK: - DES-v1.3-02-03 list realtime + viewership (HOME-11 / T-11 / AUC-16)

/// Aggregated list tick (`lot_card_tick`). No reserve price / bidder identity.
public struct LotCardTick: Equatable, Sendable, Decodable {
    public let lotId: Int64
    public let currentPrice: Int64?
    public let bidCount: Int?
    public let endAt: Date?
    public let endAtVersion: Int?
    public let extensionCount: Int?
    public let delayed: Bool?
    public let status: String?
    public let viewers: Int?
    public let favoriteCount: Int?
    public let bidderCount: Int?
    public let serverTime: Int64?
    public let seq: Int64?

    public init(
        lotId: Int64,
        currentPrice: Int64? = nil,
        bidCount: Int? = nil,
        endAt: Date? = nil,
        endAtVersion: Int? = nil,
        extensionCount: Int? = nil,
        delayed: Bool? = nil,
        status: String? = nil,
        viewers: Int? = nil,
        favoriteCount: Int? = nil,
        bidderCount: Int? = nil,
        serverTime: Int64? = nil,
        seq: Int64? = nil
    ) {
        self.lotId = lotId
        self.currentPrice = currentPrice
        self.bidCount = bidCount
        self.endAt = endAt
        self.endAtVersion = endAtVersion
        self.extensionCount = extensionCount
        self.delayed = delayed
        self.status = status
        self.viewers = viewers
        self.favoriteCount = favoriteCount
        self.bidderCount = bidderCount
        self.serverTime = serverTime
        self.seq = seq
    }
}

public enum LotCardSubState: String, Equatable, Sendable {
    case unsubscribed
    case visiblePending = "visible_pending"
    case subscribed
    case stale
}

public enum LotCardSubscribePolicy {
    /// Visible area ≥50% of cell.
    public static let minVisibleRatio: Double = 0.5
    /// Drop below 10% → immediate unsubscribe.
    public static let unsubscribeRatio: Double = 0.1
    /// Continuous visibility before subscribe (ms).
    public static let minVisibleMs: Int = 300
    /// Max concurrent card subscriptions per WS connection.
    public static let maxSubscriptions: Int = 30
    /// Merge scroll bursts (ms).
    public static let debounceMs: Int = 200
    /// Viewer ZSET heartbeat interval (seconds).
    public static let heartbeatSeconds: Int = 15
    /// Weak-network: missing heartbeat for this long still receives ticks.
    public static let heartbeatGraceSeconds: Int = 45
    /// Scroll faster than 1 screen / 0.4s → treat as fling; wait to settle.
    public static let flingScreenDuration: TimeInterval = 0.4
    public static let bannerCountCap = 99

    public static let subscribeEvent = "subscribe_card"
    public static let unsubscribeEvent = "unsubscribe_card"
    public static let heartbeatEvent = "card_heartbeat"
    public static let tickEvent = "lot_card_tick"
    public static let nackEvent = "subscribe_card_nack"
}

/// Per-list `changed_end_ids` + banner copy (HOME-11). Independent across list instances.
public struct EndTimeChangeTracker: Equatable, Sendable {
    public private(set) var changedEndIds: Set<Int64> = []
    public private(set) var knownVersions: [Int64: Int] = [:]

    public init() {}

    public mutating func seed(lotId: Int64, version: Int?) {
        if let version { knownVersions[lotId] = version }
    }

    public mutating func seed(lots: [(Int64, Int?)]) {
        for (id, ver) in lots { seed(lotId: id, version: ver) }
    }

    /// Returns true when this lot newly joins the changed set (same version is ignored).
    @discardableResult
    public mutating func noteVersionChange(lotId: Int64, newVersion: Int?) -> Bool {
        guard let newVersion else { return false }
        let previous = knownVersions[lotId]
        knownVersions[lotId] = newVersion
        guard let previous, newVersion > previous else {
            // First sighting or equal/older — do not bump banner.
            return false
        }
        return changedEndIds.insert(lotId).inserted
    }

    public var count: Int { changedEndIds.count }

    public var bannerText: String {
        let n = count
        guard n > 0 else { return "" }
        let label = n > LotCardSubscribePolicy.bannerCountCap
            ? "\(LotCardSubscribePolicy.bannerCountCap)+"
            : "\(n)"
        return "\(label) 件拍品结束时间已变化，点击刷新"
    }

    public var showsBanner: Bool { count > 0 }

    public mutating func clear() {
        changedEndIds.removeAll()
    }

    /// Filter / tab change — drop pending rearrange hint.
    public mutating func clearForFilterChange() {
        changedEndIds.removeAll()
        knownVersions.removeAll()
    }
}

/// Visibility → subscribe set engine (pure; no WS I/O).
public struct LotCardVisibilityEngine: Equatable, Sendable {
    public private(set) var ratios: [Int64: Double] = [:]
    public private(set) var pendingSince: [Int64: Date] = [:]
    public private(set) var subscribed: Set<Int64> = []
    public private(set) var stale: Set<Int64> = []
    public private(set) var states: [Int64: LotCardSubState] = [:]
    /// Last accepted visible set after fling settle.
    public private(set) var isFlinging = false

    public init() {}

    public mutating func setFlinging(_ flinging: Bool) {
        isFlinging = flinging
        if flinging {
            // Cancel pending visibility timers while flinging.
            pendingSince.removeAll()
            for id in states.keys where states[id] == .visiblePending {
                states[id] = .unsubscribed
            }
        }
    }

    public mutating func updateRatio(lotId: Int64, ratio: Double, now: Date = Date()) {
        ratios[lotId] = ratio
        if ratio < LotCardSubscribePolicy.unsubscribeRatio {
            pendingSince[lotId] = nil
            if states[lotId] != .stale {
                states[lotId] = .unsubscribed
            }
            return
        }
        if ratio >= LotCardSubscribePolicy.minVisibleRatio {
            if subscribed.contains(lotId) || stale.contains(lotId) { return }
            if isFlinging { return }
            if pendingSince[lotId] == nil {
                pendingSince[lotId] = now
                states[lotId] = .visiblePending
            }
        } else {
            // Between 10% and 50%: keep current subscription, don't start pending.
            pendingSince[lotId] = nil
            if states[lotId] == .visiblePending {
                states[lotId] = .unsubscribed
            }
        }
    }

    public mutating func remove(lotId: Int64) {
        ratios[lotId] = nil
        pendingSince[lotId] = nil
        subscribed.remove(lotId)
        stale.remove(lotId)
        states[lotId] = nil
    }

    public mutating func markStale(lotId: Int64) {
        stale.insert(lotId)
        subscribed.remove(lotId)
        pendingSince[lotId] = nil
        states[lotId] = .stale
    }

    /// Desired subscription set after applying 300ms gate + 30 cap (keeps currently subscribed when possible).
    public mutating func desiredSubscriptions(now: Date = Date(), preferredOrder: [Int64] = []) -> Set<Int64> {
        guard !isFlinging else { return subscribed }

        var ready = subscribed
        let minVisible = TimeInterval(LotCardSubscribePolicy.minVisibleMs) / 1000
        for (id, start) in pendingSince {
            if now.timeIntervalSince(start) + 1e-9 >= minVisible,
               (ratios[id] ?? 0) >= LotCardSubscribePolicy.minVisibleRatio,
               !stale.contains(id) {
                ready.insert(id)
            }
        }
        // Drop ones no longer visible enough.
        ready = Set(ready.filter { id in
            if stale.contains(id) { return false }
            let r = ratios[id] ?? 0
            return r >= LotCardSubscribePolicy.unsubscribeRatio
        })

        if ready.count <= LotCardSubscribePolicy.maxSubscriptions {
            return ready
        }
        // Prefer preferredOrder (screen order), then already-subscribed, then id.
        let orderIndex = Dictionary(uniqueKeysWithValues: preferredOrder.enumerated().map { ($1, $0) })
        let ranked = ready.sorted { a, b in
            let ia = orderIndex[a] ?? Int.max
            let ib = orderIndex[b] ?? Int.max
            if ia != ib { return ia < ib }
            let sa = subscribed.contains(a)
            let sb = subscribed.contains(b)
            if sa != sb { return sa && !sb }
            return a < b
        }
        return Set(ranked.prefix(LotCardSubscribePolicy.maxSubscriptions))
    }

    /// Apply desired set; returns (toSubscribe, toUnsubscribe).
    public mutating func applyDesired(_ desired: Set<Int64>) -> (subscribe: [Int64], unsubscribe: [Int64]) {
        let toSub = desired.subtracting(subscribed).sorted()
        let toUnsub = subscribed.subtracting(desired).sorted()
        for id in toUnsub {
            subscribed.remove(id)
            if states[id] != .stale { states[id] = .unsubscribed }
            pendingSince[id] = nil
        }
        for id in toSub {
            subscribed.insert(id)
            states[id] = .subscribed
            pendingSince[id] = nil
        }
        return (toSub, toUnsub)
    }
}

/// Client-side live fields overlay for a list card (does not reorder).
public struct LotCardLiveFields: Equatable, Sendable {
    public var currentPrice: Int64?
    public var bidCount: Int?
    public var endAt: Date?
    public var endAtVersion: Int?
    public var extensionCount: Int?
    public var delayed: Bool
    public var status: String?
    public var viewers: Int?
    public var favoriteCount: Int?
    public var bidderCount: Int?
    public var lastSeq: Int64?

    public init(
        currentPrice: Int64? = nil,
        bidCount: Int? = nil,
        endAt: Date? = nil,
        endAtVersion: Int? = nil,
        extensionCount: Int? = nil,
        delayed: Bool = false,
        status: String? = nil,
        viewers: Int? = nil,
        favoriteCount: Int? = nil,
        bidderCount: Int? = nil,
        lastSeq: Int64? = nil
    ) {
        self.currentPrice = currentPrice
        self.bidCount = bidCount
        self.endAt = endAt
        self.endAtVersion = endAtVersion
        self.extensionCount = extensionCount
        self.delayed = delayed
        self.status = status
        self.viewers = viewers
        self.favoriteCount = favoriteCount
        self.bidderCount = bidderCount
        self.lastSeq = lastSeq
    }

    /// Apply tick; drops out-of-order `seq`. Returns whether end_at_version increased.
    @discardableResult
    public mutating func apply(_ tick: LotCardTick) -> Bool {
        if let seq = tick.seq, let last = lastSeq, seq < last {
            return false
        }
        if let seq = tick.seq { lastSeq = seq }

        var versionBumped = false
        if let v = tick.endAtVersion {
            if let old = endAtVersion, v > old { versionBumped = true }
            if endAtVersion == nil || v >= (endAtVersion ?? 0) {
                endAtVersion = v
            } else {
                // Older version — ignore end_at fields but still allow price if seq ok.
                return false
            }
        }

        if let p = tick.currentPrice { currentPrice = p }
        if let b = tick.bidCount { bidCount = b }
        if let e = tick.endAt { endAt = e }
        if let c = tick.extensionCount {
            if let old = extensionCount, c > old { delayed = true }
            extensionCount = c
        }
        if tick.delayed == true { delayed = true }
        if let s = tick.status { status = s }
        if let v = tick.viewers { viewers = v }
        if let f = tick.favoriteCount { favoriteCount = f }
        if let bc = tick.bidderCount { bidderCount = bc }
        return versionBumped
    }

    public var isTerminalStatus: Bool {
        guard let status else { return false }
        return status == "ended" || status == "unsold" || status == "cancelled"
    }
}

public enum LotCardHeatCopy {
    /// 「123 人围观 · 8 收藏 · 5 人出价」; viewers 0 → 「刚刚开始」.
    public static func line(viewers: Int?, favoriteCount: Int? = nil, bidderCount: Int? = nil) -> String {
        let v = viewers ?? 0
        if v <= 0 {
            return "刚刚开始"
        }
        var parts: [String] = ["\(v) 人围观"]
        if let f = favoriteCount { parts.append("\(f) 收藏") }
        if let b = bidderCount { parts.append("\(b) 人出价") }
        return parts.joined(separator: " · ")
    }

    public static let delayedBadge = "已延时"
    public static let endedBadge = "已结束"
    public static let offlineBanner = "实时已暂停"
    public static let realtimePaused = "实时已暂停"
}

/// Diff helpers for control-plane batching.
public enum LotCardSubscribeDiff {
    public static func compute(visible desired: Set<Int64>, subscribed: Set<Int64>) -> (subscribe: [Int64], unsubscribe: [Int64]) {
        (desired.subtracting(subscribed).sorted(), subscribed.subtracting(desired).sorted())
    }
}
