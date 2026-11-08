import SwiftUI

/// Purchase Tab home: trade-mode switch, floors (全部) / channel feed / 直购 / 发售 (DES-v1.3-02-01).
struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var feed = HomeFeedModel(tab: .hot)
    @StateObject private var floors = HomeFloorsModel()
    @StateObject private var slots = HomeSlotsModel()
    @StateObject private var filters = FiltersStore.shared
    @ObservedObject private var exposures = HomeExposureReporter.shared

    @State private var tradeMode: HomeTradeMode = .all
    @State private var channel: HomeFeedTab = .hot
    @State private var path = NavigationPath()
    @State private var cachedScaleVersion: Int64?
    @State private var confirmBuy: HomeConfirmBuyRoute?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ListRealtimeBanner(
                    endTimeText: feed.realtime.endTimeChanges.showsBanner
                        ? feed.realtime.endTimeChanges.bannerText : nil,
                    offline: feed.realtime.realtimePaused && !feed.items.isEmpty
                ) {
                    Task { await feed.refreshFromBanner() }
                }
                ScrollView {
                    LazyVStack(spacing: VSpace.l, pinnedViews: []) {
                        header
                        tradeModeSwitch
                        modeBody
                    }
                    .padding(.bottom, VSpace.xl)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: HomeScrollOffsetKey.self, value: geo.frame(in: .named("homeScroll")).minY)
                                .onAppear { feed.realtime.updateViewportHeight(UIScreen.main.bounds.height) }
                        }
                    )
                }
                .coordinateSpace(name: "homeScroll")
                .onPreferenceChange(HomeScrollOffsetKey.self) { feed.realtime.noteScroll(offset: $0) }
                .background(Color.vBackground)
                .scrollIndicators(.hidden)
                .refreshable {
                    feed.realtime.acknowledgeBannerAndRefresh()
                    await reload(preserveChannel: true)
                }
            }
            .navigationDestination(for: HomeDetailRoute.self) { route in
                ListingDetailView(listingId: route.listingId, lotId: route.lotId, preloadTradeType: route.tradeType)
            }
            .navigationDestination(for: HomeSessionRoute.self) { route in
                HomeSessionDetailHost(sessionId: route.sessionId, title: route.title)
            }
            .navigationDestination(for: Route.self) { r in
                switch r {
                case .search(let q): SearchView(initialQuery: q)
                }
            }
            .sheet(item: $confirmBuy) { route in
                NavigationStack {
                    ConfirmBuyView(
                        listingId: route.listingId,
                        source: .directZone,
                        expectedPriceFen: route.price
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            feed.activateRealtime()
            await filters.load(force: true)
            reconcileScaleCache()
            await reload(preserveChannel: false)
            slots.startPolling()
        }
        .onDisappear {
            slots.stopPolling()
            feed.deactivateRealtime()
        }
        .onChange(of: channel) { _, tab in
            feed.setTab(tab)
            Task { await feed.load() }
        }
        .onChange(of: tradeMode) { _, mode in
            applyTradeModeFilter(mode)
            Task {
                if mode == .all {
                    await floors.load()
                } else if mode == .auction {
                    await feed.load()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                slots.noteBackground()
            case .active:
                Task { await slots.refreshIfStaleAfterForeground() }
            default:
                break
            }
        }
        .onChange(of: slots.requestId) { _, id in
            exposures.bind(requestId: id)
        }
        .onChange(of: session.isLoggedIn) { _, loggedIn in
            if channel == .follow {
                if loggedIn {
                    Task { await feed.load() }
                } else {
                    feed.setTab(.follow)
                    Task { await feed.load() }
                }
            }
        }
    }

    enum Route: Hashable { case search(String) }

    private struct HomeDetailRoute: Hashable {
        let listingId: Int64
        let lotId: Int64?
        let tradeType: String?

        init(listingId: Int64, lotId: Int64? = nil, tradeType: String? = nil) {
            self.listingId = listingId
            self.lotId = lotId
            self.tradeType = tradeType
        }

        init(id: Int64) {
            self.listingId = id
            self.lotId = nil
            self.tradeType = nil
        }
    }

    private struct HomeSessionRoute: Hashable {
        let sessionId: Int64
        let title: String?
    }

    private struct HomeConfirmBuyRoute: Identifiable, Hashable {
        let listingId: Int64
        let price: Int64
        var id: Int64 { listingId }
    }

    // MARK: - Mode body

    @ViewBuilder private var modeBody: some View {
        switch tradeMode {
        case .all:
            floorsBody
        case .auction:
            channelTabs
            if channel == .hot {
                slotsSection
            }
            feedSection
        case .fixed:
            DirectZoneView(
                onBackToAll: { tradeMode = .all },
                onOpenListing: { listingId in
                    path.append(HomeDetailRoute(listingId: listingId, tradeType: "fixed"))
                },
                onBuyListing: { listingId, price in
                    confirmBuy = HomeConfirmBuyRoute(listingId: listingId, price: price)
                }
            )
        case .release:
            HomeReleaseChannelView(
                onOpen: openCard,
                onBackToAll: { tradeMode = .all }
            )
        }
    }

    @ViewBuilder private var floorsBody: some View {
        HomeQuickEntryGrid(
            onAuction: { tradeMode = .auction },
            onFixed: { tradeMode = .fixed },
            onRelease: { tradeMode = .release },
            onSessions: {
                router.select(router.visibleTabs.contains(where: { $0.tab == .auctions }) ? .auctions : .buy)
            }
        )

        if channel == .hot || true {
            slotsSection
        }

        if floors.loading && !floors.hasAnyContent {
            ProgressView().padding(.top, VSpace.l)
        }

        HomeAuctionRail(
            title: "正在热拍",
            subtitle: "代拍 / 品牌 · 实时结拍",
            cards: floors.liveAuctions,
            onMore: { tradeMode = .auction },
            onOpen: openCard
        )

        HomeAuctionRail(
            title: "即将开拍",
            subtitle: "开拍倒计时",
            cards: floors.upcomingAuctions,
            showsStartCountdown: true,
            onMore: { tradeMode = .auction },
            onOpen: openCard
        )

        HomeReleaseFloor(
            cards: floors.releases,
            onMore: { tradeMode = .release },
            onOpen: openCard
        )

        // Bottom「猜你喜欢」waterfall (hot/new/follow).
        VStack(alignment: .leading, spacing: VSpace.m) {
            HomeFloorHeader(title: "猜你喜欢", subtitle: nil)
            channelTabs
            feedSection
        }

        if !floors.loading && !floors.hasAnyContent && feed.state == .loaded && feed.items.isEmpty {
            emptyAllFloors
        }
    }

    private var emptyAllFloors: some View {
        VEmptyState(
            icon: "flag.checkered",
            title: "暂无推荐商品",
            message: "代拍与品牌的 1:43 商品会出现在这里",
            actionTitle: "去拍场看看",
            action: {
                router.select(router.visibleTabs.contains(where: { $0.tab == .auctions }) ? .auctions : .buy)
            }
        )
        .padding(.top, VSpace.l)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: VSpace.s) {
            HStack(spacing: 10) {
                Text(AppConfig.brandDisplayName)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(Color.vPrimary)
                Button { path.append(Route.search("")) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.vTextTertiary)
                        Text(filters.filters.hotKeywords.first.map { "搜「\($0)」" } ?? "搜索品牌、车型、比例")
                            .font(.vCaption).foregroundStyle(Color.vTextTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color.vSurface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, VSpace.l)
            .padding(.top, VSpace.s)

            if !filters.filters.hotKeywords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters.filters.hotKeywords.prefix(8), id: \.self) { word in
                            Button {
                                path.append(Route.search(word))
                            } label: {
                                Text(word)
                                    .font(.vCaption)
                                    .foregroundStyle(Color.vTextSecondary)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.vFill, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, VSpace.l)
                }
            }
        }
    }

    private var tradeModeSwitch: some View {
        VPillSegments(
            items: HomeTradeMode.allCases.map { ($0, $0.title) },
            selection: $tradeMode
        )
    }

    private var channelTabs: some View {
        VSegmentedTabs(
            items: HomeFeedTab.allCases.map { ($0, $0.title) },
            selection: $channel
        )
        .padding(.vertical, VSpace.s)
    }

    // MARK: - Slots (hot only)

    @ViewBuilder private var slotsSection: some View {
        if slots.hasContent {
            if !slots.banners.isEmpty {
                HomeBannerCarousel(
                    banners: slots.banners,
                    onTap: handleSlotTap,
                    onExpose: exposeSlot
                )
            }
            if !slots.sessions.isEmpty {
                HomeSessionStrip(
                    sessions: slots.sessions,
                    onTap: handleSlotTap,
                    onExpose: exposeSlot
                )
            }
        }
    }

    // MARK: - Feed

    @ViewBuilder private var feedSection: some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            if feed.showingHotFallback {
                Text("热度计算中")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
                    .padding(.horizontal, VSpace.l)
            }

            switch feed.state {
            case .loading, .idle:
                WaterfallGrid(items: (0..<6).map { SkeletonItem(id: $0) }, height: { _ in 280 }) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        VSkeleton(radius: VRadius.l).frame(height: 200)
                        VSkeletonLines(lines: 2)
                    }
                }
                .padding(.horizontal, VSpace.m)
            case .failed(let msg):
                VErrorView(message: msg) { Task { await feed.load() } }
            case .loaded:
                if feed.needsLogin && channel == .follow {
                    VEmptyState(
                        icon: "person.crop.circle.badge.plus",
                        title: "登录后查看关注动态",
                        message: "关注代拍和品牌，上新会出现在这里",
                        actionTitle: "去登录",
                        action: { router.showLogin = true }
                    )
                } else if displayRows.isEmpty {
                    emptyFeed
                } else {
                    WaterfallGrid(
                        items: displayRows.map(FeedRowBox.init),
                        height: { box in
                            switch box.row {
                            case .natural(let c):
                                return HomeFeedCardView.estimatedHeight(for: c, imageHeight: HomeFeedCardView.imageHeight(for: c))
                            case .promo:
                                return 200 + 10 + 40 + 6 + 18 + 10 + 16
                            }
                        }
                    ) { box in
                        rowView(box.row)
                    }
                    .padding(.horizontal, VSpace.m)
                    if feed.loadingMore { ProgressView().padding() }
                    else if !feed.hasMore {
                        Text("— 已经到底啦 —")
                            .font(.vMicro).foregroundStyle(Color.vTextTertiary)
                            .frame(maxWidth: .infinity).padding()
                    }
                }
            }
        }
    }

    private var emptyFeed: some View {
        Group {
            if channel == .follow {
                VEmptyState(
                    icon: "heart",
                    title: "关注代拍和品牌，上新会出现在这里",
                    message: nil,
                    actionTitle: "去热门",
                    action: { channel = .hot }
                )
            } else {
                VEmptyState(
                    icon: "flag.checkered",
                    title: "暂无商品",
                    message: "下拉刷新试试",
                    actionTitle: "去拍场看看",
                    action: {
                        router.select(router.visibleTabs.contains(where: { $0.tab == .auctions }) ? .auctions : .buy)
                    }
                )
            }
        }
    }

    private var displayRows: [HomeFeedRow] {
        let filtered = HomeFeedComposer.filter(cards: feed.items, tradeMode: tradeMode == .all ? .all : tradeMode)
        if channel == .hot && tradeMode != .all {
            return HomeFeedComposer.merge(natural: filtered, promos: slots.cards)
        }
        if channel == .hot && tradeMode == .all {
            // Floors already show promos; waterfall stays natural only.
            return filtered.map { .natural($0) }
        }
        return filtered.map { .natural($0) }
    }

    @ViewBuilder private func rowView(_ row: HomeFeedRow) -> some View {
        switch row {
        case .natural(let card):
            NavigationLink(value: HomeDetailRoute(listingId: card.listingId, lotId: card.lotId, tradeType: card.tradeType)) {
                HomeFeedCardView(card: card, imageHeight: HomeFeedCardView.imageHeight(for: card))
            }
            .buttonStyle(.plain)
            .reportLotCardVisibility(
                lotId: card.tradeType == "auction" ? card.lotId : nil,
                onRatio: { id, ratio in feed.realtime.updateVisibility(lotId: id, ratio: ratio) },
                onDisappear: { id in feed.realtime.cardDidDisappear(lotId: id) }
            )
            .onAppear {
                if case .natural(let c) = row, feed.shouldLoadMore(c) {
                    Task { await feed.loadMore() }
                }
            }
        case .promo(let slot):
            Button {
                handleSlotTap(slot)
            } label: {
                HomePromoCardView(slot: slot)
            }
            .buttonStyle(.plain)
            .onAppear { exposeSlot(slot) }
            .onDisappear {
                exposures.trackDisappeared(
                    slotId: slot.id,
                    listingId: slot.bindType == .listing ? slot.bindId : nil
                )
            }
        }
    }

    // MARK: - Actions

    private func openCard(_ card: HomeFeedCard) {
        path.append(HomeDetailRoute(listingId: card.listingId, lotId: card.lotId, tradeType: card.tradeType))
    }

    private func handleSlotTap(_ slot: HomeSlotItem) {
        exposures.trackClick(
            slotId: slot.id,
            listingId: slot.bindType == .listing ? slot.bindId : nil
        )
        switch slot.bindType {
        case .listing:
            path.append(HomeDetailRoute(id: slot.bindId))
        case .session:
            path.append(HomeSessionRoute(sessionId: slot.bindId, title: slot.title))
        case .event:
            ToastCenter.shared.show("线下活动暂未开放", .info)
        case .seller:
            ToastCenter.shared.show("卖家主页即将开放", .info)
        }
    }

    private func exposeSlot(_ slot: HomeSlotItem) {
        exposures.trackAppeared(
            slotId: slot.id,
            listingId: slot.bindType == .listing ? slot.bindId : nil
        )
    }

    private func applyTradeModeFilter(_ mode: HomeTradeMode) {
        switch mode {
        case .all:
            feed.setTradeType(nil)
        case .auction:
            feed.setTradeType("auction")
        case .fixed, .release:
            break
        }
    }

    private func reload(preserveChannel: Bool) async {
        if !preserveChannel { channel = .hot; feed.setTab(.hot) }
        applyTradeModeFilter(tradeMode)
        async let a: () = feed.load()
        async let b: () = slots.load(force: true)
        async let c: () = floors.load()
        _ = await (a, b, c)
        exposures.bind(requestId: slots.requestId)
        reconcileScaleCache()
    }

    private func reconcileScaleCache() {
        let version = filters.filters.scaleVersion
        if let cachedScaleVersion, let version, cachedScaleVersion != version {
            feed.items = []
            Task { await feed.load() }
            Task { await floors.load() }
        }
        if let version { cachedScaleVersion = version }
        _ = filters.filters.effectiveScales
    }
}

private struct FeedRowBox: Identifiable {
    let row: HomeFeedRow
    var id: String { row.id }
}

private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Hosts auction session detail from home slots (own calendar model; show system back).
private struct HomeSessionDetailHost: View {
    let sessionId: Int64
    var title: String?
    @StateObject private var model = AuctionSessionCalendarModel()

    var body: some View {
        AuctionSessionDetailView(
            sessionId: sessionId,
            preload: title.map { AuctionSession(id: sessionId, name: $0) },
            model: model
        )
        .toolbar(.visible, for: .navigationBar)
    }
}

struct SkeletonItem: Identifiable { let id: Int }
