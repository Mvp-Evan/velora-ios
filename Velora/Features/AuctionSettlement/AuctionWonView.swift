import SwiftUI

/// 中拍页：大字付款倒计时 + 锁价文案（DES-v1.3-03-05 §9 AUC-09/N-05/N-06）
struct AuctionWonView: View {
    let orderId: Int64
    var presentedAsSheet = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: AuctionWonModel
    @State private var showCashier = false
    @State private var showAddressPicker = false
    @State private var showCancelConfirm = false
    @State private var result: PaymentResult?

    init(orderId: Int64, presentedAsSheet: Bool = false) {
        self.orderId = orderId
        self.presentedAsSheet = presentedAsSheet
        _model = StateObject(wrappedValue: AuctionWonModel(orderId: orderId))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading: VLoadingView()
            case .failed(let m): VErrorView(message: m) { Task { await model.load() } }
            case .loaded:
                if let o = model.order { content(o) }
            }
        }
        .background(Color.vBackground)
        .navigationTitle("拍中待付")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .task { await model.load() }
        .onAppear { if !presentedAsSheet { router.hideTabBar = true } }
        .onDisappear { if !presentedAsSheet { router.hideTabBar = false } }
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
                    Task { await model.load() }
                }
                .presentationDetents([.height(460)]).presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $result) { r in
            PaymentResultView(result: r, order: model.order) { result = nil }
        }
        .confirmationDialog(AuctionSettlementCopy.cancelEqualsDefault, isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("确认取消（视为违约）", role: .destructive) {
                Task { await model.cancelAsDefault() }
            }
            Button("再想想", role: .cancel) {}
        } message: {
            Text(AuctionSettlementCopy.cancelEqualsDefault)
        }
    }

    @ObservedObject private var ticker = Ticker.shared

    private func content(_ o: Order) -> some View {
        let overdue = o.payDeadline.timeIntervalSince(ticker.now) <= 0
        let remind = model.isInPayRemindWindow(now: ticker.now)
        return ScrollView {
            VStack(spacing: VSpace.l) {
                hero(o, overdue: overdue)
                if remind && !overdue {
                    remindBanner
                }
                lotCard(o)
                lockCard(o)
                addressCard(o)
            }
            .padding(VSpace.l)
            .padding(.bottom, 100)
        }
        .refreshable { await model.load() }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(o, overdue: overdue) }
    }

    private func hero(_ o: Order, overdue: Bool) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous)
                .fill(VGradient.brand)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "trophy.fill").font(.system(size: 22, weight: .semibold))
                    Text(AuctionSettlementCopy.wonTitle).font(.vTitle(22))
                    Spacer()
                }
                .foregroundStyle(.white)
                Text(AuctionSettlementCopy.wonSubtitle)
                    .font(.vCaption)
                    .foregroundStyle(.white.opacity(0.88))
                VStack(alignment: .leading, spacing: 4) {
                    Text(AuctionSettlementCopy.payCountdownLabel)
                        .font(.vCaption)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(overdue ? "00:00:00" : o.payDeadline.countdownText(to: ticker.now))
                        .font(.vMono(36, weight: .heavy))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .accessibilityLabel(AuctionSettlementCopy.payCountdownLabel)
                        .accessibilityValue(overdue ? "已截止" : o.payDeadline.countdownText(to: ticker.now))
                }
                .padding(.top, 4)
                Text("截止 \(o.payDeadline.shortText)")
                    .font(.vMicro)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(VSpace.xl)
        }
        .frame(minHeight: 180)
    }

    private var remindBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill").foregroundStyle(Color.vPrimary)
            Text(AuctionSettlementCopy.payRemindBanner)
                .font(.vCaptionMedium)
                .foregroundStyle(Color.vText)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.vPrimarySoft, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func lotCard(_ o: Order) -> some View {
        VCard {
            HStack(spacing: 12) {
                RemoteImage(o.lot?.cover ?? "")
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(o.lot?.title ?? "拍品").font(.vBodyMedium).lineLimit(2)
                    HStack {
                        Text("成交价").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        Spacer()
                        VPriceText(amount: o.hammerPrice, size: 18)
                    }
                }
            }
        }
    }

    private func lockCard(_ o: Order) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").foregroundStyle(Color.vGold)
                    Text(AuctionSettlementCopy.priceLocked)
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vText)
                }
                VKeyValue(key: "应付", value: o.payAmount.display, valueColor: .vPrimary, bold: true)
                if o.depositApplied > 0 {
                    VKeyValue(key: "押金抵扣", value: "-\(o.depositApplied.display)", valueColor: .vTextSecondary)
                }
            }
        }
    }

    private func addressCard(_ o: Order) -> some View {
        Button { showAddressPicker = true } label: {
            VCard {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(Color.vPrimary)
                        .frame(width: 28)
                    if o.hasAddress {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(o.address?["name"] ?? "")  \(o.address?["phone"] ?? "")")
                                .font(.vHeadline)
                            Text(o.addressLine).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        }
                    } else {
                        Text("请选择收货地址（可先付款后补）").font(.vBodyMedium).foregroundStyle(Color.vPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func bottomBar(_ o: Order, overdue: Bool) -> some View {
        VStack(spacing: 10) {
            VPrimaryButton(
                title: overdue ? AuctionSettlementErrorCode.auctionPayOverdue.fallbackMessage : AuctionSettlementCopy.goPay,
                icon: "creditcard.fill",
                disabled: overdue || o.status != .pendingPayment
            ) {
                showCashier = true
            }
            Button {
                showCancelConfirm = true
            } label: {
                Text("取消订单")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
            }
            .disabled(o.status != .pendingPayment || model.working)
        }
        .padding(.horizontal, VSpace.l)
        .padding(.vertical, VSpace.m)
        .background(Color.vSurface.ignoresSafeArea(edges: .bottom).overlay(alignment: .top) {
            Rectangle().fill(Color.vSeparator).frame(height: 0.5)
        })
    }
}

@MainActor
final class AuctionWonModel: ObservableObject {
    let orderId: Int64
    @Published var order: Order?
    @Published var state: LoadState = .idle
    @Published var working = false

    init(orderId: Int64) { self.orderId = orderId }

    func load() async {
        if order == nil { state = .loading }
        do {
            let d = try await API.order(orderId)
            order = d.order
            state = .loaded
            if d.order.status == .cancelled {
                // Overdue / defaulted — caller may navigate to AuctionDefaultView.
            }
        } catch {
            if order == nil { state = .failed((error as? APIError)?.message ?? "加载失败") }
        }
    }

    func isInPayRemindWindow(now: Date) -> Bool {
        guard let o = order else { return false }
        return AuctionSettlementLogic.isPayRemindWindow(now: now, payDeadline: o.payDeadline, hammerAt: o.createdAt)
    }

    func setAddress(_ a: Address) async {
        do {
            order = try await API.setOrderAddress(orderId, addressId: a.id)
            ToastCenter.shared.show("地址已更新", .success)
        } catch { ToastCenter.shared.error(error) }
    }

    func cancelAsDefault() async {
        working = true
        defer { working = false }
        do {
            order = try await API.cancelAuctionOrder(orderId)
            ToastCenter.shared.show(AuctionSettlementCopy.defaultBuyerHint, .info)
            await SessionStore.shared.refreshMe()
        } catch let e as APIError {
            if e.code == AuctionSettlementErrorCode.auctionPayOverdue.rawValue {
                ToastCenter.shared.show(e.message.isEmpty ? AuctionSettlementErrorCode.auctionPayOverdue.fallbackMessage : e.message, .info)
                await load()
            } else {
                ToastCenter.shared.error(e)
            }
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}
