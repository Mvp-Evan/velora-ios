import SwiftUI

/// 订单详情：待付款时即结算页（地址 + 费用明细 + 收银台）；其余状态显示时间线
struct OrderDetailView: View {
    let orderId: Int64
    /// sheet 弹出时需要关闭；NavigationLink 推入时用系统返回
    var presentedAsSheet = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: OrderModel
    @State private var showAddressPicker = false
    @State private var showCashier = false
    @State private var showShip = false
    @State private var showEvidence = false
    @State private var showUnboxGuide = false
    @State private var showUnboxEvidence = false
    @State private var unboxGuideShown = false
    @State private var showCancelUnshippedConfirm = false
    @State private var showAfterSaleApply = false
    @State private var showBountyReport = false
    @State private var showReviewSubmit = false
    @State private var result: PaymentResult?
    @State private var chatConv: Conversation?

    init(orderId: Int64, presentedAsSheet: Bool = false) {
        self.orderId = orderId
        self.presentedAsSheet = presentedAsSheet
        _model = StateObject(wrappedValue: OrderModel(orderId: orderId))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading: VLoadingView()
            case .failed(let m): VErrorView(message: m) { Task { await model.load() } }
            case .loaded:
                if let o = model.order {
                    ScrollView {
                        VStack(spacing: VSpace.m) {
                            statusHeader(o)
                            if o.status == .pendingPayment && !o.isSeller {
                                NavigationLink {
                                    AuctionWonView(orderId: o.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "trophy.fill").foregroundStyle(Color.vGold)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(AuctionSettlementCopy.wonTitle).font(.vBodyMedium)
                                            Text(AuctionSettlementCopy.priceLocked).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary)
                                    }
                                    .padding(14)
                                    .background(Color.vGold.opacity(0.12), in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            if o.status == .cancelled && !o.isSeller {
                                NavigationLink {
                                    AuctionDefaultView(orderId: o.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.vPrimary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(AuctionSettlementCopy.defaultBuyerTitle).font(.vBodyMedium)
                                            Text(AuctionSettlementCopy.defaultBuyerHint).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary)
                                    }
                                    .padding(14)
                                    .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            if o.status == .cancelled && o.isSeller {
                                NavigationLink {
                                    AuctionDefaultView(orderId: o.id)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "banknote").foregroundStyle(Color.vGreen)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(AuctionSettlementCopy.defaultSellerTitle).font(.vBodyMedium)
                                            Text(AuctionSettlementCopy.defaultSellerDepositHint).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary)
                                    }
                                    .padding(14)
                                    .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            if o.canEditAddress || o.hasAddress { addressCard(o) }
                            lotCard(o)
                            feeCard(o)
                            if o.status == .pendingPayment && !o.isSeller {
                                Text(OrderCenterCopy.priceLocked)
                                    .font(.vCaption)
                                    .foregroundStyle(Color.vTextTertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                            }
                            if o.status == .shipped || (o.trackingNo != nil && !(o.trackingNo ?? "").isEmpty) {
                                trackingCard(o)
                            }
                            if !model.refunds.isEmpty && !o.isSeller {
                                ForEach(model.refunds) { r in
                                    RefundProgressView(progress: r)
                                }
                            }
                            afterSaleEntry(o)
                            bountyReportEntry(o)
                            reviewSection(o)
                            if o.status != .pendingPayment { timelineCard(o) }
                            infoCard(o)
                        }
                        .padding(VSpace.l)
                    }
                    .refreshable { await model.load(); await model.loadTracking() }
                    .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(o) }
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(model.order?.isSeller == true ? "卖出订单" : "订单详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onAppear { if !presentedAsSheet { router.hideTabBar = true } }
        .onDisappear { if !presentedAsSheet { router.hideTabBar = false } }
        .task {
            await model.load()
            await model.loadTracking()
            await model.loadReviews()
        }
        .sheet(isPresented: $showReviewSubmit) {
            ReviewSubmitView(orderId: orderId) {
                Task {
                    await model.loadReviews()
                    await model.load()
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            ShipmentCopy.cancelUnshippedConfirm,
            isPresented: $showCancelUnshippedConfirm,
            titleVisibility: .visible
        ) {
            Button(ShipmentCopy.cancelUnshippedCTA, role: .destructive) {
                Task { await model.cancelUnshipped() }
            }
            Button("再想想", role: .cancel) {}
        }
        .sheet(isPresented: $showAddressPicker) {
            AddressListView(selecting: true) { addr in
                Task { await model.setAddress(addr) }
            }
        }
        .sheet(isPresented: $showCashier) {
            if let o = model.order {
                CashierSheet(order: o) { r in
                    showCashier = false
                    result = r
                    Task { await model.load(); await session.refreshMe() }
                }
                .presentationDetents([.height(460)]).presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showShip) {
            if let o = model.order {
                ShipSheet(
                    order: o,
                    sellerType: session.bootstrap?.seller?.sellerType ?? session.bootstrap?.me?.sellerType,
                    onOpenEvidence: { showShip = false; showEvidence = true }
                ) { Task { await model.load() } }
                    .presentationDetents([.medium, .large])
            }
        }
        .fullScreenCover(isPresented: $showEvidence) {
            if let o = model.order {
                EvidenceCaptureView(
                    orderId: o.id,
                    orderNo: o.orderNo,
                    kindGroup: .ship,
                    amountFen: o.displayAmount,
                    sellerType: session.bootstrap?.seller?.sellerType ?? session.bootstrap?.me?.sellerType
                ) {
                    Task { await model.load() }
                }
            }
        }
        .sheet(isPresented: $showUnboxGuide) {
            if let o = model.order {
                UnboxVideoGuideSheet(
                    orderId: o.id,
                    orderNo: o.orderNo,
                    onSkip: {
                        unboxGuideShown = true
                        UserDefaults.standard.set(true, forKey: "unbox_guide_skipped_\(o.id)")
                    },
                    onRecord: {
                        unboxGuideShown = true
                        showUnboxEvidence = true
                    }
                )
                .presentationDetents([.height(320)])
            }
        }
        .fullScreenCover(isPresented: $showUnboxEvidence) {
            if let o = model.order {
                EvidenceCaptureView(
                    orderId: o.id,
                    orderNo: o.orderNo,
                    kindGroup: .unbox,
                    amountFen: o.displayAmount
                )
            }
        }
        .sheet(isPresented: $showAfterSaleApply) {
            if let o = model.order {
                NavigationStack {
                    AfterSaleApplyView(
                        orderId: o.id,
                        orderStatus: o.status.rawValue,
                        afterSaleStatus: o.afterSaleStatus.rawValue,
                        signedAt: o.completedAt,
                        shipDeadline: o.shipDeadline,
                        remainingPayableCents: max(0, o.displayAmount - o.refundedAmount),
                        unboxPhotoCount: 0,
                        isRealNamed: session.user?.realNameStatus == "verified" || session.user?.realNameStatus == "passed",
                        accountRestricted: session.user?.isFrozen == true
                    ) { _ in
                        showAfterSaleApply = false
                        Task { await model.load() }
                    }
                }
            }
        }
        .sheet(isPresented: $showBountyReport) {
            if let o = model.order {
                ReportSheetView(
                    targetType: .sellerOffline,
                    targetId: o.sellerId,
                    orderId: o.id,
                    isOrderBuyer: !o.isSeller,
                    peerName: o.seller.nickname
                )
            }
        }
        .sheet(item: $result) { r in PaymentResultView(result: r, order: model.order) { result = nil } }
        .sheet(item: $chatConv) { c in NavigationStack { ChatView(conversation: c, presentedAsSheet: true) } }
        .onChange(of: model.order?.status) { _, status in
            guard status == .shipped, let o = model.order, !o.isSeller else { return }
            let key = "unbox_guide_skipped_\(o.id)"
            if !UserDefaults.standard.bool(forKey: key), !unboxGuideShown {
                unboxGuideShown = true
                showUnboxGuide = true
            }
        }
    }

    // MARK: Sections

    private func statusHeader(_ o: Order) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous).fill(headerGradient(o))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(statusTitle(o)).font(.vTitle(22)).foregroundStyle(.white)
                        if let badge = o.afterSaleBadge.label {
                            Text(badge)
                                .font(.vMicro)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.22), in: Capsule())
                        }
                    }
                    Text(o.tradeType.displayLabel).font(.vCaption).foregroundStyle(.white.opacity(0.75))
                    ForEach(statusLines(o), id: \.self) { line in
                        Text(line).font(.vCaption).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                    }
                    if o.status == .pendingPayment && !o.isSeller {
                        let remain = payRemain(o)
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                            Text("剩余 ").font(.vCaption) + Text(OrderLogic.formatCountdown(remain)).font(.vMono(13))
                        }
                        .foregroundStyle(.white).padding(.top, 4)
                        Text(OrderCenterCopy.serverTimeHint)
                            .font(.vMicro)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if o.status == .shipped && !o.isSeller {
                        let remain = confirmRemain(o)
                        let paused = ShipmentLogic.isConfirmPaused(o.confirmPauseState)
                        HStack(spacing: 4) {
                            Image(systemName: paused ? "pause.circle" : "timer")
                            Text(paused ? ShipmentCopy.confirmPausedHint : "\(ShipmentCopy.autoConfirmPrefix) ")
                                .font(.vCaption)
                            if !paused {
                                Text(OrderLogic.formatCountdown(remain)).font(.vMono(13))
                            }
                        }
                        .foregroundStyle(.white).padding(.top, 4)
                        Text(ShipmentCopy.serverTimeHint)
                            .font(.vMicro)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if let merge = o.mergeShipLabel {
                        Text(merge)
                            .font(.vCaption)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: statusIcon(o)).font(.system(size: 44, weight: .light)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(VSpace.xl)
        }
        .frame(minHeight: 120)
    }

    @ObservedObject private var ticker = Ticker.shared
    private func payRemain(_ o: Order) -> Int {
        OrderLogic.payRemainSeconds(
            deadline: o.payDeadline,
            serverRemainSec: o.payRemainSec,
            serverTime: model.serverTime ?? o.serverTime,
            fetchedAtLocal: model.fetchedAt,
            nowLocal: ticker.now
        )
    }

    private func confirmRemain(_ o: Order) -> Int {
        ShipmentLogic.confirmRemainSeconds(
            state: o.confirmPauseState,
            serverTime: model.serverTime ?? o.serverTime,
            fetchedAtLocal: model.fetchedAt,
            nowLocal: ticker.now
        )
    }

    private func canCancelUnshipped(_ o: Order) -> Bool {
        guard !o.isSeller, o.status == .paid, let deadline = o.shipDeadline else { return false }
        let serverNow: Date = {
            if let st = model.serverTime ?? o.serverTime {
                let elapsed = max(0, ticker.now.timeIntervalSince(model.fetchedAt))
                return st.addingTimeInterval(elapsed)
            }
            return ticker.now
        }()
        return ShipmentLogic.canCancelUnshipped(
            status: o.status.rawValue,
            shipDeadline: deadline,
            now: serverNow
        )
    }

    private func trackingCard(_ o: Order) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text("物流轨迹").font(.vHeadline)
                    Spacer()
                    if let label = o.mergeShipLabel {
                        Text(label).font(.vMicro).foregroundStyle(Color.vBlue)
                    }
                }
                if let c = o.shippingCarrier, !c.isEmpty {
                    HStack {
                        Image(systemName: "shippingbox").foregroundStyle(Color.vBlue)
                        Text("\(c)  \(o.trackingNo ?? "")").font(.vMono(13))
                        Spacer()
                        Button("复制") {
                            UIPasteboard.general.string = o.trackingNo
                            ToastCenter.shared.show("已复制单号", .success)
                        }.font(.vCaption)
                    }
                }
                if let cancelled = model.tracking?.memberCancelledOrderNos, !cancelled.isEmpty {
                    Text("\(ShipmentCopy.partialCancelledHint)：\(cancelled.joined(separator: "、"))")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
                if let tracking = model.tracking {
                    let events = tracking.eventsNewestFirst
                    if events.isEmpty {
                        Text(tracking.showsExceptionEmpty ? ShipmentCopy.trackingExceptionEmpty : ShipmentCopy.trackingEmpty)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    } else {
                        ForEach(Array(events.enumerated()), id: \.element.id) { i, ev in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 0) {
                                    Circle().fill(i == 0 ? Color.vPrimary : Color.vFillStrong).frame(width: 8, height: 8)
                                    if i < events.count - 1 {
                                        Rectangle().fill(Color.vSeparator).frame(width: 1.5).frame(minHeight: 24)
                                    }
                                }
                                .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ev.description).font(i == 0 ? .vBodyMedium : .vBody)
                                        .foregroundStyle(i == 0 ? Color.vText : Color.vTextSecondary)
                                    if let loc = ev.location, !loc.isEmpty {
                                        Text(loc).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                                    }
                                    Text(ev.occurredAt.fullText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                                }
                            }
                        }
                    }
                    if let synced = tracking.trackSyncedAt {
                        Text("\(ShipmentCopy.trackingUpdatedPrefix) \(synced.fullText)")
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }
                } else if model.trackingLoading {
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                } else if let c = o.shippingCarrier, !c.isEmpty {
                    Text(ShipmentCopy.trackingEmpty)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
            }
        }
    }

    private func addressCard(_ o: Order) -> some View {
        let editable = o.canEditAddress
        return Button {
            if editable { showAddressPicker = true }
            else if o.status == .shipped || o.status == .completed || o.status == .settled {
                ToastCenter.shared.show(OrderCenterCopy.addressLocked, .info)
            }
        } label: {
            VCard {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill").foregroundStyle(Color.vPrimary).frame(width: 30, height: 30).background(Color.vPrimarySoft, in: Circle())
                    if o.hasAddress, let a = o.resolvedAddress {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(a.name ?? "").font(.vHeadline)
                                Text(a.phone ?? "").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                            }
                            Text(o.addressLine).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                            if editable {
                                Text("发货前可修改").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                            }
                        }
                    } else {
                        Text(OrderCenterCopy.needAddressBanner).font(.vBodyMedium).foregroundStyle(Color.vPrimary)
                    }
                    Spacer()
                    if editable { Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary) }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!editable && o.hasAddress)
    }

    private func lotCard(_ o: Order) -> some View {
        VCard {
            HStack(spacing: 12) {
                RemoteImage(o.displayCover).frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(o.displayTitle).font(.vBodyMedium).lineLimit(2)
                    HStack(spacing: 4) {
                        if let s = o.lot?.scale ?? o.itemSnapshot?.scale, !s.isEmpty { VTagChip(text: s) }
                        if let b = o.lot?.brand ?? o.itemSnapshot?.brand, !b.isEmpty { VTagChip(text: b) }
                    }
                    HStack {
                        Text("成交价").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        Spacer()
                        VPriceText(amount: o.displayAmount, size: 16, color: .vText)
                    }
                }
            }
        }
    }

    private func feeCard(_ o: Order) -> some View {
        VCard {
            VStack(spacing: 10) {
                if o.isSeller {
                    VKeyValue(key: "成交价", value: o.displayAmount.display)
                    let fee = o.platformFee ?? o.sellerCommission
                    VKeyValue(key: "平台服务费", value: "-\(fee.display)", valueColor: .vTextSecondary)
                    Rectangle().fill(Color.vSeparator).frame(height: 0.5)
                    VKeyValue(key: (o.status == .completed || o.status == .settled) ? "已入账" : "预计入账", value: o.sellerNet.display, valueColor: .vPrimary, bold: true)
                    if o.status == .completed || o.status == .settled {
                        VKeyValue(
                            key: "分账状态",
                            value: o.status == .settled
                                ? ProfitShareStatus.succeeded.sellerLabel
                                : ProfitShareStatus.processing.sellerLabel,
                            valueColor: .vTextSecondary
                        )
                    }
                    Text("买家确认收货后按快照分账；部分成功时仍显示「结算中」。").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                } else {
                    VKeyValue(key: "成交价", value: o.displayAmount.display)
                    VKeyValue(key: "买家佣金", value: o.buyerPremium == 0 ? "免佣" : o.buyerPremium.display, valueColor: o.buyerPremium == 0 ? .vGreen : .vText)
                    if let ship = o.shippingFee, ship > 0 {
                        VKeyValue(key: "运费", value: ship.display)
                    } else {
                        VKeyValue(key: "运费", value: "卖家承担", valueColor: .vGreen)
                    }
                    Rectangle().fill(Color.vSeparator).frame(height: 0.5)
                    VKeyValue(key: o.status == .pendingPayment ? "应付" : "实付", value: o.payAmount.display, valueColor: .vPrimary, bold: true)
                    if o.depositApplied > 0 {
                        VKeyValue(key: "押金抵扣", value: "-\(o.depositApplied.display)", valueColor: .vTextSecondary)
                        VKeyValue(key: "订单总额", value: o.buyerTotal.display, valueColor: .vTextSecondary)
                        Text(OrderCenterCopy.depositSeparate).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                    }
                    if o.refundedAmount > 0 {
                        VKeyValue(key: "已退金额", value: o.refundedAmount.display, valueColor: .vTextSecondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func afterSaleEntry(_ o: Order) -> some View {
        let canApply: Bool = {
            guard o.afterSaleStatus == .none else { return false }
            switch o.status {
            case .shipped, .completed, .refunded: return true
            case .paid: return true // not_received when overdue — server validates
            default: return false
            }
        }()
        if o.afterSaleStatus == .processing || o.afterSaleStatus == .closed {
            NavigationLink {
                AfterSaleDetailView(orderId: o.id, isSeller: o.isSeller)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "building.columns.fill").foregroundStyle(Color.vGold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(o.afterSaleStatus == .processing ? OrderCenterCopy.afterSaleProcessing : AfterSaleCopy.detailTitle)
                            .font(.vBodyMedium)
                        Text(AfterSaleCopy.courtTitle)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary)
                }
                .padding(14)
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            }
            .buttonStyle(.plain)
        } else if canApply && !o.isSeller {
            Button {
                showAfterSaleApply = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "wrench.and.screwdriver").foregroundStyle(Color.vPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AfterSaleCopy.applyTitle).font(.vBodyMedium)
                        Text(AfterSaleCopy.applyEmptyHint)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary)
                }
                .padding(14)
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            }
            .buttonStyle(.plain)
        } else if canApply && o.isSeller {
            // Seller sees entry only when a case exists (processing/closed above).
            EmptyView()
        }
    }

    /// Bounty report entry — buyer only (DES-v1.3-10-02 §5.1 / §5.12).
    @ViewBuilder
    private func bountyReportEntry(_ o: Order) -> some View {
        if !o.isSeller, o.status != .pendingPayment, o.status != .cancelled {
            Button {
                showBountyReport = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield").foregroundStyle(Color.vPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(RiskCopy.bountyReportTitle).font(.vBodyMedium)
                        Text("诱导线下逃佣可提交证据；查实后有赏金奖励")
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary)
                }
                .padding(14)
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// Mutual reviews + pending D-day banner (DES-v1.3-12-02 / D40).
    @ViewBuilder
    private func reviewSection(_ o: Order) -> some View {
        if o.status == .completed || o.status == .settled {
            let remain = ReviewCreditLogic.reviewRemainDays(
                deadline: o.reviewDeadline ?? model.reviews?.reviewDeadline,
                serverRemainDays: o.reviewRemainDays,
                serverTime: model.serverTime ?? o.serverTime ?? model.reviews?.serverTime,
                fetchedAtLocal: model.fetchedAt,
                nowLocal: Date(),
                completedAt: o.completedAt
            )
            let pending = o.isReviewPendingForMe || model.reviews?.pendingForMe == true
            VStack(spacing: VSpace.m) {
                if pending, remain > 0 {
                    PendingReviewBanner(remainDays: remain) {
                        showReviewSubmit = true
                    }
                }
                OrderReviewsSection(response: model.reviews)
                if pending {
                    VPrimaryButton(title: ReviewCreditCopy.submitTitle, style: .soft) {
                        showReviewSubmit = true
                    }
                }
            }
        }
    }

    private func timelineCard(_ o: Order) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("订单进度").font(.vHeadline).padding(.bottom, VSpace.m)
                ForEach(Array(o.timeline.reversed().enumerated()), id: \.offset) { i, ev in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle().fill(i == 0 ? Color.vPrimary : Color.vFillStrong).frame(width: 10, height: 10)
                            if i < o.timeline.count - 1 { Rectangle().fill(Color.vSeparator).frame(width: 1.5).frame(minHeight: 28) }
                        }
                        .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ev.title).font(i == 0 ? .vBodyMedium : .vBody).foregroundStyle(i == 0 ? Color.vText : Color.vTextSecondary)
                            if let n = ev.note, !n.isEmpty { Text(n).font(.vCaption).foregroundStyle(Color.vTextSecondary) }
                            Text(ev.at.fullText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        }
                        .padding(.bottom, 14)
                    }
                }
                if let c = o.shippingCarrier, !c.isEmpty {
                    Rectangle().fill(Color.vSeparator).frame(height: 0.5).padding(.bottom, 10)
                    HStack {
                        Image(systemName: "shippingbox").foregroundStyle(Color.vBlue)
                        Text("\(c)  \(o.trackingNo ?? "")").font(.vMono(13))
                        Spacer()
                        Button("复制") { UIPasteboard.general.string = o.trackingNo; ToastCenter.shared.show("已复制单号", .success) }.font(.vCaption)
                    }
                }
            }
        }
    }

    private func infoCard(_ o: Order) -> some View {
        VCard {
            VStack(spacing: 8) {
                HStack {
                    Text("订单编号").font(.vCaption).foregroundStyle(Color.vTextSecondary); Spacer()
                    Text(o.orderNo).font(.vMono(12, weight: .regular))
                    Button { UIPasteboard.general.string = o.orderNo; ToastCenter.shared.show("已复制", .success) } label: { Image(systemName: "doc.on.doc").font(.vCaption) }
                }
                VKeyValue(key: "创建时间", value: o.createdAt.fullText).font(.vCaption)
                if let p = o.paidAt { VKeyValue(key: "付款时间", value: p.fullText).font(.vCaption) }
                if let s = o.shippedAt { VKeyValue(key: "发货时间", value: s.fullText).font(.vCaption) }
                if let c = o.completedAt { VKeyValue(key: "完成时间", value: c.fullText).font(.vCaption) }
                HStack {
                    Text(o.isSeller ? "买家" : "卖家").font(.vCaption).foregroundStyle(Color.vTextSecondary); Spacer()
                    VAvatar(url: (o.isSeller ? o.buyer : o.seller).avatar, size: 20)
                    Text((o.isSeller ? o.buyer : o.seller).nickname).font(.vCaption)
                }
                if !model.payments.isEmpty {
                    Rectangle().fill(Color.vSeparator).frame(height: 0.5)
                    ForEach(model.payments) { p in
                        HStack {
                            Text("支付流水").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                            Spacer()
                            Text("\(providerName(p.provider)) · \(paymentStatusLabel(p.status))").font(.vCaption)
                        }
                    }
                }
            }
        }
    }

    // MARK: Bottom bar

    @ViewBuilder private func bottomBar(_ o: Order) -> some View {
        HStack(spacing: 10) {
            Button { openChat(o) } label: {
                VStack(spacing: 3) { Image(systemName: "bubble.left").font(.system(size: 18)); Text(o.isSeller ? "联系买家" : "联系卖家").font(.vMicro) }
                    .foregroundStyle(Color.vTextSecondary).frame(width: 60)
            }
            if o.isSeller {
                switch o.status {
                case .paid:
                    if o.evidenceReady == false {
                        VPrimaryButton(title: EvidenceCopy.goEvidence, icon: "camera.fill") { showEvidence = true }
                    } else {
                        VPrimaryButton(title: "去发货", icon: "shippingbox.fill") { showShip = true }
                    }
                case .pendingPayment: VPrimaryButton(title: "等待买家付款", style: .dark, disabled: true) {}
                case .shipped: VPrimaryButton(title: "等待买家确认收货", style: .dark, disabled: true) {}
                case .completed, .settled:
                    if o.isReviewPendingForMe || model.reviews?.pendingForMe == true {
                        VPrimaryButton(title: ReviewCreditCopy.submitTitle, icon: "star.fill") { showReviewSubmit = true }
                    } else {
                        VPrimaryButton(title: o.status.label, style: .dark, disabled: true) {}
                    }
                default: VPrimaryButton(title: o.status.label, style: .dark, disabled: true) {}
                }
            } else {
                switch o.status {
                case .pendingPayment:
                    VStack(alignment: .leading, spacing: 0) {
                        Text("应付").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        VPriceText(amount: o.payAmount, size: 20)
                    }
                    .frame(width: 110, alignment: .leading)
                    VPrimaryButton(title: "立即付款", icon: "creditcard.fill") {
                        if !o.hasAddress {
                            ToastCenter.shared.show("请先选择收货地址")
                            showAddressPicker = true
                        } else {
                            showCashier = true
                        }
                    }
                case .shipped:
                    let paused = ShipmentLogic.isConfirmPaused(o.confirmPauseState)
                    Button {
                        showUnboxEvidence = true
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "video").font(.system(size: 18))
                            Text(EvidenceCopy.supplementUnbox).font(.vMicro)
                        }
                        .foregroundStyle(Color.vTextSecondary)
                        .frame(width: 60)
                    }
                    VPrimaryButton(
                        title: paused ? ShipmentCopy.confirmPausedButton : ShipmentCopy.confirmTitle,
                        icon: paused ? "pause.circle" : "checkmark.seal.fill",
                        loading: model.working,
                        disabled: paused
                    ) {
                        Task { await model.confirm() }
                    }
                case .paid:
                    if canCancelUnshipped(o) {
                        VPrimaryButton(
                            title: ShipmentCopy.cancelUnshippedCTA,
                            style: .dark,
                            loading: model.working
                        ) { showCancelUnshippedConfirm = true }
                    } else {
                        VPrimaryButton(title: "等待卖家发货", style: .dark, disabled: true) {}
                    }
                case .completed, .settled:
                    if o.isReviewPendingForMe || model.reviews?.pendingForMe == true {
                        VPrimaryButton(title: ReviewCreditCopy.submitTitle, icon: "star.fill") { showReviewSubmit = true }
                    } else {
                        VPrimaryButton(title: o.status.label, style: .dark, disabled: true) {}
                    }
                default: VPrimaryButton(title: o.status.label, style: .dark, disabled: true) {}
                }
            }
        }
        .padding(.horizontal, VSpace.l).padding(.vertical, VSpace.m)
        .background(Color.vSurface.ignoresSafeArea(edges: .bottom).overlay(alignment: .top) { Rectangle().fill(Color.vSeparator).frame(height: 0.5) })
    }

    private func openChat(_ o: Order) {
        // Prefer order-scoped session (DES-v1.3-11-02 MSG-02); fall back to lot.
        Task {
            do {
                if o.id > 0 {
                    chatConv = try await API.openConversation(orderId: o.id)
                } else if let lotId = o.lotId ?? o.lot?.id {
                    chatConv = try await API.openConversation(lotId: lotId)
                } else {
                    ToastCenter.shared.show("暂不支持联系对方", .info)
                }
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }

    // MARK: Labels

    private func statusTitle(_ o: Order) -> String {
        OrderLogic.statusHeaderTitle(status: o.status.asCenterStatus, isSeller: o.isSeller)
    }
    private func statusLines(_ o: Order) -> [String] {
        switch o.status {
        case .pendingPayment:
            return o.isSeller
                ? ["买家需在 \(o.payDeadline.shortText) 前完成付款", "逾期未付订单将自动取消"]
                : ["请在 \(o.payDeadline.shortText) 前完成付款", OrderCenterCopy.serverTimeHint]
        case .paid:
            if o.isSeller && !o.hasAddress {
                return [OrderCenterCopy.sellerAwaitingAddress, "倒计时仍按发货截止"]
            }
            if !o.isSeller && canCancelUnshipped(o) {
                return ["卖家发货已超时", ShipmentCopy.cancelUnshippedConfirm]
            }
            if !o.isSeller, let deadline = o.shipDeadline,
               ShipmentLogic.isWithinShipGrace(shipDeadline: deadline, now: ticker.now) {
                return ["卖家发货已逾期，宽限期内", ShipmentCopy.cancelUnshippedGraceHint]
            }
            return [o.isSeller ? "请在发货截止前填写物流单号" : "卖家正在打包，请耐心等待"]
        case .shipped:
            if !o.isSeller && ShipmentLogic.isConfirmPaused(o.confirmPauseState) {
                return [ShipmentCopy.confirmPausedHint, ShipmentCopy.confirmHint]
            }
            return [o.isSeller ? "等待买家确认收货后货款入账" : "收到后请确认收货，货款将打给卖家"]
        case .completed, .settled: return [o.isSeller ? "货款已入账钱包" : "感谢您的信任，欢迎再次光临"]
        case .cancelled:
            return o.isSeller
                ? [AuctionSettlementCopy.defaultSellerTitle, AuctionSettlementCopy.defaultSellerDepositHint]
                : [AuctionSettlementCopy.defaultBuyerHint, AuctionSettlementCopy.defaultCreditLine]
        case .refunded: return ["款项已原路退回"]
        }
    }
    private func statusIcon(_ o: Order) -> String {
        switch o.status {
        case .pendingPayment: return "creditcard"
        case .paid: return "shippingbox"
        case .shipped: return "truck.box"
        case .completed, .settled: return "checkmark.seal"
        case .cancelled: return "xmark.circle"
        case .refunded: return "arrow.uturn.backward.circle"
        }
    }
    private func headerGradient(_ o: Order) -> LinearGradient {
        switch o.status {
        case .pendingPayment: return VGradient.brand
        case .completed, .settled: return LinearGradient(colors: [Color(hex: 0x27C07A), Color(hex: 0x1DB06A)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .cancelled, .refunded: return LinearGradient(colors: [Color(hex: 0x8E939E), Color(hex: 0x6B7280)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default: return LinearGradient(colors: [Color(hex: 0x4F8BFF), Color(hex: 0x3478F6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

func providerName(_ p: String) -> String {
    switch p { case "alipay": return "支付宝"; case "wechatpay": return "微信支付"; case "mock": return "模拟支付"; default: return p }
}
func paymentStatusLabel(_ s: PaymentStatus) -> String {
    switch s { case .created: return "待支付"; case .paying: return "支付中"; case .succeeded: return "已支付"; case .failed: return "失败"; case .closed: return "已关闭"; case .refunded: return "已退款" }
}

// MARK: - Model

@MainActor
final class OrderModel: ObservableObject {
    let orderId: Int64
    @Published var order: Order?
    @Published var payments: [Payment] = []
    /// Two-phase refund progress for buyer UI (DES-v1.3-08-03).
    @Published var refunds: [RefundProgress] = []
    @Published var tracking: TrackingResult?
    @Published var trackingLoading = false
    @Published var state: LoadState = .idle
    @Published var working = false
    /// Calibrated from detail `server_time` (DES-v1.3-07-01 §5.8).
    @Published var serverTime: Date?
    @Published var fetchedAt = Date()
    @Published var reviews: OrderReviewsResponse?

    init(orderId: Int64) { self.orderId = orderId }

    func load() async {
        if order == nil { state = .loading }
        do {
            let d = try await API.order(orderId)
            order = d.order
            payments = d.payments
            refunds = d.refunds
            serverTime = d.serverTime ?? d.order.serverTime
            fetchedAt = Date()
            state = .loaded
            if refunds.isEmpty, d.order.afterSaleStatus == .processing || d.order.refundedAmount > 0 || d.order.status == .refunded {
                await loadRefundsFallback()
            }
        } catch { if order == nil { state = .failed((error as? APIError)?.message ?? "加载失败") } }
    }

    func loadReviews() async {
        do {
            reviews = try await API.orderReviews(orderId: orderId)
            if let st = reviews?.serverTime {
                serverTime = st
            }
        } catch {
            // Soft-fail until endpoint ships; list/detail may still carry pending flags.
            reviews = nil
        }
    }

    /// Soft-fetch when detail payload omits `refunds` but after-sale / refunded amount is present.
    private func loadRefundsFallback() async {
        do {
            let rows = try await API.orderRefunds(orderId: orderId)
            if !rows.isEmpty { refunds = rows }
        } catch {
            // Route may 404 until server ships list; keep empty.
        }
    }

    func loadTracking() async {
        guard order?.status == .shipped || !(order?.trackingNo ?? "").isEmpty else {
            tracking = nil
            return
        }
        trackingLoading = true
        defer { trackingLoading = false }
        do {
            tracking = try await API.orderTracking(orderId)
            if let n = tracking?.memberCount, n > 0, var o = order {
                o.shipmentMemberCount = n
                order = o
            }
        } catch {
            // Soft-fail: keep carrier/tracking from order when tracking API unavailable.
            tracking = nil
        }
    }

    func setAddress(_ a: Address) async {
        do {
            order = try await API.setOrderAddress(orderId, addressId: a.id)
            ToastCenter.shared.show("地址已更新", .success)
        } catch {
            if let code = (error as? APIError)?.code, code == OrderCenterErrorCode.addressLocked.rawValue {
                ToastCenter.shared.show(OrderCenterCopy.addressLocked)
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }

    func confirm() async {
        if let o = order, let err = ShipmentLogic.confirmReceiptError(o.confirmPauseState) {
            ToastCenter.shared.show(err.fallbackMessage)
            return
        }
        working = true; defer { working = false }
        do {
            order = try await API.confirm(orderId, idempotencyKey: UUID().uuidString)
            ToastCenter.shared.show("已确认收货，交易完成", .success)
            await SessionStore.shared.refreshMe()
        } catch {
            if let code = (error as? APIError)?.code,
               let shipping = ShippingErrorCode(rawValue: code) {
                ToastCenter.shared.show(shipping.fallbackMessage)
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }

    func cancelUnshipped() async {
        working = true; defer { working = false }
        do {
            order = try await API.cancelUnshipped(orderId, idempotencyKey: UUID().uuidString)
            ToastCenter.shared.show("已取消并全额退款", .success)
            await SessionStore.shared.refreshMe()
        } catch {
            if let code = (error as? APIError)?.code,
               let shipping = ShippingErrorCode(rawValue: code) {
                ToastCenter.shared.show(shipping.fallbackMessage)
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }
}

// MARK: - Ship sheet (DES-v1.3-07-02 ORD-04/09)

struct ShipSheet: View {
    let order: Order
    var sellerType: String? = nil
    var onOpenEvidence: (() -> Void)? = nil
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var carrierCode = ShippingCarrier.builtIn.first?.code ?? "SF"
    @State private var tracking = ""
    @State private var insuredOn = false
    @State private var insuredAmountText = ""
    @State private var working = false
    @State private var evidenceState: OrderEvidenceState?
    @State private var evidenceLoading = false

    private var carriers: [ShippingCarrier] { ShippingCarrier.builtIn.filter(\.enabled) }
    private var needsInsurance: Bool { order.needsInsurance || insuredOn }
    private var suggestedInsured: Int64 { ShipmentLogic.suggestedInsuredAmountFen(order.displayAmount) }

    private var evidenceGateError: EvidenceErrorCode? {
        if let st = evidenceState {
            return EvidenceLogic.canShip(state: st)
        }
        if order.evidenceReady == false { return .evidenceRequired }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VSpace.l) {
            Text(ShipmentCopy.shipFormTitle).font(.vTitle(20))
            Text(ShipmentCopy.shipFormHint).font(.vCaption).foregroundStyle(Color.vTextSecondary)
            evidenceBanner
            if order.needsInsurance {
                Text(ShipmentCopy.insuredRequiredBanner)
                    .font(.vCaption)
                    .foregroundStyle(Color.vPrimary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.vPrimarySoft, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            }
            VStack(spacing: 0) {
                VFormRow(title: "快递公司") {
                    Spacer()
                    Picker("", selection: $carrierCode) {
                        ForEach(carriers) { c in Text(c.name).tag(c.code) }
                    }.tint(Color.vText)
                }
                VDivider()
                VFormRow(title: "运单号") {
                    TextField("请输入运单号", text: $tracking)
                        .font(.vMono(15))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                }
                VDivider()
                VFormRow(title: "保价") {
                    Spacer()
                    Toggle("", isOn: $insuredOn)
                        .labelsHidden()
                        .disabled(order.needsInsurance)
                        .onAppear {
                            if order.needsInsurance {
                                insuredOn = true
                                if insuredAmountText.isEmpty {
                                    insuredAmountText = "\(suggestedInsured)"
                                }
                            }
                        }
                }
                if needsInsurance {
                    VDivider()
                    VFormRow(title: "保价金额(分)") {
                        TextField("\(ShipmentCopy.insuredSuggestedPrefix) \(suggestedInsured)", text: $insuredAmountText)
                            .font(.vMono(15))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            Spacer()
            VPrimaryButton(
                title: ShipmentCopy.shipSubmit,
                loading: working,
                disabled: tracking.isBlank || evidenceGateError != nil
            ) {
                submit()
            }
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
        .task { await refreshEvidence() }
    }

    @ViewBuilder private var evidenceBanner: some View {
        if evidenceLoading {
            HStack {
                ProgressView()
                Text("核对取证进度…").font(.vCaption).foregroundStyle(Color.vTextSecondary)
            }
        } else if let err = evidenceGateError {
            VStack(alignment: .leading, spacing: 8) {
                Text(err.fallbackMessage)
                    .font(.vCaption)
                    .foregroundStyle(Color.vPrimary)
                if let onOpenEvidence {
                    Button(EvidenceCopy.goEvidence, action: onOpenEvidence)
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vPrimary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vPrimarySoft, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
        } else if evidenceState?.shipPhotosComplete == true {
            Text(EvidenceCopy.readyToShip)
                .font(.vCaption)
                .foregroundStyle(Color.vGreen)
        }
    }

    private func refreshEvidence() async {
        evidenceLoading = true
        defer { evidenceLoading = false }
        evidenceState = try? await API.orderEvidence(order.id)
    }

    private func submit() {
        let carrier = carriers.first(where: { $0.code == carrierCode })
        let carrierName = carrier?.name ?? carrierCode
        let trackingNo = ShipmentLogic.normalizeTrackingNo(tracking)
        let insuredAmount: Int64? = {
            guard needsInsurance else { return nil }
            if let v = Int64(insuredAmountText.trimmingCharacters(in: .whitespacesAndNewlines)), v > 0 {
                return v
            }
            return suggestedInsured
        }()
        if let gate = evidenceGateError {
            ToastCenter.shared.show(gate.fallbackMessage)
            return
        }
        if let err = ShipmentLogic.validateShipOrderRequest(
            ShipOrderRequest(
                carrier: carrierName,
                trackingNo: trackingNo,
                insured: needsInsurance,
                insuredAmount: insuredAmount
            ),
            status: order.status.rawValue,
            evidenceReady: evidenceState.map { EvidenceLogic.canShip(state: $0) == nil } ?? order.evidenceReady,
            hasAddress: order.hasAddress,
            amountFen: order.displayAmount,
            insuredRequired: order.needsInsurance,
            hasInsuranceProof: order.needsInsurance ? true : nil, // App gate; AFS photo is server-side
            carrierEnabled: carrier?.enabled
        ) {
            ToastCenter.shared.show(err.fallbackMessage)
            return
        }
        working = true
        Task {
            defer { working = false }
            do {
                _ = try await API.ship(
                    order.id,
                    carrier: carrierName,
                    trackingNo: trackingNo,
                    insured: needsInsurance ? true : nil,
                    insuredAmount: insuredAmount,
                    idempotencyKey: UUID().uuidString
                )
                ToastCenter.shared.show("已发货", .success)
                done()
                dismiss()
            } catch {
                if let code = (error as? APIError)?.code {
                    if let evidence = EvidenceErrorCode.normalize(code) {
                        ToastCenter.shared.show(evidence.fallbackMessage)
                    } else if let shipping = ShippingErrorCode(rawValue: code) {
                        ToastCenter.shared.show(shipping.fallbackMessage)
                    } else {
                        ToastCenter.shared.error(error)
                    }
                } else {
                    ToastCenter.shared.error(error)
                }
            }
        }
    }
}
