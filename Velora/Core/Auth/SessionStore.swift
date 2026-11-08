import Foundation
import SwiftUI
import Combine

/// 登录态、当前用户、未读数、bootstrap；全局单例注入 Environment
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var user: User?
    @Published private(set) var isLoggedIn: Bool
    @Published var unread: Int = 0
    @Published var bootstrapped = false
    /// Latest `/me/bootstrap` payload; nil until first successful fetch (UI uses legacy fallback).
    @Published private(set) var bootstrap: MeBootstrap?
    @Published private(set) var serverClock = ServerTimeClock()
    /// Cool-off deletion banner (ACC-07); set from login `deletion` or GET `/me/deletion`.
    @Published private(set) var deletion: AuthDeletionHint?
    /// Active restriction rows from GET `/me` (DES-v1.3-01-03 §5.7).
    @Published private(set) var restrictions: [AccountRestrictionItem] = []
    /// Full-screen gate after freeze / session kick (DES §9).
    @Published var accountGate: AccountGateNotice?

    /// Union of `users.status` + restriction flags for bid / publish UI.
    var accessFlags: AccountAccessFlags {
        AccountAccessFlags.resolve(status: user?.status, restrictions: restrictions)
    }

    private(set) var accessToken: String?
    private var refreshToken: String?
    private var bag = Set<AnyCancellable>()

    private enum K {
        static let access = "access_token"
        static let refresh = "refresh_token"
        static let user = "cached_user"
        static let bootstrap = "cached_me_bootstrap"
    }

    private init() {
        accessToken = KeychainStore.get(K.access)
        refreshToken = KeychainStore.get(K.refresh)
        isLoggedIn = accessToken != nil
        if let raw = UserDefaults.standard.data(forKey: K.user), let u = try? APIClient.decoder.decode(User.self, from: raw) { user = u }
        if let raw = UserDefaults.standard.data(forKey: K.bootstrap),
           let b = try? APIClient.decoder.decode(MeBootstrap.self, from: raw) {
            bootstrap = b
        }

        Task { [weak self] in
            await APIClient.shared.configure(
                tokenProvider: {
                    self?.tokenSnapshot
                },
                refreshHandler: {
                    guard let self else { return false }
                    return await self.performRefresh()
                })
        }
        tokenSnapshot = accessToken
    }

    /// 非隔离快照，供 APIClient 同步读取
    nonisolated(unsafe) private var tokenSnapshot: String?

    // MARK: Lifecycle

    func bootstrap() async {
        defer { bootstrapped = true }
        await refreshBootstrap()
        // Guests may subscribe to list card channels for viewership (DES-v1.3-02-03 AUC-16).
        WebSocketClient.shared.connect(token: accessToken)
        listenRealtimeEvents()
        guard isLoggedIn else { return }
        await refreshMe()
        await refreshDeletionStatus()
    }

    /// 全局监听新消息 + 会话吊销（DES-v1.3-01 `session_revoked`）
    private func listenRealtimeEvents() {
        bag.removeAll()
        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ev in
                guard let self else { return }
                if ev.type == AuthErrorCode.sessionRevokedEvent {
                    self.handleSessionRevoked()
                    return
                }
                if ev.type == "message_new" || ev.type == "notification" {
                    Task { await self.refreshMe() }
                }
            }
            .store(in: &bag)
    }

    func refreshBootstrap() async {
        do {
            let boot = try await API.meBootstrap()
            applyBootstrap(boot)
        } catch let e as APIError where e.authCode == .accountFrozen || e.restrictionCode == .accountFrozen {
            handleAccountFrozen(message: e.restrictionMessage)
        } catch {
            // Keep cached schema on failure; UI falls back to legacy five tabs if never loaded.
            #if DEBUG
            print("[session] bootstrap failed: \(error)")
            #endif
        }
    }

    private func applyBootstrap(_ boot: MeBootstrap) {
        bootstrap = boot
        if boot.serverTime > 0 {
            var clock = serverClock
            clock.applyHandshake(serverTimeMs: boot.serverTime)
            serverClock = clock
        }
        if let raw = try? APIClient.encoder.encode(boot) {
            UserDefaults.standard.set(raw, forKey: K.bootstrap)
        }
    }

    func refreshMe() async {
        guard isLoggedIn else { return }
        do {
            let me = try await API.me()
            applyMe(me)
        } catch let e as APIError where e.authCode == .accountFrozen || e.restrictionCode == .accountFrozen {
            handleAccountFrozen(message: e.restrictionMessage)
            return
        } catch {
            #if DEBUG
            print("[session] me failed: \(error)")
            #endif
        }
        await refreshBootstrap()
    }

    private func applyMe(_ me: API.MeResponse) {
        var u = me.user
        if let status = me.status, !status.isEmpty {
            u.status = status
        }
        user = u
        unread = me.unread
        restrictions = me.restrictions ?? []
        if u.isPendingDeletion, deletion == nil {
            deletion = AuthDeletionHint(status: "pending_deletion", executeAt: nil)
        }
        if let raw = try? APIClient.encoder.encode(u) { UserDefaults.standard.set(raw, forKey: K.user) }
    }

    func refreshDeletionStatus() async {
        guard isLoggedIn else { deletion = nil; return }
        if let status = try? await API.deletionStatus(), status.isPending {
            deletion = AuthDeletionHint(status: status.status, executeAt: status.executeAt)
        } else if user?.isPendingDeletion == true {
            deletion = AuthDeletionHint(status: "pending_deletion", executeAt: deletion?.executeAt)
        } else {
            deletion = nil
        }
    }

    func login(phone: String, code: String, inviteCode: String? = nil) async throws {
        let pair = try await API.login(phone: phone, code: code, inviteCode: inviteCode)
        apply(pair)
        await refreshMe()
        WebSocketClient.shared.connect(token: accessToken)
        listenRealtimeEvents()
        await refreshDeletionStatus()
        PushNotificationRegistrar.shared.start()
    }

    func logout() {
        Task { await PushNotificationRegistrar.shared.unregisterCurrentToken() }
        if let r = refreshToken { Task { await API.logout(r) } }
        clearLocalSession()
        Task { await refreshBootstrap() }
    }

    /// Overlay badge from `GET /notifications/unread` / WS `notification.unread` (design §5.7).
    func applyInboxCounters(_ counters: InboxCounters) {
        unread = NotifyLogic.badgeTotal(isLoggedIn: isLoggedIn, counters: counters)
    }

    /// Server kicked this device (freeze / refresh reuse / remote revoke).
    func handleSessionRevoked(message: String? = nil) {
        clearLocalSession()
        accountGate = AccountGateNotice(
            kind: .sessionRevoked,
            message: message?.isEmpty == false ? message! : "登录已失效，请重新登录"
        )
        Task { await refreshBootstrap() }
    }

    /// HTTP `account_frozen` — clear tokens and show frozen page (DES §9).
    func handleAccountFrozen(message: String, publicReason: String? = nil) {
        clearLocalSession()
        let msg = message.isEmpty ? RestrictionErrorCode.accountFrozen.fallbackMessage : message
        accountGate = AccountGateNotice(kind: .frozen, message: msg, publicReason: publicReason)
        Task { await refreshBootstrap() }
    }

    func dismissAccountGate() {
        accountGate = nil
    }

    func cancelAccountDeletion() async throws {
        try await API.cancelDeletion()
        deletion = nil
        if var u = user { u.status = "active"; update(user: u) }
        await refreshMe()
    }

    func noteDeletion(_ hint: AuthDeletionHint?) {
        deletion = hint
        if var u = user, let hint, hint.isPendingDeletion {
            u.status = hint.status
            update(user: u)
        }
    }

    func update(user: User) {
        self.user = user
        if let raw = try? APIClient.encoder.encode(user) { UserDefaults.standard.set(raw, forKey: K.user) }
    }

    /// Align countdown clock from feed / slots `server_time` (DES-v1.3-02 §5.1).
    func applyServerTimeMs(_ ms: Int64) {
        guard ms > 0 else { return }
        var clock = serverClock
        clock.applyHandshake(serverTimeMs: ms)
        serverClock = clock
    }

    // MARK: Tokens

    private func apply(_ pair: TokenPair) {
        accessToken = pair.accessToken
        refreshToken = pair.refreshToken
        tokenSnapshot = pair.accessToken
        KeychainStore.set(pair.accessToken, for: K.access)
        KeychainStore.set(pair.refreshToken, for: K.refresh)
        isLoggedIn = true
        update(user: pair.user)
        deletion = pair.deletion
        if pair.user.isPendingDeletion, deletion == nil {
            deletion = AuthDeletionHint(status: "pending_deletion", executeAt: nil)
        }
    }

    private func clearLocalSession() {
        accessToken = nil; refreshToken = nil; tokenSnapshot = nil
        KeychainStore.remove(K.access); KeychainStore.remove(K.refresh)
        UserDefaults.standard.removeObject(forKey: K.user)
        user = nil; unread = 0; deletion = nil; restrictions = []
        isLoggedIn = false
        bag.removeAll()
        WebSocketClient.shared.connect(token: nil)
    }

    private func performRefresh() async -> Bool {
        guard let r = refreshToken else { return false }
        do {
            let pair = try await API.refresh(r)
            apply(pair)
            WebSocketClient.shared.connect(token: accessToken)
            return true
        } catch let e as APIError {
            // Refresh reuse / revoked / frozen → clear session (DES-v1.3-01 §5.3 / §9)
            if e.authCode == .accountFrozen || e.restrictionCode == .accountFrozen {
                handleAccountFrozen(message: e.restrictionMessage)
                return false
            }
            if e.status == 401 || e.status == 400 || e.authCode?.clearsLocalSession == true {
                clearLocalSession()
                return false
            }
            return false
        } catch {
            return false
        }
    }
}
