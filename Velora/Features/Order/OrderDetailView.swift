import SwiftUI

/// 订单详情：待付款时即结算页（地址 + 费用明细 + 收银台）；其余状态显示时间线
struct OrderDetailView: View {
    let orderId: Int64
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model: OrderModel
    @State private var showAddressPicker = false
    @State private var showCashier = false
    @State private var showShip = false
    @State private var result: PaymentResult?
    @State private var chatConv: Conversation?

    init(orderId: Int64) {
        self.orderId = orderId
        _model = StateObject(wrappedValue: OrderModel(orderId: orderId))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.vBackground.ignoresSafeArea()
            switch model.state {
            case .idle, .loading: VLoadingView()
            case .failed(let m): VErrorView(message: m) { Task { await model.load() } }
            case .loaded:
                if let o = model.order {
                    ScrollView {
                        VStack(spacing: VSpace.m) {
                            statusHeader(o)
                            if o.status == .pendingPayment && !o.isSeller { addressCard(o) } else if o.hasAddress { addressCard(o) }
                            lotCard(o)
                            feeCard(o)
                            if o.status != .pendingPayment { timelineCard(o) }
                            infoCard(o)
                        }
                        .padding(VSpace.l)
                        .padding(.bottom, 100)
                    }
                    .refreshable { await model.load() }
                    bottomBar(o)
                }
            }
        }
        .navigationTitle(model.order?.isSeller == true ? "卖出订单" : "订单详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "chevron.left") } }
        }
        .task { await model.load() }
        .sheet(isPresented: $showAddressPicker) {
            AddressListView(selecting: true) { addr in
                Task { await model.setAddress(addr) }
            }
        }
        .sheet(isPresented: $showCashier) {
            if let o = model.order {
                CashierSheet(order: o) { r in
                    showCashier = false
                    result = r
                    Task { await model.load(); await session.refreshMe() }
                }
                .presentationDetents([.height(460)]).presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showShip) {
            if let o = model.order { ShipSheet(order: o) { Task { await model.load() } }.presentationDetents([.height(360)]) }
        }
        .sheet(item: $result) { r in PaymentResultView(result: r, order: model.order) { result = nil } }
        .sheet(item: $chatConv) { c in NavigationStack { ChatView(conversation: c, presentedAsSheet: true) } }
    }

    // MARK: Sections

