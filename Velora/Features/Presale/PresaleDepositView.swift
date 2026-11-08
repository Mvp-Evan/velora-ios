import SwiftUI

/// 预售付定金页：法务口径、定金/尾款金额、资格清单、CTA（DES-v1.3-06-03 §5.2 / §9）。
struct PresaleDepositView: View {
    let releaseId: Int64

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PresaleDepositModel
    @ObservedObject private var ticker = Ticker.shared
    @State private var showAddressPicker = false
    @State private var showCashier = false
    @State private var paymentResult: PaymentResult?

    init(releaseId: Int64) {
        self.releaseId = releaseId
        _model = StateObject(wrappedValue: PresaleDepositModel(releaseId: releaseId))
    }

    var body: some View {
        root
            .background(Color.vBackground)
            .navigationTitle(PresaleCopy.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
            .onAppear { router.hideTabBar = true }
            .onDisappear { router.hideTabBar = false }
            .onChange(of: model.needsLogin) { _, need in
                if need {
                    router.showLogin = true
                    model.needsLogin = false
                }
            }
            .onChange(of: model.createdOrder) { _, order in
                showCashier = order != nil
            }
            .onChange(of: ticker.now) { _, _ in
                _ = model.depositCountdownSeconds
            }
            .sheet(isPresented: $model.needsRealName) {
                NavigationStack { RealNameView() }
                    .onDisappear { Task { await model.refresh() } }
            }
            .sheet(isPresented: $showAddressPicker) {
                AddressListView(selecting: true) { addr in
                    model.setAddress(addr)
                }
            }
            .sheet(isPresented: $showCashier, content: cashierSheet)
            .sheet(item: $paymentResult, content: paymentResultSheet)
            .sheet(item: existingOrderBinding, content: existingOrderSheet)
    }

    @ViewBuilder
    private var root: some View {
        switch model.state {
        case .idle, .loading:
            VLoadingView()
        case .failed(let msg) where model.detail == nil:
            VErrorView(message: msg) { Task { await model.load() } }
        default:
            loadedContent
        }
    }

    private var loadedContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.l) {
                    if let detail = model.detail {
                        PresaleDepositHero(detail: detail)
                        PresaleDepositAmounts(detail: detail)
                        if let legal = detail.legalCopy {
                            PresaleDisclosureText(legal)
                        }
                        if let settle = detail.settleDisclosureText {
                            PresaleDisclosureText(settle)
                        }
                        if model.depositCountdownSeconds > 0 {
                            Text(PresaleLogic.balanceDeadlineCountdownLine(seconds: model.depositCountdownSeconds))
                                .font(.vCaption)
                                .foregroundStyle(Color.vPrimary)
                        }
                        PresaleDepositChecklist(items: model.checklist)
                        PresaleDepositSKUPicker(
                            skus: detail.skus,
                            selectedId: model.selectedSKUId
                        ) { model.selectedSKUId = $0 }
                        addressRow
                    }
                }
                .padding(VSpace.l)
                .padding(.bottom, 100)
            }
            bottomBar
        }
    }

    private var addressRow: some View {
        Button { showAddressPicker = true } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("收货地址").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    if let a = model.address {
                        Text("\(a.name) \(a.phone)")
                            .font(.vBodyMedium)
                            .foregroundStyle(Color.vText)
                        Text(a.oneLine)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                            .lineLimit(2)
                    } else {
                        Text("请选择收货地址")
                            .font(.vBodyMedium)
                            .foregroundStyle(Color.vPrimary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.vTextTertiary)
            }
            .padding(VSpace.l)
            .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if model.cta.isPrimaryAction {
                VPrimaryButton(
                    title: model.cta.buttonTitle,
                    loading: model.busy,
                    action: { Task { await model.primaryAction() } }
                )
            } else {
                Text(model.cta.buttonTitle)
                    .font(.vBodyMedium)
                    .foregroundStyle(Color.vTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            Text(PresaleCopy.serverTimeHint)
                .font(.vMicro)
                .foregroundStyle(Color.vTextTertiary)
        }
        .padding(.horizontal, VSpace.l)
        .padding(.top, VSpace.m)
        .padding(.bottom, VSpace.s)
        .background(Color.vSurface)
    }

    private var existingOrderBinding: Binding<IDBox?> {
        Binding(
            get: {
                guard model.createdOrder == nil else { return nil }
                return model.createdPresaleOrderId.map(IDBox.init)
            },
            set: { model.createdPresaleOrderId = $0?.id }
        )
    }

    @ViewBuilder
    private func cashierSheet() -> some View {
        if let order = model.createdOrder {
            CashierSheet(order: order) { r in
                showCashier = false
                paymentResult = r
                Task { await model.handlePaymentFinished(r) }
            }
            .presentationDetents([.height(460)]).presentationDragIndicator(.visible)
        }
    }

    private func paymentResultSheet(_ r: PaymentResult) -> some View {
        PaymentResultView(result: r, order: model.createdOrder) {
            paymentResult = nil
            dismiss()
        }
    }

    private func existingOrderSheet(_ box: IDBox) -> some View {
        NavigationStack {
            PresaleOrderDetailView(presaleOrderId: box.id)
        }
    }
}

// MARK: - Subviews

private struct PresaleDepositHero: View {
    let detail: PresaleReleaseDetail

    var body: some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            RemoteImage(detail.cover ?? "")
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            Text(detail.displayTitle)
                .font(.vTitle(22))
                .foregroundStyle(Color.vText)
            if let delivery = detail.estDeliveryAt {
                Text("预计发货 \(PresaleLogic.shortDate(delivery))")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }
}

private struct PresaleDepositAmounts: View {
    let detail: PresaleReleaseDetail

    var body: some View {
        let snap = detail.amounts
        return HStack(spacing: VSpace.m) {
            amountCard("定金", snap.depositTotalFen)
            amountCard("尾款", snap.balanceTotalFen)
        }
    }

    private func amountCard(_ title: String, _ fen: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.vCaption).foregroundStyle(Color.vTextSecondary)
            Text(PresaleLogic.formatFen(fen))
                .font(.vBodyMedium)
                .foregroundStyle(Color.vText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VSpace.l)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }
}

private struct PresaleDisclosureText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.vCaption)
            .foregroundStyle(Color.vTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VSpace.m)
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }
}

private struct PresaleDepositChecklist: View {
    let items: [PresaleDepositChecklistItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("购买资格")
                .font(.vBodyMedium)
                .foregroundStyle(Color.vText)
            ForEach(items) { item in
                HStack {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.done ? Color.vGreen : Color.vTextTertiary)
                    Text(item.step.title)
                        .font(.vCaption)
                        .foregroundStyle(Color.vText)
                    Spacer()
                    if !item.done {
                        Text(item.step.actionTitle)
                            .font(.vMicro)
                            .foregroundStyle(Color.vPrimary)
                    }
                }
            }
        }
        .padding(VSpace.l)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }
}

private struct PresaleDepositSKUPicker: View {
    let skus: [SpotReleaseSKU]
    let selectedId: Int64?
    let onSelect: (Int64) -> Void

    var body: some View {
        if skus.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("规格").font(.vBodyMedium).foregroundStyle(Color.vText)
                FlowLayout(spacing: 8) {
                    ForEach(skus) { sku in
                        let on = selectedId == sku.id
                        Button {
                            onSelect(sku.id)
                        } label: {
                            Text(sku.displayName)
                                .font(.vCaption)
                                .foregroundStyle(on ? Color.white : Color.vText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(on ? Color.vPrimary : Color.vFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
