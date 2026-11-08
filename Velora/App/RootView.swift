import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var live: AuctionLiveStore
    @EnvironmentObject private var router: AppRouter
    @State private var showSplash = true

    var body: some View {
        ZStack {
            MainTabView()
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .task {
            AppRouterProxy.router = router
            async let boot: () = session.bootstrap()
            async let minDelay: () = (try? Task.sleep(for: .seconds(0.9))) ?? ()
            _ = await (boot, minDelay)
            withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
        }
        .onAppear { AppRouterProxy.router = router }
        .sheet(isPresented: $router.showLogin) {
            LoginView()
        }
        .sheet(isPresented: $router.showRealName) {
            NavigationStack { RealNameView() }
        }
        .sheet(isPresented: $router.showSellerOnboarding) {
            NavigationStack { SellerOnboardingView() }
        }
        .sheet(isPresented: $router.showSubMerchantProgress) {
            NavigationStack { SubMerchantProgressView(presentedAsSheet: true) }
        }
        .fullScreenCover(item: $session.accountGate) { notice in
            FrozenAccountView(notice: notice) {
                session.dismissAccountGate()
            } onLogin: {
                router.showLogin = true
            }
        }
        .overlay(alignment: .top) {
            if let n = live.latestNotice {
                NoticeBanner(notice: n) {
                    live.latestNotice = nil
                    if let o = n.orderId { router.open(order: o) } else if let l = n.lotId { router.open(lot: l) }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: n.id) {
                    try? await Task.sleep(for: .seconds(4))
                    if live.latestNotice?.id == n.id { withAnimation { live.latestNotice = nil } }
                }
            }
        }
        .animation(.spring(duration: 0.4), value: live.latestNotice)
    }
}

/// 顶部实时通知横幅
struct NoticeBanner: View {
    let notice: AuctionLiveStore.Notice
    let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(notice.title).font(.vBodyMedium).foregroundStyle(Color.vText)
                    Text(notice.message).font(.vCaption).foregroundStyle(Color.vTextSecondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.vTextTertiary)
            }
            .padding(12)
            .background(Color.vSurfaceElevated, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            .vFloatingShadow()
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }
    private var icon: String {
        switch notice.type {
        case "outbid": return "arrow.up.right.circle.fill"
        case "proxy_exceeded", "proxy_bid_exceeded": return "bolt.slash.fill"
        case "auction_won": return "trophy.fill"
        case "lot_sold": return "checkmark.seal.fill"
        case "lot_unsold": return "xmark.circle.fill"
        default: return "bell.fill"
        }
    }
    private var tint: Color {
        switch notice.type {
        case "outbid", "proxy_exceeded", "proxy_bid_exceeded": return .vPrimary
        case "auction_won": return .vGold
        case "lot_sold": return .vGreen
        default: return .vBlue
        }
    }
}

