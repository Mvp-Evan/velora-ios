import Foundation

// MARK: - Proxy bid (DES-v1.3-03-04 AUC-14 / T-12 / N-32)

/// `proxy_bids.status` (design §3).
public enum ProxyBidStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case active
    case exceeded
    case cancelled
    case closed

    /// Buyer can raise max (active or exceeded → active).
    public var canRaise: Bool {
        switch self {
        case .active, .exceeded: return true
        case .cancelled, .closed: return false
        }
    }

    /// Buyer can cancel (active / exceeded → cancelled).
    public var canCancel: Bool {
        switch self {
        case .active, .exceeded: return true
        case .cancelled, .closed: return false
        }
    }

    public var displayLabel: String {
        switch self {
        case .active: return "代理中"
        case .exceeded: return "已被超过"
        case .cancelled: return "已取消"
        case .closed: return "已结束"
        }
    }
}

/// Stable proxy-bid API error codes (design §5.1 / §6).
public enum ProxyBidErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case proxyMaxTooLow = "proxy_max_too_low"
    case proxyCannotDecrease = "proxy_cannot_decrease"
    case proxyVersionConflict = "proxy_version_conflict"
    case proxyCrowd = "proxy_crowd"
    case featureDisabled = "feature_disabled"
    // Shared with PlaceBid engine
    case depositNotFrozen = "deposit_not_frozen"
    case ownLot = "own_lot"
    case relatedAccountForbidden = "related_account_forbidden"
    case auctionNotLive = "auction_not_live"
    case creditTooLow = "credit_too_low"
    case realNameRequired = "real_name_required"
    case accountRestricted = "account_restricted"
    case biddingBanned = "bidding_banned"
    case bidQueueBusy = "bid_queue_busy"
    case idempotencyInProgress = "idempotency_in_progress"
    case idempotencyConflict = "idempotency_conflict"
    case missingIdempotencyKey = "missing_idempotency_key"
    case invalidIdempotencyKey = "invalid_idempotency_key"
    case rateLimited = "rate_limited"
    case blockedBySeller = "blocked_by_seller"

    public var opensDepositSheet: Bool { self == .depositNotFrozen }
    public var opensRealName: Bool { self == .realNameRequired }

    public var retriesSameIdempotencyKey: Bool {
        switch self {
        case .bidQueueBusy, .idempotencyInProgress, .depositNotFrozen:
            return true
        default:
            return false
        }
    }

    public var shouldReloadProxy: Bool {
        switch self {
        case .proxyVersionConflict, .proxyMaxTooLow, .auctionNotLive:
            return true
        default:
            return false
        }
    }

    public var fallbackMessage: String {
        switch self {
        case .proxyMaxTooLow:
            return "最高价过低，请按加价幅度提高"
        case .proxyCannotDecrease:
            return "不可下调最高价，请先取消后再重新设置"
        case .proxyVersionConflict:
            return "代理出价已变更，请刷新后重试"
        case .proxyCrowd:
            return "该拍品代理人数已满，请稍后再试"
        case .featureDisabled:
            return "代理出价暂未开放"
        case .depositNotFrozen:
            return "请先缴纳竞拍押金"
        case .ownLot:
            return "不能对自己的拍品设置代理出价"
        case .relatedAccountForbidden, .blockedBySeller:
            return "暂不可对该拍品设置代理出价"
        case .auctionNotLive:
            return "拍卖未在进行中"
        case .creditTooLow:
            return "信用分不足，暂不可出价"
        case .realNameRequired:
            return "请先完成实名认证"
        case .accountRestricted, .biddingBanned:
            return "账号暂不可竞拍"
        case .bidQueueBusy, .idempotencyInProgress:
            return "竞拍火爆，请稍后再试"
        case .idempotencyConflict:
            return "请重新设置代理出价"
        case .missingIdempotencyKey, .invalidIdempotencyKey:
            return "请求无效，请重试"
        case .rateLimited:
            return "操作过于频繁，请稍后再试"
        }
    }
}

/// PUT `/lots/{id}/proxy-bid` body.
public struct ProxyBidPutRequest: Codable, Equatable, Sendable {
    public let maxAmount: Int64
    /// Optimistic concurrency (design §10); omit on first set.
    public let version: Int64?

    public init(maxAmount: Int64, version: Int64? = nil) {
        self.maxAmount = maxAmount
        self.version = version
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(maxAmount, forKey: .maxAmount)
        try c.encodeIfPresent(version, forKey: .version)
    }

    private enum CodingKeys: String, CodingKey {
        case maxAmount, version
    }
}

/// GET / PUT response — buyer self only (design §6). Never present on public lot detail.
public struct ProxyBidState: Codable, Equatable, Sendable {
    public let maxAmount: Int64
    public let maxAmountAligned: Int64
    public let status: ProxyBidStatus
    public let leading: Bool?
    public let currentPrice: Int64?
    public let minNextBid: Int64?
    public let endAt: Date?
    public let endAtVersion: Int?
    public let version: Int64?
    public let createdAt: Date?

