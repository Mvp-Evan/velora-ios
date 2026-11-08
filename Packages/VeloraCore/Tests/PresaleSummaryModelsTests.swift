import XCTest
@testable import VeloraCore

final class PresaleSummaryModelsTests: XCTestCase {
    func testConfigDefaultsMatchDesign() {
        XCTAssertEqual(PresaleSummaryConfigDefaults.meEntryKey, "presale_orders")
        XCTAssertEqual(PresaleSummaryConfigDefaults.meEntryTitle, "预定单")
        XCTAssertEqual(PresaleSummaryConfigDefaults.meEntryIcon, "list.clipboard")
        XCTAssertEqual(PresaleSummaryConfigDefaults.merchantPresalePath, "/releases/presale")
        XCTAssertEqual(PresaleSummaryConfigDefaults.defaultMerchantWebBaseURL, "http://localhost:5173")
        XCTAssertEqual(PresaleSummaryConfigDefaults.formulaVersion, "recv_minus_refund_v1")
        XCTAssertEqual(PresaleSummaryConfigDefaults.exportTTLHours, 24)
        XCTAssertEqual(PresaleSummaryConfigDefaults.exportRowLimit, 100_000)
        XCTAssertEqual(PresaleSummaryConfigDefaults.listCompareMaxRows, 20_000)
        XCTAssertEqual(PresaleSummaryConfigDefaults.listCompareMaxBytes, 10 * 1024 * 1024)
        XCTAssertEqual(PresaleSummaryConfigDefaults.launchGateKey, "launch_gate.presale")
    }

    func testMerchantDeepLinkCopy() {
        XCTAssertEqual(PresaleSummaryCopy.useMerchantWeb, "预定单管理请在商家后台")
        XCTAssertEqual(PresaleSummaryCopy.openMerchantWeb, "打开商家后台")
        XCTAssertEqual(PresaleSummaryCopy.pageTitle, "预定单管理")
        XCTAssertFalse(PresaleSummaryCopy.hint.isEmpty)
        XCTAssertEqual(PresaleSummaryCopy.unpaidBalanceExpected, "待补款导致的差额为预期差异")
    }

    func testMerchantPresaleURL() {
        let url = PresaleSummaryLogic.merchantPresaleURL()
        XCTAssertEqual(url?.absoluteString, "http://localhost:5173/releases/presale")

        let custom = PresaleSummaryLogic.merchantPresaleURL(
            baseURLString: "https://merchant.example.com/",
            path: "/releases/presale"
        )
        XCTAssertEqual(custom?.absoluteString, "https://merchant.example.com/releases/presale")

        XCTAssertNil(PresaleSummaryLogic.merchantPresaleURL(baseURLString: "   "))
    }

    func testShowsMeEntryOnlyBrandCanPresale() {
        XCTAssertTrue(PresaleSummaryLogic.showsMeEntry(sellerType: "brand", canPresale: true))
        XCTAssertFalse(PresaleSummaryLogic.showsMeEntry(sellerType: "brand", canPresale: false))
        XCTAssertFalse(PresaleSummaryLogic.showsMeEntry(sellerType: "proxy_agent", canPresale: true))
        XCTAssertFalse(PresaleSummaryLogic.showsMeEntry(sellerType: "personal", canPresale: true))
        XCTAssertFalse(PresaleSummaryLogic.showsMeEntry(sellerType: nil, canPresale: true))
    }

    func testEmptyStubExists() {
        XCTAssertEqual(PresaleSummaryAppStub(), PresaleSummaryAppStub())
    }
}
