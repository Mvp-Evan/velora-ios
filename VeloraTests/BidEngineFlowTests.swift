import XCTest
@testable import Velora

/// Thin app-target checks for D13 bid flow helpers (heavier coverage in VeloraCore).
final class BidEngineFlowTests: XCTestCase {
    func testBidSeqGateIgnoresStale() {
        var gate = BidSeqGate(lastSeq: 4)
        XCTAssertFalse(gate.shouldApply(4))
        XCTAssertTrue(gate.note(5))
        XCTAssertEqual(gate.lastSeq, 5)
    }

    func testStickyKeyReusableForDepositRetry() {
        var session = BidIdempotencySession()
        let k = session.keyForAttempt(amountFen: 50_000) { "sticky-uuid" }
        XCTAssertEqual(session.keyForAttempt(amountFen: 50_000) { "other" }, k)
        XCTAssertTrue(BidErrorCode.depositNotFrozen.retriesSameIdempotencyKey)
        XCTAssertTrue(BidErrorCode.bidQueueBusy.retriesSameIdempotencyKey)
    }

    func testPostBidSendsExplicitIdempotencyKey() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }

        var seenKey: String?
        StubURLProtocol.handler = { request in
            seenKey = request.value(forHTTPHeaderField: "Idempotency-Key")
            let body = """
            {
              "data":{
                "lot":{
                  "id":1,"seller_id":2,"title":"t","description":"","images":[],"category":"","brand":"",
                  "scale":"","series":"","condition":"","box_status":"","location":"",
                  "start_price":10000,"deposit_amount":1000,"bid_increment":1000,
                  "current_price":10000,"bid_count":1,
                  "start_at":"2026-11-05T00:00:00Z","end_at":"2026-11-05T01:00:00Z",
                  "duration_seconds":3600,"anti_snipe_seconds":120,"extension_count":0,
                  "status":"live","follow_count":0,"view_count":0,"created_at":"2026-11-05T00:00:00Z",
                  "seller":{"id":2,"nickname":"s","avatar":"","credit_score":100,"sold_count":0,"won_count":0,"lot_count":0},
                  "cover":"","display_price":10000,"min_next_bid":11000,"is_following":false,
                  "my_bid":{"has_bid":true,"leading":true,"max_amount":10000},
                  "has_reserve":false,"reserve_met":false,"seq":1
                },
                "bid":{
                  "id":9,"lot_id":1,"bidder_id":3,"amount":10000,
                  "created_at":"2026-11-05T00:01:00Z","leading":true,"seq":1
                },
                "seq":1,"min_next_bid":11000,"extended":false
              },
              "error":null
            }
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = APIClient(session: session)

        let r: API.BidResponse = try await client.request(
            .POST,
            "lots/1/bids",
            body: .json(JSONDict(["amount": Int64(10_000)])),
            auth: false,
            idempotencyKey: "explicit-bid-key-0001"
        )
        XCTAssertEqual(seenKey, "explicit-bid-key-0001")
        XCTAssertEqual(r.effectiveSeq, 1)
        XCTAssertEqual(r.minNextBid, 11_000)
    }
}

// Local stub (mirrors IdempotencyKeyHTTPTests) — fileprivate types cannot cross files.
private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    static private(set) var lastMethod: String?

    static func reset() {
        handler = nil
        lastMethod = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        Self.lastMethod = request.httpMethod
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
