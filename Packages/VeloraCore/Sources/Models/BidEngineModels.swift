import Foundation

// MARK: - Bid engine (DES-v1.3-03-02 AUC-07/08)

/// Stable PlaceBid / auction-room error codes (design §5.1).
public enum BidErrorCode: String, Codable, Sendable, CaseIterable, Equatable {
    case missingIdempotencyKey = "missing_idempotency_key"
    case invalidIdempotencyKey = "invalid_idempotency_key"
    case idempotencyConflict = "idempotency_conflict"
    case idempotencyInProgress = "idempotency_in_progress"
    case realNameRequired = "real_name_required"
    case accountRestricted = "account_restricted"
    case biddingBanned = "bidding_banned"
    case creditTooLow = "credit_too_low"
    case depositNotFrozen = "deposit_not_frozen"
    case ownLot = "own_lot"
    case relatedAccountForbidden = "related_account_forbidden"
    case blockedBySeller = "blocked_by_seller"
    case auctionNotLive = "auction_not_live"
    case bidAmountInvalid = "bid_amount_invalid"
    case bidAmountAbnormal = "bid_amount_abnormal"
    case bidJumpTooLarge = "bid_jump_too_large"
    case alreadyLeading = "already_leading"
    case bidQueueBusy = "bid_queue_busy"
    case rateLimited = "rate_limited"
    /// Legacy server code prior to exact grid matching.
    case bidTooLow = "bid_too_low"

    public var opensDepositSheet: Bool { self == .depositNotFrozen }
    public var opensRealName: Bool { self == .realNameRequired }
    public var shouldRefreshSnapshot: Bool {
        switch self {
        case .auctionNotLive, .bidAmountInvalid, .bidTooLow, .bidJumpTooLarge:
            return true
        default:
            return false
        }
    }

    /// Same Idempotency-Key may be retried (design §5.3 / §9 / NFR-01).
    public var retriesSameIdempotencyKey: Bool {
        switch self {
        case .bidQueueBusy, .idempotencyInProgress, .depositNotFrozen:
            return true
        default:
            return false
        }
    }
}

/// POST `/lots/{id}/bids` body.
public struct PlaceBidRequest: Codable, Equatable, Sendable {
    public let amount: Int64

    public init(amount: Int64) {
        self.amount = amount
    }
}

/// Nested bid row returned from PlaceBid / bid list (subset used by clients).
public struct BidRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public let lotId: Int64?
    public let bidderId: Int64?
    public let amount: Int64
    public let seq: Int64?
    public let source: String?
    public let createdAt: Date?
    public let leading: Bool?

    public init(
        id: Int64,
        lotId: Int64? = nil,
        bidderId: Int64? = nil,
        amount: Int64,
        seq: Int64? = nil,
        source: String? = nil,
        createdAt: Date? = nil,
        leading: Bool? = nil
    ) {
        self.id = id
        self.lotId = lotId
        self.bidderId = bidderId
        self.amount = amount
        self.seq = seq
        self.source = source
        self.createdAt = createdAt
        self.leading = leading
    }
}

/// PlaceBid success payload (design §6): `{lot,bid,seq,min_next_bid,end_at,extended}`.
public struct PlaceBidResponse: Codable, Equatable, Sendable {
    public let seq: Int64?
    public let minNextBid: Int64?
    public let endAt: Date?
    public let extended: Bool?
    public let bid: BidRecord?
    /// Opaque lot object — keep as optional so tests can decode without full Lot schema.
    public let lot: BidLotSnapshot?

    public init(
        seq: Int64? = nil,
        minNextBid: Int64? = nil,
        endAt: Date? = nil,
        extended: Bool? = nil,
        bid: BidRecord? = nil,
        lot: BidLotSnapshot? = nil
    ) {
        self.seq = seq
        self.minNextBid = minNextBid
        self.endAt = endAt
        self.extended = extended
        self.bid = bid
        self.lot = lot
    }

    /// Effective room sequence after a successful place (response `seq` or nested bid/lot).
    public var effectiveSeq: Int64? {
        seq ?? bid?.seq ?? lot?.seq
    }
}

