import XCTest
@testable import VeloraCore

final class DirectZoneModelsTests: XCTestCase {
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

    // MARK: Defaults / copy

    func testUserFacingCopyNeverSaysYikoujia() {
        let blobs = [
            DirectZoneCopy.zoneTitle,
            DirectZoneCopy.buyNow,
            DirectZoneCopy.publishFixed,
            DirectZoneCopy.tradeTypeLabel,
            DirectZoneCopy.goToZone,
            DirectZoneCopy.searchPlaceholder,
        ]
        for s in blobs {
            XCTAssertFalse(s.contains("一口价"), s)
        }
        XCTAssertEqual(DirectZoneCopy.buyNow, "立即购买")
        XCTAssertEqual(DirectZoneCopy.publishFixed, "发布直购")
    }

    func testDefaultSectionsAndFilters() {
        XCTAssertEqual(DirectZoneDefaults.sections.map(\.key), [.new, .priceDrop, .sold])
        XCTAssertEqual(DirectZoneDefaults.sections.first { $0.key == .new }?.sellerTypes, [.personal])
        XCTAssertFalse(DirectZoneDefaults.filters.contains(where: { $0.key == .brandOfficial }))
        XCTAssertEqual(DirectZoneDefaults.filters.count, 5)
        XCTAssertEqual(
            DirectZoneConfig().enabledSections.map(\.key),
            [.new, .priceDrop, .sold]
        )
    }

    // MARK: HOME-05 identity

    func testActiveSectionsPersonalOnly() {
        XCTAssertTrue(DirectZoneLogic.sectionAllows(sellerType: .personal, section: .new))
        XCTAssertTrue(DirectZoneLogic.sectionAllows(sellerType: .personal, section: .priceDrop))
        XCTAssertTrue(DirectZoneLogic.sectionAllows(sellerType: .personal, section: .sold))
        XCTAssertFalse(DirectZoneLogic.sectionAllows(sellerType: .proxyAgent, section: .new))
        XCTAssertFalse(DirectZoneLogic.sectionAllows(sellerType: .brand, section: .new))
        XCTAssertFalse(DirectZoneSectionKey.featured.isActiveZoneSection)
        XCTAssertFalse(DirectZoneSectionKey.brand.isActiveZoneSection)
        XCTAssertFalse(DirectZoneLogic.isPromotable(.personal))
        XCTAssertFalse(DirectZoneLogic.isPromotable(.brand))
    }

    // MARK: Stock / qty

    func testStockInvariant() {
        XCTAssertTrue(DirectZoneLogic.isStockBalanced(StockColumns(stock: 10, availableQty: 7, reservedQty: 2, soldQty: 1)))
        XCTAssertFalse(DirectZoneLogic.isStockBalanced(StockColumns(stock: 10, availableQty: 8, reservedQty: 2, soldQty: 1)))
        XCTAssertFalse(DirectZoneLogic.isStockBalanced(StockColumns(stock: 1, availableQty: -1, reservedQty: 1, soldQty: 1)))
    }

    func testPendingOrderBlocksPriceChange() {
        XCTAssertTrue(DirectZoneLogic.canChangePriceOrOffShelf(reservedQty: 0))
        XCTAssertFalse(DirectZoneLogic.canChangePriceOrOffShelf(reservedQty: 1))
    }

    func testPublishQtyBySellerType() {
        XCTAssertNil(DirectZoneLogic.validatePublishFixedQty(sellerType: .personal, qty: 1))
        XCTAssertEqual(DirectZoneLogic.validatePublishFixedQty(sellerType: .personal, qty: 2), .stockMustBeOne)
        XCTAssertEqual(DirectZoneLogic.validatePublishFixedQty(sellerType: .proxyAgent, qty: 1), .stockMustBeOne)
        XCTAssertEqual(DirectZoneLogic.validatePublishFixedQty(sellerType: .brand, qty: 1), .stockMustBeOne)
        XCTAssertEqual(DirectZoneLogic.validatePublishFixedQty(sellerType: .brand, qty: 20), .stockMustBeOne)
    }

