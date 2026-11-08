import SwiftUI

/// Community Tab — Phase 1 empty / skeleton; Phase 3 compose gated by `community.ugc` (DES-v1.3-12-03 / D41).
struct CommunityView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var items: [NewsPostCard] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private var feedEnabled: Bool {
        session.bootstrap?.flag(CommunityConfigDefaults.feedFlagKey)
            ?? CommunityConfigDefaults.feedEnabledDefault
    }

    private var ugcEnabled: Bool {
        session.bootstrap?.flag(CommunityConfigDefaults.ugcFlagKey)
            ?? CommunityConfigDefaults.ugcEnabledDefault
    }

    private var showsCompose: Bool {
        CommunityFollowLogic.showsComposeButton(ugcEnabled: ugcEnabled)
    }

    private var placeholder: CommunityTabPlaceholder {
        CommunityFollowLogic.tabPlaceholder(
            isLoading: isLoading,
            hasItems: !items.isEmpty,
            feedEnabled: feedEnabled
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                switch placeholder {
                case .skeleton:
                    feedSkeleton
                case .feed:
                    feedList
                case .emptyPreview:
                    emptyPreview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.vBackground)
            .navigationTitle(CommunityCopy.tabTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Phase 3 only — never show composer while `community.ugc` is off (design §5.8 / §9).
                if showsCompose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            ToastCenter.shared.show(CommunityCopy.composeHidden, .info)
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("发帖")
                    }
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    private var emptyPreview: some View {
        VStack(spacing: VSpace.l) {
            Spacer()
            Image(systemName: "newspaper")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.vTextTertiary)
            Text(CommunityCopy.emptyPreview)
                .font(.vTitle(20))
                .foregroundStyle(Color.vText)
            Text(CommunityCopy.emptyHint)
                .font(.vBody)
                .foregroundStyle(Color.vTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VSpace.xl)
            if let loadError {
                Text(loadError)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
            }
            Spacer()
        }
    }

    private var feedSkeleton: some View {
        ScrollView {
            VStack(spacing: VSpace.l) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        VSkeleton(radius: VRadius.m)
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                        VSkeletonLines(lines: 2)
                    }
                    .padding(.horizontal, VSpace.l)
                }
            }
            .padding(.top, VSpace.l)
            .padding(.bottom, 100)
        }
        .accessibilityLabel(CommunityCopy.skeletonHint)
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: VSpace.l) {
                ForEach(items) { item in
                    newsCard(item)
                }
            }
            .padding(VSpace.l)
            .padding(.bottom, 100)
        }
    }

    private func newsCard(_ item: NewsPostCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let cover = item.cover, !cover.isEmpty {
                        RemoteImage(cover)
                    } else {
                        Color.vFill
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipped()

                if item.showsInvalidOverlay {
                    Color.black.opacity(0.45)
                    Text(CommunityCopy.mountInvalid)
                        .font(.vCaptionMedium)
                        .foregroundStyle(.white)
                        .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))

            Text(item.title?.isEmpty == false ? item.title! : "资讯")
                .font(.vBodyMedium)
                .foregroundStyle(Color.vText)
                .lineLimit(2)
        }
        .padding(12)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func refresh() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        // Phase 1: feed endpoint may 404 / empty — keep empty-preview UX.
        guard feedEnabled else {
            items = []
            return
        }
        do {
            let page = try await API.newsFeed()
            items = page.items
        } catch {
            items = []
            loadError = (error as? APIError)?.message
        }
    }
}
