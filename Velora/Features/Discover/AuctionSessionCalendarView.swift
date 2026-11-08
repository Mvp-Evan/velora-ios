import SwiftUI

/// 专场日历：预展 / 今晚结拍、错峰间隔、空场占位（DES-v1.3-03-03 §5.5 / §9）
struct AuctionSessionCalendarView: View {
    @StateObject private var model = AuctionSessionCalendarModel()

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                sessionSkeleton
            case .failed(let m):
                VErrorView(message: m) { Task { await model.load() } }
            case .loaded:
                if model.sessions.isEmpty {
                    VEmptyState(icon: "calendar", title: AntiSnipeCopy.sessionEmpty, message: "运营排期发布后会出现在这里")
                } else {
                    ScrollView {
                        LazyVStack(spacing: VSpace.m) {
                            weekHeader
                            ForEach(model.sessions) { session in
                                NavigationLink {
                                    AuctionSessionDetailView(sessionId: session.id, preload: session, model: model)
                                } label: {
                                    SessionCalendarRow(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, VSpace.l)
                        .padding(.bottom, VSpace.xl)
                    }
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle("专场日历")
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.sessions.isEmpty { await model.load() } }
        .refreshable { await model.load(weekOf: model.weekStart ?? Date()) }
    }

    private var weekHeader: some View {
        HStack {
            Button { Task { await model.shiftWeek(-1) } } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
            }
            Spacer()
            Text(weekLabel).font(.vCaptionMedium).foregroundStyle(Color.vTextSecondary)
            Spacer()
            Button { Task { await model.shiftWeek(1) } } label: {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
            }
        }
        .foregroundStyle(Color.vText)
        .padding(.vertical, VSpace.s)
    }

    private var weekLabel: String {
        guard let start = model.weekStart else { return "本周专场" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "M月d日"
        let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: 6, to: start) ?? start
        return "\(f.string(from: start)) – \(f.string(from: end))（UTC）"
    }

    private var sessionSkeleton: some View {
        VStack(spacing: VSpace.m) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: VRadius.l, style: .continuous)
                    .fill(Color.vFill)
                    .frame(height: 96)
                    .redacted(reason: .placeholder)
            }
            Spacer()
        }
        .padding(VSpace.l)
    }
}

private struct SessionCalendarRow: View {
    let session: AuctionSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(session.statusChip)
                    .font(.vMicro)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(chipColor, in: Capsule())
                if session.subscribed == true {
                    Text("已订阅").font(.vMicro).foregroundStyle(Color.vPrimary)
                }
                Spacer()
                if let n = session.lotCount {
                    Text("\(n)/\(session.dailyCap ?? AntiSnipeConfig.sessionDailyCap) 件")
                        .font(.vMicro).foregroundStyle(Color.vTextTertiary)
                }
            }
            Text(session.name).font(.vHeadline).foregroundStyle(Color.vText).lineLimit(2)
            if let hint = session.staggerHint {
                Text(hint).font(.vCaption).foregroundStyle(Color.vTextSecondary)
            }
            if let first = session.firstEndAt {
                Text("首件计划 \(first.shortText)")
                    .font(.vCaption).foregroundStyle(Color.vTextTertiary)
            }
        }
        .padding(VSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private var chipColor: Color {
        switch session.status {
        case .live: return .vPrimary
        case .closed: return .vTextTertiary
        default: return .vBlue
        }
    }
}

struct AuctionSessionDetailView: View {
    let sessionId: Int64
    var preload: AuctionSession?
    @ObservedObject var model: AuctionSessionCalendarModel

    var body: some View {
        Group {
            switch model.detailState {
            case .idle, .loading:
                VLoadingView()
            case .failed(let m):
                VErrorView(message: m) { Task { await model.loadDetail(sessionId) } }
            case .loaded:
                if let detail = model.selected {
                    detailBody(detail)
                } else {
                    VEmptyState(icon: "calendar", title: AntiSnipeCopy.sessionEmpty)
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(preload?.name ?? model.selected?.session.name ?? "专场")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let subscribed = model.selected?.session.subscribed == true || preload?.subscribed == true
                Button(subscribed ? "已订阅" : "订阅提醒") {
                    Task { await model.subscribeSession(sessionId) }
                }
                .disabled(subscribed || model.subscribingId == sessionId)
            }
        }
        .task { await model.loadDetail(sessionId) }
    }

    private func detailBody(_ detail: AuctionSessionDetailResponse) -> some View {
        let lots = detail.lotsBySlot
        return ScrollView {
            VStack(alignment: .leading, spacing: VSpace.m) {
                header(detail.session)
                if lots.isEmpty {
                    VEmptyState(icon: "tray", title: AntiSnipeCopy.sessionEmpty, message: "拍品排入后将按槽位错峰结拍")
                } else {
                    ForEach(lots) { row in
                        NavigationLink(value: row.lotId) {
                            SessionLotRow(lot: row, intervalHint: detail.session.intervalSeconds)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(VSpace.l)
        }
        .navigationDestination(for: Int64.self) { LotDetailView(lotId: $0) }
    }

    private func header(_ session: AuctionSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.statusChip).font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                Spacer()
                if let n = session.lotCount {
                    let cap = session.dailyCap ?? AntiSnipeConfig.sessionDailyCap
                    Text("\(n)/\(cap)")
                        .font(.vMono(13))
                        .foregroundStyle(n >= cap ? Color.vPrimary : Color.vTextSecondary)
                }
            }
            if let hint = session.staggerHint {
                Text(hint).font(.vBody).foregroundStyle(Color.vTextSecondary)
            }
            if nIsFull(session) {
                Text(AntiSnipeCopy.sessionFullHint)
                    .font(.vCaption).foregroundStyle(Color.vTextTertiary)
            }
        }
        .padding(VSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func nIsFull(_ session: AuctionSession) -> Bool {
        let n = session.lotCount ?? 0
        let cap = session.dailyCap ?? AntiSnipeConfig.sessionDailyCap
        return n >= cap
    }
}

private struct SessionLotRow: View {
    let lot: AuctionSessionLot
    var intervalHint: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let cover = lot.cover, !cover.isEmpty {
                RemoteImage(cover).frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                    .fill(Color.vFill).frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let slot = lot.slotIndex {
                        Text("#\(slot)").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                    }
                    Text(lot.title ?? "拍品").font(.vBodyMedium).foregroundStyle(Color.vText).lineLimit(1)
                }
                if let planned = lot.plannedEndAt {
                    Text("计划结束 \(planned.shortText)")
                        .font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
                if let intervalHint, intervalHint > 0 {
                    Text(AntiSnipeCopy.sessionStaggerHint)
                        .font(.vMicro).foregroundStyle(Color.vTextTertiary)
                }
            }
            Spacer(minLength: 0)
            if let price = lot.currentPrice {
                Text(Money(price).display).font(.vMono(14, weight: .bold)).foregroundStyle(Color.vText)
            }
        }
        .padding(12)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }
}
