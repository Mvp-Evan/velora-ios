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
        var seq: Int64?
        var endAtVersion: Int?
        var extensionCount: Int?
    }

    /// Lot detail currently visible — suppress duplicate global banner for in-room extend toast (DES-v1.3-03-03 §9).
    var focusedLotId: Int64?

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
    /// Per-lot bid `seq` cursor — drop WS events with seq ≤ local (DES-v1.3-03-02).
    private var seqByLot: [Int64: BidSeqGate] = [:]

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
        if let v = delta.seq { lot.seq = v }
        if let v = delta.endAtVersion { lot.endAtVersion = v }
        if let v = delta.extensionCount { lot.extensionCount = v }
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

    /// Align store cursor after HTTP snapshot / PlaceBid response.
    func alignSeq(lotId: Int64, seq: Int64?) {
        guard let seq else { return }
        var gate = seqByLot[lotId] ?? BidSeqGate()
        gate.align(toSnapshotSeq: seq)
        seqByLot[lotId] = gate
    }

    private func acceptSeq(lotId: Int64, seq: Int64?) -> Bool {
        guard let seq else { return true }
        var gate = seqByLot[lotId] ?? BidSeqGate()
        let ok = gate.note(seq)
        seqByLot[lotId] = gate
        return ok
    }

    private func handle(_ ev: WSEvent) {
        guard let lotId = ev.lotId else { return }
        let seq = ev.int64("seq")
        switch ev.type {
        case "bid_placed":
            guard acceptSeq(lotId: lotId, seq: seq) else { return }
            var d = LotDelta()
            d.currentPrice = ev.int64("amount")
            d.bidCount = ev.int64("bid_count").map(Int.init)
            d.endAt = ev.date("end_at")
            d.currentBidderId = ev.int64("bidder_id")
            d.minNextBid = ev.int64("min_next_bid")
            d.seq = seq
            d.endAtVersion = ev.int64("end_at_version").map(Int.init)
            lotDeltas.send((lotId, d))
            bidEvents.send(ev)
        case "auction_extended":
            var d = LotDelta(endAt: ev.date("end_at"))
            d.endAtVersion = ev.int64("end_at_version").map(Int.init)
            d.extensionCount = ev.int64("extension_count").map(Int.init)
            lotDeltas.send((lotId, d))
            bidEvents.send(ev)
            // In-room full-screen toast handles focused lot; elsewhere keep top notice (N-04).
            if focusedLotId != lotId {
                let when = ev.date("end_at")?.shortText ?? "稍后"
                push(.init(
                    type: ev.type,
                    title: AntiSnipeCopy.extendToastTitle,
                    message: AntiSnipeCopy.extendToastSubtitle(endAtText: when),
                    lotId: lotId,
                    orderId: nil
                ))
            }
        case "auction_started":
            lotDeltas.send((lotId, LotDelta(endAt: ev.date("end_at"), status: .live)))
            bidEvents.send(ev)
        case "auction_ended":
            let st = LotStatus(rawValue: ev.string("status") ?? "ended")
            lotDeltas.send((lotId, LotDelta(currentPrice: ev.int64("final_price"), bidCount: ev.int64("bid_count").map(Int.init), status: st)))
            bidEvents.send(ev)
        case "outbid":
            push(.init(type: ev.type, title: "您的出价已被超越", message: "「\(ev.string("lot_title") ?? "")」最新出价 \(Money(ev.int64("amount") ?? 0).display)", lotId: lotId, orderId: nil))
        case "proxy_exceeded", "proxy_bid_exceeded":
            // N-32 — do not leak others' max; only current / next (design §5.3).
            let next = Money(ev.int64("min_next_bid") ?? ev.int64("current_price") ?? 0).display
            push(.init(
                type: ev.type,
                title: ProxyBidCopy.exceededHint,
                message: "「\(ev.string("lot_title") ?? "")」当前需 \(next) 起，可提高最高价",
                lotId: lotId,
                orderId: nil
            ))
            if focusedLotId == lotId {
                bidEvents.send(ev)
            }
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