    private func statusHeader(_ o: Order) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous).fill(headerGradient(o))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(statusTitle(o)).font(.vTitle(22)).foregroundStyle(.white)
                    ForEach(statusLines(o), id: \.self) { line in
                        Text(line).font(.vCaption).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                    }
                    if o.status == .pendingPayment && !o.isSeller {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                            Text("剩余 ").font(.vCaption) + Text(payCountdown(o)).font(.vMono(13))
                        }
                        .foregroundStyle(.white).padding(.top, 4)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: statusIcon(o)).font(.system(size: 44, weight: .light)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(VSpace.xl)
        }
        .frame(minHeight: 120)
    }

    @ObservedObject private var ticker = Ticker.shared
    private func payCountdown(_ o: Order) -> String { o.payDeadline.countdownText(to: ticker.now) }

    private func addressCard(_ o: Order) -> some View {
        Button { if o.status == .pendingPayment && !o.isSeller { showAddressPicker = true } } label: {
            VCard {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill").foregroundStyle(Color.vPrimary).frame(width: 30, height: 30).background(Color.vPrimarySoft, in: Circle())
                    if o.hasAddress, let a = o.address {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(a["name"] ?? "").font(.vHeadline)
                                Text(a["phone"] ?? "").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                            }
                            Text(o.addressLine).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        }
                    } else {
                        Text("请选择收货地址").font(.vBodyMedium).foregroundStyle(Color.vPrimary)
                    }
                    Spacer()
                    if o.status == .pendingPayment && !o.isSeller { Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary) }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!(o.status == .pendingPayment && !o.isSeller))
    }

    private func lotCard(_ o: Order) -> some View {
        VCard {
            HStack(spacing: 12) {
                RemoteImage(o.lot?.cover ?? "").frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(o.lot?.title ?? "拍品").font(.vBodyMedium).lineLimit(2)
                    HStack(spacing: 4) {
                        if let s = o.lot?.scale, !s.isEmpty { VTagChip(text: s) }
                        if let b = o.lot?.brand, !b.isEmpty { VTagChip(text: b) }
                    }
                    HStack {
                        Text("成交价").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        Spacer()
                        VPriceText(amount: o.hammerPrice, size: 16, color: .vText)
                    }
                }
            }
        }
    }

    private func feeCard(_ o: Order) -> some View {
        VCard {
            VStack(spacing: 10) {
                if o.isSeller {
                    VKeyValue(key: "成交价", value: o.hammerPrice.display)
                    VKeyValue(key: "平台服务费", value: "-\(o.sellerCommission.display)", valueColor: .vTextSecondary)
                    Rectangle().fill(Color.vSeparator).frame(height: 0.5)
                    VKeyValue(key: o.status == .completed ? "已入账" : "预计入账", value: o.sellerNet.display, valueColor: .vPrimary, bold: true)
                    Text("买家确认收货后货款进入钱包可用余额；平台将为该笔收入生成税务记录。").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                } else {
                    VKeyValue(key: "成交价", value: o.hammerPrice.display)
                    VKeyValue(key: "买家佣金", value: o.buyerPremium == 0 ? "免佣" : o.buyerPremium.display, valueColor: o.buyerPremium == 0 ? .vGreen : .vText)
                    VKeyValue(key: "运费", value: "卖家承担", valueColor: .vGreen)
                    Rectangle().fill(Color.vSeparator).frame(height: 0.5)
                    VKeyValue(key: o.status == .pendingPayment ? "应付" : "实付", value: o.buyerTotal.display, valueColor: .vPrimary, bold: true)
                }
            }
        }
    }

    private func timelineCard(_ o: Order) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("订单进度").font(.vHeadline).padding(.bottom, VSpace.m)
                ForEach(Array(o.timeline.reversed().enumerated()), id: \.offset) { i, ev in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle().fill(i == 0 ? Color.vPrimary : Color.vFillStrong).frame(width: 10, height: 10)
                            if i < o.timeline.count - 1 { Rectangle().fill(Color.vSeparator).frame(width: 1.5).frame(minHeight: 28) }
                        }
                        .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ev.title).font(i == 0 ? .vBodyMedium : .vBody).foregroundStyle(i == 0 ? Color.vText : Color.vTextSecondary)
                            if let n = ev.note, !n.isEmpty { Text(n).font(.vCaption).foregroundStyle(Color.vTextSecondary) }
                            Text(ev.at.fullText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        }
                        .padding(.bottom, 14)
                    }
                }
                if let c = o.shippingCarrier, !c.isEmpty {
                    Rectangle().fill(Color.vSeparator).frame(height: 0.5).padding(.bottom, 10)
                    HStack {
                        Image(systemName: "shippingbox").foregroundStyle(Color.vBlue)
                        Text("\(c)  \(o.trackingNo ?? "")").font(.vMono(13))
                        Spacer()
                        Button("复制") { UIPasteboard.general.string = o.trackingNo; ToastCenter.shared.show("已复制单号", .success) }.font(.vCaption)
                    }
                }
            }
        }
    }

    private func infoCard(_ o: Order) -> some View {
        VCard {
            VStack(spacing: 8) {
                HStack {
                    Text("订单编号").font(.vCaption).foregroundStyle(Color.vTextSecondary); Spacer()
                    Text(o.orderNo).font(.vMono(12, weight: .regular))
                    Button { UIPasteboard.general.string = o.orderNo; ToastCenter.shared.show("已复制", .success) } label: { Image(systemName: "doc.on.doc").font(.vCaption) }
                }
                VKeyValue(key: "创建时间", value: o.createdAt.fullText).font(.vCaption)
                if let p = o.paidAt { VKeyValue(key: "付款时间", value: p.fullText).font(.vCaption) }
                if let s = o.shippedAt { VKeyValue(key: "发货时间", value: s.fullText).font(.vCaption) }
                if let c = o.completedAt { VKeyValue(key: "完成时间", value: c.fullText).font(.vCaption) }
                HStack {
                    Text(o.isSeller ? "买家" : "卖家").font(.vCaption).foregroundStyle(Color.vTextSecondary); Spacer()
                    VAvatar(url: (o.isSeller ? o.buyer : o.seller).avatar, size: 20)
                    Text((o.isSeller ? o.buyer : o.seller).nickname).font(.vCaption)
                }
                if !model.payments.isEmpty {
                    Rectangle().fill(Color.vSeparator).frame(height: 0.5)
                    ForEach(model.payments) { p in
                        HStack {
                            Text("支付流水").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                            Spacer()
                            Text("\(providerName(p.provider)) · \(paymentStatusLabel(p.status))").font(.vCaption)
                        }
                    }
                }
            }
        }
    }

    // MARK: Bottom bar

    @ViewBuilder private func bottomBar(_ o: Order) -> some View {
        HStack(spacing: 10) {
            Button { openChat(o) } label: {
                VStack(spacing: 3) { Image(systemName: "bubble.left").font(.system(size: 18)); Text(o.isSeller ? "联系买家" : "联系卖家").font(.vMicro) }
                    .foregroundStyle(Color.vTextSecondary).frame(width: 60)
            }
            if o.isSeller {
                switch o.status {
                case .paid: VPrimaryButton(title: "去发货", icon: "shippingbox.fill") { showShip = true }
                case .pendingPayment: VPrimaryButton(title: "等待买家付款", style: .dark, disabled: true) {}
                case .shipped: VPrimaryButton(title: "等待买家确认收货", style: .dark, disabled: true) {}
                default: VPrimaryButton(title: o.status.label, style: .dark, disabled: true) {}
                }
            } else {
                switch o.status {
                case .pendingPayment:
                    VStack(alignment: .leading, spacing: 0) {
                        Text("应付").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        VPriceText(amount: o.buyerTotal, size: 20)
                    }
                    .frame(width: 110, alignment: .leading)
                    VPrimaryButton(title: "立即付款", icon: "creditcard.fill", disabled: !o.hasAddress) {
                        if !o.hasAddress { ToastCenter.shared.show("请先选择收货地址"); showAddressPicker = true } else { showCashier = true }
                    }
                case .shipped: VPrimaryButton(title: "确认收货", icon: "checkmark.seal.fill", loading: model.working) { Task { await model.confirm() } }
                case .paid: VPrimaryButton(title: "等待卖家发货", style: .dark, disabled: true) {}
                default: VPrimaryButton(title: o.status.label, style: .dark, disabled: true) {}
                }
            }
        }
        .padding(.horizontal, VSpace.l).padding(.vertical, VSpace.m)
        .background(Color.vSurface.ignoresSafeArea(edges: .bottom).overlay(alignment: .top) { Rectangle().fill(Color.vSeparator).frame(height: 0.5) })
    }

    private func openChat(_ o: Order) {
        Task { do { chatConv = try await API.openConversation(lotId: o.lotId) } catch { ToastCenter.shared.error(error) } }
    }

    // MARK: Labels

    private func statusTitle(_ o: Order) -> String {
        if o.isSeller {
            switch o.status { case .pendingPayment: return "等待买家付款"; case .paid: return "买家已付款，请发货"; case .shipped: return "已发货"; case .completed: return "交易完成"; case .cancelled: return "订单已取消"; case .refunded: return "已退款" }
        }
        switch o.status { case .pendingPayment: return "等待付款"; case .paid: return "等待卖家发货"; case .shipped: return "卖家已发货"; case .completed: return "交易完成"; case .cancelled: return "订单已取消"; case .refunded: return "已退款" }
    }
    private func statusLines(_ o: Order) -> [String] {
        switch o.status {
        case .pendingPayment:
            return o.isSeller
                ? ["买家需在 \(o.payDeadline.shortText) 前完成付款", "逾期未付订单将自动取消"]
                : ["请在 \(o.payDeadline.shortText) 前完成付款", "逾期未付将自动取消订单"]
        case .paid: return [o.isSeller ? "请在 48 小时内发货并填写物流单号" : "卖家正在打包，请耐心等待"]
        case .shipped: return [o.isSeller ? "等待买家确认收货后货款入账" : "收到后请确认收货，货款将打给卖家"]
        case .completed: return [o.isSeller ? "货款已入账钱包" : "感谢您的信任，欢迎再次光临"]
        case .cancelled: return ["未在规定时间内完成付款"]
        case .refunded: return ["款项已原路退回"]
        }
    }
    private func statusIcon(_ o: Order) -> String {
        switch o.status { case .pendingPayment: return "creditcard"; case .paid: return "shippingbox"; case .shipped: return "truck.box"; case .completed: return "checkmark.seal"; case .cancelled: return "xmark.circle"; case .refunded: return "arrow.uturn.backward.circle" }
    }
    private func headerGradient(_ o: Order) -> LinearGradient {
        switch o.status {
        case .pendingPayment: return VGradient.brand
        case .completed: return LinearGradient(colors: [Color(hex: 0x27C07A), Color(hex: 0x1DB06A)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .cancelled, .refunded: return LinearGradient(colors: [Color(hex: 0x8E939E), Color(hex: 0x6B7280)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default: return LinearGradient(colors: [Color(hex: 0x4F8BFF), Color(hex: 0x3478F6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

func providerName(_ p: String) -> String {
    switch p { case "alipay": return "支付宝"; case "wechatpay": return "微信支付"; case "mock": return "模拟支付"; default: return p }
}
func paymentStatusLabel(_ s: PaymentStatus) -> String {
    switch s { case .created: return "待支付"; case .paying: return "支付中"; case .succeeded: return "已支付"; case .failed: return "失败"; case .closed: return "已关闭"; case .refunded: return "已退款" }
}

// MARK: - Model

@MainActor
final class OrderModel: ObservableObject {
    let orderId: Int64
    @Published var order: Order?
    @Published var payments: [Payment] = []
    @Published var state: LoadState = .idle
    @Published var working = false

    init(orderId: Int64) { self.orderId = orderId }

    func load() async {
        if order == nil { state = .loading }
        do {
            let d = try await API.order(orderId)
            order = d.order; payments = d.payments; state = .loaded
        } catch { if order == nil { state = .failed((error as? APIError)?.message ?? "加载失败") } }
    }

    func setAddress(_ a: Address) async {
        do { order = try await API.setOrderAddress(orderId, addressId: a.id); ToastCenter.shared.show("地址已更新", .success) }
        catch { ToastCenter.shared.error(error) }
    }

    func confirm() async {
        working = true; defer { working = false }
        do {
            order = try await API.confirm(orderId)
            ToastCenter.shared.show("已确认收货，交易完成", .success)
            await SessionStore.shared.refreshMe()
        } catch { ToastCenter.shared.error(error) }
    }
}

// MARK: - Ship sheet

struct ShipSheet: View {
    let order: Order
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var carrier = "顺丰速运"
    @State private var tracking = ""
    @State private var working = false
    private let carriers = ["顺丰速运", "京东物流", "中通快递", "圆通速递", "韵达快递", "申通快递", "EMS", "德邦快递", "其他"]

    var body: some View {
        VStack(alignment: .leading, spacing: VSpace.l) {
            Text("填写发货信息").font(.vTitle(20))
            Text("模型请使用足量缓冲材料包装，建议购买保价。").font(.vCaption).foregroundStyle(Color.vTextSecondary)
            VStack(spacing: 0) {
                VFormRow(title: "快递公司") {
                    Spacer()
                    Picker("", selection: $carrier) { ForEach(carriers, id: \.self) { Text($0).tag($0) } }.tint(Color.vText)
                }
                VDivider()
                VFormRow(title: "运单号") {
                    TextField("请输入运单号", text: $tracking).font(.vMono(15)).multilineTextAlignment(.trailing).textInputAutocapitalization(.characters)
                }
            }
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            Spacer()
            VPrimaryButton(title: "确认发货", loading: working, disabled: tracking.isBlank) {
                working = true
                Task {
                    defer { working = false }
                    do { _ = try await API.ship(order.id, carrier: carrier, trackingNo: tracking.trimmingCharacters(in: .whitespaces)); ToastCenter.shared.show("已发货", .success); done(); dismiss() }
                    catch { ToastCenter.shared.error(error) }
                }
            }
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
    }
}
