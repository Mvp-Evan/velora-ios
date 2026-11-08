import SwiftUI

/// 我的补款：待付定金 / 待补款倒计时 / 已补款交期 / 逾期 / 退款（DES-v1.3-06-03 §5.10 / §9）。
struct MyBalanceOrdersView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = MyBalanceOrdersModel()
    @ObservedObject private var ticker = Ticker.shared

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let msg) where model.items.isEmpty:
                VErrorView(message: msg) { Task { await model.load() } }
            default:
                content
            }
        }
        .background(Color.vBackground)
        .navigationTitle(PresaleCopy.myBalanceTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !session.isLoggedIn {
                router.showLogin = true
                return
            }
            await model.load()
        }
        .refreshable { await model.load() }
        .onChange(of: ticker.now) { _, _ in
            _ = model.items.map { model.subtitle(for: $0) }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MyBalanceOrdersModel.Filter.allCases) { f in
                        let on = model.filter == f
                        Button {
                            model.filter = f
                        } label: {
                            Text(f.title)
                                .font(.vCaption)
                                .foregroundStyle(on ? Color.white : Color.vTextSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(on ? Color.vPrimary : Color.vFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, VSpace.l)
                .padding(.vertical, VSpace.m)
            }

            if model.items.isEmpty {
                VEmptyState(
                    icon: "yensign.circle",
                    title: PresaleCopy.emptyOrders,
                    message: PresaleCopy.emptyOrdersHint
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: VSpace.m) {
                        ForEach(model.items) { order in
                            NavigationLink {
                                PresaleOrderDetailView(presaleOrderId: order.id)
                            } label: {
                                row(order)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if order.id == model.items.last?.id {
                                    Task { await model.loadMore() }
                                }
                            }
                        }
                        if model.loadingMore {
                            ProgressView().padding(.vertical, 12)
                        }
                    }
                    .padding(VSpace.l)
                }
            }
        }
    }

    private func row(_ order: PresaleOrderSummary) -> some View {
        let cta = PresaleLogic.resolveOrderCTA(order: order, serverNow: model.serverNow)
        return VCard {
            HStack(alignment: .top, spacing: VSpace.m) {
                RemoteImage(order.cover ?? "")
                    .frame(width: 72, height: 72)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(order.displayTitle)
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(2)
                    Text(model.subtitle(for: order))
                        .font(.vCaption)
                        .foregroundStyle(cta == .payBalance ? Color.vPrimary : Color.vTextSecondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        VTagChip(
                            text: order.resolvedStatus.displayLabel,
                            tint: tagTint(cta),
                            background: tagTint(cta).opacity(0.12)
                        )
                        if let sku = order.skuLabel, !sku.isEmpty {
                            Text(sku)
                                .font(.vMicro)
                                .foregroundStyle(Color.vTextTertiary)
                        }
                        Spacer(minLength: 0)
                        if cta == .payBalance {
                            Text(PresaleCopy.payBalance)
                                .font(.vCaptionMedium)
                                .foregroundStyle(Color.vPrimary)
                        } else if cta == .payDeposit {
                            Text(PresaleCopy.payDeposit)
                                .font(.vCaptionMedium)
                                .foregroundStyle(Color.vPrimary)
                        }
                    }
                }
            }
        }
    }

    private func tagTint(_ cta: PresaleCTA) -> Color {
        switch cta {
        case .payBalance, .payDeposit: return .vPrimary
        case .delayChoice: return .vGold
        case .expired, .cancelled, .refunded: return .vTextSecondary
        case .balancePaid, .shipped: return .vGreen
        default: return .vBlue
        }
    }
}