    func testMaxQtyPerOrder() {
        XCTAssertEqual(DirectZoneLogic.maxQtyPerOrder(sellerType: .personal, availableQty: 5), 1)
        XCTAssertEqual(DirectZoneLogic.maxQtyPerOrder(sellerType: .brand, availableQty: 20), 1)
        XCTAssertEqual(DirectZoneLogic.maxQtyPerOrder(sellerType: .brand, availableQty: 3), 1)
        XCTAssertEqual(DirectZoneLogic.maxQtyPerOrder(sellerType: .brand, availableQty: 0), 0)
    }

    func testAmountFormula() {
        XCTAssertEqual(
            DirectZoneLogic.computeAmountFen(unitPriceFen: 12_500, qty: 2, shippingFeeFen: 800),
            25_800
        )
    }

    // MARK: Sort / query

    func testSortsForSection() {
        XCTAssertEqual(DirectZoneLogic.sorts(for: .featured), [.heat])
        XCTAssertEqual(DirectZoneLogic.sorts(for: .sold), [.newest])
        XCTAssertEqual(DirectZoneLogic.sorts(for: .new), [.newest, .priceAsc, .priceDesc])
    }

    func testValidateListingsQuery() {
        var q = DirectZoneListingsQuery(section: .new, sort: .newest)
        XCTAssertNil(DirectZoneLogic.validateListingsQuery(q))
        q.sort = .heat
        XCTAssertEqual(DirectZoneLogic.validateListingsQuery(q), "invalid_sort")
        q.sort = .newest
        q.pageSize = 100
        XCTAssertEqual(DirectZoneLogic.validateListingsQuery(q), "invalid_page_size")
        q.pageSize = 20
        q.priceMin = 200
        q.priceMax = 100
        XCTAssertEqual(DirectZoneLogic.validateListingsQuery(q), "invalid_price_range")
    }

    func testQueryItemsAlwaysFixedTradeType() {
        let items = DirectZoneListingsQuery(section: .priceDrop, sort: .priceAsc, freeShipping: true).queryItems
        XCTAssertEqual(items["trade_type"] ?? nil, "fixed")
        XCTAssertEqual(items["section"] ?? nil, "price_drop")
        XCTAssertEqual(items["sort"] ?? nil, "price_asc")
        XCTAssertEqual(items["free_shipping"] ?? nil, "true")
        XCTAssertNil(items["negotiable"] ?? nil)
    }

    // MARK: Countdown / gates

    func testPayCountdownUsesServerClock() {
        let server = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = server.addingTimeInterval(15 * 60)
        XCTAssertEqual(DirectZoneLogic.countdownSeconds(payDeadline: deadline, serverTime: server), 900)
        XCTAssertEqual(DirectZoneLogic.formatPayCountdown(seconds: 125), "02:05")
        XCTAssertTrue(DirectZoneLogic.payCountdownLine(seconds: 59).contains("00:59"))
        XCTAssertTrue(DirectZoneLogic.payCountdownLine(seconds: 59).contains(DirectZoneCopy.payCountdownHint))
    }

    func testPurchaseGate() {
        XCTAssertEqual(
            DirectZoneLogic.purchaseGate(isLoggedIn: false, realNameDone: false, creditScore: 100, isRestricted: false),
            .unauthorized
        )
        XCTAssertEqual(
            DirectZoneLogic.purchaseGate(isLoggedIn: true, realNameDone: false, creditScore: 100, isRestricted: false),
            .realNameRequired
        )
        XCTAssertEqual(
            DirectZoneLogic.purchaseGate(isLoggedIn: true, realNameDone: true, creditScore: 59, isRestricted: false),
            .creditTooLow
        )
        XCTAssertEqual(
            DirectZoneLogic.purchaseGate(isLoggedIn: true, realNameDone: true, creditScore: 80, isRestricted: true),
            .accountRestricted
        )
        XCTAssertNil(
            DirectZoneLogic.purchaseGate(isLoggedIn: true, realNameDone: true, creditScore: 60, isRestricted: false)
        )
    }

    func testErrorFallbackMessages() {
        XCTAssertEqual(DirectZoneErrorCode.stockInsufficient.fallbackMessage, DirectZoneCopy.stockTaken)
        XCTAssertEqual(DirectZoneErrorCode.priceChanged.fallbackMessage, DirectZoneCopy.priceChanged)
        XCTAssertEqual(DirectZoneErrorCode.listingHasPendingOrder.fallbackMessage, DirectZoneCopy.pendingOrderBlock)
    }

