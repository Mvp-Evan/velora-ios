import Foundation
import Combine

/// 可复用的分页拍品列表模型：下拉刷新 / 上拉加载 / 实时增量
@MainActor
final class LotListModel: ObservableObject {
    @Published var items: [Lot] = []
    @Published var state: LoadState = .idle
    @Published var hasMore = true
    @Published var total = 0
    @Published private(set) var loadingMore = false

    var query: API.LotQuery
    private var bag = Set<AnyCancellable>()

    init(query: API.LotQuery = .init()) {
        self.query = query
        AuctionLiveStore.shared.lotDeltas.sink { [weak self] id, delta in
            guard let self, let idx = self.items.firstIndex(where: { $0.id == id }) else { return }
            AuctionLiveStore.shared.apply(delta, to: &self.items[idx])
        }.store(in: &bag)
    }

    func load(reset: Bool = true) async {
        if reset { state = items.isEmpty ? .loading : state; query.page = 1 }
        do {
            let page = try await API.lots(query)
            items = page.items
            hasMore = page.hasMore
            total = page.total
            state = .loaded
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
}

/// 筛选字典缓存
@MainActor
final class FiltersStore: ObservableObject {
    static let shared = FiltersStore()
    @Published var filters: Filters = .empty
    private var loaded = false

    func load() async {
        guard !loaded else { return }
        if let f = try? await API.filters() { filters = f; loaded = true }
    }
}
