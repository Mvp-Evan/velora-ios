import SwiftUI

/// 「发售」频道：现货 / 抽签 / 预售列表（替换首页 comingSoon 占位）。
struct HomeReleaseChannelView: View {
    var onOpen: (HomeFeedCard) -> Void
    var onBackToAll: (() -> Void)? = nil

    enum Segment: String, CaseIterable, Hashable {
        case all, spot, lottery, presale
        var title: String {
            switch self {
            case .all: return "全部"
            case .spot: return "现货"
            case .lottery: return "抽签"
            case .presale: return "预售"
            }
        }
        var releaseMode: String? {
            switch self {
            case .all: return nil
            case .spot: return "spot"
            case .lottery: return "lottery"
            case .presale: return "presale"
            }
        }
    }

    @State private var segment: Segment = .all
    @State private var items: [HomeFeedCard] = []
    @State private var state: LoadState = .idle
    @State private var cursor: String?
    @State private var hasMore = true
    @State private var loadingMore = false

    var body: some View {
        VStack(spacing: VSpace.m) {
            VSegmentedTabs(
                items: Segment.allCases.map { ($0, $0.title) },
                selection: $segment
            )
            .padding(.vertical, VSpace.s)

            switch state {
            case .idle, .loading:
                ProgressView().padding(.top, VSpace.xl)
            case .failed(let msg):
                VErrorView(message: msg) { Task { await reload() } }
            case .loaded:
                if items.isEmpty {
                    VEmptyState(
                        icon: "sparkles",
                        title: "暂无发售",
                        message: "代拍与品牌的现货、抽签、预售会出现在这里",
                        actionTitle: onBackToAll == nil ? nil : "回到全部",
                        action: onBackToAll
                    )
                    .padding(.top, VSpace.xl)
                } else {
                    LazyVStack(spacing: VSpace.m) {
                        ForEach(items) { card in
                            Button { onOpen(card) } label: {
                                HomeReleaseListRow(card: card)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, VSpace.l)
                            .onAppear {
                                if card.id == items.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                        if loadingMore {
                            ProgressView().padding()
                        } else if !hasMore {
                            Text("— 已经到底啦 —")
                                .font(.vMicro).foregroundStyle(Color.vTextTertiary)
                                .frame(maxWidth: .infinity).padding()
                        }
                    }
                }
            }
        }
        .task(id: segment) { await reload() }
    }

    private func reload() async {
        cursor = nil
        hasMore = true
        if items.isEmpty { state = .loading }
        do {
            let resp = try await API.homeFeed(
                tab: HomeFeedTab.hot.rawValue,
                cursor: nil,
                pageSize: 20,
                tradeType: "release",
                releaseMode: segment.releaseMode
            )
            items = resp.items
            cursor = resp.nextCursor
            hasMore = resp.nextCursor != nil
            state = .loaded
        } catch {
            if items.isEmpty {
                state = .failed((error as? APIError)?.message ?? "加载失败")
            }
        }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore, let cursor else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let resp = try await API.homeFeed(
                tab: HomeFeedTab.hot.rawValue,
                cursor: cursor,
                pageSize: 20,
                tradeType: "release",
                releaseMode: segment.releaseMode
            )
            let known = Set(items.map(\.listingId))
            items.append(contentsOf: resp.items.filter { !known.contains($0.listingId) })
            self.cursor = resp.nextCursor
            hasMore = resp.nextCursor != nil
        } catch {
            // keep cursor
        }
    }
}

private struct HomeReleaseListRow: View {
    let card: HomeFeedCard

    private var modeLabel: String {
        switch card.releaseMode {
        case "spot": return "现货"
        case "lottery": return "抽签"
        case "presale": return "预售"
        default: return "发售"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(card.cover)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    VTagChip(text: modeLabel, tint: .vGold, background: Color.vGold.opacity(0.15))
                    if let badge = card.sellerBadge {
                        SellerBadgeChip(badge: badge)
                    }
                }
                Text(card.title)
                    .font(.vBodyMedium)
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                VPriceText(amount: card.displayPrice, size: 16)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.vTextTertiary)
        }
        .padding(12)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }
}
