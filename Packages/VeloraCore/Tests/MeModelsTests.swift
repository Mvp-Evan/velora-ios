import XCTest
@testable import VeloraCore

final class MeModelsTests: XCTestCase {
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if let s = try? c.decode(String.self) {
                let withFrac = ISO8601DateFormatter()
                withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let dt = withFrac.date(from: s) { return dt }
                let plain = ISO8601DateFormatter()
                plain.formatOptions = [.withInternetDateTime]
                if let dt = plain.date(from: s) { return dt }
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
            }
            if let ms = try? c.decode(Int64.self) {
                return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
            }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date"))
        }
        return d
    }()

    // MARK: Config (design §15)

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(MeConfigDefaults.showPhase2EntriesKey, "me.show_phase2_entries")
        XCTAssertFalse(MeConfigDefaults.showPhase2EntriesDefault)
        XCTAssertEqual(MeConfigDefaults.historyDays, 90)
        XCTAssertEqual(MeConfigDefaults.historyThrottleSec, 30)
        XCTAssertEqual(MeConfigDefaults.historyExposureSec, 2)
        XCTAssertEqual(MeConfigDefaults.overviewBadgeCacheSec, 5)
        XCTAssertEqual(MeConfigDefaults.overviewBadgeTimeoutMs, 200)
        XCTAssertEqual(MeConfigDefaults.historyPageSize, 20)
        XCTAssertEqual(MeConfigDefaults.badgeCap, 99)
        XCTAssertEqual(MeConfigDefaults.legalLicensesConfigKey, "legal.licenses")
        XCTAssertEqual(MeConfigDefaults.brandDisplayName, "毂毂")
        XCTAssertEqual(MeConfigDefaults.licensesFooter, "平台不开展官方寄售，不接收实物")
    }

    // MARK: View mode

    func testMeViewModeNormalizeAndLabels() {
        XCTAssertEqual(MeViewMode.normalize("buyer"), .buyer)
        XCTAssertEqual(MeViewMode.normalize("SELLER"), .seller)
        XCTAssertEqual(MeViewMode.normalize("sell"), .seller)
        XCTAssertNil(MeViewMode.normalize("admin"))
        XCTAssertEqual(MeViewMode.buyer.displayLabel, "买家")
        XCTAssertEqual(MeViewMode.seller.displayLabel, "卖家")
    }

    // MARK: Entry codes / matrix

    func testEntryCodeNormalizeAliases() {
        XCTAssertEqual(MeEntryCode.normalize("fav"), .fav)
        XCTAssertEqual(MeEntryCode.normalize("favorites"), .fav)
        XCTAssertEqual(MeEntryCode.normalize("balance"), .balanceDue)
        XCTAssertEqual(MeEntryCode.normalize("balance_due"), .balanceDue)
        XCTAssertEqual(MeEntryCode.normalize("on_sale"), .onsale)
        XCTAssertEqual(MeEntryCode.normalize("profit"), .income)
        XCTAssertEqual(MeEntryCode.normalize("deposit"), .depositsBuy)
        XCTAssertEqual(MeEntryCode.normalize("after_sale"), .afterSaleBuy)
        XCTAssertEqual(MeEntryCode.normalize("presale_orders"), .presaleBooks)
        XCTAssertEqual(MeEntryCode.normalize("proxy_kpi"), .proxyKpi)
        XCTAssertNil(MeEntryCode.normalize("unknown_xyz"))
    }

    func testBuyerNineEntriesAndSellerMatrix() {
        let buyerCodes: [MeEntryCode] = [
            .fav, .bought, .bids, .balanceDue, .lottery, .subs, .history, .afterSaleBuy, .depositsBuy,
        ]
        XCTAssertEqual(buyerCodes.count, 9)
        for code in buyerCodes {
            XCTAssertTrue(code.isBuyerEntry)
            XCTAssertTrue(MeLogic.entryVisible(code: code, view: .buyer, sellerType: nil, showPhase2Entries: false))
        }

        let personal: [MeEntryCode] = [
            .onsale, .auctions, .sold, .wallet, .income, .afterSaleSell, .sellerDeposit,
        ]
        XCTAssertEqual(personal.count, 7)
        for code in personal {
            XCTAssertTrue(MeLogic.entryVisible(code: code, view: .seller, sellerType: .personal, showPhase2Entries: false))
        }

        XCTAssertTrue(MeLogic.shouldRenderEntry(code: .invoice, sellerType: .proxyAgent, showPhase2Entries: false))
        XCTAssertFalse(MeLogic.shouldRenderEntry(code: .invoice, sellerType: .personal, showPhase2Entries: false))
        XCTAssertFalse(MeLogic.shouldRenderEntry(code: .invoice, sellerType: .brand, showPhase2Entries: true))
        XCTAssertTrue(MeLogic.shouldRenderEntry(code: .store, sellerType: .brand, showPhase2Entries: false))
        XCTAssertFalse(MeLogic.shouldRenderEntry(code: .vip, sellerType: .proxyAgent, showPhase2Entries: true))
        XCTAssertTrue(MeLogic.shouldRenderEntry(code: .releases, sellerType: .brand, showPhase2Entries: false))
        XCTAssertFalse(MeLogic.shouldRenderEntry(code: .releases, sellerType: .personal, showPhase2Entries: false))
        XCTAssertEqual(MeLogic.sellerDepositTitle(sellerType: .brand), "品牌保证金")
        XCTAssertEqual(MeLogic.sellerDepositTitle(sellerType: .personal), "卖家保证金")
    }

    func testReasonCodes() {
        XCTAssertEqual(MeEntryReasonCode.normalize("capability_off"), .capabilityOff)
        XCTAssertEqual(MeEntryReasonCode.normalize("coming_soon"), .comingSoon)
        XCTAssertEqual(MeEntryReasonCode.normalize("real_name_required"), .realNameRequired)
        XCTAssertEqual(MeEntryReasonCode.capabilityOff.displayMessage, MeCopy.reasonCapabilityOff)
        XCTAssertEqual(MeEntryReasonCode.comingSoon.displayMessage, MeCopy.reasonComingSoon)
    }

    // MARK: Badge formatting

    func testBadgeTextCap() {
        XCTAssertNil(MeLogic.badgeText(0))
        XCTAssertEqual(MeLogic.badgeText(1), "1")
        XCTAssertEqual(MeLogic.badgeText(99), "99")
        XCTAssertEqual(MeLogic.badgeText(100), "99+")
        XCTAssertEqual(MeLogic.badgeText(999), "99+")
    }

    // MARK: History gates

    func testHistoryRecordGates() {
        XCTAssertTrue(MeLogic.shouldRecordHistory(
            isLoggedIn: true, saveBrowseHistory: true, isOwnListing: false, exposureSeconds: 2
        ))
        XCTAssertFalse(MeLogic.shouldRecordHistory(
            isLoggedIn: true, saveBrowseHistory: true, isOwnListing: false, exposureSeconds: 1.5
        ))
        XCTAssertFalse(MeLogic.shouldRecordHistory(
            isLoggedIn: false, saveBrowseHistory: true, isOwnListing: false, exposureSeconds: 5
        ))
        XCTAssertFalse(MeLogic.shouldRecordHistory(
            isLoggedIn: true, saveBrowseHistory: false, isOwnListing: false, exposureSeconds: 5
        ))
        XCTAssertFalse(MeLogic.shouldRecordHistory(
            isLoggedIn: true, saveBrowseHistory: true, isOwnListing: true, exposureSeconds: 5
        ))

        let now = Date()
        XCTAssertTrue(MeLogic.throttleAllows(lastSentAt: nil, now: now))
        XCTAssertFalse(MeLogic.throttleAllows(lastSentAt: now.addingTimeInterval(-10), now: now))
        XCTAssertTrue(MeLogic.throttleAllows(lastSentAt: now.addingTimeInterval(-30), now: now))
    }

    // MARK: Overview decode

    func testOverviewDecodeSnakeCaseAndPartial() throws {
        let json = """
        {
          "view": "seller",
          "seller_type": "personal",
          "credit_score": 88,
          "real_name_status": "verified",
          "seller_onboarding": "active",
          "partial": true,
          "partial_badges": ["bought"],
          "flags": { "show_phase2_entries": false },
          "save_browse_history": true,
          "entries": [
            {
              "code": "bought",
              "title": "我买到的",
              "badge": 3,
              "enabled": true,
              "href": "/orders?role=buyer"
            },
            {
              "code": "onsale",
              "title": "我的在售",
              "badge": 0,
              "enabled": false,
              "reason_code": "capability_off"
            }
          ]
        }
        """.data(using: .utf8)!
        let ov = try decoder.decode(MeOverviewResponse.self, from: json)
        XCTAssertEqual(ov.resolvedView, .seller)
        XCTAssertEqual(ov.resolvedSellerType, .personal)
        XCTAssertEqual(ov.creditScore, 88)
        XCTAssertTrue(ov.partial)
        XCTAssertEqual(ov.partialBadges, ["bought"])
        XCTAssertFalse(ov.showPhase2Entries)
        XCTAssertEqual(ov.entries.count, 2)
        XCTAssertEqual(ov.entries[0].badgeText, "3")
        XCTAssertEqual(ov.entries[1].resolvedReason, .capabilityOff)
        XCTAssertEqual(MeLogic.badge(for: "bought", in: ov), 3)
    }

    func testOverviewAcceptsKeyAliasForCode() throws {
        let json = """
        { "view": "buyer", "entries": [{ "key": "history", "title": "足迹", "badge": 0 }] }
        """.data(using: .utf8)!
        let ov = try decoder.decode(MeOverviewResponse.self, from: json)
        XCTAssertEqual(ov.entries.first?.resolvedCode, .history)
    }

    // MARK: Prefs

    func testPrefsDecodeAndUpdateBody() throws {
        let json = """
        {
          "me_view": "buyer",
          "save_browse_history": false,
          "updated_at": "2026-01-02T03:04:05Z"
        }
        """.data(using: .utf8)!
        let prefs = try decoder.decode(MePrefs.self, from: json)
        XCTAssertEqual(prefs.resolvedView, .buyer)
        XCTAssertFalse(prefs.saveBrowseHistory)
        XCTAssertNotNil(prefs.updatedAt)

        let req = MePrefsUpdateRequest(meView: "seller", saveBrowseHistory: true)
        XCTAssertEqual(req.body["me_view"] as? String, "seller")
        XCTAssertEqual(req.body["save_browse_history"] as? Bool, true)
    }

    func testPrefsUpdateResponseSellerRequired() throws {
        let json = """
        {
          "me_view": "buyer",
          "seller_required": true,
          "overview": { "view": "buyer", "entries": [], "seller_required": true }
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(MePrefsUpdateResponse.self, from: json)
        XCTAssertTrue(resp.isSellerRequired)
        XCTAssertEqual(resp.resolvedView, .buyer)
    }

    func testPrefsUpdateResponseFlatOverviewShape() throws {
        // Live PUT /me/prefs returns flat MeOverview with `view`, not nested `{overview:…}`.
        let json = """
        {
          "view": "seller",
          "seller_type": "personal",
          "credit_score": 90,
          "entries": [
            { "code": "onsale", "title": "我的在售", "badge": 1, "enabled": true }
          ],
          "save_browse_history": true
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(MePrefsUpdateResponse.self, from: json)
        XCTAssertEqual(resp.meView, "seller")
        XCTAssertEqual(resp.resolvedView, .seller)
        XCTAssertEqual(resp.overview?.view, "seller")
        XCTAssertEqual(resp.overview?.entries.first?.code, "onsale")
        XCTAssertEqual(resp.overview?.entries.first?.badge, 1)
        XCTAssertEqual(resp.saveBrowseHistory, true)
    }

    // MARK: Browse history

    func testBrowseHistoryItemDecodeAndUnavailable() throws {
        let json = """
        {
          "id": 11,
          "target_type": "listing",
          "target_id": 99,
          "last_viewed_at": "2026-03-01T12:00:00Z",
          "title_snapshot": "Ferrari 1/18",
          "cover": "https://cdn.example/a.jpg",
          "price_snapshot": 128000,
          "trade_type": "auction",
          "status_snapshot": "live",
          "available": true
        }
        """.data(using: .utf8)!
        let item = try decoder.decode(BrowseHistoryItem.self, from: json)
        XCTAssertEqual(item.targetId, 99)
        XCTAssertEqual(item.priceSnapshot, 128_000)
        XCTAssertFalse(item.isUnavailable)
        XCTAssertEqual(item.displayTitle, "Ferrari 1/18")

        let dead = BrowseHistoryItem(id: 1, targetId: 2, statusSnapshot: "offline", available: nil)
        XCTAssertTrue(dead.isUnavailable)

        let listJSON = """
        { "items": [{ "id": 1, "listing_id": 5, "title_snapshot": "x" }], "next_cursor": "abc", "total": 1 }
        """.data(using: .utf8)!
        let page = try decoder.decode(BrowseHistoryListResponse.self, from: listJSON)
        XCTAssertEqual(page.items.first?.targetId, 5)
        XCTAssertEqual(page.nextCursor, "abc")
        XCTAssertEqual(page.total, 1)

        let req = BrowseHistoryRecordRequest(listingId: 42)
        XCTAssertEqual(req.body["listing_id"] as? Int64, 42)
    }

    // MARK: Settings + licenses

    func testSettingsAndLicensePendingClearsNumber() throws {
        let json = """
        {
          "real_name": {
            "status": "verified",
            "masked_name": "张*",
            "id_last4": "1234"
          },
          "protocols": [
            {
              "protocol_code": "privacy",
              "version": "3",
              "signed_at": "2026-01-01T00:00:00Z"
            }
          ],
          "licenses": [
            {
              "name": "拍卖经营批准证书",
              "license_no": "SHOULD_CLEAR",
              "status": "pending"
            },
            {
              "name": "ICP",
              "license_no": "沪ICP备000",
              "status": "active",
              "image_url": "https://cdn.example/lic.png"
            }
          ],
          "save_browse_history": true,
          "deletion_eligible": false
        }
        """.data(using: .utf8)!
        let settings = try decoder.decode(MeSettingsResponse.self, from: json)
        XCTAssertEqual(settings.realName?.summaryLabel, "张* · 1234")
        XCTAssertEqual(settings.protocols.first?.displayTitle, MeCopy.privacyPolicy)
        XCTAssertNil(settings.licenses[0].licenseNo)
        XCTAssertEqual(settings.licenses[0].displayLicenseNo, MeCopy.licensePending)
        XCTAssertEqual(settings.licenses[1].licenseNo, "沪ICP备000")
        XCTAssertEqual(settings.deletionEligible, false)

        let caption = MeLogic.protocolSignedCaption(
            signedAt: Date(timeIntervalSince1970: 1_704_067_200),
            version: "3"
        )
        XCTAssertTrue(caption.contains("同意 v3"))
    }

    func testLegalLicensesListResponse() throws {
        let json = """
        {
          "licenses": [
            { "name": "软著", "status": "pending" }
          ],
          "version": "v2"
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(LegalLicensesResponse.self, from: json)
        XCTAssertEqual(resp.items.count, 1)
        XCTAssertEqual(resp.version, "v2")
        XCTAssertTrue(resp.items[0].isPending)
    }

    // MARK: Deletion precheck

    func testDeletionPrecheckEligibleAndBlockers() throws {
        let blocked = """
        {
          "eligible": false,
          "blockers": [
            { "code": "open_orders", "count": 2, "hint": "还有 2 笔待发货" },
            { "code": "wallet_balance", "count": 1, "hint": "钱包仍有余额，请先提现" }
          ]
        }
        """.data(using: .utf8)!
        let pre = try decoder.decode(MeDeletionPrecheck.self, from: blocked)
        XCTAssertFalse(pre.eligible)
        XCTAssertFalse(pre.canDelete)
        XCTAssertEqual(pre.blockers.count, 2)
        XCTAssertEqual(pre.blockers[0].resolvedCode, .openOrders)
        XCTAssertEqual(pre.blockers[0].displayText, "还有 2 笔待发货")
        XCTAssertEqual(MeDeletionBlockerCode.walletBalance.guideAction, MeCopy.blockerGuideWithdraw)

        let ok = """
        { "blockers": [] }
        """.data(using: .utf8)!
        let clear = try decoder.decode(MeDeletionPrecheck.self, from: ok)
        XCTAssertTrue(clear.eligible)
        XCTAssertTrue(clear.canDelete)
    }

    func testMeErrorCodes() {
        XCTAssertEqual(MeErrorCode.sellerRequired.rawValue, "seller_required")
        XCTAssertEqual(MeErrorCode.historyNotFound.rawValue, "history_not_found")
        XCTAssertEqual(MeErrorCode.deletionBlocked.rawValue, "deletion_blocked")
        XCTAssertTrue(MeErrorCode.sellerRequired.fallbackMessage.contains("卖家"))
        XCTAssertEqual(MeLogic.unknownEntryMessage(code: "future_vip_x"), MeCopy.upgradeApp)
    }

    func testCopyBrandAndFooter() {
        XCTAssertEqual(MeCopy.licensesFooter, "平台不开展官方寄售，不接收实物")
        XCTAssertEqual(MeCopy.historySaveOffHint, "已保存的记录仍在，可清空")
        XCTAssertEqual(MeCopy.settingsTitle, "设置")
        XCTAssertEqual(MeCopy.licensesTitle, "资质公示")
    }
}
