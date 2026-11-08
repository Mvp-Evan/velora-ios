import XCTest
@testable import VeloraCore

final class CommunityModelsTests: XCTestCase {

    // MARK: Config / flags

    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(CommunityConfigDefaults.ugcFlagKey, "community.ugc")
        XCTAssertFalse(CommunityConfigDefaults.ugcEnabledDefault)
        XCTAssertEqual(CommunityConfigDefaults.followRatePerMin, 30)
        XCTAssertEqual(CommunityConfigDefaults.newsPageSize, 20)
        XCTAssertEqual(CommunityConfigDefaults.rankTopN, 5)
        XCTAssertEqual(CommunityConfigDefaults.kolBoostDefault, 1.2, accuracy: 0.001)
        XCTAssertEqual(CommunityConfigDefaults.brandDisplayName, "毂毂")
    }

    // MARK: Error codes / copy

    func testErrorNormalizeAndCopy() {
        XCTAssertEqual(CommunityErrorCode.normalize("cannot_follow_self"), .cannotFollowSelf)
        XCTAssertEqual(CommunityErrorCode.normalize("self_follow"), .cannotFollowSelf)
        XCTAssertEqual(CommunityErrorCode.normalize("blocked_by_peer"), .blockedByPeer)
        XCTAssertEqual(CommunityErrorCode.normalize("user_blocked"), .blockedByPeer)
        XCTAssertEqual(CommunityErrorCode.normalize("ugc_disabled"), .ugcDisabled)
        XCTAssertEqual(CommunityErrorCode.normalize("account_restricted"), .accountRestricted)
        XCTAssertEqual(CommunityErrorCode.cannotFollowSelf.fallbackMessage, CommunityCopy.cannotFollowSelf)
        XCTAssertEqual(CommunityErrorCode.blockedByPeer.fallbackMessage, CommunityCopy.blockedByPeer)
        XCTAssertTrue(CommunityCopy.blockedByPeer.contains("拉黑"))
        XCTAssertEqual(CommunityCopy.emptyPreview, "本周预展即将上线")
    }

    func testRollbackContract403409() {
        XCTAssertTrue(CommunityFollowLogic.shouldRollbackFollow(httpStatus: 403))
        XCTAssertTrue(CommunityFollowLogic.shouldRollbackFollow(httpStatus: 409))
        XCTAssertFalse(CommunityFollowLogic.shouldRollbackFollow(httpStatus: 200))
        XCTAssertTrue(CommunityFollowLogic.shouldRollbackFollow(httpStatus: 400, code: "cannot_follow_self"))
        XCTAssertTrue(CommunityFollowLogic.shouldRollbackFollow(httpStatus: 400, code: "blocked_by_peer"))
        XCTAssertTrue(CommunityErrorCode.cannotFollowSelf.requiresFollowRollback)
        XCTAssertTrue(CommunityErrorCode.blockedByPeer.requiresFollowRollback)
    }

    // MARK: Follow gates / optimistic

    func testFollowGates() {
        XCTAssertEqual(
            CommunityFollowLogic.canFollow(isLoggedIn: false, viewerId: nil, followeeId: 2),
            .followLoginRequired
        )
        XCTAssertEqual(
            CommunityFollowLogic.canFollow(isLoggedIn: true, viewerId: 9, followeeId: 9),
            .cannotFollowSelf
        )
        XCTAssertNil(
            CommunityFollowLogic.canFollow(isLoggedIn: true, viewerId: 9, followeeId: 10)
        )
        // Brand self id coincidence is allowed (store id ≠ viewer user id semantics).
        XCTAssertNil(
            CommunityFollowLogic.canFollow(
                isLoggedIn: true, viewerId: 9, followeeId: 9, followeeType: .brand
            )
        )
    }

    func testOptimisticApplyAndRollback() {
        let followed = CommunityFollowLogic.applyOptimistic(
            following: false, followerCount: 10, targetFollowing: true
        )
        XCTAssertTrue(followed.following)
        XCTAssertEqual(followed.followerCount, 11)

        let unfollowed = CommunityFollowLogic.applyOptimistic(
            following: true, followerCount: 11, targetFollowing: false
        )
        XCTAssertFalse(unfollowed.following)
        XCTAssertEqual(unfollowed.followerCount, 10)

        let rolled = CommunityFollowLogic.rollback(
            following: true, followerCount: 11,
            previousFollowing: false, previousCount: 10
        )
        XCTAssertFalse(rolled.following)
        XCTAssertEqual(rolled.followerCount, 10)
    }

    func testFollowIdempotentMerge() {
        let first = CommunityFollowLogic.applyFollowSuccess(
            following: false,
            followerCount: 3,
            response: CommunityFollowResponse(alreadyFollowing: false, followerCount: 4)
        )
        XCTAssertTrue(first.following)
        XCTAssertEqual(first.followerCount, 4)

        let again = CommunityFollowLogic.applyFollowSuccess(
            following: true,
            followerCount: 4,
            response: CommunityFollowResponse(alreadyFollowing: true)
        )
        XCTAssertEqual(again.followerCount, 4)

        let gone = CommunityFollowLogic.applyUnfollowSuccess(following: true, followerCount: 4)
        XCTAssertFalse(gone.following)
        XCTAssertEqual(gone.followerCount, 3)
    }

    func testComposeHiddenUntilUgcFlag() {
        XCTAssertFalse(CommunityFollowLogic.showsComposeButton(ugcEnabled: false))
        XCTAssertTrue(CommunityFollowLogic.showsComposeButton(ugcEnabled: true))
    }

    func testTabPlaceholder() {
        XCTAssertEqual(
            CommunityFollowLogic.tabPlaceholder(isLoading: false, hasItems: false, feedEnabled: false),
            .emptyPreview
        )
        XCTAssertEqual(
            CommunityFollowLogic.tabPlaceholder(isLoading: true, hasItems: false, feedEnabled: true),
            .skeleton
        )
        XCTAssertEqual(
            CommunityFollowLogic.tabPlaceholder(isLoading: false, hasItems: true, feedEnabled: true),
            .feed
        )
    }

    // MARK: Profile DTO — no phone

    func testPublicProfileDecodeOmitsPhone() throws {
        let json = """
        {
          "id": 42,
          "nickname": "赛车店主",
          "avatar": "https://cdn/a.jpg",
          "bio": "hello",
          "credit_score": 110,
          "sold_count": 3,
          "won_count": 1,
          "lot_count": 2,
          "identity": "proxy_gold",
          "follower_count": 12,
          "viewer_following": false,
          "on_sale_count": 1,
          "on_sale_items": [
            {"listing_id": 9, "title": "RX-78", "price": 250000}
          ]
        }
        """.data(using: .utf8)!
        let profile = try JSONDecoder.veloraTest.decode(PublicUserProfile.self, from: json)
        XCTAssertEqual(profile.id, 42)
        XCTAssertEqual(profile.resolvedIdentity, .proxyGold)
        XCTAssertEqual(profile.followerCount, 12)
        XCTAssertEqual(profile.onSaleItems.count, 1)
        XCTAssertEqual(profile.onSaleItems[0].listingId, 9)
        XCTAssertEqual(profile.followTitle, CommunityCopy.follow)

        let encoded = try JSONEncoder.veloraTest.encode(profile)
        let obj = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertNotNil(obj)
        for key in PublicUserProfile.forbiddenPublicKeys {
            XCTAssertNil(obj?[key], "public profile must not encode \(key)")
        }
        // Even if server leaked phone in JSON, our CodingKeys ignore it:
        let leaky = """
        {"id":1,"nickname":"x","phone":"13800000001","phone_masked":"138****0001","address":"secret"}
        """.data(using: .utf8)!
        let scrubbed = try JSONDecoder.veloraTest.decode(PublicUserProfile.self, from: leaky)
        let scrubbedData = try JSONEncoder.veloraTest.encode(scrubbed)
        let scrubbedObj = try JSONSerialization.jsonObject(with: scrubbedData) as? [String: Any]
        XCTAssertNil(scrubbedObj?["phone"])
        XCTAssertNil(scrubbedObj?["phone_masked"])
        XCTAssertNil(scrubbedObj?["address"])
    }

    func testIdentityAndNewsNormalize() {
        XCTAssertEqual(ProfileIdentity.normalize("gold_proxy"), .proxyGold)
        XCTAssertEqual(ProfileIdentity.normalize("kol"), .kol)
        XCTAssertEqual(NewsPostType.normalize("weekly_rank"), .weeklyRank)
        XCTAssertTrue(NewsPostType.normalize("future_type").treatsAsPlainCard)
        XCTAssertEqual(NewsMountStatus.normalize("invalid"), .invalid)
        XCTAssertTrue(NewsMountStatus.invalid.isPurchaseDisabled)
        XCTAssertTrue(NewsPostStatus.published.isVisibleToConsumer)
        XCTAssertFalse(NewsPostStatus.draft.isVisibleToConsumer)
        XCTAssertEqual(FolloweeType.normalize("brand_store"), .brand)
    }

    func testFollowerCountLabel() {
        XCTAssertEqual(CommunityCopy.followerCountLabel(12), "12 粉丝")
        XCTAssertTrue(CommunityCopy.followerCountLabel(12_000).contains("万"))
    }

    // MARK: FakeAPIClient + ViewModels

    @MainActor
    func testFakeFollowOptimisticAnd403Rollback() async throws {
        let fake = FakeAPIClient()
        await fake.seedUserProfile(PublicUserProfile(
            id: 7,
            nickname: "卖家",
            followerCount: 5,
            viewerFollowing: false,
            onSaleItems: [ProfileOnSaleItem(listingId: 1, title: "在售A")]
        ))
        await fake.setFollowError(code: "blocked_by_peer", status: 403)

        let vm = UserProfileFollowViewModel(userId: 7, client: fake, viewerId: 1, isLoggedIn: true)
        await vm.load()
        XCTAssertEqual(vm.profile?.followerCount, 5)
        XCTAssertFalse(vm.isFollowing)

        let ok = await vm.toggleFollow()
        XCTAssertFalse(ok)
        XCTAssertEqual(vm.lastErrorCode, "blocked_by_peer")
        XCTAssertEqual(vm.lastErrorStatus, 403)
        XCTAssertFalse(vm.isFollowing)
        XCTAssertEqual(vm.profile?.followerCount, 5) // rolled back
    }

    @MainActor
    func testFakeFollowSuccessAndCannotFollowSelf() async throws {
        let fake = FakeAPIClient()
        await fake.seedUserProfile(PublicUserProfile(
            id: 7, nickname: "卖家", followerCount: 2, viewerFollowing: false
        ))

        let vm = UserProfileFollowViewModel(userId: 7, client: fake, viewerId: 1)
        await vm.load()
        let ok = await vm.toggleFollow()
        XCTAssertTrue(ok)
        XCTAssertTrue(vm.isFollowing)
        XCTAssertEqual(vm.profile?.followerCount, 3)

        let selfVM = UserProfileFollowViewModel(userId: 1, client: fake, viewerId: 1)
        await fake.seedUserProfile(PublicUserProfile(id: 1, nickname: "我"))
        await selfVM.load()
        let selfOk = await selfVM.toggleFollow()
        XCTAssertFalse(selfOk)
        XCTAssertEqual(selfVM.lastErrorCode, CommunityErrorCode.cannotFollowSelf.rawValue)
    }

    @MainActor
    func testFake409RollbackAndBrandFollow() async throws {
        let fake = FakeAPIClient()
        await fake.seedUserProfile(PublicUserProfile(
            id: 8, nickname: "B", followerCount: 1, viewerFollowing: false
        ))
        await fake.setFollowError(code: "follow_rate_limited", status: 409)
        let vm = UserProfileFollowViewModel(userId: 8, client: fake, viewerId: 1)
        await vm.load()
        let rolled = await vm.toggleFollow()
        XCTAssertFalse(rolled)
        XCTAssertEqual(vm.lastErrorStatus, 409)
        XCTAssertFalse(vm.isFollowing)

        await fake.setFollowError(code: nil)
        let brand = try await fake.followBrand(brandId: 3, idempotencyKey: "k1")
        XCTAssertEqual(brand.following, true)
        XCTAssertEqual(brand.followerCount, 1)
        try await fake.unfollowBrand(brandId: 3, idempotencyKey: "k2")
        let calls = await fake.followCalls
        XCTAssertEqual(calls.filter { $0.targetType == .brand }.count, 2)
    }

    @MainActor
    func testCommunityFeedEmptyAndComposeHidden() async {
        let fake = FakeAPIClient()
        let vm = CommunityFeedViewModel(client: fake, feedEnabled: false, ugcEnabled: false)
        await vm.load()
        XCTAssertEqual(vm.placeholder, .emptyPreview)
        XCTAssertFalse(vm.showsCompose)
        XCTAssertTrue(vm.items.isEmpty)

        await fake.seedNewsFeed(NewsFeedResponse(items: [
            NewsPostCard(id: 1, type: "preview", title: "预展", mountStatus: "live"),
        ]))
        let feedVM = CommunityFeedViewModel(client: fake, feedEnabled: true, ugcEnabled: true)
        await feedVM.load()
        XCTAssertEqual(feedVM.placeholder, .feed)
        XCTAssertTrue(feedVM.showsCompose)
        XCTAssertEqual(feedVM.items.first?.resolvedType, .preview)
    }

    @MainActor
    func testGuestFollowOpensLogin() async {
        let fake = FakeAPIClient()
        await fake.seedUserProfile(PublicUserProfile(id: 2, nickname: "x"))
        let vm = UserProfileFollowViewModel(userId: 2, client: fake, isLoggedIn: false)
        await vm.load()
        let gated = await vm.toggleFollow()
        XCTAssertFalse(gated)
        XCTAssertTrue(vm.needsLogin)
        XCTAssertEqual(vm.lastErrorCode, CommunityErrorCode.followLoginRequired.rawValue)
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

private extension JSONEncoder {
    static var veloraTest: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
