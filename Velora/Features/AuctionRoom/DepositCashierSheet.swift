import SwiftUI

/// 竞拍押金收银台
struct DepositCashierSheet: View {
    let lot: Lot
    let onPaid: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var methods: [PaymentMethod] = []
    @State private var selected: String?
    @State private var loading = true
    @State private var paying = false

    var body: some View {
        VStack(spacing: VSpace.l) {
            VStack(spacing: 6) {
                Text("竞拍押金").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                VPriceText(amount: lot.depositAmount, size: 36, color: .vText)
                Text("出价前须缴纳；未中标全额退回，拍中可抵扣货款；逾期未付将按规则扣除部分押金。")
                    .font(.vMicro).foregroundStyle(Color.vTextTertiary).multilineTextAlignment(.center)
            }
            .padding(.top, VSpace.m)

            if loading { ProgressView().frame(maxWidth: .infinity, minHeight: 100) }
            else {
                VStack(spacing: 0) {
                    ForEach(methods) { m in
                        let svc = PaymentServiceRegistry.service(for: m.provider)
                        let available = m.enabled && (svc?.isAvailable ?? false)
                        Button { if available { selected = m.provider } } label: {
                            HStack(spacing: 12) {
                                Text(m.name).font(.vBodyMedium).foregroundStyle(available ? Color.vText : Color.vTextTertiary)
                                Spacer()
                                Image(systemName: selected == m.provider ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected == m.provider ? Color.vPrimary : Color.vFillStrong)
                            }
                            .padding(.vertical, 12).padding(.horizontal, VSpace.l)
                        }
                        .buttonStyle(.plain).disabled(!available)
                        if m.id != methods.last?.id { VDivider(inset: 16) }
                    }
                }
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            }
            Spacer(minLength: 0)
            VPrimaryButton(title: "缴纳押金 \(lot.depositAmount.display)", loading: paying, disabled: selected == nil, action: pay)
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
        .task {
            methods = (try? await API.paymentMethods()) ?? []
            selected = methods.first { $0.enabled && (PaymentServiceRegistry.service(for: $0.provider)?.isAvailable ?? false) }?.provider
            loading = false
        }
    }

    private func pay() {
        guard let provider = selected else { return }
        paying = true
        Task {
            defer { paying = false }
            do {
                var pm = try await API.createDepositPayment(lotId: lot.id, provider: provider)
                if provider == "mock" {
                    pm = try await API.mockConfirm(pm.id, success: true)
                } else if let svc = PaymentServiceRegistry.service(for: provider) {
                    _ = try await svc.pay(payload: pm.clientPayload ?? [:])
                    pm = try await API.syncPayment(pm.id)
                }
                if pm.status == .succeeded {
                    ToastCenter.shared.show("押金已缴纳，可以出价了", .success)
                    onPaid(); dismiss()
                } else {
                    ToastCenter.shared.show("支付未完成，请重试", .error)
                }
            } catch { ToastCenter.shared.error(error) }
        }
    }
}
