import Foundation
import Combine

/// Parallel floor loads for purchase-home「全部」视图 (DES-v1.3-02-01 floors).
/// Each floor fails silently so one empty/error channel does not blank the page.
@MainActor
final class HomeFloorsModel: ObservableObject {
    @Published private(set) var liveAuctions: [HomeFeedCard] = []
    @Published private(set) var upcomingAuctions: [HomeFeedCard] = []
    @Published private(set) var releases: [HomeFeedCard] = []
    @Published private(set) var loading = false
    @Published private(set) var lastLoadedAt: Date?

    var hasAnyContent: Bool {
        !liveAuctions.isEmpty || !upcomingAuctions.isEmpty || !releases.isEmpty
    }

    func load() async {
        loading = true
        defer {
            loading = false
            lastLoadedAt = Date()
        }

        async let liveTask = fetch(tab: .hot, tradeType: "auction", status: "live", pageSize: 12)
        async let upcomingTask = fetch(tab: .new, tradeType: "auction", status: "scheduled", pageSize: 10)
        async let releaseTask = fetch(tab: .hot, tradeType: "release", status: nil, pageSize: 6)

        let (live, upcoming, release) = await (liveTask, upcomingTask, releaseTask)
        liveAuctions = live
        upcomingAuctions = upcoming
        releases = release
    }

    private func fetch(
        tab: HomeFeedTab,
        tradeType: String,
        status: String?,
        pageSize: Int
    ) async -> [HomeFeedCard] {
        do {
            let resp = try await API.homeFeed(
                tab: tab.rawValue,
                cursor: nil,
                pageSize: pageSize,
                tradeType: tradeType,
                status: status
            )
            if let ms = resp.resolvedServerTimeMs {
                SessionStore.shared.applyServerTimeMs(ms)
            }
            return resp.items
        } catch {
            return []
        }
    }
}
