import SwiftUI

struct WalletView: View {
    @State private var wallet: Wallet?
    @State private var ledger: [LedgerEntry] = []
    @State private var withdrawals: [WithdrawalRequest] = []
    @State private var state: LoadState = .idle
    @State private var tab = 0
    @State private var showWithdraw = false

    var body: some View {
        ScrollView {
            VStack(spacing: VSpace.l) {
                if let w = wallet { cards(w) } else { VSkeleton(radius: VRadius.xl).frame(height: 170).padding(.horizontal, VSpace.l) }

                VPillSegments(items: [(0, "收支明细"), (1, "提现记录")], selection: $tab)

                switch state {
                case .idle, .loading: VLoadingView()
                case .failed(let m): VErrorView(message: m) { Task { await load() } }
                case .loaded:
                    if tab == 0 { ledgerList } else { withdrawalList }
                }
            }
            .padding(.vertical, VSpace.m)
        }
        .background(Color.vBackground)
        .navigationTitle("我的钱包")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showWithdraw) {
            if let w = wallet { WithdrawSheet(available: w.availableBalance) { Task { await load() } }.presentationDetents([.height(480)]) }
        }
    }

    private func cards(_ w: Wallet) -> some View {
        VStack(spacing: VSpace.m) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous).fill(VGradient.carbon)
                Circle().fill(Color.vPrimary.opacity(0.8)).frame(width: 200, height: 200).offset(x: 220, y: -60).blur(radius: 40)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("可用余额").font(.vCaption).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Image(systemName: "wallet.pass.fill").foregroundStyle(Color.vGold)
                    }
                    VPriceText(amount: w.availableBalance, size: 36, color: .white)
                    HStack {
                        Text("累计收入 \(w.totalIncome.display)").font(.vMicro).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Button { showWithdraw = true } label: {
                            Text("提现").font(.vCaptionMedium).foregroundStyle(Color.vCarbon)
                                .padding(.horizontal, 16).padding(.vertical, 7).background(.white, in: Capsule())
                        }
                        .disabled(w.availableBalance < 100)
                        .opacity(w.availableBalance < 100 ? 0.5 : 1)
                    }
                }
                .padding(VSpace.xl)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous))

            HStack(spacing: VSpace.m) {
                smallCard("在途货款", w.pendingBalance, "买家确认收货后入账", .vGold, "clock.badge.checkmark")
                smallCard("累计提现", w.totalWithdrawn, "已到账银行卡", .vGreen, "arrow.down.to.line")
            }
        }
        .padding(.horizontal, VSpace.l)
    }

    private func smallCard(_ title: String, _ amount: Money, _ sub: String, _ tint: Color, _ icon: String) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(title).font(.vCaption).foregroundStyle(Color.vTextSecondary); Spacer(); Image(systemName: icon).foregroundStyle(tint).font(.vCaption) }
                VPriceText(amount: amount, size: 20, color: .vText)
                Text(sub).font(.vMicro).foregroundStyle(Color.vTextTertiary)
            }
        }
    }

    private var ledgerList: some View {
        VCard(padding: 0) {
            if ledger.isEmpty { VEmptyState(icon: "list.bullet.rectangle", title: "暂无收支记录") }
            else {
                VStack(spacing: 0) {
                    ForEach(ledger) { e in
                        HStack(spacing: 12) {
                            Image(systemName: e.direction == "credit" ? "arrow.down.left" : "arrow.up.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(e.direction == "credit" ? Color.vGreen : Color.vTextSecondary)
                                .frame(width: 32, height: 32).background(Color.vFill, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.accountLabel).font(.vBodyMedium)
                                Text(e.memo.isEmpty ? e.journalId : e.memo).font(.vMicro).foregroundStyle(Color.vTextTertiary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text((e.direction == "credit" ? "+" : "-") + e.amount.display).font(.vMono(15)).foregroundStyle(e.direction == "credit" ? Color.vGreen : Color.vText)
                                Text(e.createdAt.relativeText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                            }
                        }
                        .padding(.horizontal, VSpace.l).padding(.vertical, 12)
                        if e.id != ledger.last?.id { VDivider(inset: 60) }
                    }
                }
            }
        }
        .padding(.horizontal, VSpace.l)
    }

    private var withdrawalList: some View {
        VCard(padding: 0) {
            if withdrawals.isEmpty { VEmptyState(icon: "banknote", title: "暂无提现记录") }
            else {
                VStack(spacing: 0) {
                    ForEach(withdrawals) { w in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("提现至 \(w.bankAccount?["bank_name"] ?? "银行卡")").font(.vBodyMedium)
                                Text(w.createdAt.fullText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                                if let n = w.note, !n.isEmpty { Text(n).font(.vMicro).foregroundStyle(Color.vPrimary) }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(w.amount.display).font(.vMono(15))
                                Text(w.statusLabel).font(.vMicro).foregroundStyle(w.status == "paid" ? Color.vGreen : (w.status == "rejected" ? Color.vPrimary : Color.vGold))
                            }
                        }
                        .padding(.horizontal, VSpace.l).padding(.vertical, 12)
                        if w.id != withdrawals.last?.id { VDivider() }
                    }
                }
            }
        }
        .padding(.horizontal, VSpace.l)
    }

    private func load() async {
        if wallet == nil { state = .loading }
        do {
            async let w = API.wallet()
            async let l = API.ledger()
            async let d = API.withdrawals()
            wallet = try await w; ledger = try await l.items; withdrawals = try await d
            state = .loaded
        } catch { state = .failed((error as? APIError)?.message ?? "加载失败") }
    }
}

struct WithdrawSheet: View {
    let available: Money
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var yuan = ""
    @State private var bank = ""
    @State private var name = ""
    @State private var account = ""
    @State private var working = false

    private var amount: Money? { Double(yuan).map { Money(($0 * 100).rounded()) } }
    private var valid: Bool { (amount ?? 0) >= 100 && (amount ?? 0) <= available && !bank.isBlank && !name.isBlank && account.count >= 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: VSpace.l) {
            Text("提现").font(.vTitle(20))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥").font(.vPrice(22))
                TextField("0.00", text: $yuan).keyboardType(.decimalPad).font(.vPrice(34))
                Spacer()
                Button("全部") { yuan = String(format: "%.2f", available.yuan) }.font(.vCaptionMedium)
            }
            .padding(.horizontal, VSpace.l).frame(height: 64)
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            Text("可提现 \(available.display)，最低 ¥1，1-3 个工作日到账").font(.vCaption).foregroundStyle(Color.vTextSecondary)

            VStack(spacing: 0) {
                VFormRow(title: "开户行") { TextField("如：招商银行", text: $bank).multilineTextAlignment(.trailing) }
                VDivider()
                VFormRow(title: "户名") { TextField("与实名一致", text: $name).multilineTextAlignment(.trailing) }
                VDivider()
                VFormRow(title: "卡号") { TextField("银行卡号", text: $account).keyboardType(.numberPad).font(.vMono(15)).multilineTextAlignment(.trailing) }
            }
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))

            Spacer()
            VPrimaryButton(title: "申请提现", loading: working, disabled: !valid) {
                guard let a = amount else { return }
                working = true
                Task {
                    defer { working = false }
                    do { _ = try await API.requestWithdrawal(amount: a, bankName: bank, accountName: name, accountNo: account); ToastCenter.shared.show("提现申请已提交", .success); done(); dismiss() }
                    catch { ToastCenter.shared.error(error) }
                }
            }
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
    }
}
