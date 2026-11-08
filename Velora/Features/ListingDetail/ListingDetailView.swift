import SwiftUI

/// Unified product detail entry — auction / 直购 / 发售 templates (DES-v1.3-02-04 ITEM-01).
struct ListingDetailView: View {
    let listingId: Int64
    var lotId: Int64? = nil
    var preloadTradeType: String? = nil
    /// From N-09 / offer deeplink — used so sellers load the pending offer card (not buyer `/offers/mine`).
    var preferredOfferId: Int64? = nil

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ListingDetailModel

    @State private var imageIndex = 0
    @State private var showGallery = false
    @State private var showFlawGallery = false
    @State private var showCamera = false
    @State private var legalDoc: LegalDocument?
    @State private var chatConv: Conversation?
    @State private var showConfirmBuy = false
    @State private var showOfferCompose = false
    @State private var activeOfferCard: OfferCard?
    @State private var rejectOfferRoute: RejectOfferRoute?
    @State private var counterListingContext: CounterContext?
    @StateObject private var offerActions = OfferActionModel()
    @State private var payOrderId: Int64?
    @State private var openSpotReleaseId: Int64?
    @State private var openLotteryReleaseId: Int64?
    @State private var openPresaleReleaseId: Int64?
    /// ME-06: detail exposure clock for browse history (DES-v1.3-12-01).
    @State private var historyAppearedAt = Date()
    @State private var historySaveEnabled = true

    init(listingId: Int64, lotId: Int64? = nil, preloadTradeType: String? = nil, preferredOfferId: Int64? = nil) {
        self.listingId = listingId
        self.lotId = lotId
        self.preloadTradeType = preloadTradeType
        self.preferredOfferId = preferredOfferId
        _model = StateObject(wrappedValue: ListingDetailModel(listingId: listingId, preferredLotId: lotId))
    }

