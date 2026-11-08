import SwiftUI

/// Universal Link 落地：尾款确认 + 支付（DES-v1.3-06-03 §5.3 / §9）。
struct BalancePayLandingView: View {
    let balanceOrderId: Int64
    var token: String? = nil

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: BalancePayLandingModel
    @ObservedObject private var ticker = Ticker.shared
    @State private var showCashier = false
    @State private var paymentResult: PaymentResult?

    init(balanceOrderId: Int64, token: String? = nil) {
        self.balanceOrderId = balanceOrderId
        self.token = token
        _model = StateObject(wrappedValue: BalancePayLandingModel(balanceOrderId: balanceOrderId, token: token))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let msg) where model.landing == nil:
                VErrorView(message: msg) { Task { await model.load() } }
            default:
                content
            }
        }
        .background(Color.vBackground)
        .navigationTitle(PresaleCopy.payBalance)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .task { await model.load() }
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
            _ = model.countdownSeconds
        }
        .onChange(of: session.isLoggedIn) { _, loggedIn in
            if loggedIn {
                Task { await model.load() }
            }
        }
        .sheet(isPresented: $showCashier) {
            if let order = model.openPayOrder {
                CashierSheet(
                    order: order,
                    createPayment: { orderId, provider in
                        try await model.createBalancePayment(orderId: orderId, provider: provider)
                    }
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
                if case .success = r.outcome { dismiss() }
            }
        }
        .confirmationDialog(
            PresaleCopy.confirmBalanceAmount,
            isPresented: $model.confirmAmount,
            titleVisibility: .visible
        ) {
            Button(PresaleCopy.payBalance) {
                Task { await model.pay() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let landing = model.landing {
                Text("\(PresaleCopy.balanceConfirmHint)\n尾款 \(PresaleLogic.formatFen(landing.payAmountFen))")
            } else {
                Text(PresaleCopy.balanceConfirmHint)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.l) {
                    if let landing = model.landing {
                        HStack(alignment: .top, spacing: VSpace.m) {
                            RemoteImage(landing.cover ?? "")
                                .frame(width: 88, height: 88)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(landing.title ?? "预售尾款")
                                    .font(.vTitle(20))
                                    .foregroundStyle(Color.vText)
                                if let status = landing.bizStatus {
                                    VTagChip(
                                        text: status.displayLabel,
                                        tint: .vPrimary,
                                        background: Color.vPrimary.opacity(0.12)
                                    )
                                }
                            }
                            Spacer(minLength: 0)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("应付尾款")
                                .font(.vCaption)
                                .foregroundStyle(Color.vTextSecondary)
                            Text(PresaleLogic.formatFen(landing.payAmountFen))
                                .font(.vTitle(28))
                                .foregroundStyle(Color.vPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(VSpace.l)
                        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))

                        if landing.deadline != nil {
                            Text(PresaleLogic.balanceDeadlineCountdownLine(seconds: model.countdownSeconds))
                                .font(.vCaption)
                                .foregroundStyle(Color.vPrimary)
                        }

                        if landing.expired == true || landing.tokenValid == false {
                            Text(PresaleCopy.linkExpired)
                                .font(.vCaption)
                                .foregroundStyle(Color.vTextSecondary)
                        }
                        if landing.buyerMismatch == true {
                            Text(PresaleCopy.buyerMismatch)
                                .font(.vCaption)
                                .foregroundStyle(Color.vGold)
                        }
                    }
                }
                .padding(VSpace.l)
            }

            VStack(spacing: 8) {
                if model.landing?.canPay == true {
                    VPrimaryButton(
                        title: PresaleCopy.payBalance,
                        loading: model.busy
                    ) {
                        model.confirmAmount = true
                    }
                } else if let oid = model.landing?.presaleOrderId {
                    NavigationLink {
                        PresaleOrderDetailView(presaleOrderId: oid)
                    } label: {
                        Text("打开「我的补款」详情")
                            .font(.vBodyMedium)
                            .foregroundStyle(Color.vPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                } else {
                    Text(PresaleCopy.notBalancePending)
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, VSpace.l)
            .padding(.vertical, VSpace.m)
            .background(Color.vSurface)
        }
    }
}
