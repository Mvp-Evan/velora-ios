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
            async let boot: () = session.bootstrap()
            async let minDelay: () = (try? Task.sleep(for: .seconds(0.9))) ?? ()
            _ = await (boot, minDelay)
            withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
        }
        .sheet(isPresented: $router.showLogin) {
            LoginView()
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
        case "auction_won": return "trophy.fill"
        case "lot_sold": return "checkmark.seal.fill"
        case "lot_unsold": return "xmark.circle.fill"
        default: return "bell.fill"
        }
    }
    private var tint: Color {
        switch notice.type {
        case "outbid": return .vPrimary
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
                Text("Velora").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
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
                case .home: HomeView()
                case .auctions: AuctionsView()
                case .publish: HomeView()
                case .messages: MessagesView()
                case .me: ProfileView()
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
            PublishView()
        }
        .sheet(item: Binding(get: { router.pendingLot.map(IDBox.init) }, set: { router.pendingLot = $0?.id })) { box in
            NavigationStack { LotDetailView(lotId: box.id) }
        }
        .sheet(item: Binding(get: { router.pendingOrder.map(IDBox.init) }, set: { router.pendingOrder = $0?.id })) { box in
            NavigationStack { OrderDetailView(orderId: box.id, presentedAsSheet: true) }
        }
    }
}

struct IDBox: Identifiable { let id: Int64 }

/// 自定义底栏：中间凸起的「发布」按钮
struct VTabBar: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            tab(.home, icon: "house", selectedIcon: "house.fill", title: "首页")
            tab(.auctions, icon: "flag.checkered", selectedIcon: "flag.checkered", title: "拍场")
            publishButton
            tab(.messages, icon: "bubble.left.and.bubble.right", selectedIcon: "bubble.left.and.bubble.right.fill", title: "消息", badge: session.unread)
            tab(.me, icon: "person", selectedIcon: "person.fill", title: "我的")
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

    private func tab(_ t: AppRouter.Tab, icon: String, selectedIcon: String, title: String, badge: Int = 0) -> some View {
        let on = router.tab == t
        return Button {
            if t != .home && t != .auctions && !session.isLoggedIn { router.showLogin = true; return }
            Haptics.light()
            router.select(t)
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: on ? selectedIcon : icon)
                        .font(.system(size: 21, weight: on ? .semibold : .regular))
                        .symbolRenderingMode(.hierarchical)
                        .frame(height: 26)
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1).background(Color.vPrimary, in: Capsule())
                            .offset(x: 10, y: -4)
                    }
                }
                Text(title).font(.system(size: 10, weight: on ? .semibold : .medium))
            }
            .foregroundStyle(on ? Color.vPrimary : Color.vTextSecondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var publishButton: some View {
        Button {
            Haptics.medium()
            if !session.isLoggedIn { router.showLogin = true; return }
            router.showPublish = true
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(VGradient.brand).frame(width: 50, height: 50)
                        .shadow(color: Color.vPrimary.opacity(0.4), radius: 10, y: 4)
                    Image(systemName: "plus").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                }
                .offset(y: -14)
                Text("发布").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.vTextSecondary).offset(y: -12)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
