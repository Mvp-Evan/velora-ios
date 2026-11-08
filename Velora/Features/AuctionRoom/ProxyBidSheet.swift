import SwiftUI

/// Set / raise / cancel confidential max (DES-v1.3-03-04 §5.6 / §9).
struct ProxyBidSheet: View {
    let lot: Lot
    @ObservedObject var model: LotDetailModel
    @Environment(\.dismiss) private var dismiss
    @State private var yuan: String = ""
    @State private var showConfirm = false
    @State private var showCancelConfirm = false
    @FocusState private var focused: Bool

    private var amount: Money? { Double(yuan).map { Money(($0 * 100).rounded()) } }

    private var alignedPreview: Int64? {
        guard let amount else { return nil }
        return BidAmountGrid.alignDown(
            maxFen: amount,
            startPriceFen: lot.startPrice,
            currentPriceFen: lot.currentPrice,
            bidCount: lot.bidCount,
            sellerBidIncrementFen: lot.bidIncrement
        )
    }

    private var localCheck: ProxyBidLocalValidation? {
        guard let amount else { return nil }
        return ProxyBidLocalValidation.validate(
            typedMaxFen: amount,
            existing: model.proxyBid,
            startPriceFen: lot.startPrice,
            currentPriceFen: lot.currentPrice,
            bidCount: lot.bidCount,
            sellerBidIncrementFen: lot.bidIncrement
        )
    }

    private var canSubmit: Bool {
        if case .ok = localCheck { return true }
        return false
    }

    private var primaryTitle: String {
        if model.proxyBid?.isExceeded == true { return ProxyBidCopy.entryRaise }
        if model.proxyBid?.isActive == true { return "提高最高价" }
        return "确认设置代理"
    }

