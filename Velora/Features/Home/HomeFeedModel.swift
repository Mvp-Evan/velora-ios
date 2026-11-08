import Foundation
import Combine

/// Cursor-paginated purchase-home channel feed (`GET /home/feed`) + list realtime (DES-v1.3-02-03).
@MainActor
final class HomeFeedModel: ObservableObject {
    @Published var items: [HomeFeedCard] = []
    @Published var state: LoadState = .idle
    @Published var hasMore = true
    @Published private(set) var loadingMore = false
    @Published private(set) var feedVersion: Int64?
    @Published private(set) var needsLogin = false
    /// Hot channel cold-start: server empty → fall back to「上新」with banner copy (DES §9).
    @Published private(set) var showingHotFallback = false

    let realtime = ListCardRealtimeSession()

    private(set) var tab: HomeFeedTab
    /// Optional server-side trade_type filter (e.g. `"auction"` for 拍卖频道).
    private(set) var tradeType: String?
    private var cursor: String?
    private var bag = Set<AnyCancellable>()

    init(tab: HomeFeedTab = .hot, tradeType: String? = nil) {
        self.tab = tab
        self.tradeType = tradeType
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

    func setTab(_ tab: HomeFeedTab) {
        guard self.tab != tab else { return }
        self.tab = tab
        items = []
        cursor = nil
        hasMore = true
        needsLogin = false
        showingHotFallback = false
        state = .idle
        realtime.clearForFilterChange()
    }

    func setTradeType(_ tradeType: String?) {
        guard self.tradeType != tradeType else { return }
        self.tradeType = tradeType
        items = []
        cursor = nil
        hasMore = true
        needsLogin = false
        showingHotFallback = false
        state = .idle
        realtime.clearForFilterChange()
    }

    func load(reset: Bool = true) async {
        if reset {
            cursor = nil
            hasMore = true
            needsLogin = false
            showingHotFallback = false
            if items.isEmpty { state = .loading }
            realtime.acknowledgeBannerAndRefresh()
        }
        do {
            let resp = try await API.homeFeed(
                tab: tab.rawValue,
                cursor: cursor,
                tradeType: tradeType
            )
            applyServerTime(resp)
            feedVersion = resp.feedVersion
            items = resp.items
            cursor = resp.nextCursor
            hasMore = resp.nextCursor != nil
            state = .loaded
            syncRealtimeSeeds()

            if tab == .hot, tradeType == nil, items.isEmpty {
                await loadHotFallback()
            }
        } catch let e as APIError where e.code == "login_required" || e.isUnauthorized {
            needsLogin = true
            items = []
            hasMore = false
            state = .loaded
            realtime.clearForFilterChange()
        } catch {
            if items.isEmpty {
                state = .failed((error as? APIError)?.message ?? "加载失败")
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }

    func loadMore() async {
        guard hasMore, !loadingMore, state == .loaded, let cursor else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let resp = try await API.homeFeed(
                tab: showingHotFallback ? HomeFeedTab.new.rawValue : tab.rawValue,
                cursor: cursor,
                tradeType: tradeType
            )
            applyServerTime(resp)
            let known = Set(items.map(\.listingId))
            items.append(contentsOf: resp.items.filter { !known.contains($0.listingId) })
            self.cursor = resp.nextCursor
            hasMore = resp.nextCursor != nil
            syncRealtimeSeeds()
        } catch {
            // Keep cursor; user can retry via scroll or pull.
        }
    }

    func shouldLoadMore(_ card: HomeFeedCard) -> Bool {
        guard let idx = items.firstIndex(where: { $0.listingId == card.listingId }) else { return false }
        return idx >= items.count - 4
    }

    func refreshFromBanner() async {
        realtime.acknowledgeBannerAndRefresh()
        await load(reset: true)
    }

    private func loadHotFallback() async {
        do {
            let resp = try await API.homeFeed(
                tab: HomeFeedTab.new.rawValue,
                cursor: nil,
                tradeType: tradeType
            )
            applyServerTime(resp)
            items = resp.items
            cursor = resp.nextCursor
            hasMore = resp.nextCursor != nil
            showingHotFallback = !items.isEmpty
            syncRealtimeSeeds()
        } catch {
            // Keep empty hot state.
        }
    }

    private func applyServerTime(_ resp: HomeFeedResponse) {
        if let ms = resp.resolvedServerTimeMs {
            SessionStore.shared.applyServerTimeMs(ms)
        }
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
        for i in items.indices {
            guard let lotId = items[i].lotId, let patch = live[lotId] else { continue }
            items[i].applyLive(patch)
        }
    }
}
