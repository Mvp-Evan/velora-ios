import SwiftUI

/// 卖家钱包：渠道二级商户余额投影 + 渠道提现（DES-v1.3-08-03 / PAY-09）。
struct WalletView: View {
    @State private var wallet: WalletProjection?
    @State private var ledger: [WalletLedgerEntry] = []
    @State private var withdrawals: [WithdrawalRequest] = []
    @State private var state: LoadState = .idle
    @State private var tab = 0
    @State private var showWithdraw = false
    @State private var forbiddenBuyer = false
    @State private var needSubMerchant = false

    var body: some View {
        Group {
            if forbiddenBuyer {
                VEmptyState(
                    icon: "person.crop.circle.badge.exclamationmark",
                    title: WalletCopy.buyerForbidden,
                    message: WalletCopy.guideOnboarding
                )
            } else if needSubMerchant {
                VEmptyState(
                    icon: "creditcard",
                    title: WalletCopy.subMerchantRequired,
                    message: WalletCopy.guideOnboarding,
                    actionTitle: ProfitSharingCopy.progressTitle
                ) {
                    // Navigation handled via links in Me; toast nudge.
                    ToastCenter.shared.show(WalletCopy.guideOnboarding, .info)
                }
            } else {
                content
            }
        }
        .background(Color.vBackground)
        .navigationTitle(WalletCopy.homeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showWithdraw) {
            if let w = wallet {
                WithdrawSheet(available: w.available) { Task { await load() } }
                    .presentationDetents([.height(420)])
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: VSpace.l) {
                disclaimer
                if let w = wallet {
                    cards(w)
                } else if state == .loading || state == .idle {
                    VSkeleton(radius: VRadius.xl).frame(height: 170).padding(.horizontal, VSpace.l)
                }

                VPillSegments(items: [(0, WalletCopy.ledgerTitle), (1, WalletCopy.withdrawalsTitle)], selection: $tab)

                switch state {
                case .idle, .loading: VLoadingView()
                case .failed(let m): VErrorView(message: m) { Task { await load() } }
                case .loaded:
                    if tab == 0 { ledgerList } else { withdrawalList }
                }
            }
            .padding(.vertical, VSpace.m)
        }
    }

    private var disclaimer: some View {
        Text(WalletCopy.custodyDisclaimer)
            .font(.vCaption)
            .foregroundStyle(Color.vTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VSpace.l)
            .accessibilityLabel(WalletCopy.custodyDisclaimer)
    }

