import Foundation
import Combine

/// 我的补款列表（DES-v1.3-06-03 §5.10 / GET /me/presale-orders）。
@MainActor
final class MyBalanceOrdersModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case depositPending
        case balancePending
        case balancePaid
        case expired
        case refunding

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .depositPending: return "待付定金"
            case .balancePending: return "待补款"
            case .balancePaid: return "已补款"
            case .expired: return "逾期"
            case .refunding: return "退款中"
            }
        }

        var apiStatus: PresaleBizStatus? {
            switch self {
            case .all: return nil
            case .depositPending: return .depositPending
            case .balancePending: return .balancePending
            case .balancePaid: return .balancePaid
            case .expired: return .expired
            case .refunding: return .buyerRefunded
            }
        }
    }

    @Published var filter: Filter = .all {
        didSet {
            if oldValue != filter {
                Task { await load(reset: true) }
            }
        }
    }
    @Published var items: [PresaleOrderSummary] = []
    @Published var state: LoadState = .idle
    @Published var hasMore = false
    @Published var loadingMore = false

    private var page = 1

    var serverNow: Date {
        let ms = SessionStore.shared.serverClock.serverNowMs()
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    func load(reset: Bool = true) async {
        if reset {
            page = 1
            if items.isEmpty { state = .loading }
        }
        do {
            let pageResult = try await API.myPresaleOrders(
                bizStatus: filter.apiStatus,
                page: page
            )
            if reset {
                items = pageResult.items
            } else {
                items.append(contentsOf: pageResult.items)
            }
            hasMore = pageResult.hasMore
            state = .loaded
        } catch let e as APIError {
            if items.isEmpty {
                state = .failed(e.message)
            } else {
                ToastCenter.shared.error(e)
            }
        } catch {
            if items.isEmpty {
                state = .failed("加载失败")
            }
        }
    }

    func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        page += 1
        await load(reset: false)
    }

    func subtitle(for order: PresaleOrderSummary) -> String {
        PresaleLogic.listSubtitle(order: order, serverNow: serverNow)
    }
}