    // MARK: Decode

    func testDecodeZoneConfig() throws {
        let json = """
        {
          "enabled": true,
          "config_version": 3,
          "sections": [
            {"key":"new","title":"最新","enabled":true,"sort_order":1,"seller_types":[]},
            {"key":"featured","title":"精选","enabled":true,"sort_order":2,"seller_types":["proxy_agent","brand"]}
          ],
          "filters": [
            {"key":"free_shipping","title":"包邮","enabled":true,"sort_order":1}
          ],
          "featured_slots": [
            {"id":"s1","listing_id":"42","position":1,"label":"recommend"}
          ],
          "lock_minutes": 15
        }
        """.data(using: .utf8)!
        let cfg = try decoder.decode(DirectZoneConfig.self, from: json)
        XCTAssertTrue(cfg.enabled)
        XCTAssertEqual(cfg.configVersion, "3")
        // Featured remains decodable but is filtered from active zone sections.
        XCTAssertEqual(cfg.enabledSections.map(\.key), [.new])
        XCTAssertEqual(cfg.featuredSlots.first?.listingId, 42)
        XCTAssertEqual(cfg.featuredSlots.first?.label.displayText, "推荐")
        XCTAssertEqual(cfg.resolvedLockMinutes, 15)
    }

    func testDecodeListingCardAndLowStock() throws {
        let json = """
        {
          "listing_id": 99,
          "title": "RB19 直购",
          "cover": "https://cdn.example/a.jpg",
          "condition": "全新未拆",
          "price": 128000,
          "original_price": 150000,
          "free_shipping": true,
          "negotiable": false,
          "seller_type": "brand",
          "available_qty": 3,
          "price_dropped": true,
          "status": "on_sale"
        }
        """.data(using: .utf8)!
        let card = try decoder.decode(DirectZoneListingCard.self, from: json)
        XCTAssertEqual(card.listingId, 99)
        XCTAssertTrue(card.showsPriceDrop)
        XCTAssertEqual(card.lowStockText, "仅剩 3 件")
        XCTAssertTrue(card.isPurchasable)
        XCTAssertNil(card.sellerType?.badgeLabel)
        XCTAssertFalse(card.sellerType?.showsIdentityBadge == true)
    }

    func testDecodeOrderPreviewAndCreate() throws {
        let previewJSON = """
        {
          "listing_id": "7",
          "qty": 1,
          "unit_price_fen": 10000,
          "shipping_fee_fen": 0,
          "amount_fen": 10000,
          "available_qty": 1,
          "max_qty": 1,
          "lock_minutes": 15,
          "ship_hours": 72,
          "title": "Demo",
          "seller_type": "personal"
        }
        """.data(using: .utf8)!
        let preview = try decoder.decode(FixedOrderPreview.self, from: previewJSON)
        XCTAssertEqual(preview.listingId, 7)
        XCTAssertFalse(preview.showsQtyStepper)
        XCTAssertEqual(
            DirectZoneLogic.computeAmountFen(
                unitPriceFen: preview.unitPriceFen,
                qty: preview.qty,
                shippingFeeFen: preview.shippingFeeFen
            ),
            preview.amountFen
        )

        let createJSON = """
        {
          "order_id": "1001",
          "pay_deadline": "2026-11-05T04:15:00Z",
          "server_time": "2026-11-05T04:00:00Z",
          "amount": 10000,
          "shipping_fee": 0,
          "qty": 1,
          "listing_id": 7
        }
        """.data(using: .utf8)!
        let created = try decoder.decode(FixedOrderCreateResult.self, from: createJSON)
        XCTAssertEqual(created.orderId, 1001)
        XCTAssertEqual(
            DirectZoneLogic.countdownSeconds(payDeadline: created.payDeadline, serverTime: created.serverTime),
            15 * 60
        )
    }

    func testCardPersonalOmitsBadge() {
        let card = DirectZoneListingCard(
            listingId: 1,
            title: "x",
            price: 100,
            sellerType: .personal,
            availableQty: 1
        )
        XCTAssertNil(card.sellerType?.badgeLabel)
        XCTAssertFalse(card.sellerType?.showsIdentityBadge == true)
    }
}
