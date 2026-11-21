import Foundation
import Combine

/// Public user homepage + follow (DES-v1.3-12-03 COM-01 / D41).
@MainActor
final class UserProfileModel: ObservableObject {
    let userId: Int64

    @Published var profile: PublicUserProfile?
    @Published var state: LoadState = .idle
    @Published var followingBusy = false
    @Published var showUnfollowConfirm = false
    @Published var needsLogin = false
    @Published var onSaleLots: [Lot] = []

    init(userId: Int64) {
        self.userId = userId
    }

    var isFollowing: Bool { profile?.viewerFollowing == true }
    var isSelf: Bool { SessionStore.shared.user?.id == userId }

    func load() async {
        guard userId > 0 else {
            state = .failed(CommunityCopy.userNotFound)
            return
        }
        if profile == nil { state = .loading }
        do {
            let page = try await API.userProfile(userId)
            profile = page
            state = .loaded
            await loadOnSaleIfNeeded()
        } catch {
            if profile == nil {
                state = .failed((error as? APIError)?.message ?? "加载失败")
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }

    private func loadOnSaleIfNeeded() async {
        guard var p = profile else { return }
        if !p.onSaleItems.isEmpty { return }
        var items: [ProfileOnSaleItem] = []
        if let page = try? await API.listings(
            ListingSearchQuery(tradeType: "fixed", status: "on_sale", sellerId: userId, page: 1, pageSize: 20)
        ) {
            items = page.items.map {
                ProfileOnSaleItem(
                    listingId: $0.listingId,
                    title: $0.title,
                    cover: $0.cover,
                    price: $0.price ?? $0.currentPrice,
                    tradeType: "fixed",
                    status: "on_sale"
                )
            }
        }
        if items.isEmpty {
            if let page = try? await API.lots(API.LotQuery(status: "live", sellerId: userId, page: 1, pageSize: 20)) {
                onSaleLots = page.items
                if p.onSaleCount == nil { p.onSaleCount = page.total }
                profile = p
            }
            return
        }
        p.onSaleItems = items
        if p.onSaleCount == nil { p.onSaleCount = items.count }
        profile = p
    }

    func toggleFollow() async {
        if isSelf {
            ToastCenter.shared.show(CommunityCopy.cannotFollowSelf, .info)
            return
        }
        if isFollowing {
            showUnfollowConfirm = true
            return
        }
        await follow()
    }

    func follow() async {
        if let gate = CommunityFollowLogic.canFollow(
            isLoggedIn: SessionStore.shared.isLoggedIn,
            viewerId: SessionStore.shared.user?.id,
            followeeId: userId,
            followeeType: .user
        ) {
            if gate.opensLogin {
                needsLogin = true
                ToastCenter.shared.show(gate.fallbackMessage, .info)
            } else {
                ToastCenter.shared.show(gate.fallbackMessage, .error)
            }
            return
        }
        guard var p = profile else { return }
        let previousFollowing = p.viewerFollowing == true
        let previousCount = p.followerCount
        let optimistic = CommunityFollowLogic.applyOptimistic(
            following: previousFollowing,
            followerCount: previousCount,
            targetFollowing: true
        )
        p.viewerFollowing = optimistic.following
        p.followerCount = optimistic.followerCount
        profile = p
        followingBusy = true
        defer { followingBusy = false }
        do {
            let resp = try await API.followUser(userId)
            let merged = CommunityFollowLogic.applyFollowSuccess(
                following: previousFollowing,
                followerCount: previousCount,
                response: resp
            )
            p.viewerFollowing = merged.following
            p.followerCount = merged.followerCount
            profile = p
            Haptics.light()
        } catch {
            rollback(previousFollowing: previousFollowing, previousCount: previousCount)
            handleFollowError(error)
        }
    }

    func confirmUnfollow() async {
        showUnfollowConfirm = false
        guard var p = profile else { return }
        let previousFollowing = p.viewerFollowing == true
        let previousCount = p.followerCount
        let optimistic = CommunityFollowLogic.applyOptimistic(
            following: previousFollowing,
            followerCount: previousCount,
            targetFollowing: false
        )
        p.viewerFollowing = optimistic.following
        p.followerCount = optimistic.followerCount
        profile = p
        followingBusy = true
        defer { followingBusy = false }
        do {
            try await API.unfollowUser(userId)
            let merged = CommunityFollowLogic.applyUnfollowSuccess(
                following: previousFollowing,
                followerCount: previousCount
            )
            p.viewerFollowing = merged.following
            p.followerCount = merged.followerCount
            profile = p
            Haptics.light()
        } catch {
            rollback(previousFollowing: previousFollowing, previousCount: previousCount)
            handleFollowError(error)
        }
    }

    private func rollback(previousFollowing: Bool, previousCount: Int) {
        guard var p = profile else { return }
        let rolled = CommunityFollowLogic.rollback(
            following: p.viewerFollowing == true,
            followerCount: p.followerCount,
            previousFollowing: previousFollowing,
            previousCount: previousCount
        )
        p.viewerFollowing = rolled.following
        p.followerCount = rolled.followerCount
        profile = p
    }

    private func handleFollowError(_ error: Error) {
        guard let e = error as? APIError else {
            ToastCenter.shared.error(error)
            return
        }
        if let code = CommunityErrorCode.normalize(e.code) {
            if code.opensLogin { needsLogin = true }
            ToastCenter.shared.show(
                e.message.isEmpty ? code.fallbackMessage : e.message,
                code.opensLogin ? .info : .error
            )
            return
        }
        if e.isUnauthorized {
            needsLogin = true
            ToastCenter.shared.show(CommunityCopy.followLoginRequired, .info)
            return
        }
        // 403 / 409 already rolled back above.
        _ = CommunityFollowLogic.shouldRollbackFollow(httpStatus: e.status, code: e.code)
        ToastCenter.shared.error(error)
    }
}
