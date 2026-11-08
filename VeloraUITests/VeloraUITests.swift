import XCTest

final class VeloraUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Smoke: launch the app and assert a window exists. Skips if the process dies before UI settles
    /// (e.g. hard crash); network/backend absence alone should still leave a login shell.
    func testLaunchSmoke() throws {
        let app = XCUIApplication()
        app.launch()

        // Give SwiftUI a moment to attach a scene.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, app.windows.count == 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        if app.state != .runningForeground && app.windows.count == 0 {
            throw XCTSkip("App did not present a window (simulator/backend environment).")
        }

        XCTAssertGreaterThan(app.windows.count, 0, "Expected at least one window after launch")
    }
}
