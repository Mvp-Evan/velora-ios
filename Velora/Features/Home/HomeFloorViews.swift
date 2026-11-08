import SwiftUI

// MARK: - Floor chrome

struct HomeFloorHeader: View {
    let title: String
    var subtitle: String? = nil
    var moreTitle: String = "查看更多"
    var onMore: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.vHeadline)
                    .foregroundStyle(Color.vText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
            Spacer(minLength: 8)
            if let onMore {
                Button(action: onMore) {
                    HStack(spacing: 2) {
                        Text(moreTitle).font(.vCaptionMedium)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.vTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, VSpace.l)
    }
}

/// Quick-entry grid: 拍卖 / 直购 / 发售 / 专场.
struct HomeQuickEntryGrid: View {
    var onAuction: () -> Void
    var onFixed: () -> Void
    var onRelease: () -> Void
    var onSessions: () -> Void

    private let entries: [(title: String, icon: String, tint: Color)] = [
        ("拍卖", "hammer.fill", .vPrimary),
        ("直购", "bag.fill", .vBlue),
        ("发售", "sparkles", .vGold),
        ("专场", "calendar", .vCarbon),
    ]

    var body: some View {
        HStack(spacing: VSpace.m) {
            ForEach(Array(entries.enumerated()), id: \.offset) { idx, e in
                Button {
                    switch idx {
                    case 0: onAuction()
                    case 1: onFixed()
                    case 2: onRelease()
                    default: onSessions()
                    }
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(e.tint.opacity(0.12))
                                .frame(width: 48, height: 48)
                            Image(systemName: e.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(e.tint)
                        }
                        Text(e.title)
                            .font(.vCaptionMedium)
                            .foregroundStyle(Color.vText)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, VSpace.l)
    }
}

// MARK: - Horizontal auction cards

struct HomeAuctionRail: View {
    let title: String
    var subtitle: String? = nil
    let cards: [HomeFeedCard]
    var showsStartCountdown: Bool = false
    var onMore: () -> Void
    var onOpen: (HomeFeedCard) -> Void

    var body: some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HomeFloorHeader(title: title, subtitle: subtitle, onMore: onMore)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VSpace.m) {
                        ForEach(cards) { card in
                            Button { onOpen(card) } label: {
                                HomeAuctionRailCard(card: card, showsStartCountdown: showsStartCountdown)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, VSpace.l)
                }
            }
        }
    }
}

struct HomeAuctionRailCard: View {
    let card: HomeFeedCard
    var showsStartCountdown: Bool = false
    @ObservedObject private var ticker = Ticker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RemoteImage(card.cover)
                    .frame(width: 148, height: 148)
                HStack(spacing: 4) {
                    if let badge = card.sellerBadge {
                        SellerBadgeChip(badge: badge)
                    }
                    Spacer(minLength: 0)
                    if card.delayed {
                        Text(LotCardHeatCopy.delayedBadge)
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.vGold.opacity(0.95), in: Capsule())
                    }
                }
                .padding(6)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: VRadius.m, topTrailingRadius: VRadius.m, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                    .frame(height: 36, alignment: .topLeading)
                VPriceText(amount: card.displayPrice, size: 15)
                if showsStartCountdown, let listed = card.listedAt ?? card.endAt {
                    // Prefer endAt as open time when scheduled feed cards expose start via endAt absence;
                    // listedAt is listing time — countdown to endAt when available for upcoming lots.
                    let target = card.endAt ?? listed
                    Text(countdownLabel(until: target, prefix: "开拍"))
                        .font(.vMicro)
                        .foregroundStyle(Color.vPrimary)
                } else if let endAt = card.endAt {
                    Text(countdownLabel(until: endAt, prefix: "距结拍"))
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextSecondary)
                }
                if let bids = card.bidCount, bids > 0 {
                    Text("\(bids) 次出价")
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
            .padding(8)
            .frame(width: 148, alignment: .leading)
        }
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }

    private func countdownLabel(until date: Date, prefix: String) -> String {
        let remain = max(0, Int(date.timeIntervalSince(ticker.now)))
        let h = remain / 3600
        let m = (remain % 3600) / 60
        let s = remain % 60
        if h > 24 {
            return "\(prefix) \(h / 24) 天"
        }
        return String(format: "%@ %02d:%02d:%02d", prefix, h, m, s)
    }
}

