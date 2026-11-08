import Foundation

// MARK: - Fake API client (DES-v1.3-12-02 / D40 + DES-v1.3-12-03 / D41 + DES-v1.3-12-04 / D42)

/// Surface used by review / credit ViewModels so tests inject fixtures without network IO.
@available(iOS 17.0, macOS 14.0, *)
public protocol ReviewCreditAPIClient: Sendable {
    func submitOrderReview(
        orderId: Int64,
        request: SubmitOrderReviewRequest,
        idempotencyKey: String
    ) async throws -> OrderReview

    func orderReviews(orderId: Int64) async throws -> OrderReviewsResponse

    func userReviews(userId: Int64, cursor: String?, pageSize: Int) async throws -> UserReviewsListResponse

    func meCredit() async throws -> MeCreditResponse

    func sellerCard(userId: Int64) async throws -> SellerCardMetrics
}

/// Community follow / public profile / news feed (DES-v1.3-12-03 / D41).
@available(iOS 17.0, macOS 14.0, *)
public protocol CommunityAPIClient: Sendable {
    func userProfile(userId: Int64) async throws -> PublicUserProfile

    func followUser(userId: Int64, idempotencyKey: String) async throws -> CommunityFollowResponse

    func unfollowUser(userId: Int64, idempotencyKey: String) async throws

    func followBrand(brandId: Int64, idempotencyKey: String) async throws -> CommunityFollowResponse

    func unfollowBrand(brandId: Int64, idempotencyKey: String) async throws

    func newsFeed(page: Int, pageSize: Int) async throws -> NewsFeedResponse
}

/// Product library / cabinet / curve / badges (DES-v1.3-12-04 / D42) — Phase 3 stubs.
@available(iOS 17.0, macOS 14.0, *)
public protocol LibraryAPIClient: Sendable {
    func listSKUs(cursor: String?, pageSize: Int) async throws -> SkuListResponse

    func skuDetail(skuId: Int64) async throws -> ProductSKU

    func skuCurve(skuId: Int64) async throws -> SkuCurveResponse

    func userCabinet(userId: Int64, cursor: String?, pageSize: Int) async throws -> CabinetWallResponse

    func meCabinetSummary() async throws -> CabinetSummaryResponse

    func meBadges() async throws -> [SeriesBadge]

    func addManualCabinet(body: ManualCabinetBody, idempotencyKey: String) async throws -> CabinetItem

    func setWishlist(skuId: Int64, body: WishlistWriteBody, idempotencyKey: String) async throws

    func removeWishlist(skuId: Int64, idempotencyKey: String) async throws
}

