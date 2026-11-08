import Foundation
import Combine
import SwiftUI

/// Per-list-instance card realtime session (DES-v1.3-02-03).
/// Owns visibility → subscribe_card, lot_card_tick apply (no reorder), and end-time change banner.
@MainActor
final class ListCardRealtimeSession: ObservableObject {
    @Published private(set) var liveByLotId: [Int64: LotCardLiveFields] = [:]
    @Published private(set) var endTimeChanges = EndTimeChangeTracker()
    @Published private(set) var realtimePaused = false

    private var engine = LotCardVisibilityEngine()
    private var preferredOrder: [Int64] = []
    private var bag = Set<AnyCancellable>()
    private var debounceTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var visibilityPollTask: Task<Void, Never>?
    private var active = false
    private var lastScrollOffset: CGFloat = 0
    private var lastScrollAt: Date = .distantPast
    private var viewportHeight: CGFloat = 800

    init() {
        WebSocketClient.shared.$connected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ok in
                guard let self else { return }
                self.realtimePaused = !ok
                if ok, self.active {
                    self.resubscribeAll()
                }
            }
            .store(in: &bag)

        WebSocketClient.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ev in self?.handle(ev) }
            .store(in: &bag)
    }

    deinit {
        // Tasks cancelled via stop(); cannot call MainActor stop from deinit safely.
    }

    func start() {
        guard !active else { return }
        active = true
        realtimePaused = !WebSocketClient.shared.connected
        startHeartbeat()
        startVisibilityPoll()
    }

    func stop() {
        active = false
        debounceTask?.cancel()
        heartbeatTask?.cancel()
        visibilityPollTask?.cancel()
        let ids = Array(engine.subscribed)
        if !ids.isEmpty {
            WebSocketClient.shared.unsubscribeCards(ids)
        }
        engine.resetSubscriptionsKeepingStale()
    }

    /// Call when HTTP list is replaced (refresh / filter). Does not auto-reorder.
    func replaceDataSource(lotIdsWithVersions: [(Int64, Int?)]) {
        endTimeChanges.clear()
        var nextLive: [Int64: LotCardLiveFields] = [:]
        for (id, ver) in lotIdsWithVersions {
            endTimeChanges.seed(lotId: id, version: ver)
            if let existing = liveByLotId[id] {
                var copy = existing
                if let ver { copy.endAtVersion = ver }
                nextLive[id] = copy
            } else {
                var fields = LotCardLiveFields()
                fields.endAtVersion = ver
                nextLive[id] = fields
            }
        }
        // Drop live state for lots no longer in page.
        let keep = Set(lotIdsWithVersions.map(\.0))
        for id in liveByLotId.keys where !keep.contains(id) {
            engine.remove(lotId: id)
        }
        liveByLotId = nextLive
        preferredOrder = lotIdsWithVersions.map(\.0)
        scheduleReconcile()
    }

    func clearForFilterChange() {
        endTimeChanges.clearForFilterChange()
        let ids = Array(engine.subscribed)
        if !ids.isEmpty { WebSocketClient.shared.unsubscribeCards(ids) }
        engine = LotCardVisibilityEngine()
        liveByLotId = [:]
        preferredOrder = []
    }

    func acknowledgeBannerAndRefresh() {
        endTimeChanges.clear()
    }

    // MARK: - Visibility

    func updateViewportHeight(_ h: CGFloat) {
        if h > 0 { viewportHeight = h }
    }

    func noteScroll(offset: CGFloat) {
        let now = Date()
        let dt = now.timeIntervalSince(lastScrollAt)
        if dt > 0, dt < 0.5, viewportHeight > 0 {
            let screensPerSec = abs(offset - lastScrollOffset) / viewportHeight / max(dt, 0.001)
            // 1 screen / 0.4s ≈ 2.5 screens/s
            let fling = screensPerSec > (1.0 / LotCardSubscribePolicy.flingScreenDuration)
            engine.setFlinging(fling)
            if fling {
                scheduleReconcile(afterMs: 400)
            }
        }
        lastScrollOffset = offset
        lastScrollAt = now
    }

    func updateVisibility(lotId: Int64, ratio: Double) {
        guard active, lotId > 0 else { return }
        engine.updateRatio(lotId: lotId, ratio: ratio)
        scheduleReconcile()
    }

    func cardDidDisappear(lotId: Int64) {
        engine.updateRatio(lotId: lotId, ratio: 0)
        scheduleReconcile()
    }

    func live(for lotId: Int64?) -> LotCardLiveFields? {
        guard let lotId else { return nil }
        return liveByLotId[lotId]
    }

    // MARK: - Internals

    private func scheduleReconcile(afterMs: Int = LotCardSubscribePolicy.debounceMs) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(afterMs))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    private func reconcile() {
        guard active else { return }
        // Clear fling if scroll has settled.
        if engine.isFlinging, Date().timeIntervalSince(lastScrollAt) > LotCardSubscribePolicy.flingScreenDuration {
            engine.setFlinging(false)
        }
        let desired = engine.desiredSubscriptions(preferredOrder: preferredOrder)
        let diff = engine.applyDesired(desired)
        if !diff.unsubscribe.isEmpty {
            WebSocketClient.shared.unsubscribeCards(diff.unsubscribe)
        }
        if !diff.subscribe.isEmpty {
            WebSocketClient.shared.subscribeCards(diff.subscribe)
        }
    }

    private func resubscribeAll() {
        let ids = Array(engine.subscribed)
        guard !ids.isEmpty else {
            scheduleReconcile(afterMs: 50)
            return
        }
        WebSocketClient.shared.subscribeCards(ids)
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(LotCardSubscribePolicy.heartbeatSeconds))
                guard let self, self.active else { return }
                let ids = Array(self.engine.subscribed)
                if !ids.isEmpty, WebSocketClient.shared.connected {
                    WebSocketClient.shared.cardHeartbeat(ids)
                }
            }
        }
    }

    /// Re-check pending 300ms gates even if ratio hasn't changed.
    private func startVisibilityPoll() {
        visibilityPollTask?.cancel()
        visibilityPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, self.active else { return }
                if !self.engine.pendingSince.isEmpty || self.engine.isFlinging {
                    self.scheduleReconcile(afterMs: 0)
                }
            }
        }
    }

    private func handle(_ ev: WSEvent) {
        switch ev.type {
        case LotCardSubscribePolicy.tickEvent:
            guard let tick = LotCardTick.from(event: ev) else { return }
            applyTick(tick)
        case LotCardSubscribePolicy.nackEvent:
            if let lotId = ev.lotId {
                engine.remove(lotId: lotId)
                liveByLotId[lotId] = nil
            }
        default:
            break
        }
    }

    private func applyTick(_ tick: LotCardTick) {
        // Only apply for lots we still hold in the page (or currently subscribed).
        guard liveByLotId[tick.lotId] != nil || engine.subscribed.contains(tick.lotId) else { return }

        if let ms = tick.serverTime, ms > 0 {
            SessionStore.shared.applyServerTimeMs(ms)
        }

        var fields = liveByLotId[tick.lotId] ?? LotCardLiveFields()
        let bumped = fields.apply(tick)
        liveByLotId[tick.lotId] = fields

        var tracker = endTimeChanges
        if bumped {
            _ = tracker.noteVersionChange(lotId: tick.lotId, newVersion: tick.endAtVersion)
        } else if let v = tick.endAtVersion, tracker.knownVersions[tick.lotId] == nil {
            tracker.seed(lotId: tick.lotId, version: v)
        }
        endTimeChanges = tracker

        if fields.isTerminalStatus {
            engine.markStale(lotId: tick.lotId)
            WebSocketClient.shared.unsubscribeCards([tick.lotId])
        }
    }
}

