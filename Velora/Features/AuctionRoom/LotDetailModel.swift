import Foundation
import Combine

/// 拍卖间状态：拍品详情 + 实时出价流 + 事件提示
@MainActor
final class LotDetailModel: ObservableObject {
    struct FeedItem: Identifiable, Equatable {
        enum Kind: Equatable { case bid(amount: Money, name: String, avatar: String, mine: Bool), extended, started, ended(sold: Bool), system(String) }
        let id: String
        let kind: Kind
        let at: Date
    }

    enum Prompt: Identifiable, Equatable {
        case outbid(minNext: Money), extended(Date), won(orderId: Int64), lost, unsold, cancelled
        var id: String {
            switch self {
            case .outbid: return "outbid"; case .extended: return "extended"; case .won: return "won"
            case .lost: return "lost"; case .unsold: return "unsold"; case .cancelled: return "cancelled"
            }
        }
    }

    let lotId: Int64
    @Published var lot: Lot?
    @Published var state: LoadState = .idle
    @Published var feed: [FeedItem] = []
    @Published var prompt: Prompt?
    @Published var bidding = false
    @Published var needsDeposit = false
    @Published var priceBump = false
    @Published var customAmount: String = ""

    private var bag = Set<AnyCancellable>()
    private var subscribed = false

    init(lotId: Int64, preload: Lot?) {
        self.lotId = lotId
        self.lot = preload
        if preload != nil { state = .loaded }

        AuctionLiveStore.shared.lotDeltas.sink { [weak self] id, delta in
            guard let self, id == self.lotId, var l = self.lot else { return }
            AuctionLiveStore.shared.apply(delta, to: &l)
            self.lot = l
        }.store(in: &bag)

        AuctionLiveStore.shared.bidEvents.sink { [weak self] ev in
            guard let self, ev.lotId == self.lotId else { return }
            self.handle(ev)
        }.store(in: &bag)
    }

    var me: Int64? { SessionStore.shared.user?.id }
    var isSeller: Bool { lot.map { $0.sellerId == me } ?? false }
    var isLeading: Bool { lot?.currentBidderId != nil && lot?.currentBidderId == me }
    var isWinner: Bool { lot?.status == .ended && lot?.winnerId == me }

    /// 快捷出价阶梯：最低加价 ×1 / ×2 / ×5
    var quickBids: [Money] {
        guard let lot else { return [] }
        let base = lot.minNextBid
        let inc = lot.bidIncrement
        return [base, base + inc, base + inc * 4]
    }

    var isPreview: Bool { lotId == 0 }

    func load() async {
        guard !isPreview else { return }
        if lot == nil { state = .loading }
        do {
            let l = try await API.lot(lotId)
            lot = l
            state = .loaded
            if feed.isEmpty, let bids = l.recentBids {
                feed = bids.map { FeedItem(id: "bid-\($0.id)", kind: .bid(amount: $0.amount, name: $0.bidderName, avatar: $0.bidderAvatar, mine: $0.bidderId == me), at: $0.createdAt) }
            }
        } catch {
            if lot == nil { state = .failed((error as? APIError)?.message ?? "加载失败") }
        }
    }

    func subscribe() {
        guard !subscribed, !isPreview else { return }
        subscribed = true
        WebSocketClient.shared.subscribeLot(lotId)
    }

    func unsubscribe() {
        guard subscribed else { return }
        subscribed = false
        WebSocketClient.shared.unsubscribeLot(lotId)
    }

    func placeBid(_ amount: Money) async -> Bool {
        guard !bidding else { return false }
        bidding = true
        defer { bidding = false }
        do {
            if let lot, lot.depositAmount > 0 {
                let info = try? await API.lotDeposit(lotId)
                if info?.deposit?.status != "held" && info?.deposit?.status != "applied" {
                    needsDeposit = true
                    ToastCenter.shared.show("请先缴纳竞拍押金 \(lot.depositAmount.display)", .info)
                    return false
                }
            }
            let r = try await API.bid(lotId, amount: amount)
            lot = r.lot
            Haptics.success()
            ToastCenter.shared.show("出价成功，当前领先", .success)
            return true
        } catch {
            if let e = error as? APIError {
                switch e.code {
                case "bid_too_low":
                    ToastCenter.shared.show("出价已被抢先，请按最新价格出价", .error)
                    await load()
                case "already_leading": ToastCenter.shared.show("您已是当前最高出价", .info)
                case "own_lot": ToastCenter.shared.show("不能对自己的拍品出价", .error)
                case "auction_not_live": ToastCenter.shared.show("拍卖未在进行中", .error); await load()
                case "conflict" where e.message.contains("押金"):
                    needsDeposit = true
                    ToastCenter.shared.show(e.message, .info)
                default: ToastCenter.shared.error(e)
                }
            } else { ToastCenter.shared.error(error) }
            return false
        }
    }

    func toggleFollow() async {
        guard var l = lot else { return }
        let target = !l.isFollowing
        l.isFollowing = target
        l.followCount += target ? 1 : -1
        lot = l
        Haptics.light()
        do { try await API.follow(lotId, target) } catch {
            l.isFollowing.toggle(); l.followCount += target ? -1 : 1; lot = l
            ToastCenter.shared.error(error)
        }
    }

    func cancel() async {
        do {
            lot = try await API.cancelLot(lotId)
            ToastCenter.shared.show("已撤拍", .success)
        } catch { ToastCenter.shared.error(error) }
    }

    // MARK: Events

    private func handle(_ ev: WSEvent) {
        switch ev.type {
        case "bid_placed":
            let bidder = ev.int64("bidder_id")
            let mine = bidder == me
            feed.insert(FeedItem(id: "bid-\(ev.int64("bid_id") ?? Int64(Date().timeIntervalSince1970 * 1000))",
                                 kind: .bid(amount: ev.int64("amount") ?? 0, name: ev.string("bidder_nickname") ?? "", avatar: ev.string("bidder_avatar") ?? "", mine: mine),
                                 at: ev.date("at") ?? Date()), at: 0)
            bump()
            if !mine, lot?.myBid.hasBid == true { prompt = .outbid(minNext: ev.int64("min_next_bid") ?? lot?.minNextBid ?? 0) }
        case "auction_extended":
            if let d = ev.date("end_at") {
                feed.insert(FeedItem(id: "ext-\(ev.at.timeIntervalSince1970)", kind: .extended, at: ev.at), at: 0)
                if prompt == nil || !(prompt?.id == "outbid") { prompt = .extended(d) }
            }
        case "auction_started":
            feed.insert(FeedItem(id: "start", kind: .started, at: ev.at), at: 0)
        case "auction_ended":
            let sold = ev.string("status") == "ended"
            feed.insert(FeedItem(id: "end", kind: .ended(sold: sold), at: ev.at), at: 0)
            let winner = ev.int64("winner_id")
            if sold, winner == me, let oid = ev.int64("order_id") {
                if var l = lot { l.winnerId = me; l.orderId = oid; lot = l }
                prompt = .won(orderId: oid)
            } else if sold, lot?.myBid.hasBid == true { prompt = .lost }
            else if !sold, isSeller { prompt = .unsold }
            Task { await load() }
        default: break
        }
        if feed.count > 100 { feed.removeLast(feed.count - 100) }
    }

    private func bump() {
        priceBump = true
        Task { try? await Task.sleep(for: .seconds(0.5)); priceBump = false }
    }
}
