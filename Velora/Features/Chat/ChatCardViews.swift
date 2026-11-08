import SwiftUI

/// Listing / order card bubbles for private chat (DES-v1.3-11-02 MSG-02 / §5.6 / §9).
struct ChatListingCardView: View {
    let card: ChatListingCardPayload
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RemoteImage(card.cover ?? "")
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                    if card.isInactive {
                        RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 56, height: 56)
                        Text(ChatCopy.listingInvalidOverlay)
                            .font(.vMicro)
                            .foregroundStyle(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(ChatCopy.listingCardTitle)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                    Text(card.title)
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(2)
                    VPriceText(amount: card.price, size: 14)
                        .opacity(card.isInactive ? 0.55 : 1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
            }
            .padding(12)
            .frame(minHeight: CGFloat(ChatConfigDefaults.cardMinTapHeightPt), alignment: .center)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                Color.vSurface,
                in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VRadius.l, style: .continuous)
                    .stroke(Color.vSeparator, lineWidth: 0.5)
            )
            .opacity(card.isInactive ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ChatCopy.listingCardTitle) \(card.title)")
    }
}

struct ChatOrderCardView: View {
    let card: ChatOrderCardPayload
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.vPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(ChatCopy.orderCardTitle)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                    Text(card.title ?? card.orderNo ?? "订单 #\(card.orderId)")
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        VPriceText(amount: card.amount, size: 14)
                        if let status = card.status, !status.isEmpty {
                            Text(status)
                                .font(.vMicro)
                                .foregroundStyle(Color.vTextSecondary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
            }
            .padding(12)
            .frame(minHeight: CGFloat(ChatConfigDefaults.cardMinTapHeightPt), alignment: .center)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                Color.vSurface,
                in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VRadius.l, style: .continuous)
                    .stroke(Color.vSeparator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ChatCopy.orderCardTitle) \(card.orderNo ?? "\(card.orderId)")")
    }
}

/// N-24 risk strip under a bubble / top bar — not dismissible for the session (design §9).
struct ChatRiskStripView: View {
    let text: String
    var showsLearnMore: Bool = true
    var onLearnMore: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x8A5A00))
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.vCaption)
                    .foregroundStyle(Color(hex: 0x8A5A00))
                    .fixedSize(horizontal: false, vertical: true)
                if showsLearnMore {
                    Button(ChatCopy.learnProtection) {
                        onLearnMore?()
                    }
                    .font(.vMicro)
                    .foregroundStyle(Color.vPrimary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VSpace.l)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFF6E0))
        .accessibilityLabel(text)
    }
}
