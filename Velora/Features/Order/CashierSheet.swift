import SwiftUI

struct PaymentResult: Identifiable {
    enum Outcome { case success, pending, failed(String), cancelled }
    let id = UUID()
    let outcome: Outcome
    let payment: Payment?
}

/// 收银台：选择支付方式 → 创建支付单 → 拉起 SDK → 轮询服务端确认
struct CashierSheet: View {
    let order: Order
    let onFinish: (PaymentResult) -> Void
    @State private var methods: [PaymentMethod] = []
    @State private var selected: String?
    @State private var loading = true
    @State private var paying = false
    @State private var stage = ""
    @ObservedObject private var ticker = Ticker.shared

    var body: some View {
        VStack(spacing: VSpace.l) {
            VStack(spacing: 6) {
                Text("订单金额").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                VPriceText(amount: order.payAmount, size: 36, color: .vText)
                if order.depositApplied > 0 {
                    Text("已抵扣押金 \(order.depositApplied.display)").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "timer").font(.system(size: 10))
                    Text("支付剩余 \(order.payDeadline.countdownText(to: ticker.now))").font(.vMono(12, weight: .medium))
                }
                .foregroundStyle(Color.vPrimary)
            }
            .padding(.top, VSpace.m)

            if loading { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
            else {
                VStack(spacing: 0) {
                    ForEach(methods) { m in
                        let svc = PaymentServiceRegistry.service(for: m.provider)
                        let available = m.enabled && (svc?.isAvailable ?? false)
                        Button { if available { selected = m.provider } } label: {
                            HStack(spacing: 12) {
                                methodIcon(m.provider)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).font(.vBodyMedium).foregroundStyle(available ? Color.vText : Color.vTextTertiary)
                                    Text(available ? m.description : "SDK 未接入，见 docs/payments.md").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                                }
                                Spacer()
                                Image(systemName: selected == m.provider ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20)).foregroundStyle(selected == m.provider ? Color.vPrimary : Color.vFillStrong)
                            }
                            .padding(.vertical, 12).padding(.horizontal, VSpace.l)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                        if m.id != methods.last?.id { VDivider(inset: 58) }
                    }
                }
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            }

            Spacer(minLength: 0)

            if paying {
                HStack(spacing: 8) { ProgressView().tint(Color.vPrimary); Text(stage).font(.vCaption).foregroundStyle(Color.vTextSecondary) }
            }
            VPrimaryButton(title: "确认支付 \(order.payAmount.display)", loading: paying, disabled: selected == nil, action: pay)
            Text("支付由第三方渠道完成，Velora 不会保存您的支付密码").font(.vMicro).foregroundStyle(Color.vTextTertiary)
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
        .task {
            methods = (try? await API.paymentMethods()) ?? []
            selected = methods.first { $0.enabled && (PaymentServiceRegistry.service(for: $0.provider)?.isAvailable ?? false) }?.provider
            loading = false
        }
    }

    private func methodIcon(_ p: String) -> some View {
        let (sym, color): (String, Color) = {
            switch p {
            case "alipay": return ("a.circle.fill", Color(hex: 0x1677FF))
            case "wechatpay": return ("message.circle.fill", Color(hex: 0x07C160))
            default: return ("wand.and.stars", Color.vGold)
            }
        }()
        return Image(systemName: sym).font(.system(size: 26)).foregroundStyle(color).frame(width: 30)
    }

    private func pay() {
        guard let provider = selected, let svc = PaymentServiceRegistry.service(for: provider) else { return }
        paying = true
        Task {
            defer { paying = false }
            stage = "正在创建支付单…"
            let payment: Payment
            do { payment = try await API.createPayment(orderId: order.id, provider: provider) }
            catch { ToastCenter.shared.error(error); return }

            stage = "正在拉起\(providerName(provider))…"
            let launch = await svc.launch(payment: payment)
            switch launch {
            case .cancelled:
                onFinish(PaymentResult(outcome: .cancelled, payment: payment)); return
            case .failed(let m):
                onFinish(PaymentResult(outcome: .failed(m), payment: payment)); return
            case .unavailable:
                onFinish(PaymentResult(outcome: .failed("该支付方式尚未接入 SDK"), payment: payment)); return
            case .launched, .completed:
                break
            }

            stage = "正在确认支付结果…"
            let final = await poll(payment.id)
            switch final?.status {
            case .succeeded: onFinish(PaymentResult(outcome: .success, payment: final))
            case .failed, .closed: onFinish(PaymentResult(outcome: .failed(final?.failReason ?? "支付未完成"), payment: final))
            default: onFinish(PaymentResult(outcome: .pending, payment: final ?? payment))
            }
        }
    }

    /// 轮询 GET /payments/:id，最多 ~15s；中途尝试一次主动同步
    private func poll(_ id: Int64) async -> Payment? {
        var last: Payment?
        for i in 0..<10 {
            if let p = try? await API.payment(id) {
                last = p
                if p.status == .succeeded || p.status == .failed || p.status == .closed { return p }
            }
            if i == 4 { last = (try? await API.syncPayment(id)) ?? last; if last?.status == .succeeded { return last } }
            try? await Task.sleep(for: .seconds(1.5))
        }
        return last
    }
}

// MARK: - Result

struct PaymentResultView: View {
    let result: PaymentResult
    let order: Order?
    let close: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: VSpace.xl) {
            Spacer()
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 120, height: 120)
                Image(systemName: icon).font(.system(size: 56, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(spacing: 8) {
                Text(title).font(.vTitle(24))
                Text(message).font(.vBody).foregroundStyle(Color.vTextSecondary).multilineTextAlignment(.center)
            }
            if case .success = result.outcome, let o = order {
                VCard {
                    VStack(spacing: 8) {
                        VKeyValue(key: "实付金额", value: o.buyerTotal.display, valueColor: .vPrimary, bold: true)
                        VKeyValue(key: "支付方式", value: providerName(result.payment?.provider ?? ""))
                        VKeyValue(key: "订单编号", value: o.orderNo)
                    }
                }
                .padding(.horizontal, VSpace.xl)
            }
            Spacer()
            VPrimaryButton(title: "完成", style: .dark) { dismiss(); close() }.padding(.horizontal, VSpace.xl)
        }
        .padding(.bottom, VSpace.xl)
        .background(Color.vBackground)
    }

    private var tint: Color {
        switch result.outcome { case .success: return .vGreen; case .pending: return .vGold; case .failed: return .vPrimary; case .cancelled: return .vTextSecondary }
    }
    private var icon: String {
        switch result.outcome { case .success: return "checkmark"; case .pending: return "hourglass"; case .failed: return "xmark"; case .cancelled: return "arrow.uturn.left" }
    }
    private var title: String {
        switch result.outcome { case .success: return "支付成功"; case .pending: return "支付处理中"; case .failed: return "支付失败"; case .cancelled: return "已取消支付" }
    }
    private var message: String {
        switch result.outcome {
        case .success: return "卖家将在 48 小时内发货，请留意物流信息"
        case .pending: return "支付结果确认中，稍后可在订单详情查看，请勿重复支付"
        case .failed(let m): return m
        case .cancelled: return "订单仍为您保留，请在截止时间前完成付款"
        }
    }
}