/// Lot snapshot fields used for reconnect alignment (design §5.5).
public struct BidLotSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: Int64
    public var status: String?
    public var currentPrice: Int64?
    public var bidCount: Int?
    public var endAt: Date?
    public var endAtVersion: Int?
    public var minNextBid: Int64?
    public var hasReserve: Bool?
    public var reserveMet: Bool?
    public var seq: Int64?
    public var currentBidderId: Int64?
    public var extensionCount: Int?

    public init(
        id: Int64,
        status: String? = nil,
        currentPrice: Int64? = nil,
        bidCount: Int? = nil,
        endAt: Date? = nil,
        endAtVersion: Int? = nil,
        minNextBid: Int64? = nil,
        hasReserve: Bool? = nil,
        reserveMet: Bool? = nil,
        seq: Int64? = nil,
        currentBidderId: Int64? = nil,
        extensionCount: Int? = nil
    ) {
        self.id = id
        self.status = status
        self.currentPrice = currentPrice
        self.bidCount = bidCount
        self.endAt = endAt
        self.endAtVersion = endAtVersion
        self.minNextBid = minNextBid
        self.hasReserve = hasReserve
        self.reserveMet = reserveMet
        self.seq = seq
        self.currentBidderId = currentBidderId
        self.extensionCount = extensionCount
    }
}

/// Optional error hints when amount is off-grid (design §5.1 `bid_amount_invalid`).
public struct BidAmountInvalidHint: Codable, Equatable, Sendable {
    public let minNextBid: Int64?
    public let increment: Int64?
    public let nHint: Int?

    public init(minNextBid: Int64? = nil, increment: Int64? = nil, nHint: Int? = nil) {
        self.minNextBid = minNextBid
        self.increment = increment
        self.nHint = nHint
    }
}

// MARK: - Seq gate (AUC-08)

/// Per-lot monotonic bid sequence. Ignore WS / stale events when `incoming <= local`.
public struct BidSeqGate: Equatable, Sendable {
    public private(set) var lastSeq: Int64

    public init(lastSeq: Int64 = 0) {
        self.lastSeq = max(0, lastSeq)
    }

    /// Whether an event/snapshot with `seq` should be applied.
    public func shouldApply(_ seq: Int64?) -> Bool {
        guard let seq else { return true }
        return seq > lastSeq
    }

    /// Advance local cursor when applying a fresher seq. Returns false if ignored.
    @discardableResult
    public mutating func note(_ seq: Int64?) -> Bool {
        guard let seq else { return true }
        guard seq > lastSeq else { return false }
        lastSeq = seq
        return true
    }

    /// Snapshot wins on reconnect when server is ahead (design §5.5 step 4).
    public mutating func align(toSnapshotSeq seq: Int64?) {
        guard let seq else { return }
        if seq >= lastSeq { lastSeq = seq }
    }
}

// MARK: - Idempotency sticky key (design §5.3 / §9)

/// Holds one sticky UUID per in-flight place-bid attempt so deposit / queue retries reuse the key.
public struct BidIdempotencySession: Equatable, Sendable {
    public var key: String?
    public var amountFen: Int64?
    public var queueRetries: Int

    public static let maxQueueRetries = 3

    public init(key: String? = nil, amountFen: Int64? = nil, queueRetries: Int = 0) {
        self.key = key
        self.amountFen = amountFen
        self.queueRetries = queueRetries
    }

    public mutating func keyForAttempt(
        amountFen: Int64,
        generate: () -> String
    ) -> String {
        if let key, self.amountFen == amountFen {
            return key
        }
        let fresh = generate()
        self.key = fresh
        self.amountFen = amountFen
        self.queueRetries = 0
        return fresh
    }

    public mutating func clear() {
        key = nil
        amountFen = nil
        queueRetries = 0
    }

    /// Returns whether another automatic same-key retry is allowed for `bid_queue_busy`.
    public mutating func consumeQueueRetry() -> Bool {
        guard queueRetries < Self.maxQueueRetries else { return false }
        queueRetries += 1
        return true
    }
}

// MARK: - Grid / jump helpers (ties to AUC-03 MinNextBid)

public enum BidAmountGrid {
    /// Max `n` for `current + n×increment` (design §5.2).
    public static let maxN = 20

    public static func jumpN(
        amountFen: Int64,
        startPriceFen: Int64,
        currentPriceFen: Int64,
        bidCount: Int,
        sellerBidIncrementFen: Int64,
        tiers: [BidIncrementTier] = BidIncrementLadder.defaultTiers
    ) -> Int? {
        let priceForLadder = bidCount == 0 ? startPriceFen : currentPriceFen
        let inc = BidIncrementLadder.effectiveIncrement(
            sellerBidIncrementFen: sellerBidIncrementFen,
            currentPriceFen: priceForLadder,
            tiers: tiers
        )
        guard inc > 0 else { return nil }
        if bidCount == 0 {
            if amountFen == startPriceFen { return 0 }
            let delta = amountFen - startPriceFen
            guard delta > 0, delta % inc == 0 else { return nil }
            return Int(delta / inc)
        }
        let delta = amountFen - currentPriceFen
        guard delta > 0, delta % inc == 0 else { return nil }
        return Int(delta / inc)
    }

