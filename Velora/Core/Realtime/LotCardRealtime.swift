import Foundation

// MARK: - DES-v1.3-02-03 list realtime (app mirror of VeloraCore)

struct LotCardTick: Equatable {
    let lotId: Int64
    var currentPrice: Money?
    var bidCount: Int?
    var endAt: Date?
    var endAtVersion: Int?
    var extensionCount: Int?
    var delayed: Bool?
    var status: String?
    var viewers: Int?
    var favoriteCount: Int?
    var bidderCount: Int?
    var serverTime: Int64?
    var seq: Int64?

    init(
        lotId: Int64,
        currentPrice: Money? = nil,
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

    static func from(event ev: WSEvent) -> LotCardTick? {
        guard let lotId = ev.lotId ?? ev.int64("lot_id") else { return nil }
        return LotCardTick(
            lotId: lotId,
            currentPrice: ev.int64("current_price") ?? ev.int64("amount"),
            bidCount: ev.int64("bid_count").map(Int.init),
            endAt: ev.date("end_at"),
            endAtVersion: ev.int64("end_at_version").map(Int.init),
            extensionCount: ev.int64("extension_count").map(Int.init),
            delayed: ev.data["delayed"]?.value as? Bool,
            status: ev.string("status"),
            viewers: ev.int64("viewers").map(Int.init),
            favoriteCount: ev.int64("favorite_count").map(Int.init),
            bidderCount: ev.int64("bidder_count").map(Int.init),
            serverTime: ev.int64("server_time"),
            seq: ev.int64("seq")
        )
    }
}

enum LotCardSubState: String {
    case unsubscribed, visiblePending = "visible_pending", subscribed, stale
}

enum LotCardSubscribePolicy {
    static let minVisibleRatio: Double = 0.5
    static let unsubscribeRatio: Double = 0.1
    static let minVisibleMs: Int = 300
    static let maxSubscriptions: Int = 30
    static let debounceMs: Int = 200
    static let heartbeatSeconds: Int = 15
    static let flingScreenDuration: TimeInterval = 0.4
    static let bannerCountCap = 99

    static let subscribeEvent = "subscribe_card"
    static let unsubscribeEvent = "unsubscribe_card"
    static let heartbeatEvent = "card_heartbeat"
    static let tickEvent = "lot_card_tick"
    static let nackEvent = "subscribe_card_nack"
}

struct EndTimeChangeTracker: Equatable {
    private(set) var changedEndIds: Set<Int64> = []
    private(set) var knownVersions: [Int64: Int] = [:]

    mutating func seed(lotId: Int64, version: Int?) {
        if let version { knownVersions[lotId] = version }
    }

    @discardableResult
    mutating func noteVersionChange(lotId: Int64, newVersion: Int?) -> Bool {
        guard let newVersion else { return false }
        let previous = knownVersions[lotId]
        knownVersions[lotId] = newVersion
        guard let previous, newVersion > previous else { return false }
        return changedEndIds.insert(lotId).inserted
    }

    var count: Int { changedEndIds.count }

    var bannerText: String {
        let n = count
        guard n > 0 else { return "" }
        let label = n > LotCardSubscribePolicy.bannerCountCap
            ? "\(LotCardSubscribePolicy.bannerCountCap)+"
            : "\(n)"
        return "\(label) 件拍品结束时间已变化，点击刷新"
    }

    var showsBanner: Bool { count > 0 }

    mutating func clear() { changedEndIds.removeAll() }

    mutating func clearForFilterChange() {
        changedEndIds.removeAll()
        knownVersions.removeAll()
    }
}

struct LotCardVisibilityEngine: Equatable {
    private(set) var ratios: [Int64: Double] = [:]
    private(set) var pendingSince: [Int64: Date] = [:]
    private(set) var subscribed: Set<Int64> = []
    private(set) var stale: Set<Int64> = []
    private(set) var states: [Int64: LotCardSubState] = [:]
    private(set) var isFlinging = false

    mutating func setFlinging(_ flinging: Bool) {
        isFlinging = flinging
        if flinging {
            pendingSince.removeAll()
            for id in states.keys where states[id] == .visiblePending {
                states[id] = .unsubscribed
            }
        }
    }

    mutating func updateRatio(lotId: Int64, ratio: Double, now: Date = Date()) {
        ratios[lotId] = ratio
        if ratio < LotCardSubscribePolicy.unsubscribeRatio {
            pendingSince[lotId] = nil
            if states[lotId] != .stale { states[lotId] = .unsubscribed }
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
            pendingSince[lotId] = nil
            if states[lotId] == .visiblePending { states[lotId] = .unsubscribed }
        }
    }

    mutating func remove(lotId: Int64) {
        ratios[lotId] = nil
        pendingSince[lotId] = nil
        subscribed.remove(lotId)
        stale.remove(lotId)
        states[lotId] = nil
    }

    mutating func markStale(lotId: Int64) {
        stale.insert(lotId)
        subscribed.remove(lotId)
        pendingSince[lotId] = nil
        states[lotId] = .stale
    }

    mutating func desiredSubscriptions(now: Date = Date(), preferredOrder: [Int64] = []) -> Set<Int64> {
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
        ready = Set(ready.filter { id in
            if stale.contains(id) { return false }
            return (ratios[id] ?? 0) >= LotCardSubscribePolicy.unsubscribeRatio
        })
        if ready.count <= LotCardSubscribePolicy.maxSubscriptions { return ready }
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

    mutating func applyDesired(_ desired: Set<Int64>) -> (subscribe: [Int64], unsubscribe: [Int64]) {
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

    mutating func resetSubscriptionsKeepingStale() {
        let keepStale = stale
        subscribed.removeAll()
        pendingSince.removeAll()
        for id in states.keys where !keepStale.contains(id) {
            states[id] = .unsubscribed
        }
    }
}

struct LotCardLiveFields: Equatable {
    var currentPrice: Money?
    var bidCount: Int?
    var endAt: Date?
    var endAtVersion: Int?
    var extensionCount: Int?
    var delayed: Bool = false
    var status: String?
    var viewers: Int?
    var favoriteCount: Int?
    var bidderCount: Int?
    var lastSeq: Int64?

    @discardableResult
    mutating func apply(_ tick: LotCardTick) -> Bool {
        if let seq = tick.seq, let last = lastSeq, seq < last { return false }
        if let seq = tick.seq { lastSeq = seq }

        var versionBumped = false
        if let v = tick.endAtVersion {
            if let old = endAtVersion, v > old { versionBumped = true }
            if endAtVersion == nil || v >= (endAtVersion ?? 0) {
                endAtVersion = v
            } else {
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

    var isTerminalStatus: Bool {
        guard let status else { return false }
        return status == "ended" || status == "unsold" || status == "cancelled"
    }
}

enum LotCardHeatCopy {
    static func line(viewers: Int?, favoriteCount: Int? = nil, bidderCount: Int? = nil) -> String {
        let v = viewers ?? 0
        if v <= 0 { return "刚刚开始" }
        var parts: [String] = ["\(v) 人围观"]
        if let f = favoriteCount { parts.append("\(f) 收藏") }
        if let b = bidderCount { parts.append("\(b) 人出价") }
        return parts.joined(separator: " · ")
    }

    static let delayedBadge = "已延时"
    static let endedBadge = "已结束"
    static let offlineBanner = "实时已暂停"
}
