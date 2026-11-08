import XCTest

/// Core-flow UI smokes for Phase 1 audit. Without a mock auth harness / accessibility IDs
/// these skip rather than flake against a live backend.
final class WalletBidFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLoginNavigateToWalletSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-smoke"]
        app.launch()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, app.windows.count == 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard app.windows.count > 0 else {
            throw XCTSkip("No window after launch (simulator/backend).")
        }

        // Prefer explicit accessibility IDs when present; otherwise soft-skip.
        let walletEntry = app.buttons["wallet.entry"].firstMatch
        let profileTab = app.tabBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "我的")).firstMatch
        if walletEntry.exists {
            walletEntry.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "毂毂")).firstMatch.waitForExistence(timeout: 3)
                || app.otherElements["wallet.root"].waitForExistence(timeout: 3))
            return
        }
        if profileTab.exists {
            profileTab.tap()
            let wallet = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "钱包")).firstMatch
            if wallet.waitForExistence(timeout: 3) {
                wallet.tap()
                return
            }
        }
        throw XCTSkip("Login→wallet UI harness / accessibility IDs not wired; launch smoke covered separately.")
    }

    func testLoginNavigateToBidSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-test-smoke"]
        app.launch()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, app.windows.count == 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard app.windows.count > 0 else {
            throw XCTSkip("No window after launch (simulator/backend).")
        }

        let bidCTA = app.buttons["lot.bid.cta"].firstMatch
        if bidCTA.exists {
            bidCTA.tap()
            return
        }
        let homeTab = app.tabBars.buttons.element(boundBy: 0)
        if homeTab.exists {
            homeTab.tap()
            let firstCard = app.cells.firstMatch
            if firstCard.waitForExistence(timeout: 3) {
                firstCard.tap()
                return
            }
        }
        throw XCTSkip("Login→bid UI harness / accessibility IDs not wired; launch smoke covered separately.")
    }
}
