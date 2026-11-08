import XCTest
@testable import VeloraCore

final class RestrictionModelsTests: XCTestCase {
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let dt = withFrac.date(from: s) { return dt }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let dt = plain.date(from: s) { return dt }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()

    func testAccountStatusRawValues() {
        XCTAssertEqual(AccountStatus.active.rawValue, "active")
        XCTAssertEqual(AccountStatus.banBid.rawValue, "ban_bid")
        XCTAssertEqual(AccountStatus.banPublish.rawValue, "ban_publish")
        XCTAssertEqual(AccountStatus.rateLimited.rawValue, "rate_limited")
        XCTAssertEqual(AccountStatus.frozen.rawValue, "frozen")
        XCTAssertTrue(AccountStatus.frozen.isRestrictionState)
        XCTAssertFalse(AccountStatus.active.isRestrictionState)
    }

    func testRestrictionItemDecode() throws {
        let json = """
        {"type":"ban_bid","ends_at":"2026-12-01T00:00:00Z","public_reason":"多次拍卖违约"}
        """.data(using: .utf8)!
        let item = try decoder.decode(AccountRestrictionItem.self, from: json)
        XCTAssertEqual(item.type, "ban_bid")
        XCTAssertEqual(item.status, .banBid)
        XCTAssertEqual(item.publicReason, "多次拍卖违约")
        XCTAssertNotNil(item.endsAt)
    }

    func testResolveFlagsUnionBanPublishAndBanBid() {
        let flags = AccountAccessFlags.resolve(
            status: "ban_publish",
            restrictions: [
                AccountRestrictionItem(type: "ban_publish", publicReason: "违规上架"),
                AccountRestrictionItem(type: "ban_bid", endsAt: Date(timeIntervalSince1970: 1_800_000_000), publicReason: "禁竞拍"),
            ]
        )
        XCTAssertEqual(flags.status, .banPublish)
        XCTAssertTrue(flags.isBanPublish)
        XCTAssertTrue(flags.isBanBid)
        XCTAssertFalse(flags.canBid)
        XCTAssertFalse(flags.canPublish)
        XCTAssertFalse(flags.showsDepositEntry)
        XCTAssertEqual(flags.banBidPublicReason, "禁竞拍")
    }

    func testResolveFrozenFromRestrictionRowOverridesActiveColumn() {
        let flags = AccountAccessFlags.resolve(
            status: "active",
            restrictions: [AccountRestrictionItem(type: "frozen", publicReason: "信用过低")]
        )
        XCTAssertTrue(flags.isFrozen)
        XCTAssertFalse(flags.canBid)
        XCTAssertEqual(flags.frozenPublicReason, "信用过低")
    }

    func testBanBidStatusAloneHidesDeposit() {
        let flags = AccountAccessFlags.resolve(status: "ban_bid")
        XCTAssertTrue(flags.isBanBid)
        XCTAssertTrue(flags.canPublish)
        XCTAssertFalse(flags.showsDepositEntry)
    }

    func testRestrictionErrorCodes() {
        XCTAssertEqual(RestrictionErrorCode.bidForbidden.rawValue, "bid_forbidden")
        XCTAssertEqual(RestrictionErrorCode.accountFrozen.rawValue, "account_frozen")
        XCTAssertTrue(RestrictionErrorCode.accountFrozen.clearsLocalSession)
        XCTAssertFalse(RestrictionErrorCode.bidForbidden.clearsLocalSession)
        XCTAssertTrue(RestrictionErrorCode.bidForbidden.fallbackMessage.contains("竞拍"))
    }

    func testAccountGateNoticeCopy() {
        let frozen = AccountGateNotice(kind: .frozen, message: "账号已冻结", publicReason: "运营处理中")
        XCTAssertEqual(frozen.title, "账号已冻结")
        XCTAssertEqual(frozen.detailText, "运营处理中")

        let kick = AccountGateNotice(kind: .sessionRevoked, message: "登录已失效，请重新登录")
        XCTAssertEqual(kick.title, "登录已失效")
        XCTAssertEqual(kick.detailText, "登录已失效，请重新登录")
        XCTAssertEqual(AccountGateNotice.Kind.sessionRevoked.rawValue, AuthErrorCode.sessionRevokedEvent)
    }

    func testMePayloadWithRestrictions() throws {
        let json = """
        {
          "status":"ban_bid",
          "unread":0,
          "user":{"id":1,"nickname":"车迷","avatar":"","credit_score":100,"sold_count":0,"won_count":0,"lot_count":0,"status":"ban_bid"},
          "restrictions":[
            {"type":"ban_bid","ends_at":"2026-12-31T16:00:00Z","public_reason":"禁止竞拍至年底"}
          ]
        }
        """.data(using: .utf8)!
        struct MeShape: Decodable {
            let status: String?
            let restrictions: [AccountRestrictionItem]?
            let unread: Int
        }
        let me = try decoder.decode(MeShape.self, from: json)
        let flags = AccountAccessFlags.resolve(status: me.status, restrictions: me.restrictions ?? [])
        XCTAssertTrue(flags.isBanBid)
        XCTAssertEqual(flags.banBidPublicReason, "禁止竞拍至年底")
        XCTAssertEqual(me.unread, 0)
    }
}
