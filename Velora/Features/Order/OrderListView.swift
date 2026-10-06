import SwiftUI

/// 订单列表：买到的 / 卖出的，按状态分段
struct OrderListView: View {
    let role: String // buyer | seller
    var initialStatus: String? = nil
    @State private var status: String = ""
    @State private var orders: [Order] = []
    @State private var state: LoadState = .idle
    @State private var page = 1
    @State private var hasMore = true
    @State private var shipOrder: Order?

    private var segments: [(String, String)] {
        role == "seller"
            ? [("", "全部"), ("pending_payment", "待付款"), ("paid", "待发货"), ("shipped", "已发货"), ("completed", "已完成")]
            : [("", "全部"), ("pending_payment", "待付款"), ("paid", "待发货"), ("shipped", "待收货"), ("completed", "已完成")]
    }

    var body: some View {
        VStack(spacing: 0) {
            VSegmentedTabs(items: segments, selection: $status).padding(.vertical, VSpace.s)
            ScrollView {
                switch state {
                case .idle, .loading: VLoadingView()
                case .failed(let m): VErrorView(message: m) { Task { await load() } }
                case .loaded:
                    if orders.isEmpty { VEmptyState(icon: "shippingbox", title: "暂无订单", message: role == "seller" ? "拍品成交后订单会出现在这里" : "拍中的宝贝会出现在这里") }
                    else {
                        LazyVStack(spacing: VSpace.m) {
                            ForEach(orders) { o in
                                OrderRow(order: o) {
                                    shipOrder = o
                                }
                                .onAppear { if o.id == orders.last?.id, hasMore { Task { await loadMore() } } }
                            }
                        }
                        .padding(VSpace.l)
                    }
                }
            }
            .refreshable { await load() }
        }
        .background(Color.vBackground)
        .navigationTitle(role == "seller" ? "我卖出的" : "我拍到的")
        .navigationBarTitleDisplayMode(.inline)
        .task { status = initialStatus ?? ""; await load() }
        .onChange(of: status) { _, _ in Task { await load() } }
        .sheet(item: $shipOrder) { o in
            ShipSheet(order: o) { Task { await load() } }
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
    }

    private func load() async {
        state = orders.isEmpty ? .loading : state
        page = 1
        do {
            let p = try await API.myOrders(role: role, status: status.isEmpty ? nil : status, page: 1)
            orders = p.items; hasMore = p.hasMore; state = .loaded
        } catch { state = .failed((error as? APIError)?.message ?? "加载失败") }
    }

    private func loadMore() async {
        page += 1
        if let p = try? await API.myOrders(role: role, status: status.isEmpty ? nil : status, page: page) {
            orders.append(contentsOf: p.items); hasMore = p.hasMore
        }
    }
}

struct OrderRow: View {
    let order: Order
    var onShip: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            NavigationLink { OrderDetailView(orderId: order.id) } label: {
                VStack(spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            VAvatar(url: (order.isSeller ? order.buyer : order.seller).avatar, size: 18)
                            Text((order.isSeller ? order.buyer : order.seller).nickname).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        }
                        Spacer()
                        Text(order.status.label).font(.vCaptionMedium).foregroundStyle(statusColor)
                    }
                    HStack(spacing: 12) {
                        RemoteImage(order.lot?.cover ?? "").frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(order.lot?.title ?? "拍品").font(.vBodyMedium).lineLimit(2)
                            HStack(spacing: 4) {
                                if let s = order.lot?.scale, !s.isEmpty { VTagChip(text: s) }
                                if let b = order.lot?.brand, !b.isEmpty { VTagChip(text: b) }
                            }
                            Text(order.createdAt.relativeText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(order.isSeller ? "到手" : "实付").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                            VPriceText(amount: order.isSeller ? order.sellerNet : order.buyerTotal, size: 16, color: .vText)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            if showsAction {
                HStack {
                    Spacer()
                    if order.isSeller && order.status == .paid {
                        Button(action: onShip) {
                            Text("去发货").font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 6).overlay(Capsule().stroke(Color.vPrimary, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink { OrderDetailView(orderId: order.id) } label: {
                            Text(actionHint).font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                                .padding(.horizontal, 12).padding(.vertical, 6).overlay(Capsule().stroke(Color.vPrimary, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private var showsAction: Bool {
        order.status == .pendingPayment || order.status == .shipped || (order.isSeller && order.status == .paid)
    }
    private var actionHint: String {
        if order.isSeller { return "查看" }
        switch order.status { case .pendingPayment: return "去付款"; case .shipped: return "确认收货"; default: return "查看" }
    }
    private var statusColor: Color {
        switch order.status { case .pendingPayment: return .vPrimary; case .paid, .shipped: return .vBlue; case .completed: return .vGreen; default: return .vTextTertiary }
    }
}
