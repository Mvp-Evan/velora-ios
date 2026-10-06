import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @State private var wallet: Wallet?
    @State private var showEdit = false
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: VSpace.l) {
                    header
                    orderEntry
                    lotsEntry
                    assetsEntry
                    settingsEntry
                }
                .padding(.bottom, 100)
            }
            .background(Color.vBackground)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await refresh() }
            .task { await refresh() }
        }
        .sheet(isPresented: $showEdit) { EditProfileView() }
        .confirmationDialog("退出登录？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { session.logout(); router.tab = .home }
        }
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            VGradient.brand.frame(height: 230).ignoresSafeArea()
                .mask(LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: VSpace.l) {
                HStack {
                    Spacer()
                    Button { showEdit = true } label: {
                        Image(systemName: "gearshape").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).frame(width: 34, height: 34).background(.white.opacity(0.2), in: Circle())
                    }
                }
                if let u = session.user {
                    HStack(spacing: 14) {
                        VAvatar(url: u.avatar, size: 68).overlay(Circle().stroke(.white, lineWidth: 2))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(u.nickname).font(.vTitle(22)).foregroundStyle(.white)
                            HStack(spacing: 6) {
                                VTagChip(text: "信用 \(u.creditScore)", tint: .white, background: .white.opacity(0.2))
                                if let loc = u.location, !loc.isEmpty { VTagChip(text: loc, tint: .white, background: .white.opacity(0.2)) }
                                if let p = u.phoneMasked { Text(p).font(.vMicro).foregroundStyle(.white.opacity(0.8)) }
                            }
                            if let bio = u.bio, !bio.isEmpty { Text(bio).font(.vCaption).foregroundStyle(.white.opacity(0.85)).lineLimit(1) }
                        }
                        Spacer()
                    }
                    HStack(spacing: 0) {
                        NavigationLink { MyLotsView(kind: .mine) } label: { stat("\(u.lotCount)", "在拍/已拍") }
                        NavigationLink { OrderListView(role: "buyer") } label: { stat("\(u.wonCount)", "拍到") }
                        NavigationLink { OrderListView(role: "seller") } label: { stat("\(u.soldCount)", "卖出") }
                        NavigationLink { WalletView() } label: {
                            VStack(spacing: 3) {
                                Text(wallet?.availableBalance.display ?? "--").font(.vMono(17, weight: .heavy))
                                Text("钱包").font(.vMicro).opacity(0.85)
                            }
                            .foregroundStyle(.white).frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                } else {
                    Button { router.showLogin = true } label: {
                        HStack(spacing: 14) {
                            Circle().fill(.white.opacity(0.3)).frame(width: 68, height: 68).overlay(Image(systemName: "person.fill").font(.system(size: 28)).foregroundStyle(.white))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("点击登录").font(.vTitle(22)).foregroundStyle(.white)
                                Text("登录后参与竞拍、发布拍品").font(.vCaption).foregroundStyle(.white.opacity(0.85))
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, VSpace.l).padding(.top, VSpace.s)
        }
    }

    private func stat(_ v: String, _ k: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.vMono(17, weight: .heavy))
            Text(k).font(.vMicro).opacity(0.85)
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity)
    }

    private var orderEntry: some View {
        VCard {
            VStack(spacing: VSpace.m) {
                HStack {
                    Text("我拍到的").font(.vHeadline)
                    Spacer()
                    NavigationLink { OrderListView(role: "buyer") } label: { HStack(spacing: 2) { Text("全部订单"); Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)) }.font(.vCaption).foregroundStyle(Color.vTextSecondary) }
                }
                HStack {
                    entry("creditcard", "待付款", .vPrimary) { OrderListView(role: "buyer", initialStatus: "pending_payment") }
                    entry("shippingbox", "待发货", .vBlue) { OrderListView(role: "buyer", initialStatus: "paid") }
                    entry("truck.box", "待收货", .vGold) { OrderListView(role: "buyer", initialStatus: "shipped") }
                    entry("checkmark.seal", "已完成", .vGreen) { OrderListView(role: "buyer", initialStatus: "completed") }
                }
            }
        }
        .padding(.horizontal, VSpace.l)
    }

    private var lotsEntry: some View {
        VCard {
            VStack(spacing: VSpace.m) {
                HStack { Text("我的拍卖").font(.vHeadline); Spacer() }
                HStack {
                    entry("flag.checkered", "我的拍品", .vCarbon) { MyLotsView(kind: .mine) }
                    entry("hand.raised", "我的出价", .vPrimary) { MyLotsView(kind: .bids) }
                    entry("heart", "我的关注", .vPrimary) { MyLotsView(kind: .follows) }
                    entry("tag", "我卖出的", .vGreen) { OrderListView(role: "seller") }
                }
            }
        }
        .padding(.horizontal, VSpace.l)
    }

    private func entry<D: View>(_ icon: String, _ title: String, _ tint: Color, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium)).foregroundStyle(tint).frame(height: 24)
                Text(title).font(.vMicro).foregroundStyle(Color.vTextSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var assetsEntry: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                NavigationLink { WalletView() } label: { VNavRow(icon: "wallet.pass", iconTint: .vGold, title: "我的钱包", value: wallet.map { "在途 \($0.pendingBalance.display)" }) }
                VDivider(inset: 58)
                NavigationLink { TaxCenterView() } label: { VNavRow(icon: "doc.text.magnifyingglass", iconTint: .vBlue, title: "实名与税务", value: "报税预留") }
                VDivider(inset: 58)
                NavigationLink { AddressListView() } label: { VNavRow(icon: "mappin.and.ellipse", iconTint: .vGreen, title: "收货地址") }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, VSpace.l)
    }

    private var settingsEntry: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                NavigationLink { FeeRulesView() } label: { VNavRow(icon: "percent", iconTint: .vPrimary, title: "平台服务费说明") }
                VDivider(inset: 58)
                NavigationLink { LegalDocumentView(document: .appGuide, showDone: false) } label: { VNavRow(icon: "book", iconTint: .vBlue, title: "使用说明") }
                VDivider(inset: 58)
                NavigationLink { LegalDocumentView(document: .auctionRules, showDone: false) } label: { VNavRow(icon: "flag.checkered", iconTint: .vPrimary, title: "拍卖规则") }
                VDivider(inset: 58)
                NavigationLink { LegalDocumentView(document: .disclaimer, showDone: false) } label: { VNavRow(icon: "exclamationmark.shield", iconTint: .vGold, title: "免责声明") }
                VDivider(inset: 58)
                NavigationLink { AboutView() } label: { VNavRow(icon: "info.circle", iconTint: .vTextSecondary, title: "关于 Velora", value: "v0.1.0") }
                if session.isLoggedIn {
                    VDivider(inset: 58)
                    Button { showLogoutConfirm = true } label: { VNavRow(icon: "rectangle.portrait.and.arrow.right", iconTint: .vTextSecondary, title: "退出登录") }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, VSpace.l)
    }

    private func refresh() async {
        guard session.isLoggedIn else { return }
        await session.refreshMe()
        wallet = try? await API.wallet()
    }
}

