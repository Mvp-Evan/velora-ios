import SwiftUI

/// 违约页：买家看禁竞拍/信用；卖家看保证金赔付预估（不向买家展示分账）（DES-v1.3-03-05 §9 AUC-10）
struct AuctionDefaultView: View {
    let orderId: Int64
    var presentedAsSheet = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model: AuctionDefaultModel

    init(orderId: Int64, presentedAsSheet: Bool = false) {
        self.orderId = orderId
        self.presentedAsSheet = presentedAsSheet
        _model = StateObject(wrappedValue: AuctionDefaultModel(orderId: orderId))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading: VLoadingView()
            case .failed(let m): VErrorView(message: m) { Task { await model.load() } }
            case .loaded:
                if let o = model.order { content(o) }
            }
        }
        .background(Color.vBackground)
        .navigationTitle("违约关单")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .task { await model.load() }
        .onAppear { if !presentedAsSheet { router.hideTabBar = true } }
        .onDisappear { if !presentedAsSheet { router.hideTabBar = false } }
    }

    @ObservedObject private var ticker = Ticker.shared

    private func content(_ o: Order) -> some View {
        ScrollView {
            VStack(spacing: VSpace.l) {
                hero(o)
                lotCard(o)
                if o.isSeller {
                    sellerCard
                } else {
                    buyerCard
                }
            }
            .padding(VSpace.l)
        }
        .refreshable { await model.load() }
    }

    private func hero(_ o: Order) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x8E939E), Color(hex: 0x5C6370)], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22, weight: .semibold))
                    Text(o.isSeller ? AuctionSettlementCopy.defaultSellerTitle : AuctionSettlementCopy.defaultBuyerTitle)
                        .font(.vTitle(22))
                    Spacer()
                }
                .foregroundStyle(.white)
                Text(o.isSeller ? AuctionSettlementCopy.defaultSellerDepositHint : AuctionSettlementCopy.defaultBuyerHint)
                    .font(.vCaption)
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(VSpace.xl)
        }
        .frame(minHeight: 130)
    }

    private func lotCard(_ o: Order) -> some View {
        VCard {
            HStack(spacing: 12) {
                RemoteImage(o.lot?.cover ?? "")
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(o.lot?.title ?? "拍品").font(.vBodyMedium).lineLimit(2)
                    HStack {
                        Text("原成交价").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        Spacer()
                        // Locked hammer still shown; seller forfeit split never shown to buyer.
                        VPriceText(amount: o.hammerPrice, size: 16, color: .vText)
                    }
                    Text("订单 \(o.orderNo)").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private var buyerCard: some View {
        let summary = model.buyerSummary
        return VCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("处罚说明").font(.vHeadline)
                HStack(spacing: 10) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Color.vPrimary)
                    Text(summary.creditLine).font(.vBodyMedium)
                    Spacer()
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.raised.slash.fill").foregroundStyle(Color.vGold)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.banLine(dateText: { $0.shortText }))
                            .font(.vBodyMedium)
                        if !summary.isPermanentBan, let until = summary.banUntil {
                            Text("剩余 \(until.countdownText(to: ticker.now))")
                                .font(.vMono(14, weight: .semibold))
                                .foregroundStyle(Color.vTextSecondary)
                                .contentTransition(.numericText())
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text("不展示卖家分得金额；如有疑问请联系客服。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
            }
        }
    }

    private var sellerCard: some View {
        let summary = model.sellerSummary
        return VCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("保证金赔付").font(.vHeadline)
                VKeyValue(key: "状态", value: summary.payoutStatusLabel, valueColor: .vPrimary, bold: true)
                VKeyValue(key: "预估到账", value: Money(summary.estimatedSellerShareFen).display)
                Text(AuctionSettlementCopy.defaultSellerDepositHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
                if summary.canInviteSecondChance && summary.secondChanceAvailable {
                    // Phase 3 entry — visible only when server flags availability.
                    VPrimaryButton(title: AuctionSettlementCopy.secondChanceAction, style: .soft, disabled: true) {}
                    Text("次高价邀约即将开放")
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }
}

@MainActor
final class AuctionDefaultModel: ObservableObject {
    let orderId: Int64
    @Published var order: Order?
    @Published var state: LoadState = .idle
    @Published var buyerSummary = AuctionDefaultBuyerSummary(banUntil: nil, isPermanentBan: false)
    @Published var sellerSummary = AuctionDefaultSellerSummary(depositFen: 0)

    init(orderId: Int64) { self.orderId = orderId }

    func load() async {
        if order == nil { state = .loading }
        do {
            let d = try await API.order(orderId)
            order = d.order
            rebuildSummaries(from: d.order)
            state = .loaded
        } catch {
            if order == nil { state = .failed((error as? APIError)?.message ?? "加载失败") }
        }
    }

    private func rebuildSummaries(from o: Order) {
        let flags = SessionStore.shared.accessFlags
        buyerSummary = AuctionDefaultBuyerSummary(
            banUntil: flags.banBidEndsAt,
            isPermanentBan: flags.isBanBid && flags.banBidEndsAt == nil,
            orderId: o.id,
            lotTitle: o.lot?.title
        )
        // Deposit amount not always on order; fall back to depositApplied (was frozen stake).
        let deposit = max(o.depositApplied, 0)
        sellerSummary = AuctionDefaultSellerSummary(
            depositFen: deposit,
            payoutStatus: "processing",
            canInviteSecondChance: false,
            secondChanceAvailable: false
        )
    }
}
