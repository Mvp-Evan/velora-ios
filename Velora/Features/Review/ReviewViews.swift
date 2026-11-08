import SwiftUI

/// Non-dismissible arbitration tag bubble (client duty — design §9 / end notes).
struct ArbitrationTagBubble: View {
    @State private var showHint = false

    var body: some View {
        Button {
            showHint = true
        } label: {
            Text(ReviewCreditCopy.arbitrationTag)
                .font(.vMicro)
                .foregroundStyle(Color.vTextSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.vFill, in: Capsule())
        }
        .buttonStyle(.plain)
        // Tag itself is never removable — only shows explanation.
        .popover(isPresented: $showHint) {
            Text(ReviewCreditCopy.arbitrationHint)
                .font(.vCaption)
                .padding()
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(ReviewCreditCopy.arbitrationTag)
        .accessibilityHint(ReviewCreditCopy.arbitrationHint)
    }
}

struct ReviewCardView: View {
    let review: OrderReview
    var showsAuthor = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let rating = review.resolvedRating {
                    Label(rating.displayLabel, systemImage: rating.systemImage)
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vText)
                } else if review.isPending {
                    Text(ReviewCreditCopy.pendingBanner)
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vGold)
                }
                if review.showsArbitrationTag {
                    ArbitrationTagBubble()
                }
                Spacer()
                if showsAuthor {
                    Text(review.displayAuthor)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
            let body = review.displayContent
            if !body.isEmpty {
                Text(body)
                    .font(.vBody)
                    .foregroundStyle(review.isHidden ? Color.vTextTertiary : Color.vText)
            }
            if !review.imageUrls.isEmpty, !review.isHidden {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(review.imageUrls, id: \.self) { url in
                            RemoteImage(url)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: VRadius.s, style: .continuous))
                        }
                    }
                }
            }
            if review.resolvedSource == .autoGood {
                Text(ReviewCreditCopy.sourceAutoGood)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }
}

/// Pending-review yellow banner with D-day countdown (server_time calibrated).
struct PendingReviewBanner: View {
    let remainDays: Int
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "star.bubble.fill")
                    .foregroundStyle(Color.vGold)
                Text(ReviewCreditLogic.pendingBannerText(remainDays: remainDays))
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.vTextTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.vGold.opacity(0.18), in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

struct OrderReviewsSection: View {
    let response: OrderReviewsResponse?
    var empty: Bool { response?.items.isEmpty != false }

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text("订单评价").font(.vHeadline)
                if empty {
                    Text(ReviewCreditCopy.emptyReviews)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                } else if let response {
                    ForEach(response.items) { review in
                        ReviewCardView(review: review)
                    }
                }
            }
        }
    }
}

struct UserReviewsListView: View {
    let userId: Int64
    @State private var items: [OrderReview] = []
    @State private var cursor: String?
    @State private var state: LoadState = .idle
    @State private var hasMore = true

    var body: some View {
        ScrollView {
            switch state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let m):
                VErrorView(message: m) { Task { await load(reset: true) } }
            case .loaded:
                if items.isEmpty {
                    VEmptyState(icon: "star", title: ReviewCreditCopy.emptyReviews, message: "")
                } else {
                    LazyVStack(spacing: VSpace.m) {
                        ForEach(items) { r in
                            ReviewCardView(review: r)
                                .onAppear {
                                    if r.id == items.last?.id, hasMore {
                                        Task { await loadMore() }
                                    }
                                }
                        }
                    }
                    .padding(VSpace.l)
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(ReviewCreditCopy.userReviewsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        if reset {
            state = items.isEmpty ? .loading : state
            cursor = nil
        }
        do {
            let page = try await API.userReviews(userId: userId, cursor: cursor)
            items = page.items.filter(ReviewCreditLogic.publicVisible)
            cursor = page.nextCursor
            hasMore = page.nextCursor != nil
            state = .loaded
        } catch {
            state = .failed((error as? APIError)?.message ?? "加载失败")
        }
    }

    private func loadMore() async {
        guard let cursor else { return }
        if let page = try? await API.userReviews(userId: userId, cursor: cursor) {
            items.append(contentsOf: page.items.filter(ReviewCreditLogic.publicVisible))
            self.cursor = page.nextCursor
            hasMore = page.nextCursor != nil
        }
    }
}
