import Foundation

// MARK: - Auction kind (DES-v1.3-03-01 AUC-01)

/// Lot `auction_kind` values. Personal sellers are forced to `.personal`.
public enum AuctionKind: String, Codable, Sendable, CaseIterable, Equatable {
    case personal
    case proxySession = "proxy_session"
    case proxyFree = "proxy_free"
    case brandSpecial = "brand_special"

    public var label: String {
        switch self {
        case .personal: return "个人拍卖"
        case .proxySession: return "申请专场"
        case .proxyFree: return "自由结拍"
        case .brandSpecial: return "特殊号"
        }
    }

    public var shortHint: String {
        switch self {
        case .personal: return "个人自由结拍，不进专场"
        case .proxySession: return "由运营排期入专场，本单可不写结束时间"
        case .proxyFree: return "代拍自由结拍，无首页专场标识"
        case .brandSpecial: return "限量编号发售，须填写特殊号"
        }
    }

    public var requiresEditionNo: Bool { self == .brandSpecial }
    public var allowsSession: Bool { self == .proxySession || self == .brandSpecial }
    public var usesFreeEndSchedule: Bool {
        self == .personal || self == .proxyFree
    }
}

/// Seller identity used to resolve allowed `auction_kind` values (AUC-01).
public enum AuctionSellerType: String, Codable, Sendable, CaseIterable, Equatable {
    case personal
    case proxyAgent = "proxy_agent"
    case brand

    public init(raw: String?) {
        switch raw {
        case "proxy_agent": self = .proxyAgent
        case "brand": self = .brand
        default: self = .personal
        }
    }

    public var allowedAuctionKinds: [AuctionKind] {
        switch self {
        case .personal: return [.personal]
        case .proxyAgent: return [.proxySession, .proxyFree]
        case .brand: return [.brandSpecial]
        }
    }

    public var defaultAuctionKind: AuctionKind {
        allowedAuctionKinds[0]
    }

    /// Whether the publish UI should show an auction-kind control.
    public var showsAuctionKindPicker: Bool {
        switch self {
        case .personal: return false
        case .proxyAgent, .brand: return true
        }
    }
}

public enum AuctionKindResolver {
    public static func resolve(sellerTypeRaw: String?, preferred: String?) -> AuctionKind {
        let seller = AuctionSellerType(raw: sellerTypeRaw)
        let allowed = seller.allowedAuctionKinds
        if let preferred, let kind = AuctionKind(rawValue: preferred), allowed.contains(kind) {
            return kind
        }
        return seller.defaultAuctionKind
    }

    public static func isAllowed(_ kind: AuctionKind, sellerTypeRaw: String?) -> Bool {
        AuctionSellerType(raw: sellerTypeRaw).allowedAuctionKinds.contains(kind)
    }
}

// MARK: - Bid increment tiers (AUC-03)

/// One ladder band. `maxPriceFen == nil` means open-ended (≥ min).
public struct BidIncrementTier: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(minPriceFen)-\(maxPriceFen.map(String.init) ?? "inf")" }
    public let minPriceFen: Int64
    public let maxPriceFen: Int64?
    public let minIncrementFen: Int64

    public init(minPriceFen: Int64, maxPriceFen: Int64?, minIncrementFen: Int64) {
        self.minPriceFen = minPriceFen
        self.maxPriceFen = maxPriceFen
        self.minIncrementFen = minIncrementFen
    }

    public func contains(priceFen: Int64) -> Bool {
        if priceFen < minPriceFen { return false }
        if let max = maxPriceFen { return priceFen <= max }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case minPriceFen, maxPriceFen, minIncrementFen
        case min, max, inc
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let min = try c.decodeIfPresent(Int64.self, forKey: .minPriceFen) {
            minPriceFen = min
            maxPriceFen = try c.decodeIfPresent(Int64.self, forKey: .maxPriceFen)
            minIncrementFen = try c.decode(Int64.self, forKey: .minIncrementFen)
        } else {
            // Snapshot / compact shape: {min,max,inc}
            minPriceFen = try c.decode(Int64.self, forKey: .min)
            maxPriceFen = try c.decodeIfPresent(Int64.self, forKey: .max)
            minIncrementFen = try c.decode(Int64.self, forKey: .inc)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(minPriceFen, forKey: .minPriceFen)
        try c.encodeIfPresent(maxPriceFen, forKey: .maxPriceFen)
        try c.encode(minIncrementFen, forKey: .minIncrementFen)
    }
}