    public static func isAcceptable(
        amountFen: Int64,
        startPriceFen: Int64,
        currentPriceFen: Int64,
        bidCount: Int,
        sellerBidIncrementFen: Int64,
        tiers: [BidIncrementTier] = BidIncrementLadder.defaultTiers
    ) -> Bool {
        guard BidIncrementLadder.isValidBidAmount(
            amountFen: amountFen,
            startPriceFen: startPriceFen,
            currentPriceFen: currentPriceFen,
            bidCount: bidCount,
            sellerBidIncrementFen: sellerBidIncrementFen,
            tiers: tiers
        ) else { return false }
        guard let n = jumpN(
            amountFen: amountFen,
            startPriceFen: startPriceFen,
            currentPriceFen: currentPriceFen,
            bidCount: bidCount,
            sellerBidIncrementFen: sellerBidIncrementFen,
            tiers: tiers
        ) else { return false }
        return n <= maxN
    }

    /// Snap typed amount down to the nearest legal grid ≥ minNext (or minNext if below).
    public static func snapToGrid(
        amountFen: Int64,
        startPriceFen: Int64,
        currentPriceFen: Int64,
        bidCount: Int,
        sellerBidIncrementFen: Int64,
        tiers: [BidIncrementTier] = BidIncrementLadder.defaultTiers
    ) -> Int64 {
        let minNext = BidIncrementLadder.minNextBid(
            startPriceFen: startPriceFen,
            currentPriceFen: currentPriceFen,
            bidCount: bidCount,
            sellerBidIncrementFen: sellerBidIncrementFen,
            tiers: tiers
        )
        if amountFen <= minNext { return minNext }
        let priceForLadder = bidCount == 0 ? startPriceFen : currentPriceFen
        let inc = BidIncrementLadder.effectiveIncrement(
            sellerBidIncrementFen: sellerBidIncrementFen,
            currentPriceFen: priceForLadder,
            tiers: tiers
        )
        guard inc > 0 else { return minNext }
        let base = bidCount == 0 ? startPriceFen : currentPriceFen
        let delta = amountFen - base
        let n = max(1, min(maxN, Int(delta / inc)))
        let snapped = base + Int64(n) * inc
        return max(minNext, snapped)
    }

    /// Floor `maxFen` to the largest legal bid grid ≤ max (DES-v1.3-03-04 §5.2.1).
    /// No jump-cap — proxy max may sit many steps above current. Returns nil when max < min_next.
    public static func alignDown(
        maxFen: Int64,
        startPriceFen: Int64,
        currentPriceFen: Int64,
        bidCount: Int,
        sellerBidIncrementFen: Int64,
        tiers: [BidIncrementTier] = BidIncrementLadder.defaultTiers
    ) -> Int64? {
        let minNext = BidIncrementLadder.minNextBid(
            startPriceFen: startPriceFen,
            currentPriceFen: currentPriceFen,
            bidCount: bidCount,
            sellerBidIncrementFen: sellerBidIncrementFen,
            tiers: tiers
        )
        guard maxFen >= minNext else { return nil }
        let priceForLadder = bidCount == 0 ? startPriceFen : currentPriceFen
        let inc = BidIncrementLadder.effectiveIncrement(
            sellerBidIncrementFen: sellerBidIncrementFen,
            currentPriceFen: priceForLadder,
            tiers: tiers
        )
        guard inc > 0 else { return nil }
        if bidCount == 0 {
            // Legal set: {start} ∪ {start + n×inc}
            if maxFen == startPriceFen { return startPriceFen }
            let delta = maxFen - startPriceFen
            let n = delta / inc
            let aligned = startPriceFen + n * inc
            return aligned >= minNext ? aligned : nil
        }
        // Legal set: {current + n×inc}, n ≥ 1
        let delta = maxFen - currentPriceFen
        let n = delta / inc
        guard n >= 1 else { return nil }
        let aligned = currentPriceFen + n * inc
        return aligned >= minNext ? aligned : nil
    }
}
