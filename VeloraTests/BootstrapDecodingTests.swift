import XCTest
@testable import Velora

final class BootstrapDecodingTests: XCTestCase {
    func testDecodeBootstrapFixture() throws {
        let url = try XCTUnwrap(
            Bundle(for: BootstrapDecodingTests.self).url(forResource: "bootstrap", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle(for: BootstrapDecodingTests.self).url(forResource: "bootstrap", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        let env = try APIClient.decoder.decode(Envelope<MeBootstrap>.self, from: data)

        XCTAssertNil(env.error)
        let boot = try XCTUnwrap(env.data)

        XCTAssertEqual(boot.navSchema.version, 1)
        XCTAssertEqual(boot.navSchema.tabs.map(\.key), ["buy", "community", "publish", "inbox", "me"])
        XCTAssertEqual(boot.navSchema.tabs[0].title, "购买")
        XCTAssertEqual(boot.navSchema.meBuyerEntries.count, 9)
        XCTAssertEqual(boot.navSchema.meSellerEntries.first?.key, "on_sale")

        XCTAssertEqual(boot.publishActions.count, 4)
        XCTAssertEqual(boot.publishActions.map(\.key), ["fixed", "auction", "post", "release"])
        XCTAssertEqual(boot.publishActions.first(where: { $0.key == "post" })?.enabled, false)
        XCTAssertEqual(boot.publishActions.first(where: { $0.key == "auction" })?.requiresCapability, "can_auction")

        XCTAssertEqual(boot.me?.creditScore, 100)
        XCTAssertEqual(boot.me?.realNameStatus, "verified")
        XCTAssertEqual(boot.me?.sellerType, "personal")

        let seller = try XCTUnwrap(boot.seller)
        XCTAssertEqual(seller.sellerType, "personal")
        XCTAssertTrue(seller.capabilities.canFixed)
        XCTAssertTrue(seller.capabilities.canAuction)
        XCTAssertFalse(seller.capabilities.canBatchList)
        XCTAssertTrue(seller.capabilities.allows("can_auction"))
        XCTAssertFalse(seller.capabilities.allows("can_vip"))

        XCTAssertEqual(boot.flags["nav.v13"], true)
        XCTAssertEqual(boot.flags["community.feed"], false)
        XCTAssertEqual(boot.serverTime, 1_730_740_000_000)
        XCTAssertEqual(boot.creditScore, 100)
    }

    func testDecodeNavAliasField() throws {
        let json = """
        {
          "nav": {
            "version": 2,
            "tabs": [
              {"key":"home","title":"首页"},
              {"key":"auctions","title":"拍场"},
              {"key":"publish","title":"发布"},
              {"key":"messages","title":"消息"},
              {"key":"me","title":"我的"}
            ]
          },
          "publish_actions": [],
          "flags": {},
          "server_time": 1
        }
        """.data(using: .utf8)!
        let boot = try APIClient.decoder.decode(MeBootstrap.self, from: json)
        XCTAssertEqual(boot.navSchema.version, 2)
        XCTAssertEqual(boot.navSchema.tabs.map(\.key), ["home", "auctions", "publish", "messages", "me"])
    }

    func testDecodeNavVersionStringAndISOServerTime() throws {
        let url = try XCTUnwrap(
            Bundle(for: BootstrapDecodingTests.self).url(forResource: "bootstrap_v13_iso", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle(for: BootstrapDecodingTests.self).url(forResource: "bootstrap_v13_iso", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        let env = try APIClient.decoder.decode(Envelope<MeBootstrap>.self, from: data)
        let boot = try XCTUnwrap(env.data)

        XCTAssertEqual(boot.navSchema.version, 13)
        XCTAssertEqual(boot.serverTime, 1_793_880_000_000)

        let inline = """
        {
          "nav_schema": { "version": "v13", "tabs": [] },
          "publish_actions": [],
          "flags": {},
          "server_time": "2026-11-05T12:00:00Z"
        }
        """.data(using: .utf8)!
        let inlineBoot = try APIClient.decoder.decode(MeBootstrap.self, from: inline)
        XCTAssertEqual(inlineBoot.navSchema.version, 13)
        XCTAssertEqual(inlineBoot.serverTime, 1_793_880_000_000)
    }

    func testTabKeyMappingNewSchema() {
        let keys = ["buy", "community", "publish", "inbox", "me"]
        let tabs = keys.compactMap(AppTab.from(navKey:))
        XCTAssertEqual(tabs, [.buy, .community, .publish, .inbox, .me])
    }

    func testTabKeyMappingLegacyAndAliases() {
        XCTAssertEqual(AppTab.from(navKey: "home"), .home)
        XCTAssertEqual(AppTab.from(navKey: "auctions"), .auctions)
        XCTAssertEqual(AppTab.from(navKey: "messages"), .inbox)
        XCTAssertEqual(AppTab.from(navKey: "inbox"), .inbox)
        XCTAssertNil(AppTab.from(navKey: "unknown_tab"))
    }

    func testResolvedTabsSkipsUnknownKeys() {
        let schema = NavSchema(
            version: 1,
            tabs: [
                NavTab(key: "buy", title: "购买"),
                NavTab(key: "future_tab", title: "未来"),
                NavTab(key: "me", title: "我的"),
            ]
        )
        XCTAssertEqual(schema.resolvedTabs.map(\.tab), [.buy, .me])
    }

    func testLegacyFallbackFiveTabs() {
        let resolved = NavSchema.legacyFallback.resolvedTabs.map(\.tab)
        XCTAssertEqual(resolved, [.home, .auctions, .publish, .inbox, .me])
    }

    @MainActor
    func testAppRouterAppliesBootstrapTabs() {
        let router = AppRouter()
        XCTAssertEqual(router.visibleTabs.map(\.tab), [.home, .auctions, .publish, .inbox, .me])

        let boot = MeBootstrap(
            navSchema: .v13Default,
            publishActions: [
                PublishAction(key: "auction", title: "拍卖", enabled: true),
                PublishAction(key: "fixed", title: "直购", enabled: true),
            ],
            me: BootstrapMe(creditScore: 88),
            seller: nil,
            flags: ["nav.v13": true],
            serverTime: 100
        )
        router.applyBootstrap(boot)
        XCTAssertEqual(router.visibleTabs.map(\.tab), [.buy, .community, .publish, .inbox, .me])
        XCTAssertEqual(router.publishActions.map(\.key), ["auction", "fixed"])
        XCTAssertEqual(router.primaryBrowseTab, .buy)
    }

    @MainActor
    func testAppRouterFallsBackWhenBootstrapNil() {
        let router = AppRouter()
        router.applyBootstrap(nil)
        XCTAssertEqual(router.visibleTabs.map(\.tab), [.home, .auctions, .publish, .inbox, .me])
        XCTAssertEqual(router.primaryBrowseTab, .home)
    }
}
