import Foundation
import Combine

/// 可复用的分页拍品列表模型：下拉刷新 / 上拉加载 / 列表卡片实时（DES-v1.3-02-03）
@MainActor
final class LotListModel: ObservableObject {
    @Published var items: [Lot] = []
    @Published var state: LoadState = .idle
    @Published var hasMore = true
    @Published var total = 0
    @Published private(set) var loadingMore = false

    let realtime = ListCardRealtimeSession()

    var query: API.LotQuery
    private var bag = Set<AnyCancellable>()

    init(query: API.LotQuery = .init()) {
        self.query = query
        // List ignores bid_placed fan-out (T-11); updates come from lot_card_tick only.
        realtime.$liveByLotId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] live in self?.applyLive(live) }
            .store(in: &bag)
        realtime.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    func activateRealtime() { realtime.start() }
    func deactivateRealtime() { realtime.stop() }

    func load(reset: Bool = true) async {
        if reset {
            state = items.isEmpty ? .loading : state
            query.page = 1
            realtime.acknowledgeBannerAndRefresh()
        }
        do {
            let page = try await API.lots(query)
            items = page.items
            hasMore = page.hasMore
            total = page.total
            state = .loaded
            syncRealtimeSeeds()
        } catch {
            if items.isEmpty { state = .failed((error as? APIError)?.message ?? "加载失败") } else { ToastCenter.shared.error(error) }
        }
    }

    func loadMore() async {
        guard hasMore, !loadingMore, state == .loaded else { return }
        loadingMore = true
        defer { loadingMore = false }
        query.page += 1
        do {
            let page = try await API.lots(query)
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            hasMore = page.hasMore
            syncRealtimeSeeds()
        } catch {
            query.page -= 1
        }
    }

    func update(_ lot: Lot) {
        if let i = items.firstIndex(where: { $0.id == lot.id }) { items[i] = lot }
    }

    func shouldLoadMore(_ lot: Lot) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == lot.id }) else { return false }
        return idx >= items.count - 4
    }

    func refreshFromBanner() async {
        realtime.acknowledgeBannerAndRefresh()
        await load(reset: true)
    }

    private func syncRealtimeSeeds() {
        // Lot HTTP payload may not include endAtVersion yet — seed nil; ticks fill it.
        let seeds: [(Int64, Int?)] = items.map { ($0.id, nil) }
        realtime.replaceDataSource(lotIdsWithVersions: seeds)
    }

    private func applyLive(_ live: [Int64: LotCardLiveFields]) {
        guard !live.isEmpty else { return }
        for i in items.indices {
            guard let patch = live[items[i].id] else { continue }
            if let p = patch.currentPrice { items[i].currentPrice = p; items[i].displayPrice = p }
            if let b = patch.bidCount { items[i].bidCount = b }
            if let e = patch.endAt { items[i].endAt = e }
            if let c = patch.extensionCount { items[i].extensionCount = c }
            if let s = patch.status, let st = LotStatus(rawValue: s) { items[i].status = st }
        }
    }
}

/// 筛选字典缓存
@MainActor
final class FiltersStore: ObservableObject {
    static let shared = FiltersStore()
    @Published var filters: Filters = .empty
    private var loaded = false

    func load(force: Bool = false) async {
        guard force || !loaded else { return }
        if let f = try? await API.filters() {
            // HOME-07: scale_version bump → clear feed cache via HomeView reconcile.
            filters = f
            loaded = true
        }
    }
}
