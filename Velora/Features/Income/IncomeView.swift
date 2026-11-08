import SwiftUI

/// 卖家收入与利润（DES-v1.3-08-04 FIN-02 / D32）。
struct IncomeView: View {
    @State private var page: IncomePage?
    @State private var state: LoadState = .idle
    @State private var period: String = IncomeProfitLogic.currentMonthPeriod()
    @State private var forbiddenBuyer = false
    @State private var exporting = false

    var body: some View {
        Group {
            if forbiddenBuyer {
                VEmptyState(
                    icon: "person.crop.circle.badge.exclamationmark",
                    title: IncomeCopy.buyerForbidden,
                    message: IncomeCopy.forbidden
                )
            } else {
                content
            }
        }
        .background(Color.vBackground)
        .navigationTitle(IncomeCopy.homeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    TaxCenterView()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel(IncomeCopy.taxCenterCTA)
                Button {
                    Task { await exportIncome() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(exporting || page?.isEmpty == true)
                .accessibilityLabel(IncomeCopy.exportCTA)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: VSpace.l) {
                periodBar
                formulaBanner
                if let page {
                    if page.isProxyAgent {
                        privacyBanner
                    }
                    summaryCards(page.summary)
                    if let hint = page.summary.missingCostHint {
                        Text(hint)
                            .font(.vCaption)
                            .foregroundStyle(Color.vGold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, VSpace.l)
                    }
                    linesSection(page)
                } else if state == .loading || state == .idle {
                    VSkeleton(radius: VRadius.xl).frame(height: 140).padding(.horizontal, VSpace.l)
                    VLoadingView()
                } else if case .failed(let m) = state {
                    VErrorView(message: m) { Task { await load() } }
                }
            }
            .padding(.vertical, VSpace.m)
        }
    }

    private var periodBar: some View {
        HStack {
            Text(IncomeCopy.periodLabel)
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
            Spacer()
            TextField("yyyy-MM", text: $period)
                .font(.vMono(15))
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { Task { await load() } }
            Button("查询") { Task { await load() } }
                .font(.vCaptionMedium)
        }
        .padding(.horizontal, VSpace.l)
    }

    private var formulaBanner: some View {
        Text(IncomeCopy.formulaHint)
            .font(.vCaption)
            .foregroundStyle(Color.vTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VSpace.l)
            .accessibilityLabel(IncomeCopy.formulaHint)
    }

    private var privacyBanner: some View {
        Text(IncomeCopy.proxyPrivacy)
            .font(.vMicro)
            .foregroundStyle(Color.vTextTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VSpace.l)
    }

    private func summaryCards(_ s: IncomeSummary) -> some View {
        VStack(spacing: VSpace.m) {
            HStack(spacing: VSpace.m) {
                metricCard(
                    title: IncomeCopy.sellerNetTitle,
                    amount: s.sellerNet,
                    accent: true
                )
                metricCard(
                    title: IncomeCopy.profitTitle,
                    amount: s.profit,
                    allowNull: true
                )
            }
            HStack(spacing: VSpace.m) {
                metricCard(
                    title: IncomeCopy.gmvTitle,
                    amount: s.gmv,
                    subtitle: IncomeCopy.gmvNotRevenue
                )
                metricCard(
                    title: IncomeCopy.serviceFeeTitle,
                    amount: s.serviceFee
                )
            }
        }
        .padding(.horizontal, VSpace.l)
    }

    private func metricCard(
        title: String,
        amount: Int64?,
        accent: Bool = false,
        allowNull: Bool = false,
        subtitle: String? = nil
    ) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                if allowNull, amount == nil {
                    Text(IncomeConfigDefaults.missingProfitDisplay)
                        .font(.vTitle(22))
                        .foregroundStyle(Color.vTextTertiary)
                } else if let amount {
                    VPriceText(amount: amount, size: 22, color: accent ? .vPrimary : .vText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(IncomeConfigDefaults.missingProfitDisplay)
                        .font(.vTitle(22))
                        .foregroundStyle(Color.vTextTertiary)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func linesSection(_ page: IncomePage) -> some View {
        if page.items.isEmpty {
            VEmptyState(
                icon: "chart.line.uptrend.xyaxis",
                title: IncomeCopy.emptyOrders,
                message: IncomeCopy.emptyHint
            )
            .padding(.horizontal, VSpace.l)
        } else {
            VStack(alignment: .leading, spacing: VSpace.s) {
                Text(IncomeCopy.missingCostGuide)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                    .padding(.horizontal, VSpace.l)
                VCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(page.items) { line in
                            NavigationLink {
                                OrderCostEditView(line: line) {
                                    Task { await load() }
                                }
                            } label: {
                                lineRow(line)
                            }
                            .buttonStyle(.plain)
                            if line.id != page.items.last?.id {
                                VDivider(inset: 16)
                            }
                        }
                    }
                }
                .padding(.horizontal, VSpace.l)
            }
        }
    }

    private func lineRow(_ line: IncomeOrderLine) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.title?.nilIfEmpty ?? line.orderNo ?? "#\(line.orderId)")
                    .font(.vBodyMedium)
                    .foregroundStyle(Color.vText)
                    .lineLimit(1)
                Text("实收 \(line.sellerNet.display) · 服务费 \(line.platformFee.display)")
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                if !line.hasCost {
                    Text(IncomeCopy.costEntryTitle)
                        .font(.vMicro)
                        .foregroundStyle(Color.vPrimary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(line.profitDisplay)
                    .font(.vMono(15))
                    .foregroundStyle(line.hasCost ? Color.vText : Color.vTextTertiary)
                Text(IncomeCopy.profitTitle)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
            }
        }
        .padding(.horizontal, VSpace.l)
        .padding(.vertical, 12)
        .accessibilityLabel("利润 \(line.profitDisplay)")
    }

    private func load() async {
        forbiddenBuyer = false
        if page == nil { state = .loading }
        let p = period.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else {
            state = .failed("请输入账期")
            return
        }
        do {
            page = try await API.sellerIncome(period: p)
            state = .loaded
        } catch let e as APIError {
            let code = IncomeErrorCode.normalize(e.code)
            if code == .forbidden {
                forbiddenBuyer = true
                state = .loaded
            } else {
                state = .failed(IncomeProfitLogic.message(for: e.code, serverMessage: e.message))
            }
        } catch {
            state = .failed(IncomeCopy.loadFailed)
        }
    }

    private func exportIncome() async {
        exporting = true
        defer { exporting = false }
        do {
            _ = try await API.exportSellerIncome(period: period)
            ToastCenter.shared.show(IncomeCopy.exportQueued, .info)
        } catch let e as APIError {
            ToastCenter.shared.show(IncomeProfitLogic.message(for: e.code, serverMessage: e.message), .error)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}

// MARK: - Cost editor

struct OrderCostEditView: View {
    let line: IncomeOrderLine
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var costYuan = ""
    @State private var shippingYuan = ""
    @State private var working = false

    private var costFen: Money? { Self.parseYuan(costYuan) }
    private var shippingFen: Money? { Self.parseYuan(shippingYuan) }

    var body: some View {
        Form {
            Section {
                LabeledContent("成交价") { Text(line.amount.display) }
                LabeledContent(IncomeCopy.serviceFeeTitle) { Text(line.platformFee.display) }
                LabeledContent(IncomeCopy.sellerNetTitle) { Text(line.sellerNet.display) }
                LabeledContent(IncomeCopy.profitTitle) {
                    Text(previewProfit)
                        .foregroundStyle(Color.vTextSecondary)
                }
            } footer: {
                Text(IncomeCopy.snapshotHint + "\n" + IncomeCopy.formulaHint)
            }

            Section(IncomeCopy.costEntryTitle) {
                HStack {
                    Text(IncomeCopy.costPriceLabel)
                    Spacer()
                    TextField("0.00", text: $costYuan)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.vMono(16))
                }
                HStack {
                    Text(IncomeCopy.actualShippingLabel)
                    Spacer()
                    TextField("0.00", text: $shippingYuan)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.vMono(16))
                }
            }

            if line.isProxyHint {
                Section {
                    Text(IncomeCopy.proxyPrivacy)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
            }
        }
        .navigationTitle(IncomeCopy.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(working ? "保存中…" : "保存") { Task { await save() } }
                    .disabled(working || costFen == nil)
            }
        }
        .onAppear {
            if let c = line.costPrice { costYuan = String(format: "%.2f", Double(c) / 100) }
            if let s = line.actualShippingCost { shippingYuan = String(format: "%.2f", Double(s) / 100) }
            else { shippingYuan = "0.00" }
        }
    }

    private var previewProfit: String {
        guard let cost = costFen else { return IncomeConfigDefaults.missingProfitDisplay }
        let ship = shippingFen ?? 0
        let p = IncomeProfitLogic.profitFen(
            sellerNetFen: line.sellerNet,
            actualShippingCostFen: ship,
            costPriceFen: cost
        )
        return IncomeProfitLogic.profitDisplay(p)
    }

    private func save() async {
        guard let cost = costFen else { return }
        working = true
        defer { working = false }
        do {
            _ = try await API.updateOrderCost(
                orderId: line.orderId,
                costPrice: cost,
                actualShippingCost: shippingFen ?? 0
            )
            ToastCenter.shared.show(IncomeCopy.costSaved, .success)
            onSaved()
            dismiss()
        } catch let e as APIError {
            ToastCenter.shared.show(IncomeProfitLogic.message(for: e.code, serverMessage: e.message), .error)
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    private static func parseYuan(_ raw: String) -> Money? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let v = Double(s), v >= 0 else { return nil }
        return Money((v * 100).rounded())
    }
}

private extension IncomeOrderLine {
    var isProxyHint: Bool {
        let t = (tradeType ?? "").lowercased()
        return t.contains("proxy") || (feeRuleSnapshot?.sellerType?.lowercased().contains("proxy") == true)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
