import SwiftUI

/// Search / sold listing card (DES-v1.3-02-02). Reuses home visual language without mutating HomeFeedCardView.
struct SearchListingCardView: View {
    let card: SearchListingCard
    var imageHeight: CGFloat = 200
    @EnvironmentObject private var session: SessionStore
    @ObservedObject private var ticker = Ticker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RemoteImage(card.cover).frame(height: imageHeight)
                HStack(spacing: 6) {
                    if card.isSoldCard {
                        Text("已成交")
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.vCarbon.opacity(0.75), in: Capsule())
                    } else if card.showsEndedBadge {
                        Text(LotCardHeatCopy.endedBadge)
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.vCarbon.opacity(0.75), in: Capsule())
                    } else if let badge = card.sellerBadge {
                        SellerBadgeChip(badge: badge)
                    }
                    Spacer(minLength: 0)
                    if card.delayed, !card.isSoldCard {
                        Text(LotCardHeatCopy.delayedBadge)
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.vGold.opacity(0.95), in: Capsule())
                            .accessibilityLabel(LotCardHeatCopy.delayedBadge)
                    } else if let leak = card.leakBadge, !leak.isEmpty, !card.isSoldCard {
                        Text(leak)
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.vPrimary, in: Capsule())
                            .accessibilityLabel(LeakBadgePolicy.voiceOverLabel)
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
                    ForEach(card.tags.prefix(2), id: \.self) { VTagChip(text: $0) }
                    tradeTypeChip
                }

                HStack(alignment: .firstTextBaseline) {
                    if card.isSoldCard {
                        VPriceText(amount: card.displayPrice, size: 17, prefix: card.soldPriceLabel)
                    } else {
                        VPriceText(amount: card.displayPrice, size: 17)
                    }
                    Spacer()
                    trailingMeta
                }

                if card.isSoldCard {
                    soldMeta
                } else if card.tradeType == "auction", let endAt = card.endAt {
                    countdownRow(endAt: endAt)
                } else if card.freeShipping == true {
                    Text("包邮").font(.vMicro).foregroundStyle(Color.vGreen)
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
        if card.isSoldCard {
            EmptyView()
        } else if card.tradeType == "auction" {
            Text((card.bidCount ?? 0) > 0 ? "\(card.bidCount!)次出价" : "起拍")
                .font(.vMicro).foregroundStyle(Color.vTextTertiary)
        } else if card.negotiable == true {
            Text("可议价").font(.vMicro).foregroundStyle(Color.vTextSecondary)
        }
    }

    private var soldMeta: some View {
        HStack {
            if let soldAt = card.soldAt {
                Text(soldAt.shortText)
                    .font(.vMicro).foregroundStyle(Color.vTextTertiary)
            }
            Spacer()
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

    static func estimatedHeight(for card: SearchListingCard, imageHeight: CGFloat) -> CGFloat {
        imageHeight + 10 + (card.title.count > 14 ? 40 : 20) + 6 + 18 + 6 + 22 + 6 + 16 + 10
    }

    static func imageHeight(for card: SearchListingCard) -> CGFloat {
        let base: [CGFloat] = [170, 200, 230, 185, 215]
        return base[Int(card.listingId % Int64(base.count))]
    }
}