// MARK: - Fixed picks grid

struct HomeFixedFloor: View {
    let cards: [HomeFeedCard]
    var onMore: () -> Void
    var onOpen: (HomeFeedCard) -> Void

    private var rows: [[HomeFeedCard]] {
        stride(from: 0, to: min(cards.count, 8), by: 2).map { i in
            Array(cards[i..<min(i + 2, cards.count)])
        }
    }

    var body: some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HomeFloorHeader(title: "直购精选", subtitle: "一口价 · 可议价", onMore: onMore)
                VStack(spacing: VSpace.m) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: VSpace.m) {
                            ForEach(row) { card in
                                Button { onOpen(card) } label: {
                                    HomeFixedPickCard(card: card)
                                }
                                .buttonStyle(.plain)
                            }
                            if row.count == 1 { Spacer(minLength: 0) }
                        }
                    }
                }
                .padding(.horizontal, VSpace.l)
            }
        }
    }
}

struct HomeFixedPickCard: View {
    let card: HomeFeedCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RemoteImage(card.cover)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                HStack {
                    if let badge = card.sellerBadge {
                        SellerBadgeChip(badge: badge)
                    }
                    Spacer()
                    if card.freeShipping == true {
                        Text("包邮")
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.vBlue.opacity(0.9), in: Capsule())
                    }
                }
                .padding(6)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: VRadius.m, topTrailingRadius: VRadius.m, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                    .frame(height: 36, alignment: .topLeading)
                HStack(alignment: .firstTextBaseline) {
                    VPriceText(amount: card.displayPrice, size: 15)
                    Spacer()
                    if card.negotiable == true {
                        Text("可议价")
                            .font(.vMicro)
                            .foregroundStyle(Color.vGold)
                    }
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }
}

// MARK: - Release floor

struct HomeReleaseFloor: View {
    let cards: [HomeFeedCard]
    var onMore: () -> Void
    var onOpen: (HomeFeedCard) -> Void

    var body: some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HomeFloorHeader(title: "新品发售", subtitle: "现货 · 抽签 · 预售", onMore: onMore)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: VSpace.m) {
                        ForEach(cards) { card in
                            Button { onOpen(card) } label: {
                                HomeReleaseCard(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, VSpace.l)
                }
            }
        }
    }
}

struct HomeReleaseCard: View {
    let card: HomeFeedCard

    private var modeLabel: String {
        switch card.releaseMode {
        case "spot": return "现货"
        case "lottery": return "抽签"
        case "presale": return "预售"
        default: return "发售"
        }
    }

    private var statusLabel: String {
        switch card.releaseStatus {
        case "upcoming", "scheduled", "not_started": return "即将开售"
        case "live", "on_sale", "enrolling": return "进行中"
        case "sold_out": return "已售罄"
        case "drawn", "ended": return "已结束"
        default: return card.releaseStatus ?? ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RemoteImage(card.cover)
                    .frame(width: 200, height: 120)
                HStack {
                    Text(modeLabel)
                        .font(.vMicro).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.vGold.opacity(0.95), in: Capsule())
                    Spacer()
                    if !statusLabel.isEmpty {
                        Text(statusLabel)
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.vCarbon.opacity(0.7), in: Capsule())
                    }
                }
                .padding(8)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: VRadius.m, topTrailingRadius: VRadius.m, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                    .frame(width: 184, height: 36, alignment: .topLeading)
                VPriceText(amount: card.displayPrice, size: 15)
            }
            .padding(10)
        }
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }
}
