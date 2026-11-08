import Foundation
import Combine

/// 拍卖间状态：拍品详情 + 实时出价流 + 事件提示（DES-v1.3-03-02 幂等 / seq）+ 代理出价（DES-v1.3-03-04）
@MainActor
final class LotDetailModel: ObservableObject {
    struct FeedItem: Identifiable, Equatable {
        enum Kind: Equatable { case bid(amount: Money, name: String, avatar: String, mine: Bool), extended, started, ended(sold: Bool), system(String) }
        let id: String
        let kind: Kind
        let at: Date
    }

    enum Prompt: Identifiable, Equatable {
        case outbid(minNext: Money), proxyExceeded(minNext: Money), extended(Date), won(orderId: Int64), lost, unsold, cancelled
        var id: String {
            switch self {
            case .outbid: return "outbid"
            case .proxyExceeded: return "proxy_exceeded"
            case .extended: return "extended"; case .won: return "won"
            case .lost: return "lost"; case .unsold: return "unsold"; case .cancelled: return "cancelled"
            }
        }
    }

    /// Full-screen delay toast (DES-v1.3-03-03 §9) — auto-dismiss, not a modal PromptCard.
    struct ExtendToast: Equatable {
        let endAt: Date
        let endAtVersion: Int
    }

    let lotId: Int64
    @Published var lot: Lot?
    @Published var state: LoadState = .idle
    @Published var feed: [FeedItem] = []
    @Published var prompt: Prompt?
    @Published var extendToast: ExtendToast?
    @Published var closingRemindSubscribed = false
    @Published var reminding = false
    @Published var bidding = false
    @Published var needsDeposit = false
    @Published var needsRealName = false
    @Published var priceBump = false
    @Published var customAmount: String = ""
    @Published private(set) var realtimePaused = false
    /// Own proxy row only (GET/PUT); never from public lot JSON (design §6 / §8).
    @Published var proxyBid: ProxyBidState?
    @Published var proxyLoading = false
    @Published var proxySaving = false
    /// Feature flag off from server (`feature_disabled`).
    @Published var proxyFeatureDisabled = false

    private var bag = Set<AnyCancellable>()
    private var subscribed = false
    private var seqGate = BidSeqGate()
    private var idempotency = BidIdempotencySession()
    private var proxyIdempotency = BidIdempotencySession()
    private var lastExtendToastVersion: Int = 0
    private var extendToastTask: Task<Void, Never>?

