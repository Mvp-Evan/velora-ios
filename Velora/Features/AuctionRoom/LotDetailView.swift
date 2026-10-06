import SwiftUI

struct LotDetailView: View {
    let lotId: Int64
    var preload: Lot? = nil

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LotDetailModel
    @State private var imageIndex = 0
    @State private var showBidSheet = false
    @State private var showAllBids = false
    @State private var showCancelConfirm = false
    @State private var showGallery = false
    @State private var chatConv: Conversation?
    @State private var orderToOpen: Int64?

    init(lotId: Int64, preload: Lot? = nil) {
        self.lotId = lotId
        self.preload = preload
        _model = StateObject(wrappedValue: LotDetailModel(lotId: lotId, preload: preload))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.vBackground.ignoresSafeArea()
            switch model.state {
            case .idle, .loading: VLoadingView()
            case .failed(let m): VErrorView(message: m) { Task { await model.load() } }
            case .loaded:
                if let lot = model.lot { content(lot) }
            }
            if let lot = model.lot { bottomBar(lot) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await model.load(); model.subscribe() }
        .onAppear { router.hideTabBar = true }
        .onDisappear { router.hideTabBar = false; model.unsubscribe() }
        .sheet(isPresented: $showBidSheet) {
            if let lot = model.lot { BidSheet(lot: lot, model: model).presentationDetents([.height(420)]).presentationDragIndicator(.visible) }
        }
        .sheet(isPresented: $showAllBids) {
            if let lot = model.lot { BidHistorySheet(lot: lot).presentationDetents([.medium, .large]) }
        }
        .sheet(item: $chatConv) { conv in NavigationStack { ChatView(conversation: conv, presentedAsSheet: true) } }
        .sheet(item: Binding(get: { orderToOpen.map(IDBox.init) }, set: { orderToOpen = $0?.id })) { box in
            NavigationStack { OrderDetailView(orderId: box.id) }
        }
        .fullScreenCover(isPresented: $showGallery) {
            if let lot = model.lot { GalleryView(images: lot.images, index: $imageIndex) }
        }
        .overlay { promptOverlay }
        .confirmationDialog("确认撤拍？", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("撤拍", role: .destructive) { Task { await model.cancel() } }
        } message: { Text("撤拍后拍品将不再展示，已有出价的拍品无法撤拍。") }
    }

    // MARK: Content

