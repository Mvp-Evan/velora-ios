import XCTest
@testable import VeloraCore

final class LibraryModelsTests: XCTestCase {

    // MARK: Config / flags

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(LibraryConfigDefaults.curveFlagKey, "library.curve")
        XCTAssertFalse(LibraryConfigDefaults.curveEnabledDefault)
        XCTAssertEqual(LibraryConfigDefaults.curveMinSamples, 5)
        XCTAssertEqual(LibraryConfigDefaults.valuationDays, 90)
        XCTAssertEqual(LibraryConfigDefaults.valuationMinN, 3)
        XCTAssertEqual(LibraryConfigDefaults.badgeCopperRatio, 0.3, accuracy: 0.0001)
        XCTAssertEqual(LibraryConfigDefaults.badgeSilverRatio, 0.6, accuracy: 0.0001)
        XCTAssertTrue(LibraryConfigDefaults.cabinetPublicDefault)
        XCTAssertEqual(LibraryConfigDefaults.firstScale, "1:43")
        XCTAssertEqual(LibraryConfigDefaults.wishlistMax, 200)
        XCTAssertEqual(LibraryConfigDefaults.disclaimerCodeReferenceOnly, "reference_only")
        XCTAssertEqual(LibraryConfigDefaults.meEntryCabinet, "cabinet")
        XCTAssertEqual(LibraryConfigDefaults.meEntryLibrary, "library")
        XCTAssertEqual(LibraryConfigDefaults.meEntryAtlas, "atlas")
    }

    // MARK: Error codes / copy

    func testErrorNormalizeAndCopy() {
        XCTAssertEqual(LibraryErrorCode.normalize("sku_not_found"), .skuNotFound)
        XCTAssertEqual(LibraryErrorCode.normalize("curve_not_ready"), .curveNotReady)
        XCTAssertEqual(LibraryErrorCode.normalize("sample_insufficient"), .curveNotReady)
        XCTAssertEqual(LibraryErrorCode.normalize("cabinet_private"), .cabinetPrivate)
        XCTAssertEqual(LibraryErrorCode.normalize("real_name_required"), .realNameRequired)
        XCTAssertEqual(LibraryErrorCode.normalize("wishlist_full"), .wishlistFull)
        XCTAssertEqual(LibraryErrorCode.normalize("library_not_enabled"), .libraryNotEnabled)
        XCTAssertEqual(LibraryErrorCode.normalize("library_off"), .libraryNotEnabled)
        XCTAssertEqual(LibraryErrorCode.normalize("feature_disabled"), .featureDisabled)
        XCTAssertEqual(LibraryErrorCode.normalize("account_frozen"), .accountRestricted)
        XCTAssertEqual(LibraryErrorCode.curveNotReady.fallbackMessage, LibraryCopy.curveNotReady)
        XCTAssertEqual(LibraryCopy.libraryBuilding, "产品库建设中")
        XCTAssertTrue(LibraryCopy.valuationDisclaimer.contains("仅供参考"))
        XCTAssertEqual(LibraryCopy.cabinetPrivate, "该柜未公开")
    }

    // MARK: Curve gate (library.curve off)

    func testHideCurveWhenLibraryFlagOff() {
        XCTAssertFalse(
            LibraryLogic.showsCurve(
                libraryCurveEnabled: false,
                skuCurveEnabled: true,
                sampleN: 20
            )
        )
        XCTAssertEqual(
            LibraryLogic.curvePlaceholder(
                libraryCurveEnabled: false,
                skuCurveEnabled: true,
                sampleN: 20
            ),
            .curveHiddenByFlag
        )
        XCTAssertEqual(
            LibraryLogic.placeholderTitle(.curveHiddenByFlag),
            LibraryCopy.curveHidden
        )
    }

    func testCurveReadyOnlyWithSamplesAndFlag() {
        XCTAssertFalse(
            LibraryLogic.showsCurve(
                libraryCurveEnabled: true,
                skuCurveEnabled: true,
                sampleN: 4
            )
        )
        XCTAssertEqual(
            LibraryLogic.curvePlaceholder(
                libraryCurveEnabled: true,
                skuCurveEnabled: true,
                sampleN: 4
            ),
            .curveNotReady
        )
        XCTAssertTrue(
            LibraryLogic.showsCurve(
                libraryCurveEnabled: true,
                skuCurveEnabled: true,
                sampleN: 5
            )
        )
        XCTAssertNil(
            LibraryLogic.curvePlaceholder(
                libraryCurveEnabled: true,
                skuCurveEnabled: true,
                sampleN: 5
            )
        )
        XCTAssertFalse(
            LibraryLogic.showsCurve(
                libraryCurveEnabled: true,
                skuCurveEnabled: false,
                sampleN: 10
            )
        )
    }

    // MARK: Entry placeholders

    func testEntryPlaceholders() {
        XCTAssertEqual(LibraryLogic.entryPlaceholder(for: "library"), .libraryBuilding)
        XCTAssertEqual(LibraryLogic.entryPlaceholder(for: "cabinet"), .cabinetComingSoon)
        XCTAssertEqual(LibraryLogic.entryPlaceholder(for: "atlas"), .atlasComingSoon)
        XCTAssertEqual(LibraryLogic.entryPlaceholder(for: "图鉴"), .atlasComingSoon)
        XCTAssertEqual(LibraryLogic.placeholderTitle(.libraryBuilding), LibraryCopy.libraryBuilding)
        XCTAssertEqual(LibraryLogic.placeholderTitle(.cabinetComingSoon), LibraryCopy.cabinetComingSoon)
        XCTAssertEqual(LibraryLogic.placeholderTitle(.atlasComingSoon), LibraryCopy.atlasComingSoon)
    }

    // MARK: Badge thresholds

    func testBadgeThresholds() {
        let n10 = LibraryLogic.badgeThresholds(seriesSkuCount: 10)
        XCTAssertEqual(n10.copper, 3)
        XCTAssertEqual(n10.silver, 6)
        XCTAssertEqual(n10.gold, 10)

        let n1 = LibraryLogic.badgeThresholds(seriesSkuCount: 1)
        XCTAssertEqual(n1.copper, 1)
        XCTAssertEqual(n1.silver, 1)
        XCTAssertEqual(n1.gold, 1)

        XCTAssertEqual(
            LibraryLogic.tiersCrossed(ownedDistinctSkuCount: 3, seriesSkuCount: 10),
            [.copper]
        )
        XCTAssertEqual(
            LibraryLogic.tiersCrossed(ownedDistinctSkuCount: 10, seriesSkuCount: 10),
            [.copper, .silver, .gold]
        )
    }

    // MARK: Gates / completion / disclaimer

    func testWantAndManualGates() {
        XCTAssertEqual(
            LibraryLogic.canWant(isLoggedIn: false, isRealNamed: false, accountRestricted: false),
            .loginRequired
        )
        XCTAssertEqual(
            LibraryLogic.canWant(isLoggedIn: true, isRealNamed: false, accountRestricted: false),
            .realNameRequired
        )
        XCTAssertEqual(
            LibraryLogic.canWant(isLoggedIn: true, isRealNamed: true, accountRestricted: true),
            .accountRestricted
        )
        XCTAssertNil(
            LibraryLogic.canWant(isLoggedIn: true, isRealNamed: true, accountRestricted: false)
        )
        XCTAssertEqual(
            LibraryLogic.canManualCabinet(isLoggedIn: false, accountRestricted: false),
            .loginRequired
        )
        XCTAssertNil(
            LibraryLogic.canManualCabinet(isLoggedIn: true, accountRestricted: false)
        )
        XCTAssertTrue(LibraryLogic.canBrowseLibrary(isLoggedIn: false))
    }

    func testCompletionAndDisclaimer() {
        let items = [
            CabinetItem(id: 1, skuId: 10, source: "order_auto"),
            CabinetItem(id: 2, skuId: 10, source: "manual", slotNo: 2),
            CabinetItem(id: 3, skuId: 11, source: "order_auto"),
            CabinetItem(id: 4, skuId: 12, status: "removed"),
        ]
        XCTAssertEqual(LibraryLogic.completionOwnedCount(items: items), 2)
        XCTAssertTrue(CabinetItemSource.manual.countsTowardBadge == false)
        XCTAssertTrue(CabinetItemSource.orderAuto.countsTowardBadge)

        let summary = CabinetSummaryResponse(valueFen: 100_00, valueStatus: "ok")
        XCTAssertTrue(summary.showsDisclaimer)
        XCTAssertEqual(summary.displayDisclaimer, LibraryCopy.valuationDisclaimer)
        XCTAssertTrue(LibraryLogic.mustRenderDisclaimer(code: "reference_only"))
    }

    func testEnumNormalize() {
        XCTAssertEqual(WishlistKind.normalize("want"), .want)
        XCTAssertEqual(WishlistKind.normalize("favorite"), .wish)
        XCTAssertEqual(CabinetItemSource.normalize("order_auto"), .orderAuto)
        XCTAssertEqual(CabinetItemStatus.normalize("in"), .in)
        XCTAssertEqual(SeriesBadgeTier.normalize("bronze"), .copper)
        XCTAssertEqual(SeriesBadgeTier.gold.displayLabel, LibraryCopy.tierGold)
        XCTAssertEqual(ValuationStatus.normalize("partial"), .partial)
        XCTAssertEqual(SkuStatus.normalize("retired"), .retired)
    }

    // MARK: DTO decode — curve whitelist

    func testCurvePointDecodeIgnoresListingIdSurface() throws {
        // CodingKeys whitelist: only date / price / n decode; extra JSON keys are ignored by Codable.
        let json = """
        {"date":"2026-11-01","price":250000,"n":2}
        """.data(using: .utf8)!
        let point = try JSONDecoder.veloraTest.decode(SkuCurvePoint.self, from: json)
        XCTAssertEqual(point.date, "2026-11-01")
        XCTAssertEqual(point.price, 250_000)
        XCTAssertEqual(point.n, 2)
        XCTAssertTrue(LibraryLogic.forbiddenCurveKeys.contains("listing_id"))
        XCTAssertTrue(LibraryLogic.curvePointIsSafe(point))

        let curveJSON = """
        {"points":[{"date":"2026-11-01","price":100}],"sample_n":5,"disclaimer":"仅供参考"}
        """.data(using: .utf8)!
        let curve = try JSONDecoder.veloraTest.decode(SkuCurveResponse.self, from: curveJSON)
        XCTAssertEqual(curve.points.count, 1)
        XCTAssertEqual(curve.resolvedSampleN, 5)
    }

    func testProductSKUAndSummaryDecode() throws {
        let skuJSON = """
        {
          "id": 9,
          "sku_code": "BBR-F40-LM-RED-43",
          "brand_name": "BBR",
          "series_name": "Ferrari",
          "model_name": "F40",
          "scale": "1:43",
          "color": "Rosso",
          "curve_enabled": false,
          "status": "active"
        }
        """.data(using: .utf8)!
        let sku = try JSONDecoder.veloraTest.decode(ProductSKU.self, from: skuJSON)
        XCTAssertEqual(sku.skuCode, "BBR-F40-LM-RED-43")
        XCTAssertFalse(sku.isCurveEnabled)
        XCTAssertTrue(sku.displayName.contains("F40"))

        let summaryJSON = """
        {
          "completion":[{"series_id":1,"series_name":"Ferrari","owned":2,"total":10}],
          "value_fen":880000,
          "value_status":"partial",
          "disclaimer":"仅供参考，不构成估价或保值承诺",
          "disclaimer_code":"reference_only",
          "badges":[{"series_id":1,"tier":"copper","trigger_count":3}]
        }
        """.data(using: .utf8)!
        let summary = try JSONDecoder.veloraTest.decode(CabinetSummaryResponse.self, from: summaryJSON)
        XCTAssertEqual(summary.completion.first?.owned, 2)
        XCTAssertEqual(summary.resolvedValueStatus, .partial)
        XCTAssertEqual(summary.badges?.first?.resolvedTier, .copper)
        XCTAssertTrue(summary.showsDisclaimer)
    }

    // MARK: FakeAPIClient + ViewModels

    @MainActor
    func testLibraryIndexEmptyPlaceholder() async {
        let fake = FakeAPIClient()
        let vm = LibraryIndexViewModel(client: fake)
        await vm.load()
        XCTAssertEqual(vm.placeholder, .libraryBuilding)
        XCTAssertEqual(vm.placeholderTitle, LibraryCopy.libraryBuilding)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertFalse(vm.libraryCurveEnabled)
    }

    @MainActor
    func testCurveHiddenWhenFlagOffEvenIfSeeded() async throws {
        let fake = FakeAPIClient()
        await fake.seedSKU(ProductSKU(id: 3, skuCode: "X", curveEnabled: true))
        await fake.seedCurve(
            SkuCurveResponse(points: [
                SkuCurvePoint(date: "2026-10-01", price: 100),
                SkuCurvePoint(date: "2026-10-02", price: 110),
                SkuCurvePoint(date: "2026-10-03", price: 120),
                SkuCurvePoint(date: "2026-10-04", price: 130),
                SkuCurvePoint(date: "2026-10-05", price: 140),
            ], sampleN: 5),
            skuId: 3
        )
        // Default library.curve = false
        let vm = SkuCurveViewModel(skuId: 3, client: fake, libraryCurveEnabled: false)
        await vm.load()
        XCTAssertTrue(vm.loaded)
        XCTAssertFalse(vm.showsCurve)
        XCTAssertEqual(vm.curvePlaceholder, .curveHiddenByFlag)
        XCTAssertNil(vm.curve)

        // Direct API also refuses while flag off.
        do {
            _ = try await fake.skuCurve(skuId: 3)
            XCTFail("expected library_not_enabled")
        } catch let e as FakeAPIError {
            XCTAssertEqual(e.code, LibraryErrorCode.libraryNotEnabled.rawValue)
            XCTAssertEqual(e.status, 409)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func testCurveReadyWhenFlagOn() async throws {
        let fake = FakeAPIClient()
        await fake.setLibraryCurveEnabled(true)
        await fake.seedSKU(ProductSKU(id: 4, curveEnabled: true))
        await fake.seedCurve(
            SkuCurveResponse(points: (1...5).map {
                SkuCurvePoint(date: "2026-10-0\($0)", price: Int64($0 * 100))
            }, sampleN: 5),
            skuId: 4
        )
        let curve = try await fake.skuCurve(skuId: 4)
        XCTAssertEqual(curve.points.count, 5)

        let vm = SkuCurveViewModel(skuId: 4, client: fake, libraryCurveEnabled: true)
        await vm.load()
        XCTAssertTrue(vm.showsCurve)
        XCTAssertNil(vm.curvePlaceholder)
    }

    @MainActor
    func testCurveNotReadyBelowSampleGate() async {
        let fake = FakeAPIClient()
        await fake.setLibraryCurveEnabled(true)
        await fake.seedSKU(ProductSKU(id: 5, curveEnabled: true))
        await fake.seedCurve(
            SkuCurveResponse(points: [
                SkuCurvePoint(date: "2026-10-01", price: 100),
                SkuCurvePoint(date: "2026-10-02", price: 110),
            ], sampleN: 2),
            skuId: 5
        )
        do {
            _ = try await fake.skuCurve(skuId: 5)
            XCTFail("expected curve_not_ready")
        } catch let e as FakeAPIError {
            XCTAssertEqual(e.code, LibraryErrorCode.curveNotReady.rawValue)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func testCabinetPlaceholderAndPrivate() async {
        let fake = FakeAPIClient()
        let emptyVM = CabinetPlaceholderViewModel(
            client: fake,
            userId: 9,
            isSelf: false,
            entryKind: .cabinetComingSoon
        )
        await emptyVM.load()
        XCTAssertEqual(emptyVM.placeholder, .cabinetComingSoon)

        await fake.seedCabinet(
            CabinetWallResponse(items: [], total: 0, publicVisible: false),
            userId: 9
        )
        await fake.setLibraryError(code: nil)
        // viewerId default 1 ≠ 9 → private
        let privateVM = CabinetPlaceholderViewModel(
            client: fake, userId: 9, isSelf: false, entryKind: .cabinetComingSoon
        )
        await privateVM.load()
        XCTAssertEqual(privateVM.lastErrorCode, LibraryErrorCode.cabinetPrivate.rawValue)
        XCTAssertEqual(privateVM.placeholder, .cabinetPrivate)

        let atlasVM = CabinetPlaceholderViewModel(
            client: fake, userId: nil, isSelf: true, entryKind: .atlasComingSoon
        )
        await fake.seedMeCabinetSummary(CabinetSummaryResponse())
        await atlasVM.load()
        XCTAssertEqual(atlasVM.placeholder, .atlasComingSoon)
        XCTAssertTrue(atlasVM.showsDisclaimer)
    }

    @MainActor
    func testManualCabinetAndWishlistStubs() async throws {
        let fake = FakeAPIClient()
        await fake.seedSKU(ProductSKU(id: 7, skuCode: "Y"))
        let item = try await fake.addManualCabinet(
            body: ManualCabinetBody(skuId: 7, note: "自有"),
            idempotencyKey: "cab-1"
        )
        XCTAssertTrue(item.showsManualMark)
        XCTAssertEqual(item.resolvedSource, .manual)

        try await fake.setWishlist(
            skuId: 7,
            body: WishlistWriteBody(kind: .wish),
            idempotencyKey: "w1"
        )
        try await fake.removeWishlist(skuId: 7, idempotencyKey: "w2")
        let writes = await fake.wishlistWrites
        XCTAssertEqual(writes.count, 2)
        XCTAssertTrue(writes[1].remove)
    }

    @MainActor
    func testSkuNotFound() async {
        let fake = FakeAPIClient()
        do {
            _ = try await fake.skuDetail(skuId: 999)
            XCTFail("expected sku_not_found")
        } catch let e as FakeAPIError {
            XCTAssertEqual(e.code, LibraryErrorCode.skuNotFound.rawValue)
            XCTAssertEqual(e.status, 404)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

// MARK: - JSON helpers

private extension JSONDecoder {
    static var veloraTest: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
