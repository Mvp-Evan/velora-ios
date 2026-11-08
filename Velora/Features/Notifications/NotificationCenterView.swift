import SwiftUI
import Combine

/// Five-tab notification center (DES-v1.3-11-01 MSG-01 / D37).
/// Chat tab → conversations; other tabs → `/notifications?category=`.
struct NotificationCenterView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @State private var tab: InboxTab = .trade
    @State private var counters = InboxCounters.guestZero
    @State private var items: [InboxNotification] = []
    @State private var convs: [Conversation] = []
    @State private var state: LoadState = .idle
    @State private var marking = false
    @State private var refGoneMessage: String?
    @State private var bag = Set<AnyCancellable>()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                content
            }
            .background(Color.vBackground)
            .navigationTitle(NotifyCopy.centerTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if session.isLoggedIn {
                        NavigationLink { PushSettingsView() } label: {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .accessibilityLabel(NotifyCopy.pushSettingsTitle)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if session.isLoggedIn, counters.unreadTotal > 0 {
                        Button {
                            Task { await markAllRead() }
                        } label: {
                            Text(marking ? NotifyCopy.marking : NotifyCopy.markAllRead)
                                .font(.vCaptionMedium)
                        }
                        .disabled(marking)
                    }
                }
            }
            .refreshable { await reload(force: true) }
            .task {
                await reload(force: true)
                listenRealtime()
            }
            .alert(NotifyCopy.refGone, isPresented: Binding(
                get: { refGoneMessage != nil },
                set: { if !$0 { refGoneMessage = nil } }
            )) {
                Button(NotifyCopy.backToList) { refGoneMessage = nil }
            } message: {
                Text(refGoneMessage ?? "")
            }
        }
        .id(router.messagesStackID)
    }

    // MARK: Tabs

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InboxTab.allCases) { t in
                    tabChip(t)
                }
            }
            .padding(.horizontal, VSpace.l)
            .padding(.vertical, 10)
        }
        .background(Color.vBackground)
    }

    private func tabChip(_ t: InboxTab) -> some View {
        let selected = tab == t
        let badge = counters.unread(for: t)
        return Button {
            tab = t
            Task { await reload(force: false) }
        } label: {
            HStack(spacing: 6) {
                Text(t.displayLabel)
                    .font(.vCaptionMedium)
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(.vMicro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.vPrimary, in: Capsule())
                }
            }
            .foregroundStyle(selected ? Color.vPrimary : Color.vTextSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selected ? Color.vPrimary.opacity(0.12) : Color.vFill,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !session.isLoggedIn {
            VEmptyState(icon: "bell.slash", title: NotifyCopy.guestBlocked, message: "登录后同步五栏未读与推送")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch state {
            case .idle, .loading:
                VLoadingView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let m):
                VErrorView(message: m.isEmpty ? NotifyCopy.syncFailed : m) {
                    Task { await reload(force: true) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                if tab.usesConversationsAPI {
                    conversationsList
                } else {
                    notificationsList
                }
            }
        }
    }

    @ViewBuilder
    private var conversationsList: some View {
        if convs.isEmpty {
            VEmptyState(
                icon: InboxTab.chat.systemImage,
                title: NotifyCopy.emptyTitle,
                message: InboxTab.chat.emptyMessage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(convs) { c in
                            NavigationLink { ChatView(conversation: c) } label: {
                                ConversationRow(conv: c)
                            }
                            .buttonStyle(.plain)
                            if c.id != convs.last?.id { VDivider(inset: 76) }
                        }
                    }
                }
                .padding(VSpace.l)
                .padding(.bottom, 84)
            }
        }
    }

    @ViewBuilder
    private var notificationsList: some View {
        if items.isEmpty {
            VEmptyState(
                icon: tab.systemImage,
                title: NotifyCopy.emptyTitle,
                message: tab.emptyMessage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: VSpace.m) {
                    ForEach(items) { n in
                        Button {
                            Task { await openNotification(n) }
                        } label: {
                            notificationRow(n)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(VSpace.l)
                .padding(.bottom, 84)
            }
        }
    }

    private func notificationRow(_ n: InboxNotification) -> some View {
        VCard {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(n.isUnread ? Color.vPrimary : Color.vTextTertiary.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(n.title)
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    Text(n.body)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                        .lineLimit(2)
                    if let at = n.createdAt {
                        Text(at.relativeText)
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.vTextTertiary)
            }
        }
    }

    // MARK: Data

    private func listenRealtime() {
        bag.removeAll()
        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { ev in
                if ev.type == "notification" || ev.type == "message_new" || ev.type == "message_sent" {
                    Task { await reload(force: true) }
                }
            }
            .store(in: &bag)
    }

    private func reload(force: Bool) async {
        guard session.isLoggedIn else {
            counters = .guestZero
            items = []
            convs = []
            state = .loaded
            session.applyInboxCounters(.guestZero)
            return
        }
        if force || (items.isEmpty && convs.isEmpty) {
            if state != .loaded { state = .loading }
        }
        do {
            async let unreadTask = API.notificationUnread()
            if tab.usesConversationsAPI {
                async let convTask = API.conversations()
                counters = try await unreadTask
                convs = try await convTask
                items = []
            } else {
                let category = tab.apiCategory?.rawValue
                async let listTask = API.notifications(category: category)
                counters = try await unreadTask
                let page = try await listTask
                items = page.items
                convs = []
            }
            session.applyInboxCounters(counters)
            state = .loaded
        } catch {
            state = .failed((error as? APIError)?.message ?? NotifyCopy.syncFailed)
        }
    }

    private func markAllRead() async {
        marking = true
        defer { marking = false }
        do {
            if tab.usesConversationsAPI {
                try await API.markAllConversationsRead()
            } else if let cat = tab.apiCategory {
                _ = try await API.markNotificationsRead(
                    MarkNotificationsReadRequest(category: cat.rawValue)
                )
            } else {
                _ = try await API.markNotificationsRead(
                    MarkNotificationsReadRequest(all: true)
                )
            }
            counters = try await API.notificationUnread()
            session.applyInboxCounters(counters)
            await reload(force: true)
            Haptics.light()
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    private func openNotification(_ n: InboxNotification) async {
        // Mark read first (design §5.1 — browse ≠ read; tap writes).
        do {
            let resp = try await API.markNotificationsRead(
                MarkNotificationsReadRequest(ids: [n.id])
            )
            if let unread = resp.unread {
                counters = unread
                session.applyInboxCounters(unread)
            } else {
                counters = NotifyLogic.countersAfterMarking(counters, tab: n.inboxTab, all: false, decreasingBy: n.isUnread ? 1 : 0)
                session.applyInboxCounters(counters)
            }
            if let idx = items.firstIndex(where: { $0.id == n.id }) {
                items[idx].readAt = items[idx].readAt ?? Date()
            }
        } catch let e as APIError {
            if e.code == NotifyErrorCode.refGone.rawValue || NotifyErrorCode.normalize(e.code) == .refGone {
                refGoneMessage = e.message.isEmpty ? NotifyCopy.refGone : e.message
                return
            }
            // Still try deeplink on soft failures.
        } catch {
            // Continue to deeplink attempt.
        }

        // N-09 seed links use listings/{offer_id}; resolve via offer list when ref is offer.
        if n.refType == "offer", let offerId = Int64(n.refId ?? "") {
            if let listingId = await NotificationDeepLinkRouter.resolveOfferListingId(offerId) {
                router.open(listing: listingId, offerId: offerId)
                return
            }
        }

        guard let link = n.deeplink, !link.isEmpty else { return }
        if !NotifyLogic.isDeeplinkAllowed(link) {
            ToastCenter.shared.show("链接不可用", .error)
            return
        }
        if let handled = NotificationDeepLinkRouter.open(link, router: router), !handled {
            refGoneMessage = NotifyCopy.refGone
        }
    }
}

/// Lightweight deeplink → AppRouter (paddock43:// only).
enum NotificationDeepLinkRouter {
    /// Returns `false` when the target looks gone / unparseable; `nil` when URL invalid.
    @MainActor
    static func open(_ raw: String, router: AppRouter) -> Bool? {
        guard NotifyLogic.isDeeplinkAllowed(raw) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }

        let path: String
        if let scheme = url.scheme?.lowercased(), scheme == NotifyConfigDefaults.deeplinkScheme {
            // paddock43://lots/1  → host=lots, path=/1  OR paddock43:/lots/1
            let host = url.host ?? ""
            let rest = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            path = host.isEmpty ? rest : (rest.isEmpty ? host : "\(host)/\(rest)")
        } else {
            path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        let parts = path.split(separator: "/").map(String.init)
        guard let head = parts.first else { return false }

        switch head {
        case "lots", "lot":
            if let id = parts.dropFirst().first.flatMap({ Int64($0) }) {
                router.open(lot: id)
                router.select(.buy)
                return true
            }
        case "orders", "order":
            if let id = parts.dropFirst().first.flatMap({ Int64($0) }) {
                router.open(order: id)
                router.select(.me)
                return true
            }
        case "listings", "listing":
            if let id = parts.dropFirst().first.flatMap({ Int64($0) }) {
                router.open(listing: id)
                return true
            }
        case "offers", "offer":
            if let id = parts.dropFirst().first.flatMap({ Int64($0) }) {
                Task { @MainActor in
                    if let listingId = await resolveOfferListingId(id) {
                        router.open(listing: listingId)
                    } else {
                        ToastCenter.shared.show(NotifyCopy.refGone, .info)
                    }
                }
                return true
            }
        case "conversations", "conversation":
            router.select(.inbox)
            return true
        case "me":
            router.select(.me)
            return true
        case "pay":
            if parts.count >= 3, parts[1] == "balance", let id = Int64(parts[2]) {
                router.openBalancePay(BalancePayDeepLink(balanceOrderId: id, rawURL: url))
                return true
            }
            router.select(.me)
            return true
        case "releases", "release", "sessions", "session",
             "after-sales", "after_sales":
            // Surface in me / buy until dedicated routers land; still counts as handled.
            router.select(.buy)
            return true
        default:
            return false
        }
        return false
    }

    @MainActor
    static func resolveOfferListingId(_ offerId: Int64) async -> Int64? {
        for role in [OfferRole.seller, OfferRole.buyer] {
            if let page = try? await API.myOffers(role: role),
               let offer = page.items.first(where: { $0.id == offerId }) {
                return offer.listingId
            }
        }
        return nil
    }
}
