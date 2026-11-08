import XCTest
@testable import VeloraCore

final class BidEngineModelsTests: XCTestCase {
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let dt = withFrac.date(from: s) { return dt }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let dt = plain.date(from: s) { return dt }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    // MARK: Request / response decode

    func testPlaceBidRequestEncodesAmount() throws {
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        let data = try enc.encode(PlaceBidRequest(amount: 110_000))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["amount"] as? Int, 110_000)
    }

    func testPlaceBidResponseDecodesSeqAndNested() throws {
        let json = """
        {
          "lot": {
            "id": 42,
            "status": "live",
            "current_price": 110000,
            "bid_count": 2,
            "end_at": "2026-11-05T12:00:00Z",
            "end_at_version": 3,
            "min_next_bid": 115000,
            "has_reserve": true,
            "reserve_met": false,
            "seq": 7,
            "current_bidder_id": 9
          },
          "bid": {
            "id": 1001,
            "lot_id": 42,
            "bidder_id": 9,
            "amount": 110000,
            "seq": 7,
            "source": "manual",
            "created_at": "2026-11-05T11:59:50Z",
            "leading": true
          },
          "seq": 7,
          "min_next_bid": 115000,
          "end_at": "2026-11-05T12:00:00Z",
          "extended": true
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(PlaceBidResponse.self, from: json)
        XCTAssertEqual(resp.seq, 7)
        XCTAssertEqual(resp.effectiveSeq, 7)
        XCTAssertEqual(resp.minNextBid, 115_000)
        XCTAssertEqual(resp.extended, true)
        XCTAssertEqual(resp.bid?.id, 1001)
        XCTAssertEqual(resp.bid?.seq, 7)
        XCTAssertEqual(resp.lot?.seq, 7)
        XCTAssertEqual(resp.lot?.endAtVersion, 3)
        XCTAssertEqual(resp.lot?.currentPrice, 110_000)
    }

    func testPlaceBidResponseEffectiveSeqFallsBackToBid() throws {
        let json = """
        {"bid":{"id":1,"amount":10000,"seq":4},"min_next_bid":11000}
        """.data(using: .utf8)!
        let resp = try decoder.decode(PlaceBidResponse.self, from: json)
        XCTAssertNil(resp.seq)
        XCTAssertEqual(resp.effectiveSeq, 4)
    }

    func testBidLotSnapshotDecode() throws {
        let json = """
        {
          "id": 5,
          "status": "live",
          "current_price": 50000,
          "bid_count": 1,
          "seq": 1,
          "min_next_bid": 55000,
          "end_at_version": 1
        }
        """.data(using: .utf8)!
        let snap = try decoder.decode(BidLotSnapshot.self, from: json)
        XCTAssertEqual(snap.seq, 1)
        XCTAssertEqual(snap.minNextBid, 55_000)
    }

    // MARK: Error codes

    func testBidErrorCodeSemantics() {
        XCTAssertTrue(BidErrorCode.depositNotFrozen.opensDepositSheet)
        XCTAssertTrue(BidErrorCode.depositNotFrozen.retriesSameIdempotencyKey)
        XCTAssertTrue(BidErrorCode.bidQueueBusy.retriesSameIdempotencyKey)
        XCTAssertEqual(BidErrorCode.bidQueueBusy.rawValue, "bid_queue_busy")
        XCTAssertTrue(BidErrorCode.bidAmountInvalid.shouldRefreshSnapshot)
        XCTAssertEqual(BidErrorCode.missingIdempotencyKey.rawValue, "missing_idempotency_key")
    }

    // MARK: Seq gate

    func testBidSeqGateIgnoresStaleAndEqual() {
        var gate = BidSeqGate(lastSeq: 5)
        XCTAssertFalse(gate.shouldApply(3))
        XCTAssertFalse(gate.shouldApply(5))
        XCTAssertTrue(gate.shouldApply(6))
        XCTAssertTrue(gate.shouldApply(nil))

        XCTAssertFalse(gate.note(4))
        XCTAssertEqual(gate.lastSeq, 5)
        XCTAssertFalse(gate.note(5))
        XCTAssertTrue(gate.note(8))
        XCTAssertEqual(gate.lastSeq, 8)
    }

    func testBidSeqGateAlignSnapshot() {
        var gate = BidSeqGate(lastSeq: 2)
        gate.align(toSnapshotSeq: 10)
        XCTAssertEqual(gate.lastSeq, 10)
        // Behind snapshot local is not rolled back by older snapshot
        gate.align(toSnapshotSeq: 7)
        XCTAssertEqual(gate.lastSeq, 10)
    }

    // MARK: Idempotency session

    func testStickyIdempotencyKeyReusedForSameAmount() {
        var session = BidIdempotencySession()
        var generated = 0
        let k1 = session.keyForAttempt(amountFen: 100) {
            generated += 1
            return "AAAA-1111"
        }
        let k2 = session.keyForAttempt(amountFen: 100) {
            generated += 1
            return "BBBB-2222"
        }
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1, "AAAA-1111")
        XCTAssertEqual(generated, 1)

        let k3 = session.keyForAttempt(amountFen: 200) {
            generated += 1
            return "CCCC-3333"
        }
        XCTAssertEqual(k3, "CCCC-3333")
        XCTAssertEqual(generated, 2)
    }

    func testQueueRetryBudget() {
        var session = BidIdempotencySession()
        _ = session.keyForAttempt(amountFen: 1) { "K" }
        XCTAssertTrue(session.consumeQueueRetry())
        XCTAssertTrue(session.consumeQueueRetry())
        XCTAssertTrue(session.consumeQueueRetry())
        XCTAssertFalse(session.consumeQueueRetry())
        session.clear()
        XCTAssertNil(session.key)
        XCTAssertEqual(session.queueRetries, 0)
    }

    // MARK: Amount grid / n≤20

    func testJumpNAndMaxN() {
        // current 1000, inc 50 → 1100 is n=2
        XCTAssertEqual(
            BidAmountGrid.jumpN(
                amountFen: 110_000,
                startPriceFen: 100_000,
                currentPriceFen: 100_000,
                bidCount: 1,
                sellerBidIncrementFen: 5_000
            ),
            2
        )
        XCTAssertTrue(
            BidAmountGrid.isAcceptable(
                amountFen: 110_000,
                startPriceFen: 100_000,
                currentPriceFen: 100_000,
                bidCount: 1,
                sellerBidIncrementFen: 5_000
            )
        )
        // 1049 元 off-grid
        XCTAssertFalse(
            BidAmountGrid.isAcceptable(
                amountFen: 104_900,
                startPriceFen: 100_000,
                currentPriceFen: 100_000,
                bidCount: 1,
                sellerBidIncrementFen: 5_000
            )
        )
        // n=21 rejected
        let tooFar = 100_000 + Int64(21) * 5_000
        XCTAssertFalse(
            BidAmountGrid.isAcceptable(
                amountFen: tooFar,
                startPriceFen: 100_000,
                currentPriceFen: 100_000,
                bidCount: 1,
                sellerBidIncrementFen: 5_000
            )
        )
        XCTAssertEqual(
            BidAmountGrid.jumpN(
                amountFen: tooFar,
                startPriceFen: 100_000,
                currentPriceFen: 100_000,
                bidCount: 1,
                sellerBidIncrementFen: 5_000
            ),
            21
        )
    }

    func testSnapToGrid() {
        let snapped = BidAmountGrid.snapToGrid(
            amountFen: 104_900,
            startPriceFen: 100_000,
            currentPriceFen: 100_000,
            bidCount: 1,
            sellerBidIncrementFen: 5_000
        )
        // floor to n=0 relative → minNext = 105000
        XCTAssertEqual(snapped, 105_000)

        let mid = BidAmountGrid.snapToGrid(
            amountFen: 112_300,
            startPriceFen: 100_000,
            currentPriceFen: 100_000,
            bidCount: 1,
            sellerBidIncrementFen: 5_000
        )
        XCTAssertEqual(mid, 110_000)
    }
}
