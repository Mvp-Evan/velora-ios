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
                .onOpenURL { url in
                    if KYCCallbackRouter.handle(url) {
                        router.openKYCReturn()
                        return
                    }
                    if let link = BalancePayDeepLink.parse(url: url) {
                        router.openBalancePay(link)
                        return
                    }
                    _ = PaymentCallbackRouter.handle(url)
                }
                .onChange(of: session.bootstrap) { _, boot in
                    router.applyBootstrap(boot)
                }
                .onAppear { router.applyBootstrap(session.bootstrap) }
                .onReceive(NotificationCenter.default.publisher(for: .balancePayDeepLink)) { note in
                    if let url = note.object as? URL, let link = BalancePayDeepLink.parse(url: url) {
                        router.openBalancePay(link)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .notificationDeepLink)) { note in
                    if let link = note.object as? String {
                        _ = NotificationDeepLinkRouter.open(link, router: router)
                    }
                }
                .onChange(of: session.isLoggedIn) { _, loggedIn in
                    if loggedIn {
                        PushNotificationRegistrar.shared.start()
                    }
                }
                .task {
                    if session.isLoggedIn {
                        PushNotificationRegistrar.shared.start()
                    }
                }
        }
    }
}

/// 处理支付 SDK 的回调（支付宝 URL Scheme / 微信 Universal Link）+ APNs (D37)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PaymentServiceRegistry.registerSDKs()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushNotificationRegistrar.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushNotificationRegistrar.shared.handleRegistrationFailure(error)
        }
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if KYCCallbackRouter.handle(url) { return true }
        if BalancePayDeepLink.parse(url: url) != nil {
            NotificationCenter.default.post(name: .balancePayDeepLink, object: url)
            return true
        }
        return PaymentCallbackRouter.handle(url)
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL else { return false }
        if KYCCallbackRouter.handle(url) { return true }
        if BalancePayDeepLink.parse(url: url) != nil {
            NotificationCenter.default.post(name: .balancePayDeepLink, object: url)
            return true
        }
        return PaymentCallbackRouter.handle(url)
    }
}

extension Notification.Name {
    static let balancePayDeepLink = Notification.Name("velora.balancePayDeepLink")
    /// Credit threshold interstitial (DES-v1.3-12-02 / D40) — userInfo: code, score?, action?
    static let veloraCreditBlock = Notification.Name("velora.creditBlock")
}

/// 全局路由：底栏由 `/me/bootstrap` 的 `nav_schema.tabs[].key` 驱动（DES-v1.3-00-02）。
@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .home
    @Published private(set) var visibleTabs: [(tab: AppTab, meta: NavTab)] = NavSchema.legacyFallback.resolvedTabs
    @Published private(set) var publishActions: [PublishAction] = MeBootstrap.legacyFallback.publishActions
    @Published var pendingLot: Int64?
    @Published var pendingOrder: Int64?
    @Published var pendingListing: Int64?
    /// When opening a listing from an offer notification (N-09), load this offer for the seller card.
    @Published var pendingListingOfferId: Int64?
    /// Universal Link `/pay/balance/{id}` pending landing (DES-v1.3-06-03 / D25).
    @Published var pendingBalancePay: BalancePayDeepLink?
    @Published var showPublish = false
    @Published var showPublishActions = false
    /// Trade type for the open publish wizard (fixed / auction).
    @Published var publishTradeType: PublishTradeType = .auction
    @Published var showLogin = false
    /// Present real-name KYC (middleware `real_name_required` / deep link return).
    @Published var showRealName = false
    /// Present personal seller onboarding funnel.
    @Published var showSellerOnboarding = false
    /// Present sub-merchant progress (DES-v1.3-08-01 / D29).
    @Published var showSubMerchantProgress = false
    /// Credit threshold interstitial (DES-v1.3-12-02 / D40) — branch by `error.code`.
    @Published var creditBlock: CreditBlockInfo?
    /// 拍卖间等沉浸页隐藏底部 Tab
    @Published var hideTabBar = false
    /// 再点当前 Tab 时递增，强制对应 NavigationStack 回到根
    @Published var meStackID = UUID()
    @Published var messagesStackID = UUID()
    @Published var meMode: MeShellMode = .buyer

    func open(lot id: Int64) { pendingLot = id }
    func open(order id: Int64) { pendingOrder = id }
    func open(listing id: Int64, offerId: Int64? = nil) {
        pendingListingOfferId = offerId
        pendingListing = id
    }

    func openBalancePay(_ link: BalancePayDeepLink) {
        pendingBalancePay = link
        tab = .me
    }

    func openRealName() {
        showRealName = true
    }

    func openSellerOnboarding() {
        meMode = .seller
        tab = .me
        showSellerOnboarding = true
    }

    func openSubMerchantProgress() {
        meMode = .seller
        tab = .me
        showSubMerchantProgress = true
    }

    /// Present credit block by stable API `error.code` (never by message text).
    func presentCreditBlock(code: String?, score: Int? = nil, action: String = ReviewCreditCopy.defaultBlockedAction) {
        creditBlock = ReviewCreditLogic.creditBlock(fromCode: code, score: score, action: action)
    }

    func openMeCredit() {
        tab = .me
        creditBlock = nil
    }

    func openKYCReturn() {
        tab = .me
        showRealName = true
    }

    func applyBootstrap(_ boot: MeBootstrap?) {
        let schema = boot?.navSchema
        let resolved = (schema?.resolvedTabs).flatMap { $0.isEmpty ? nil : $0 } ?? NavSchema.legacyFallback.resolvedTabs
        visibleTabs = resolved
        publishActions = boot?.publishActions ?? MeBootstrap.legacyFallback.publishActions
        if !resolved.contains(where: { $0.tab == tab }) {
            tab = resolved.first(where: { $0.tab != .publish })?.tab ?? .home
        }
    }

    /// Primary browse tab after logout / deep-link home.
    var primaryBrowseTab: AppTab {
        if visibleTabs.contains(where: { $0.tab == .buy }) { return .buy }
        if visibleTabs.contains(where: { $0.tab == .home }) { return .home }
        return visibleTabs.first(where: { $0.tab != .publish })?.tab ?? .home
    }

    func selectPrimaryBrowse() { select(primaryBrowseTab) }

    func select(_ t: AppTab) {
        if tab == t {
            switch t {
            case .me: meStackID = UUID(); hideTabBar = false
            case .inbox: messagesStackID = UUID(); hideTabBar = false
            default: break
            }
        } else {
            tab = t
            hideTabBar = false
        }
    }

    /// Always surface the action sheet so RootView can run PUB-01 entry gates.
    func openPublishFlow() {
        let enabled = publishActions.filter(\.enabled)
        if enabled.isEmpty {
            // Phase 1 fallback: auction wizard; gate still runs in RootView if sheet empty.
            publishTradeType = .auction
            showPublish = true
            return
        }
        // Single or multi: confirmationDialog → handlePublishAction (gates + trade type).
        showPublishActions = true
    }

    func openPublish(action: PublishAction) {
        switch action.key {
        case "fixed":
            publishTradeType = .fixed
            showPublish = true
        case "auction":
            publishTradeType = .auction
            showPublish = true
        default:
            break
        }
    }
}

enum MeShellMode: String, Hashable {
    case buyer
    case seller
}
