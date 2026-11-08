import Foundation
import Combine

/// Purchase-home recommendation slots (`GET /home/slots`) with versioned replace + poll.
@MainActor
final class HomeSlotsModel: ObservableObject {
    @Published private(set) var banners: [HomeSlotItem] = []
    @Published private(set) var cards: [HomeSlotItem] = []
    @Published private(set) var sessions: [HomeSlotItem] = []
    @Published private(set) var slotConfigVersion: Int64?
    @Published private(set) var requestId: String?
    @Published private(set) var loaded = false
    /// Slots failure must not block natural feed (DES §9).
    @Published private(set) var failedSilently = false

    private var pollTask: Task<Void, Never>?
    private var lastBackgroundAt: Date?

    var hasContent: Bool { !banners.isEmpty || !cards.isEmpty || !sessions.isEmpty }

    func load(force: Bool = false) async {
        do {
            let raw = try await API.homeSlots()
            let resp = raw.filteringExpired()
            if force || slotConfigVersion != resp.slotConfigVersion || !loaded {
                banners = resp.banners
                cards = resp.cards
                sessions = resp.sessions
                slotConfigVersion = resp.slotConfigVersion
            } else {
                // Same version: still refresh request_id for exposure correlation.
                banners = resp.banners
                cards = resp.cards
                sessions = resp.sessions
            }
            requestId = resp.requestId
            loaded = true
            failedSilently = false
        } catch {
            failedSilently = true
            // Keep previous slots if any; otherwise leave empty.
        }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(HomeExposurePolicy.slotsPollIntervalSeconds))
                guard !Task.isCancelled else { break }
                await self?.load()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func noteBackground() {
        lastBackgroundAt = Date()
    }

    func refreshIfStaleAfterForeground() async {
        guard let last = lastBackgroundAt else { return }
        lastBackgroundAt = nil
        if Date().timeIntervalSince(last) >= HomeExposurePolicy.backgroundRefreshThresholdSeconds {
            await load(force: true)
        }
    }
}
