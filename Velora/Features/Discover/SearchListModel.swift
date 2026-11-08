import Foundation
import Combine

/// Paginated listings search (DES-v1.3-02-02) + list realtime (DES-v1.3-02-03).
@MainActor
final class SearchListModel: ObservableObject {
    @Published var items: [SearchListingCard] = []
    @Published var state: LoadState = .idle
    @Published var hasMore = true
    @Published var total = 0
    @Published private(set) var loadingMore = false
    @Published var networkDegraded = false

    let realtime = ListCardRealtimeSession()

    var query: ListingSearchQuery
    private var lastGoodItems: [SearchListingCard] = []
    private var bag = Set<AnyCancellable>()

    init(query: ListingSearchQuery = .init()) {
        self.query = query
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
        if let err = query.validating() {
            state = .failed(err.fallbackMessage)
            return
        }
        if reset {
            state = items.isEmpty ? .loading : state
            query.page = 1
            realtime.acknowledgeBannerAndRefresh()
        }
        do {
            let page = try await API.listings(query)
            items = page.items
            lastGoodItems = page.items
            hasMore = page.hasMore
            total = page.total
            state = .loaded
            networkDegraded = false
            if let ms = page.resolvedServerTimeMs {
                SessionStore.shared.applyServerTimeMs(ms)
            }
            syncRealtimeSeeds()
        } catch let e as APIError {
            handle(e, reset: reset)
        } catch {
            if items.isEmpty { state = .failed("加载失败") } else {
                networkDegraded = true
                ToastCenter.shared.error(error)
            }
        }
    }

    func loadMore() async {
        guard hasMore, !loadingMore, state == .loaded else { return }
        loadingMore = true
        defer { loadingMore = false }
        query.page += 1
        do {
            let page = try await API.listings(query)
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            hasMore = page.hasMore
            total = page.total
            syncRealtimeSeeds()
        } catch {
            query.page -= 1
            networkDegraded = true
        }
    }

    func shouldLoadMore(_ card: SearchListingCard) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == card.id }) else { return false }
        return idx >= items.count - 4
    }

    func onFilterChanged() {
        realtime.clearForFilterChange()
    }

    func refreshFromBanner() async {
        realtime.acknowledgeBannerAndRefresh()
        await load(reset: true)
    }

    private func syncRealtimeSeeds() {
        let seeds: [(Int64, Int?)] = items.compactMap { card in
            guard let lotId = card.lotId, card.tradeType == "auction" else { return nil }
            return (lotId, card.endAtVersion)
        }
        realtime.replaceDataSource(lotIdsWithVersions: seeds)
    }

    private func applyLive(_ live: [Int64: LotCardLiveFields]) {
        guard !live.isEmpty else { return }
        var changed = false
        for i in items.indices {
            guard let lotId = items[i].lotId, let patch = live[lotId] else { continue }
            items[i].applyLive(patch)
            changed = true
        }
        if changed { objectWillChange.send() }
    }

    private func handle(_ e: APIError, reset: Bool) {
        if let code = SearchErrorCode(rawValue: e.code) {
            state = .failed(code.fallbackMessage)
            ToastCenter.shared.show(code.fallbackMessage, .info)
            return
        }
        if e.code == "network" || e.status == 0 {
            networkDegraded = true
            if items.isEmpty, !lastGoodItems.isEmpty {
                items = lastGoodItems
                state = .loaded
            } else if items.isEmpty {
                state = .failed(e.message)
            } else {
                ToastCenter.shared.show("网络不佳", .info)
            }
            return
        }
        if items.isEmpty { state = .failed(e.message) } else { ToastCenter.shared.error(e) }
    }
}

@MainActor
final class SearchMetaStore: ObservableObject {
    static let shared = SearchMetaStore()

    @Published var hotWords: [HotWord] = HotWordsResponse.presetFallback.items
    @Published var shortcuts = UserShortcutsResponse()
    @Published var savedCount = 0

    private var hotLoadedAt: Date?
    private let hotCacheTTL: TimeInterval = 60

    func loadHotWords(force: Bool = false) async {
        if !force, let at = hotLoadedAt, Date().timeIntervalSince(at) < hotCacheTTL { return }
        do {
            let resp = try await API.hotWords()
            if !resp.items.isEmpty {
                hotWords = resp.items.sorted { ($0.weight ?? 0) > ($1.weight ?? 0) }
            }
            hotLoadedAt = Date()
        } catch {
            if hotWords.isEmpty { hotWords = HotWordsResponse.presetFallback.items }
        }
    }

    func loadShortcuts() async {
        guard SessionStore.shared.isLoggedIn else {
            shortcuts = UserShortcutsResponse()
            return
        }
        if let resp = try? await API.myShortcuts() {
            shortcuts = resp
        }
    }

    func saveShortcuts() async -> SearchErrorCode? {
        guard SessionStore.shared.isLoggedIn else { return .loginRequired }
        do {
            shortcuts = try await API.putShortcuts(shortcuts.words)
            return nil
        } catch let e as APIError {
            return SearchErrorCode(rawValue: e.code) ?? nil
        } catch {
            return nil
        }
    }

    func refreshSavedCount() async {
        guard SessionStore.shared.isLoggedIn else { savedCount = 0; return }
        if let resp = try? await API.savedSearches() {
            savedCount = resp.activeCount
        }
    }
}
