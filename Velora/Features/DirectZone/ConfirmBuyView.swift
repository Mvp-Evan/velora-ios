import SwiftUI

/// 立即购买确认页：地址 / 商品 / 数量 / 费用 / 规则 → 提交订单（DES-v1.3-04-01 §5.5 / §9）。
struct ConfirmBuyView: View {
    let listingId: Int64
    var source: DirectOrderSource = .detail
    var expectedPriceFen: Int64? = nil

    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ConfirmBuyModel
    @State private var showAddressPicker = false
    @State private var showCashier = false
    @State private var paymentResult: PaymentResult?

    init(listingId: Int64, source: DirectOrderSource = .detail, expectedPriceFen: Int64? = nil) {
        self.listingId = listingId
        self.source = source
        self.expectedPriceFen = expectedPriceFen
        _model = StateObject(
            wrappedValue: ConfirmBuyModel(
                listingId: listingId,
                source: source,
                expectedPriceFen: expectedPriceFen
            )
        )
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let msg) where model.preview == nil && model.address == nil:
                VErrorView(message: msg) { Task { await model.bootstrap() } }
            default:
                content
            }
        }
        .background(Color.vBackground)
        .navigationTitle(DirectZoneCopy.buyNow)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .task { await model.bootstrap() }
        .onChange(of: model.needsLogin) { _, need in
            if need {
                router.showLogin = true
                model.needsLogin = false
            }
        }
        .sheet(isPresented: $model.needsRealName) {
            NavigationStack { RealNameView() }
        }
        .sheet(isPresented: $showAddressPicker) {
            AddressListView(selecting: true) { addr in
                Task { await model.setAddress(addr) }
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
            } else if id != nil {
                // Order fetch lagged — open order detail as fallback.
                dismiss()
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: VSpace.l) {
                    addressCard
                    if let preview = model.preview {
                        goodsCard(preview)
                        feeCard(preview)
                        rulesCard(preview)
                    } else if model.address != nil {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else {
                        Text("请先填写收货地址以查看费用")
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(VSpace.l)
                .padding(.bottom, 100)
            }
            .refreshable { await model.refreshPreview() }

            bottomBar
        }
    }

    private var addressCard: some View {
        Button { showAddressPicker = true } label: {
            VCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Color.vGreen)
                    if let a = model.address {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(a.name).font(.vBodyMedium)
                                Text(a.phone).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                            }
                            Text(a.oneLine)
                                .font(.vCaption)
                                .foregroundStyle(Color.vTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("添加收货地址")
                            .font(.vBodyMedium)
                            .foregroundStyle(Color.vPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func goodsCard(_ p: FixedOrderPreview) -> some View {
        VCard {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(p.cover ?? "")
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.title ?? "直购商品")
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(2)
                    if let condition = p.condition, !condition.isEmpty {
                        VTagChip(text: condition)
                    }
                    if let name = p.sellerName, !name.isEmpty {
                        Text(name).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                    }
                    VPriceText(amount: p.unitPriceFen, size: 18)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func feeCard(_ p: FixedOrderPreview) -> some View {
        VCard {
            VStack(spacing: 10) {
                feeRow("商品价", model.goodsSubtotal)
                feeRow("运费", p.shippingFeeFen, freeHint: p.shippingFeeFen == 0)
                Divider()
                HStack {
                    Text("合计").font(.vHeadline)
                    Spacer()
                    VPriceText(amount: p.amountFen, size: 22)
                }
            }
        }
    }

    private func feeRow(_ title: String, _ amount: Int64, freeHint: Bool = false) -> some View {
        HStack {
            Text(title).font(.vCaption).foregroundStyle(Color.vTextSecondary)
            Spacer()
            if freeHint {
                Text("包邮").font(.vCaption).foregroundStyle(Color.vGreen)
            } else {
                Text(amount.display).font(.vCaptionMedium).foregroundStyle(Color.vText)
            }
        }
    }

    private func rulesCard(_ p: FixedOrderPreview) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("购买须知").font(.vHeadline)
                ruleLine("timer", "付款时限 \(p.lockMinutes) 分钟")
                ruleLine("shippingbox", "发货时限 \(p.shipHours) 小时")
                ruleLine("checkmark.shield", "售后规则以商品页与订单快照为准")
            }
        }
    }

    private func ruleLine(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.vTextTertiary)
                .frame(width: 16)
            Text(text)
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let p = model.preview {
                HStack {
                    Text("应付").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    VPriceText(amount: p.amountFen, size: 20)
                    Spacer()
                }
            }
            VPrimaryButton(
                title: DirectZoneCopy.submitOrder,
                loading: model.submitting,
                disabled: !model.canSubmit
            ) {
                Task {
                    if await model.submit() != nil, model.createdOrder != nil {
                        showCashier = true
                    }
                }
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
}
