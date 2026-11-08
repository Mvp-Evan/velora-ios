import XCTest
@testable import Velora

final class AppConfigTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppConfig.brandingPaddock43 = true
    }

    override func tearDown() {
        AppConfig.infoBundle = .main
        AppConfig.brandingPaddock43 = true
        super.tearDown()
    }

    func testLoadsAPIBaseURLFromInfoPlist() {
        AppConfig.infoBundle = Bundle(for: AppConfigTests.self)
        XCTAssertEqual(AppConfig.baseURL.absoluteString, "https://unit-test.api.velora")
        XCTAssertEqual(AppConfig.apiURL.absoluteString, "https://unit-test.api.velora/api/v1")
    }

    func testLoadsWSBaseURLFromInfoPlist() {
        AppConfig.infoBundle = Bundle(for: AppConfigTests.self)
        XCTAssertEqual(AppConfig.wsURL.absoluteString, "wss://unit-test.api.velora/ws")
    }

    func testBrandDisplayNameUsesGuguHubWhenFlagOn() {
        AppConfig.brandingPaddock43 = true
        XCTAssertEqual(AppConfig.brandDisplayName, "毂毂")
    }

    func testBrandDisplayNameUsesGuguEnglishWhenFlagOff() {
        AppConfig.brandingPaddock43 = false
        XCTAssertEqual(AppConfig.brandDisplayName, "gugu")
    }
}
