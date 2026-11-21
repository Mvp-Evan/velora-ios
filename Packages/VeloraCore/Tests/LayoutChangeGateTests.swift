import XCTest
@testable import VeloraCore

final class LayoutChangeGateTests: XCTestCase {
    func testShouldEmitFrameIgnoresSubPixelNoise() {
        let a = CGRect(x: 0, y: 100, width: 390, height: 200)
        let b = CGRect(x: 0, y: 100.5, width: 390, height: 200)
        XCTAssertFalse(LayoutChangeGate.shouldEmitFrame(previous: a, next: b, minDelta: 1.5))
        let c = CGRect(x: 0, y: 104, width: 390, height: 200)
        XCTAssertTrue(LayoutChangeGate.shouldEmitFrame(previous: a, next: c, minDelta: 1.5))
        XCTAssertTrue(LayoutChangeGate.shouldEmitFrame(previous: nil, next: a))
    }

    func testShouldEmitScrollRequiresDelta() {
        XCTAssertTrue(LayoutChangeGate.shouldEmitScroll(previous: nil, next: -10))
        XCTAssertFalse(LayoutChangeGate.shouldEmitScroll(previous: -10, next: -11, minDelta: 2))
        XCTAssertTrue(LayoutChangeGate.shouldEmitScroll(previous: -10, next: -14, minDelta: 2))
    }

    func testShouldEmitRatioEdges() {
        XCTAssertTrue(LayoutChangeGate.shouldEmitRatio(previous: 0.5, next: 0))
        XCTAssertTrue(LayoutChangeGate.shouldEmitRatio(previous: 0, next: 0.2))
        XCTAssertFalse(LayoutChangeGate.shouldEmitRatio(previous: 0.5, next: 0.51, minDelta: 0.03))
    }

    func testLotPresentationPolicy() {
        XCTAssertTrue(LotPresentationPolicy.shouldPresent(newId: 9, currentId: nil))
        XCTAssertFalse(LotPresentationPolicy.shouldPresent(newId: 9, currentId: 9))
        XCTAssertTrue(LotPresentationPolicy.shouldPresent(newId: 10, currentId: 9))
        XCTAssertFalse(LotPresentationPolicy.shouldPresent(newId: 0, currentId: nil))
    }

    func testSheetChainDeferral() {
        let deferred = SheetChain.deferOrderUntilListingDismissed(orderId: 42, listingPresented: true)
        XCTAssertTrue(deferred.dismissListing)
        XCTAssertNil(deferred.immediateOrderId)
        XCTAssertEqual(deferred.deferredOrderId, 42)

        let immediate = SheetChain.deferOrderUntilListingDismissed(orderId: 42, listingPresented: false)
        XCTAssertFalse(immediate.dismissListing)
        XCTAssertEqual(immediate.immediateOrderId, 42)
        XCTAssertNil(immediate.deferredOrderId)

        XCTAssertEqual(SheetChain.promoteDeferredOrder(42), 42)
        XCTAssertNil(SheetChain.promoteDeferredOrder(nil))
    }

    func testPublishDraftPolicy() {
        XCTAssertTrue(PublishDraftPolicy.isEffectivelyEmpty(title: "  ", photoCount: 0))
        XCTAssertFalse(PublishDraftPolicy.shouldPersistCloudDraft(title: "", photoCount: 0))
        XCTAssertTrue(PublishDraftPolicy.shouldPersistCloudDraft(title: "车模", photoCount: 0))
        XCTAssertTrue(PublishDraftPolicy.shouldPersistCloudDraft(title: "", photoCount: 2))
    }
}
