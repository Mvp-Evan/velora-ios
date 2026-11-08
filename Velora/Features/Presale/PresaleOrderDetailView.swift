import SwiftUI

/// 预售订单详情：biz_status、交期时间线、尾款倒计时、延期选择（DES-v1.3-06-03 §5.10 / §9）。
struct PresaleOrderDetailView: View {
    let presaleOrderId: Int64

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: PresaleOrderDetailModel
    @ObservedObject private var ticker = Ticker.shared
    @State private var showCashier = false
    @State private var paymentResult: PaymentResult?

    init(presaleOrderId: Int64) {
        self.presaleOrderId = presaleOrderId
        _model = StateObject(wrappedValue: PresaleOrderDetailModel(presaleOrderId: presaleOrderId))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let msg) where model.detail == nil:
                VErrorView(message: msg) { Task { await model.load() } }
            default:
                content
            }
        }
        .background(Color.vBackground)
        .navigationTitle(PresaleCopy.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.refresh() }
        .onChange(of: model.needsLogin) { _, need in
            if need {
                router.showLogin = true
                model.needsLogin = false
            }
        }
        .onChange(of: model.openPayOrder) { _, order in
            showCashier = order != nil
        }
        .onChange(of: ticker.now) { _, _ in
            _ = model.balanceCountdownSeconds
        }
        .sheet(isPresented: $showCashier) {
            if let order = model.openPayOrder {
                CashierSheet(
                    order: order,
                    createPayment: model.payingBalance
                        ? { orderId, provider in try await model.createBalancePayment(orderId: orderId, provider: provider) }
                        : nil
                ) { r in
                    showCashier = false
                    paymentResult = r
                    Task { await model.handlePaymentFinished(r) }
                }
                .presentationDetents([.height(460)]).presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $paymentResult) { r in
            PaymentResultView(result: r, order: model.openPayOrder) {
                paymentResult = nil
            }
        }
        .sheet(isPresented: $model.showDelaySheet) {
            delayChoiceSheet
        }
        .confirmationDialog(
            PresaleCopy.confirmBalanceAmount,
            isPresented: $model.confirmBalanceAmount,
            titleVisibility: .visible
        ) {
            Button(PresaleCopy.payBalance) {
                Task { await model.confirmAndPayBalance() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let detail = model.detail {
                Text("\(PresaleCopy.balanceConfirmHint)\n尾款 \(PresaleLogic.formatFen(detail.amounts.balanceTotalFen))")
            } else {
                Text(PresaleCopy.balanceConfirmHint)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.l) {
                    if let detail = model.detail {
                        hero(detail)
                        statusBlock(detail)
                        amountsBlock(detail)
                        if detail.resolvedStatus.showsBalanceCountdown {
                            countdownBlock
                        }
                        if let legal = detail.legalDepositKind?.displayCopy {
                            disclosure(legal)
                        }
                        if let overdue = detail.overdueReasonCopy, !overdue.isEmpty {
                            disclosure(overdue)
                        }
                        timeline(detail)
                        Text(PresaleCopy.addressLockedHint)
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }
                }
                .padding(VSpace.l)
                .padding(.bottom, 100)
            }

            bottomBar
        }
    }

    private func hero(_ detail: PresaleOrderDetail) -> some View {
        HStack(alignment: .top, spacing: VSpace.m) {
            RemoteImage(detail.cover ?? "")
                .frame(width: 88, height: 88)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.displayTitle)
                    .font(.vTitle(20))
                    .foregroundStyle(Color.vText)
                if let sku = detail.skuLabel, !sku.isEmpty {
                    Text(sku).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
                VTagChip(
                    text: detail.resolvedStatus.displayLabel,
                    tint: .vPrimary,
                    background: Color.vPrimary.opacity(0.12)
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func statusBlock(_ detail: PresaleOrderDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.resolvedStatus.displayLabel)
                .font(.vBodyMedium)
                .foregroundStyle(Color.vText)
            if let delivery = detail.resolvedDeliveryAt {
                Text("预计发货 \(PresaleLogic.shortDate(delivery))")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
            if let notice = detail.openDelayNotice {
                Text(notice.displayBody)
                    .font(.vCaption)
                    .foregroundStyle(Color.vGold)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VSpace.l)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func amountsBlock(_ detail: PresaleOrderDetail) -> some View {
        let amounts = detail.amounts
        return VStack(alignment: .leading, spacing: 10) {
            amountRow("定金", amounts.depositTotalFen)
            amountRow("尾款", amounts.balanceTotalFen)
            VDivider()
            amountRow("合计", amounts.totalFen, emphasize: true)
        }
        .padding(VSpace.l)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func amountRow(_ title: String, _ fen: Int64, emphasize: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(emphasize ? .vBodyMedium : .vCaption)
                .foregroundStyle(emphasize ? Color.vText : Color.vTextSecondary)
            Spacer()
            Text(PresaleLogic.formatFen(fen))
                .font(emphasize ? .vBodyMedium : .vCaption)
                .foregroundStyle(emphasize ? Color.vPrimary : Color.vText)
        }
    }

    private var countdownBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("补款截止")
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
            Text(model.balanceCountdownLine)
                .font(.vMono(18, weight: .semibold))
                .foregroundStyle(Color.vPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VSpace.l)
        .background(Color.vPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func disclosure(_ text: String) -> some View {
        Text(text)
            .font(.vCaption)
            .foregroundStyle(Color.vTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VSpace.m)
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }

    private func timeline(_ detail: PresaleOrderDetail) -> some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            Text("交期节点")
                .font(.vBodyMedium)
                .foregroundStyle(Color.vText)
            if detail.timeline.isEmpty {
                Text("节点将随进度更新")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(detail.timeline.enumerated()), id: \.offset) { _, event in
                            VStack(alignment: .leading, spacing: 6) {
                                Circle()
                                    .fill(Color.vPrimary)
                                    .frame(width: 8, height: 8)
                                Text(event.displayTitle)
                                    .font(.vCaptionMedium)
                                    .foregroundStyle(Color.vText)
                                    .lineLimit(2)
                                if let at = event.at {
                                    Text(PresaleLogic.shortDate(at))
                                        .font(.vMicro)
                                        .foregroundStyle(Color.vTextTertiary)
                                }
                                if let actor = event.actorType {
                                    Text(actor.displayLabel)
                                        .font(.vMicro)
                                        .foregroundStyle(Color.vTextTertiary)
                                }
                            }
                            .frame(width: 110, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(VSpace.l)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
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
        }
        .padding(.horizontal, VSpace.l)
        .padding(.top, VSpace.m)
        .padding(.bottom, VSpace.s)
        .background(Color.vSurface)
    }

    private var delayChoiceSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: VSpace.l) {
                if let notice = model.detail?.openDelayNotice {
                    Text(notice.displayBody)
                        .font(.vBody)
                        .foregroundStyle(Color.vText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let newDelivery = notice.newDelivery {
                        Text("新交期 \(PresaleLogic.shortDate(newDelivery))")
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    }
                    if let deadline = notice.choiceDeadline {
                        Text("选择截止 \(PresaleLogic.shortDate(deadline)) · \(PresaleCopy.serverTimeHint)")
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }
                } else {
                    Text("发货时间已延期，请选择继续等待或申请退定金。")
                        .font(.vBody)
                        .foregroundStyle(Color.vText)
                }
                Spacer()
                VPrimaryButton(title: PresaleCopy.delayContinue) {
                    model.continueWaiting()
                }
                Button {
                    Task { await model.refundDeposit() }
                } label: {
                    Text(PresaleCopy.delayRefund)
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
            }
            .padding(VSpace.l)
            .navigationTitle("延期公告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { model.showDelaySheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
