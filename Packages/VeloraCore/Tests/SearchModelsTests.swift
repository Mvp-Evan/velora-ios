import XCTest
@testable import VeloraCore

final class SearchModelsTests: XCTestCase {
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

    func testEndingWithinAndSortRawValues() {
        XCTAssertEqual(EndingWithin.oneHour.rawValue, "1h")
        XCTAssertEqual(EndingWithin.tonight.rawValue, "tonight")
        XCTAssertEqual(EndingWithin.twentyFourHours.rawValue, "24h")
        XCTAssertEqual(ListingSearchSort.endingSoon.rawValue, "ending_soon")
        XCTAssertEqual(ListingSearchSort.comprehensive.title, "综合")
    }

    func testFilterConflictSoldAndEnding() {
        var q = ListingSearchQuery(endingWithin: .oneHour, sold: true)
        XCTAssertEqual(ListingSearchValidator.validate(q), .filterConflict)
        q.applySoldTab(true)
        XCTAssertNil(q.endingWithin)
        XCTAssertEqual(q.sold, true)
        XCTAssertNil(ListingSearchValidator.validate(q))
    }

    func testInvalidPriceRange() {
        let q = ListingSearchQuery(priceMin: 20000, priceMax: 10000)
        XCTAssertEqual(ListingSearchValidator.validate(q), .invalidPriceRange)
    }

    func testQueryItemsOmitEmptyAndCapPageSize() {
        let q = ListingSearchQuery(
            q: "EMP",
            endingWithin: .twentyFourHours,
            maxBidCount: 1,
            noReserve: true,
            sort: .endingSoon,
            page: 2,
            pageSize: 99
        )
        let items = q.queryItems
        XCTAssertEqual(items["q"]!, "EMP")
        XCTAssertEqual(items["ending_within"]!, "24h")
        XCTAssertEqual(items["max_bid_count"]!, "1")
        XCTAssertEqual(items["no_reserve"]!, "true")
        XCTAssertEqual(items["page_size"]!, "50")
        XCTAssertEqual(items["sold"]!, nil)
    }

    func testLeakBadgePolicyNoReserveAlone() {
        let now = Date()
        let end = now.addingTimeInterval(3600)
        XCTAssertTrue(LeakBadgePolicy.shouldShow(endAt: end, now: now, bidCount: 0))
        XCTAssertTrue(LeakBadgePolicy.shouldShow(endAt: end, now: now, bidCount: 1))
        XCTAssertFalse(LeakBadgePolicy.shouldShow(endAt: end, now: now, bidCount: 5))
        XCTAssertFalse(LeakBadgePolicy.shouldShow(endAt: now.addingTimeInterval(48 * 3600), now: now, bidCount: 0))
    }

    func testContactGuardPhoneAndWechat() {
        XCTAssertTrue(SearchContactGuard.containsContactInfo("微信号: alice_88"))
        XCTAssertTrue(SearchContactGuard.containsContactInfo("13812345678"))
        XCTAssertFalse(SearchContactGuard.containsContactInfo("EMP"))
        XCTAssertFalse(SearchContactGuard.containsContactInfo("Make Up"))
        XCTAssertFalse(SearchContactGuard.containsContactInfo("128000"))
        XCTAssertEqual(SearchContactGuard.validateShortcutWord("微信 wxid_abc12"), .contactInfoForbidden)
    }

    func testShortcutUpsertLimit12() {
        var resp = UserShortcutsResponse()
        for i in 0..<12 {
            XCTAssertNil(resp.upsert("词\(i)"))
        }
        XCTAssertEqual(resp.words.count, 12)
        XCTAssertEqual(resp.upsert("第13"), .shortcutLimitExceeded)
    }

    func testSearchListingCardDecodeSold() throws {
        let json = """
        {
          "listing_id": 9,
          "lot_id": null,
          "trade_type": "fixed",
          "title": "议价成交样例",
          "cover": "https://cdn.example/x.jpg",
          "price": 88000,
          "sold_price_public": 88000,
          "sold_at": "2026-11-01T12:00:00Z",
          "leak_badge": null,
          "has_reserve": false
        }
        """.data(using: .utf8)!
        let card = try decoder.decode(SearchListingCard.self, from: json)
        XCTAssertEqual(card.listingId, 9)
        XCTAssertEqual(card.soldPricePublic, 88000)
        XCTAssertEqual(card.soldPriceLabel, "标价")
        XCTAssertEqual(card.displayPrice, 88000)
        XCTAssertNil(card.leakBadge)
    }