    init(lotId: Int64, preload: Lot?) {
        self.lotId = lotId
        self.lot = preload
        if let s = preload?.seq { seqGate.align(toSnapshotSeq: s) }
        if preload != nil { state = .loaded }

        AuctionLiveStore.shared.lotDeltas.sink { [weak self] id, delta in
            guard let self, id == self.lotId, var l = self.lot else { return }
            // Stale seq already dropped in AuctionLiveStore; do not re-gate here or feed
            // handling of the same bid_placed would see seq as already applied.
            AuctionLiveStore.shared.apply(delta, to: &l)
            self.lot = l
        }.store(in: &bag)

        AuctionLiveStore.shared.bidEvents.sink { [weak self] ev in
            guard let self, ev.lotId == self.lotId else { return }
            self.handle(ev)
        }.store(in: &bag)

        WebSocketClient.shared.$connected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ok in
                guard let self else { return }
                self.realtimePaused = !ok
                if ok, self.subscribed {
                    Task { await self.resyncAfterReconnect() }
                }
            }
            .store(in: &bag)
    }

    var me: Int64? { SessionStore.shared.user?.id }
    var isSeller: Bool { lot.map { $0.sellerId == me } ?? false }
    var isLeading: Bool { lot?.currentBidderId != nil && lot?.currentBidderId == me }
    var isWinner: Bool { lot?.status == .ended && lot?.winnerId == me }
    var lastBidSeq: Int64 { seqGate.lastSeq }

    /// 快捷出价阶梯：最低加价 ×1 / ×2 / ×5
    var quickBids: [Money] {
        guard let lot else { return [] }
        let base = lot.minNextBid
        let inc = lot.bidIncrement
        return [base, base + inc, base + inc * 4]
    }

    /// Price-card / sheet CTA label for proxy entry (design §5.6 / §9).
    var proxyEntryTitle: String {
        guard let proxyBid else { return ProxyBidCopy.entrySet }
        if proxyBid.isExceeded { return ProxyBidCopy.entryRaise }
        if proxyBid.status.canRaise { return ProxyBidCopy.entryManage }
        return ProxyBidCopy.entrySet
    }

    var hasManageableProxy: Bool {
        guard let proxyBid else { return false }
        return proxyBid.status.canRaise || proxyBid.status.canCancel
    }

    var isPreview: Bool { lotId == 0 }

    func load() async {
        guard !isPreview else { return }
        if lot == nil { state = .loading }
        do {
            let l = try await API.lot(lotId)
            applySnapshot(l)
            state = .loaded
            if feed.isEmpty, let bids = l.recentBids {
                feed = bids.map { FeedItem(id: "bid-\($0.id)", kind: .bid(amount: $0.amount, name: $0.bidderName, avatar: $0.bidderAvatar, mine: $0.bidderId == me), at: $0.createdAt) }
            }
            await loadProxyBid()
        } catch {
            if lot == nil { state = .failed((error as? APIError)?.message ?? "加载失败") }
        }
    }

    /// Load confidential own proxy (404 → none). Skips when logged out / seller.
    func loadProxyBid() async {
        guard !isPreview, !isSeller, SessionStore.shared.isLoggedIn else {
            proxyBid = nil
            return
        }
        proxyLoading = true
        defer { proxyLoading = false }
        do {
            proxyBid = try await API.proxyBid(lotId)
            proxyFeatureDisabled = false
        } catch let e as APIError where e.code == ProxyBidErrorCode.featureDisabled.rawValue {
            proxyFeatureDisabled = true
            proxyBid = nil
        } catch {
            // Keep prior state on weak network (design §9).
        }
    }

    func subscribe() {
        guard !subscribed, !isPreview else { return }
        subscribed = true
        AuctionLiveStore.shared.focusedLotId = lotId
        WebSocketClient.shared.subscribeLot(lotId)
    }

    func unsubscribe() {
        guard subscribed else { return }
        subscribed = false
        if AuctionLiveStore.shared.focusedLotId == lotId {
            AuctionLiveStore.shared.focusedLotId = nil
        }
        WebSocketClient.shared.unsubscribeLot(lotId)
    }

    /// Re-subscribe + GET snapshot to align `seq` after WS drop (design §5.5).
    func resyncAfterReconnect() async {
        guard !isPreview else { return }
        WebSocketClient.shared.subscribeLot(lotId)
        await load()
    }

    func placeBid(_ amount: Money) async -> Bool {
        guard !bidding else { return false }
        if !SessionStore.shared.accessFlags.canBid {
            ToastCenter.shared.show(banBidToastMessage, .info)
            return false
        }
        if let lot, !BidAmountGrid.isAcceptable(
            amountFen: amount,
            startPriceFen: lot.startPrice,
            currentPriceFen: lot.currentPrice,
            bidCount: lot.bidCount,
            sellerBidIncrementFen: lot.bidIncrement
        ) {
            ToastCenter.shared.show("请按加价幅度出价（最低 \(lot.minNextBid.display)）", .error)
            return false
        }

        bidding = true
        defer { bidding = false }

        let key = idempotency.keyForAttempt(amountFen: amount) {
            APIClient.shared.idempotencyKey()
        }

        if SessionStore.shared.accessFlags.showsDepositEntry, let lot, lot.depositAmount > 0 {
            let info = try? await API.lotDeposit(lotId)
            if info?.isFrozen != true {
                needsDeposit = true
                let amt = (info?.sheetAmount ?? 0) > 0 ? (info?.sheetAmount ?? lot.depositAmount) : lot.depositAmount
                ToastCenter.shared.show("\(DepositCopy.needFreezeFirst) \(amt.display)", .info)
                return false
            }
        }
        return await submitBid(amount: amount, key: key)
    }

    /// After deposit freeze succeeds, re-submit with the same Idempotency-Key.
    func retryPendingBidAfterDeposit() async {
        if let amount = proxyIdempotency.amountFen, let key = proxyIdempotency.key {
            proxySaving = true
            defer { proxySaving = false }
            _ = await submitProxyBid(maxAmount: amount, key: key)
            return
        }
        guard let amount = idempotency.amountFen, let key = idempotency.key else { return }
        bidding = true
        defer { bidding = false }
        _ = await submitBid(amount: amount, key: key)
    }

    // MARK: Proxy bid (DES-v1.3-03-04)

    /// Set or raise confidential max. Returns true on success.
    func putProxyBid(_ maxAmount: Money) async -> Bool {
        guard !proxySaving else { return false }
        if proxyFeatureDisabled {
            ToastCenter.shared.show(ProxyBidErrorCode.featureDisabled.fallbackMessage, .info)
            return false
        }
        if !SessionStore.shared.accessFlags.canBid {
            ToastCenter.shared.show(banBidToastMessage, .info)
            return false
        }
        guard let lot else { return false }

        switch ProxyBidLocalValidation.validate(
            typedMaxFen: maxAmount,
            existing: proxyBid,
            startPriceFen: lot.startPrice,
            currentPriceFen: lot.currentPrice,
            bidCount: lot.bidCount,
            sellerBidIncrementFen: lot.bidIncrement
        ) {
        case .tooLow:
            ToastCenter.shared.show(ProxyBidErrorCode.proxyMaxTooLow.fallbackMessage, .error)
            return false
        case .cannotDecrease:
            ToastCenter.shared.show(ProxyBidErrorCode.proxyCannotDecrease.fallbackMessage, .error)
            return false
        case .ok(let aligned):
            proxySaving = true
            defer { proxySaving = false }
            let key = proxyIdempotency.keyForAttempt(amountFen: aligned) {
                APIClient.shared.idempotencyKey()
            }
            if SessionStore.shared.accessFlags.showsDepositEntry, lot.depositAmount > 0 {
                let info = try? await API.lotDeposit(lotId)
                if info?.isFrozen != true {
                    needsDeposit = true
                    let amt = (info?.sheetAmount ?? 0) > 0 ? (info?.sheetAmount ?? lot.depositAmount) : lot.depositAmount
                    ToastCenter.shared.show("\(DepositCopy.needFreezeFirst) \(amt.display)", .info)
                    return false
                }
            }
            return await submitProxyBid(maxAmount: aligned, key: key)
        }
    }

    func cancelProxyBid() async -> Bool {
        guard !proxySaving, let current = proxyBid, current.status.canCancel else { return false }
        proxySaving = true
        defer { proxySaving = false }
        do {
            try await API.deleteProxyBid(lotId, version: current.version)
            proxyBid = nil
            proxyIdempotency.clear()
            Haptics.success()
            ToastCenter.shared.show("已取消代理出价", .success)
            return true
        } catch {
            return await handleProxyError(error, maxAmount: nil, key: nil, isCancel: true)
        }
    }

    private func submitProxyBid(maxAmount: Money, key: String) async -> Bool {
        do {
            let state = try await API.putProxyBid(
                lotId,
                maxAmount: maxAmount,
                version: proxyBid?.version,
                idempotencyKey: key
            )
            applyProxyResponse(state)
            proxyIdempotency.clear()
            Haptics.success()
            if state.leading == true {
                ToastCenter.shared.show(ProxyBidCopy.leadingActiveHint, .success)
            } else {
                ToastCenter.shared.show("代理出价已设置（\(ProxyBidCopy.alignedHint(maxFen: state.displayMaxFen))）", .success)
            }
            return true
        } catch {
            return await handleProxyError(error, maxAmount: maxAmount, key: key, isCancel: false)
        }
    }

    private func applyProxyResponse(_ state: ProxyBidState) {
        proxyBid = state
        proxyFeatureDisabled = false
        guard var l = lot else { return }
        if let price = state.currentPrice { l.currentPrice = price; l.displayPrice = price }
        if let min = state.minNextBid { l.minNextBid = min }
        if let end = state.endAt { l.endAt = end }
        if let ver = state.endAtVersion { l.endAtVersion = ver }
        if state.leading == true, let me {
            l.currentBidderId = me
        }
        lot = l
    }

    @discardableResult
    private func handleProxyError(
        _ error: Error,
        maxAmount: Money?,
        key: String?,
        isCancel: Bool
    ) async -> Bool {
        guard let e = error as? APIError else {
            ToastCenter.shared.show("以服务器为准，可下拉刷新", .info)
            return false
        }
        let code = ProxyBidErrorCode(rawValue: e.code)
        switch code {
        case .bidQueueBusy, .idempotencyInProgress:
            if let maxAmount, let key, proxyIdempotency.consumeQueueRetry() {
                ToastCenter.shared.show("竞拍火爆，已为你重试", .info)
                try? await Task.sleep(for: .milliseconds(400))
                return await submitProxyBid(maxAmount: maxAmount, key: key)
            }
            ToastCenter.shared.show(e.message.isEmpty ? code?.fallbackMessage ?? e.message : e.message, .info)
        case .depositNotFrozen:
            needsDeposit = true
            ToastCenter.shared.show(e.message.isEmpty ? (code?.fallbackMessage ?? e.message) : e.message, .info)
        case .realNameRequired:
            needsRealName = true
            ToastCenter.shared.show(e.trustMessage, .info)
        case .proxyVersionConflict:
            ToastCenter.shared.show(code?.fallbackMessage ?? e.message, .info)
            proxyIdempotency.clear()
            await loadProxyBid()
            await load()
        case .proxyCannotDecrease, .proxyMaxTooLow, .proxyCrowd:
            ToastCenter.shared.show(e.message.isEmpty ? (code?.fallbackMessage ?? e.message) : e.message, .error)
            proxyIdempotency.clear()
            if code?.shouldReloadProxy == true { await loadProxyBid() }
        case .featureDisabled:
            proxyFeatureDisabled = true
            ToastCenter.shared.show(code?.fallbackMessage ?? e.message, .info)
            proxyIdempotency.clear()
        case .ownLot:
            ToastCenter.shared.show(code?.fallbackMessage ?? e.message, .error)
            proxyIdempotency.clear()
        case .relatedAccountForbidden, .blockedBySeller:
            ToastCenter.shared.show(RiskCopy.bidNotAllowed, .error)
            proxyIdempotency.clear()
        case .auctionNotLive:
            ToastCenter.shared.show(code?.fallbackMessage ?? e.message, .error)
            proxyIdempotency.clear()
            await load()
        case .creditTooLow:
            presentCreditBlock(code: e.code, action: "出价")
            proxyIdempotency.clear()
        case .biddingBanned, .accountRestricted:
            ToastCenter.shared.show(e.restrictionMessage, .info)
            proxyIdempotency.clear()
        case .idempotencyConflict, .missingIdempotencyKey, .invalidIdempotencyKey:
            proxyIdempotency.clear()
            ToastCenter.shared.show(e.message.isEmpty ? (code?.fallbackMessage ?? e.message) : e.message, .info)
        case .rateLimited:
            ToastCenter.shared.show(code?.fallbackMessage ?? e.message, .info)
        case .none:
            if ReviewCreditErrorCode.normalize(e.code)?.isCreditBlock == true {
                presentCreditBlock(code: e.code, action: "出价")
                proxyIdempotency.clear()
            } else if e.code == RestrictionErrorCode.accountFrozen.rawValue {
                SessionStore.shared.handleAccountFrozen(message: e.restrictionMessage)
                proxyIdempotency.clear()
            } else if e.code == RestrictionErrorCode.bidForbidden.rawValue {
                ToastCenter.shared.show(e.restrictionMessage, .info)
                proxyIdempotency.clear()
            } else {
                ToastCenter.shared.error(e)
                if isCancel { await loadProxyBid() }
                proxyIdempotency.clear()
            }
        }
        return false
    }

    private func presentCreditBlock(code: String, action: String) {
        let score = SessionStore.shared.bootstrap?.me?.creditScore ?? SessionStore.shared.user?.creditScore
        if ReviewCreditLogic.creditBlock(fromCode: code, score: score, action: action) != nil {
            AppRouterProxy.presentCreditBlock(code: code, score: score, action: action)
        } else {
            ToastCenter.shared.show(ReviewCreditCopy.errCreditGeneric, .info)
        }
    }

    private func submitBid(amount: Money, key: String) async -> Bool {
        do {
            let r = try await API.bid(lotId, amount: amount, idempotencyKey: key)
            var l = r.lot
            if let seq = r.effectiveSeq {
                seqGate.align(toSnapshotSeq: seq)
                AuctionLiveStore.shared.alignSeq(lotId: lotId, seq: seq)
                l.seq = seq
            }
            if let min = r.minNextBid { l.minNextBid = min }
            if let end = r.endAt { l.endAt = end }
            lot = l
            idempotency.clear()
            Haptics.success()
            if r.extended == true {
                // Full-screen extend toast; WS may also deliver auction_extended — deduped by version.
                presentExtendToast(endAt: l.endAt, version: l.endAtVersion ?? lastExtendToastVersion + 1)
            } else {
                ToastCenter.shared.show("出价成功，当前领先", .success)
            }
            return true
        } catch {
            return await handleBidError(error, amount: amount, key: key)
        }
    }

    @discardableResult
    private func handleBidError(_ error: Error, amount: Money, key: String) async -> Bool {
        guard let e = error as? APIError else {
            // Weak network: keep sticky key; do not mint a new one (design §9).
            ToastCenter.shared.show("以服务器为准，可下拉刷新", .info)
            return false
        }
        let code = BidErrorCode(rawValue: e.code)
        switch code {
        case .bidQueueBusy, .idempotencyInProgress:
            if idempotency.consumeQueueRetry() {
                ToastCenter.shared.show("竞拍火爆，已为你重试", .info)
                try? await Task.sleep(for: .milliseconds(400))
                return await submitBid(amount: amount, key: key)
            }
            ToastCenter.shared.show(e.message.isEmpty ? "竞拍火爆，请稍后再试" : e.message, .info)
        case .depositNotFrozen:
            needsDeposit = true
            ToastCenter.shared.show(
                e.message.isEmpty ? TrustErrorCode.depositNotFrozen.fallbackMessage : e.message,
                .info
            )
        case .realNameRequired:
            needsRealName = true
            ToastCenter.shared.show(e.trustMessage, .info)
        case .alreadyLeading:
            ToastCenter.shared.show("您已是当前最高出价", .info)
            idempotency.clear()
        case .ownLot:
            ToastCenter.shared.show("不能对自己的拍品出价", .error)
            idempotency.clear()
        case .relatedAccountForbidden, .blockedBySeller:
            ToastCenter.shared.show(RiskCopy.bidNotAllowed, .error)
            idempotency.clear()
        case .auctionNotLive:
            ToastCenter.shared.show("拍卖未在进行中", .error)
            idempotency.clear()
            await load()
        case .bidAmountInvalid, .bidTooLow, .bidJumpTooLarge, .bidAmountAbnormal:
            ToastCenter.shared.show(e.message.isEmpty ? "出价金额不符合加价规则" : e.message, .error)
            idempotency.clear()
            await load()
        case .creditTooLow:
            presentCreditBlock(code: e.code, action: "出价")
            idempotency.clear()
        case .biddingBanned, .accountRestricted:
            ToastCenter.shared.show(e.restrictionMessage, .info)
            idempotency.clear()
        case .idempotencyConflict:
            ToastCenter.shared.show("请重新出价", .info)
            idempotency.clear()
        case .missingIdempotencyKey, .invalidIdempotencyKey:
            idempotency.clear()
            ToastCenter.shared.error(e)
        case .rateLimited:
            ToastCenter.shared.show("操作过于频繁，请稍后再试", .info)
        case .none:
            if ReviewCreditErrorCode.normalize(e.code)?.isCreditBlock == true {
                presentCreditBlock(code: e.code, action: "出价")
                idempotency.clear()
            } else if e.code == RestrictionErrorCode.accountFrozen.rawValue {
                SessionStore.shared.handleAccountFrozen(message: e.restrictionMessage)
                idempotency.clear()
            } else if e.code == RestrictionErrorCode.bidForbidden.rawValue {
                ToastCenter.shared.show(e.restrictionMessage, .info)
                idempotency.clear()
            } else if let risk = RiskErrorCode.normalize(e.code), risk.isBidDenied {
                ToastCenter.shared.show(RiskCopy.bidNotAllowed, .error)
                idempotency.clear()
            } else if e.code == "conflict", e.message.contains("押金") {
                if SessionStore.shared.accessFlags.showsDepositEntry { needsDeposit = true }
                ToastCenter.shared.show(e.message, .info)
            } else {
                ToastCenter.shared.error(e)
                idempotency.clear()
            }
        }
        return false
    }

    var banBidToastMessage: String {
        let flags = SessionStore.shared.accessFlags
        if let reason = flags.banBidPublicReason, !reason.isEmpty { return reason }
        if let end = flags.banBidEndsAt {
            return "账号已被限制竞拍，预计 \(end.shortText) 解除"
        }
        return RestrictionErrorCode.bidForbidden.fallbackMessage
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

    /// Subscribe single-lot closing remind (AUC-13). Idempotent; also joins follow set on server.
    func subscribeClosingRemind() async {
        guard !reminding, !closingRemindSubscribed else { return }
        reminding = true
        defer { reminding = false }
        do {
            let r = try await API.remindLot(lotId)
            closingRemindSubscribed = r.isSubscribed
            if var l = lot, !l.isFollowing {
                l.isFollowing = true
                l.followCount += 1
                lot = l
            }
            Haptics.success()
            ToastCenter.shared.show(AntiSnipeCopy.closingRemindSuccess, .success)
        } catch let e as APIError where e.code == "unauthorized" || e.code == "unauthenticated" {
            ToastCenter.shared.show("请先登录后再订阅结拍提醒", .info)
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    func cancel() async {
        do {
            lot = try await API.cancelLot(lotId)
            ToastCenter.shared.show("已撤拍", .success)
        } catch let e as APIError where e.code == AuctionSettlementErrorCode.lotHasBids.rawValue {
            ToastCenter.shared.show(AuctionSettlementErrorCode.lotHasBids.fallbackMessage, .info)
            await load()
        } catch { ToastCenter.shared.error(error) }
    }

    // MARK: Snapshot / Events

    private func applySnapshot(_ l: Lot) {
        seqGate.align(toSnapshotSeq: l.seq)
        AuctionLiveStore.shared.alignSeq(lotId: lotId, seq: l.seq)
        lot = l
    }

    private func handle(_ ev: WSEvent) {
        let seq = ev.int64("seq")
        // Ignore stale / duplicate room events (seq <= local).
        if let seq, !seqGate.shouldApply(seq) { return }

        switch ev.type {
        case "bid_placed":
            _ = seqGate.note(seq)
            let bidder = ev.int64("bidder_id")
            let mine = bidder == me
            feed.insert(FeedItem(id: "bid-\(ev.int64("bid_id") ?? Int64(Date().timeIntervalSince1970 * 1000))",
                                 kind: .bid(amount: ev.int64("amount") ?? 0, name: ev.string("bidder_nickname") ?? "", avatar: ev.string("bidder_avatar") ?? "", mine: mine),
                                 at: ev.date("at") ?? Date()), at: 0)
            if var l = lot {
                if let seq { l.seq = seq }
                if let ver = ev.int64("end_at_version").map(Int.init) { l.endAtVersion = ver }
                lot = l
            }
            bump()
            if !mine, lot?.myBid.hasBid == true { prompt = .outbid(minNext: ev.int64("min_next_bid") ?? lot?.minNextBid ?? 0) }
            // Proxy may have auto-followed; refresh confidential max / leading.
            if proxyBid?.status.canRaise == true {
                Task { await loadProxyBid() }
            }
        case "proxy_exceeded", "proxy_bid_exceeded":
            // N-32: max surpassed; payload has current / min_next only (design §5.3).
            if var p = proxyBid, p.status == .active {
                p = ProxyBidState(
                    maxAmount: p.maxAmount,
                    maxAmountAligned: p.maxAmountAligned,
                    status: .exceeded,
                    leading: false,
                    currentPrice: ev.int64("current_price") ?? p.currentPrice,
                    minNextBid: ev.int64("min_next_bid") ?? p.minNextBid,
                    endAt: p.endAt,
                    endAtVersion: p.endAtVersion,
                    version: p.version,
                    createdAt: p.createdAt
                )
                proxyBid = p
            }
            prompt = .proxyExceeded(minNext: ev.int64("min_next_bid") ?? lot?.minNextBid ?? 0)
            Task { await loadProxyBid() }
        case "auction_extended":
            if let d = ev.date("end_at") {
                feed.insert(FeedItem(id: "ext-\(ev.at.timeIntervalSince1970)", kind: .extended, at: ev.at), at: 0)
                if var l = lot {
                    l.endAt = d
                    if let ver = ev.int64("end_at_version").map(Int.init) { l.endAtVersion = ver }
                    if let ext = ev.int64("extension_count").map(Int.init) { l.extensionCount = ext }
                    lot = l
                    presentExtendToast(endAt: d, version: l.endAtVersion ?? 0)
                } else {
                    presentExtendToast(endAt: d, version: ev.int64("end_at_version").map(Int.init) ?? 0)
                }
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

    /// Design §9: full-screen toast「已延时 2 分钟」, synced with WS; dedupe by end_at_version.
    private func presentExtendToast(endAt: Date, version: Int) {
        let ver = max(version, 1)
        if ver > 0, ver <= lastExtendToastVersion { return }
        lastExtendToastVersion = ver
        extendToastTask?.cancel()
        extendToast = ExtendToast(endAt: endAt, endAtVersion: ver)
        Haptics.success()
        extendToastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.extendToast = nil }
        }
    }
}
