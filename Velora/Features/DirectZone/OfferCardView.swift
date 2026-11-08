import SwiftUI

/// Structured offer card for IM / detail (DES-v1.3-04-02 §5.1 / §9). Read-only prices; actions call API.
struct OfferCardView: View {
    let card: OfferCard
    var role: OfferRole = .buyer
    var isActing: Bool = false
    /// When false, only show price / countdown (actions rendered elsewhere, e.g. listing bottom bar).
    var embedActions: Bool = true
    var onAction: ((OfferCardAction) -> Void)?

    @ObservedObject private var ticker = Ticker.shared

    /// Prefer session-synced server clock; fall back to card.serverTime snapshot + local tick.
    private var serverNow: Date {
        let ms = SessionStore.shared.serverClock.serverNowMs()
        if ms > 0 {
            return Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        if let snap = card.serverTime {
            let skew = snap.timeIntervalSince(ticker.now)
            return ticker.now.addingTimeInterval(skew)
        }
        return ticker.now
    }
    private var remain: Int {
        OfferLogic.countdownSeconds(deadline: card.expiresAt, serverTime: serverNow)
    }
    private var expired: Bool {
        if let status = card.status, status.isInactiveChrome || status == .expired { return true }
        return card.expiresAt <= serverNow
    }
    private var visibleActions: [OfferCardAction] {
        if !card.actions.isEmpty { return card.actions }
        return OfferLogic.defaultActions(
            status: card.status ?? .pendingSeller,
            role: role,
            buyerQuoteCount: card.buyerQuoteCount ?? card.round,
            hasOrder: card.orderId != nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            prices
            countdownRow
            if let status = card.status, status == .accepted, let pay = card.payDeadline {
                payRow(pay)
            }
            if embedActions, !expired, card.showsActions || (!card.actions.isEmpty && card.status?.isPending != false) {
                actionsRow
            }
        }
        .padding(14)
        .background(
            Color.vSurface,
            in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VRadius.l, style: .continuous)
                .stroke(Color.vSeparator, lineWidth: 0.5)
        )
        .opacity(expired ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.accessibilityLabel)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RemoteImage(card.cover ?? "")
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title ?? "商品")
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    VTagChip(
                        text: card.roundText,
                        tint: .vBlue,
                        background: Color.vBlue.opacity(0.12)
                    )
                    if let status = card.status {
                        Text(status.displayLabel)
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var prices: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(OfferCopy.listPriceLabel)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                Text(OfferLogic.yuanDisplay(card.listPrice))
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                    .strikethrough(card.offerPrice < card.listPrice)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(OfferCopy.offerPriceLabel)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                Text(OfferLogic.yuanDisplay(card.offerPrice))
                    .font(.vPrice(26))
                    .foregroundStyle(Color.vPrice)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
        }
    }

    private var countdownRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
            if expired {
                Text(OfferCopy.expiredHint).font(.vCaption)
            } else {
                Text(OfferLogic.offerCountdownLine(seconds: remain)).font(.vCaption)
            }
        }
        .foregroundStyle(expired ? Color.vTextTertiary : (remain < 3600 ? Color.vPrimary : Color.vTextSecondary))
        .accessibilityLabel(expired ? OfferCopy.expiredHint : OfferCopy.offerCountdownLabel)
        .accessibilityValue(expired ? "已过期" : OfferLogic.formatCountdown(seconds: remain))
    }

    private func payRow(_ deadline: Date) -> some View {
        let secs = OfferLogic.countdownSeconds(deadline: deadline, serverTime: serverNow)
        return HStack(spacing: 6) {
            Image(systemName: "creditcard")
                .font(.system(size: 12, weight: .medium))
            Text(OfferLogic.payCountdownLine(seconds: secs)).font(.vCaption)
        }
        .foregroundStyle(Color.vGold)
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            ForEach(visibleActions, id: \.rawValue) { action in
                actionButton(action)
            }
        }
    }

    private func actionButton(_ action: OfferCardAction) -> some View {
        Button {
            guard !isActing else { return }
            onAction?(action)
        } label: {
            Text(isActing ? OfferCopy.pendingButton : action.title)
                .font(.vCaptionMedium)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .foregroundStyle(action.isPrimary ? Color.white : Color.vText)
                .background(
                    action.isPrimary ? Color.vPrimary : Color.vFill,
                    in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                )
        }
        .disabled(isActing)
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    OfferCardView(
        card: OfferCard(
            offerId: 1,
            listingId: 7,
            cover: "",
            title: "RB19 直购样例",
            listPrice: 128_000,
            offerPrice: 100_000,
            expiresAt: Date().addingTimeInterval(8_000),
            round: 1,
            status: .pendingSeller,
            actions: [.accept, .reject, .counter],
            minPrice: 64_000
        ),
        role: .seller
    )
    .padding()
    .background(Color.vBackground)
}
#endif
