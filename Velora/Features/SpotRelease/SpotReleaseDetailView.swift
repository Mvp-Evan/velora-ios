import SwiftUI

/// 现货发售抢购页：倒计时 / 预约 → 抢购；独家资格；VIP 窗口；售罄空态（DES-v1.3-06-01 §9）。
struct SpotReleaseDetailView: View {
    let releaseId: Int64

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SpotReleaseModel
    @ObservedObject private var ticker = Ticker.shared
    @State private var showAddressPicker = false
    @State private var showCashier = false
    @State private var paymentResult: PaymentResult?

    init(releaseId: Int64) {
        self.releaseId = releaseId
        _model = StateObject(wrappedValue: SpotReleaseModel(releaseId: releaseId))
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
        .navigationTitle(SpotReleaseCopy.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
        }
        .onAppear { router.hideTabBar = true }
        .onDisappear {
            model.stopPolling()
            router.hideTabBar = false
        }
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
        .sheet(isPresented: $model.needsExclusiveDeposit) {
            exclusiveDepositSheet
        }
        .sheet(isPresented: $showAddressPicker) {
            AddressListView(selecting: true) { addr in
                model.setAddress(addr)
            }
        }
        .sheet(isPresented: $showCashier) {
            if let order = model.createdOrder {
                CashierSheet(order: order) { r in
                    showCashier = false
                    paymentResult = r
                }
                .presentationDetents([.height(460)]).presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $paymentResult) { r in
            PaymentResultView(result: r, order: model.createdOrder) {
                paymentResult = nil
                dismiss()
            }
        }
        .onChange(of: model.createdOrderId) { _, id in
            if id != nil, model.createdOrder != nil {
                showCashier = true
            }
        }
        .onChange(of: ticker.now) { _, _ in
            // Drive countdown redraw from shared 1s ticker; sale_open still from poll.
            _ = model.countdownSeconds
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: VSpace.l) {
                    if model.showSoldOut || model.cta == .soldOut {
                        soldOutEmpty
                    } else {
                        hero
                        countdownBlock
                        if let detail = model.detail, detail.isExclusive {
                            exclusiveChecklist(detail)
                        }
                        if model.cta == .waitVIPWindow || model.vipClosedCopy != nil {
                            vipWindowBanner
                        }
                        skuSection
                        rulesSection
                    }
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
                if model.detail?.isExclusive == true {
                    VTagChip(text: SpotReleaseCopy.exclusiveBadge, tint: .vGold, background: Color.vGold.opacity(0.15))
                }
                if model.detail?.isConvertedFromPresale == true {
                    VTagChip(text: SpotReleaseCopy.convertedPresaleHint, tint: .vBlue, background: Color.vBlue.opacity(0.12))
                }
                if let status = model.detail?.status {
                    VTagChip(text: status.displayLabel, tint: .vTextSecondary, background: Color.vFill)
                }
                Spacer(minLength: 0)
            }

            Text(model.detail?.displayTitle ?? SpotReleaseCopy.pageTitle)
                .font(.vTitle(22))
                .foregroundStyle(Color.vText)

            if let sku = model.selectedSKU, let price = sku.priceFen {
                VPriceText(amount: price, size: 28)
            }

            if let remaining = model.detail?.resolvedRemaining {
                Text("剩余 \(remaining) · 限购 \(model.detail?.resolvedLimitPerUser ?? 1) 件")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private var countdownBlock: some View {
        VStack(spacing: 8) {
            if SpotReleaseLogic.isSaleOpen(model.detail ?? SpotReleaseDetail(id: releaseId), serverNow: model.serverNow) {
                Text("抢购进行中")
                    .font(.vHeadline)
                    .foregroundStyle(Color.vPrimary)
            } else {
                Text(model.countdownLine)
                    .font(.vMono(28, weight: .bold))
                    .foregroundStyle(Color.vText)
                    .contentTransition(.numericText())
                    .accessibilityLabel("开售倒计时")
                    .accessibilityValue(model.countdownLine)
            }
            Text(SpotReleaseCopy.serverTimeHint)
                .font(.vCaption)
                .foregroundStyle(Color.vTextTertiary)
            if model.showsClockSkewBanner {
                Text("设备时间与服务器偏差较大，请以服务器时间为准")
                    .font(.vMicro)
                    .foregroundStyle(Color.vGold)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, VSpace.m)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func exclusiveChecklist(_ detail: SpotReleaseDetail) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("独家首发资格").font(.vHeadline)
                Text("完成以下步骤后即可抢购")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                ForEach(model.exclusiveChecklist) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.done ? Color.vGreen : Color.vTextTertiary)
                        Text(item.step.title)
                            .font(.vBody)
                            .foregroundStyle(Color.vText)
                        Spacer()
                        if !item.done {
                            Button(item.step.actionTitle) {
                                Task { await model.completeEligibility() }
                            }
                            .font(.vCaptionMedium)
                            .foregroundStyle(Color.vPrimary)
                        }
                    }
                }
                if detail.resolvedDepositFen > 0 {
                    Text("保证金 ¥\(SpotReleaseLogic.formatYuan(detail.resolvedDepositFen))（发售结束未成交将解冻）")
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private var vipWindowBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SpotReleaseCopy.vipWindowClosed)
                .font(.vBodyMedium)
                .foregroundStyle(Color.vText)
            Text(model.vipClosedCopy ?? SpotReleaseCopy.viewVIPRules)
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VSpace.m)
        .background(Color.vGold.opacity(0.12), in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }

    private var skuSection: some View {
        Group {
            if let skus = model.detail?.skus, skus.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("规格").font(.vHeadline)
                    FlowSKUChips(skus: skus, selectedId: model.selectedSKUId) { id in
                        model.selectSKU(id)
                    }
                }
            }
        }
    }

    private var rulesSection: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("规则").font(.vHeadline)
                Text(SpotReleaseCopy.payWindowHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                Text(SpotReleaseCopy.shipWindowHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                Text(SpotReleaseCopy.serverTimeHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
            }
        }
    }

    private var soldOutEmpty: some View {
        VStack(spacing: VSpace.l) {
            Image(systemName: "bag.badge.minus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.vTextTertiary)
            Text(SpotReleaseCopy.soldOut)
                .font(.vTitle(20))
                .foregroundStyle(Color.vText)
            Text(model.detail?.isConvertedFromPresale == true
                  ? SpotReleaseCopy.convertedPresaleHint
                  : SpotReleaseCopy.soldOutHint)
                .font(.vBody)
                .foregroundStyle(Color.vTextSecondary)
                .multilineTextAlignment(.center)
            VPrimaryButton(title: SpotReleaseCopy.emptySoldOutSubscribe, style: .soft, height: 44) {
                ToastCenter.shared.show("补货订阅即将开放", .info)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if model.cta == .rush {
                Button {
                    showAddressPicker = true
                } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                        Text(model.address.map { "\($0.name) \($0.phone)" } ?? "选择收货地址（可先抢后填）")
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }

            VPrimaryButton(
                title: model.cta.buttonTitle,
                loading: model.busy,
                disabled: !model.cta.isPrimaryAction && model.cta != .waitVIPWindow && model.cta != .soldOut,
                height: 48
            ) {
                Task { await model.primaryAction() }
            }
        }
        .padding(.horizontal, VSpace.l)
        .padding(.top, VSpace.m)
        .padding(.bottom, VSpace.s)
        .background(
            Color.vSurface.ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Rectangle().fill(Color.vSeparator).frame(height: 0.5) }
        )
    }

    private var exclusiveDepositSheet: some View {
        NavigationStack {
            VStack(spacing: VSpace.l) {
                Text("独家首发保证金")
                    .font(.vTitle(20))
                Text("冻结 ¥\(SpotReleaseLogic.formatYuan(model.detail?.resolvedDepositFen ?? SpotReleaseConfigDefaults.exclusiveDepositDefaultFen)) 预授权后即可参与抢购。未成交将在发售结束后解冻。")
                    .font(.vBody)
                    .foregroundStyle(Color.vTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                VPrimaryButton(title: "发起预授权", loading: model.busy, height: 48) {
                    Task {
                        model.needsExclusiveDeposit = false
                        await model.startExclusiveDeposit()
                    }
                }
                .padding(.horizontal, VSpace.l)
                Spacer()
            }
            .padding(.top, VSpace.xl)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { model.needsExclusiveDeposit = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - SKU chips

private struct FlowSKUChips: View {
    let skus: [SpotReleaseSKU]
    let selectedId: Int64?
    let onSelect: (Int64) -> Void

    var body: some View {
        FlexibleWrap(spacing: 8) {
            ForEach(skus) { sku in
                let selected = sku.id == selectedId
                Button {
                    onSelect(sku.id)
                } label: {
                    Text(sku.displayName)
                        .font(.vCaptionMedium)
                        .foregroundStyle(selected ? Color.white : Color.vText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selected ? Color.vPrimary : Color.vFill,
                            in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(sku.resolvedRemaining <= 0)
                .opacity(sku.resolvedRemaining <= 0 ? 0.4 : 1)
            }
        }
    }
}

/// Simple wrapping HStack for SKU chips (avoids extra layout deps).
private struct FlexibleWrap<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Fallback: horizontal scroll when many SKUs — keeps layout simple & stable.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) { content() }
        }
    }
}