// MARK: - My lots / bids / follows

struct MyLotsView: View {
    enum Kind { case mine, bids, follows }
    let kind: Kind
    @State private var items: [Lot] = []
    @State private var state: LoadState = .idle
    @State private var status = "all"

    var body: some View {
        VStack(spacing: 0) {
            if kind == .mine {
                VPillSegments(items: [("all", "全部"), ("live", "竞拍中"), ("upcoming", "预展中"), ("ended", "已结束")], selection: $status).padding(.vertical, VSpace.s)
            }
            ScrollView {
                switch state {
                case .idle, .loading: VLoadingView()
                case .failed(let m): VErrorView(message: m) { Task { await load() } }
                case .loaded:
                    if items.isEmpty { VEmptyState(icon: emptyIcon, title: emptyTitle) }
                    else {
                        LazyVStack(spacing: VSpace.m) {
                            ForEach(items) { lot in
                                NavigationLink {
                                    LotDetailView(lotId: lot.id, preload: lot)
                                } label: {
                                    LotRow(lot: lot, trailing: kind == .bids && lot.myBid.hasBid ? "我出 \(lot.myBid.maxAmount.display)" : nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(VSpace.l)
                    }
                }
            }
            .refreshable { await load() }
        }
        .background(Color.vBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: status) { _, _ in Task { await load() } }
    }

    private var title: String { switch kind { case .mine: return "我的拍品"; case .bids: return "我的出价"; case .follows: return "我的关注" } }
    private var emptyIcon: String { switch kind { case .mine: return "flag.checkered"; case .bids: return "hand.raised"; case .follows: return "heart" } }
    private var emptyTitle: String { switch kind { case .mine: return "还没有发布拍品"; case .bids: return "还没有出过价"; case .follows: return "还没有关注的拍品" } }

    private func load() async {
        if items.isEmpty { state = .loading }
        do {
            switch kind {
            case .mine: items = try await API.myLots(status: status).items
            case .bids: items = try await API.myBids().items
            case .follows: items = try await API.myFollows().items
            }
            state = .loaded
        } catch { state = .failed((error as? APIError)?.message ?? "加载失败") }
    }
}

// MARK: - Edit profile

struct EditProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var bio = ""
    @State private var location = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: VSpace.m) {
                    VAvatar(url: session.user?.avatar ?? "", size: 84).padding(.top, VSpace.l)
                    VCard(padding: 0) {
                        VStack(spacing: 0) {
                            VFormRow(title: "昵称") { TextField("1-20 个字符", text: $nickname).multilineTextAlignment(.trailing) }
                            VDivider()
                            VFormRow(title: "所在地") { TextField("如：上海", text: $location).multilineTextAlignment(.trailing) }
                            VDivider()
                            VFormRow(title: "简介") { TextField("介绍一下你的收藏方向", text: $bio, axis: .vertical).multilineTextAlignment(.trailing) }
                        }
                    }
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saving = true
                        Task {
                            defer { saving = false }
                            do {
                                let u = try await API.updateMe(JSONDict(["nickname": nickname, "bio": bio, "location": location]))
                                session.update(user: u); ToastCenter.shared.show("已保存", .success); dismiss()
                            } catch { ToastCenter.shared.error(error) }
                        }
                    }.disabled(nickname.isBlank || saving)
                }
            }
            .onAppear { nickname = session.user?.nickname ?? ""; bio = session.user?.bio ?? ""; location = session.user?.location ?? "" }
        }
    }
}