    var body: some View {
        Group {
            if let lid = resolvedAuctionLotId {
                LotDetailView(lotId: lid, listingId: listingId)
            } else {
                listingBody
            }
        }
        .task {
            historyAppearedAt = Date()
            if let settings = try? await API.meSettings() {
                historySaveEnabled = settings.saveBrowseHistory
            }
            await model.load()
            try? await Task.sleep(for: .seconds(MeConfigDefaults.historyExposureSec))
            await BrowseHistoryRecorder.recordIfNeeded(
                listingId: listingId,
                sellerId: model.detail?.sellerId,
                meId: session.user?.id,
                saveBrowseHistory: historySaveEnabled,
                isLoggedIn: session.isLoggedIn,
                appearedAt: historyAppearedAt
            )
        }
        .onChange(of: model.needsLogin) { _, need in
            if need {
                router.showLogin = true
                model.needsLogin = false
            }
        }
        .sheet(isPresented: $model.needsRealName) {
            NavigationStack { RealNameView() }
        }
        .sheet(item: $legalDoc) { LegalDocumentView(document: $0) }
        .sheet(item: $chatConv) { conv in
            NavigationStack { ChatView(conversation: conv, presentedAsSheet: true) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            SupplementCameraView(
                listingId: listingId,
                shooterId: session.user?.id ?? 0
            ) { data in
                Task { await model.uploadSupplement(jpegData: data) }
            }
        }
        .fullScreenCover(isPresented: $showGallery) {
            if let d = model.detail {
                GalleryView(images: d.galleryURLs, index: $imageIndex)
            }
        }
        .fullScreenCover(isPresented: $showFlawGallery) {
            if let d = model.detail {
                GalleryView(images: d.flawImageURLs, index: $imageIndex)
            }
        }
        .sheet(isPresented: $showConfirmBuy) {
            NavigationStack {
                ConfirmBuyView(
                    listingId: listingId,
                    source: .detail,
                    expectedPriceFen: model.detail?.price
                )
            }
        }
        .sheet(item: Binding(
            get: { openSpotReleaseId.map(IDBox.init) },
            set: { openSpotReleaseId = $0?.id }
        )) { box in
            NavigationStack {
                SpotReleaseDetailView(releaseId: box.id)
            }
        }
        .sheet(item: Binding(
            get: { openLotteryReleaseId.map(IDBox.init) },
            set: { openLotteryReleaseId = $0?.id }
        )) { box in
            NavigationStack {
                LotteryEnrollView(releaseId: box.id)
            }
        }
        .sheet(item: Binding(
            get: { openPresaleReleaseId.map(IDBox.init) },
            set: { openPresaleReleaseId = $0?.id }
        )) { box in
            NavigationStack {
                PresaleDepositView(releaseId: box.id)
            }
        }
        .sheet(isPresented: $showOfferCompose) {
            if let d = model.detail {
                OfferComposeSheet(
                    listingId: listingId,
                    listPriceFen: d.price,
                    title: d.title,
                    cover: d.galleryURLs.first,
                    minPriceFen: OfferLogic.minPriceFen(listPriceFen: d.price),
                    mode: .create
                ) { card in
                    activeOfferCard = card
                }
            }
        }
        // Nested `.sheet` over RootView's listing sheet often presents blank / undismissable.
        // Use fullScreenCover with non-optional item content instead.
        .fullScreenCover(item: $counterListingContext) { ctx in
            OfferComposeSheet(
                listingId: listingId,
                listPriceFen: ctx.listPrice,
                title: ctx.title,
                cover: ctx.cover,
                minPriceFen: ctx.minPrice,
                mode: .counter(offerId: ctx.offerId, asBuyer: ctx.asBuyer),
                round: ctx.round,
                buyerQuoteCount: ctx.buyerQuoteCount
            ) { card in
                activeOfferCard = card
                counterListingContext = nil
                Task { await refreshMyOffer() }
            }
        }
        .fullScreenCover(item: $rejectOfferRoute) { route in
            OfferRejectSheet(offerId: route.id) {
                activeOfferCard = nil
                rejectOfferRoute = nil
                Task { await refreshMyOffer() }
            }
        }
        .onChange(of: offerActions.needsLogin) { _, need in
            if need {
                router.showLogin = true
                offerActions.needsLogin = false
            }
        }
        .sheet(isPresented: $offerActions.needsRealName) {
            NavigationStack { RealNameView() }
        }
        .task(id: model.detail?.id) {
            await refreshMyOffer()
        }
    }

    private func refreshMyOffer() async {
        guard session.isLoggedIn, model.detail?.negotiable == true else { return }
        let offer: Offer?
        if model.isSeller {
            offer = await resolveSellerOffer()
        } else {
            offer = await offerActions.myOffer(listingId: listingId)
        }
        guard let offer, offer.status.isPending || offer.status == .accepted else {
            if model.isSeller { activeOfferCard = nil }
            return
        }
        let role: OfferRole = model.isSeller ? .seller : (offer.buyerId == session.user?.id ? .buyer : .seller)
        activeOfferCard = OfferCard(
            offerId: offer.id,
            listingId: offer.listingId,
            cover: model.detail?.galleryURLs.first,
            title: model.detail?.title,
            listPrice: offer.listingPriceSnapshot ?? model.detail?.price ?? offer.price,
            offerPrice: offer.price,
            expiresAt: offer.expiresAt,
            round: offer.round,
            status: offer.status,
            actions: OfferLogic.defaultActions(
                status: offer.status,
                role: role,
                buyerQuoteCount: offer.buyerQuoteCount ?? offer.round,
                hasOrder: offer.orderId != nil
            ),
            orderId: offer.orderId,
            payDeadline: offer.payDeadline,
            serverTime: offer.serverTime,
            minPrice: offer.resolvedMinPrice,
            buyerQuoteCount: offer.buyerQuoteCount
        )
    }

    /// Buyer `/offers/mine` never returns rows for the listing owner — use seller offer list.
    private func resolveSellerOffer() async -> Offer? {
        guard let page = try? await API.myOffers(role: .seller) else { return nil }
        if let preferredOfferId,
           let match = page.items.first(where: { $0.id == preferredOfferId }) {
            return match
        }
        return page.items.first {
            $0.listingId == listingId && ($0.status.isPending || $0.status == .accepted)
        }
    }

    /// Prefer nested lot from detail; fall back to route lotId for auction cards.
    private var resolvedAuctionLotId: Int64? {
        if let detail = model.detail {
            guard detail.template == .auction else { return nil }
            return detail.lotId ?? lotId
        }
        guard let lotId else { return nil }
        let auctionHint = preloadTradeType == "auction" || preloadTradeType == nil
        guard auctionHint else { return nil }
        switch model.state {
        case .idle, .loading, .failed:
            return lotId
        case .loaded:
            return nil
        }
    }

    @ViewBuilder private var listingBody: some View {
        ZStack(alignment: .bottom) {
            Color.vBackground.ignoresSafeArea()
            switch model.state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let m):
                failedBody(message: m)
            case .loaded:
                if let detail = model.detail {
                    scrollContent(detail)
                }
            }
            if let detail = model.detail {
                bottomBar(detail)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { router.hideTabBar = true }
        .onDisappear { router.hideTabBar = false }
    }

    /// Failed state still hides the system nav bar; keep an explicit back control so users can leave.
    private func failedBody(message: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                VIconButton(system: "chevron.left", tint: Color.vText, background: Color.vFill) {
                    dismiss()
                }
                Spacer()
            }
            .padding(.horizontal, VSpace.m)
            .padding(.top, 12)
            Spacer(minLength: 0)
            VErrorView(message: message) { Task { await model.load() } }
            Spacer(minLength: 0)
        }
    }

    private func scrollContent(_ detail: ListingDetail) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                hero(detail)
                VStack(spacing: VSpace.m) {
                    priceCard(detail)
                    titleCard(detail)
                    paramsCard(detail)
                    ConditionFlawSection(detail: detail) { idx in
                        imageIndex = idx
                        showFlawGallery = true
                    }
                    if let desc = detail.description, !desc.isEmpty {
                        VCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("商品描述").font(.vHeadline)
                                Text(desc).font(.vBody).foregroundStyle(Color.vTextSecondary).lineSpacing(5)
                            }
                        }
                    }
                    if let card = activeOfferCard {
                        OfferCardView(
                            card: card,
                            role: cardRole(card),
                            isActing: offerActions.busy,
                            // Seller / buyer CTAs pin to the floating bottom bar.
                            embedActions: false
                        )
                    } else if model.isSeller, detail.negotiable {
                        Text("暂无待处理报价")
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if detail.negotiable, detail.canPurchase {
                        Text(OfferCopy.emptyBuyer(minPriceFen: OfferLogic.minPriceFen(listPriceFen: detail.price)))
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    sellerPlaceholder(detail)
                    ListingQASection(model: model) { router.showLogin = true }
                    PhotoRequestSection(
                        model: model,
                        onRequireLogin: { router.showLogin = true },
                        onOpenCamera: { showCamera = true }
                    )
                    ListingRulesSection(snapshot: detail.rulesSnapshot) {
                        legalDoc = .auctionRules
                    }
                }
                .padding(.horizontal, VSpace.l)
                .padding(.top, VSpace.m)
                .padding(.bottom, 120)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) { navBar(detail) }
        .refreshable { await model.load() }
    }

    private func navBar(_ detail: ListingDetail) -> some View {
        HStack {
            VIconButton(system: "chevron.left", tint: .white, background: .black.opacity(0.35)) { dismiss() }
            Spacer()
            ShareLink(item: "毂毂：\(detail.title)") {
                Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(.black.opacity(0.35), in: Circle())
            }
        }
        .padding(.horizontal, VSpace.m)
        .padding(.top, 50)
    }

    private func hero(_ detail: ListingDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            let images = detail.galleryURLs
            VImageCarousel(images: images.isEmpty ? [""] : images, index: $imageIndex, height: 400) {
                showGallery = true
            }
            VGradient.imageScrim.frame(height: 140).frame(maxHeight: .infinity, alignment: .bottom).allowsHitTesting(false)
            HStack {
                FlawConditionTitleBadge(detail: detail)
                Spacer()
                if let v = detail.viewers {
                    Label("\(v)", systemImage: "eye").font(.vMicro).foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(VSpace.l)
            .allowsHitTesting(false)
        }
    }

    private func priceCard(_ detail: ListingDetail) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                switch detail.template {
                case .direct:
                    Text(detail.stock <= 0 ? "已售罄" : "标价").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    VPriceText(amount: detail.soldPricePublic ?? detail.price, size: 34)
                    HStack(spacing: 8) {
                        if detail.negotiable {
                            VTagChip(text: "可议价", tint: .vGold, background: Color.vGold.opacity(0.12))
                        }
                        if detail.freeShipping == true {
                            VTagChip(text: "包邮", tint: .vGreen, background: Color.vGreen.opacity(0.12))
                        }
                        if let sold = detail.soldCount {
                            Text("已售 \(sold)").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        }
                        Spacer()
                    }
                    if detail.conditionIncomplete {
                        Text("成色信息不完整，暂不可购买").font(.vCaption).foregroundStyle(Color.vPrimary)
                    } else if detail.stock <= 0 {
                        Text("已售罄").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    }
                case .release:
                    Text("发售").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    VPriceText(amount: detail.price, size: 34)
                    if let starts = detail.releaseStartsAt {
                        Text("开售 \(starts.shortText) · \(SpotReleaseCopy.serverTimeHint)")
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    } else if let status = detail.releaseStatus, !status.isEmpty {
                        Text(status).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    } else if detail.releaseId != nil {
                        Text("查看发售详情").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    } else {
                        Text("发售详情即将开放").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    }
                case .auction:
                    EmptyView()
                }
            }
        }
    }

    private func titleCard(_ detail: ListingDetail) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.s) {
                HStack(spacing: 8) {
                    FlawConditionTitleBadge(detail: detail)
                    Text(detail.title).font(.vTitle(19)).foregroundStyle(Color.vText)
                }
            }
        }
    }

    private func paramsCard(_ detail: ListingDetail) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text("商品参数").font(.vHeadline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    attr("品牌", detail.brand ?? "")
                    attr("系列", detail.series ?? "")
                    attr("车型", detail.model ?? "")
                    attr("比例", detail.scale ?? "")
                    attr("成色", detail.conditionLabel)
                    attr("类型", detail.template == .direct ? DirectZoneCopy.tradeTypeLabel : (detail.template == .release ? "发售" : "拍卖"))
                }
            }
        }
    }

    private func attr(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.vMicro).foregroundStyle(Color.vTextTertiary)
            Text(v.isEmpty ? "—" : v).font(.vBodyMedium).foregroundStyle(Color.vText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }

    private func sellerPlaceholder(_ detail: ListingDetail) -> some View {
        let badge = detail.sellerBadge
        let isProxy = badge == .proxyGold || badge == .proxyProbation
        let isBrand = badge == .brandOfficial
        return VCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("卖家").font(.vHeadline)
                    if isBrand {
                        NavigationLink {
                            BrandStoreView(brandId: detail.sellerId)
                        } label: {
                            HStack(spacing: 4) {
                                Text("品牌店铺").font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.vTextTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            UserProfileView(userId: detail.sellerId)
                        } label: {
                            HStack(spacing: 4) {
                                Text("卖家主页").font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.vTextTertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if let badge {
                        SellerBadgeChip(badge: badge)
                    }
                    if isProxy {
                        Text(ProxyAgentCopy.fulfillmentResponsibility)
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }
                    SellerCardMetricsLoader(userId: detail.sellerId)
                }
                Spacer()
                Button {
                    guard model.requireLogin() else { router.showLogin = true; return }
                    // Chat currently keyed by lot; skip when no lot.
                    ToastCenter.shared.show("私聊入口即将开放", .info)
                } label: {
                    Text("咨询").font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .overlay(Capsule().stroke(Color.vPrimary, lineWidth: 1))
                }
            }
        }
    }

    private func bottomBar(_ detail: ListingDetail) -> some View {
        HStack(spacing: 10) {
            if !model.isSeller {
                Button {
                    Task { await model.toggleFavorite() }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: detail.isFavorited ? "heart.fill" : "heart")
                            .font(.system(size: 18, weight: .medium))
                        Text(detail.isFavorited ? "已收藏" : "收藏").font(.vMicro)
                    }
                    .foregroundStyle(detail.isFavorited ? Color.vPrimary : Color.vTextSecondary)
                    .frame(width: 48, height: 44)
                }
            }

            switch detail.template {
            case .direct:
                if model.isSeller {
                    sellerDirectBottomBar
                } else if let card = activeOfferCard, !buyerOfferActions(for: card).isEmpty {
                    buyerOfferBottomBar(card)
                } else if detail.canPurchase {
                    if detail.negotiable {
                        VPrimaryButton(title: OfferCopy.entryTitle, style: .soft) {
                            guard model.requireLogin() else { router.showLogin = true; return }
                            let rn = session.bootstrap?.me?.realNameStatus ?? session.user?.realNameStatus
                            let realNameDone = rn == "verified" || rn == "passed"
                            let credit = session.bootstrap?.me?.creditScore ?? session.user?.creditScore ?? 0
                            if let gate = OfferLogic.offerGate(
                                isLoggedIn: true,
                                realNameDone: realNameDone,
                                creditScore: credit,
                                isRestricted: session.accessFlags.isFrozen || session.accessFlags.isBanBid,
                                isOwner: detail.sellerId == session.user?.id,
                                negotiable: detail.negotiable
                            ) {
                                if gate.opensRealName {
                                    model.needsRealName = true
                                }
                                ToastCenter.shared.show(gate.fallbackMessage, .info)
                                return
                            }
                            showOfferCompose = true
                        }
                    }
                    VPrimaryButton(title: DirectZoneCopy.buyNow) {
                        guard model.requireLogin() else { router.showLogin = true; return }
                        showConfirmBuy = true
                    }
                } else {
                    let soldOrOff = detail.status == "off_shelf" ? DirectZoneCopy.offShelf : DirectZoneCopy.soldOut
                    VPrimaryButton(
                        title: detail.conditionIncomplete ? "成色不完整" : soldOrOff,
                        style: .dark,
                        disabled: true
                    ) {}
                }
            case .release:
                VPrimaryButton(title: releaseCTATitle(detail.releaseMode)) {
                    if let rid = detail.releaseId {
                        switch (detail.releaseMode ?? "").lowercased() {
                        case "lottery":
                            openLotteryReleaseId = rid
                        case "presale":
                            openPresaleReleaseId = rid
                        default:
                            openSpotReleaseId = rid
                        }
                    } else {
                        ToastCenter.shared.show("发售详情暂不可用", .info)
                    }
                }
            case .auction:
                EmptyView()
            }
        }
        .padding(.horizontal, VSpace.l)
        .padding(.top, VSpace.m)
        .padding(.bottom, VSpace.s)
        .background(
            Color.vSurface.ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(Color.vSeparator).frame(height: 0.5) }
        )
    }

    /// Floating accept / reject / counter (or waiting hint) for the listing owner.
    @ViewBuilder private var sellerDirectBottomBar: some View {
        let actions = sellerOfferActions(for: activeOfferCard)
        if let card = activeOfferCard, !actions.isEmpty {
            HStack(spacing: 8) {
                ForEach(actions, id: \.rawValue) { action in
                    Button {
                        guard !offerActions.busy else { return }
                        Task { await handleOfferAction(action, card: card) }
                    } label: {
                        Text(offerActions.busy ? OfferCopy.pendingButton : action.title)
                            .font(.vCaptionMedium)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .foregroundStyle(action.isPrimary ? Color.white : Color.vText)
                            .background(
                                action.isPrimary ? Color.vPrimary : Color.vFill,
                                in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(offerActions.busy)
                }
            }
        } else if activeOfferCard != nil {
            Text("等待买家处理报价")
                .font(.vBodyMedium)
                .foregroundStyle(Color.vTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
        } else {
            Text("你的在售商品")
                .font(.vBodyMedium)
                .foregroundStyle(Color.vTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
        }
    }

    private func sellerOfferActions(for card: OfferCard?) -> [OfferCardAction] {
        guard let card else { return [] }
        if !card.actions.isEmpty { return card.actions }
        return OfferLogic.defaultActions(
            status: card.status ?? .pendingSeller,
            role: .seller,
            buyerQuoteCount: card.buyerQuoteCount ?? card.round,
            hasOrder: card.orderId != nil
        )
    }

    private func buyerOfferActions(for card: OfferCard) -> [OfferCardAction] {
        if !card.actions.isEmpty { return card.actions }
        return OfferLogic.defaultActions(
            status: card.status ?? .pendingSeller,
            role: .buyer,
            buyerQuoteCount: card.buyerQuoteCount ?? card.round,
            hasOrder: card.orderId != nil
        )
    }

    private func buyerOfferBottomBar(_ card: OfferCard) -> some View {
        let actions = buyerOfferActions(for: card)
        return HStack(spacing: 8) {
            ForEach(actions, id: \.rawValue) { action in
                Button {
                    guard !offerActions.busy else { return }
                    Task { await handleOfferAction(action, card: card) }
                } label: {
                    Text(offerActions.busy ? OfferCopy.pendingButton : action.title)
                        .font(.vCaptionMedium)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .foregroundStyle(action.isPrimary ? Color.white : Color.vText)
                        .background(
                            action.isPrimary ? Color.vPrimary : Color.vFill,
                            in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(offerActions.busy)
            }
        }
    }

    private func releaseCTATitle(_ mode: String?) -> String {
        switch (mode ?? "").lowercased() {
        case "lottery": return "前往抽签"
        case "presale": return "前往预售"
        default: return "前往发售"
        }
    }

    private func cardRole(_ card: OfferCard) -> OfferRole {
        if let detail = model.detail, detail.sellerId == session.user?.id {
            return .seller
        }
        _ = card
        return .buyer
    }

    private func handleOfferAction(_ action: OfferCardAction, card: OfferCard) async {
        switch action {
        case .accept:
            if let resp = await offerActions.acceptOffer(offerId: card.offerId) {
                payOrderId = resp.orderId
                router.open(order: resp.orderId)
                await refreshMyOffer()
            }
        case .reject:
            rejectOfferRoute = RejectOfferRoute(id: card.offerId)
        case .counter:
            guard let d = model.detail else { return }
            showOfferCompose = false
            counterListingContext = CounterContext(
                offerId: card.offerId,
                asBuyer: cardRole(card) == .buyer,
                listPrice: d.price,
                title: d.title,
                cover: d.galleryURLs.first,
                minPrice: card.minPrice ?? OfferLogic.minPriceFen(listPriceFen: d.price),
                round: card.round,
                buyerQuoteCount: card.buyerQuoteCount ?? card.round
            )
        case .cancel:
            if await offerActions.cancelOffer(offerId: card.offerId) {
                activeOfferCard = nil
                await refreshMyOffer()
            }
        case .pay:
            if let orderId = card.orderId {
                router.open(order: orderId)
            }
        }
    }
}

private struct RejectOfferRoute: Identifiable {
    let id: Int64
}

private struct CounterContext: Identifiable {
    var id: Int64 { offerId }
    let offerId: Int64
    let asBuyer: Bool
    let listPrice: Int64
    let title: String
    let cover: String?
    let minPrice: Int64
    let round: Int
    let buyerQuoteCount: Int
}