    private func content(_ lot: Lot) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                hero(lot)
                VStack(spacing: VSpace.m) {
                    priceCard(lot)
                    if lot.isLive || !model.feed.isEmpty { liveFeed(lot) }
                    titleCard(lot)
                    attributesCard(lot)
                    sellerCard(lot)
                    rulesCard(lot)
                }
                .padding(.horizontal, VSpace.l)
                .padding(.top, VSpace.m)
                .padding(.bottom, 120)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) { navBar(lot) }
        .refreshable { await model.load() }
    }

    private func navBar(_ lot: Lot) -> some View {
        HStack {
            VIconButton(system: "chevron.left", tint: .white, background: .black.opacity(0.35)) { dismiss() }
            Spacer()
            ShareLink(item: "Velora 拍品：\(lot.title) 当前 \(lot.displayPrice.display)") {
                Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(.black.opacity(0.35), in: Circle())
            }
        }
        .padding(.horizontal, VSpace.m)
        .padding(.top, 50)
    }

    private func hero(_ lot: Lot) -> some View {
        ZStack(alignment: .bottomLeading) {
            VImageCarousel(images: lot.images.isEmpty ? [lot.cover] : lot.images, index: $imageIndex, height: 400) { showGallery = true }
            VGradient.imageScrim.frame(height: 160).frame(maxHeight: .infinity, alignment: .bottom).allowsHitTesting(false)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    VStatusBadge(status: lot.status)
                    if lot.isLive || lot.isUpcoming {
                        VCountdown(endAt: lot.isUpcoming ? lot.startAt : lot.endAt, status: lot.status, style: .large)
                    } else {
                        Text(lot.status == .ended ? "已于 \(lot.endAt.shortText) 成交" : "已结束").font(.vCaption).foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                HStack(spacing: 12) {
                    Label("\(lot.viewCount.compact)", systemImage: "eye").font(.vMicro)
                    Label("\(lot.followCount)", systemImage: "heart").font(.vMicro)
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            .padding(VSpace.l)
            .allowsHitTesting(false)
        }
    }

    private func priceCard(_ lot: Lot) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(priceTitle(lot)).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        VPriceText(amount: lot.displayPrice, size: 34)
                            .scaleEffect(model.priceBump ? 1.06 : 1, anchor: .leading)
                            .animation(.spring(duration: 0.35), value: model.priceBump)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("起拍价 \(lot.startPrice.display)").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        Text("加价幅度 \(lot.bidIncrement.display)").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        if lot.hasReserve {
                            Text(lot.reserveMet ? "已达保留价" : "未达保留价").font(.vMicro)
                                .foregroundStyle(lot.reserveMet ? Color.vGreen : Color.vGold)
                        }
                    }
                }

                HStack(spacing: 8) {
                    if let b = lot.currentBidder {
                        VAvatar(url: b.avatar, size: 22)
                        Text(model.isLeading ? "您正在领先" : "\(b.nickname) 领先").font(.vCaptionMedium)
                            .foregroundStyle(model.isLeading ? Color.vGold : Color.vText)
                    } else {
                        Image(systemName: "hand.raised.fill").foregroundStyle(Color.vTextTertiary).font(.vCaption)
                        Text(lot.isUpcoming ? "预展中，开拍后可出价" : "暂无出价，快来抢沙发").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    }
                    Spacer()
                    Button { showAllBids = true } label: {
                        HStack(spacing: 2) { Text("\(lot.bidCount) 次出价"); Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)) }
                            .font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    }
                }

                if lot.myBid.hasBid, lot.isLive {
                    HStack(spacing: 6) {
                        Image(systemName: lot.myBid.leading ? "crown.fill" : "exclamationmark.triangle.fill")
                        Text(lot.myBid.leading ? "您的出价 \(lot.myBid.maxAmount.display) 领先中" : "您的出价已被超越，最低需出 \(lot.minNextBid.display)")
                        Spacer()
                    }
                    .font(.vCaptionMedium)
                    .foregroundStyle(lot.myBid.leading ? Color.vGold : Color.vPrimary)
                    .padding(10)
                    .background((lot.myBid.leading ? Color.vGold : Color.vPrimary).opacity(0.1), in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                }

                if lot.isLive, !model.isSeller {
                    if model.isLeading {
                        Text("您已是当前最高出价，被超越后可再次出价").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    } else {
                        VPrimaryButton(title: "立即出价 \(lot.minNextBid.display)", icon: "hammer.fill", loading: model.bidding) {
                            guard requireLogin() else { return }
                            showBidSheet = true
                        }
                    }
                } else if lot.isUpcoming, !model.isSeller {
                    Text("预展中 · \(lot.startAt.shortText) 开拍后即可出价，可先点底部「开拍提醒」").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                } else if model.isSeller, lot.isLive || lot.isUpcoming {
                    Text("这是你发布的拍品，卖家不能对自己的拍品出价").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }

                if model.isWinner, let oid = lot.orderId {
                    Button { orderToOpen = oid } label: {
                        HStack {
                            Image(systemName: "trophy.fill")
                            Text("恭喜拍中！前往付款")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.vBodyMedium).foregroundStyle(.white).padding(12)
                        .background(VGradient.gold, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                    }
                }
            }
        }
    }

    private func priceTitle(_ lot: Lot) -> String {
        switch lot.status {
        case .live: return lot.bidCount > 0 ? "当前价" : "起拍价"
        case .scheduled: return "起拍价"
        case .ended: return "成交价"
        default: return "最终价"
        }
    }

    private func liveFeed(_ lot: Lot) -> some View {
        VCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 5) {
                        Circle().fill(Color.vPrimary).frame(width: 6, height: 6).modifier(PulseModifier())
                        Text("实时出价").font(.vHeadline)
                    }
                    Spacer()
                    Text(WebSocketClient.shared.connected ? "已连接" : "连接中…").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                }
                .padding(VSpace.l)
                if model.feed.isEmpty {
                    Text("暂无出价记录").font(.vCaption).foregroundStyle(Color.vTextTertiary).padding(.horizontal, VSpace.l).padding(.bottom, VSpace.l)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.feed.prefix(6).enumerated()), id: \.element.id) { i, item in
                            FeedRow(item: item, isTop: i == 0)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            if i < min(model.feed.count, 6) - 1 { VDivider() }
                        }
                    }
                    .animation(.spring(duration: 0.35), value: model.feed.map(\.id))
                    .padding(.bottom, VSpace.s)
                }
            }
        }
    }

    private func titleCard(_ lot: Lot) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text(lot.title).font(.vTitle(19)).foregroundStyle(Color.vText)
                HStack(spacing: 6) { ForEach(lot.tags, id: \.self) { VTagChip(text: $0, tint: .vPrimary, background: .vPrimarySoft) } }
                if !lot.description.isEmpty {
                    Text(lot.description).font(.vBody).foregroundStyle(Color.vTextSecondary).lineSpacing(5)
                }
            }
        }
    }

    private func attributesCard(_ lot: Lot) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text("拍品参数").font(.vHeadline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    attr("分类", lot.category); attr("品牌", lot.brand)
                    attr("比例", lot.scale); attr("系列", lot.series)
                    attr("成色", lot.condition); attr("包装", lot.boxStatus)
                    attr("所在地", lot.location); attr("开拍时间", lot.startAt.shortText)
                }
            }
        }
    }

    private func attr(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.vMicro).foregroundStyle(Color.vTextTertiary)
            Text(v.isEmpty ? "—" : v).font(.vBodyMedium).foregroundStyle(Color.vText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }

    private func sellerCard(_ lot: Lot) -> some View {
        VCard {
            HStack(spacing: 12) {
                VAvatar(url: lot.seller.avatar, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(lot.seller.nickname).font(.vHeadline)
                        VTagChip(text: "信用 \(lot.seller.creditScore)", tint: .vGreen, background: Color.vGreen.opacity(0.1))
                    }
                    Text("已售出 \(lot.seller.soldCount) 件 · 在拍 \(lot.seller.lotCount) 件" + (lot.seller.location.map { " · \($0)" } ?? ""))
                        .font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
                Spacer()
                if !model.isSeller {
                    Button { openChat() } label: {
                        Text("咨询").font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .overlay(Capsule().stroke(Color.vPrimary, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func rulesCard(_ lot: Lot) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("拍卖规则").font(.vHeadline)
                rule("timer", "结束前 \(lot.antiSnipeSeconds / 60) 分钟内出价，自动延时 \(lot.antiSnipeSeconds / 60) 分钟（已延时 \(lot.extensionCount) 次）")
                rule("checkmark.shield", "拍中后 24 小时内完成付款，逾期订单自动取消并影响信用")
                rule("percent", "买家无需支付佣金；卖家按成交价支付平台服务费")
                rule("shippingbox", "卖家在买家付款后 48 小时内发货，买家确认收货后货款入账")
            }
        }
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.vPrimary).frame(width: 16).padding(.top, 2)
            Text(text).font(.vCaption).foregroundStyle(Color.vTextSecondary)
        }
    }

    // MARK: Bottom bar

    private func bottomBar(_ lot: Lot) -> some View {
        HStack(spacing: 10) {
            barAction(icon: lot.isFollowing ? "heart.fill" : "heart", title: lot.isFollowing ? "已关注" : (lot.isUpcoming ? "开拍提醒" : "关注"),
                      tint: lot.isFollowing ? .vPrimary : .vTextSecondary) {
                guard requireLogin() else { return }
                Task { await model.toggleFollow() }
            }
            if !model.isSeller {
                barAction(icon: "bubble.left", title: "咨询", tint: .vTextSecondary) { openChat() }
            }

            if model.isSeller {
                if lot.isLive || lot.isUpcoming {
                    VPrimaryButton(title: lot.bidCount > 0 ? "已有出价，不可撤拍" : "撤拍", style: .outline, disabled: lot.bidCount > 0) { showCancelConfirm = true }
                } else if lot.status == .ended, let oid = lot.orderId {
                    VPrimaryButton(title: "查看订单", style: .dark) { orderToOpen = oid }
                } else {
                    VPrimaryButton(title: "已结束", disabled: true) {}
                }
            } else if lot.isLive {
                HStack(spacing: 8) {
                    ForEach(model.quickBids.prefix(2), id: \.self) { amt in
                        Button {
                            guard requireLogin() else { return }
                            Task { await model.placeBid(amt) }
                        } label: {
                            VStack(spacing: 1) {
                                Text(amt == lot.minNextBid ? "最低出价" : "加价").font(.vMicro).opacity(0.85)
                                Text(amt.display).font(.vMono(14, weight: .bold))
                            }
                            .foregroundStyle(amt == lot.minNextBid ? Color.vPrimary : .white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(amt == lot.minNextBid ? Color.vPrimarySoft : Color.vCarbon, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                        }
                        .disabled(model.bidding || model.isLeading)
                        .opacity(model.isLeading ? 0.45 : 1)
                    }
                    Button {
                        guard requireLogin() else { return }
                        showBidSheet = true
                    } label: {
                        VStack(spacing: 1) {
                            Text(model.isLeading ? "领先中" : "自定义").font(.vMicro).opacity(0.85)
                            Text(model.isLeading ? "已领先" : "出价").font(.vMono(14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(VGradient.brand, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                    }
                    .disabled(model.bidding || model.isLeading)
                    .opacity(model.isLeading ? 0.45 : 1)
                }
            } else if lot.isUpcoming {
                VPrimaryButton(title: "开拍后可出价 · \(lot.startAt.shortText)", style: .dark, disabled: true) {}
            } else if model.isWinner, let oid = lot.orderId {
                VPrimaryButton(title: "我已拍中 · 去付款", icon: "trophy.fill") { orderToOpen = oid }
            } else {
                VPrimaryButton(title: lot.status == .ended ? "已成交" : "已结束", style: .dark, disabled: true) {}
            }
        }
        .padding(.horizontal, VSpace.l)
        .padding(.top, VSpace.m)
        .padding(.bottom, VSpace.s)
        .background(Color.vSurface.ignoresSafeArea(edges: .bottom).overlay(alignment: .top) { Rectangle().fill(Color.vSeparator).frame(height: 0.5) })
    }

    private func barAction(icon: String, title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .medium))
                Text(title).font(.vMicro)
            }
            .foregroundStyle(tint)
            .frame(width: 48)
        }
    }

    private func requireLogin() -> Bool {
        if session.isLoggedIn { return true }
        router.showLogin = true
        return false
    }

    private func openChat() {
        guard requireLogin() else { return }
        Task {
            do { chatConv = try await API.openConversation(lotId: lotId) } catch { ToastCenter.shared.error(error) }
        }
    }

    // MARK: Prompt overlay

    @ViewBuilder private var promptOverlay: some View {
        if let p = model.prompt {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { model.prompt = nil }
                PromptCard(prompt: p, lot: model.lot) { action in
                    model.prompt = nil
                    switch action {
                    case .bid(let amt): Task { await model.placeBid(amt) }
                    case .custom: showBidSheet = true
                    case .order(let id): orderToOpen = id
                    case .none: break
                    }
                }
                .padding(.horizontal, VSpace.xl)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            .animation(.spring(duration: 0.35), value: model.prompt)
        }
    }
}

// MARK: - Feed row

struct FeedRow: View {
    let item: LotDetailModel.FeedItem
    var isTop: Bool
    var body: some View {
        HStack(spacing: 10) {
            switch item.kind {
            case .bid(let amount, let name, let avatar, let mine):
                VAvatar(url: avatar, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(mine ? "我" : name).font(.vCaptionMedium).foregroundStyle(Color.vText)
                        if isTop { Text("领先").font(.vMicro).foregroundStyle(Color.vGold).padding(.horizontal, 5).padding(.vertical, 1).background(Color.vGold.opacity(0.12), in: Capsule()) }
                    }
                    Text(item.at.relativeText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                }
                Spacer()
                Text(amount.display).font(.vMono(15, weight: .bold)).foregroundStyle(isTop ? Color.vPrimary : Color.vText)
            case .extended:
                systemRow("clock.arrow.circlepath", "触发防狙击，拍卖已延时", .vBlue)
            case .started:
                systemRow("flag.fill", "拍卖开始", .vGreen)
            case .ended(let sold):
                systemRow(sold ? "hammer.fill" : "xmark.circle", sold ? "一锤定音，拍卖结束" : "无人竞得，流拍", sold ? .vCarbon : .vTextTertiary)
            case .system(let s):
                systemRow("info.circle", s, .vTextSecondary)
            }
        }
        .padding(.horizontal, VSpace.l).padding(.vertical, 10)
    }
    private func systemRow(_ icon: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint).frame(width: 28)
            Text(text).font(.vCaption).foregroundStyle(Color.vTextSecondary)
            Spacer()
            Text(item.at.relativeText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
        }
    }
}

// MARK: - Prompt card

struct PromptCard: View {
    enum Action { case bid(Money), custom, order(Int64), none }
    let prompt: LotDetailModel.Prompt
    let lot: Lot?
    let act: (Action) -> Void

    var body: some View {
        VStack(spacing: VSpace.l) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 72, height: 72)
                Image(systemName: icon).font(.system(size: 30, weight: .semibold)).foregroundStyle(tint)
            }
            Text(title).font(.vTitle(20))
            Text(message).font(.vBody).foregroundStyle(Color.vTextSecondary).multilineTextAlignment(.center)
            buttons
        }
        .padding(VSpace.xl)
        .background(Color.vSurfaceElevated, in: RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous))
    }

    @ViewBuilder private var buttons: some View {
        switch prompt {
        case .outbid(let minNext):
            VStack(spacing: 10) {
                VPrimaryButton(title: "立即追加 \(minNext.display)") { act(.bid(minNext)) }
                HStack(spacing: 10) {
                    VPrimaryButton(title: "自定义出价", style: .soft) { act(.custom) }
                    VPrimaryButton(title: "再想想", style: .outline) { act(.none) }
                }
            }
        case .won(let oid):
            VPrimaryButton(title: "去付款", icon: "creditcard.fill") { act(.order(oid)) }
        case .extended:
            VPrimaryButton(title: "知道了", style: .dark) { act(.none) }
        default:
            VPrimaryButton(title: "知道了", style: .dark) { act(.none) }
        }
    }

    private var icon: String {
        switch prompt {
        case .outbid: return "arrow.up.right"; case .extended: return "clock.arrow.circlepath"; case .won: return "trophy.fill"
        case .lost: return "flag.slash"; case .unsold: return "xmark.circle"; case .cancelled: return "xmark"
        }
    }
    private var tint: Color {
        switch prompt { case .outbid: return .vPrimary; case .extended: return .vBlue; case .won: return .vGold; default: return .vTextSecondary }
    }
    private var title: String {
        switch prompt {
        case .outbid: return "您的出价被超越了"; case .extended: return "拍卖已延时"; case .won: return "恭喜您拍中！"
        case .lost: return "很遗憾，与它擦肩而过"; case .unsold: return "本次流拍"; case .cancelled: return "拍卖已取消"
        }
    }
    private var message: String {
        switch prompt {
        case .outbid(let m): return "有人出了更高的价格，最低需出 \(m.display) 才能重回领先。"
        case .extended(let d): return "结束前出现新出价，结束时间延长至 \(d.shortText)。"
        case .won: return "「\(lot?.title ?? "")」已归您所有，请在 24 小时内完成付款。"
        case .lost: return "拍品已被他人竞得，拍场里还有更多好车等你。"
        case .unsold: return "未达到成交条件，您可以调整起拍价后重新上拍。"
        case .cancelled: return "卖家已撤回该拍品。"
        }
    }
}

