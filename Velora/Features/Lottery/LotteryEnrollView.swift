import SwiftUI

/// 抽签报名：资格 / 保证金 / 报名；中签付款 / 候补 / 凭证入口（DES-v1.3-06-02 §9）。
struct LotteryEnrollView: View {
    let releaseId: Int64

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: LotteryEnrollModel
    @ObservedObject private var ticker = Ticker.shared
    @State private var showAddressPicker = false
    @State private var showCashier = false
    @State private var paymentResult: PaymentResult?

    init(releaseId: Int64) {
        self.releaseId = releaseId
        _model = StateObject(wrappedValue: LotteryEnrollModel(releaseId: releaseId))
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
        .navigationTitle(LotteryCopy.pageTitle)
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
        .sheet(isPresented: $model.needsRealName) {
            NavigationStack { RealNameView() }
                .onDisappear { Task { await model.refresh() } }
        }
        .sheet(isPresented: $model.needsDeposit) {
            depositSheet
        }
        .sheet(isPresented: $showAddressPicker) {
            AddressListView(selecting: true) { addr in
                model.setAddress(addr)
            }
        }
        .sheet(isPresented: $model.openProof) {
            NavigationStack {
                LotteryDrawProofView(releaseId: releaseId)
            }
        }
        .sheet(isPresented: $showCashier) {
            if let order = model.payOrder {
                CashierSheet(order: order) { r in
                    showCashier = false
                    paymentResult = r
                }
                .presentationDetents([.height(460)]).presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $paymentResult) { r in
            PaymentResultView(result: r, order: model.payOrder) {
                paymentResult = nil
                Task { await model.refresh() }
            }
        }
        .onChange(of: model.openPayOrderId) { _, id in
            if id != nil, model.payOrder != nil {
                showCashier = true
            }
        }
        .onChange(of: ticker.now) { _, _ in
            _ = model.enrollCountdownSeconds
            _ = model.payCountdownSeconds
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: VSpace.l) {
                    hero
                    statusBlock
                    checklistCard
                    if model.cta == .waitlist, let entry = model.detail?.myEntry {
                        waitlistCard(entry)
                    }
                    if model.cta == .pay {
                        payDeadlineCard
                    }
                    if model.cta == .lost {
                        hintCard(LotteryCopy.depositReleased)
                    }
                    if model.cta == .forfeited {
                        hintCard(LotteryCopy.depositDeducted)
                    }
                    rulesSection
                }
                .padding(VSpace.l)
                .padding(.bottom, 100)
            }
            .refreshable { await model.refresh() }

            bottomBar
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            RemoteImage(model.detail?.cover ?? "")
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))

            HStack(spacing: 8) {
                VTagChip(text: "抽签", tint: .vGold, background: Color.vGold.opacity(0.15))
                if let status = model.detail?.status {
                    VTagChip(text: status.displayLabel, tint: .vTextSecondary, background: Color.vFill)
                }
                Spacer(minLength: 0)
            }

            Text(model.detail?.displayTitle ?? LotteryCopy.pageTitle)
                .font(.vTitle(22))
                .foregroundStyle(Color.vText)

            if let price = model.detail?.priceFen {
                VPriceText(amount: price, size: 28)
            }

            Text("名额 \(model.detail?.resolvedQuotaN ?? 0) · 候补 \(model.detail?.resolvedWaitlistM ?? 0) · 保证金 ¥\(LotteryLogic.formatYuan(model.detail?.resolvedDepositFen ?? LotteryConfigDefaults.depositDefaultFen))")
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
        }
    }

    private var statusBlock: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                if model.cta == .pay {
                    Text(LotteryCopy.payCTA)
                        .font(.vHeadline)
                    Text(LotteryLogic.payDeadlineCountdownLine(seconds: model.payCountdownSeconds))
                        .font(.vTitle(28).monospacedDigit())
                        .foregroundStyle(Color.vPrimary)
                        .accessibilityLabel("付款倒计时")
                        .accessibilityValue(LotteryLogic.formatCountdown(seconds: model.payCountdownSeconds))
                } else if model.enrollCountdownSeconds > 0 {
                    Text(model.cta == .waitEnrollOpen ? "距报名开始" : "距报名截止")
                        .font(.vHeadline)
                    Text(LotteryLogic.formatCountdown(seconds: model.enrollCountdownSeconds))
                        .font(.vTitle(28).monospacedDigit())
                        .foregroundStyle(Color.vPrimary)
                } else {
                    Text(model.cta.buttonTitle)
                        .font(.vHeadline)
                }
                Text(LotteryCopy.serverTimeHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private var checklistCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text("报名资格")
                    .font(.vHeadline)
                ForEach(model.checklist) { item in
                    HStack {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.done ? Color.vGreen : Color.vTextTertiary)
                        Text(item.step.title)
                            .font(.vBody)
                            .foregroundStyle(Color.vText)
                        Spacer()
                        if !item.done {
                            Button(item.step.actionTitle) {
                                Task {
                                    if item.step == .address {
                                        showAddressPicker = true
                                    } else {
                                        await model.completeEligibility()
                                    }
                                }
                            }
                            .font(.vCaption)
                        }
                    }
                }
                if let addr = model.address {
                    Button { showAddressPicker = true } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                            Text(addr.oneLine)
                                .lineLimit(1)
                            Spacer()
                            Text("更换").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        }
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func waitlistCard(_ entry: LotteryEntry) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(LotteryCopy.waitlist)
                    .font(.vHeadline)
                Text(
                    LotteryLogic.waitlistPositionLine(
                        rank: entry.resolvedWaitlistRank,
                        remainingUnpaid: entry.remainingUnpaidWon ?? model.detail?.remainingUnpaidWon
                    )
                )
                .font(.vBody)
                .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private var payDeadlineCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(LotteryCopy.payWindowHint)
                    .font(.vBody)
                Text(LotteryCopy.n12RemindHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                Text(LotteryCopy.forbiddenSpotBuyCTA)
                    .font(.vCaption)
                    .foregroundStyle(Color.vGold)
            }
        }
    }

    private func hintCard(_ text: String) -> some View {
        VCard {
            Text(text)
                .font(.vBody)
                .foregroundStyle(Color.vTextSecondary)
        }
    }

    private var rulesSection: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("规则")
                    .font(.vHeadline)
                Text(LotteryCopy.payWindowHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                Text("一人一签 · 多维去重 · 算法 \(model.detail?.resolvedAlgorithmVersion ?? LotteryConfigDefaults.algorithmVersion)")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                if model.detail?.status == .drawn || model.detail?.myEntry != nil {
                    Button(LotteryCopy.viewProof) {
                        model.openProof = true
                    }
                    .font(.vCaption)
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.vSeparator).frame(height: 0.5)
            VPrimaryButton(
                title: model.cta.buttonTitle,
                style: model.cta.isPrimaryAction ? .filled : .soft,
                disabled: model.busy || (!model.cta.isPrimaryAction && model.cta != .pay)
            ) {
                Task { await model.primaryAction() }
            }
            .padding(VSpace.l)
        }
        .background(Color.vSurface.ignoresSafeArea(edges: .bottom))
    }

    private var depositSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: VSpace.l) {
                Text("冻结保证金")
                    .font(.vTitle(22))
                Text("冻结 ¥\(LotteryLogic.formatYuan(model.detail?.resolvedDepositFen ?? LotteryConfigDefaults.depositDefaultFen)) 后即可报名。未中签开奖后将解冻；中签弃权将扣除并影响信用分。")
                    .font(.vBody)
                    .foregroundStyle(Color.vTextSecondary)
                Spacer()
                VPrimaryButton(title: "确认冻结并报名", disabled: model.busy) {
                    Task { await model.confirmDepositAndEnroll() }
                }
            }
            .padding(VSpace.l)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { model.needsDeposit = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
