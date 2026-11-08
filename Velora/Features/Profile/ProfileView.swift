import SwiftUI

/// 账户与资料：仅管理对外身份与账号安全，不再重复「我的」买卖家入口（DES-v1.3-12-01）。
struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @State private var showEdit = false

    private var boot: MeBootstrap? { session.bootstrap }

    var body: some View {
        Group {
            if let user = session.user {
                ScrollView {
                    VStack(spacing: VSpace.l) {
                        identityCard(user)
                        profileFieldsCard(user)
                        securityCard
                    }
                    .padding(VSpace.l)
                    .padding(.bottom, 40)
                }
            } else {
                VEmptyState(
                    icon: "person.crop.circle",
                    title: MeCopy.loginRequired,
                    message: "登录后可编辑昵称、简介与实名信息",
                    actionTitle: "去登录"
                ) {
                    router.showLogin = true
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(MeCopy.accountProfileTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.user != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(MeCopy.accountProfileEdit) { showEdit = true }
                        .font(.vCaptionMedium)
                }
            }
        }
        .sheet(isPresented: $showEdit) { EditProfileView() }
        .task {
            guard session.isLoggedIn else { return }
            await session.refreshMe()
        }
    }

    private func identityCard(_ user: User) -> some View {
        VCard {
            HStack(spacing: 14) {
                VAvatar(url: user.avatar, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(user.nickname).font(.vTitle(20)).foregroundStyle(Color.vText)
                    HStack(spacing: 6) {
                        let credit = boot?.creditScore ?? user.creditScore
                        NavigationLink { MeCreditView() } label: {
                            Text("信用 \(credit)")
                                .font(.vCaptionMedium)
                                .foregroundStyle(Color.vPrimary)
                        }
                        .buttonStyle(.plain)
                        if let type = boot?.seller?.sellerType {
                            Text(sellerTypeLabel(type))
                                .font(.vCaption)
                                .foregroundStyle(Color.vTextSecondary)
                        }
                    }
                    Text(MeCopy.accountProfileHint)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func profileFieldsCard(_ user: User) -> some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                Button { showEdit = true } label: {
                    VNavRow(
                        icon: "person.text.rectangle",
                        iconTint: .vBlue,
                        title: "昵称",
                        value: user.nickname
                    )
                }
                VDivider(inset: 58)
                Button { showEdit = true } label: {
                    VNavRow(
                        icon: "mappin.and.ellipse",
                        iconTint: .vGreen,
                        title: "所在地",
                        value: {
                            let loc = user.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            return loc.isEmpty ? MeCopy.accountLocationEmpty : loc
                        }()
                    )
                }
                VDivider(inset: 58)
                Button { showEdit = true } label: {
                    VNavRow(
                        icon: "text.alignleft",
                        iconTint: .vTextSecondary,
                        title: "简介",
                        value: {
                            let bio = user.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            return bio.isEmpty ? MeCopy.accountBioEmpty : bio
                        }()
                    )
                }
                if let phone = user.phoneMasked, !phone.isEmpty {
                    VDivider(inset: 58)
                    VNavRow(
                        icon: "phone",
                        iconTint: .vBlue,
                        title: MeCopy.accountPhoneTitle,
                        value: phone
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var securityCard: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                NavigationLink { RealNameView() } label: {
                    VNavRow(
                        icon: "checkmark.shield",
                        iconTint: .vGreen,
                        title: MeCopy.realNameTitle,
                        value: realNameLabel
                    )
                }
                VDivider(inset: 58)
                NavigationLink { SessionsView() } label: {
                    VNavRow(
                        icon: "laptopcomputer.and.iphone",
                        iconTint: .vBlue,
                        title: MeCopy.accountSessionsTitle
                    )
                }
                VDivider(inset: 58)
                NavigationLink { MeSettingsView() } label: {
                    VNavRow(
                        icon: "gearshape",
                        iconTint: .vTextSecondary,
                        title: MeCopy.settingsTitle,
                        value: "地址 · 推送 · 协议"
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var realNameLabel: String {
        let raw = boot?.me?.realNameStatus ?? session.user?.realNameStatus ?? "none"
        return RealNameStatusValue(rawValue: raw)?.displayLabel ?? MeCopy.realNameUnset
    }

    private func sellerTypeLabel(_ type: String) -> String {
        switch type {
        case "personal": return "个人卖家"
        case "proxy_agent":
            if let label = boot?.seller?.proxyBuyerBadgeLabel { return label }
            return ProxyAgentCopy.goldBadge
        case "brand": return "品牌官方"
        default: return type
        }
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
                VPillSegments(
                    items: [
                        ("all", "全部"),
                        ("live", "竞拍中"),
                        ("upcoming", "预展中"),
                        ("ended", "已成交"),
                        ("unsold", "流拍"),
                    ],
                    selection: $status
                )
                .padding(.vertical, VSpace.s)
            }
            ScrollView {
                switch state {
                case .idle, .loading: VLoadingView()
                case .failed(let m): VErrorView(message: m) { Task { await load() } }
                case .loaded:
                    if items.isEmpty {
                        if kind == .mine && status == "unsold" {
                            UnsoldLotsEmptyView()
                        } else {
                            VEmptyState(icon: emptyIcon, title: emptyTitle)
                        }
                    } else {
                        LazyVStack(spacing: VSpace.m) {
                            ForEach(items) { lot in
                                NavigationLink {
                                    if kind == .mine && lot.status == .unsold {
                                        AuctionUnsoldView(lotId: lot.id, preload: lot)
                                    } else {
                                        LotDetailView(lotId: lot.id, preload: lot)
                                    }
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
            case .mine:
                var lots = try await API.myLots(status: status).items
                // Defend against server defaulting unknown status (e.g. unsold→live+scheduled).
                switch status {
                case "live": lots = lots.filter { $0.status == .live }
                case "upcoming": lots = lots.filter { $0.status == .scheduled }
                case "ended": lots = lots.filter { $0.status == .ended }
                case "unsold": lots = lots.filter { $0.status == .unsold }
                default: break
                }
                items = lots
            case .bids: items = try await API.myBids().items
            case .follows: items = try await API.myFollows().items
            }
            state = .loaded
        } catch { state = .failed((error as? APIError)?.message ?? "加载失败") }
    }
}

// MARK: - Seller fixed / 直购 listings (我的在售)

struct MyListingsView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var items: [SearchListingCard] = []
    @State private var state: LoadState = .idle
    @State private var status = "on_sale"
    @State private var actingId: Int64?

    var body: some View {
        VStack(spacing: 0) {
            VPillSegments(
                items: [
                    ("on_sale", "在售"),
                    ("off_shelf", "已下架"),
                    ("sold", "已售出"),
                ],
                selection: $status
            )
            .padding(.vertical, VSpace.s)

            ScrollView {
                switch state {
                case .idle, .loading:
                    VLoadingView()
                case .failed(let m):
                    VErrorView(message: m) { Task { await load() } }
                case .loaded:
                    if items.isEmpty {
                        VEmptyState(icon: "tag", title: emptyTitle, message: "发布直购后会出现在这里")
                    } else {
                        LazyVStack(spacing: VSpace.m) {
                            ForEach(items) { card in
                                HStack(spacing: 8) {
                                    NavigationLink {
                                        ListingDetailView(listingId: card.listingId, preloadTradeType: "fixed")
                                    } label: {
                                        sellerListingRow(card)
                                    }
                                    .buttonStyle(.plain)
                                    if status == "on_sale" {
                                        Button("下架") {
                                            Task { await offShelf(card.listingId) }
                                        }
                                        .font(.vCaptionMedium)
                                        .foregroundStyle(Color.vPrimary)
                                        .disabled(actingId == card.listingId)
                                        .padding(.trailing, 4)
                                    }
                                }
                            }
                        }
                        .padding(VSpace.l)
                    }
                }
            }
            .refreshable { await load() }
        }
        .background(Color.vBackground)
        .navigationTitle("我的在售")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: status) { _, _ in Task { await load() } }
    }

    private var emptyTitle: String {
        switch status {
        case "off_shelf": return "没有已下架的直购"
        case "sold": return "还没有售出的直购"
        default: return "还没有在售直购"
        }
    }

    private func sellerListingRow(_ card: SearchListingCard) -> some View {
        HStack(spacing: 12) {
            RemoteImage(card.cover)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title).font(.vBodyMedium).foregroundStyle(Color.vText).lineLimit(2)
                HStack(spacing: 6) {
                    VPriceText(amount: card.displayPrice, size: 14)
                    if card.negotiable == true {
                        Text("可议价").font(.vMicro).foregroundStyle(Color.vGold)
                    }
                }
                Text(statusLabel(card.status)).font(.vCaption).foregroundStyle(Color.vTextTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.vTextTertiary)
        }
        .padding(12)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func statusLabel(_ raw: String?) -> String {
        switch raw {
        case "on_sale": return "在售"
        case "off_shelf": return "已下架"
        case "sold": return "已售出"
        default: return raw ?? ""
        }
    }

    private func load() async {
        guard let sellerId = session.user?.id else {
            state = .failed("请先登录")
            return
        }
        if items.isEmpty { state = .loading }
        do {
            var q = ListingSearchQuery()
            q.tradeType = "fixed"
            q.sellerId = sellerId
            q.status = status
            q.pageSize = 50
            let page = try await API.listings(q)
            items = page.items
            state = .loaded
        } catch {
            state = .failed((error as? APIError)?.message ?? "加载失败")
        }
    }

    private func offShelf(_ id: Int64) async {
        actingId = id
        defer { actingId = nil }
        do {
            try await API.offShelfListing(id)
            ToastCenter.shared.show("已下架", .success)
            await load()
        } catch {
            ToastCenter.shared.error(error)
        }
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
            .navigationTitle(MeCopy.accountProfileEdit)
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
                Text(AppConfig.brandDisplayName).font(.vLargeTitle)
                Text("赛车模型实时拍卖社区").font(.vBody).foregroundStyle(Color.vTextSecondary)
                Text("版本 0.1.0 · 服务端 \(AppConfig.baseURL.absoluteString)").font(.vMicro).foregroundStyle(Color.vTextTertiary)

                VCard(padding: 0) {
                    VStack(spacing: 0) {
                        NavigationLink { LegalDocumentView(document: .appGuide, showDone: false) } label: { VNavRow(icon: "book", iconTint: .vBlue, title: "使用说明") }
                        VDivider(inset: 58)
                        NavigationLink { LegalDocumentView(document: .auctionRules, showDone: false) } label: { VNavRow(icon: "flag.checkered", iconTint: .vPrimary, title: "拍卖规则") }
                        VDivider(inset: 58)
                        NavigationLink { LegalDocumentView(document: .disclaimer, showDone: false) } label: { VNavRow(icon: "exclamationmark.shield", iconTint: .vGold, title: "免责声明") }
                        VDivider(inset: 58)
                        NavigationLink { FeeRulesView() } label: { VNavRow(icon: "percent", iconTint: .vPrimary, title: "平台服务费说明") }
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