// MARK: - Fee rules / About

struct FeeRulesView: View {
    @State private var fee: FeeBreakdown?
    @State private var yuan = "1000"
    var body: some View {
        ScrollView {
            VStack(spacing: VSpace.m) {
                VCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("服务费计算器").font(.vHeadline)
                        HStack {
                            Text("成交价 ¥").foregroundStyle(Color.vTextSecondary)
                            TextField("1000", text: $yuan).keyboardType(.numberPad).font(.vMono(18))
                        }
                        .padding(12).background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                        if let fee {
                            VKeyValue(key: "规则", value: fee.ruleName)
                            VKeyValue(key: "卖家服务费（\(fee.sellerRateText)）", value: fee.sellerCommission.display)
                            VKeyValue(key: "买家佣金", value: fee.buyerPremium == 0 ? "免佣" : fee.buyerPremium.display)
                            VKeyValue(key: "卖家到手", value: fee.sellerNet.display, valueColor: .vPrimary, bold: true)
                        }
                    }
                }
                VCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("规则说明").font(.vHeadline)
                        Text("· 买家不支付佣金，成交价即应付金额\n· 卖家按成交价支付平台服务费，设有最低与封顶金额\n· 服务费在买家确认收货、货款结算时自动扣除\n· 不同分类可能适用不同费率，以订单快照为准")
                            .font(.vCaption).foregroundStyle(Color.vTextSecondary).lineSpacing(5)
                    }
                }
            }
            .padding(VSpace.l)
        }
        .background(Color.vBackground)
        .navigationTitle("平台服务费")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: yuan) {
            guard let v = Double(yuan), v > 0 else { return }
            try? await Task.sleep(for: .milliseconds(300))
            fee = try? await API.estimateFee(category: "", price: Money(v * 100))
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: VSpace.l) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(VGradient.brand).frame(width: 96, height: 96)
                    Text("V").font(.system(size: 56, weight: .black, design: .rounded)).foregroundStyle(.white)
                }
                .padding(.top, 40)
                Text("Velora").font(.vLargeTitle)
                Text("赛车模型实时拍卖社区").font(.vBody).foregroundStyle(Color.vTextSecondary)
                Text("版本 0.1.0 · 服务端 \(AppConfig.baseURL.absoluteString)").font(.vMicro).foregroundStyle(Color.vTextTertiary)

                VCard(padding: 0) {
                    VStack(spacing: 0) {
                        NavigationLink { LegalDocumentView(document: .appGuide, showDone: false) } label: { VNavRow(icon: "book", iconTint: .vBlue, title: "使用说明") }
                        VDivider(inset: 58)
                        NavigationLink { LegalDocumentView(document: .auctionRules, showDone: false) } label: { VNavRow(icon: "flag.checkered", iconTint: .vPrimary, title: "拍卖规则") }
                        VDivider(inset: 58)
                        NavigationLink { LegalDocumentView(document: .disclaimer, showDone: false) } label: { VNavRow(icon: "exclamationmark.shield", iconTint: .vGold, title: "免责声明") }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, VSpace.l)
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.vBackground)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
