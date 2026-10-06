import SwiftUI

@main
struct VeloraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SessionStore.shared
    @StateObject private var live = AuctionLiveStore.shared
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(live)
                .environmentObject(router)
                .toastHost()
                .tint(Color.vPrimary)
                .onOpenURL { url in PaymentCallbackRouter.handle(url) }
        }
    }
}

/// 处理支付 SDK 的回调（支付宝 URL Scheme / 微信 Universal Link）
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PaymentServiceRegistry.registerSDKs()
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        PaymentCallbackRouter.handle(url)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL else { return false }
        return PaymentCallbackRouter.handle(url)
    }
}

/// 全局路由：跨 Tab 跳转（如通知点击进入订单）
@MainActor
final class AppRouter: ObservableObject {
    enum Tab: Hashable { case home, auctions, publish, messages, me }
    @Published var tab: Tab = .home
    @Published var pendingLot: Int64?
    @Published var pendingOrder: Int64?
    @Published var showPublish = false
    @Published var showLogin = false
    /// 拍卖间等沉浸页隐藏底部 Tab
    @Published var hideTabBar = false

    func open(lot id: Int64) { pendingLot = id }
    func open(order id: Int64) { pendingOrder = id }
}
