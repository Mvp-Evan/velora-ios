import SwiftUI

/// Natural feed card for purchase-home channels (DES-v1.3-02).
struct HomeFeedCardView: View {
    let card: HomeFeedCard
    var imageHeight: CGFloat = 200
    @EnvironmentObject private var session: SessionStore
    @ObservedObject private var ticker = Ticker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RemoteImage(card.cover).frame(height: imageHeight)
                HStack(spacing: 6) {
                    if card.showsEndedBadge {
                        Text(LotCardHeatCopy.endedBadge)
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.vCarbon.opacity(0.75), in: Capsule())
                    } else if let badge = card.sellerBadge {
                        SellerBadgeChip(badge: badge)
                    }
                    Spacer(minLength: 0)
                    if card.delayed {
                        Text(LotCardHeatCopy.delayedBadge)
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.vGold.opacity(0.95), in: Capsule())
                            .accessibilityLabel(LotCardHeatCopy.delayedBadge)
                    } else if let leak = card.leakBadge, !leak.isEmpty {
                        Text(leak)
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.vPrimary, in: Capsule())
                    }
                }
                .padding(8)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: VRadius.l, topTrailingRadius: VRadius.l, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    if let condition = card.condition, !condition.isEmpty {
                        VTagChip(text: condition)
                    }
                    tradeTypeChip
                }

                HStack(alignment: .firstTextBaseline) {
                    VPriceText(amount: card.displayPrice, size: 17)
                    Spacer()
                    trailingMeta
                }

                if card.tradeType == "auction", let endAt = card.endAt {
                    countdownRow(endAt: endAt)
                } else if card.tradeType == "fixed" {
                    fixedMeta
                } else if card.tradeType == "release" {
                    releaseMeta
                }
            }
            .padding(10)
        }
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    @ViewBuilder private var tradeTypeChip: some View {
        switch card.tradeType {
        case "auction": VTagChip(text: "拍卖", tint: .vPrimary, background: .vPrimarySoft)
        case "fixed": VTagChip(text: "直购", tint: .vBlue, background: Color.vBlue.opacity(0.12))
        case "release": VTagChip(text: "发售", tint: .vGold, background: Color.vGold.opacity(0.15))
        default: EmptyView()
        }
    }

    @ViewBuilder private var trailingMeta: some View {
        if card.tradeType == "auction" {
            Text((card.bidCount ?? 0) > 0 ? "\(card.bidCount!)次出价" : "起拍")
                .font(.vMicro).foregroundStyle(Color.vTextTertiary)
        } else if card.freeShipping == true {
            Text("包邮").font(.vMicro).foregroundStyle(Color.vGreen)
        }
    }

    private func countdownRow(endAt: Date) -> some View {
        let serverNow = Date(timeIntervalSince1970: Double(session.serverClock.serverNowMs()) / 1000)
        let remain = endAt.timeIntervalSince(serverNow)
        let urgent = remain > 0 && remain < 300
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "timer").font(.system(size: 10, weight: .semibold))
                Text(endAt.countdownText(to: serverNow))
                    .font(.vMono(11))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(urgent ? Color.vPrimary : Color.vTextSecondary)
            Text(card.heatLine)
                .font(.vMicro)
                .foregroundStyle(Color.vTextTertiary)
                .lineLimit(2)
                .accessibilityHidden(true)
        }
    }

    private var fixedMeta: some View {
        HStack(spacing: 8) {
            if card.negotiable == true {
                Text("可议价").font(.vMicro).foregroundStyle(Color.vTextSecondary)
            }
            Spacer()
        }
    }

    private var releaseMeta: some View {
        HStack {
            if let mode = card.releaseMode, !mode.isEmpty {
                Text(mode).font(.vMicro).foregroundStyle(Color.vTextSecondary)
            }
            Spacer()
            if let status = card.releaseStatus, !status.isEmpty {
                Text(status).font(.vMicro).foregroundStyle(Color.vGold)
            }
        }
    }

    static func estimatedHeight(for card: HomeFeedCard, imageHeight: CGFloat) -> CGFloat {
        imageHeight + 10 + (card.title.count > 14 ? 40 : 20) + 6 + 18 + 6 + 22 + 6 + 16 + 10
    }

    static func imageHeight(for card: HomeFeedCard) -> CGFloat {
        let base: [CGFloat] = [170, 200, 230, 185, 215]
        return base[Int(card.listingId % Int64(base.count))]
    }
}

