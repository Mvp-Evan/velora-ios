import SwiftUI
import Combine

struct MessagesView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var live: AuctionLiveStore
    @EnvironmentObject private var router: AppRouter
    @State private var convs: [Conversation] = []
    @State private var state: LoadState = .idle
    @State private var bag = Set<AnyCancellable>()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: VSpace.m) {
                    noticeCard
                    switch state {
                    case .idle, .loading: VLoadingView()
                    case .failed(let m): VErrorView(message: m) { Task { await load() } }
                    case .loaded:
                        if convs.isEmpty { VEmptyState(icon: "bubble.left.and.bubble.right", title: "暂无会话", message: "在拍品页点击「咨询」即可联系卖家") }
                        else {
                            VCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(convs) { c in
                                        NavigationLink { ChatView(conversation: c) } label: { ConversationRow(conv: c) }.buttonStyle(.plain)
                                        if c.id != convs.last?.id { VDivider(inset: 76) }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationTitle("消息")
            .refreshable { await load() }
            .task {
                await load()
                WebSocketClient.shared.events
                    .filter { $0.type == "message_new" || $0.type == "message_sent" }
                    .receive(on: DispatchQueue.main)
                    .sink { _ in Task { await load(); await session.refreshMe() } }
                    .store(in: &bag)
            }
        }
    }

    private var noticeCard: some View {
        NavigationLink { NoticeListView() } label: {
            VCard {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge.fill").font(.system(size: 18)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(VGradient.brand, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("拍卖通知").font(.vHeadline)
                        Text(live.noticeFeed.first?.message ?? "出价被超越、拍中、成交等实时提醒").font(.vCaption).foregroundStyle(Color.vTextSecondary).lineLimit(1)
                    }
                    Spacer()
                    if !live.noticeFeed.isEmpty {
                        Text("\(live.noticeFeed.count)").font(.vMicro).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Color.vPrimary, in: Capsule())
                    }
                    Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        if convs.isEmpty { state = .loading }
        do { convs = try await API.conversations(); state = .loaded }
        catch { state = .failed((error as? APIError)?.message ?? "加载失败") }
    }
}

struct ConversationRow: View {
    let conv: Conversation
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                VAvatar(url: conv.peer.avatar, size: 48)
                if let lot = conv.lot {
                    RemoteImage(lot.cover).frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.vSurface, lineWidth: 2)).offset(x: 4, y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conv.peer.nickname).font(.vBodyMedium)
                    Spacer()
                    Text(conv.lastMessageAt?.relativeText ?? "").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                }
                HStack {
                    Text(conv.lastMessage.isEmpty ? "[\(conv.lot?.title ?? "拍品")]" : conv.lastMessage).font(.vCaption).foregroundStyle(Color.vTextSecondary).lineLimit(1)
                    Spacer()
                    if conv.unread > 0 {
                        Text("\(conv.unread)").font(.vMicro).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Color.vPrimary, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, VSpace.l).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct NoticeListView: View {
    @EnvironmentObject private var live: AuctionLiveStore
    @EnvironmentObject private var router: AppRouter
    var body: some View {
        ScrollView {
            if live.noticeFeed.isEmpty { VEmptyState(icon: "bell", title: "暂无通知", message: "本次运行期间收到的实时拍卖通知会显示在这里") }
            else {
                LazyVStack(spacing: VSpace.m) {
                    ForEach(live.noticeFeed) { n in
                        Button { if let o = n.orderId { router.open(order: o) } else if let l = n.lotId { router.open(lot: l) } } label: {
                            VCard {
                                HStack(alignment: .top, spacing: 12) {
                                    Circle().fill(Color.vPrimary).frame(width: 8, height: 8).padding(.top, 6)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(n.title).font(.vBodyMedium)
                                        Text(n.message).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(VSpace.l)
            }
        }
        .background(Color.vBackground)
        .navigationTitle("拍卖通知")
        .navigationBarTitleDisplayMode(.inline)
    }
}
