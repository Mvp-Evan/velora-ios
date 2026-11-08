import Foundation
import Combine

/// 我的抽签列表（DES-v1.3-06-02 §9 / GET /me/lottery-entries）。
@MainActor
final class MyLotteryEntriesModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case registered
        case won
        case waitlisted
        case lost
        case paid
        case forfeited

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .registered: return "待开奖"
            case .won: return "中签待付"
            case .waitlisted: return "候补"
            case .lost: return "未中签"
            case .paid: return "已付款"
            case .forfeited: return "已弃权"
            }
        }

        var apiStatus: LotteryEntryStatus? {
            switch self {
            case .all: return nil
            case .registered: return .registered
            case .won: return .won
            case .waitlisted: return .waitlisted
            case .lost: return .lost
            case .paid: return .paid
            case .forfeited: return .forfeited
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
    @Published var items: [LotteryEntry] = []
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
            let pageResult = try await API.myLotteryEntries(
                status: filter.apiStatus,
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

    func subtitle(for entry: LotteryEntry) -> String {
        let cta = LotteryLogic.resolveEntryCTA(entry: entry, serverNow: serverNow)
        switch cta {
        case .pay:
            if let deadline = entry.payDeadline {
                let sec = LotteryLogic.countdownSeconds(until: deadline, serverNow: serverNow)
                return LotteryLogic.payDeadlineCountdownLine(seconds: sec)
            }
            return LotteryCopy.payCTA
        case .waitlist:
            return LotteryLogic.waitlistPositionLine(
                rank: entry.resolvedWaitlistRank,
                remainingUnpaid: entry.remainingUnpaidWon
            )
        case .lost:
            return LotteryCopy.depositReleased
        case .forfeited:
            return LotteryCopy.depositDeducted
        default:
            return entry.resolvedStatus.displayLabel
        }
    }
}
