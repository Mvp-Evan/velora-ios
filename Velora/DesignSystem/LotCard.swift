import SwiftUI

/// 瀑布流拍品卡片
struct LotCard: View {
    let lot: Lot
    var imageHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RemoteImage(lot.cover).frame(height: imageHeight)
                HStack(spacing: 6) {
                    VStatusBadge(status: lot.status)
                    Spacer(minLength: 0)
                    if lot.extensionCount > 0 {
                        Text(LotCardHeatCopy.delayedBadge)
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.vGold.opacity(0.95), in: Capsule())
                    } else if lot.myBid.hasBid {
                        Text(lot.myBid.leading ? "领先" : "被超越")
                            .font(.vMicro).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(lot.myBid.leading ? Color.vGold : Color.vCarbon.opacity(0.8), in: Capsule())
                    }
                }
                .padding(8)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: VRadius.l, topTrailingRadius: VRadius.l, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(lot.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    ForEach(lot.tags.prefix(2), id: \.self) { VTagChip(text: $0) }
                }

                HStack(alignment: .firstTextBaseline) {
                    VPriceText(amount: lot.displayPrice, size: 17)
                    Spacer()
                    Text(lot.bidCount > 0 ? "\(lot.bidCount)次出价" : "起拍")
                        .font(.vMicro).foregroundStyle(Color.vTextTertiary)
                }

                HStack {
                    VCountdown(endAt: lot.isUpcoming ? lot.startAt : lot.endAt, status: lot.status)
                    Spacer()
                    HStack(spacing: 4) {
                        VAvatar(url: lot.seller.avatar, size: 16)
                        Text(lot.seller.nickname).font(.vMicro).foregroundStyle(Color.vTextTertiary).lineLimit(1)
                    }
                    .frame(maxWidth: 90, alignment: .trailing)
                }
            }
            .padding(10)
        }
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    /// 估算卡片高度用于瀑布流分配
    static func estimatedHeight(for lot: Lot, imageHeight: CGFloat) -> CGFloat {
        imageHeight + 10 + (lot.title.count > 14 ? 40 : 20) + 6 + 18 + 6 + 22 + 6 + 16 + 10
    }

    /// 根据 id 生成稳定的图片高度（模拟不同比例）
    static func imageHeight(for lot: Lot) -> CGFloat {
        let base: [CGFloat] = [170, 200, 230, 185, 215]
        return base[Int(lot.id % Int64(base.count))]
    }
}

/// 横向列表小卡片（正在竞拍）
struct LotStripCard: View {
    let lot: Lot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(lot.cover).frame(width: 140, height: 140)
                VGradient.imageScrim.frame(height: 50).frame(maxHeight: .infinity, alignment: .bottom)
                HStack(spacing: 3) {
                    Image(systemName: "timer").font(.system(size: 9, weight: .bold))
                    VCountdown(endAt: lot.endAt, status: lot.status, style: .inline).foregroundStyle(.white)
                }
                .font(.vMono(11))
                .foregroundStyle(.white)
                .padding(8)
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))

            Text(lot.title).font(.vCaptionMedium).foregroundStyle(Color.vText).lineLimit(1)
            HStack {
                VPriceText(amount: lot.displayPrice, size: 15)
                Spacer()
                Text("\(lot.bidCount)次").font(.vMicro).foregroundStyle(Color.vTextTertiary)
            }
        }
        .frame(width: 140)
    }
}

/// 列表行样式（我的拍品 / 出价 / 关注）
struct LotRow: View {
    let lot: Lot
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(lot.cover).frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(lot.title).font(.vBodyMedium).foregroundStyle(Color.vText).lineLimit(2)
                HStack(spacing: 6) {
                    VStatusBadge(status: lot.status)
                    if lot.myBid.hasBid && lot.isLive {
                        Text(lot.myBid.leading ? "领先中" : "已被超越").font(.vMicro).foregroundStyle(lot.myBid.leading ? Color.vGold : Color.vTextSecondary)
                    }
                }
                HStack {
                    VPriceText(amount: lot.displayPrice, size: 16)
                    Spacer()
                    if let trailing { Text(trailing).font(.vCaption).foregroundStyle(Color.vTextTertiary) }
                    else { VCountdown(endAt: lot.isUpcoming ? lot.startAt : lot.endAt, status: lot.status) }
                }
            }
        }
        .padding(12)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }
}
