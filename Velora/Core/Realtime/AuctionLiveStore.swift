import Foundation
import Combine

/// 全局实时状态：监听 WS 事件，向各页面派发拍品增量更新与用户通知
@MainActor
final class AuctionLiveStore: ObservableObject {
    static let shared = AuctionLiveStore()

    /// 拍品级别增量（价格、出价数、结束时间、状态）
    struct LotDelta {
        var currentPrice: Money?
        var bidCount: Int?
        var endAt: Date?
        var status: LotStatus?
        var currentBidderId: Int64?
        var minNextBid: Money?
    }

    /// 用户级别的通知（被超越、拍中、售出、开拍等）
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let type: String
        let title: String
        let message: String
        let lotId: Int64?
        let orderId: Int64?
    }

    let lotDeltas = PassthroughSubject<(Int64, LotDelta), Never>()
    let bidEvents = PassthroughSubject<WSEvent, Never>()
    @Published var latestNotice: Notice?
    @Published var noticeFeed: [Notice] = []

    private var bag = Set<AnyCancellable>()

    private init() {
        WebSocketClient.shared.events.sink { [weak self] ev in self?.handle(ev) }.store(in: &bag)
    }

    func apply(_ delta: LotDelta, to lot: inout Lot) {
        if let v = delta.currentPrice { lot.currentPrice = v }
        if let v = delta.bidCount { lot.bidCount = v }
        if let v = delta.endAt { lot.endAt = v }
        if let v = delta.status { lot.status = v }
        if let v = delta.minNextBid { lot.minNextBid = v }
        if let v = delta.currentPrice { lot.displayPrice = v }
        if let bidder = delta.currentBidderId {
            lot.currentBidderId = bidder
            if let me = SessionStore.shared.user?.id {
                if bidder == me {
                    lot.myBid.hasBid = true
                    lot.myBid.leading = true
                    lot.myBid.maxAmount = max(lot.myBid.maxAmount, delta.currentPrice ?? 0)
                } else if lot.myBid.hasBid {
                    lot.myBid.leading = false
                }
            }
        }
    }

    private func handle(_ ev: WSEvent) {
        guard let lotId = ev.lotId else { return }
        switch ev.type {
        case "bid_placed":
            var d = LotDelta()
            d.currentPrice = ev.int64("amount")
            d.bidCount = ev.int64("bid_count").map(Int.init)
            d.endAt = ev.date("end_at")
            d.currentBidderId = ev.int64("bidder_id")
            d.minNextBid = ev.int64("min_next_bid")
            lotDeltas.send((lotId, d))
            bidEvents.send(ev)
        case "auction_extended":
            lotDeltas.send((lotId, LotDelta(endAt: ev.date("end_at"))))
            bidEvents.send(ev)
            let when = ev.date("end_at")?.shortText ?? "稍后"
            push(.init(type: ev.type, title: "拍卖已延时 2 分钟", message: "截止前有新出价，结束时间改为 \(when)", lotId: lotId, orderId: nil))
        case "auction_started":
            lotDeltas.send((lotId, LotDelta(endAt: ev.date("end_at"), status: .live)))
            bidEvents.send(ev)
        case "auction_ended":
            let st = LotStatus(rawValue: ev.string("status") ?? "ended")
            lotDeltas.send((lotId, LotDelta(currentPrice: ev.int64("final_price"), bidCount: ev.int64("bid_count").map(Int.init), status: st)))
            bidEvents.send(ev)
        case "outbid":
            push(.init(type: ev.type, title: "您的出价已被超越", message: "「\(ev.string("lot_title") ?? "")」最新出价 \(Money(ev.int64("amount") ?? 0).display)", lotId: lotId, orderId: nil))
        case "auction_won":
            push(.init(type: ev.type, title: "恭喜拍中！", message: "「\(ev.string("lot_title") ?? "")」请在 24 小时内完成付款", lotId: lotId, orderId: ev.int64("order_id")))
            Task { await SessionStore.shared.refreshMe() }
        case "lot_sold":
            push(.init(type: ev.type, title: "拍品已成交", message: "「\(ev.string("lot_title") ?? "")」以 \(Money(ev.int64("amount") ?? 0).display) 成交", lotId: lotId, orderId: ev.int64("order_id")))
        case "lot_unsold":
            push(.init(type: ev.type, title: "拍品流拍", message: "「\(ev.string("lot_title") ?? "")」本次未成交，可重新上拍", lotId: lotId, orderId: nil))
        case "lot_started":
            push(.init(type: ev.type, title: "关注的拍品开拍了", message: "「\(ev.string("lot_title") ?? "")」正在竞拍中", lotId: lotId, orderId: nil))
        default:
            break
        }
    }

    private func push(_ n: Notice) {
        latestNotice = n
        noticeFeed.insert(n, at: 0)
        if noticeFeed.count > 50 { noticeFeed.removeLast() }
    }
}
