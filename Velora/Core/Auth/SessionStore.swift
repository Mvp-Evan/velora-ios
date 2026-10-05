import Foundation
import SwiftUI

/// 登录态、当前用户、未读数；全局单例注入 Environment
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var user: User?
    @Published private(set) var isLoggedIn: Bool
    @Published var unread: Int = 0
    @Published var bootstrapped = false

    private(set) var accessToken: String?
    private var refreshToken: String?

    private enum K { static let access = "access_token"; static let refresh = "refresh_token"; static let user = "cached_user" }

    private init() {
        accessToken = KeychainStore.get(K.access)
        refreshToken = KeychainStore.get(K.refresh)
        isLoggedIn = accessToken != nil
        if let raw = UserDefaults.standard.data(forKey: K.user), let u = try? APIClient.decoder.decode(User.self, from: raw) { user = u }

        Task {
            await APIClient.shared.configure(
                tokenProvider: { [weak self] in
                    // tokenProvider is sync; read from a nonisolated snapshot
                    return self?.tokenSnapshot
                },
                refreshHandler: { [weak self] in
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
        guard isLoggedIn else { return }
        await refreshMe()
        WebSocketClient.shared.connect(token: accessToken)
    }

    func refreshMe() async {
        guard isLoggedIn else { return }
        if let me = try? await API.me() {
            user = me.user
            unread = me.unread
            if let raw = try? APIClient.encoder.encode(me.user) { UserDefaults.standard.set(raw, forKey: K.user) }
        }
    }

    func login(phone: String, code: String) async throws {
        let pair = try await API.login(phone: phone, code: code)
        apply(pair)
        await refreshMe()
        WebSocketClient.shared.connect(token: accessToken)
    }

    func logout() {
        if let r = refreshToken { Task { await API.logout(r) } }
        clear()
        WebSocketClient.shared.connect(token: nil)
    }

    func update(user: User) {
        self.user = user
        if let raw = try? APIClient.encoder.encode(user) { UserDefaults.standard.set(raw, forKey: K.user) }
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
    }

    private func clear() {
        accessToken = nil; refreshToken = nil; tokenSnapshot = nil
        KeychainStore.remove(K.access); KeychainStore.remove(K.refresh)
        UserDefaults.standard.removeObject(forKey: K.user)
        user = nil; unread = 0
        isLoggedIn = false
    }

    private func performRefresh() async -> Bool {
        guard let r = refreshToken else { return false }
        do {
            let pair = try await API.refresh(r)
            apply(pair)
            WebSocketClient.shared.connect(token: accessToken)
            return true
        } catch let e as APIError where e.status == 401 || e.status == 400 {
            clear()
            return false
        } catch {
            return false
        }
    }
}