// MARK: - Visibility reporting view modifier

struct LotCardVisibilityModifier: ViewModifier {
    let lotId: Int64?
    let onRatio: (Int64, Double) -> Void
    let onDisappearLot: (Int64) -> Void

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { report(geo) }
                        .onChange(of: geo.frame(in: .global)) { _, _ in report(geo) }
                }
            )
            .onDisappear {
                if let lotId { onDisappearLot(lotId) }
            }
    }

    private func report(_ geo: GeometryProxy) {
        guard let lotId, lotId > 0 else { return }
        let frame = geo.frame(in: .global)
        guard frame.width > 1, frame.height > 1 else {
            onRatio(lotId, 0)
            return
        }
        let screen = UIScreen.main.bounds
        let inter = frame.intersection(screen)
        let area = frame.width * frame.height
        let ratio = area > 0 ? (inter.width * inter.height) / area : 0
        onRatio(lotId, max(0, min(1, ratio)))
    }
}

extension View {
    func reportLotCardVisibility(
        lotId: Int64?,
        onRatio: @escaping (Int64, Double) -> Void,
        onDisappear: @escaping (Int64) -> Void = { _ in }
    ) -> some View {
        modifier(LotCardVisibilityModifier(lotId: lotId, onRatio: onRatio, onDisappearLot: onDisappear))
    }
}

/// Sticky banner for end-time changes / offline realtime pause.
struct ListRealtimeBanner: View {
    let endTimeText: String?
    let offline: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if offline {
                Text(LotCardHeatCopy.offlineBanner)
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.vGold.opacity(0.25))
                    .accessibilityLabel(LotCardHeatCopy.offlineBanner)
            }
            if let endTimeText, !endTimeText.isEmpty {
                Button(action: onRefresh) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                        Text(endTimeText)
                            .font(.vCaptionMedium)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.vPrimary)
                    .padding(.horizontal, VSpace.l)
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.vPrimarySoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(endTimeText)
            }
        }
    }
}