// MARK: - Bid sheet

struct BidSheet: View {
    let lot: Lot
    @ObservedObject var model: LotDetailModel
    @Environment(\.dismiss) private var dismiss
    @State private var yuan: String = ""
    @FocusState private var focused: Bool

    private var amount: Money? { Double(yuan).map { Money(($0 * 100).rounded()) } }
    private var valid: Bool { (amount ?? 0) >= lot.minNextBid }

    var body: some View {
        VStack(spacing: VSpace.l) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("出价").font(.vTitle(20))
                    Text("当前 \(lot.displayPrice.display) · 最低 \(lot.minNextBid.display) · 每手 \(lot.bidIncrement.display)").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
                Spacer()
                VCountdown(endAt: lot.endAt, status: lot.status)
            }

            HStack(spacing: 10) {
                Button { step(-1) } label: { stepper("minus") }
                HStack(spacing: 4) {
                    Text("¥").font(.vPrice(24)).foregroundStyle(Color.vPrimary)
                    TextField("", text: $yuan).keyboardType(.decimalPad).font(.vPrice(30)).foregroundStyle(Color.vPrimary)
                        .multilineTextAlignment(.center).focused($focused)
                }
                .frame(maxWidth: .infinity).frame(height: 60)
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                Button { step(1) } label: { stepper("plus") }
            }

