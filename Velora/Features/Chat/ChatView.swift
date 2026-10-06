import SwiftUI
import Combine

struct ChatView: View {
    let conversation: Conversation
    /// sheet 弹出时需要关闭按钮；NavigationLink 推入时用系统返回
    var presentedAsSheet = false
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [Message] = []
    @State private var text = ""
    @State private var sending = false
    @State private var loaded = false
    @State private var bag = Set<AnyCancellable>()
    @FocusState private var focused: Bool

    private let quickReplies = ["还在吗？", "可以小刀吗？", "有无盒卡？", "能多拍几张细节图吗？", "什么时候发货？"]

    var body: some View {
        VStack(spacing: 0) {
            lotBanner
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !loaded { ProgressView().padding() }
                        ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                            if i == 0 || m.createdAt.timeIntervalSince(messages[i - 1].createdAt) > 300 {
                                Text(m.createdAt.relativeText).font(.vMicro).foregroundStyle(Color.vTextTertiary).padding(.top, 6)
                            }
                            bubble(m).id(m.id)
                        }
                    }
                    .padding(VSpace.l)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onAppear { if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            inputBar
        }
        .background(Color.vBackground)
        .navigationTitle(conversation.peer.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            await load()
            WebSocketClient.shared.events
                .filter { $0.type == "message_new" || $0.type == "message_sent" }
                .receive(on: DispatchQueue.main)
                .sink { ev in handleIncoming(ev) }
                .store(in: &bag)
        }
    }

    private var lotBanner: some View {
        Group {
            if let lot = conversation.lot {
                Button { router.open(lot: lot.id) } label: {
                    HStack(spacing: 10) {
                        RemoteImage(lot.cover).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: VRadius.s, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lot.title).font(.vCaptionMedium).lineLimit(1)
                            HStack(spacing: 6) {
                                VPriceText(amount: lot.currentPrice, size: 14)
                                VStatusBadge(status: lot.status)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.vCaption).foregroundStyle(Color.vTextTertiary)
                    }
                    .padding(.horizontal, VSpace.l).padding(.vertical, 10)
                    .background(Color.vSurface)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bubble(_ m: Message) -> some View {
        let mine = m.senderId == session.user?.id
        return HStack(alignment: .bottom, spacing: 8) {
            if mine { Spacer(minLength: 60) } else { VAvatar(url: conversation.peer.avatar, size: 32) }
            Group {
                switch m.type {
                case .system:
                    Text(m.content).font(.vMicro).foregroundStyle(Color.vTextTertiary).padding(.horizontal, 10).padding(.vertical, 5).background(Color.vFill, in: Capsule())
                case .image:
                    RemoteImage(m.content).frame(width: 160, height: 160).clipShape(RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                default:
                    Text(m.content).font(.vBody).foregroundStyle(mine ? .white : Color.vText)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(mine ? AnyShapeStyle(VGradient.brand) : AnyShapeStyle(Color.vSurface),
                                    in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: mine ? 16 : 4, bottomTrailingRadius: mine ? 4 : 16, topTrailingRadius: 16, style: .continuous))
                }
            }
            if !mine { Spacer(minLength: 60) } else { VAvatar(url: session.user?.avatar ?? "", size: 32) }
        }
        .frame(maxWidth: .infinity, alignment: m.type == .system ? .center : (mine ? .trailing : .leading))
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickReplies, id: \.self) { q in
                        Button { text = q; send() } label: {
                            Text(q).font(.vCaption).foregroundStyle(Color.vText).padding(.horizontal, 12).padding(.vertical, 6).background(Color.vFill, in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, VSpace.l)
            }
            HStack(spacing: 10) {
                TextField("说点什么…", text: $text, axis: .vertical).lineLimit(1...4).font(.vBody).focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.vFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(text.isBlank ? Color.vFillStrong : Color.vPrimary, in: Circle())
                }
                .disabled(text.isBlank || sending)
            }
            .padding(.horizontal, VSpace.l)
        }
        .padding(.vertical, 10)
        .background(Color.vSurface.ignoresSafeArea(edges: .bottom).overlay(alignment: .top) { Rectangle().fill(Color.vSeparator).frame(height: 0.5) })
    }

    private func load() async {
        messages = (try? await API.messages(conversation.id)) ?? []
        loaded = true
        await session.refreshMe()
    }

    private func send() {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        text = ""
        sending = true
        Task {
            defer { sending = false }
            do {
                let m = try await API.send(conversation.id, type: .text, content: content)
                if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
            } catch { ToastCenter.shared.error(error); text = content }
        }
    }

    private func handleIncoming(_ ev: WSEvent) {
        guard ev.int64("conversation_id") == conversation.id, let id = ev.int64("id") else { return }
        guard !messages.contains(where: { $0.id == id }) else { return }
        let type = MessageType(rawValue: ev.string("type") ?? "text") ?? .text
        let m = Message(id: id, conversationId: conversation.id, senderId: ev.int64("sender_id") ?? 0, type: type,
                        content: ev.string("content") ?? "", payload: nil, createdAt: ev.date("created_at") ?? Date())
        messages.append(m)
        if m.senderId != session.user?.id { Haptics.light() }
    }
}