/// `GET /api/v1/meta/bid-increments` payload.
public struct BidIncrementTiersResponse: Codable, Equatable, Sendable {
    public let version: Int
    public let tiers: [BidIncrementTier]
    public let effectiveAt: Date?

    public init(version: Int, tiers: [BidIncrementTier], effectiveAt: Date? = nil) {
        self.version = version
        self.tiers = tiers
        self.effectiveAt = effectiveAt
    }
}

/// Locked ladder snapshot stored on the lot after first bid.
public struct BidIncrementLadderSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let tiers: [BidIncrementTier]

    public init(version: Int, tiers: [BidIncrementTier]) {
        self.version = version
        self.tiers = tiers
    }
}

/// Pure ladder helpers shared by publish preview and bid engine clients (DES §5.3 / §15).
public enum BidIncrementLadder {
    /// Default 8.2 ladder (fen) — also used when meta API is unreachable.
    public static let defaultTiers: [BidIncrementTier] = [
        BidIncrementTier(minPriceFen: 0, maxPriceFen: 49_900, minIncrementFen: 1_000),
        BidIncrementTier(minPriceFen: 50_000, maxPriceFen: 199_900, minIncrementFen: 5_000),
        BidIncrementTier(minPriceFen: 200_000, maxPriceFen: 499_900, minIncrementFen: 10_000),
        BidIncrementTier(minPriceFen: 500_000, maxPriceFen: 1_999_900, minIncrementFen: 20_000),
        BidIncrementTier(minPriceFen: 2_000_000, maxPriceFen: nil, minIncrementFen: 50_000),
    ]

    public static let defaultVersion = 1

    public static var defaultResponse: BidIncrementTiersResponse {
        BidIncrementTiersResponse(version: defaultVersion, tiers: defaultTiers)
    }

    public static func minIncrement(forPriceFen priceFen: Int64, tiers: [BidIncrementTier] = defaultTiers) -> Int64 {
        for t in tiers where t.contains(priceFen: priceFen) {
            return t.minIncrementFen
        }
        return tiers.first?.minIncrementFen ?? 1_000
    }

    /// `effective_inc = max(lot.bid_increment, ladder(current_price))`.
    public static func effectiveIncrement(
        sellerBidIncrementFen: Int64,
        currentPriceFen: Int64,
        tiers: [BidIncrementTier] = defaultTiers
    ) -> Int64 {
        max(sellerBidIncrementFen, minIncrement(forPriceFen: currentPriceFen, tiers: tiers))
    }

    /// Minimum acceptable next bid amount (DES §5.3 `MinNextBid`).
    public static func minNextBid(
        startPriceFen: Int64,
        currentPriceFen: Int64,
        bidCount: Int,
        sellerBidIncrementFen: Int64,
        tiers: [BidIncrementTier] = defaultTiers
    ) -> Int64 {
        let price = bidCount == 0 ? startPriceFen : currentPriceFen
        let inc = effectiveIncrement(
            sellerBidIncrementFen: sellerBidIncrementFen,
            currentPriceFen: price,
            tiers: tiers
        )
        if bidCount == 0 { return startPriceFen }
        return currentPriceFen + inc
    }

