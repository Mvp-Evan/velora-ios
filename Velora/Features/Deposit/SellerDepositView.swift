import SwiftUI

/// 卖家保证金：应缴/已缴/缺口、补缴、退出（DES-v1.3-08-02 PAY-07 / §9）.
struct SellerDepositView: View {
    var presentedAsSheet: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var account: SellerDepositAccount?
    @State private var items: [Deposit] = []
    @State private var loading = true
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var methods: [PaymentMethod] = []
    @State private var selectedProvider: String?
    @State private var showTopUp = false
    @State private var showExitConfirm = false
    @State private var payKey = APIClient.shared.idempotencyKey()
    @State private var exitKey = APIClient.shared.idempotencyKey()

    var body: some View {
        Group {
            if loading && account == nil && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, account == nil && items.isEmpty {
                VErrorView(message: errorMessage) { Task { await load() } }
            } else {
                content
            }
        }
        .background(Color.vBackground)
        .navigationTitle(DepositCopy.sellerPageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showTopUp) { topUpSheet }
        .alert("确认退出卖家？", isPresented: $showExitConfirm) {
            Button("取消", role: .cancel) {}
            Button("申请退出", role: .destructive) {
                Task { await exitSeller() }
            }
        } message: {
            Text("退出后不可发布；最后一笔订单完结满 \(DepositConfigDefaults.sellerExitDays) 天后退还保证金。")
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                if let account {
                    statusCard(account)
                    actions(account)
                } else {
                    VCard {
                        Text(DepositCopy.sellerGapHint)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                        VPrimaryButton(title: DepositCopy.sellerTopUpCTA, loading: busy) {
                            showTopUp = true
                        }
                    }
                }

                if !items.isEmpty {
                    Text("冻结记录")
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vTextSecondary)
                    ForEach(items) { d in
                        VCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(d.statusLabel)
                                        .font(.vBodyMedium)
                                    Text(d.methodUserLabel)
                                        .font(.vMicro)
                                        .foregroundStyle(Color.vTextTertiary)
                                }
                                Spacer()
                                Text(d.amount.display)
                                    .font(.vHeadline)
                            }
                        }
                    }
                }
            }
            .padding(VSpace.l)
        }
    }

    private func statusCard(_ a: SellerDepositAccount) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                if let tier = a.sellerType {
                    Text(tier.displayLabel)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
                HStack {
                    metric("应缴", a.requiredAmount)
                    metric("已缴", a.heldAmount)
                    metric("缺口", a.gapAmount, emphasize: a.gapAmount > 0)
                }
                if a.blocksPublish {
                    Text(a.gapMessage)
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vPrimary)
                        .accessibilityLabel(a.gapMessage)
                } else {
                    Text(DepositCopy.alreadySufficient)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
                if let exitMsg = a.exitMessage {
                    Text(exitMsg)
                        .font(.vCaption)
                        .foregroundStyle(Color.vGold)
                }
            }
        }
    }

    private func metric(_ title: String, _ fen: Int64, emphasize: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.vMicro)
                .foregroundStyle(Color.vTextTertiary)
            Text(fen.display)
                .font(.vBodyMedium)
                .foregroundStyle(emphasize ? Color.vPrimary : Color.vText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actions(_ a: SellerDepositAccount) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                if a.blocksPublish {
                    VPrimaryButton(title: DepositCopy.sellerTopUpCTA, loading: busy) {
                        showTopUp = true
                    }
                    Text(DepositCopy.sellerGapHint)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                } else {
                    VPrimaryButton(title: "刷新状态", style: .outline, loading: busy) {
                        Task { await load() }
                    }
                }
                if !a.isExiting {
                    VPrimaryButton(title: DepositCopy.sellerExitCTA, style: .soft, loading: busy) {
                        showExitConfirm = true
                    }
                }
            }
        }
    }

    private var topUpSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: VSpace.l) {
                Text(DepositCopy.freezeTitle)
                    .font(.vTitle(22))
                if let gap = account?.gapAmount, gap > 0 {
                    VPriceText(amount: gap, size: 32, color: .vText)
                    Text(account?.gapMessage ?? DepositCopy.sellerGapTitle)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
                Text(DepositCopy.noTechDiffHint)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                ForEach(methods) { m in
                    let available = m.enabled && (PaymentServiceRegistry.service(for: m.provider)?.isAvailable ?? false)
                    Button {
                        if available { selectedProvider = m.provider }
                    } label: {
                        HStack {
                            Text(m.name).foregroundStyle(available ? Color.vText : Color.vTextTertiary)
                            Spacer()
                            Image(systemName: selectedProvider == m.provider ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedProvider == m.provider ? Color.vPrimary : Color.vFillStrong)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                }
                Spacer()
                VPrimaryButton(
                    title: DepositCopy.sellerTopUpCTA,
                    loading: busy,
                    disabled: selectedProvider == nil
                ) {
                    Task { await topUp() }
                }
            }
            .padding(VSpace.l)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showTopUp = false }
                }
            }
            .task {
                methods = (try? await API.paymentMethods()) ?? []
                selectedProvider = methods.first {
                    $0.enabled && (PaymentServiceRegistry.service(for: $0.provider)?.isAvailable ?? false)
                }?.provider
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        if account == nil && items.isEmpty { loading = true }
        errorMessage = nil
        defer { loading = false }
        do {
            let resp = try await API.myDeposits(type: DepositType.seller.rawValue)
            items = resp.items
            if let acct = resp.sellerAccount {
                account = acct
            } else if let first = resp.items.first {
                // Fallback projection when server only returns deposit rows.
                let held = resp.items
                    .filter { $0.status.isActiveFreeze || $0.status == .frozen }
                    .reduce(Int64(0)) { $0 + $1.amount }
                let required = max(first.amount, DepositConfigDefaults.sellerPersonalFen)
                account = SellerDepositAccount(
                    userId: first.userId,
                    requiredAmount: required,
                    heldAmount: held > 0 ? held : (first.status.allowsBidding ? first.amount : 0),
                    status: first.status
                )
            }
        } catch let e as APIError {
            errorMessage = e.message.isEmpty ? "加载失败" : e.message
        } catch {
            errorMessage = "加载失败"
        }
    }

    private func topUp() async {
        guard let provider = selectedProvider else { return }
        busy = true
        defer { busy = false }
        do {
            let gap = account?.gapAmount
            var pm = try await API.createSellerDepositPayment(
                amount: (gap ?? 0) > 0 ? gap : nil,
                provider: provider,
                idempotencyKey: payKey
            )
            if provider == "mock" {
                pm = try await API.mockConfirm(pm.id, success: true)
            } else if let svc = PaymentServiceRegistry.service(for: provider) {
                _ = await svc.launch(payment: pm)
                pm = try await API.syncPayment(pm.id)
            }
            if pm.status == .succeeded {
                ToastCenter.shared.show(DepositCopy.topUpSucceeded, .success)
                showTopUp = false
                payKey = APIClient.shared.idempotencyKey()
                await load()
            } else {
                payKey = APIClient.shared.idempotencyKey()
                ToastCenter.shared.show("支付未完成，请重试", .error)
            }
        } catch let e as APIError where e.code == DepositErrorCode.alreadySufficient.rawValue {
            ToastCenter.shared.show(DepositCopy.alreadySufficient, .info)
            showTopUp = false
            await load()
        } catch {
            payKey = APIClient.shared.idempotencyKey()
            ToastCenter.shared.error(error)
        }
    }

    private func exitSeller() async {
        busy = true
        defer { busy = false }
        do {
            let resp = try await API.exitSellerDeposit(idempotencyKey: exitKey)
            let msg = resp.message?.isEmpty == false
                ? (resp.message ?? DepositCopy.exitRequested)
                : (resp.remainingDays.map { SellerDepositLogic.exitCoolingMessage(remainingDays: $0) }
                    ?? DepositCopy.exitRequested)
            ToastCenter.shared.show(msg, .success)
            exitKey = APIClient.shared.idempotencyKey()
            await load()
        } catch let e as APIError where e.code == DepositErrorCode.openOrdersExist.rawValue {
            ToastCenter.shared.show(
                e.message.isEmpty ? DepositErrorCode.openOrdersExist.fallbackMessage : e.message,
                .info
            )
        } catch let e as APIError where e.code == DepositErrorCode.exitCooling.rawValue {
            ToastCenter.shared.show(
                e.message.isEmpty ? DepositErrorCode.exitCooling.fallbackMessage : e.message,
                .info
            )
            await load()
        } catch {
            exitKey = APIClient.shared.idempotencyKey()
            ToastCenter.shared.error(error)
        }
    }
}
