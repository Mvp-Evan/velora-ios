import Foundation
import Combine

/// 拍场专场日历（DES-v1.3-03-03 §5.5 / AUC-05）
@MainActor
final class AuctionSessionCalendarModel: ObservableObject {
    @Published var sessions: [AuctionSession] = []
    @Published var state: LoadState = .idle
    @Published var weekStart: Date?
    @Published var serverTime: Date?
    @Published var selected: AuctionSessionDetailResponse?
    @Published var detailState: LoadState = .idle
    @Published var subscribingId: Int64?

    private var weekAnchor: Date = Date()

    func load(weekOf date: Date = Date()) async {
        weekAnchor = date
        if sessions.isEmpty { state = .loading }
        do {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            // Prefer UTC week_start query so local TZ cannot shift the close day (design §9).
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: 0)!
            let startOfDay = cal.startOfDay(for: date)
            let weekday = cal.component(.weekday, from: startOfDay)
            // Align to Monday 00:00 UTC of that week (design default preview week).
            let daysFromMonday = (weekday + 5) % 7
            let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
            let resp = try await API.auctionSessions(weekStart: iso.string(from: monday))
            sessions = resp.displaySessions
            weekStart = resp.weekStart ?? monday
            serverTime = resp.serverTime
            state = .loaded
        } catch {
            if sessions.isEmpty {
                state = .failed((error as? APIError)?.message ?? "专场日历加载失败")
            } else {
                ToastCenter.shared.error(error)
                state = .loaded
            }
        }
    }

    func shiftWeek(_ delta: Int) async {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let next = cal.date(byAdding: .day, value: 7 * delta, to: weekAnchor) else { return }
        await load(weekOf: next)
    }

    func loadDetail(_ id: Int64) async {
        detailState = .loading
        do {
            selected = try await API.auctionSession(id)
            detailState = .loaded
        } catch {
            detailState = .failed((error as? APIError)?.message ?? "专场详情加载失败")
        }
    }

    func subscribeSession(_ id: Int64) async {
        guard subscribingId == nil else { return }
        subscribingId = id
        defer { subscribingId = nil }
        do {
            _ = try await API.subscribeAuctionSession(id)
            if let idx = sessions.firstIndex(where: { $0.id == id }) {
                sessions[idx].subscribed = true
            }
            if let detail = selected, detail.session.id == id {
                var s = detail.session
                s.subscribed = true
                selected = AuctionSessionDetailResponse(session: s, lots: detail.lots)
            }
            ToastCenter.shared.show("已订阅专场提醒", .success)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}