    /// Whether `amountFen` is a legal bid under the n×increment rule.
    public static func isValidBidAmount(
        amountFen: Int64,
        startPriceFen: Int64,
        currentPriceFen: Int64,
        bidCount: Int,
        sellerBidIncrementFen: Int64,
        tiers: [BidIncrementTier] = defaultTiers
    ) -> Bool {
        let priceForLadder = bidCount == 0 ? startPriceFen : currentPriceFen
        let inc = effectiveIncrement(
            sellerBidIncrementFen: sellerBidIncrementFen,
            currentPriceFen: priceForLadder,
            tiers: tiers
        )
        guard inc > 0 else { return false }
        if bidCount == 0 {
            if amountFen == startPriceFen { return true }
            let delta = amountFen - startPriceFen
            return delta > 0 && delta % inc == 0
        }
        let delta = amountFen - currentPriceFen
        return delta > 0 && delta % inc == 0
    }

    public static func validateSellerIncrement(
        incrementFen: Int64,
        startPriceFen: Int64,
        tiers: [BidIncrementTier] = defaultTiers
    ) -> PublishErrorCode? {
        let floor = minIncrement(forPriceFen: startPriceFen, tiers: tiers)
        if incrementFen < floor { return .incrementBelowTier }
        return nil
    }

    public static func yuanDisplay(_ fen: Int64) -> String {
        if fen % 100 == 0 { return "¥\(fen / 100)" }
        return String(format: "¥%.2f", Double(fen) / 100)
    }

    public static func tierHint(forPriceFen priceFen: Int64, tiers: [BidIncrementTier] = defaultTiers) -> String {
        let min = minIncrement(forPriceFen: priceFen, tiers: tiers)
        return "当前档最小加价 \(yuanDisplay(min))"
    }
}

// MARK: - Duration codes (AUC-06)

public enum AuctionDurationCode: String, Codable, Sendable, CaseIterable, Equatable {
    case d1 = "1d"
    case d3 = "3d"
    case d5 = "5d"
    case d7 = "7d"

    public var days: Int {
        switch self {
        case .d1: return 1
        case .d3: return 3
        case .d5: return 5
        case .d7: return 7
        }
    }

    public var label: String { "\(days) 天" }

    public static func from(days: Int) -> AuctionDurationCode? {
        allCases.first { $0.days == days }
    }

    public static let whitelistDays: [Int] = allCases.map(\.days)
}

// MARK: - Deposit preview (AUC-02 / 8.3)

public enum AuctionDepositFormula {
    public static let rateBp = 1_000 // 10%
    public static let minFen: Int64 = 5_000
    public static let maxFen: Int64 = 200_000
    /// Seller may raise up to 2× system max by default.
    public static let sellerRaiseCapMultiplier: Int64 = 2

    /// `sys = clamp(start × rate_bp / 10000, min, max)` (integer fen math).
    public static func systemFloor(startPriceFen: Int64) -> Int64 {
        let raw = startPriceFen * Int64(rateBp) / 10_000
        return min(maxFen, max(minFen, raw))
    }

    public static func validate(depositFen: Int64, startPriceFen: Int64) -> PublishErrorCode? {
        let floor = systemFloor(startPriceFen: startPriceFen)
        if depositFen < floor { return .depositBelowFloor }
        return nil
    }

    public static func sellerRaiseCap(startPriceFen: Int64) -> Int64 {
        let floor = systemFloor(startPriceFen: startPriceFen)
        return max(floor, maxFen * sellerRaiseCapMultiplier)
    }

    public static func previewCopy(startPriceFen: Int64?) -> String {
        guard let start = startPriceFen, start > 0 else {
            return "系统保证金 = 起拍×10%，限制 50–2000 元；卖家只可上调"
        }
        let floor = systemFloor(startPriceFen: start)
        return "系统保证金 \(BidIncrementLadder.yuanDisplay(floor))（起拍×10%，50–2000 元，可上调）"
    }
}

// MARK: - Live publish tips (DES §9)

