import SwiftUI

/// Public user profile card — avatar / nickname / identity / follow / on-sale (DES-v1.3-12-03 COM-01).
/// Never renders phone or address.
struct UserProfileView: View {
    let userId: Int64
    @StateObject private var model: UserProfileModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SessionStore

    init(userId: Int64) {
        self.userId = userId
        _model = StateObject(wrappedValue: UserProfileModel(userId: userId))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                profileSkeleton
            case .failed(let message):
                VErrorView(message: message) { Task { await model.load() } }
            case .loaded:
                if let profile = model.profile {
                    profileScroll(profile)
                } else {
                    VEmptyState(icon: "person", title: CommunityCopy.userNotFound)
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(model.profile?.nickname ?? "主页")
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.profile == nil { await model.load() } }
        .refreshable { await model.load() }
        .confirmationDialog(
            CommunityCopy.unfollowConfirm,
            isPresented: $model.showUnfollowConfirm,
            titleVisibility: .visible
        ) {
            Button(CommunityCopy.unfollow, role: .destructive) {
                Task { await model.confirmUnfollow() }
            }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: model.needsLogin) { _, need in
            if need {
                router.showLogin = true
                model.needsLogin = false
            }
        }
    }

    private func profileScroll(_ profile: PublicUserProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                headerCard(profile)
                if !model.isSelf {
                    followButton(profile)
                }
                onSaleSection(profile)
                // DES-v1.3-12-04 / D42 — public 模型柜 entry (Phase 3 coming-soon / privacy shell)
                NavigationLink {
                    CabinetWallView(userId: userId, isSelf: model.isSelf, entryKind: .cabinetComingSoon)
                } label: {
                    HStack {
                        Text(LibraryCopy.cabinetTitle)
                            .font(.vBodyMedium)
                            .foregroundStyle(Color.vText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.vTextTertiary)
                    }
                    .padding(14)
                    .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                }
                .buttonStyle(.plain)
                NavigationLink {
                    UserReviewsListView(userId: userId)
                } label: {
                    HStack {
                        Text(ReviewCreditCopy.userReviewsTitle)
                            .font(.vBodyMedium)
                            .foregroundStyle(Color.vText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.vTextTertiary)
                    }
                    .padding(14)
                    .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(VSpace.l)
            .padding(.bottom, VSpace.xl)
        }
    }

    private func headerCard(_ profile: PublicUserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                VAvatar(url: profile.avatar, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.nickname)
                        .font(.vTitle(20))
                        .foregroundStyle(Color.vText)
                    HStack(spacing: 6) {
                        Text(profile.resolvedIdentity.displayLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.vBlue, in: Capsule())
                        VTagChip(text: "信用 \(profile.creditScore)", tint: Color.vTextSecondary, background: Color.vFill)
                        if let loc = profile.location, !loc.isEmpty {
                            VTagChip(text: loc, tint: Color.vTextSecondary, background: Color.vFill)
                        }
                    }
                    // COM-01: never show phone / address on public card.
                    Text(CommunityCopy.followerCountLabel(profile.followerCount))
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
                Spacer(minLength: 0)
            }
            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(.vBody)
                    .foregroundStyle(Color.vTextSecondary)
            }
            HStack(spacing: 0) {
                stat("\(profile.lotCount)", "在拍")
                stat("\(profile.soldCount)", "卖出")
                stat("\(profile.wonCount)", "拍到")
                stat("\(profile.displayOnSaleCount)", CommunityCopy.onSaleSection)
            }
            .padding(.vertical, 10)
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
        }
        .padding(16)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func stat(_ v: String, _ k: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.vMono(16, weight: .heavy)).foregroundStyle(Color.vText)
            Text(k).font(.vMicro).foregroundStyle(Color.vTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func followButton(_ profile: PublicUserProfile) -> some View {
        Button {
            Task { await model.toggleFollow() }
        } label: {
            HStack(spacing: 6) {
                if model.followingBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: profile.isFollowing ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(profile.followTitle)
                    .font(.vBodyMedium)
            }
            .foregroundStyle(profile.isFollowing ? Color.vPrimary : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                profile.isFollowing
                    ? AnyShapeStyle(Color.vPrimary.opacity(0.12))
                    : AnyShapeStyle(VGradient.brand),
                in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
            )
            .overlay {
                if profile.isFollowing {
                    RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                        .stroke(Color.vPrimary.opacity(0.35), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.followingBusy)
    }

    @ViewBuilder
    private func onSaleSection(_ profile: PublicUserProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(CommunityCopy.onSaleSection).font(.vHeadline)
                Spacer()
                NavigationLink {
                    SellerOnSaleListView(userId: userId, nickname: profile.nickname)
                } label: {
                    HStack(spacing: 2) {
                        Text(CommunityCopy.onSaleSeeAll)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                }
            }

            if !profile.onSaleItems.isEmpty {
                LazyVStack(spacing: 10) {
                    ForEach(profile.onSaleItems.prefix(5)) { item in
                        NavigationLink {
                            ListingDetailView(listingId: item.listingId)
                        } label: {
                            onSaleRow(title: item.displayTitle, cover: item.cover, price: item.price)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !model.onSaleLots.isEmpty {
                LazyVStack(spacing: 10) {
                    ForEach(model.onSaleLots.prefix(5)) { lot in
                        NavigationLink {
                            LotDetailView(lotId: lot.id, preload: lot)
                        } label: {
                            onSaleRow(title: lot.title, cover: lot.cover, price: lot.currentPrice)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text(CommunityCopy.onSaleEmpty)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(14)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func onSaleRow(title: String, cover: String?, price: Int64?) -> some View {
        HStack(spacing: 10) {
            Group {
                if let cover, !cover.isEmpty {
                    RemoteImage(cover)
                } else {
                    Color.vFill
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: VRadius.s, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.vBodyMedium)
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                if let price {
                    Text(price.display)
                        .font(.vMono(14, weight: .semibold))
                        .foregroundStyle(Color.vPrimary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var profileSkeleton: some View {
        VStack(alignment: .leading, spacing: VSpace.l) {
            VSkeleton(radius: VRadius.l).frame(height: 140)
            VSkeleton(radius: VRadius.m).frame(height: 44)
            VSkeletonLines(lines: 3)
            Spacer()
        }
        .padding(VSpace.l)
    }
}

/// Seller on-sale entry point from public profile (COM-01).
struct SellerOnSaleListView: View {
    let userId: Int64
    var nickname: String = ""
    @State private var lots: [Lot] = []
    @State private var state: LoadState = .idle

    var body: some View {
        ScrollView {
            switch state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let m):
                VErrorView(message: m) { Task { await load() } }
            case .loaded:
                if lots.isEmpty {
                    VEmptyState(icon: "tag", title: CommunityCopy.onSaleEmpty)
                } else {
                    LazyVStack(spacing: VSpace.m) {
                        ForEach(lots) { lot in
                            NavigationLink {
                                LotDetailView(lotId: lot.id, preload: lot)
                            } label: {
                                LotRow(lot: lot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(VSpace.l)
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(nickname.isEmpty ? CommunityCopy.onSaleSection : "\(nickname)的在售")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if lots.isEmpty { state = .loading }
        do {
            let page = try await API.lots(API.LotQuery(status: "live", sellerId: userId, page: 1, pageSize: 50))
            lots = page.items
            state = .loaded
        } catch {
            state = .failed((error as? APIError)?.message ?? "加载失败")
        }
    }
}
