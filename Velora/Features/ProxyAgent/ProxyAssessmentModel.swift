import Foundation
import Combine

/// Monthly KPI + forecast for dedicated proxy agents (DES-v1.3-05-01 §5.5 / §9).
@MainActor
final class ProxyAssessmentModel: ObservableObject {
    enum State: Equatable {
        case idle, loading
        case loaded
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var profile: ProxySellerProfile?
    @Published var items: [ProxyAssessmentMonth] = []
    @Published var forecast: ProxyAssessmentForecast?
    @Published var showDowngrade = false

    private var lastKnownLevel: ProxyAssessmentLevel?

    var currentLevel: ProxyAssessmentLevel {
        profile?.assessmentLevel ?? .gold
    }

    var badgeLabel: String {
        profile?.buyerBadgeLabel ?? ProxyAgentCopy.goldBadge
    }

    var latest: ProxyAssessmentMonth? { items.first }

    func load() async {
        if state == .idle { state = .loading }
        let previous = lastKnownLevel
        let profileResult = await fetchProfile()
        let listResult = await fetchAssessments()
        profile = profileResult
        items = listResult.items.sorted { $0.yearMonth > $1.yearMonth }
        forecast = listResult.forecast
        if let prev = previous, let next = profileResult.assessmentLevel, next != prev,
           shouldPromptDowngrade(from: prev, to: next) {
            showDowngrade = true
        }
        lastKnownLevel = profileResult.assessmentLevel ?? previous
        state = .loaded
    }

    func downgradeNotice() -> ProxyDowngradeNotice? {
        guard let to = profile?.assessmentLevel, to != .gold else { return nil }
        let from: ProxyAssessmentLevel = (to == .probation) ? .gold : (lastKnownLevel == .gold ? .gold : .probation)
        return ProxyDowngradeNotice(from: from, to: to)
    }

    private func shouldPromptDowngrade(from: ProxyAssessmentLevel, to: ProxyAssessmentLevel) -> Bool {
        switch (from, to) {
        case (.gold, .probation), (.gold, .revoked), (.probation, .revoked): return true
        default: return false
        }
    }

    private func fetchProfile() async -> ProxySellerProfile {
        do {
            return try await API.proxySellerProfile()
        } catch {
            return ProxySellerProfile(
                sellerType: ProxyAgentConfigDefaults.sellerType,
                badge: ProxyAgentConfigDefaults.badgeGoldWire,
                assessmentLevel: .gold,
                capabilities: .goldDefaults
            )
        }
    }

    private func fetchAssessments() async -> ProxyAssessmentListResponse {
        do {
            return try await API.proxyAssessments()
        } catch {
            return ProxyAssessmentListResponse()
        }
    }
}
