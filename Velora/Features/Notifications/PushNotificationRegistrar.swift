import Foundation
import UIKit
import UserNotifications

/// APNs permission + token register (DES-v1.3-11-01 MSG-03 / D37).
/// Simulator-friendly: never crashes; uses a stable `sim.` token when APNs is unavailable.
@MainActor
final class PushNotificationRegistrar: NSObject {
    static let shared = PushNotificationRegistrar()

    private var lastRegisteredToken: String?
    private var started = false

    private override init() {
        super.init()
    }

    /// Call on cold start / after login. Safe on Simulator.
    func start() {
        guard !started else {
            Task { await registerIfPossible() }
            return
        }
        started = true
        UNUserNotificationCenter.current().delegate = self
        Task { await registerIfPossible() }
    }

    func registerIfPossible() async {
        guard SessionStore.shared.isLoggedIn else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let ok = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                if !ok {
                    #if DEBUG
                    print("[apns] permission denied — inbox unaffected")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[apns] auth error: \(error)")
                #endif
            }
        case .denied:
            break
        default:
            break
        }

        UIApplication.shared.registerForRemoteNotifications()

        // Simulator / unsigned builds often never call didRegister. Fall back after a short wait.
        try? await Task.sleep(nanoseconds: 800_000_000)
        if lastRegisteredToken == nil {
            await uploadToken(Self.simulatorFriendlyToken())
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await uploadToken(hex) }
    }

    func handleRegistrationFailure(_ error: Error) {
        #if DEBUG
        print("[apns] register failed (sim-ok): \(error.localizedDescription)")
        #endif
        Task { await uploadToken(Self.simulatorFriendlyToken()) }
    }

    /// Logout: DELETE current device token; other devices kept (design §5.8).
    func unregisterCurrentToken() async {
        let token = lastRegisteredToken ?? Self.cachedToken()
        lastRegisteredToken = nil
        Self.clearCachedToken()
        guard SessionStore.shared.isLoggedIn || token != nil else { return }
        // Best-effort; session may already be clearing.
        if let token, !token.isEmpty {
            try? await API.deletePushToken(token)
        }
    }

    private func uploadToken(_ token: String) async {
        guard SessionStore.shared.isLoggedIn else { return }
        guard !token.isEmpty else { return }
        if token == lastRegisteredToken { return }
        let bundleId = Bundle.main.bundleIdentifier ?? "com.velora.app"
        let body = PushTokenRegistration(
            platform: NotifyConfigDefaults.platformIOSAPNs,
            token: token,
            brand: "apple",
            bundleId: bundleId
        )
        guard body.isValidPlatform else { return }
        do {
            try await API.registerPushToken(body)
            lastRegisteredToken = token
            Self.cacheToken(token)
            #if DEBUG
            print("[apns] token registered (\(token.suffix(6)))")
            #endif
        } catch {
            #if DEBUG
            print("[apns] PUT push-tokens failed: \(error)")
            #endif
        }
    }

    /// Stable sim token so local backends can exercise PUT without real APNs.
    static func simulatorFriendlyToken() -> String {
        if let cached = cachedToken(), cached.hasPrefix("sim.") { return cached }
        #if targetEnvironment(simulator)
        return "sim.\(DeviceID.current.replacingOccurrences(of: "-", with: ""))"
        #else
        // Device without APNs callback yet — ephemeral placeholder until real token arrives.
        return "pending.\(DeviceID.current.replacingOccurrences(of: "-", with: "").prefix(16))"
        #endif
    }

    static func authorizationHint() async -> String {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch status {
        case .denied:
            return NotifyCopy.pushAuthDenied
        default:
            return ""
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static let cacheKey = "apns_device_token"

    private static func cacheToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: cacheKey)
    }

    private static func cachedToken() -> String? {
        UserDefaults.standard.string(forKey: cacheKey)
    }

    private static func clearCachedToken() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}

extension PushNotificationRegistrar: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Online users may still get WS; suppress banner noise when app is foreground unless trade.
        [.badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let deeplink = (userInfo["deeplink"] as? String)
            ?? (userInfo["aps"] as? [String: Any]).flatMap { $0["deeplink"] as? String }
        guard let deeplink, !deeplink.isEmpty else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .notificationDeepLink, object: deeplink)
        }
    }
}

extension Notification.Name {
    static let notificationDeepLink = Notification.Name("velora.notificationDeepLink")
}