struct SplashView: View {
    @State private var scale: CGFloat = 0.85
    @State private var opacity: CGFloat = 0
    var body: some View {
        ZStack {
            Color.vPrimary.ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white).frame(width: 108, height: 108)
                    Text("V").font(.system(size: 66, weight: .black, design: .rounded)).foregroundStyle(Color.vPrimary)
                }
                Text(AppConfig.brandDisplayName).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("赛车模型 · 实时拍卖").font(.vBodyMedium).foregroundStyle(.white.opacity(0.85)).tracking(2)
            }
            .scaleEffect(scale).opacity(opacity)
        }
        .onAppear { withAnimation(.spring(duration: 0.6)) { scale = 1; opacity = 1 } }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch router.tab {
                case .buy, .home:
                    HomeView()
                case .auctions:
                    AuctionsView()
                case .community:
                    CommunityView()
                case .publish:
                    // Publish is a modal; keep last browse surface under the tab chrome.
                    HomeView()
                case .inbox:
                    NotificationCenterView()
                case .me:
                    MeShellView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.bottom, router.hideTabBar ? 0 : 84)

            if !router.hideTabBar {
                VTabBar()
            }
        }
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $router.showPublish) {
            PublishView(tradeType: router.publishTradeType)
        }
        .confirmationDialog("选择发布类型", isPresented: $router.showPublishActions, titleVisibility: .visible) {
            ForEach(router.publishActions.filter(\.enabled)) { action in
                Button(action.title) {
                    handlePublishAction(action)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(item: Binding(get: { router.pendingLot.map(IDBox.init) }, set: { router.pendingLot = $0?.id })) { box in
            NavigationStack { LotDetailView(lotId: box.id) }
        }
        .sheet(item: Binding(
            get: { router.pendingListing.map(IDBox.init) },
            set: {
                router.pendingListing = $0?.id
                if $0 == nil { router.pendingListingOfferId = nil }
            }
        )) { box in
            NavigationStack {
                ListingDetailView(
                    listingId: box.id,
                    preferredOfferId: router.pendingListingOfferId
                )
            }
        }
        .sheet(item: Binding(get: { router.pendingOrder.map(IDBox.init) }, set: { router.pendingOrder = $0?.id })) { box in
            NavigationStack { OrderDetailView(orderId: box.id, presentedAsSheet: true) }
        }
        .sheet(item: Binding(
            get: { router.pendingBalancePay.map(BalancePayLinkBox.init) },
            set: { router.pendingBalancePay = $0?.link }
        )) { box in
            NavigationStack {
                if let orderId = box.link.balanceOrderId {
                    BalancePayLandingView(balanceOrderId: orderId, token: box.link.token)
                } else {
                    MyBalanceOrdersView()
                }
            }
        }
        .sheet(item: $router.creditBlock) { info in
            CreditBlockView(
                info: info,
                onDismiss: { router.creditBlock = nil },
                onOpenCredit: {
                    router.creditBlock = nil
                    router.tab = .me
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func handlePublishAction(_ action: PublishAction) {
        let rn = session.bootstrap?.me?.realNameStatus ?? session.user?.realNameStatus
        let realNameDone = rn == "verified" || rn == "passed"
        let seller = session.bootstrap?.seller
        let sellerStatus = seller?.onboardingStatus
        let sellerReady = seller != nil && (
            sellerStatus == nil
                || sellerStatus == "ready"
                || sellerStatus == "completed"
                || sellerStatus == "finished"
        )
        let gate = PublishEntryResolver.resolve(
            isLoggedIn: session.isLoggedIn,
            isFrozen: session.accessFlags.isFrozen,
            canPublish: session.accessFlags.canPublish,
            realNameDone: realNameDone,
            sellerReady: sellerReady,
            actionKey: action.key,
            actionEnabled: action.enabled,
            actionTitle: action.title,
            requiresCapability: action.requiresCapability,
            capabilityAllows: { key in
                seller?.capabilities.allows(key) ?? false
            }
        )
        switch gate {
        case .ok:
            router.openPublish(action: action)
        case .loginRequired:
            router.showLogin = true
        case .realNameRequired:
            ToastCenter.shared.show(gate.message, .info)
            router.openRealName()
        case .sellerRequired:
            ToastCenter.shared.show(gate.message, .info)
            router.openSellerOnboarding()
        case .frozen, .publishForbidden, .capabilityDisabled, .comingSoon:
            ToastCenter.shared.show(gate.message, .info)
        }
    }
}

struct IDBox: Identifiable { let id: Int64 }

struct BalancePayLinkBox: Identifiable {
    let link: BalancePayDeepLink
    var id: String {
        if let oid = link.balanceOrderId {
            return "balance-\(oid)-\(link.token ?? "")"
        }
        return "short-\(link.shortCode ?? link.rawURL.absoluteString)"
    }
}

/// 自定义底栏：中间凸起的「发布」按钮；Tab 顺序/文案来自 bootstrap `nav_schema`。
struct VTabBar: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SessionStore

    private var barItems: [(tab: AppTab, meta: NavTab)] {
        router.visibleTabs
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(barItems, id: \.tab) { item in
                if item.tab == .publish {
                    publishButton(title: item.meta.title)
                } else {
                    tab(item.tab, meta: item.meta, badge: item.tab == .inbox ? session.unread : 0)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background(
            Color.vSurface.opacity(0.96)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Rectangle().fill(Color.vSeparator).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tab(_ t: AppTab, meta: NavTab, badge: Int = 0) -> some View {
        let on = router.tab == t
        let icons = iconPair(for: t, serverIcon: meta.icon)
        return Button {
            if t.requiresLogin && !session.isLoggedIn { router.showLogin = true; return }
            Haptics.light()
            router.select(t)
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: on ? icons.selected : icons.normal)
                        .font(.system(size: 21, weight: on ? .semibold : .regular))
                        .symbolRenderingMode(.hierarchical)
                        .frame(height: 26)
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1).background(Color.vPrimary, in: Capsule())
                            .offset(x: 10, y: -4)
                    }
                }
                Text(meta.title).font(.system(size: 10, weight: on ? .semibold : .medium))
            }
            .foregroundStyle(on ? Color.vPrimary : Color.vTextSecondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func publishButton(title: String) -> some View {
        Button {
            Haptics.medium()
            if !session.isLoggedIn { router.showLogin = true; return }
            router.openPublishFlow()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(VGradient.brand).frame(width: 50, height: 50)
                        .shadow(color: Color.vPrimary.opacity(0.4), radius: 10, y: 4)
                    Image(systemName: "plus").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                }
                .offset(y: -14)
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.vTextSecondary).offset(y: -12)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func iconPair(for tab: AppTab, serverIcon: String?) -> (normal: String, selected: String) {
        if let serverIcon, !serverIcon.isEmpty {
            return (serverIcon, serverIcon + ".fill")
        }
        switch tab {
        case .buy: return ("bag", "bag.fill")
        case .community: return ("person.3", "person.3.fill")
        case .home: return ("house", "house.fill")
        case .auctions: return ("flag.checkered", "flag.checkered")
        case .inbox: return ("bubble.left.and.bubble.right", "bubble.left.and.bubble.right.fill")
        case .me: return ("person", "person.fill")
        case .publish: return ("plus", "plus")
        }
    }
}