            HStack(spacing: 8) {
                ForEach(model.quickBids, id: \.self) { q in
                    Button { yuan = fmt(q) } label: {
                        Text(q.display).font(.vMono(13)).foregroundStyle(amount == q ? .white : Color.vText)
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background(amount == q ? Color.vCarbon : Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                    }
                }
            }

            if let a = amount, !valid {
                Text("出价不得低于 \(lot.minNextBid.display)（您输入 \(a.display)）").font(.vCaption).foregroundStyle(Color.vPrimary)
            } else {
                Text("出价后不可撤回，拍中需在 24 小时内付款").font(.vCaption).foregroundStyle(Color.vTextTertiary)
            }

            VPrimaryButton(title: amount.map { "确认出价 \($0.display)" } ?? "确认出价", loading: model.bidding, disabled: !valid) {
                guard let a = amount else { return }
                Task { if await model.placeBid(a) { dismiss() } }
            }
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
        .onAppear { yuan = fmt(lot.minNextBid); focused = true }
    }

    private func stepper(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.vText)
            .frame(width: 48, height: 60).background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }
    private func step(_ dir: Int) {
        let cur = amount ?? lot.minNextBid
        yuan = fmt(max(lot.minNextBid, cur + Money(dir) * lot.bidIncrement))
        Haptics.light()
    }
    private func fmt(_ m: Money) -> String { m % 100 == 0 ? "\(m / 100)" : String(format: "%.2f", m.yuan) }
}

