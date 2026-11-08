import XCTest
@testable import VeloraCore

final class HomeModelsTests: XCTestCase {
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

    func testFeedTabRawValues() {
        XCTAssertEqual(HomeFeedTab.follow.rawValue, "follow")
        XCTAssertEqual(HomeFeedTab.hot.rawValue, "hot")
        XCTAssertEqual(HomeFeedTab.new.rawValue, "new")
        XCTAssertEqual(HomeFeedTab.hot.title, "热门")
    }

    func testSlotLabelDisplayTextImmutable() {
        XCTAssertEqual(HomeSlotLabel.ad.displayText, "广告")
        XCTAssertEqual(HomeSlotLabel.recommend.displayText, "推荐")
    }

    func testFeedCardDecodeSuperset() throws {
        let json = """
        {
          "listing_id": 101,
          "lot_id": 55,
          "trade_type": "auction",
          "title": "RB19",
          "cover": "https://cdn.example/a.jpg",
          "condition": "near_mint",
          "seller_badge": "proxy_gold",
          "current_price": 128000,
          "bid_count": 8,
          "viewers": 42,
          "end_at": "2026-11-05T12:00:00Z",
          "listed_at": "2026-11-01T08:00:00Z",
          "price": null,
          "free_shipping": null,
          "negotiable": null,
          "release_mode": null,
          "release_status": null,
          "leak_badge": null
        }
        """.data(using: .utf8)!
        let card = try decoder.decode(HomeFeedCard.self, from: json)
        XCTAssertEqual(card.listingId, 101)
        XCTAssertEqual(card.lotId, 55)
        XCTAssertEqual(card.sellerBadge, .proxyGold)
        XCTAssertEqual(card.displayPrice, 128000)
        XCTAssertEqual(card.detailRouteId, 55)
        XCTAssertEqual(card.sellerBadge?.label, "金牌代拍")
    }

    func testFeedCardMissingCoverDefaultsEmpty() throws {
        let omitted = """
        {
          "listing_id": 202,
          "trade_type": "fixed",
          "title": "No cover field"
        }
        """.data(using: .utf8)!
        let card = try decoder.decode(HomeFeedCard.self, from: omitted)
        XCTAssertEqual(card.cover, "")
        XCTAssertEqual(card.listingId, 202)

        let nullCover = """
        {
          "listing_id": 203,
          "trade_type": "auction",
          "title": "Null cover",
          "cover": null
        }
        """.data(using: .utf8)!
        let nullCard = try decoder.decode(HomeFeedCard.self, from: nullCover)
        XCTAssertEqual(nullCard.cover, "")
    }

    func testFeedResponseDecode() throws {
        let json = """
        {
          "items": [],
          "next_cursor": "84.0000:101",
          "server_time": "2026-11-05T00:00:00Z",
          "feed_version": 3
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(HomeFeedResponse.self, from: json)
        XCTAssertEqual(resp.nextCursor, "84.0000:101")
        XCTAssertEqual(resp.feedVersion, 3)
        XCTAssertNotNil(resp.resolvedServerTimeMs)
    }

    func testSlotsDecodeAndExpireFilter() throws {
        let json = """
        {
          "banners": [
            {"id":1,"kind":"banner","label":"ad","bind_type":"listing","bind_id":9,"title":"Banner","cover":"c","end_at":"2099-01-01T00:00:00Z"}
          ],
          "cards": [
            {"id":2,"kind":"promo_card","label":"recommend","bind_type":"listing","bind_id":10,"rank":1,"end_at":"2000-01-01T00:00:00Z"}
          ],
          "sessions": [],
          "slot_config_version": 7,
          "request_id": "req-abc"
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(HomeSlotsResponse.self, from: json)
        XCTAssertEqual(resp.slotConfigVersion, 7)
        XCTAssertEqual(resp.requestId, "req-abc")
        let live = resp.filteringExpired(at: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(live.banners.count, 1)
        XCTAssertTrue(live.cards.isEmpty)
    }

    func testMergeSkipsAdjacentDuplicateListing() {
        let natural = [
            HomeFeedCard(listingId: 10, tradeType: "auction", title: "A", cover: "a"),
            HomeFeedCard(listingId: 11, tradeType: "auction", title: "B", cover: "b"),
            HomeFeedCard(listingId: 12, tradeType: "auction", title: "C", cover: "c"),
        ]
        let promos = [
            HomeSlotItem(id: 1, kind: .promoCard, label: .recommend, bindType: .listing, bindId: 10, rank: 1),
            HomeSlotItem(id: 2, kind: .promoCard, label: .ad, bindType: .listing, bindId: 99, rank: 2),
        ]
        let rows = HomeFeedComposer.merge(natural: natural, promos: promos)
        XCTAssertEqual(rows.count, natural.count + promos.count)
        XCTAssertTrue(rows.contains(.promo(promos[0])))
        XCTAssertTrue(rows.contains(.promo(promos[1])))
        // Promo for listing 10 must not sit immediately next to natural listing 10.
        let promo10Index = rows.firstIndex(of: .promo(promos[0]))
        let natural10Index = rows.firstIndex(of: .natural(natural[0]))
        XCTAssertNotNil(promo10Index)
        XCTAssertNotNil(natural10Index)
        if let p = promo10Index, let n = natural10Index {
            XCTAssertNotEqual(abs(p - n), 1)
        }
        // No two adjacent rows share the same listing id.
        for i in 1..<rows.count {
            if let a = rows[i - 1].listingId, let b = rows[i].listingId {
                XCTAssertNotEqual(a, b, "adjacent duplicate listing_id at \(i - 1)/\(i)")
            }
        }
    }

    func testTradeModeFilter() {
        let cards = [
            HomeFeedCard(listingId: 1, tradeType: "auction", title: "a", cover: "a"),
            HomeFeedCard(listingId: 2, tradeType: "fixed", title: "b", cover: "b"),
        ]
        XCTAssertEqual(HomeFeedComposer.filter(cards: cards, tradeMode: .all).count, 2)
        XCTAssertEqual(HomeFeedComposer.filter(cards: cards, tradeMode: .fixed).map(\.listingId), [2])
    }

    func testExposurePolicyConstants() {
        XCTAssertEqual(HomeExposurePolicy.minVisibleRatio, 0.5, accuracy: 0.001)
        XCTAssertEqual(HomeExposurePolicy.minVisibleMs, 1000)
        XCTAssertEqual(HomeExposurePolicy.maxBatchSize, 50)
    }

    func testPersonalBadgeOnlySemantics() {
        XCTAssertEqual(SellerBadge.personal.rawValue, "personal")
        XCTAssertEqual(SellerBadge.brandOfficial.label, "品牌官方")
    }

    func testExposuresRequestEncodeShape() throws {
        let req = HomeExposuresRequest(
            requestId: "r1",
            events: [HomeExposureEvent(slotId: 1, listingId: 9, event: .impression, visibleMs: 1200)],
            deviceId: "dev"
        )
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        let data = try enc.encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["request_id"] as? String, "r1")
        XCTAssertEqual(obj?["device_id"] as? String, "dev")
        let events = obj?["events"] as? [[String: Any]]
        XCTAssertEqual(events?.first?["event"] as? String, "impression")
        XCTAssertEqual(events?.first?["visible_ms"] as? Int, 1200)
    }
}
