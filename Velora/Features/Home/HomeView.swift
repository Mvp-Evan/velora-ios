import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var feed = LotListModel(query: .init(status: nil, sort: nil))
    @StateObject private var hot = LotListModel(query: .init(status: "live", sort: "hot", pageSize: 10))
    @StateObject private var filters = FiltersStore.shared
    @State private var category: String = ""
    @State private var path = NavigationPath()

    private let categoryAll = ""

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: VSpace.l, pinnedViews: []) {
                    header
                    categoryChips
                    banner
                    hotStrip
                    waterfall
                }
                .padding(.bottom, VSpace.xl)
            }
            .background(Color.vBackground)
            .scrollIndicators(.hidden)
            .refreshable { await reload() }
            .navigationDestination(for: Lot.self) { LotDetailView(lotId: $0.id, preload: $0) }
            .navigationDestination(for: Route.self) { r in
                switch r {
                case .search(let q): SearchView(initialQuery: q)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await filters.load()
            if feed.items.isEmpty { await reload() }
        }
    }

    enum Route: Hashable { case search(String) }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Text("Velora").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(Color.vPrimary)
            Button { path.append(Route.search("")) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.vTextTertiary)
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
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", categoryAll)
                ForEach(filters.filters.categories, id: \.self) { chip($0, $0) }
            }
            .padding(.horizontal, VSpace.l)
        }
    }

    private func chip(_ title: String, _ value: String) -> some View {
        let on = category == value
        return Button {
            Haptics.light()
            category = value
            feed.query.category = value.isEmpty ? nil : value
            Task { await feed.load() }
        } label: {
            Text(title)
                .font(on ? .vCaptionMedium : .vCaption)
                .foregroundStyle(on ? .white : Color.vText)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? Color.vCarbon : Color.vSurface, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var banner: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous).fill(VGradient.carbon)
            Circle().fill(Color.vPrimary.opacity(0.9)).frame(width: 180, height: 180).offset(x: 240, y: 40).blur(radius: 30)
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LIVE AUCTION").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(Color.vGold)
                    Text("每一次出价\n都是冲线前的加速").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Text("\(hot.total > 0 ? hot.total : feed.total) 件拍品正在竞拍").font(.vCaption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "flag.checkered.2.crossed").font(.system(size: 54, weight: .thin)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(VSpace.xl)
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous))
        .padding(.horizontal, VSpace.l)
        .onTapGesture { router.tab = .auctions }
    }

    @ViewBuilder private var hotStrip: some View {
        if !hot.items.isEmpty {
            VStack(alignment: .leading, spacing: VSpace.m) {
                VSectionHeader(title: "正在竞拍", subtitle: "热度最高", action: { router.tab = .auctions })
                    .padding(.horizontal, VSpace.l)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VSpace.m) {
                        ForEach(hot.items) { lot in
                            NavigationLink(value: lot) { LotStripCard(lot: lot) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, VSpace.l)
                }
            }
        }
    }

    @ViewBuilder private var waterfall: some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            VSectionHeader(title: "即将结拍", subtitle: feed.total > 0 ? "\(feed.total) 件" : nil)
                .padding(.horizontal, VSpace.l)

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
                if feed.items.isEmpty {
                    VEmptyState(icon: "flag.checkered", title: "暂无拍品", message: "换个分类试试，或者发布你的第一件拍品")
                } else {
                    WaterfallGrid(items: feed.items, height: { LotCard.estimatedHeight(for: $0, imageHeight: LotCard.imageHeight(for: $0)) }) { lot in
                        NavigationLink(value: lot) { LotCard(lot: lot, imageHeight: LotCard.imageHeight(for: lot)) }
                            .buttonStyle(.plain)
                            .onAppear { if feed.shouldLoadMore(lot) { Task { await feed.loadMore() } } }
                    }
                    .padding(.horizontal, VSpace.m)
                    if feed.loadingMore { ProgressView().padding() }
                    else if !feed.hasMore { Text("— 已经到底啦 —").font(.vMicro).foregroundStyle(Color.vTextTertiary).frame(maxWidth: .infinity).padding() }
                }
            }
        }
    }

    private func reload() async {
        async let a: () = feed.load()
        async let b: () = hot.load()
        _ = await (a, b)
    }
}

struct SkeletonItem: Identifiable { let id: Int }
