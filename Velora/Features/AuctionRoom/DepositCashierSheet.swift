import SwiftUI

/// 参拍保证金半屏（DES-v1.3-08-02 §9）— 首次出价前冻结；文案统一「冻结保证金」。
struct DepositCashierSheet: View {
    let lot: Lot
    var requiredAmount: Money? = nil
    let onPaid: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var methods: [PaymentMethod] = []
    @State private var selected: String?
    @State private var loading = true
    @State private var paying = false
    @State private var info: LotDepositInfo?
    @State private var payIdempotencyKey = APIClient.shared.idempotencyKey()

    private var amount: Money {
        if let a = requiredAmount, a > 0 { return a }
        if let a = info?.sheetAmount, a > 0 { return a }
        return lot.depositAmount
    }

    var body: some View {
        VStack(spacing: VSpace.l) {
            VStack(spacing: 6) {
                Text(DepositCopy.bidSheetTitle)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                VPriceText(amount: amount, size: 36, color: .vText)
                Text(DepositCopy.bidSheetHint)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                    .multilineTextAlignment(.center)
                Text(DepositCopy.bidSheetRefundHint)
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vTextSecondary)
                Text(DepositCopy.releaseArriveHint)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, VSpace.m)
            .accessibilityElement(children: .combine)

            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            } else {
                VStack(spacing: 0) {
                    ForEach(methods) { m in
                        let svc = PaymentServiceRegistry.service(for: m.provider)
                        let available = m.enabled && (svc?.isAvailable ?? false)
                        Button { if available { selected = m.provider } } label: {
                            HStack(spacing: 12) {
                                Text(m.name)
                                    .font(.vBodyMedium)
                                    .foregroundStyle(available ? Color.vText : Color.vTextTertiary)
                                Spacer()
                                Image(systemName: selected == m.provider ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected == m.provider ? Color.vPrimary : Color.vFillStrong)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, VSpace.l)
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                        if m.id != methods.last?.id { VDivider(inset: 16) }
                    }
                }
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            }
            Spacer(minLength: 0)
            VPrimaryButton(
                title: "\(DepositCopy.freezeVerb) \(amount.display)",
                loading: paying,
                disabled: selected == nil,
                action: pay
            )
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
        .task { await bootstrap() }
    }

    private func bootstrap() async {
        async let methodsTask = API.paymentMethods()
        async let depositTask = API.lotDeposit(lot.id)
        methods = (try? await methodsTask) ?? []
        info = try? await depositTask
        if info?.isFrozen == true {
            ToastCenter.shared.show(DepositCopy.freezeSucceeded, .success)
            onPaid()
            dismiss()
            return
        }
        selected = methods.first {
            $0.enabled && (PaymentServiceRegistry.service(for: $0.provider)?.isAvailable ?? false)
        }?.provider
        loading = false
    }

    private func pay() {
        guard let provider = selected else { return }
        paying = true
        Task {
            defer { paying = false }
            do {
                var pm = try await API.createDepositPayment(
                    lotId: lot.id,
                    provider: provider,
                    idempotencyKey: payIdempotencyKey
                )
                if provider == "mock" {
                    pm = try await API.mockConfirm(pm.id, success: true)
                } else if let svc = PaymentServiceRegistry.service(for: provider) {
                    _ = await svc.launch(payment: pm)
                    pm = try await API.syncPayment(pm.id)
                }
                if pm.status == .succeeded {
                    // Poll until frozen (design §9).
                    for _ in 0..<6 {
                        if let latest = try? await API.lotDeposit(lot.id), latest.isFrozen {
                            ToastCenter.shared.show(DepositCopy.freezeSucceeded, .success)
                            onPaid()
                            dismiss()
                            return
                        }
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                    ToastCenter.shared.show(DepositCopy.freezeSucceeded, .success)
                    onPaid()
                    dismiss()
                } else {
                    payIdempotencyKey = APIClient.shared.idempotencyKey()
                    ToastCenter.shared.show("支付未完成，请重试", .error)
                }
            } catch let e as APIError where e.code == DepositErrorCode.creditTooLow.rawValue {
                ToastCenter.shared.show(
                    e.message.isEmpty ? DepositErrorCode.creditTooLow.fallbackMessage : e.message,
                    .info
                )
            } catch let e as APIError where e.code == DepositErrorCode.realNameRequired.rawValue
                || e.trustCode == .realNameRequired {
                ToastCenter.shared.show(
                    e.message.isEmpty ? DepositErrorCode.realNameRequired.fallbackMessage : e.message,
                    .info
                )
                AppRouterProxy.openRealName()
            } catch {
                payIdempotencyKey = APIClient.shared.idempotencyKey()
                ToastCenter.shared.error(error)
            }
        }
    }
}
