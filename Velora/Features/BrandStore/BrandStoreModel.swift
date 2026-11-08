import Foundation
import Combine

/// Brand store page + follow (DES-v1.3-05-03 BRD-02 / D21; optimistic COM-01 DES-v1.3-12-03 / D41).
@MainActor
final class BrandStoreModel: ObservableObject {
    let brandId: Int64

    @Published var store: BrandStorePage?
    @Published var calendar: [BrandUpcomingRelease] = []
    @Published var state: LoadState = .idle
    @Published var followingBusy = false
    @Published var showUnfollowConfirm = false
    @Published var needsLogin = false

    init(brandId: Int64) {
        self.brandId = brandId
    }

    var isFollowing: Bool { store?.viewerFollowing == true }
    var isFrozen: Bool { store?.isFrozen == true }

    func load() async {
        guard brandId > 0 else {
            state = .failed("无效店铺")
            return
        }
        if store == nil { state = .loading }
        do {
            let page = try await API.brandStore(brandId)
            store = page
            calendar = page.upcomingReleases
            state = .loaded
            await refreshCalendarIfNeeded()
            await refreshVIPIfNeeded()
        } catch {
            if store == nil {
                state = .failed((error as? APIError)?.message ?? "加载失败")
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }

    private func refreshCalendarIfNeeded() async {
        guard calendar.isEmpty else { return }
        do {
            let resp = try await API.brandStoreReleases(brandId)
            calendar = resp.items
            if var s = store {
                s.upcomingReleases = resp.items
                store = s
            }
        } catch {
            // Aggregate payload is enough for first paint.
        }
    }

    /// Prefer dedicated me/vip when logged in (design §6 / §12); keep aggregate `viewer_vip` on failure.
    private func refreshVIPIfNeeded() async {
        guard SessionStore.shared.isLoggedIn else { return }
        do {
            let vip = try await API.brandStoreVIP(brandId)
            guard var s = store else { return }
            s.viewerVip = vip
            store = s
        } catch {
            // Aggregate `viewer_vip` (or absence) is enough; guests / 401 stay strip-free.
        }
    }

    func toggleFollow() async {
        if isFollowing {
            showUnfollowConfirm = true
            return
        }
        await follow()
    }

    func follow() async {
        if let gate = BrandFollowLogic.canFollow(isLoggedIn: SessionStore.shared.isLoggedIn) {
            needsLogin = true
            ToastCenter.shared.show(gate.fallbackMessage, .info)
            return
        }
        guard var s = store else { return }
        let previousFollowing = s.viewerFollowing == true
        let previousCount = s.followerCount ?? 0
        // Optimistic UI; 403/409 rollback (DES-v1.3-12-03 client duties).
        let optimistic = CommunityFollowLogic.applyOptimistic(
            following: previousFollowing,
            followerCount: previousCount,
            targetFollowing: true
        )
        s.viewerFollowing = optimistic.following
        s.followerCount = optimistic.followerCount
        store = s
        followingBusy = true
        defer { followingBusy = false }
        do {
            let resp = try await API.followBrandStore(brandId)
            store = BrandFollowLogic.applyFollowSuccess(store: s, response: resp)
            Haptics.light()
        } catch {
            rollback(previousFollowing: previousFollowing, previousCount: previousCount)
            handleFollowError(error)
        }
    }

    func confirmUnfollow() async {
        showUnfollowConfirm = false
        guard var s = store else { return }
        let previousFollowing = s.viewerFollowing == true
        let previousCount = s.followerCount ?? 0
        let optimistic = CommunityFollowLogic.applyOptimistic(
            following: previousFollowing,
            followerCount: previousCount,
            targetFollowing: false
        )
        s.viewerFollowing = optimistic.following
        s.followerCount = optimistic.followerCount
        store = s
        followingBusy = true
        defer { followingBusy = false }
        do {
            try await API.unfollowBrandStore(brandId)
            store = BrandFollowLogic.applyUnfollowSuccess(store: s)
            // Re-apply from pre-optimistic baseline so count stays consistent with BrandFollowLogic.
            if var next = store {
                next.viewerFollowing = false
                next.followerCount = previousFollowing ? max(0, previousCount - 1) : previousCount
                store = next
            }
            Haptics.light()
        } catch {
            rollback(previousFollowing: previousFollowing, previousCount: previousCount)
            handleFollowError(error)
        }
    }

    private func rollback(previousFollowing: Bool, previousCount: Int) {
        guard var s = store else { return }
        let rolled = CommunityFollowLogic.rollback(
            following: s.viewerFollowing == true,
            followerCount: s.followerCount ?? 0,
            previousFollowing: previousFollowing,
            previousCount: previousCount
        )
        s.viewerFollowing = rolled.following
        s.followerCount = rolled.followerCount
        store = s
    }

    private func handleFollowError(_ error: Error) {
        guard let e = error as? APIError else {
            ToastCenter.shared.error(error)
            return
        }
        if let community = CommunityErrorCode.normalize(e.code) {
            if community.opensLogin { needsLogin = true }
            ToastCenter.shared.show(
                e.message.isEmpty ? community.fallbackMessage : e.message,
                community.opensLogin ? .info : .error
            )
            return
        }
        if let code = BrandStoreErrorCode(rawValue: e.code) {
            if code.opensLogin {
                needsLogin = true
            }
            ToastCenter.shared.show(e.message.isEmpty ? code.fallbackMessage : e.message, code.opensLogin ? .info : .error)
            return
        }
        if e.isUnauthorized {
            needsLogin = true
            ToastCenter.shared.show(BrandStoreErrorCode.followLoginRequired.fallbackMessage, .info)
            return
        }
        _ = CommunityFollowLogic.shouldRollbackFollow(httpStatus: e.status, code: e.code)
        ToastCenter.shared.error(error)
    }
}