/// In-memory fake for unit tests / previews. Mutate stored fixtures between calls.
@available(iOS 17.0, macOS 14.0, *)
public actor FakeAPIClient: ReviewCreditAPIClient, CommunityAPIClient, LibraryAPIClient {
    public var orderReviewsById: [Int64: OrderReviewsResponse] = [:]
    public var userReviewsById: [Int64: UserReviewsListResponse] = [:]
    public var meCreditResponse: MeCreditResponse = MeCreditResponse()
    public var sellerCardsById: [Int64: SellerCardMetrics] = [:]
    public var submitErrorCode: String?
    public var meCreditErrorCode: String?
    public var submitted: [(orderId: Int64, request: SubmitOrderReviewRequest, key: String)] = []
    public private(set) var lastIdempotencyKey: String?

    // Community / follow (D41)
    public var profilesById: [Int64: PublicUserProfile] = [:]
    public var brandFollowState: [Int64: (following: Bool, count: Int)] = [:]
    public var newsFeedResponse: NewsFeedResponse = NewsFeedResponse()
    public var followErrorCode: String?
    public var followErrorStatus: Int = 403
    public var viewerId: Int64 = 1
    public var ugcEnabled: Bool = CommunityConfigDefaults.ugcEnabledDefault
    public private(set) var followCalls: [(targetType: FolloweeType, id: Int64, follow: Bool)] = []

    // Library / cabinet (D42) — Phase 3 defaults: curve flag off, empty lists
    public var libraryCurveEnabled: Bool = LibraryConfigDefaults.curveEnabledDefault
    public var skusById: [Int64: ProductSKU] = [:]
    public var skuList: [ProductSKU] = []
    public var curvesBySkuId: [Int64: SkuCurveResponse] = [:]
    public var cabinetsByUserId: [Int64: CabinetWallResponse] = [:]
    public var meCabinetSummaryResponse: CabinetSummaryResponse = CabinetSummaryResponse()
    public var meBadgesResponse: [SeriesBadge] = []
    public var libraryErrorCode: String?
    public var libraryErrorStatus: Int = 409
    public var wishlistSkuIds: Set<Int64> = []
    public private(set) var cabinetWrites: [ManualCabinetBody] = []
    public private(set) var wishlistWrites: [(skuId: Int64, kind: WishlistKind?, remove: Bool)] = []

    public init() {}

    public func reset() {
        orderReviewsById = [:]
        userReviewsById = [:]
        meCreditResponse = MeCreditResponse()
        sellerCardsById = [:]
        submitErrorCode = nil
        meCreditErrorCode = nil
        submitted = []
        lastIdempotencyKey = nil
        profilesById = [:]
        brandFollowState = [:]
        newsFeedResponse = NewsFeedResponse()
        followErrorCode = nil
        followErrorStatus = 403
        viewerId = 1
        ugcEnabled = CommunityConfigDefaults.ugcEnabledDefault
        followCalls = []
        libraryCurveEnabled = LibraryConfigDefaults.curveEnabledDefault
        skusById = [:]
        skuList = []
        curvesBySkuId = [:]
        cabinetsByUserId = [:]
        meCabinetSummaryResponse = CabinetSummaryResponse()
        meBadgesResponse = []
        libraryErrorCode = nil
        libraryErrorStatus = 409
        wishlistSkuIds = []
        cabinetWrites = []
        wishlistWrites = []
    }

    public func seedOrderReviews(_ response: OrderReviewsResponse, orderId: Int64? = nil) {
        let id = orderId ?? response.orderId
        orderReviewsById[id] = response
    }

    public func seedUserReviews(_ response: UserReviewsListResponse, userId: Int64) {
        userReviewsById[userId] = response
    }

    public func seedMeCredit(_ response: MeCreditResponse) {
        meCreditResponse = response
    }

    public func seedSellerCard(_ card: SellerCardMetrics, userId: Int64) {
        sellerCardsById[userId] = card
    }

    public func submitOrderReview(
        orderId: Int64,
        request: SubmitOrderReviewRequest,
        idempotencyKey: String
    ) async throws -> OrderReview {
        lastIdempotencyKey = idempotencyKey
        if let code = submitErrorCode {
            throw FakeAPIError(code: code, message: ReviewCreditErrorCode.normalize(code)?.fallbackMessage ?? code)
        }
        submitted.append((orderId, request, idempotencyKey))
        let review = OrderReview(
            id: Int64(submitted.count),
            orderId: orderId,
            role: ReviewRole.buyerToSeller.rawValue,
            rating: request.rating.rawValue,
            content: request.content,
            imageUrls: [],
            source: ReviewSource.user.rawValue,
            arbitrationTag: orderReviewsById[orderId]?.items.first?.arbitrationTag ?? false,
            status: ReviewStatus.published.rawValue,
            publishedAt: Date()
        )
        var existing = orderReviewsById[orderId] ?? OrderReviewsResponse(orderId: orderId)
        var items = existing.items.filter { !$0.isPending || $0.resolvedRole != .buyerToSeller }
        items.append(review)
        existing = OrderReviewsResponse(
            orderId: orderId,
            buyerToSeller: review,
            sellerToBuyer: existing.sellerToBuyer,
            items: items,
            reviewDeadline: existing.reviewDeadline,
            myPending: false,
            serverTime: existing.serverTime
        )
        orderReviewsById[orderId] = existing
        return review
    }

    public func orderReviews(orderId: Int64) async throws -> OrderReviewsResponse {
        if let r = orderReviewsById[orderId] { return r }
        return OrderReviewsResponse(orderId: orderId, items: [])
    }

    public func userReviews(userId: Int64, cursor: String?, pageSize: Int) async throws -> UserReviewsListResponse {
        _ = cursor
        _ = pageSize
        return userReviewsById[userId] ?? UserReviewsListResponse()
    }

    public func meCredit() async throws -> MeCreditResponse {
        if let code = meCreditErrorCode {
            throw FakeAPIError(code: code, message: ReviewCreditErrorCode.normalize(code)?.fallbackMessage ?? code)
        }
        return meCreditResponse
    }

    public func sellerCard(userId: Int64) async throws -> SellerCardMetrics {
        sellerCardsById[userId] ?? SellerCardMetrics(userId: userId, stale: true)
    }

    // MARK: CommunityAPIClient

    public func seedUserProfile(_ profile: PublicUserProfile) {
        profilesById[profile.id] = profile
    }

    public func seedNewsFeed(_ response: NewsFeedResponse) {
        newsFeedResponse = response
    }

    public func setFollowError(code: String?, status: Int = 403) {
        followErrorCode = code
        followErrorStatus = status
    }

    public func userProfile(userId: Int64) async throws -> PublicUserProfile {
        if let p = profilesById[userId] { return p }
        throw FakeAPIError(code: CommunityErrorCode.userNotFound.rawValue, message: CommunityCopy.userNotFound, status: 404)
    }

    public func followUser(userId: Int64, idempotencyKey: String) async throws -> CommunityFollowResponse {
        lastIdempotencyKey = idempotencyKey
        try throwFollowErrorIfNeeded()
        if userId == viewerId {
            throw FakeAPIError(
                code: CommunityErrorCode.cannotFollowSelf.rawValue,
                message: CommunityCopy.cannotFollowSelf,
                status: 403
            )
        }
        guard var profile = profilesById[userId] else {
            throw FakeAPIError(code: CommunityErrorCode.userNotFound.rawValue, message: CommunityCopy.userNotFound, status: 404)
        }
        let already = profile.viewerFollowing == true
        if !already {
            profile.viewerFollowing = true
            profile.followerCount += 1
            profilesById[userId] = profile
        }
        followCalls.append((.user, userId, true))
        return CommunityFollowResponse(
            alreadyFollowing: already,
            followerCount: profile.followerCount,
            following: true
        )
    }

    public func unfollowUser(userId: Int64, idempotencyKey: String) async throws {
        lastIdempotencyKey = idempotencyKey
        try throwFollowErrorIfNeeded()
        guard var profile = profilesById[userId] else {
            throw FakeAPIError(code: CommunityErrorCode.userNotFound.rawValue, message: CommunityCopy.userNotFound, status: 404)
        }
        if profile.viewerFollowing == true {
            profile.viewerFollowing = false
            profile.followerCount = max(0, profile.followerCount - 1)
            profilesById[userId] = profile
        }
        followCalls.append((.user, userId, false))
    }

    public func followBrand(brandId: Int64, idempotencyKey: String) async throws -> CommunityFollowResponse {
        lastIdempotencyKey = idempotencyKey
        try throwFollowErrorIfNeeded()
        var state = brandFollowState[brandId] ?? (false, 0)
        let already = state.following
        if !already {
            state = (true, state.count + 1)
            brandFollowState[brandId] = state
        }
        followCalls.append((.brand, brandId, true))
        return CommunityFollowResponse(
            alreadyFollowing: already,
            followerCount: state.count,
            following: true
        )
    }

    public func unfollowBrand(brandId: Int64, idempotencyKey: String) async throws {
        lastIdempotencyKey = idempotencyKey
        try throwFollowErrorIfNeeded()
        var state = brandFollowState[brandId] ?? (false, 0)
        if state.following {
            state = (false, max(0, state.count - 1))
            brandFollowState[brandId] = state
        }
        followCalls.append((.brand, brandId, false))
    }

    public func newsFeed(page: Int, pageSize: Int) async throws -> NewsFeedResponse {
        _ = page
        _ = pageSize
        if !ugcEnabled {
            // Phase 1/2: feed may still return news; ugc flag only gates compose / posts.
        }
        return newsFeedResponse
    }

    private func throwFollowErrorIfNeeded() throws {
        if let code = followErrorCode {
            let msg = CommunityErrorCode.normalize(code)?.fallbackMessage ?? code
            throw FakeAPIError(code: code, message: msg, status: followErrorStatus)
        }
    }

    // MARK: LibraryAPIClient (D42 Phase 3 stubs)

    public func seedSKU(_ sku: ProductSKU) {
        skusById[sku.id] = sku
        if !skuList.contains(where: { $0.id == sku.id }) {
            skuList.append(sku)
        }
    }

    public func seedSkuList(_ items: [ProductSKU]) {
        skuList = items
        for s in items { skusById[s.id] = s }
    }

    public func seedCurve(_ response: SkuCurveResponse, skuId: Int64) {
        curvesBySkuId[skuId] = response
    }

    public func seedCabinet(_ response: CabinetWallResponse, userId: Int64) {
        cabinetsByUserId[userId] = response
    }

    public func seedMeCabinetSummary(_ response: CabinetSummaryResponse) {
        meCabinetSummaryResponse = response
    }

    public func seedMeBadges(_ badges: [SeriesBadge]) {
        meBadgesResponse = badges
    }

    public func setLibraryCurveEnabled(_ enabled: Bool) {
        libraryCurveEnabled = enabled
    }

    public func setLibraryError(code: String?, status: Int = 409) {
        libraryErrorCode = code
        libraryErrorStatus = status
    }

    public func listSKUs(cursor: String?, pageSize: Int) async throws -> SkuListResponse {
        _ = cursor
        _ = pageSize
        try throwLibraryErrorIfNeeded()
        // Phase 3: empty index is the expected shell (design §9「产品库建设中」).
        return SkuListResponse(
            items: skuList,
            total: skuList.count,
            enabled: libraryCurveEnabled
        )
    }

    public func skuDetail(skuId: Int64) async throws -> ProductSKU {
        try throwLibraryErrorIfNeeded()
        if let sku = skusById[skuId] { return sku }
        throw FakeAPIError(
            code: LibraryErrorCode.skuNotFound.rawValue,
            message: LibraryCopy.skuNotFound,
            status: 404
        )
    }

    public func skuCurve(skuId: Int64) async throws -> SkuCurveResponse {
        try throwLibraryErrorIfNeeded()
        // Flag off → never return points (design §13 `library.curve` Phase 3 off).
        if !libraryCurveEnabled {
            throw FakeAPIError(
                code: LibraryErrorCode.libraryNotEnabled.rawValue,
                message: LibraryCopy.curveHidden,
                status: 409
            )
        }
        guard let sku = skusById[skuId] else {
            throw FakeAPIError(
                code: LibraryErrorCode.skuNotFound.rawValue,
                message: LibraryCopy.skuNotFound,
                status: 404
            )
        }
        if let curve = curvesBySkuId[skuId] {
            let n = curve.resolvedSampleN
            if LibraryLogic.showsCurve(
                libraryCurveEnabled: true,
                skuCurveEnabled: sku.isCurveEnabled,
                sampleN: n
            ) {
                return curve
            }
        }
        throw FakeAPIError(
            code: LibraryErrorCode.curveNotReady.rawValue,
            message: LibraryCopy.curveNotReady,
            status: 409
        )
    }

    public func userCabinet(userId: Int64, cursor: String?, pageSize: Int) async throws -> CabinetWallResponse {
        _ = cursor
        _ = pageSize
        try throwLibraryErrorIfNeeded()
        if let wall = cabinetsByUserId[userId] {
            if wall.publicVisible == false, userId != viewerId {
                throw FakeAPIError(
                    code: LibraryErrorCode.cabinetPrivate.rawValue,
                    message: LibraryCopy.cabinetPrivate,
                    status: 403
                )
            }
            return wall
        }
        // Phase 3 empty wall.
        return CabinetWallResponse(items: [], total: 0, publicVisible: true)
    }

    public func meCabinetSummary() async throws -> CabinetSummaryResponse {
        try throwLibraryErrorIfNeeded()
        return meCabinetSummaryResponse
    }

    public func meBadges() async throws -> [SeriesBadge] {
        try throwLibraryErrorIfNeeded()
        return meBadgesResponse
    }

    public func addManualCabinet(body: ManualCabinetBody, idempotencyKey: String) async throws -> CabinetItem {
        lastIdempotencyKey = idempotencyKey
        try throwLibraryErrorIfNeeded()
        cabinetWrites.append(body)
        let item = CabinetItem(
            id: Int64(cabinetWrites.count),
            skuId: body.skuId,
            source: CabinetItemSource.manual.rawValue,
            status: CabinetItemStatus.in.rawValue,
            slotNo: body.slotNo,
            note: body.note,
            sku: skusById[body.skuId]
        )
        var wall = cabinetsByUserId[viewerId] ?? CabinetWallResponse()
        var items = wall.items
        items.append(item)
        wall = CabinetWallResponse(
            items: items,
            total: items.count,
            publicVisible: wall.publicVisible ?? true
        )
        cabinetsByUserId[viewerId] = wall
        return item
    }

    public func setWishlist(skuId: Int64, body: WishlistWriteBody, idempotencyKey: String) async throws {
        lastIdempotencyKey = idempotencyKey
        try throwLibraryErrorIfNeeded()
        if wishlistSkuIds.count >= LibraryConfigDefaults.wishlistMax, !wishlistSkuIds.contains(skuId) {
            throw FakeAPIError(
                code: LibraryErrorCode.wishlistFull.rawValue,
                message: LibraryCopy.wishlistFull,
                status: 409
            )
        }
        wishlistSkuIds.insert(skuId)
        wishlistWrites.append((skuId, body.kind, false))
    }

    public func removeWishlist(skuId: Int64, idempotencyKey: String) async throws {
        lastIdempotencyKey = idempotencyKey
        try throwLibraryErrorIfNeeded()
        wishlistSkuIds.remove(skuId)
        wishlistWrites.append((skuId, nil, true))
    }

    private func throwLibraryErrorIfNeeded() throws {
        if let code = libraryErrorCode {
            let msg = LibraryErrorCode.normalize(code)?.fallbackMessage ?? code
            throw FakeAPIError(code: code, message: msg, status: libraryErrorStatus)
        }
    }
}