    public init(
        maxAmount: Int64,
        maxAmountAligned: Int64,
        status: ProxyBidStatus,
        leading: Bool? = nil,
        currentPrice: Int64? = nil,
        minNextBid: Int64? = nil,
        endAt: Date? = nil,
        endAtVersion: Int? = nil,
        version: Int64? = nil,
        createdAt: Date? = nil
    ) {
        self.maxAmount = maxAmount
        self.maxAmountAligned = maxAmountAligned
        self.status = status
        self.leading = leading
        self.currentPrice = currentPrice
        self.minNextBid = minNextBid
        self.endAt = endAt
        self.endAtVersion = endAtVersion
        self.version = version
        self.createdAt = createdAt
    }

    /// Prefer server-aligned max for display.
    public var displayMaxFen: Int64 { maxAmountAligned > 0 ? maxAmountAligned : maxAmount }

    public var isActive: Bool { status == .active }
    public var isExceeded: Bool { status == .exceeded }
}

// MARK: - Client helpers (design §5.6 / §9)

public enum ProxyBidSuggest {
    /// Default input: `min_next` + 3 steps (design §5.6 「2–3 档之上」).
    public static let defaultStepsAboveMinNext = 3
    /// One-tap 「当前价 + 10 档」.
    public static let tenStepBoost = 10

    public static func defaultMaxFen(
        minNextBidFen: Int64,
        incrementFen: Int64,
        steps: Int = defaultStepsAboveMinNext
    ) -> Int64 {
        let inc = max(incrementFen, 1)
        return minNextBidFen + Int64(max(0, steps)) * inc
    }

    public static func plusTenStepsFen(
        currentPriceFen: Int64,
        incrementFen: Int64
    ) -> Int64 {
        let inc = max(incrementFen, 1)
        return currentPriceFen + Int64(tenStepBoost) * inc
    }
}

public enum ProxyBidCopy {
    public static let entrySet = "设置代理出价"
    public static let entryRaise = "提高最高价"
    public static let entryManage = "管理代理出价"
    public static let confirmTitle = "确认设置代理出价？"
    public static let confirmBody = "最高价对他人不可见；已出部分不可撤回。系统将按最小加价自动跟价。"
    public static let cancelTitle = "取消代理出价？"
    public static let cancelWhileLeading = "你仍领先，但取消后不会自动跟价。已出部分不会撤回。"
    public static let cancelBody = "取消后已出部分不会撤回，也不会再自动跟价。"
    public static let exceededHint = "代理已失效，可提高最高价"
    public static let leadingActiveHint = "当前由你领先，系统会按最小加价自动跟"
    public static let alignedHintPrefix = "最高可出"
    public static let privacyA11y = "最高价对他人不可见"
    public static let sheetTitle = "代理出价"
    public static let maxFieldLabel = "最高价"
    public static let plusTenSteps = "当前价 + 10 档"

    public static func alignedHint(maxFen: Int64) -> String {
        "\(alignedHintPrefix) \(BidIncrementLadder.yuanDisplay(maxFen))"
    }

    public static func activeBanner(maxFen: Int64, leading: Bool) -> String {
        if leading {
            return "\(leadingActiveHint)（最高 \(BidIncrementLadder.yuanDisplay(maxFen))）"
        }
        return "代理最高价 \(BidIncrementLadder.yuanDisplay(maxFen))（对他人保密）"
    }
}

/// Local pre-check before PUT (server remains source of truth).
public enum ProxyBidLocalValidation: Equatable, Sendable {
    case ok(alignedFen: Int64)
    case tooLow
    case cannotDecrease(oldMax: Int64)

    public static func validate(
        typedMaxFen: Int64,
        existing: ProxyBidState?,
        startPriceFen: Int64,
        currentPriceFen: Int64,
        bidCount: Int,
        sellerBidIncrementFen: Int64,
        tiers: [BidIncrementTier] = BidIncrementLadder.defaultTiers
    ) -> ProxyBidLocalValidation {
        guard let aligned = BidAmountGrid.alignDown(
            maxFen: typedMaxFen,
            startPriceFen: startPriceFen,
            currentPriceFen: currentPriceFen,
            bidCount: bidCount,
            sellerBidIncrementFen: sellerBidIncrementFen,
            tiers: tiers
        ) else {
            return .tooLow
        }
        if let existing, existing.status.canRaise {
            let old = existing.displayMaxFen
            if aligned < old {
                return .cannotDecrease(oldMax: old)
            }
            if aligned <= old {
                return .tooLow
            }
        }
        return .ok(alignedFen: aligned)
    }
}
