import SwiftUI

/// 「我的」买卖家视图壳：overview 角标 + bootstrap 入口（DES-v1.3-00-02 / DES-v1.3-12-01 D39）。
struct MeShellView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var meModel = MeOverviewModel()
    @State private var showLogoutConfirm = false
    @State private var showDeletion = false
    @State private var suppressingModeWrite = false

    private var boot: MeBootstrap? { session.bootstrap }
    private var buyerEntries: [MeEntry] {
        if let ov = meModel.overview, ov.resolvedView == .buyer, !ov.entries.isEmpty {
            return ov.entries
                .filter { MeEntryCode.normalize($0.code)?.isBuyerEntry != false }
                .map { meEntry(from: $0) }
        }
        let e = boot?.navSchema.meBuyerEntries ?? []
        return e.isEmpty ? NavSchema.v13Default.meBuyerEntries : e
    }
    private var sellerEntries: [MeEntry] {
        if let ov = meModel.overview, ov.resolvedView == .seller, !ov.entries.isEmpty {
            let sellerType = MeSellerType.normalize(ov.sellerType) ?? MeSellerType.normalize(boot?.seller?.sellerType)
            return ov.entries
                .filter { entry in
                    guard let code = MeEntryCode.normalize(entry.code) else { return true }
                    return MeLogic.shouldRenderEntry(
                        code: code,
                        sellerType: sellerType,
                        showPhase2Entries: ov.showPhase2Entries
                    ) && !code.isBuyerEntry
                }
                .map { meEntry(from: $0) }
        }
        let e = boot?.navSchema.meSellerEntries ?? []
        let base = e.isEmpty ? NavSchema.v13Default.meSellerEntries : e
        // ME-04: invoice / proxy_kpi only for proxy_agent (DES-v1.3-05-01).
        // ME-05 / D21: store only for brand + can_store (DES-v1.3-05-03).
        // D26: presale_orders only for brand + can_presale → merchant Web (DES-v1.3-06-04).
        let sellerType = boot?.seller?.sellerType
        let isProxy = sellerType == ProxyAgentConfigDefaults.sellerType
        let isBrand = sellerType == BrandStoreConfigDefaults.sellerType
        let caps = boot?.seller?.capabilities
        let canStore = caps?.canStore == true
        let canPresale = caps?.canPresale == true
        let canRelease = (caps?.canSpotRelease == true) || (caps?.canLottery == true) || (caps?.canPresale == true)
        return base.filter { entry in
            switch entry.key {
            case ProxyAgentConfigDefaults.meEntryKPI, ProxyAgentConfigDefaults.meEntryInvoice, "invoice", "proxy_kpi":
                return isProxy
            case BrandStoreConfigDefaults.meEntryStore, "store":
                return isBrand && canStore
            case PresaleSummaryConfigDefaults.meEntryKey, "presale_orders", "presale_books":
                return PresaleSummaryLogic.showsMeEntry(sellerType: sellerType, canPresale: canPresale)
            case "releases":
                return isBrand && canRelease
            case "vip", "merge_ship":
                return isBrand
            default:
                return true
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: VSpace.l) {
                    header
                    if session.deletion?.isPendingDeletion == true {
                        deletionBanner
                    }
                    modePicker
                    if meModel.partialHint {
                        Text(MeCopy.partialBadgesHint)
                            .font(.vCaption)
                            .foregroundStyle(Color.vGold)
                            .padding(.horizontal, VSpace.l)
                    }
                    switch router.meMode {
                    case .buyer:
                        entryGrid(buyerEntries, emptyTitle: "买家入口加载中")
                        buyerQuickLinks
                    case .seller:
                        if boot?.seller == nil && meModel.overview?.sellerType == nil {
                            sellerOnboarding
                        } else {
                            sellerBadge
                            entryGrid(sellerEntries, emptyTitle: "卖家入口加载中")
                        }
                    }
                    settingsSection
                }
                .padding(.bottom, 100)
            }
            .background(Color.vBackground)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await session.refreshMe()
                await meModel.refresh()
            }
            .task {
                await meModel.refresh()
                if let view = meModel.overview?.resolvedView {
                    suppressingModeWrite = true
                    router.meMode = view == .seller ? .seller : .buyer
                    suppressingModeWrite = false
                }
            }
        }
        .id(router.meStackID)
        .sheet(isPresented: $showDeletion) { AccountDeletionView() }
        .confirmationDialog("退出登录？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                session.logout()
                router.selectPrimaryBrowse()
            }
        }
        .onChange(of: router.meMode) { _, newMode in
            guard !suppressingModeWrite else { return }
            Task { await handleModeChange(newMode) }
        }
    }

    private func meEntry(from ov: MeOverviewEntry) -> MeEntry {
        let code = MeEntryCode.normalize(ov.code)
        let title: String
        if code == .sellerDeposit {
            title = MeLogic.sellerDepositTitle(sellerType: meModel.overview?.resolvedSellerType)
        } else {
            title = ov.title.isEmpty ? (code?.defaultTitle ?? ov.code) : ov.title
        }
        return MeEntry(
            key: ov.code,
            title: title,
            icon: ov.systemImage,
            enabled: ov.enabled
        )
    }

    private func handleModeChange(_ newMode: MeShellMode) async {
        guard session.isLoggedIn else { return }
        let previous: MeShellMode = newMode == .buyer ? .seller : .buyer
        let target: MeViewMode = newMode == .seller ? .seller : .buyer
        switch await meModel.switchView(target) {
        case .ok(let confirmed):
            let mapped: MeShellMode = confirmed == .seller ? .seller : .buyer
            if mapped != newMode {
                suppressingModeWrite = true
                router.meMode = mapped
                suppressingModeWrite = false
            }
        case .sellerRequired:
            suppressingModeWrite = true
            router.meMode = .buyer
            suppressingModeWrite = false
            ToastCenter.shared.show(MeErrorCode.sellerRequired.fallbackMessage, .info)
        case .failed:
            suppressingModeWrite = true
            router.meMode = previous
            suppressingModeWrite = false
            ToastCenter.shared.show(MeCopy.viewSwitchFailed, .error)
        }
    }

    private var deletionBanner: some View {
        Button { showDeletion = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.vGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("账号注销冷静期").font(.vBodyMedium).foregroundStyle(Color.vText)
                    if let at = session.deletion?.executeAt {
                        Text("将于 \(at.shortText) 注销，点此取消")
                            .font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    } else {
                        Text("点此查看或取消注销").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.vTextTertiary)
            }
            .padding(14)
            .background(Color.vGold.opacity(0.15), in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, VSpace.l)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            if let u = session.user {
                NavigationLink { ProfileView() } label: {
                    HStack(spacing: 14) {
                        VAvatar(url: u.avatar, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(u.nickname).font(.vTitle(20)).foregroundStyle(Color.vText)
                            HStack(spacing: 6) {
                                let credit = boot?.creditScore ?? u.creditScore
                                Text("信用 \(credit)")
                                    .font(.vCaptionMedium)
                                    .foregroundStyle(Color.vPrimary)
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
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.vTextTertiary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button { router.showLogin = true } label: {
                    HStack(spacing: 14) {
                        Circle().fill(Color.vSurfaceElevated).frame(width: 56, height: 56)
                            .overlay(Image(systemName: "person.fill").foregroundStyle(Color.vTextSecondary))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("点击登录").font(.vTitle(20)).foregroundStyle(Color.vText)
                            Text("登录后同步买卖家入口").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, VSpace.l)
        .padding(.top, VSpace.l)
    }

    private var modePicker: some View {
        Picker("视图", selection: $router.meMode) {
            Text(MeCopy.buyerTab).tag(MeShellMode.buyer)
            Text(MeCopy.sellerTab).tag(MeShellMode.seller)
        }
        .pickerStyle(.segmented)
        .disabled(meModel.switching)
        .padding(.horizontal, VSpace.l)
    }

    private func entryGrid(_ entries: [MeEntry], emptyTitle: String) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                if entries.isEmpty {
                    Text(emptyTitle).font(.vCaption).foregroundStyle(Color.vTextTertiary)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                        ForEach(entries) { entry in
                            entryCell(entry)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, VSpace.l)
    }

    @ViewBuilder
    private func entryCell(_ entry: MeEntry) -> some View {
        let enabled = meModel.isEntryEnabled(entry.key, bootstrapEnabled: entry.enabled)
        switch entry.key {
        case "history", "browse_history":
            NavigationLink { BrowseHistoryView() } label: { entryLabel(entry) }
                .buttonStyle(.plain)
                .opacity(enabled ? 1 : 0.55)
        case "fav", "favorites", "favorite":
            NavigationLink { MyLotsView(kind: .follows) } label: { entryLabel(entry) }
                .buttonStyle(.plain)
                .opacity(enabled ? 1 : 0.55)
        case "bids", "my_bids":
            NavigationLink { MyLotsView(kind: .bids) } label: { entryLabel(entry) }
                .buttonStyle(.plain)
                .opacity(enabled ? 1 : 0.55)
        case "onsale", "on_sale":
            NavigationLink { MyListingsView() } label: { entryLabel(entry) }
                .buttonStyle(.plain)
                .opacity(enabled ? 1 : 0.55)
                .disabled(!enabled)
                .simultaneousGesture(TapGesture().onEnded {
                    if !enabled {
                        ToastCenter.shared.show(
                            meModel.reasonMessage(for: entry.key) ?? MeCopy.reasonCapabilityOff,
                            .info
                        )
                    }
                })
        case "auctions", "auction":
            NavigationLink { MyLotsView(kind: .mine) } label: { entryLabel(entry) }
                .buttonStyle(.plain)
                .opacity(enabled ? 1 : 0.55)
                .disabled(!enabled)
                .simultaneousGesture(TapGesture().onEnded {
                    if !enabled {
                        ToastCenter.shared.show(
                            meModel.reasonMessage(for: entry.key) ?? MeCopy.reasonCapabilityOff,
                            .info
                        )
                    }
                })
        case "subs", "subscriptions", "subscription":
            Button {
                guard enabled else {
                    ToastCenter.shared.show(meModel.reasonMessage(for: entry.key) ?? MeCopy.reasonComingSoon, .info)
                    return
                }
                ToastCenter.shared.show(MeCopy.comingSoonSheet, .info)
            } label: { entryLabel(entry) }
            .buttonStyle(.plain)
        case "releases", "vip", "merge_ship":
            Button {
                guard enabled else {
                    ToastCenter.shared.show(meModel.reasonMessage(for: entry.key) ?? MeCopy.reasonComingSoon, .info)
                    return
                }
                if !session.isLoggedIn { router.showLogin = true; return }
                ToastCenter.shared.show(MeCopy.comingSoonSheet, .info)
            } label: { entryLabel(entry) }
            .buttonStyle(.plain)
        case "proxy_kpi", ProxyAgentConfigDefaults.meEntryKPI:
            NavigationLink {
                ProxyAssessmentView()
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(entry.enabled ? 1 : 0.55)
        case "invoice", ProxyAgentConfigDefaults.meEntryInvoice, InvoiceConfigDefaults.meEntryKey:
            NavigationLink {
                InvoiceHomeView()
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(entry.enabled ? 1 : 0.55)
        case "sub_merchant", ProfitSharingConfigDefaults.meEntryKey:
            NavigationLink {
                SubMerchantProgressView()
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(entry.enabled ? 1 : 0.55)
        case "deposit", "deposits_buy", DepositConfigDefaults.meEntryKey:
            NavigationLink {
                MyDepositsView()
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(enabled ? 1 : 0.55)
        case "seller_deposit", DepositConfigDefaults.meSellerEntryKey:
            NavigationLink {
                SellerDepositView()
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(entry.enabled ? 1 : 0.55)
        case "lottery", LotteryConfigDefaults.meEntryKey:
            NavigationLink {
                MyLotteryEntriesView()
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(entry.enabled ? 1 : 0.55)
        case "balance", "balance_due", PresaleConfigDefaults.meEntryKey:
            NavigationLink {
                MyBalanceOrdersView()
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(enabled ? 1 : 0.55)
        case "store", BrandStoreConfigDefaults.meEntryStore:
            if let sellerId = session.user?.id {
                NavigationLink {
                    BrandStoreView(brandId: sellerId)
                } label: {
                    entryLabel(entry)
                }
                .buttonStyle(.plain)
                .opacity(entry.enabled ? 1 : 0.55)
            } else {
                Button {
                    router.showLogin = true
                } label: {
                    entryLabel(entry)
                }
                .buttonStyle(.plain)
            }
        case "presale_orders", PresaleSummaryConfigDefaults.meEntryKey:
            NavigationLink {
                PresaleMerchantRedirectView()
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(entry.enabled ? 1 : 0.55)
        case "bought", OrderCenterConfigDefaults.meBuyerEntryKey, "orders":
            NavigationLink {
                OrderListView(role: "buyer")
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(entry.enabled ? 1 : 0.55)
        case "sold", OrderCenterConfigDefaults.meSellerEntryKey:
            NavigationLink {
                OrderListView(role: "seller")
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(entry.enabled ? 1 : 0.55)
        case "after_sale", "after_sale_buy", "after_sale_sell":
            NavigationLink {
                OrderListView(role: router.meMode == .seller ? "seller" : "buyer", initialStatus: "after_sale")
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(enabled ? 1 : 0.55)
        case "wallet", WalletConfigDefaults.meEntryKey:
            NavigationLink {
                WalletView()
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(enabled ? 1 : 0.55)
        case "profit", "income", IncomeConfigDefaults.meEntryKey:
            NavigationLink {
                IncomeView()
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(enabled ? 1 : 0.55)
        case "presale_books":
            NavigationLink {
                PresaleMerchantRedirectView()
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .opacity(enabled ? 1 : 0.55)
        case LibraryConfigDefaults.meEntryLibrary, "product_library", "skus":
            NavigationLink { LibraryIndexView() } label: { entryLabel(entry) }
                .buttonStyle(.plain)
        case LibraryConfigDefaults.meEntryCabinet, "model_cabinet", "virtual_cabinet":
            NavigationLink {
                CabinetWallView(
                    userId: session.user?.id,
                    isSelf: true,
                    entryKind: .cabinetComingSoon
                )
            } label: { entryLabel(entry) }
            .buttonStyle(.plain)
        case LibraryConfigDefaults.meEntryAtlas, "codex", "collection_atlas":
            NavigationLink { AtlasSummaryView() } label: { entryLabel(entry) }
                .buttonStyle(.plain)
        default:
            if MeEntryCode.normalize(entry.key) == nil {
                Button {
                    ToastCenter.shared.show(MeLogic.unknownEntryMessage(code: entry.key), .info)
                } label: {
                    entryLabel(entry)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    guard enabled else {
                        ToastCenter.shared.show(
                            meModel.reasonMessage(for: entry.key) ?? MeCopy.reasonComingSoon,
                            .info
                        )
                        return
                    }
                    if !session.isLoggedIn {
                        router.showLogin = true
                        return
                    }
                    ToastCenter.shared.show("「\(entry.title)」\(MeCopy.comingSoonSheet)", .info)
                } label: {
                    entryLabel(entry)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func entryLabel(_ entry: MeEntry) -> some View {
        let enabled = meModel.isEntryEnabled(entry.key, bootstrapEnabled: entry.enabled)
        let badge = meModel.badge(for: entry.key)
        return VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: entry.icon ?? MeEntryCode.normalize(entry.key)?.defaultSystemImage ?? "square.grid.2x2")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(enabled ? Color.vPrimary : Color.vTextTertiary)
                    .frame(width: 28, height: 24)
                if let text = MeLogic.badgeText(badge) {
                    Text(text)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.vPrimary, in: Capsule())
                        .offset(x: 10, y: -6)
                }
            }
            Text(entry.title)
                .font(.vMicro)
                .foregroundStyle(enabled ? Color.vTextSecondary : Color.vTextTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .opacity(enabled ? 1 : 0.55)
    }

    private func proxyCapabilitiesFromBootstrap() -> ProxyCapabilities {
        guard let caps = boot?.seller?.capabilities else { return .goldDefaults }
        return ProxyCapabilities(
            canFixed: caps.canFixed,
            canAuction: caps.canAuction,
            canBatchList: caps.canBatchList,
            canInvoiceService: caps.canInvoiceService,
            canSession: caps.canSession,
            canPromote: caps.canPromote
        )
    }

    private var buyerQuickLinks: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                NavigationLink { BrowseHistoryView() } label: {
                    VNavRow(icon: "clock", iconTint: .vBlue, title: MeCopy.historyTitle)
                }
                VDivider(inset: 58)
                NavigationLink { OrderListView(role: "buyer") } label: {
                    VNavRow(icon: "shippingbox", iconTint: .vPrimary, title: OrderCenterCopy.centerTitle)
                }
                VDivider(inset: 58)
                NavigationLink { MyLotsView(kind: .bids) } label: {
                    VNavRow(icon: "hand.raised", iconTint: .vPrimary, title: "我的出价")
                }
                VDivider(inset: 58)
                NavigationLink { MyLotsView(kind: .follows) } label: {
                    VNavRow(icon: "heart", iconTint: .vPrimary, title: "我的关注")
                }
                // DES-v1.3-12-04 / D42 Phase 3 — empty / coming-soon library shells
                VDivider(inset: 58)
                NavigationLink { LibraryIndexView() } label: {
                    VNavRow(icon: "books.vertical", iconTint: .vBlue, title: LibraryCopy.libraryTitle)
                }
                VDivider(inset: 58)
                NavigationLink {
                    CabinetWallView(
                        userId: session.user?.id,
                        isSelf: true,
                        entryKind: .cabinetComingSoon
                    )
                } label: {
                    VNavRow(icon: "cube.box", iconTint: .vGold, title: LibraryCopy.cabinetTitle)
                }
                VDivider(inset: 58)
                NavigationLink { AtlasSummaryView() } label: {
                    VNavRow(icon: "square.grid.3x3", iconTint: .vPrimary, title: LibraryCopy.atlasTitle)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, VSpace.l)
    }

    private var sellerOnboarding: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text(MeCopy.sellerOnboardingTitle).font(.vHeadline)
                Text(MeCopy.sellerOnboardingHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                HStack(spacing: 8) {
                    ForEach(["实名", "协议", "保证金", "进件"], id: \.self) { step in
                        Text(step)
                            .font(.vMicro)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.vSurfaceElevated, in: Capsule())
                            .foregroundStyle(Color.vTextSecondary)
                    }
                }
                Button {
                    if !session.isLoggedIn { router.showLogin = true; return }
                    router.showSellerOnboarding = true
                } label: {
                    Text(MeCopy.sellerOnboardingCTA)
                        .font(.vBodyMedium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(VGradient.brand, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, VSpace.l)
    }

    private var sellerBadge: some View {
        Group {
            if let seller = boot?.seller {
                HStack(spacing: 8) {
                    if seller.sellerType == ProxyAgentConfigDefaults.sellerType {
                        NavigationLink {
                            ProxyAgentBadgeView(
                                level: seller.proxyAssessmentLevel ?? .gold,
                                badgeLabel: seller.proxyBuyerBadgeLabel ?? sellerTypeLabel(seller.sellerType),
                                capabilities: proxyCapabilitiesFromBootstrap()
                            )
                        } label: {
                            Text(seller.proxyBuyerBadgeLabel ?? sellerTypeLabel(seller.sellerType))
                                .font(.vCaptionMedium)
                                .foregroundStyle(Color.vPrimary)
                        }
                        .buttonStyle(.plain)
                    } else if seller.sellerType == BrandStoreConfigDefaults.sellerType,
                              let sellerId = session.user?.id {
                        NavigationLink {
                            BrandStoreView(brandId: sellerId)
                        } label: {
                            HStack(spacing: 4) {
                                Text(sellerTypeLabel(seller.sellerType))
                                    .font(.vCaptionMedium)
                                    .foregroundStyle(Color.vPrimary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.vTextTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(sellerTypeLabel(seller.sellerType))
                            .font(.vCaptionMedium)
                            .foregroundStyle(Color.vPrimary)
                    }
                    if let level = seller.proxyAssessmentLevel {
                        Text(level.displayLabel)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    } else if let badge = seller.badge, !badge.isEmpty {
                        Text(badge).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    }
                    Spacer()
                    if seller.capabilities.canAuction {
                        Text("可拍卖").font(.vMicro).foregroundStyle(Color.vGreen)
                    }
                    if seller.capabilities.canFixed {
                        Text("可直购").font(.vMicro).foregroundStyle(Color.vGreen)
                    }
                }
                .padding(.horizontal, VSpace.l)
            }
        }
    }

    private var settingsSection: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                NavigationLink { ProfileView() } label: {
                    VNavRow(
                        icon: "person.crop.circle",
                        iconTint: .vBlue,
                        title: MeCopy.accountProfileTitle,
                        value: session.user?.nickname
                    )
                }
                VDivider(inset: 58)
                NavigationLink { MeSettingsView() } label: {
                    VNavRow(
                        icon: "gearshape",
                        iconTint: .vBlue,
                        title: MeCopy.settingsTitle,
                        value: realNameLabel
                    )
                }
                VDivider(inset: 58)
                NavigationLink { BrowseHistoryView() } label: {
                    VNavRow(icon: "clock", iconTint: .vBlue, title: MeCopy.historyTitle)
                }
                VDivider(inset: 58)
                NavigationLink { WalletView() } label: {
                    VNavRow(icon: "wallet.pass", iconTint: .vGold, title: "我的钱包")
                }
                VDivider(inset: 58)
                NavigationLink { SubMerchantProgressView() } label: {
                    VNavRow(icon: "creditcard", iconTint: .vGold, title: ProfitSharingCopy.progressTitle)
                }
                VDivider(inset: 58)
                NavigationLink { AboutView() } label: {
                    VNavRow(
                        icon: "info.circle",
                        iconTint: .vTextSecondary,
                        title: "关于 \(AppConfig.brandDisplayName)",
                        value: "规则 · 协议"
                    )
                }
                if session.isLoggedIn {
                    VDivider(inset: 58)
                    Button { showLogoutConfirm = true } label: {
                        VNavRow(icon: "rectangle.portrait.and.arrow.right", iconTint: .vTextSecondary, title: "退出登录")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, VSpace.l)
    }

    private func sellerTypeLabel(_ type: String) -> String {
        switch type {
        case "personal": return "个人卖家"
        case "proxy_agent":
            // Prefer assessment_level when present (DES-v1.3-05-01 §14).
            if let label = boot?.seller?.proxyBuyerBadgeLabel { return label }
            return ProxyAgentCopy.goldBadge
        case "brand": return "品牌官方"
        default: return type
        }
    }

    private var realNameLabel: String {
        let raw = boot?.me?.realNameStatus ?? session.user?.realNameStatus ?? "none"
        return RealNameStatusValue(rawValue: raw)?.displayLabel ?? "未实名"
    }
}
