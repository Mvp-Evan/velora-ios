import SwiftUI

/// 我的抽签：报名中 / 待开奖 / 中签待付倒计时 / 候补 / 未中签（DES-v1.3-06-02 §9）。
struct MyLotteryEntriesView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = MyLotteryEntriesModel()
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
        .navigationTitle(LotteryCopy.myEntriesTitle)
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
                    ForEach(MyLotteryEntriesModel.Filter.allCases) { f in
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
                    icon: "ticket",
                    title: LotteryCopy.emptyEntries,
                    message: LotteryCopy.emptyEntriesHint
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: VSpace.m) {
                        ForEach(model.items) { entry in
                            NavigationLink {
                                if let rid = entry.releaseId {
                                    LotteryEnrollView(releaseId: rid)
                                } else {
                                    Text("活动不可用")
                                }
                            } label: {
                                row(entry)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if entry.id == model.items.last?.id {
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

    private func row(_ entry: LotteryEntry) -> some View {
        let cta = LotteryLogic.resolveEntryCTA(entry: entry, serverNow: model.serverNow)
        return VCard {
            HStack(alignment: .top, spacing: VSpace.m) {
                RemoteImage(entry.cover ?? "")
                    .frame(width: 72, height: 72)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.displayTitle)
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vText)
                        .lineLimit(2)
                    Text(model.subtitle(for: entry))
                        .font(.vCaption)
                        .foregroundStyle(cta == .pay ? Color.vPrimary : Color.vTextSecondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        VTagChip(
                            text: entry.resolvedStatus.displayLabel,
                            tint: tagTint(cta),
                            background: tagTint(cta).opacity(0.12)
                        )
                        if let no = entry.entryNo {
                            Text("签号 \(no)")
                                .font(.vMicro)
                                .foregroundStyle(Color.vTextTertiary)
                        }
                        Spacer(minLength: 0)
                        if cta == .pay {
                            Text(LotteryCopy.payCTA)
                                .font(.vCaptionMedium)
                                .foregroundStyle(Color.vPrimary)
                        }
                    }
                }
            }
        }
    }

    private func tagTint(_ cta: LotteryCTA) -> Color {
        switch cta {
        case .pay: return .vPrimary
        case .waitlist: return .vGold
        case .lost, .forfeited: return .vTextSecondary
        case .paid: return .vGreen
        default: return .vBlue
        }
    }
}