    func testSearchListingCardDecodeListingIdFallback() throws {
        let json = """
        {
          "id": 42,
          "trade_type": "auction",
          "title": "RB19",
          "images": ["https://cdn.example/a.jpg"],
          "current_price": 150000,
          "bid_count": 0,
          "end_at": "2026-11-05T12:00:00Z",
          "leak_badge": "捡漏",
          "has_reserve": true
        }
        """.data(using: .utf8)!
        let card = try decoder.decode(SearchListingCard.self, from: json)
        XCTAssertEqual(card.listingId, 42)
        XCTAssertEqual(card.cover, "https://cdn.example/a.jpg")
        XCTAssertEqual(card.leakBadge, "捡漏")
        XCTAssertEqual(card.hasReserve, true)
        XCTAssertEqual(card.soldPriceLabel, "成交价")
    }

    func testHotWordsFallbackAndDecode() throws {
        XCTAssertEqual(HotWordsResponse.presetFallback.items.first?.word, "EMP")
        let json = #"{"items":[{"word":"BBR","weight":10,"locked":true}]}"#.data(using: .utf8)!
        let resp = try decoder.decode(HotWordsResponse.self, from: json)
        XCTAssertEqual(resp.items.count, 1)
        XCTAssertEqual(resp.items[0].locked, true)
    }

    func testSavedSearchDecodeFiltersAlias() throws {
        let json = """
        {
          "id": 3,
          "query": "EMP",
          "filters": {"ending_within":"24h","max_bid_count":"0"},
          "notify_types": ["new_list","ending_soon"],
          "status": "active"
        }
        """.data(using: .utf8)!
        let s = try decoder.decode(SavedSearch.self, from: json)
        XCTAssertEqual(s.filtersJson?["ending_within"], "24h")
        XCTAssertEqual(s.endingSoon, true)
        XCTAssertEqual(s.notifyTypes?.contains(.endingSoon), true)
    }

    func testCreateSavedSearchRequest() {
        let req = CreateSavedSearchRequest(
            query: "EMP",
            filters: ["ending_within": "1h"],
            notifyTypes: [.newList, .endingSoon]
        )
        XCTAssertTrue(req.endingSoonEnabled)
        XCTAssertEqual(SearchLimits.maxSavedSearches, 20)
        XCTAssertEqual(SearchLimits.maxShortcuts, 12)
    }

    func testTonightBoundUsesShanghai() {
        let now = Date(timeIntervalSince1970: 1_730_733_000) // ~2024-11-04 UTC+8 afternoon-ish
        let bound = SearchBusinessTimezone.tonightBound(from: now)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = SearchBusinessTimezone.shanghai
        XCTAssertEqual(cal.component(.hour, from: bound), 0)
        XCTAssertFalse(SearchBusinessTimezone.tonightCaption(from: now).isEmpty)
    }

    func testSearchHistoryPushDedupesAndCaps() {
        var raw = ""
        for i in 0..<25 { SearchHistoryStore.push("k\(i)", into: &raw) }
        let items = SearchHistoryStore.parse(raw)
        XCTAssertEqual(items.count, SearchLimits.historyMax)
        XCTAssertEqual(items.first, "k24")
        SearchHistoryStore.push("k24", into: &raw)
        XCTAssertEqual(SearchHistoryStore.parse(raw).first, "k24")
        XCTAssertEqual(SearchHistoryStore.parse(raw).filter { $0 == "k24" }.count, 1)
    }

    func testSoldSnapshotEncodeRoundTrip() throws {
        let snap = SoldSnapshot(
            displayPrice: 88000,
            displayPriceKind: .list,
            soldAt: Date(timeIntervalSince1970: 1_730_000_000),
            title: "样例",
            cover: "c"
        )
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(snap)
        let decoded = try decoder.decode(SoldSnapshot.self, from: data)
        XCTAssertEqual(decoded.displayPriceKind, .list)
        XCTAssertEqual(decoded.displayPrice, 88000)
    }
}