public struct FakeAPIError: Error, Equatable, Sendable {
    public let code: String
    public let message: String
    public let status: Int

    public init(code: String, message: String, status: Int = 400) {
        self.code = code
        self.message = message
        self.status = status
    }
}

/// Lightweight ViewModel exercising FakeAPIClient (logic + orchestration; no SwiftUI).
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class ReviewSubmitViewModel {
    public private(set) var rating: ReviewRating?
    public private(set) var content: String = ""
    public private(set) var imageIds: [String] = []
    public private(set) var submittedReview: OrderReview?
    public private(set) var lastErrorCode: String?
    public private(set) var needsBadConfirm = false
    public var confirmBad = false

    private let orderId: Int64
    private let client: any ReviewCreditAPIClient
    private let idempotencyKey: String
    private let isLoggedIn: Bool
    private let isRealNamed: Bool
    private let windowOpen: Bool

    public init(
        orderId: Int64,
        client: any ReviewCreditAPIClient,
        idempotencyKey: String = UUID().uuidString,
        isLoggedIn: Bool = true,
        isRealNamed: Bool = true,
        windowOpen: Bool = true
    ) {
        self.orderId = orderId
        self.client = client
        self.idempotencyKey = idempotencyKey
        self.isLoggedIn = isLoggedIn
        self.isRealNamed = isRealNamed
        self.windowOpen = windowOpen
    }

    public func setRating(_ rating: ReviewRating) {
        self.rating = rating
        needsBadConfirm = rating.requiresSecondaryConfirm
    }

    public func setContent(_ text: String) {
        content = String(text.prefix(ReviewCreditConfigDefaults.reviewContentMax))
    }

    public func setImageIds(_ ids: [String]) {
        imageIds = Array(ids.prefix(ReviewCreditConfigDefaults.reviewMaxImages))
    }

    public func submit() async -> Bool {
        lastErrorCode = nil
        if let gate = ReviewCreditLogic.canSubmitReview(
            rating: rating,
            content: content.isEmpty ? nil : content,
            imageCount: imageIds.count,
            isLoggedIn: isLoggedIn,
            isRealNamed: isRealNamed,
            windowOpen: windowOpen
        ) {
            lastErrorCode = gate.rawValue
            return false
        }
        guard let rating else { return false }
        if rating.requiresSecondaryConfirm && !confirmBad {
            needsBadConfirm = true
            return false
        }
        do {
            submittedReview = try await client.submitOrderReview(
                orderId: orderId,
                request: SubmitOrderReviewRequest(
                    rating: rating,
                    content: content.isEmpty ? nil : content,
                    imageIds: imageIds
                ),
                idempotencyKey: idempotencyKey
            )
            return true
        } catch let e as FakeAPIError {
            lastErrorCode = e.code
            return false
        } catch {
            lastErrorCode = "network"
            return false
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class MeCreditViewModel {
    public private(set) var credit: MeCreditResponse?
    public private(set) var lastErrorCode: String?
    public private(set) var loaded = false

    private let client: any ReviewCreditAPIClient

    public init(client: any ReviewCreditAPIClient) {
        self.client = client
    }

    public func load() async {
        lastErrorCode = nil
        do {
            credit = try await client.meCredit()
            loaded = true
        } catch let e as FakeAPIError {
            lastErrorCode = e.code
            loaded = false
        } catch {
            lastErrorCode = "network"
            loaded = false
        }
    }
}

/// Optimistic follow harness for public user profile (DES-v1.3-12-03 / D41).
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class UserProfileFollowViewModel {
    public private(set) var profile: PublicUserProfile?
    public private(set) var lastErrorCode: String?
    public private(set) var lastErrorStatus: Int?
    public private(set) var followingBusy = false
    public private(set) var needsLogin = false
    public var ugcEnabled: Bool

    private let userId: Int64
    private let client: any CommunityAPIClient
    private let viewerId: Int64?
    private let isLoggedIn: Bool
    private let idempotencyKey: String

    public init(
        userId: Int64,
        client: any CommunityAPIClient,
        viewerId: Int64? = nil,
        isLoggedIn: Bool = true,
        ugcEnabled: Bool = CommunityConfigDefaults.ugcEnabledDefault,
        idempotencyKey: String = UUID().uuidString
    ) {
        self.userId = userId
        self.client = client
        self.viewerId = viewerId
        self.isLoggedIn = isLoggedIn
        self.ugcEnabled = ugcEnabled
        self.idempotencyKey = idempotencyKey
    }

    public var showsCompose: Bool {
        CommunityFollowLogic.showsComposeButton(ugcEnabled: ugcEnabled)
    }

    public var isFollowing: Bool { profile?.viewerFollowing == true }

    public func load() async {
        lastErrorCode = nil
        do {
            profile = try await client.userProfile(userId: userId)
        } catch let e as FakeAPIError {
            lastErrorCode = e.code
            lastErrorStatus = e.status
        } catch {
            lastErrorCode = "network"
        }
    }

    public func toggleFollow() async -> Bool {
        lastErrorCode = nil
        lastErrorStatus = nil
        if let gate = CommunityFollowLogic.canFollow(
            isLoggedIn: isLoggedIn,
            viewerId: viewerId,
            followeeId: userId,
            followeeType: .user
        ) {
            lastErrorCode = gate.rawValue
            if gate.opensLogin { needsLogin = true }
            return false
        }
        guard var p = profile else { return false }
        let previousFollowing = p.viewerFollowing == true
        let previousCount = p.followerCount
        let target = !previousFollowing

        // Optimistic UI (design client duties).
        let optimistic = CommunityFollowLogic.applyOptimistic(
            following: previousFollowing,
            followerCount: previousCount,
            targetFollowing: target
        )
        p.viewerFollowing = optimistic.following
        p.followerCount = optimistic.followerCount
        profile = p
        followingBusy = true
        defer { followingBusy = false }

        do {
            if target {
                let resp = try await client.followUser(userId: userId, idempotencyKey: idempotencyKey)
                let merged = CommunityFollowLogic.applyFollowSuccess(
                    following: previousFollowing,
                    followerCount: previousCount,
                    response: resp
                )
                p.viewerFollowing = merged.following
                p.followerCount = merged.followerCount
            } else {
                try await client.unfollowUser(userId: userId, idempotencyKey: idempotencyKey)
                let merged = CommunityFollowLogic.applyUnfollowSuccess(
                    following: previousFollowing,
                    followerCount: previousCount
                )
                p.viewerFollowing = merged.following
                p.followerCount = merged.followerCount
            }
            profile = p
            return true
        } catch let e as FakeAPIError {
            lastErrorCode = e.code
            lastErrorStatus = e.status
            // Always roll back optimistic UI; 403/409 are the contract cases (design § client).
            _ = CommunityFollowLogic.shouldRollbackFollow(httpStatus: e.status, code: e.code)
            let rolled = CommunityFollowLogic.rollback(
                following: optimistic.following,
                followerCount: optimistic.followerCount,
                previousFollowing: previousFollowing,
                previousCount: previousCount
            )
            p.viewerFollowing = rolled.following
            p.followerCount = rolled.followerCount
            profile = p
            return false
        } catch {
            lastErrorCode = "network"
            let rolled = CommunityFollowLogic.rollback(
                following: optimistic.following,
                followerCount: optimistic.followerCount,
                previousFollowing: previousFollowing,
                previousCount: previousCount
            )
            p.viewerFollowing = rolled.following
            p.followerCount = rolled.followerCount
            profile = p
            return false
        }
    }
}

/// Community Tab feed placeholder ViewModel (Phase 1 empty / skeleton).
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class CommunityFeedViewModel {
    public private(set) var items: [NewsPostCard] = []
    public private(set) var isLoading = false
    public private(set) var lastErrorCode: String?
    public var feedEnabled: Bool
    public var ugcEnabled: Bool

    private let client: any CommunityAPIClient

    public init(
        client: any CommunityAPIClient,
        feedEnabled: Bool = CommunityConfigDefaults.feedEnabledDefault,
        ugcEnabled: Bool = CommunityConfigDefaults.ugcEnabledDefault
    ) {
        self.client = client
        self.feedEnabled = feedEnabled
        self.ugcEnabled = ugcEnabled
    }

    public var placeholder: CommunityTabPlaceholder {
        CommunityFollowLogic.tabPlaceholder(
            isLoading: isLoading,
            hasItems: !items.isEmpty,
            feedEnabled: feedEnabled
        )
    }

    public var showsCompose: Bool {
        CommunityFollowLogic.showsComposeButton(ugcEnabled: ugcEnabled)
    }

    public func load() async {
        isLoading = true
        lastErrorCode = nil
        defer { isLoading = false }
        do {
            let page = try await client.newsFeed(page: 1, pageSize: CommunityConfigDefaults.newsPageSize)
            items = page.items
        } catch let e as FakeAPIError {
            lastErrorCode = e.code
            items = []
        } catch {
            lastErrorCode = "network"
            items = []
        }
    }
}

/// Product library index placeholder (DES-v1.3-12-04 / D42 Phase 3).
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class LibraryIndexViewModel {
    public private(set) var items: [ProductSKU] = []
    public private(set) var isLoading = false
    public private(set) var lastErrorCode: String?
    public var libraryCurveEnabled: Bool

    private let client: any LibraryAPIClient

    public init(
        client: any LibraryAPIClient,
        libraryCurveEnabled: Bool = LibraryConfigDefaults.curveEnabledDefault
    ) {
        self.client = client
        self.libraryCurveEnabled = libraryCurveEnabled
    }

    public var placeholder: LibraryPlaceholderKind {
        if items.isEmpty { return .libraryBuilding }
        return .empty
    }

    public var placeholderTitle: String { LibraryLogic.placeholderTitle(placeholder) }
    public var placeholderHint: String { LibraryLogic.placeholderHint(placeholder) }

    public func load() async {
        isLoading = true
        lastErrorCode = nil
        defer { isLoading = false }
        do {
            let page = try await client.listSKUs(cursor: nil, pageSize: LibraryConfigDefaults.skuListPageSize)
            items = page.items
        } catch let e as FakeAPIError {
            lastErrorCode = e.code
            items = []
        } catch {
            lastErrorCode = "network"
            items = []
        }
    }
}

/// SKU detail curve gate — hide when `library.curve` off (design §13).
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class SkuCurveViewModel {
    public private(set) var sku: ProductSKU?
    public private(set) var curve: SkuCurveResponse?
    public private(set) var lastErrorCode: String?
    public private(set) var loaded = false
    public var libraryCurveEnabled: Bool

    private let skuId: Int64
    private let client: any LibraryAPIClient

    public init(
        skuId: Int64,
        client: any LibraryAPIClient,
        libraryCurveEnabled: Bool = LibraryConfigDefaults.curveEnabledDefault
    ) {
        self.skuId = skuId
        self.client = client
        self.libraryCurveEnabled = libraryCurveEnabled
    }

    public var showsCurve: Bool {
        guard let sku, let curve else { return false }
        return LibraryLogic.showsCurve(
            libraryCurveEnabled: libraryCurveEnabled,
            skuCurveEnabled: sku.isCurveEnabled,
            sampleN: curve.resolvedSampleN
        )
    }

    public var curvePlaceholder: LibraryPlaceholderKind? {
        LibraryLogic.curvePlaceholder(
            libraryCurveEnabled: libraryCurveEnabled,
            skuCurveEnabled: sku?.isCurveEnabled ?? false,
            sampleN: curve?.resolvedSampleN ?? 0
        )
    }

    public func load() async {
        lastErrorCode = nil
        do {
            sku = try await client.skuDetail(skuId: skuId)
            if libraryCurveEnabled {
                do {
                    curve = try await client.skuCurve(skuId: skuId)
                } catch let e as FakeAPIError {
                    curve = nil
                    lastErrorCode = e.code
                }
            } else {
                curve = nil
            }
            loaded = true
        } catch let e as FakeAPIError {
            lastErrorCode = e.code
            loaded = false
        } catch {
            lastErrorCode = "network"
            loaded = false
        }
    }
}

/// Cabinet / 图鉴 Phase 3 shell ViewModel.
@available(iOS 17.0, macOS 14.0, *)
@MainActor
public final class CabinetPlaceholderViewModel {
    public private(set) var wall: CabinetWallResponse?
    public private(set) var summary: CabinetSummaryResponse?
    public private(set) var badges: [SeriesBadge] = []
    public private(set) var lastErrorCode: String?
    public private(set) var isLoading = false
    public let entryKind: LibraryPlaceholderKind

    private let userId: Int64?
    private let client: any LibraryAPIClient
    private let isSelf: Bool

    public init(
        client: any LibraryAPIClient,
        userId: Int64? = nil,
        isSelf: Bool = true,
        entryKind: LibraryPlaceholderKind = .cabinetComingSoon
    ) {
        self.client = client
        self.userId = userId
        self.isSelf = isSelf
        self.entryKind = entryKind
    }

    public var placeholder: LibraryPlaceholderKind {
        if lastErrorCode == LibraryErrorCode.cabinetPrivate.rawValue {
            return .cabinetPrivate
        }
        let items = wall?.items ?? []
        if items.isEmpty { return entryKind }
        return .empty
    }

    public var placeholderTitle: String { LibraryLogic.placeholderTitle(placeholder) }
    public var placeholderHint: String { LibraryLogic.placeholderHint(placeholder) }

    public var showsDisclaimer: Bool { summary?.showsDisclaimer == true }

    public func load() async {
        isLoading = true
        lastErrorCode = nil
        defer { isLoading = false }
        do {
            if let userId {
                wall = try await client.userCabinet(
                    userId: userId,
                    cursor: nil,
                    pageSize: LibraryConfigDefaults.cabinetPageSize
                )
            }
            if isSelf {
                summary = try await client.meCabinetSummary()
                badges = try await client.meBadges()
            }
        } catch let e as FakeAPIError {
            lastErrorCode = e.code
            if e.code == LibraryErrorCode.cabinetPrivate.rawValue {
                wall = nil
            }
        } catch {
            lastErrorCode = "network"
        }
    }
}
