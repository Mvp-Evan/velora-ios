import SwiftUI

/// 统一订单中心：买家 / 卖家 + Tab 全部/待付款/待发货/待收货/待评价/退款售后（DES-v1.3-07-01 / D27）
struct OrderListView: View {
    let role: String // buyer | seller
    var initialStatus: String? = nil
    @State private var tab: OrderCenterTab = .all
    @State private var orders: [Order] = []
    @State private var state: LoadState = .idle
    @State private var page = 1
    @State private var hasMore = true
    @State private var shipOrder: Order?
    @State private var fetchedAt = Date()
    @State private var listServerTime: Date?
    @ObservedObject private var ticker = Ticker.shared

    private var segments: [(String, String)] {
        OrderCenterTab.allCases.map { ($0.rawValue, $0.title) }
    }

    private var tabBinding: Binding<String> {
        Binding(
            get: { tab.rawValue },
            set: { tab = OrderCenterTab(rawValue: $0) ?? .all }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VSegmentedTabs(items: segments, selection: tabBinding).padding(.vertical, VSpace.s)
            ScrollView {
                switch state {
                case .idle, .loading: VLoadingView()
                case .failed(let m): VErrorView(message: m) { Task { await load() } }
                case .loaded:
                    if orders.isEmpty {
                        VEmptyState(
                            icon: "shippingbox",
                            title: OrderCenterCopy.emptyTitle,
                            message: role == "seller" ? OrderCenterCopy.emptyHintSeller : OrderCenterCopy.emptyHintBuyer
                        )
                    } else {
                        LazyVStack(spacing: VSpace.m) {
                            ForEach(orders) { o in
                                OrderRow(
                                    order: o,
                                    remainPay: remainPay(o),
                                    remainShip: remainShip(o),
                                    remainReviewDays: remainReviewDays(o)
                                ) {
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
        .navigationTitle(role == "seller" ? OrderCenterCopy.sellerTitle : OrderCenterCopy.centerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            tab = OrderCenterTab.from(initialStatus: initialStatus)
            await load()
        }
        .onChange(of: tab) { _, _ in Task { await load() } }
        .sheet(item: $shipOrder) { o in
            ShipSheet(order: o) { Task { await load() } }
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
    }

    private func remainPay(_ o: Order) -> Int {
        OrderLogic.payRemainSeconds(
            deadline: o.status == .pendingPayment ? o.payDeadline : nil,
            serverRemainSec: o.payRemainSec,
            serverTime: o.serverTime ?? listServerTime,
            fetchedAtLocal: fetchedAt,
            nowLocal: ticker.now
        )
    }

    private func remainShip(_ o: Order) -> Int {
        guard o.status == .paid else { return 0 }
        return OrderLogic.shipRemainSeconds(
            deadline: o.shipDeadline,
            serverRemainSec: o.shipRemainSec,
            serverTime: o.serverTime ?? listServerTime,
            fetchedAtLocal: fetchedAt,
            nowLocal: ticker.now
        )
    }

    private func remainReviewDays(_ o: Order) -> Int {
        guard o.isReviewPendingForMe else { return 0 }
        return ReviewCreditLogic.reviewRemainDays(
            deadline: o.reviewDeadline,
            serverRemainDays: o.reviewRemainDays,
            serverTime: o.serverTime ?? listServerTime,
            fetchedAtLocal: fetchedAt,
            nowLocal: ticker.now,
            completedAt: o.completedAt
        )
    }

    private func load() async {
        state = orders.isEmpty ? .loading : state
        page = 1
        do {
            let q = tab.listQuery
            let p = try await API.myOrders(
                role: role,
                status: q.status,
                tradeType: q.tradeType,
                afterSaleStatus: q.afterSaleStatus,
                tab: q.tab,
                page: 1
            )
            orders = p.items.map { stampedRole($0) }
            hasMore = p.hasMore
            fetchedAt = Date()
            listServerTime = p.items.compactMap(\.serverTime).first
            state = .loaded
        } catch {
            state = .failed((error as? APIError)?.message ?? "加载失败")
        }
    }

    private func loadMore() async {
        page += 1
        let q = tab.listQuery
        if let p = try? await API.myOrders(
            role: role,
            status: q.status,
            tradeType: q.tradeType,
            afterSaleStatus: q.afterSaleStatus,
            tab: q.tab,
            page: page
        ) {
            orders.append(contentsOf: p.items.map { stampedRole($0) })
            hasMore = p.hasMore
        }
    }

    /// List cards omit `role`; stamp from the screen context (buy vs sell).
    private func stampedRole(_ order: Order) -> Order {
        var o = order
        let sell = role == "seller" || role == "sell"
        o.role = sell ? "seller" : "buyer"
        return o
    }
}

struct OrderRow: View {
    let order: Order
    var remainPay: Int = 0
    var remainShip: Int = 0
    var remainReviewDays: Int = 0
    var onShip: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            if order.isReviewPendingForMe, remainReviewDays > 0 {
                PendingReviewBanner(remainDays: remainReviewDays)
            }
            NavigationLink { OrderDetailView(orderId: order.id) } label: {
                VStack(spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            VAvatar(url: (order.isSeller ? order.buyer : order.seller).avatar, size: 18)
                            Text((order.isSeller ? order.buyer : order.seller).nickname).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                            VTagChip(text: order.tradeType.displayLabel)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            if let badge = order.afterSaleBadge.label {
                                Text(badge)
                                    .font(.vMicro)
                                    .foregroundStyle(Color.vPrimary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.vPrimarySoft, in: Capsule())
                            }
                            Text(order.status.label).font(.vCaptionMedium).foregroundStyle(statusColor)
                        }
                    }
                    HStack(spacing: 12) {
                        RemoteImage(order.displayCover).frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(order.displayTitle).font(.vBodyMedium).lineLimit(2)
                            HStack(spacing: 4) {
                                if let s = order.lot?.scale ?? order.itemSnapshot?.scale, !s.isEmpty { VTagChip(text: s) }
                                if let b = order.lot?.brand ?? order.itemSnapshot?.brand, !b.isEmpty { VTagChip(text: b) }
                            }
                            if order.status == .pendingPayment, remainPay > 0 {
                                Text("付款剩余 \(OrderLogic.formatCountdown(remainPay))")
                                    .font(.vMono(11))
                                    .foregroundStyle(OrderLogic.isCountdownUrgent(remainPay) ? Color.vPrimary : Color.vTextTertiary)
                            } else if order.status == .paid, remainShip > 0 {
                                Text("发货剩余 \(OrderLogic.formatCountdown(remainShip))")
                                    .font(.vMono(11))
                                    .foregroundStyle(OrderLogic.isCountdownUrgent(remainShip) ? Color.vPrimary : Color.vTextTertiary)
                            } else if order.isReviewPendingForMe, remainReviewDays > 0 {
                                Text(ReviewCreditLogic.pendingBannerText(remainDays: remainReviewDays))
                                    .font(.vMono(11))
                                    .foregroundStyle(Color.vGold)
                            } else {
                                Text(order.createdAt.relativeText).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                            }
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
        if order.isSeller {
            return order.status == .paid || order.isReviewPendingForMe
        }
        return order.status == .pendingPayment
            || order.status == .shipped
            || order.isReviewPendingForMe
    }
    private var actionHint: String {
        if order.isReviewPendingForMe { return ReviewCreditCopy.submitTitle }
        if order.isSeller {
            return order.status == .paid ? "去发货" : "查看"
        }
        switch order.status { case .pendingPayment: return "去付款"; case .shipped: return "确认收货"; default: return "查看" }
    }
    private var statusColor: Color {
        switch order.status {
        case .pendingPayment: return .vPrimary
        case .paid, .shipped: return .vBlue
        case .completed, .settled: return .vGreen
        default: return .vTextTertiary
        }
    }
}
