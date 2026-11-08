import SwiftUI

/// Conversation row shared by the notification-center chat tab (DES-v1.3-11-01 / D38 subject preview).
struct ConversationRow: View {
    let conv: Conversation
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                VAvatar(url: conv.peer.avatar, size: 48)
                if let lot = conv.lot {
                    RemoteImage(lot.cover).frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.vSurface, lineWidth: 2)).offset(x: 4, y: 4)
                } else if conv.resolvedSubjectType == .order {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.vPrimary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.vSurface, lineWidth: 2))
                        .offset(x: 4, y: 4)
                } else if conv.resolvedSubjectType == .listing {
                    Image(systemName: "tag")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.vPrimary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.vSurface, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conv.peer.nickname).font(.vBodyMedium)
                    Spacer()
                    Text(conv.lastMessageAt?.relativeText ?? "").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                }
                HStack {
                    Text(previewText).font(.vCaption).foregroundStyle(Color.vTextSecondary).lineLimit(1)
                    Spacer()
                    if conv.unread > 0 {
                        Text("\(conv.unread)").font(.vMicro).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Color.vPrimary, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, VSpace.l).padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var previewText: String {
        if !conv.lastMessage.isEmpty { return conv.lastMessage }
        if let title = conv.lot?.title { return "[\(title)]" }
        switch conv.resolvedSubjectType {
        case .order: return ChatCopy.orderCardTitle
        case .listing: return ChatCopy.listingCardTitle
        case .lot: return "拍品"
        }
    }
}

/// Live auction notice feed (room WS) — kept as a secondary surface under 竞拍.
struct NoticeListView: View {
    @EnvironmentObject private var live: AuctionLiveStore
    @EnvironmentObject private var router: AppRouter
    var body: some View {
        ScrollView {
            if live.noticeFeed.isEmpty {
                VEmptyState(icon: "bell", title: "暂无通知", message: "本次运行期间收到的实时拍卖通知会显示在这里")
            } else {
                LazyVStack(spacing: VSpace.m) {
                    ForEach(live.noticeFeed) { n in
                        Button {
                            if let o = n.orderId { router.open(order: o) }
                            else if let l = n.lotId { router.open(lot: l) }
                        } label: {
                            VCard {
                                HStack(alignment: .top, spacing: 12) {
                                    Circle().fill(Color.vPrimary).frame(width: 8, height: 8).padding(.top, 6)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(n.title).font(.vBodyMedium)
                                        Text(n.message).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Color.vTextTertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(VSpace.l)
            }
        }
        .background(Color.vBackground)
        .navigationTitle("拍卖通知")
        .navigationBarTitleDisplayMode(.inline)
    }
}