struct SellerBadgeChip: View {
    let badge: SellerBadge
    var body: some View {
        Text(badge.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(background, in: Capsule())
            .accessibilityLabel(badge.label)
    }

    private var foreground: Color {
        switch badge {
        case .personal: return .vTextSecondary
        case .proxyGold: return Color(hex: 0x5C3B00)
        case .proxyProbation: return Color.vTextSecondary
        case .brandOfficial: return .white
        }
    }

    private var background: Color {
        switch badge {
        case .personal: return .vFillStrong
        case .proxyGold: return Color.vGold
        case .proxyProbation: return Color.vFillStrong
        case .brandOfficial: return .vBlue
        }
    }
}

/// Promo / ad card with mandatory label and 8pt stroke isolation (DES §5.3).
struct HomePromoCardView: View {
    let slot: HomeSlotItem
    var imageHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RemoteImage(slot.cover ?? "").frame(height: imageHeight)
                SlotLabelBadge(label: slot.label).padding(8)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: VRadius.l, topTrailingRadius: VRadius.l, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(slot.title ?? "精选推荐")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                Text(slot.label.displayText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.vTextTertiary)
                    .accessibilityLabel(slot.label.displayText)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vPrimarySoft.opacity(0.45))
        }
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VRadius.l, style: .continuous)
                .stroke(Color.vPrimary.opacity(0.35), lineWidth: 8)
        )
    }
}

struct SlotLabelBadge: View {
    let label: HomeSlotLabel
    var body: some View {
        Text(label.displayText)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(label == .ad ? Color.vCarbon.opacity(0.75) : Color.vPrimary.opacity(0.85), in: Capsule())
            .accessibilityLabel(label.displayText)
    }
}

struct HomeBannerCarousel: View {
    let banners: [HomeSlotItem]
    var onTap: (HomeSlotItem) -> Void
    var onExpose: (HomeSlotItem) -> Void
    @State private var index = 0

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(banners.prefix(5).enumerated()), id: \.element.id) { i, slot in
                ZStack(alignment: .topLeading) {
                    RemoteImage(slot.cover ?? "")
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .clipped()
                    SlotLabelBadge(label: slot.label).padding(10)
                    if let title = slot.title {
                        VStack {
                            Spacer()
                            Text(title)
                                .font(.vBodyMedium).foregroundStyle(.white)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(VGradient.imageScrim)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous))
                .padding(.horizontal, VSpace.l)
                .tag(i)
                .contentShape(Rectangle())
                .onTapGesture { onTap(slot) }
                .onAppear { onExpose(slot) }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: banners.count > 1 ? .automatic : .never))
        .frame(height: 140)
    }
}

struct HomeSessionStrip: View {
    let sessions: [HomeSlotItem]
    var onTap: (HomeSlotItem) -> Void
    var onExpose: (HomeSlotItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            VSectionHeader(title: "专场入口").padding(.horizontal, VSpace.l)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: VSpace.m) {
                    ForEach(sessions) { slot in
                        Button { onTap(slot) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topLeading) {
                                    RemoteImage(slot.cover ?? "").frame(width: 140, height: 88)
                                    SlotLabelBadge(label: slot.label).padding(6)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                                Text(slot.title ?? "专场")
                                    .font(.vCaptionMedium).foregroundStyle(Color.vText)
                                    .lineLimit(1)
                                    .frame(width: 140, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .onAppear { onExpose(slot) }
                    }
                }
                .padding(.horizontal, VSpace.l)
            }
        }
    }
}
