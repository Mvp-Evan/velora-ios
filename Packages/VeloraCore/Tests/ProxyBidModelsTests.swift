import XCTest
@testable import VeloraCore

final class ProxyBidModelsTests: XCTestCase {
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

    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: Decode / encode

    func testProxyBidStateDecodeSelfOnlyPayload() throws {
        let json = """
        {
          "max_amount": 101000,
          "max_amount_aligned": 100000,
          "status": "active",
          "leading": true,
          "current_price": 50000,
          "min_next_bid": 55000,
          "end_at": "2026-11-05T12:00:00Z",
          "end_at_version": 2,
          "version": 3
        }
        """.data(using: .utf8)!
        let state = try decoder.decode(ProxyBidState.self, from: json)
        XCTAssertEqual(state.maxAmount, 101_000)
        XCTAssertEqual(state.maxAmountAligned, 100_000)
        XCTAssertEqual(state.displayMaxFen, 100_000)
        XCTAssertEqual(state.status, .active)
        XCTAssertEqual(state.leading, true)
        XCTAssertEqual(state.currentPrice, 50_000)
        XCTAssertEqual(state.minNextBid, 55_000)
        XCTAssertEqual(state.endAtVersion, 2)
        XCTAssertEqual(state.version, 3)
        XCTAssertTrue(state.isActive)
    }

    func testProxyBidPutRequestEncodesMaxAndOptionalVersion() throws {
        let withVer = try encoder.encode(ProxyBidPutRequest(maxAmount: 200_000, version: 4))
        let obj = try JSONSerialization.jsonObject(with: withVer) as? [String: Any]
        XCTAssertEqual(obj?["max_amount"] as? Int, 200_000)
        XCTAssertEqual(obj?["version"] as? Int, 4)

        let first = try encoder.encode(ProxyBidPutRequest(maxAmount: 80_000))
        let firstObj = try JSONSerialization.jsonObject(with: first) as? [String: Any]
        XCTAssertEqual(firstObj?["max_amount"] as? Int, 80_000)
        XCTAssertNil(firstObj?["version"])
    }

    func testProxyBidStatusFlags() {
        XCTAssertTrue(ProxyBidStatus.active.canRaise)
        XCTAssertTrue(ProxyBidStatus.exceeded.canRaise)
        XCTAssertTrue(ProxyBidStatus.exceeded.canCancel)
        XCTAssertFalse(ProxyBidStatus.cancelled.canRaise)
        XCTAssertFalse(ProxyBidStatus.closed.canCancel)
        XCTAssertEqual(ProxyBidStatus.exceeded.displayLabel, "已被超过")
    }

    // MARK: Error codes

    func testProxyBidErrorCodeSemantics() {
        XCTAssertEqual(ProxyBidErrorCode.proxyCannotDecrease.rawValue, "proxy_cannot_decrease")
        XCTAssertTrue(ProxyBidErrorCode.depositNotFrozen.opensDepositSheet)
        XCTAssertTrue(ProxyBidErrorCode.bidQueueBusy.retriesSameIdempotencyKey)
        XCTAssertTrue(ProxyBidErrorCode.proxyVersionConflict.shouldReloadProxy)
        XCTAssertFalse(ProxyBidErrorCode.featureDisabled.retriesSameIdempotencyKey)
        XCTAssertFalse(ProxyBidErrorCode.proxyMaxTooLow.fallbackMessage.isEmpty)
    }

    // MARK: align_down (§5.2.1)

    func testAlignDownNoBidsIncludesStart() {
        // start 500, inc 50; max 800 → 800; max 1010 with start 1000? use fen
        // current 0 bids, start 50_000 (¥500), inc 5_000, max 80_000 → 80_000
        XCTAssertEqual(
            BidAmountGrid.alignDown(
                maxFen: 80_000,
                startPriceFen: 50_000,
                currentPriceFen: 50_000,
                bidCount: 0,
                sellerBidIncrementFen: 5_000
            ),
            80_000
        )
        // max == start is legal on first set
        XCTAssertEqual(
            BidAmountGrid.alignDown(
                maxFen: 50_000,
                startPriceFen: 50_000,
                currentPriceFen: 50_000,
                bidCount: 0,
                sellerBidIncrementFen: 5_000
            ),
            50_000
        )
        // design example: max 1010 yuan with grid 50 → write 1000 (fen: 101_000 → 100_000)
        // start 100_000, bidCount 0, inc 5_000 → legal 100000, 105000, …
        XCTAssertEqual(
            BidAmountGrid.alignDown(
                maxFen: 101_000,
                startPriceFen: 100_000,
                currentPriceFen: 100_000,
                bidCount: 0,
                sellerBidIncrementFen: 5_000
            ),
            100_000
        )
    }

