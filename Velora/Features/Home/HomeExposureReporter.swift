import Foundation
import Combine

/// Client-view impression / click reporting for home slots (DES-v1.3-02 §5.4).
@MainActor
final class HomeExposureReporter: ObservableObject {
    static let shared = HomeExposureReporter()

    private var requestId: String?
    private var pending: [HomeExposureEvent] = []
    private var impressedKeys = Set<String>()
    private var lastClickAt: [String: Date] = [:]
    private var flushTask: Task<Void, Never>?
    private var visibleSince: [String: Date] = [:]

    func bind(requestId: String?) {
        self.requestId = requestId
    }

    /// Call when a slot's visible ratio crosses the threshold (or drops below).
    func updateVisibility(slotId: Int64, listingId: Int64?, visibleRatio: Double) {
        let key = visibilityKey(slotId: slotId, listingId: listingId)
        if visibleRatio >= HomeExposurePolicy.minVisibleRatio {
            if visibleSince[key] == nil {
                visibleSince[key] = Date()
            } else if let start = visibleSince[key] {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                if ms >= HomeExposurePolicy.minVisibleMs {
                    recordImpression(slotId: slotId, listingId: listingId, visibleMs: ms)
                    visibleSince[key] = nil
                }
            }
        } else {
            visibleSince[key] = nil
        }
    }

    /// Convenience for SwiftUI `onAppear` + delayed check (approx ≥50% / ≥1s).
    func trackAppeared(slotId: Int64, listingId: Int64?) {
        let key = visibilityKey(slotId: slotId, listingId: listingId)
        visibleSince[key] = Date()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(HomeExposurePolicy.minVisibleMs))
            guard let self else { return }
            guard self.visibleSince[key] != nil else { return }
            self.recordImpression(slotId: slotId, listingId: listingId, visibleMs: HomeExposurePolicy.minVisibleMs)
            self.visibleSince[key] = nil
        }
    }

    func trackDisappeared(slotId: Int64, listingId: Int64?) {
        visibleSince[visibilityKey(slotId: slotId, listingId: listingId)] = nil
    }

    func trackClick(slotId: Int64, listingId: Int64?) {
        let key = visibilityKey(slotId: slotId, listingId: listingId)
        if let last = lastClickAt[key], Date().timeIntervalSince(last) * 1000 < Double(HomeExposurePolicy.clickDedupeMs) {
            return
        }
        lastClickAt[key] = Date()
        enqueue(HomeExposureEvent(slotId: slotId, listingId: listingId, event: .click, visibleMs: nil))
        Task { await flush(force: true) }
    }

    private func recordImpression(slotId: Int64, listingId: Int64?, visibleMs: Int) {
        let key = "\(slotId)-\(listingId ?? 0)-imp-\(dayKey())"
        guard !impressedKeys.contains(key) else { return }
        impressedKeys.insert(key)
        enqueue(HomeExposureEvent(slotId: slotId, listingId: listingId, event: .impression, visibleMs: visibleMs))
        scheduleFlush()
    }

    private func enqueue(_ event: HomeExposureEvent) {
        pending.append(event)
        if pending.count >= HomeExposurePolicy.maxBatchSize {
            Task { await flush(force: true) }
        }
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.flush(force: false)
        }
    }

    func flush(force: Bool) async {
        guard !pending.isEmpty else { return }
        guard let requestId, !requestId.isEmpty else {
            // Without request_id version correlation fails — drop quietly.
            if force { pending.removeAll() }
            return
        }
        let batch = Array(pending.prefix(HomeExposurePolicy.maxBatchSize))
        pending.removeFirst(min(batch.count, pending.count))
        do {
            try await API.reportHomeExposures(
                requestId: requestId,
                events: batch,
                deviceId: DeviceID.current
            )
        } catch {
            // Prefer under-counting; re-queue only on network failure.
            if (error as? APIError)?.code == "network" {
                pending.insert(contentsOf: batch, at: 0)
            }
        }
    }

    private func visibilityKey(slotId: Int64, listingId: Int64?) -> String {
        "\(slotId)-\(listingId ?? 0)"
    }

    private func dayKey() -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }
}