    var body: some View {
        VStack(spacing: VSpace.l) {
            header
            if model.proxyLoading, model.proxyBid == nil {
                skeleton
            } else {
                statusBanner
                amountField
                quickActions
                validationLine
                privacyNote
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
        .accessibilityElement(children: .contain)
        .onAppear { seedDefault(); focused = true }
        .confirmationDialog(ProxyBidCopy.confirmTitle, isPresented: $showConfirm, titleVisibility: .visible) {
            Button("确认设置") {
                Task {
                    guard let a = alignedPreview ?? amount else { return }
                    if await model.putProxyBid(a) { dismiss() }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(ProxyBidCopy.confirmBody)
        }
        .confirmationDialog(ProxyBidCopy.cancelTitle, isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("取消代理", role: .destructive) {
                Task { if await model.cancelProxyBid() { dismiss() } }
            }
            Button("再想想", role: .cancel) {}
        } message: {
            Text(model.isLeading ? ProxyBidCopy.cancelWhileLeading : ProxyBidCopy.cancelBody)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(ProxyBidCopy.sheetTitle).font(.vTitle(20))
                Text("当前 \(lot.displayPrice.display) · 最低 \(lot.minNextBid.display) · 每手 \(lot.bidIncrement.display)")
                    .font(.vCaption).foregroundStyle(Color.vTextSecondary)
            }
            Spacer()
            VCountdown(endAt: lot.endAt, status: lot.status)
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                .fill(Color.vFill).frame(height: 44)
            RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                .fill(Color.vFill).frame(height: 60)
            Text("加载代理出价…").font(.vCaption).foregroundStyle(Color.vTextTertiary)
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("加载中")
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let p = model.proxyBid, p.status.canRaise {
            HStack(spacing: 8) {
                Image(systemName: p.isExceeded ? "exclamationmark.triangle.fill" : "bolt.fill")
                Text(
                    p.isExceeded
                        ? ProxyBidCopy.exceededHint
                        : ProxyBidCopy.activeBanner(maxFen: p.displayMaxFen, leading: p.leading == true || model.isLeading)
                )
                Spacer()
            }
            .font(.vCaptionMedium)
            .foregroundStyle(p.isExceeded ? Color.vPrimary : Color.vGold)
            .padding(10)
            .background(
                (p.isExceeded ? Color.vPrimary : Color.vGold).opacity(0.1),
                in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
            )
        }
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProxyBidCopy.maxFieldLabel)
                .font(.vCaption).foregroundStyle(Color.vTextSecondary)
                .accessibilityLabel(ProxyBidCopy.privacyA11y)
            HStack(spacing: 10) {
                Button { step(-1) } label: { stepper("minus") }
                HStack(spacing: 4) {
                    Text("¥").font(.vPrice(24)).foregroundStyle(Color.vPrimary)
                    TextField("", text: $yuan)
                        .keyboardType(.decimalPad)
                        .font(.vPrice(30))
                        .foregroundStyle(Color.vPrimary)
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .accessibilityLabel("最高价金额，对他人不可见")
                        .onChange(of: focused) { _, isFocused in
                            if !isFocused { snapAmount() }
                        }
                }
                .frame(maxWidth: .infinity).frame(height: 60)
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                Button { step(1) } label: { stepper("plus") }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            suggestChip(
                title: "默认 +\(ProxyBidSuggest.defaultStepsAboveMinNext) 档",
                fen: ProxyBidSuggest.defaultMaxFen(
                    minNextBidFen: lot.minNextBid,
                    incrementFen: lot.bidIncrement
                )
            )
            suggestChip(
                title: ProxyBidCopy.plusTenSteps,
                fen: ProxyBidSuggest.plusTenStepsFen(
                    currentPriceFen: lot.currentPrice,
                    incrementFen: lot.bidIncrement
                )
            )
        }
    }

    private func suggestChip(title: String, fen: Money) -> some View {
        Button {
            yuan = fmt(fen)
            snapAmount()
            Haptics.light()
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.vMicro).opacity(0.85)
                Text(fen.display).font(.vMono(13, weight: .bold))
            }
            .foregroundStyle(Color.vText)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
        }
    }

    @ViewBuilder
    private var validationLine: some View {
        if let check = localCheck {
            switch check {
            case .ok(let aligned):
                Text(ProxyBidCopy.alignedHint(maxFen: aligned))
                    .font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .tooLow:
                Text(ProxyBidErrorCode.proxyMaxTooLow.fallbackMessage)
                    .font(.vCaption).foregroundStyle(Color.vPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .cannotDecrease(let old):
                Text("不可下调（当前最高 \(Money(old).display)），请先取消再设")
                    .font(.vCaption).foregroundStyle(Color.vPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("输入最高价后，系统按加价幅度向下对齐")
                .font(.vCaption).foregroundStyle(Color.vTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var privacyNote: some View {
        Text(ProxyBidCopy.confirmBody)
            .font(.vCaption).foregroundStyle(Color.vTextTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(ProxyBidCopy.privacyA11y)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            VPrimaryButton(
                title: primaryTitle,
                icon: "bolt.fill",
                loading: model.proxySaving,
                disabled: !canSubmit || model.proxySaving
            ) {
                snapAmount()
                guard canSubmit else { return }
                showConfirm = true
            }
            .accessibilityHint(ProxyBidCopy.privacyA11y)

            if model.proxyBid?.status.canCancel == true {
                Button {
                    showCancelConfirm = true
                } label: {
                    Text("取消代理出价")
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .disabled(model.proxySaving)
            }
        }
    }

    private func seedDefault() {
        if let p = model.proxyBid, p.status.canRaise {
            yuan = fmt(p.displayMaxFen)
        } else {
            let suggested = ProxyBidSuggest.defaultMaxFen(
                minNextBidFen: lot.minNextBid,
                incrementFen: lot.bidIncrement
            )
            yuan = fmt(suggested)
            snapAmount()
        }
    }

    private func snapAmount() {
        guard let cur = amount else { return }
        guard let aligned = BidAmountGrid.alignDown(
            maxFen: cur,
            startPriceFen: lot.startPrice,
            currentPriceFen: lot.currentPrice,
            bidCount: lot.bidCount,
            sellerBidIncrementFen: lot.bidIncrement
        ) else { return }
        if aligned != cur { yuan = fmt(aligned) }
    }

    private func stepper(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Color.vText)
            .frame(width: 48, height: 60).background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func step(_ dir: Int) {
        let base = alignedPreview ?? amount ?? lot.minNextBid
        let next = max(lot.minNextBid, base + Money(dir) * lot.bidIncrement)
        yuan = fmt(next)
        snapAmount()
        Haptics.light()
    }

    private func fmt(_ m: Money) -> String { m % 100 == 0 ? "\(m / 100)" : String(format: "%.2f", m.yuan) }
}
