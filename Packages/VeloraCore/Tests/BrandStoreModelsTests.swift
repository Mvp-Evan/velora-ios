import XCTest
@testable import VeloraCore

final class BrandStoreModelsTests: XCTestCase {
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

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    // MARK: Defaults

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(BrandStoreConfigDefaults.depositFen, 1_000_000)
        XCTAssertEqual(BrandStoreConfigDefaults.depositYuan, 10_000)
        XCTAssertEqual(BrandStoreConfigDefaults.sellerType, "brand")
        XCTAssertEqual(BrandStoreConfigDefaults.badgeOfficial, "brand_official")
        XCTAssertEqual(BrandStoreConfigDefaults.followTargetType, "brand_store")
        XCTAssertEqual(BrandStoreConfigDefaults.followLimit, 200)
        XCTAssertEqual(BrandStoreConfigDefaults.storeNameMaxLen, 20)
        XCTAssertEqual(BrandStoreConfigDefaults.announcementMaxLen, 500)
        XCTAssertEqual(BrandStoreConfigDefaults.n10LeadMinutes, 5)
        XCTAssertEqual(BrandStoreConfigDefaults.calendarHorizonDays, 90)
        XCTAssertEqual(BrandStoreConfigDefaults.authRemindDays, [30, 7, 1])
        XCTAssertEqual(BrandStoreConfigDefaults.renewMinCoverDays, 90)
        XCTAssertEqual(BrandStoreConfigDefaults.launchGateKey, "launch_gate.brand_merchant")
        XCTAssertEqual(BrandStoreConfigDefaults.notifyN10, "N-10")
        XCTAssertEqual(BrandStoreConfigDefaults.notifyN22, "N-22")
        XCTAssertEqual(BrandStoreConfigDefaults.meEntryStore, "store")
        XCTAssertEqual(BrandStoreConfigDefaults.logoAspect, 1.0, accuracy: 1e-9)
        XCTAssertEqual(BrandStoreConfigDefaults.bannerAspect, 3.0, accuracy: 1e-9)
        XCTAssertTrue(BrandStoreConfigDefaults.inviteRequired)
    }

    func testBrandCapabilityDefaults() {
        let caps = BrandCapabilities.brandDefaults
        XCTAssertFalse(caps.canFixed)
        XCTAssertFalse(caps.canAuction)
        XCTAssertTrue(caps.canSpecialNo)
        XCTAssertTrue(caps.canSpotRelease)
        XCTAssertTrue(caps.canLottery)
        XCTAssertTrue(caps.canPresale)
        XCTAssertTrue(caps.canStore)
        XCTAssertTrue(caps.canVip)
        XCTAssertTrue(caps.canPromote)
        XCTAssertTrue(caps.canBatchList)
        XCTAssertTrue(caps.showsReleasePublishEntry)
        XCTAssertTrue(caps.allows(.canStore))
        XCTAssertFalse(caps.allows(.canAuction))
        XCTAssertFalse(caps.allows(.canFixed))
    }

    func testCopyAndErrorMessages() {
        XCTAssertEqual(BrandStoreCopy.officialBadge, "品牌官方")
        XCTAssertEqual(BrandStoreCopy.followingReminderOn, "开售提醒已开启")
        XCTAssertEqual(BrandStoreCopy.calendarEmpty, "暂无发售，关注以免错过")
        XCTAssertEqual(BrandStoreCopy.unfollowConfirm, "将不再收到开售提醒")
        XCTAssertTrue(BrandStoreCopy.personalSellerGate.contains("邀请"))
        XCTAssertEqual(BrandStoreErrorCode.brandNotVerified.fallbackMessage.contains("认证"), true)
        XCTAssertTrue(BrandStoreErrorCode.followLoginRequired.opensLogin)
        XCTAssertFalse(BrandStoreErrorCode.brandNotAuthorized.opensLogin)
        XCTAssertEqual(
            BrandStoreCopy.notAuthorized(selected: "X", list: "A、B"),
            "只能发布授权品牌：A、B。当前选择 X 不在范围内。"
        )
    }

    // MARK: AuthorizeBrand matrix (design §14)

    func testAuthorizeActiveInWindow() {
        let row = BrandAuthorization(
            brandDictId: 10,
            brandName: "Spark",
            startsAt: date("2026-01-01T00:00:00Z"),
            expiresAt: date("2027-01-01T16:00:00Z"),
            status: .active
        )
        let result = BrandAuthorizeLogic.authorize(
            brandDictId: 10,
            brandName: "Spark",
            at: date("2026-06-01T00:00:00Z"),
            authorizations: [row],
            isBrandVerified: true
        )
        XCTAssertTrue(result.isAllowed)
        if case .ok(let ok) = result {
            XCTAssertEqual(ok.brandDictId, 10)
        } else {
            XCTFail("expected ok")
        }
    }

    func testAuthorizeExpired() {
        let row = BrandAuthorization(
            brandDictId: 10,
            brandName: "Spark",
            startsAt: date("2025-01-01T00:00:00Z"),
            expiresAt: date("2026-11-04T16:00:00Z"),
            status: .expired
        )
        let result = BrandAuthorizeLogic.authorize(
            brandDictId: 10,
            brandName: "Spark",
            at: date("2026-11-05T00:00:00Z"),
            authorizations: [row],
            isBrandVerified: true
        )
        XCTAssertEqual(result.errorCode, .brandAuthExpired)
        XCTAssertTrue(result.message.contains("到期"))
    }

    func testAuthorizeActiveButPastExpiresAtBoundary() {
        // expires_at inclusive exclusive: at >= expires_at → fail (design §3).
        let row = BrandAuthorization(
            brandDictId: 10,
            brandName: "Spark",
            startsAt: date("2025-01-01T00:00:00Z"),
            expiresAt: date("2026-11-04T16:00:00Z"),
            status: .active
        )
        let atExpiry = BrandAuthorizeLogic.authorize(
            brandDictId: 10, brandName: nil,
            at: date("2026-11-04T16:00:00Z"),
            authorizations: [row], isBrandVerified: true
        )
        XCTAssertEqual(atExpiry.errorCode, .brandAuthExpired)

        let before = BrandAuthorizeLogic.authorize(
            brandDictId: 10, brandName: nil,
            at: date("2026-11-04T15:59:59Z"),
            authorizations: [row], isBrandVerified: true
        )
        XCTAssertTrue(before.isAllowed)
    }

    func testAuthorizeRevokedAndWrongDict() {
        let revoked = BrandAuthorization(
            brandDictId: 10, brandName: "Spark",
            startsAt: date("2025-01-01T00:00:00Z"),
            expiresAt: date("2027-01-01T16:00:00Z"),
            status: .revoked
        )
        let other = BrandAuthorization(
            brandDictId: 11, brandName: "Nova",
            startsAt: date("2025-01-01T00:00:00Z"),
            expiresAt: date("2027-01-01T16:00:00Z"),
            status: .active
        )
        let r = BrandAuthorizeLogic.authorize(
            brandDictId: 10, brandName: "Spark",
            at: date("2026-06-01T00:00:00Z"),
            authorizations: [revoked, other],
            isBrandVerified: true
        )
        XCTAssertEqual(r.errorCode, .brandNotAuthorized)

        let wrong = BrandAuthorizeLogic.authorize(
            brandDictId: 99, brandName: "Ghost",
            at: date("2026-06-01T00:00:00Z"),
            authorizations: [other],
            isBrandVerified: true
        )
        XCTAssertEqual(wrong.errorCode, .brandNotAuthorized)
        XCTAssertTrue(wrong.message.contains("Nova"))
    }

    func testAuthorizeNotStartedAndNotVerifiedAndDictOther() {
        let future = BrandAuthorization(
            brandDictId: 10, brandName: "Spark",
            startsAt: date("2027-01-01T00:00:00Z"),
            expiresAt: date("2028-01-01T16:00:00Z"),
            status: .active
        )
        let notStarted = BrandAuthorizeLogic.authorize(
            brandDictId: 10, brandName: nil,
            at: date("2026-06-01T00:00:00Z"),
            authorizations: [future], isBrandVerified: true
        )
        XCTAssertEqual(notStarted.errorCode, .brandNotAuthorized)

        let unverified = BrandAuthorizeLogic.authorize(
            brandDictId: 10, brandName: "Spark",
            at: date("2026-06-01T00:00:00Z"),
            authorizations: [future], isBrandVerified: false
        )
        XCTAssertEqual(unverified.errorCode, .brandNotVerified)

        let other = BrandAuthorizeLogic.authorize(
            brandDictId: nil, brandName: "其他",
            at: date("2026-06-01T00:00:00Z"),
            authorizations: [], isBrandVerified: true
        )
        XCTAssertEqual(other.errorCode, .brandNotAuthorized)
        XCTAssertTrue(other.message.contains("其他"))
    }

    func testMultiAuthOnlyExpiredBlocksThatBrand() {
        let expired = BrandAuthorization(
            brandDictId: 1, brandName: "A",
            startsAt: date("2024-01-01T00:00:00Z"),
            expiresAt: date("2025-01-01T16:00:00Z"),
            status: .expired
        )
        let active = BrandAuthorization(
            brandDictId: 2, brandName: "B",
            startsAt: date("2024-01-01T00:00:00Z"),
            expiresAt: date("2027-01-01T16:00:00Z"),
            status: .active
        )
        let now = date("2026-06-01T00:00:00Z")
        XCTAssertEqual(
            BrandAuthorizeLogic.authorize(brandDictId: 1, brandName: "A", at: now, authorizations: [expired, active], isBrandVerified: true).errorCode,
            .brandAuthExpired
        )
        XCTAssertTrue(
            BrandAuthorizeLogic.authorize(brandDictId: 2, brandName: "B", at: now, authorizations: [expired, active], isBrandVerified: true).isAllowed
        )
        let form = BrandAuthorizeLogic.activeForForm([expired, active], at: now)
        XCTAssertEqual(form.map(\.brandDictId), [2])
    }

    func testRemindBand() {
        XCTAssertEqual(BrandAuthorizeLogic.remindBand(daysUntilExpiry: 30), .yellow)
        XCTAssertEqual(BrandAuthorizeLogic.remindBand(daysUntilExpiry: 7), .red)
        XCTAssertEqual(BrandAuthorizeLogic.remindBand(daysUntilExpiry: 1), .red)
        XCTAssertNil(BrandAuthorizeLogic.remindBand(daysUntilExpiry: 31))
        XCTAssertNil(BrandAuthorizeLogic.remindBand(daysUntilExpiry: nil))
    }

    // MARK: Follow / N-10

    func testFollowGates() {
        XCTAssertEqual(BrandFollowLogic.canFollow(isLoggedIn: false), .followLoginRequired)
        XCTAssertNil(BrandFollowLogic.canFollow(isLoggedIn: true))
        XCTAssertEqual(BrandFollowLogic.canAddFollow(currentCount: 200), .followLimitExceeded)
        XCTAssertNil(BrandFollowLogic.canAddFollow(currentCount: 199))
    }

    func testFollowIdempotentMerge() {
        let store = BrandStorePage(id: 7, storeName: "示例品牌店", followerCount: 10, viewerFollowing: false)
        let first = BrandFollowLogic.applyFollowSuccess(
            store: store,
            response: BrandFollowResponse(alreadyFollowing: false, muted: false, followerCount: 11)
        )
        XCTAssertEqual(first.viewerFollowing, true)
        XCTAssertEqual(first.followerCount, 11)
        XCTAssertEqual(first.viewerMuted, false)

        let again = BrandFollowLogic.applyFollowSuccess(
            store: first,
            response: BrandFollowResponse(alreadyFollowing: true, muted: false)
        )
        XCTAssertEqual(again.followerCount, 11) // no double-count
        XCTAssertEqual(again.followTitle, BrandStoreCopy.followingReminderOn)

        let unfollowed = BrandFollowLogic.applyUnfollowSuccess(store: again)
        XCTAssertEqual(unfollowed.viewerFollowing, false)
        XCTAssertEqual(unfollowed.followerCount, 10)
        XCTAssertNil(unfollowed.viewerMuted)
    }

    func testN10Schedule() {
        let start = date("2026-11-05T12:00:00Z")
        let early = date("2026-11-05T10:00:00Z")
        let fire = BrandFollowLogic.n10FireAt(startAt: start, now: early)
        XCTAssertEqual(fire, date("2026-11-05T11:55:00Z"))

        let inside = date("2026-11-05T11:58:00Z")
        let immediate = BrandFollowLogic.n10FireAt(startAt: start, now: inside)
        XCTAssertEqual(immediate, inside)
        XCTAssertTrue(BrandFollowLogic.shouldSendN10(startAt: start, now: inside))
        XCTAssertFalse(BrandFollowLogic.shouldSendN10(startAt: start, now: date("2026-11-05T12:00:01Z")))
    }

    func testFollowButtonTitles() {
        XCTAssertEqual(BrandFollowLogic.followButtonTitle(following: false, muted: nil), BrandStoreCopy.follow)
        XCTAssertEqual(BrandFollowLogic.followButtonTitle(following: true, muted: false), BrandStoreCopy.followingReminderOn)
        XCTAssertEqual(BrandFollowLogic.followButtonTitle(following: true, muted: true), BrandStoreCopy.followingMuted)
    }

    // MARK: Validation / status

    func testStoreNameValidation() {
        XCTAssertNil(BrandStoreValidation.storeNameError("示例品牌店"))
        XCTAssertNotNil(BrandStoreValidation.storeNameError(""))
        XCTAssertNotNil(BrandStoreValidation.storeNameError(String(repeating: "啊", count: 21)))
        XCTAssertNotNil(BrandStoreValidation.storeNameError("加微信abc"))
        XCTAssertNotNil(BrandStoreValidation.announcementError(String(repeating: "公", count: 501)))
        XCTAssertNil(BrandStoreValidation.announcementError("ok"))
    }

    func testStoreStatusFlags() {
        XCTAssertTrue(BrandStoreStatus.frozen.isReadOnly)
        XCTAssertFalse(BrandStoreStatus.frozen.allowsFollowReminders)
        XCTAssertTrue(BrandStoreStatus.live.allowsFollowReminders)
        XCTAssertTrue(BrandStoreStatus.live.showsAsPublicStore)
        XCTAssertFalse(BrandAuthorizationStatus.expired.allowsPublish)
        XCTAssertTrue(BrandAuthorizationStatus.active.allowsPublish)
        XCTAssertEqual(BrandProofType.authLetter.displayLabel, "品牌授权书")
    }

    func testSectionOrderMatchesDesign() {
        XCTAssertEqual(
            BrandStoreSection.allCases.map(\.rawValue),
            ["banner", "identity", "follow", "announcement", "onSale", "calendar", "intro", "footer"]
        )
    }

    // MARK: Decoding

    func testDecodeStoreAggregate() throws {
        let json = """
        {
          "id": 42,
          "seller_id": 42,
          "store_name": "示例品牌店",
          "logo": "https://cdn/logo.png",
          "banner": "https://cdn/banner.png",
          "intro": "厂牌介绍",
          "announcement": "本周上新",
          "badge": "brand_official",
          "status": "live",
          "follower_count": 128,
          "on_sale_count": 3,
          "upcoming_releases": [
            {
              "id": 9,
              "title": "冬季发售",
              "start_at": "2026-12-01T04:00:00Z",
              "release_mode": "spot"
            }
          ],
          "on_sale_items": [
            { "listing_id": 100, "title": "车模 A", "price": 19900, "trade_type": "fixed" }
          ],
          "viewer_following": true,
          "viewer_muted": false,
          "viewer_vip": { "level": 2, "level_name": "银卡", "spend_fen": 50000 }
        }
        """.data(using: .utf8)!
        let page = try decoder.decode(BrandStorePage.self, from: json)
        XCTAssertEqual(page.id, 42)
        XCTAssertEqual(page.storeName, "示例品牌店")
        XCTAssertTrue(page.isOfficialBadge)
        XCTAssertEqual(page.officialBadgeLabel, "品牌官方")
        XCTAssertEqual(page.followerCount, 128)
        XCTAssertEqual(page.upcomingReleases.count, 1)
        XCTAssertEqual(page.upcomingReleases[0].modeLabel, "现货")
        XCTAssertEqual(page.onSaleItems.count, 1)
        XCTAssertFalse(page.onSaleItems[0].isStoreOnSaleVisible) // fixed excluded from brand 在售
        XCTAssertTrue(BrandOnSaleItem(listingId: 1, tradeType: "release").isStoreOnSaleVisible)
        XCTAssertTrue(BrandOnSaleItem(listingId: 2, tradeType: "auction").isStoreOnSaleVisible)
        XCTAssertEqual(page.viewerFollowing, true)
        XCTAssertTrue(page.showsVipStrip)
        XCTAssertTrue(page.viewerVip!.displayLine.contains("Lv.2"))
        XCTAssertEqual(page.followTitle, BrandStoreCopy.followingReminderOn)
        XCTAssertEqual(page.status, .live)
    }

    func testDecodeFollowResponseAndCalendarGroup() throws {
        let follow = try decoder.decode(
            BrandFollowResponse.self,
            from: Data(#"{"already_following":true,"muted":false,"follower_count":12,"following":true}"#.utf8)
        )
        XCTAssertEqual(follow.alreadyFollowing, true)
        XCTAssertEqual(follow.followerCount, 12)

        let cal = BrandReleaseCalendarResponse(items: [
            BrandUpcomingRelease(id: 1, title: "A", startAt: date("2026-12-01T04:00:00Z")),
            BrandUpcomingRelease(id: 2, title: "B", startAt: date("2026-12-01T08:00:00Z")),
            BrandUpcomingRelease(id: 3, title: "C", startAt: date("2026-12-02T04:00:00Z")),
        ])
        let groups = cal.groupedByDay()
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].releases.map(\.id), [1, 2])
        XCTAssertEqual(groups[1].releases.map(\.id), [3])
    }

    func testDecodeAuthorizationList() throws {
        let json = """
        {
          "items": [
            {
              "id": 1,
              "seller_id": 42,
              "brand_dict_id": 10,
              "brand_name": "Spark",
              "proof_type": "auth_letter",
              "starts_at": "2026-01-01T00:00:00Z",
              "expires_at": "2027-01-01T16:00:00Z",
              "status": "active"
            }
          ]
        }
        """.data(using: .utf8)!
        let list = try decoder.decode(BrandAuthorizationListResponse.self, from: json)
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items[0].proofType, .authLetter)
        XCTAssertTrue(list.items[0].isActive(at: date("2026-06-01T00:00:00Z")))
        XCTAssertEqual(list.items[0].expiresAtDisplay.count, 10)
    }

    func testSellerBadgeBrandOfficialStillDecodes() throws {
        let badge = try decoder.decode(SellerBadge.self, from: Data("\"brand_official\"".utf8))
        XCTAssertEqual(badge, .brandOfficial)
        XCTAssertEqual(badge.label, "品牌官方")
    }
}
