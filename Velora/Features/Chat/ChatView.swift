import SwiftUI
import Combine
import UIKit

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
    @StateObject private var offerActions = OfferActionModel()
    @State private var rejectOfferId: Int64?
    @State private var showOfferReject = false
    @State private var counterOfferCard: OfferCard?
    @State private var showCreateOffer = false
    @State private var interceptBanner: IMRiskBanner?
    @State private var warnBanner: IMRiskBanner?
    @State private var lastWarnCategory: RiskCategory?
    @State private var lastWarnAt: Date?
    @State private var muteUntil: Date?
    @State private var serverNowHint: Date?
    @State private var showReport = false
    @State private var showBlockConfirm = false
    @State private var showListingNav: ListingNavTarget?
    @State private var sessionRiskHint: String?
    /// Local N-23 merge pending cleared when opening this conversation (design §9).
    @State private var localPushCollapse: PushCollapseState?
    @FocusState private var focused: Bool

    private struct ListingNavTarget: Identifiable {
        let id: Int64
    }

    private let quickReplies = ["还在吗？", "可以小刀吗？", "有无盒卡？", "能多拍几张细节图吗？", "什么时候发货？"]

    private var composer: IMComposerState {
        IMRiskLogic.composerState(
            muteUntil: muteUntil,
            serverNow: serverNowHint,
            defaultPlaceholder: ChatCopy.composerPlaceholder
        )
    }

    private var muteBanner: IMRiskBanner? {
        guard let muteUntil, composer.mute == .muted else { return nil }
        return IMRiskLogic.muteBanner(until: muteUntil, serverNow: serverNowHint)
    }

    var body: some View {
        VStack(spacing: 0) {
            subjectBanner
            riskStrips
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !loaded { ProgressView().padding() }
                        else if messages.isEmpty {
                            Text(ChatCopy.emptyConversation)
                                .font(.vCaption)
                                .foregroundStyle(Color.vTextTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        }
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(RiskCopy.reportTitle) { showReport = true }
                    Button(RiskCopy.blockAction, role: .destructive) { showBlockConfirm = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .peerRiskActions(
            peerId: conversation.peer.id,
            peerName: conversation.peer.nickname,
            showReport: $showReport,
            showBlockConfirm: $showBlockConfirm
        )
        .onAppear {
            if !presentedAsSheet { router.hideTabBar = true }
        }
        .onDisappear {
            if !presentedAsSheet { router.hideTabBar = false }
        }
        .task {
            await load()
            WebSocketClient.shared.events
                .filter { $0.type == "message_new" || $0.type == "message_sent" }
                .receive(on: DispatchQueue.main)
                .sink { ev in handleIncoming(ev) }
                .store(in: &bag)
        }
        .sheet(isPresented: $showOfferReject) {
            if let id = rejectOfferId {
                OfferRejectSheet(offerId: id) {
                    Task { await load() }
                }
            }
        }
        .sheet(item: $counterOfferCard) { card in
            OfferComposeSheet(
                listingId: card.listingId ?? 0,
                listPriceFen: card.listPrice,
                title: card.title ?? "商品",
                cover: card.cover,
                minPriceFen: card.minPrice ?? OfferLogic.minPriceFen(listPriceFen: card.listPrice),
                mode: .counter(
                    offerId: card.offerId,
                    asBuyer: conversation.buyerId == session.user?.id
                ),
                round: card.round,
                buyerQuoteCount: card.buyerQuoteCount ?? card.round
            ) { _ in
                Task { await load() }
            }
        }
        .sheet(isPresented: $showCreateOffer) {
            if let lot = conversation.lot {
                OfferComposeSheet(
                    listingId: lot.id,
                    listPriceFen: lot.currentPrice,
                    title: lot.title,
                    cover: lot.cover,
                    minPriceFen: OfferLogic.minPriceFen(listPriceFen: lot.currentPrice),
                    mode: .create
                ) { _ in
                    interceptBanner = nil
                    Task { await load() }
                }
            }
        }
        .sheet(item: $showListingNav) { target in
            NavigationStack {
                ListingDetailView(listingId: target.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") { showListingNav = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var riskStrips: some View {
        VStack(spacing: 0) {
            if let muteBanner {
                IMRiskBannerView(banner: muteBanner)
            }
            // Session risk hint is not dismissible (design §9 / N-24).
            if let sessionRiskHint {
                ChatRiskStripView(text: sessionRiskHint) {
                    openTradeProtection()
                }
            } else if let warnBanner {
                IMRiskBannerView(banner: warnBanner)
            }
            if let interceptBanner {
                IMRiskBannerView(banner: interceptBanner) {
                    openOfferComposeFromIntercept()
                }
            }
        }
    }

    @ViewBuilder
    private var subjectBanner: some View {
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
        } else if conversation.resolvedSubjectType == .order, conversation.resolvedSubjectId > 0 {
            Button { router.open(order: conversation.resolvedSubjectId) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Color.vPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.s, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ChatCopy.orderCardTitle).font(.vCaptionMedium)
                        Text("订单 #\(conversation.resolvedSubjectId)")
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.vCaption).foregroundStyle(Color.vTextTertiary)
                }
                .padding(.horizontal, VSpace.l).padding(.vertical, 10)
                .background(Color.vSurface)
            }
            .buttonStyle(.plain)
        } else if conversation.resolvedSubjectType == .listing, conversation.resolvedSubjectId > 0 {
            Button { showListingNav = ListingNavTarget(id: conversation.resolvedSubjectId) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tag")
                        .foregroundStyle(Color.vPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.s, style: .continuous))
                    Text(ChatCopy.listingCardTitle).font(.vCaptionMedium)
                    Spacer()
                    Image(systemName: "chevron.right").font(.vCaption).foregroundStyle(Color.vTextTertiary)
                }
                .padding(.horizontal, VSpace.l).padding(.vertical, 10)
                .background(Color.vSurface)
            }
            .buttonStyle(.plain)
        }
    }

    private func bubble(_ m: Message) -> some View {
        let mine = m.senderId == session.user?.id
        let blockedDimmed = ChatLogic.senderBubbleDimmed(
            blocked: m.blocked == true,
            riskLevel: m.effectiveRiskAction == .block ? .block : (m.effectiveRiskAction == .warn ? .hint : ChatRiskLevel.none)
        )
        let centered = m.type == .system || m.type == .riskBanner
        return HStack(alignment: .bottom, spacing: 8) {
            if centered {
                EmptyView()
            } else if mine {
                Spacer(minLength: 60)
            } else {
                VAvatar(url: conversation.peer.avatar, size: 32)
            }
            Group {
                switch m.type {
                case .system:
                    Text(m.content.isEmpty ? ChatCopy.peerDeactivated : m.content)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.vFill, in: Capsule())
                case .riskBanner:
                    Text(m.content.isEmpty ? ChatCopy.riskHintBoth : m.content)
                        .font(.vMicro)
                        .foregroundStyle(Color(hex: 0x8A5A00))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(hex: 0xFFF6E0), in: Capsule())
                case .image:
                    let url = ChatCardParsing.image(from: m)?.url ?? m.content
                    RemoteImage(url)
                        .frame(width: 160, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                        .opacity(blockedDimmed && mine ? 0.55 : 1)
                case .listingCard:
                    if let card = ChatCardParsing.listing(from: m) {
                        ChatListingCardView(card: card) {
                            showListingNav = ListingNavTarget(id: card.listingId)
                        }
                    } else {
                        fallbackCardText(m.content.isEmpty ? ChatCopy.listingCardTitle : m.content)
                    }
                case .orderCard:
                    if let card = ChatCardParsing.order(from: m) {
                        ChatOrderCardView(card: card) {
                            router.open(order: card.orderId)
                        }
                    } else {
                        fallbackCardText(m.content.isEmpty ? ChatCopy.orderCardTitle : m.content)
                    }
                case .offerCard:
                    if let card = OfferCardParsing.from(message: m) {
                        OfferCardView(
                            card: card,
                            role: conversation.sellerId == session.user?.id ? .seller : .buyer,
                            isActing: offerActions.busy
                        ) { action in
                            Task { await handleOfferAction(action, card: card) }
                        }
                        .frame(maxWidth: 280)
                    } else {
                        fallbackCardText(m.content.isEmpty ? OfferCopy.accessibilityCard : m.content)
                    }
                case .text:
                    VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                        Text(m.content)
                            .font(.vBody)
                            .foregroundStyle(mine && !blockedDimmed ? .white : Color.vText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                mine
                                    ? AnyShapeStyle(blockedDimmed ? Color.vFillStrong : Color.vPrimary)
                                    : AnyShapeStyle(Color.vSurface),
                                in: UnevenRoundedRectangle(
                                    topLeadingRadius: 16,
                                    bottomLeadingRadius: mine ? 16 : 4,
                                    bottomTrailingRadius: mine ? 4 : 16,
                                    topTrailingRadius: 16,
                                    style: .continuous
                                )
                            )
                        if blockedDimmed && mine {
                            Text(ChatCopy.riskBlockedSender)
                                .font(.vMicro)
                                .foregroundStyle(Color.vTextTertiary)
                        } else if m.effectiveRiskAction == .warn, let notice = m.risk?.displayNotice, !notice.isEmpty {
                            Text(notice)
                                .font(.vMicro)
                                .foregroundStyle(Color(hex: 0x8A5A00))
                                .accessibilityLabel(IMRiskCopy.accessibilityRiskLabel)
                        }
                    }
                }
            }
            if centered {
                EmptyView()
            } else if !mine {
                Spacer(minLength: 60)
            } else {
                VAvatar(url: session.user?.avatar ?? "", size: 32)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: centered ? .center : (mine ? .trailing : .leading)
        )
    }

    private func fallbackCardText(_ text: String) -> some View {
        Text(text)
            .font(.vCaption)
            .foregroundStyle(Color.vTextSecondary)
            .padding(12)
            .frame(minHeight: CGFloat(ChatConfigDefaults.cardMinTapHeightPt), alignment: .center)
            .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if composer.isEnabled {
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
            }
            HStack(spacing: 10) {
                Button {
                    IMRiskImageScanPlaceholder.presentDisabledToast()
                } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.vTextTertiary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(IMRiskCopy.imageScanFeatureDisabled)
                .disabled(!composer.isEnabled)

                TextField(composer.placeholder, text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.vBody)
                    .focused($focused)
                    .disabled(!composer.isEnabled || sending)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.vFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .opacity(composer.isEnabled ? 1 : 0.7)

                Button(action: send) {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(text.isBlank || !composer.isEnabled ? Color.vFillStrong : Color.vPrimary, in: Circle())
                }
                .disabled(text.isBlank || sending || !composer.isEnabled)
            }
            .padding(.horizontal, VSpace.l)
            if !composer.isEnabled {
                Text(IMRiskCopy.mutedContactSupport)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VSpace.l)
            }
        }
        .padding(.vertical, 10)
        .background(Color.vSurface.ignoresSafeArea(edges: .bottom).overlay(alignment: .top) { Rectangle().fill(Color.vSeparator).frame(height: 0.5) })
    }

    private func load() async {
        messages = (try? await API.messages(conversation.id)) ?? []
        loaded = true
        await session.refreshMe()
        // N-23: opening conversation clears local merge pending (design §9).
        if var pending = localPushCollapse {
            pending = ChatLogic.clearLocalPending(pending)
            localPushCollapse = pending
        } else if let uid = session.user?.id {
            localPushCollapse = ChatLogic.clearLocalPending(
                PushCollapseState(conversationId: conversation.id, recipientId: uid)
            )
        }
        _ = try? await API.markConversationRead(conversation.id, lastMessageId: messages.last?.id)
        // Hydrate mute / session risk hint from recent messages.
        for m in messages where m.effectiveRiskAction == .warn {
            applyWarnBanner(from: m.risk)
        }
    }

    private func send() {
        guard composer.isEnabled else {
            if let muteUntil {
                interceptBanner = nil
                ToastCenter.shared.show(IMRiskLogic.muteBanner(until: muteUntil, serverNow: serverNowHint).text, .info)
            }
            return
        }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        if OfferLogic.looksLikePriceOfferText(content) {
            ToastCenter.shared.show(OfferCopy.chatGuide + " — " + OfferCopy.chatAmountHint, .info)
        } else if IMRiskLogic.looksLikePureAmount(content) {
            ToastCenter.shared.show(IMRiskCopy.pureAmountHint, .info)
        }
        // Keep draft until success so content_blocked / im_muted can restore (design §5.12 / §9).
        let draft = content
        text = ""
        sending = true
        interceptBanner = nil
        Task {
            defer { sending = false }
            do {
                let m = try await API.send(conversation.id, type: .text, content: draft)
                if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
                applyWarnBanner(from: m.risk)
            } catch {
                handleSendError(error, draft: draft)
            }
        }
    }

    private func handleSendError(_ error: Error, draft: String) {
        text = draft
        if let api = error as? APIError, let chatCode = ChatErrorCode.normalize(api.code) {
            switch chatCode {
            case .riskBlocked:
                interceptBanner = IMRiskLogic.interceptBanner(notice: api.message.isEmpty ? ChatCopy.riskBlockedSender : api.message)
                ToastCenter.shared.show(ChatCopy.riskBlockedSender, .error)
                return
            case .riskHint:
                sessionRiskHint = api.message.isEmpty ? ChatCopy.riskHintBoth : api.message
                return
            case .blockedByPeer:
                ToastCenter.shared.show(ChatCopy.blockedByPeer, .error)
                return
            case .realNameRequired:
                ToastCenter.shared.show(ChatCopy.realNameRequired, .info)
                router.openRealName()
                return
            case .muteUntil, .accountRestricted:
                ToastCenter.shared.show(chatCode.fallbackMessage, .info)
                return
            case .invalidMessageType, .orderCardForbidden, .invalidImage, .imageTooLarge:
                ToastCenter.shared.show(chatCode.fallbackMessage, .error)
                return
            default:
                break
            }
        }
        if let api = error as? APIError, let code = IMRiskErrorCode.normalize(api.code) {
            switch code {
            case .contentBlocked:
                interceptBanner = IMRiskLogic.interceptBanner(notice: api.message.isEmpty ? nil : api.message)
                ToastCenter.shared.show(IMRiskCopy.blockedNotice, .error)
            case .imMuted:
                let until = IMRiskLogic.parseMuteUntil(from: api.message) ?? muteUntil ?? Date().addingTimeInterval(TimeInterval(IMRiskConfigDefaults.muteHours * 3600))
                muteUntil = until
                serverNowHint = Date()
                interceptBanner = nil
                ToastCenter.shared.show(IMRiskLogic.muteBanner(until: until, serverNow: serverNowHint).text, .info)
            case .blockedByUser:
                ToastCenter.shared.show(ChatCopy.blockedByPeer, .error)
            case .contentReviewPending:
                ToastCenter.shared.show(code.fallbackMessage, .info)
            case .featureDisabled:
                ToastCenter.shared.show(IMRiskCopy.imageScanFeatureDisabled, .info)
            case .lexiconRegexInvalid:
                ToastCenter.shared.show(code.fallbackMessage, .error)
            }
            return
        }
        ToastCenter.shared.error(error)
    }

    private func applyWarnBanner(from risk: MessageRiskInfo?) {
        guard let risk, risk.action == .warn else { return }
        let notice = risk.displayNotice.isEmpty ? ChatCopy.riskHintBoth : risk.displayNotice
        // N-24 hint strip stays for the session — not dismissible (design §9).
        sessionRiskHint = notice
        let now = Date()
        guard IMRiskLogic.shouldShowWarnBanner(
            category: risk.category,
            lastShownCategory: lastWarnCategory,
            lastShownAt: lastWarnAt,
            now: now
        ) else { return }
        warnBanner = IMRiskLogic.warnBanner(notice: risk.notice, category: risk.category)
        lastWarnCategory = risk.category
        lastWarnAt = now
    }

    private func openTradeProtection() {
        if let url = URL(string: ChatConfigDefaults.brandProtectionURL) {
            UIApplication.shared.open(url)
        } else {
            ToastCenter.shared.show(ChatCopy.learnProtection, .info)
        }
    }

    private func openOfferComposeFromIntercept() {
        guard conversation.lot != nil else {
            ToastCenter.shared.show(IMRiskCopy.blockedCTA + " — " + IMRiskCopy.offerWhitelistHint, .info)
            return
        }
        showCreateOffer = true
    }

    private func handleOfferAction(_ action: OfferCardAction, card: OfferCard) async {
        switch action {
        case .accept:
            if let resp = await offerActions.acceptOffer(offerId: card.offerId) {
                router.open(order: resp.orderId)
                await load()
            }
        case .reject:
            rejectOfferId = card.offerId
            showOfferReject = true
        case .counter:
            counterOfferCard = card
        case .cancel:
            if await offerActions.cancelOffer(offerId: card.offerId) {
                await load()
            }
        case .pay:
            if let orderId = card.orderId {
                router.open(order: orderId)
            }
        }
    }

    private func handleIncoming(_ ev: WSEvent) {
        guard ev.int64("conversation_id") == conversation.id, let id = ev.int64("id") else { return }
        guard !messages.contains(where: { $0.id == id }) else { return }
        let kind = ChatMessageKind.normalize(ev.string("type")) ?? .text
        let type = MessageType(kind: kind)
        let riskAction = RiskAction.normalize(ev.string("risk_action"))
            ?? RiskAction.normalize(ev.string("risk_level"))
        let risk: MessageRiskInfo? = {
            guard let riskAction, riskAction != .none else { return nil }
            return MessageRiskInfo(
                action: riskAction,
                notice: ev.string("risk_notice"),
                category: RiskCategory.normalize(ev.string("risk_category"))
            )
        }()
        let m = Message(
            id: id,
            conversationId: conversation.id,
            senderId: ev.int64("sender_id") ?? 0,
            type: type,
            content: ev.string("content") ?? "",
            payload: nil,
            createdAt: ev.date("created_at") ?? Date(),
            risk: risk,
            blocked: ev.bool("blocked") ? true : nil,
            offerId: ev.int64("offer_id")
        )
        // Dropped / blocked rows must never appear for the peer (design §5.12 / N-24).
        let isPeer = m.senderId != session.user?.id
        if isPeer && (m.blocked == true || m.effectiveRiskAction == .block) { return }
        messages.append(m)
        applyWarnBanner(from: risk)
        if isPeer { Haptics.light() }
    }
}
