import SwiftUI

/// 拍场 Tab：进行中 / 即将开始 / 已结束
struct AuctionsView: View {
    enum Segment: String, CaseIterable { case live, upcoming, ended }
    @State private var segment: Segment = .live
    @StateObject private var live = LotListModel(query: .init(status: "live", sort: "ending"))
    @StateObject private var upcoming = LotListModel(query: .init(status: "upcoming", sort: "starting"))
    @StateObject private var ended = LotListModel(query: .init(status: "ended"))
    @StateObject private var filters = FiltersStore.shared
    @State private var sort = "ending"

    private var current: LotListModel {
        switch segment { case .live: return live; case .upcoming: return upcoming; case .ended: return ended }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ListRealtimeBanner(
                    endTimeText: current.realtime.endTimeChanges.showsBanner
                        ? current.realtime.endTimeChanges.bannerText : nil,
                    offline: current.realtime.realtimePaused && !current.items.isEmpty && segment != .ended
                ) {
                    Task { await current.refreshFromBanner() }
                }
                VSegmentedTabs(items: [(Segment.live, "进行中"), (.upcoming, "即将开始"), (.ended, "已结束")], selection: $segment,
                               counts: [.live: live.total])
                    .padding(.vertical, VSpace.s)
                if segment == .live {
                    VPillSegments(items: [("ending", "即将结束"), ("hot", "最热"), ("newest", "最新"), ("price_asc", "价格↑"), ("price_desc", "价格↓")], selection: $sort)
                        .padding(.bottom, VSpace.s)
                        .onChange(of: sort) { _, v in
                            live.realtime.clearForFilterChange()
                            live.query.sort = v
                            Task { await live.load() }
                        }
                }
                TabView(selection: $segment) {
                    list(live).tag(Segment.live)
                    list(upcoming).tag(Segment.upcoming)
                    list(ended).tag(Segment.ended)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color.vBackground)
            .navigationTitle("拍场")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { AuctionSessionCalendarView() } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("专场日历")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SearchView() } label: { Image(systemName: "magnifyingglass") }
                }
            }
            .navigationDestination(for: Lot.self) { LotDetailView(lotId: $0.id, preload: $0) }
        }
        .task {
            live.activateRealtime()
            upcoming.activateRealtime()
            await filters.load()
            if live.items.isEmpty { await live.load() }
        }
        .onDisappear {
            live.deactivateRealtime()
            upcoming.deactivateRealtime()
        }
        .onChange(of: segment) { _, s in
            Task { if current.items.isEmpty { await current.load() } }
        }
    }

    private func list(_ model: LotListModel) -> some View {
        ScrollView {
            switch model.state {
            case .idle, .loading: VLoadingView()
            case .failed(let m): VErrorView(message: m) { Task { await model.load() } }
            case .loaded:
                if model.items.isEmpty {
                    VEmptyState(icon: "flag.checkered", title: "这里还没有拍品")
                } else {
                    LazyVStack(spacing: VSpace.m) {
                        ForEach(model.items) { lot in
                            NavigationLink(value: lot) {
                                AuctionRow(lot: lot, delayed: model.realtime.live(for: lot.id)?.delayed == true)
                            }
                            .buttonStyle(.plain)
                            .reportLotCardVisibility(
                                lotId: segment == .ended ? nil : lot.id,
                                onRatio: { id, ratio in model.realtime.updateVisibility(lotId: id, ratio: ratio) },
                                onDisappear: { id in model.realtime.cardDidDisappear(lotId: id) }
                            )
                            .onAppear { if model.shouldLoadMore(lot) { Task { await model.loadMore() } } }
                        }
                        if model.loadingMore { ProgressView().padding() }
                    }
                    .padding(.horizontal, VSpace.l).padding(.bottom, VSpace.xl)
                }
            }
        }
        .refreshable {
            model.realtime.acknowledgeBannerAndRefresh()
            await model.load()
        }
    }
}

/// 拍场列表大图行
struct AuctionRow: View {
    let lot: Lot
    var delayed: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(lot.cover).frame(height: 190)
                VGradient.imageScrim.frame(height: 90).frame(maxHeight: .infinity, alignment: .bottom)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            VStatusBadge(status: lot.status)
                            if delayed {
                                Text(LotCardHeatCopy.delayedBadge)
                                    .font(.vMicro).foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color.vGold.opacity(0.95), in: Capsule())
                            }
                        }
                        Text(lot.title).font(.vHeadline).foregroundStyle(.white).lineLimit(1)
                    }
                    Spacer()
                    if lot.isLive || lot.isUpcoming {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(lot.isUpcoming ? "距开拍" : "距结束").font(.vMicro).foregroundStyle(.white.opacity(0.75))
                            VCountdown(endAt: lot.isUpcoming ? lot.startAt : lot.endAt, status: lot.status, style: .inline).foregroundStyle(.white)
                        }
                    }
                }
                .padding(12)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: VRadius.l, topTrailingRadius: VRadius.l, style: .continuous))

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lot.isFinished ? (lot.status == .ended ? "成交价" : "最终价") : (lot.bidCount > 0 ? "当前价" : "起拍价"))
                        .font(.vMicro).foregroundStyle(Color.vTextTertiary)
                    VPriceText(amount: lot.displayPrice, size: 20)
                }
                Spacer()
                HStack(spacing: 14) {
                    stat("\(lot.bidCount)", "出价")
                    stat("\(lot.followCount)", "关注")
                    stat(lot.viewCount.compact, "围观")
                }
                if lot.myBid.hasBid {
                    Text(lot.myBid.leading ? "领先" : "被超越").font(.vMicro).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(lot.myBid.leading ? Color.vGold : Color.vCarbon.opacity(0.75), in: Capsule())
                }
            }
            .padding(12)
            .background(Color.vSurface)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: VRadius.l, bottomTrailingRadius: VRadius.l, style: .continuous))
        }
    }

    private func stat(_ v: String, _ k: String) -> some View {
        VStack(spacing: 1) {
            Text(v).font(.vMono(14)).foregroundStyle(Color.vText)
            Text(k).font(.vMicro).foregroundStyle(Color.vTextTertiary)
        }
    }
}