public struct PublishAuctionLiveTips: Equatable, Sendable {
    public let depositTip: String
    public let incrementTip: String
    public let durationTip: String
    public let earliestEndAt: Date
    public let estimatedEndAt: Date?
    public let durationOK: Bool
    public let incrementOK: Bool
    public let depositOK: Bool

    public var allOK: Bool { durationOK && incrementOK && depositOK }

    public static func make(
        startPriceFen: Int64?,
        incrementFen: Int64?,
        depositFen: Int64?,
        durationDays: Int,
        useCustomEndAt: Bool,
        endAt: Date,
        auctionKind: AuctionKind = .personal,
        now: Date = Date(),
        tiers: [BidIncrementTier] = BidIncrementLadder.defaultTiers
    ) -> PublishAuctionLiveTips {
        let earliest = now.addingTimeInterval(PublishLimits.minEndAfterPublishSeconds)
        let estimated: Date? = {
            guard auctionKind.usesFreeEndSchedule else { return nil }
            if useCustomEndAt { return endAt }
            return now.addingTimeInterval(TimeInterval(durationDays) * 86_400)
        }()

        let depositTip = AuctionDepositFormula.previewCopy(startPriceFen: startPriceFen)

        let incrementTip: String
        let incrementOK: Bool
        if let start = startPriceFen, start > 0 {
            let floor = BidIncrementLadder.minIncrement(forPriceFen: start, tiers: tiers)
            if let inc = incrementFen {
                if inc < floor {
                    incrementTip = "加价幅度不可低于当前档 \(BidIncrementLadder.yuanDisplay(floor))"
                    incrementOK = false
                } else {
                    incrementTip = "当前档最小加价 \(BidIncrementLadder.yuanDisplay(floor))，你已设 \(BidIncrementLadder.yuanDisplay(inc))"
                    incrementOK = true
                }
            } else {
                incrementTip = "当前档最小加价 \(BidIncrementLadder.yuanDisplay(floor))"
                incrementOK = false
            }
        } else {
            incrementTip = "填写起拍价后显示当前档最小加价"
            incrementOK = false
        }

        let durationTip: String
        let durationOK: Bool
        if !auctionKind.usesFreeEndSchedule {
            durationTip = "专场结束时间由运营排期，提交后等待通知"
            durationOK = true
        } else if let end = estimated {
            if end < earliest {
                let fmt = DateFormatter()
                fmt.locale = Locale(identifier: "zh_CN")
                fmt.dateFormat = "M月d日 HH:mm"
                durationTip = "结束时间须 ≥ 发布后 24 小时（最早 \(fmt.string(from: earliest))）"
                durationOK = false
            } else if end.timeIntervalSince(now) > PublishLimits.personalMaxEndSeconds {
                durationTip = "自由结拍最长 \(PublishLimits.personalMaxDays) 天"
                durationOK = false
            } else {
                let fmt = DateFormatter()
                fmt.locale = Locale(identifier: "zh_CN")
                fmt.dateFormat = "M月d日 HH:mm"
                durationTip = "预计结束 \(fmt.string(from: end))（须 ≥24h，≤\(PublishLimits.personalMaxDays) 天）"
                durationOK = true
            }
        } else {
            durationTip = "请选择 1/3/5/7 天或指定结束时间"
            durationOK = false
        }

        let depositOK: Bool = {
            guard let start = startPriceFen, start > 0 else { return false }
            let floor = AuctionDepositFormula.systemFloor(startPriceFen: start)
            let value = depositFen ?? floor
            return AuctionDepositFormula.validate(depositFen: value, startPriceFen: start) == nil
        }()

        return PublishAuctionLiveTips(
            depositTip: depositTip,
            incrementTip: incrementTip,
            durationTip: durationTip,
            earliestEndAt: earliest,
            estimatedEndAt: estimated,
            durationOK: durationOK,
            incrementOK: incrementOK,
            depositOK: depositOK
        )
    }
}