    private func cards(_ w: WalletProjection) -> some View {
        VStack(spacing: VSpace.m) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous).fill(VGradient.carbon)
                Circle().fill(Color.vPrimary.opacity(0.8)).frame(width: 200, height: 200).offset(x: 220, y: -60).blur(radius: 40)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(WalletCopy.availableTitle).font(.vCaption).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        if w.showsSandboxWatermark {
                            Text(WalletCopy.sandboxWatermark)
                                .font(.vMicro)
                                .foregroundStyle(Color.vCarbon)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.vGold.opacity(0.9), in: Capsule())
                        } else {
                            Image(systemName: "wallet.pass.fill").foregroundStyle(Color.vGold)
                        }
                    }
                    VPriceText(amount: w.available, size: 36, color: .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            if w.hasSyncError || w.isStale() {
                                Text(w.hasSyncError ? WalletCopy.syncFailed : WalletCopy.staleHint)
                                    .font(.vMicro)
                                    .foregroundStyle(.white.opacity(0.75))
                            } else if let at = w.lastSyncedAt {
                                Text("同步于 \(at.relativeText)")
                                    .font(.vMicro)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Text(WalletCopy.withdrawArriveHint)
                                .font(.vMicro)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Button { showWithdraw = true } label: {
                            Text(WalletCopy.withdrawCTA).font(.vCaptionMedium).foregroundStyle(Color.vCarbon)
                                .padding(.horizontal, 16).padding(.vertical, 7).background(.white, in: Capsule())
                        }
                        .disabled(w.available < WalletConfigDefaults.withdrawMinFen)
                        .opacity(w.available < WalletConfigDefaults.withdrawMinFen ? 0.5 : 1)
                        .accessibilityLabel(WalletCopy.withdrawCTA)
                    }
                }
                .padding(VSpace.xl)
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous))

            HStack(spacing: VSpace.m) {
                pendingCard(w.pending)
            }
        }
        .padding(.horizontal, VSpace.l)
    }

    private func pendingCard(_ amount: Money) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(WalletCopy.pendingTitle).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    Spacer()
                    Image(systemName: "lock.fill").foregroundStyle(Color.vTextTertiary).font(.vCaption)
                }
                VPriceText(amount: amount, size: 20, color: .vTextSecondary)
                    .lineLimit(1)
                    .accessibilityLabel("\(WalletCopy.pendingTitle) \(amount.display)，\(WalletCopy.pendingHint)")
                Text(amount > 0 ? WalletCopy.pendingHint : WalletCopy.emptyBalance)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
            }
        }
    }

    private var ledgerList: some View {
        VCard(padding: 0) {
            if ledger.isEmpty {
                VEmptyState(icon: "list.bullet.rectangle", title: WalletCopy.emptyLedger, message: WalletCopy.ledgerNotPlatform)
            } else {
                VStack(spacing: 0) {
                    Text(WalletCopy.ledgerNotPlatform)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, VSpace.l)
                        .padding(.top, 12)
                    ForEach(ledger) { e in
                        HStack(spacing: 12) {
                            Image(systemName: e.isCredit ? "arrow.down.left" : "arrow.up.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(e.isCredit ? Color.vGreen : Color.vTextSecondary)
                                .frame(width: 32, height: 32).background(Color.vFill, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.accountLabel).font(.vBodyMedium)
                                if let no = e.orderNo, !no.isEmpty {
                                    Text(no).font(.vMicro).foregroundStyle(Color.vTextTertiary).lineLimit(1)
                                } else if let memo = e.memo, !memo.isEmpty {
                                    Text(memo).font(.vMicro).foregroundStyle(Color.vTextTertiary).lineLimit(1)
                                } else if let j = e.journalId {
                                    Text(j).font(.vMicro).foregroundStyle(Color.vTextTertiary).lineLimit(1)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text((e.isCredit ? "+" : "-") + e.amount.display)
                                    .font(.vMono(15))
                                    .foregroundStyle(e.isCredit ? Color.vGreen : Color.vText)
                                    .lineLimit(1)
                                if let at = e.createdAt {
                                    Text(at.relativeText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                                }
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
            if withdrawals.isEmpty {
                VEmptyState(icon: "banknote", title: WalletCopy.emptyWithdrawals)
            } else {
                VStack(spacing: 0) {
                    ForEach(withdrawals) { w in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("渠道提现").font(.vBodyMedium)
                                if let at = w.createdAt {
                                    Text(at.fullText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                                }
                                if let fail = w.failureDisplay {
                                    Text(fail).font(.vMicro).foregroundStyle(Color.vPrimary).lineLimit(2)
                                } else if w.requiresReopenChannelWithdraw {
                                    Text(WalletCopy.reopenChannelWithdraw).font(.vMicro).foregroundStyle(Color.vPrimary)
                                } else if let no = w.channelWithdrawNo, !no.isEmpty {
                                    Text(no).font(.vMicro).foregroundStyle(Color.vTextTertiary).lineLimit(1)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(w.amount.display).font(.vMono(15)).lineLimit(1)
                                Text(w.statusLabel)
                                    .font(.vMicro)
                                    .foregroundStyle(withdrawColor(w.status))
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

    private func withdrawColor(_ s: WithdrawalStatus) -> Color {
        switch s {
        case .succeeded: return .vGreen
        case .failed: return .vPrimary
        case .created, .channelPending: return .vGold
        }
    }

    private func load() async {
        forbiddenBuyer = false
        needSubMerchant = false
        if wallet == nil { state = .loading }
        do {
            async let w = API.wallet()
            async let l = API.ledger()
            async let d = API.withdrawals()
            wallet = try await w
            ledger = try await l.items
            withdrawals = try await d
            state = .loaded
        } catch let e as APIError {
            let code = WalletErrorCode.normalize(e.code)
            if code == .forbidden {
                forbiddenBuyer = true
                state = .loaded
            } else if code == .subMerchantRequired {
                needSubMerchant = true
                state = .loaded
            } else {
                state = .failed(WalletWithdrawLogic.message(for: e.code, serverMessage: e.message))
            }
        } catch {
            state = .failed("加载失败")
        }
    }
}

struct WithdrawSheet: View {
    let available: Money
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var yuan = ""
    @State private var working = false
    @State private var confirm = false
    @State private var idemKey = APIClient.shared.idempotencyKey()

    private var amount: Money? { Double(yuan).map { Money(($0 * 100).rounded()) } }
    private var valid: Bool {
        guard let amount else { return false }
        return WalletWithdrawLogic.isAmountValid(amountFen: amount, availableFen: available)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VSpace.l) {
            Text(WalletCopy.withdrawCTA).font(.vTitle(20))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥").font(.vPrice(22))
                TextField("0.00", text: $yuan).keyboardType(.decimalPad).font(.vPrice(34))
                Spacer()
                Button("全部") {
                    yuan = String(format: "%.2f", available.yuan)
                }.font(.vCaptionMedium)
            }
            .padding(.horizontal, VSpace.l).frame(height: 64)
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("可提现 \(available.display)，\(WalletCopy.withdrawMinHint)")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                Text(WalletCopy.withdrawArriveHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                Text(WalletCopy.withdrawFeeHint)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                Text(WalletCopy.custodyDisclaimer)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
            }

            Spacer()
            VPrimaryButton(
                title: working ? WalletCopy.withdrawLoading : WalletCopy.withdrawConfirmTitle,
                loading: working,
                disabled: !valid
            ) {
                confirm = true
            }
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
        .confirmationDialog(
            WalletCopy.withdrawConfirmTitle,
            isPresented: $confirm,
            titleVisibility: .visible
        ) {
            Button(WalletCopy.withdrawCTA) { Task { await submit() } }
            Button("取消", role: .cancel) {}
        } message: {
            if let amount {
                Text("提现 \(amount.display) 至渠道结算账户")
            }
        }
    }

    private func submit() async {
        guard let amount else { return }
        if let err = WalletWithdrawLogic.canSubmit(amountFen: amount, availableFen: available) {
            ToastCenter.shared.show(err.fallbackMessage, .error)
            return
        }
        working = true
        defer { working = false }
        do {
            _ = try await API.requestWithdrawal(amount: amount, idempotencyKey: idemKey)
            ToastCenter.shared.show(WalletCopy.withdrawSubmitted, .success)
            done()
            dismiss()
        } catch let e as APIError {
            // Keep same idempotency key on retryable in-flight; rotate on conflict / success path.
            let code = WalletErrorCode.normalize(e.code)
            if code == .missingIdempotencyKey {
                idemKey = APIClient.shared.idempotencyKey()
            }
            ToastCenter.shared.show(WalletWithdrawLogic.message(for: e.code, serverMessage: e.message), .error)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}