// MARK: - Bid history

struct BidHistorySheet: View {
    let lot: Lot
    @State private var bids: [Bid] = []
    @State private var loading = true
    var body: some View {
        NavigationStack {
            Group {
                if loading { VLoadingView() }
                else if bids.isEmpty { VEmptyState(icon: "hand.raised", title: "暂无出价") }
                else {
                    List(Array(bids.enumerated()), id: \.element.id) { i, b in
                        HStack(spacing: 10) {
                            VAvatar(url: b.bidderAvatar, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.bidderName).font(.vCaptionMedium)
                                Text(b.createdAt.fullText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                            }
                            Spacer()
                            Text(b.amount.display).font(.vMono(15, weight: .bold)).foregroundStyle(i == 0 ? Color.vPrimary : Color.vText)
                            if i == 0 { Text(lot.isFinished ? "成交" : "领先").font(.vMicro).foregroundStyle(Color.vGold) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("出价记录（\(lot.bidCount)）")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            bids = (try? await API.lotBids(lot.id))?.items ?? []
            loading = false
        }
    }
}

// MARK: - Gallery

struct GalleryView: View {
    let images: [String]
    @Binding var index: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, url in
                    RemoteImage(url, contentMode: .fit).tag(i)
                }
            }
            .tabViewStyle(.page)
            VIconButton(system: "xmark", tint: .white, background: .white.opacity(0.2)) { dismiss() }.padding()
        }
    }
}
