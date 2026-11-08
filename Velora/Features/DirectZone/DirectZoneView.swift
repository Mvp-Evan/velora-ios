import SwiftUI

/// 直购专区：分区 / 筛选 / 瀑布流（DES-v1.3-04-01 §5.1–5.2 / §9）。
/// Embedded under Purchase Tab trade-mode switch; parent owns NavigationStack.
struct DirectZoneView: View {
    var onBackToAll: (() -> Void)?
    var onOpenListing: (Int64) -> Void
    var onBuyListing: (Int64, Int64) -> Void

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model = DirectZoneModel()

    var body: some View {
        Group {
            if model.zoneDisabled || !model.bootstrapFlagEnabled(session: session) {
                disabledState
            } else {
                zoneBody
            }
        }
        .task {
            if !model.bootstrapFlagEnabled(session: session) {
                model.zoneDisabled = true
                return
            }
            await model.loadConfig()
            if !model.zoneDisabled {
                await model.load(reset: true)
            }
        }
    }

    private var disabledState: some View {
        VEmptyState(
            icon: "tag",
            title: "直购专区暂未开放",
            message: "仍可通过搜索筛选「直购」购买在售商品",
            actionTitle: "回到全部",
            action: { onBackToAll?() }
        )
        .padding(.top, VSpace.xl)
    }

    private var zoneBody: some View {
        VStack(spacing: VSpace.s) {
            searchBar
            sectionTabs
            filterRow
            if model.showsSortPicker {
                sortRow
            }
            listArea
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.vTextTertiary)
            TextField(DirectZoneCopy.searchPlaceholder, text: $model.searchText)
                .font(.vCaption)
                .submitLabel(.search)
                .onSubmit { model.submitSearch() }
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                    model.submitSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.vSurface, in: Capsule())
        .padding(.horizontal, VSpace.l)
    }

    private var sectionTabs: some View {
        VSegmentedTabs(
            items: model.enabledSections.map { ($0.key, $0.title) },
            selection: Binding(
                get: { model.section },
                set: { model.selectSection($0) }
            )
        )
        .padding(.vertical, 4)
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.enabledQuickFilters) { filter in
                    let on = model.isFilterOn(filter.key)
                    Button {
                        model.toggleFilter(filter.key)
                    } label: {
                        Text(filter.title)
                            .font(.vCaption)
                            .foregroundStyle(on ? Color.white : Color.vTextSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(on ? Color.vPrimary : Color.vFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if let total = model.total {
                    Text("\(total) 件")
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                        .padding(.leading, 4)
                }
            }
            .padding(.horizontal, VSpace.l)
        }
    }

    private var sortRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.availableSorts, id: \.self) { s in
                    let on = model.sort == s
                    Button { model.selectSort(s) } label: {
                        Text(s.title)
                            .font(.vMicro)
                            .foregroundStyle(on ? Color.vPrimary : Color.vTextTertiary)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .overlay(
                                Capsule().stroke(on ? Color.vPrimary : Color.vSeparator, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, VSpace.l)
        }
    }

    @ViewBuilder private var listArea: some View {
        switch model.state {
        case .idle, .loading:
            WaterfallGrid(items: (0..<6).map { SkeletonItem(id: $0) }, height: { _ in 300 }) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    VSkeleton(radius: VRadius.l).frame(height: 200)
                    VSkeletonLines(lines: 2)
                }
            }
            .padding(.horizontal, VSpace.m)
        case .failed(let msg):
            VErrorView(message: msg) { Task { await model.load(reset: true) } }
        case .loaded:
            if model.items.isEmpty {
                emptyState
            } else {
                VStack(spacing: VSpace.m) {
                    WaterfallGrid(
                        items: model.items,
                        height: { card in
                            DirectZoneCardView.estimatedHeight(
                                for: card,
                                imageHeight: DirectZoneCardView.imageHeight(for: card),
                                showBuy: model.section != .sold
                            )
                        }
                    ) { card in
                        DirectZoneCardView(
                            card: card,
                            imageHeight: DirectZoneCardView.imageHeight(for: card),
                            showBuyButton: model.section != .sold,
                            onBuy: { beginBuy(card) },
                            onOpen: { onOpenListing(card.listingId) }
                        )
                        .onAppear {
                            if model.shouldLoadMore(card) {
                                Task { await model.loadMore() }
                            }
                        }
                    }
                    .padding(.horizontal, VSpace.m)

                    if model.loadingMore {
                        ProgressView().padding()
                    } else if !model.hasMore {
                        Text("— 已经到底啦 —")
                            .font(.vMicro).foregroundStyle(Color.vTextTertiary)
                            .frame(maxWidth: .infinity).padding()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        Group {
            if model.hasActiveFilters {
                VEmptyState(
                    icon: "line.3.horizontal.decrease.circle",
                    title: DirectZoneCopy.emptyFilters,
                    message: nil,
                    actionTitle: DirectZoneCopy.clearFilters,
                    action: { model.clearFilters() }
                )
            } else {
                VEmptyState(
                    icon: "tag",
                    title: DirectZoneCopy.emptyZone,
                    message: DirectZoneCopy.emptyZoneHint,
                    actionTitle: "去拍卖",
                    action: { onBackToAll?() }
                )
            }
        }
        .padding(.top, VSpace.xl)
    }

    private func beginBuy(_ card: DirectZoneListingCard) {
        guard session.isLoggedIn else {
            router.showLogin = true
            return
        }
        onBuyListing(card.listingId, card.price)
    }
}
