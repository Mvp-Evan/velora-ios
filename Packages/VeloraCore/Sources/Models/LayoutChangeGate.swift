import CoreGraphics
import Foundation

/// Throttle layout / scroll feedback so GeometryReader updates do not form
/// layout → state → layout loops (iOS 18 continuous scroll drift).
public enum LayoutChangeGate {
    /// Whether a new geometry frame should emit visibility work.
    public static func shouldEmitFrame(
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

    /// Whether a scroll offset change is large enough to note.
    public static func shouldEmitScroll(
        previous: CGFloat?,
        next: CGFloat,
        minDelta: CGFloat = 2
    ) -> Bool {
        guard let previous else { return true }
        return abs(previous - next) >= minDelta
    }

    /// Whether a visibility ratio change should update the engine.
    public static func shouldEmitRatio(
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

/// Decide whether opening a lot should present a new sheet or reuse the current one.
public enum LotPresentationPolicy {
    /// Returns true when a new sheet presentation is needed.
    public static func shouldPresent(newId: Int64, currentId: Int64?) -> Bool {
        guard newId > 0 else { return false }
        return currentId != newId
    }
}

/// Chain listing → order sheets so the order appears after the listing dismisses.
public enum SheetChain {
    /// When accepting an offer while a listing sheet is open, defer the order until dismiss.
    public static func deferOrderUntilListingDismissed(
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

    /// After listing sheet dismiss, promote deferred order if any.
    public static func promoteDeferredOrder(_ deferred: Int64?) -> Int64? {
        guard let deferred, deferred > 0 else { return nil }
        return deferred
    }
}

/// Publish draft persistence guards (empty drafts must not be saved to cloud).
public enum PublishDraftPolicy {
    public static func isEffectivelyEmpty(
        title: String,
        photoCount: Int,
        description: String = ""
    ) -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && photoCount <= 0
            && description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func shouldPersistCloudDraft(
        title: String,
        photoCount: Int,
        description: String = ""
    ) -> Bool {
        !isEffectivelyEmpty(title: title, photoCount: photoCount, description: description)
    }
}