    func testAlignDownWithBidsFloorsToGrid() {
        // current 1000, inc 50 → min_next 1050; max 1010 → nil (< min_next)
        XCTAssertNil(
            BidAmountGrid.alignDown(
                maxFen: 101_000,
                startPriceFen: 100_000,
                currentPriceFen: 100_000,
                bidCount: 1,
                sellerBidIncrementFen: 5_000
            )
        )
        // max 1123 → floor to 1100 (n=2)
        XCTAssertEqual(
            BidAmountGrid.alignDown(
                maxFen: 112_300,
                startPriceFen: 100_000,
                currentPriceFen: 100_000,
                bidCount: 1,
                sellerBidIncrementFen: 5_000
            ),
            110_000
        )
        // large max — no n≤20 cap (unlike manual snap)
        let far = 100_000 + Int64(40) * 5_000
        XCTAssertEqual(
            BidAmountGrid.alignDown(
                maxFen: far + 2_500,
                startPriceFen: 100_000,
                currentPriceFen: 100_000,
                bidCount: 1,
                sellerBidIncrementFen: 5_000
            ),
            far
        )
    }

    func testAlignDownRejectsBelowMinNext() {
        XCTAssertNil(
            BidAmountGrid.alignDown(
                maxFen: 100_000,
                startPriceFen: 100_000,
                currentPriceFen: 100_000,
                bidCount: 1,
                sellerBidIncrementFen: 5_000
            )
        )
    }

    // MARK: Suggest + local validation

    func testSuggestDefaultAndTenSteps() {
        XCTAssertEqual(
            ProxyBidSuggest.defaultMaxFen(minNextBidFen: 105_000, incrementFen: 5_000),
            105_000 + 3 * 5_000
        )
        XCTAssertEqual(
            ProxyBidSuggest.plusTenStepsFen(currentPriceFen: 100_000, incrementFen: 5_000),
            150_000
        )
    }

    func testLocalValidationRaiseAndDecrease() {
        let existing = ProxyBidState(
            maxAmount: 150_000,
            maxAmountAligned: 150_000,
            status: .active
        )
        // decrease → cannotDecrease
        let down = ProxyBidLocalValidation.validate(
            typedMaxFen: 120_000,
            existing: existing,
            startPriceFen: 100_000,
            currentPriceFen: 100_000,
            bidCount: 1,
            sellerBidIncrementFen: 5_000
        )
        XCTAssertEqual(down, .cannotDecrease(oldMax: 150_000))

        // raise aligned equal after floor → tooLow
        let same = ProxyBidLocalValidation.validate(
            typedMaxFen: 152_000,
            existing: existing,
            startPriceFen: 100_000,
            currentPriceFen: 100_000,
            bidCount: 1,
            sellerBidIncrementFen: 5_000
        )
        // 152000 floors to 150000 → not greater
        XCTAssertEqual(same, .tooLow)

        let up = ProxyBidLocalValidation.validate(
            typedMaxFen: 200_000,
            existing: existing,
            startPriceFen: 100_000,
            currentPriceFen: 100_000,
            bidCount: 1,
            sellerBidIncrementFen: 5_000
        )
        XCTAssertEqual(up, .ok(alignedFen: 200_000))

        // first set too low
        let low = ProxyBidLocalValidation.validate(
            typedMaxFen: 90_000,
            existing: nil,
            startPriceFen: 100_000,
            currentPriceFen: 100_000,
            bidCount: 1,
            sellerBidIncrementFen: 5_000
        )
        XCTAssertEqual(low, .tooLow)
    }

    func testCopyHelpers() {
        XCTAssertEqual(ProxyBidCopy.entrySet, "设置代理出价")
        XCTAssertTrue(ProxyBidCopy.alignedHint(maxFen: 100_000).contains("¥1000") || ProxyBidCopy.alignedHint(maxFen: 100_000).contains("1000"))
        XCTAssertTrue(ProxyBidCopy.activeBanner(maxFen: 200_000, leading: true).contains("领先"))
        XCTAssertEqual(ProxyBidCopy.exceededHint, "代理已失效，可提高最高价")
    }
}
