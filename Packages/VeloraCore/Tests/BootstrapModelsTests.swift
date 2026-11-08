import XCTest
@testable import VeloraCore

final class BootstrapModelsTests: XCTestCase {
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func testNavVersionAcceptsV13String() throws {
        let json = """
        {
          "nav_schema": {
            "version": "v13",
            "tabs": [
              {"key":"buy","title":"购买"}
            ]
          },
          "publish_actions": [],
          "flags": {"nav.v13": true},
          "server_time": "2026-11-05T12:00:00Z"
        }
        """.data(using: .utf8)!
        let boot = try decoder.decode(MeBootstrapDTO.self, from: json)
        XCTAssertEqual(boot.navSchema.version, 13)
        XCTAssertEqual(boot.navSchema.tabs.first?.key, "buy")
        XCTAssertEqual(boot.serverTime, 1_793_880_000_000)
    }

    func testServerTimeStillAcceptsUnixMs() throws {
        let json = """
        {
          "nav": { "version": 1, "tabs": [] },
          "publish_actions": [],
          "flags": {},
          "server_time": 1730740000000
        }
        """.data(using: .utf8)!
        let boot = try decoder.decode(MeBootstrapDTO.self, from: json)
        XCTAssertEqual(boot.navSchema.version, 1)
        XCTAssertEqual(boot.serverTime, 1_730_740_000_000)
    }
}
