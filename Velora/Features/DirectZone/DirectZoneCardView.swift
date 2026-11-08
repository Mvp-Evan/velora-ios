import SwiftUI

/// Dual-column zone card: tap body → detail; 「购买」→ confirm (DES-v1.3-04-01 §5.2 / §9).
struct DirectZoneCardView: View {
    let card: DirectZoneListingCard
    var imageHeight: CGFloat = 200
    var showBuyButton: Bool = true
    var onBuy: (() -> Void)?
    var onOpen: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onOpen?()
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    cover
                    meta
                }
            }
            .buttonStyle(.plain)

            if showBuyButton, card.isPurchasable, sectionAllowsBuy {
                buyRow
            }
        }
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private var sectionAllowsBuy: Bool {
        // Sold section is browse-only.
        card.status != "sold"
    }

    private var cover: some View {
        ZStack(alignment: .topLeading) {
            RemoteImage(card.cover ?? "").frame(height: imageHeight)
            HStack(spacing: 6) {
                if card.showsPriceDrop {
                    Text(DirectZoneCopy.priceDropBadge)
                        .font(.vMicro).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.vPrimary, in: Capsule())
                }
                if let label = card.slotLabel {
                    Text(label.displayText)
                        .font(.vMicro).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(label == .ad ? Color.vCarbon.opacity(0.75) : Color.vPrimary.opacity(0.85), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: VRadius.l, topTrailingRadius: VRadius.l, style: .continuous))
    }

    private var meta: some View {
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
                if card.freeShipping == true {
                    VTagChip(text: "包邮", tint: .vGreen, background: Color.vGreen.opacity(0.12))
                }
                if card.negotiable == true {
                    VTagChip(text: "可议价", tint: .vBlue, background: Color.vBlue.opacity(0.12))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VPriceText(amount: card.price, size: 17)
                if card.showsPriceDrop, let original = card.originalPrice, original > card.price {
                    Text(original.display)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                        .strikethrough()
                }
                Spacer(minLength: 0)
            }

            if let low = card.lowStockText {
                Text(low).font(.vMicro).foregroundStyle(Color.vPrimary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, showBuyButton && card.isPurchasable ? 4 : 10)
    }

    private var buyRow: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                onBuy?()
            } label: {
                Text(DirectZoneCopy.buyShort)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, 14)
                    .background(Color.vPrimary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DirectZoneCopy.buyNow)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    static func estimatedHeight(for card: DirectZoneListingCard, imageHeight: CGFloat, showBuy: Bool) -> CGFloat {
        let titleH: CGFloat = card.title.count > 14 ? 40 : 20
        let buyH: CGFloat = showBuy && card.isPurchasable ? 54 : 10
        return imageHeight + 10 + titleH + 6 + 18 + 6 + 22 + 6 + 16 + buyH
    }

    static func imageHeight(for card: DirectZoneListingCard) -> CGFloat {
        let base: [CGFloat] = [170, 200, 230, 185, 215]
        return base[Int(card.listingId % Int64(base.count))]
    }
}
