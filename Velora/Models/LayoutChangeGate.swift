import CoreGraphics
import Foundation

/// Throttle layout / scroll feedback so GeometryReader updates do not form
/// layout → state → layout loops (iOS 18 continuous scroll drift).
enum LayoutChangeGate {
    static func shouldEmitFrame(
        previous: CGRect?,
        next: CGRect,
        minDelta: CGFloat = 1.5
    ) -> Bool {
        guard let previous else { return true }
        if abs(previous.minX - next.minX) >= minDelta { return true }
        if abs(previous.minY - next.minY) >= minDelta { return true }
        if abs(previous.width - next.width) >= minDelta { return true }
        if abs(previous.height - next.height) >= minDelta { return true }
        return false
    }

    static func shouldEmitScroll(
        previous: CGFloat?,
        next: CGFloat,
        minDelta: CGFloat = 2
    ) -> Bool {
        guard let previous else { return true }
        return abs(previous - next) >= minDelta
    }

    static func shouldEmitRatio(
        previous: Double?,
        next: Double,
        minDelta: Double = 0.03
    ) -> Bool {
        guard let previous else { return true }
        if next <= 0, previous > 0 { return true }
        if next > 0, previous <= 0 { return true }
        return abs(previous - next) >= minDelta
    }
}

enum LotPresentationPolicy {
    static func shouldPresent(newId: Int64, currentId: Int64?) -> Bool {
        guard newId > 0 else { return false }
        return currentId != newId
    }
}

enum SheetChain {
    static func deferOrderUntilListingDismissed(
        orderId: Int64?,
        listingPresented: Bool
    ) -> (dismissListing: Bool, immediateOrderId: Int64?, deferredOrderId: Int64?) {
        guard let orderId, orderId > 0 else {
            return (false, nil, nil)
        }
        if listingPresented {
            return (true, nil, orderId)
        }
        return (false, orderId, nil)
    }

    static func promoteDeferredOrder(_ deferred: Int64?) -> Int64? {
        guard let deferred, deferred > 0 else { return nil }
        return deferred
    }
}

enum PublishDraftPolicy {
    static func isEffectivelyEmpty(
        title: String,
        photoCount: Int,
        description: String = ""
    ) -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && photoCount <= 0
            && description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldPersistCloudDraft(
        title: String,
        photoCount: Int,
        description: String = ""
    ) -> Bool {
        !isEffectivelyEmpty(title: title, photoCount: photoCount, description: description)
    }
}
