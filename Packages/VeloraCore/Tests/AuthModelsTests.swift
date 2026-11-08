import XCTest
@testable import VeloraCore

final class AuthModelsTests: XCTestCase {
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

    func testInviteRequiredErrorCode() throws {
        let json = """
        {"data":null,"error":{"code":"invite_required","message":"新用户需填写邀请码"}}
        """.data(using: .utf8)!
        let env = try decoder.decode(Envelope<Empty>.self, from: json)
        XCTAssertEqual(env.error?.code, AuthErrorCode.inviteRequired.rawValue)
        XCTAssertEqual(AuthErrorCode(rawValue: env.error!.code), .inviteRequired)
        XCTAssertFalse(AuthErrorCode.inviteRequired.clearsLocalSession)
    }

    func testSessionRevokedIsWSEventConstant() {
        XCTAssertEqual(AuthErrorCode.sessionRevokedEvent, "session_revoked")
        XCTAssertTrue(AuthErrorCode.unauthorized.clearsLocalSession)
        XCTAssertTrue(AuthErrorCode.accountFrozen.clearsLocalSession)
    }

    func testUnauthorizedEnvelopeClearsSessionSemantics() throws {
        let json = """
        {"data":null,"error":{"code":"unauthorized","message":"刷新令牌无效"}}
        """.data(using: .utf8)!
        let env = try decoder.decode(Envelope<Empty>.self, from: json)
        let code = AuthErrorCode(rawValue: env.error!.code)
        XCTAssertEqual(code, .unauthorized)
        XCTAssertTrue(code!.clearsLocalSession)
    }

    func testSendSmsResponseRetryAfter() throws {
        let json = #"{"retry_after":60,"sent":true}"#.data(using: .utf8)!
        let resp = try decoder.decode(SendSmsResponse.self, from: json)
        XCTAssertEqual(resp.retryAfter, 60)
        XCTAssertEqual(resp.cooldownSeconds, 60)
        XCTAssertNil(resp.devCode)
    }

    func testSendSmsResponseDefaultCooldownWhenMissing() throws {
        let json = #"{"sent":true}"#.data(using: .utf8)!
        let resp = try decoder.decode(SendSmsResponse.self, from: json)
        XCTAssertEqual(resp.cooldownSeconds, 60)
    }

    func testLoginTokenPairWithDeletionHint() throws {
        let json = """
        {
          "access_token":"a",
          "refresh_token":"r",
          "expires_at":"2026-11-04T12:00:00Z",
          "user":{"id":1,"nickname":"车迷","status":"pending_deletion","real_name_status":"none"},
          "is_new":false,
          "deletion":{"status":"pending_deletion","execute_at":"2026-11-19T12:00:00Z"}
        }
        """.data(using: .utf8)!
        let pair = try decoder.decode(AuthTokenPair.self, from: json)
        XCTAssertEqual(pair.accessToken, "a")
        XCTAssertEqual(pair.user?.status, "pending_deletion")
        XCTAssertTrue(pair.user?.isPendingDeletion == true)
        XCTAssertTrue(pair.deletion?.isPendingDeletion == true)
        XCTAssertEqual(pair.isNew, false)
    }

    func testRefreshTokenPairOmitsIsNew() throws {
        let json = """
        {"access_token":"a2","refresh_token":"r2","user":{"id":1,"nickname":"车迷"}}
        """.data(using: .utf8)!
        let pair = try decoder.decode(AuthTokenPair.self, from: json)
        XCTAssertEqual(pair.isNew, false)
        XCTAssertNil(pair.deletion)
    }

    func testSessionsListArrayAndWrapped() throws {
        let arr = """
        [{"id":"10","device_name":"iPhone","ip_masked":"1.2.*.*","current":true}]
        """.data(using: .utf8)!
        let fromArr = try decoder.decode(SessionsListResponse.self, from: arr)
        XCTAssertEqual(fromArr.items.count, 1)
        XCTAssertTrue(fromArr.items[0].current)

        let wrapped = """
        {"items":[{"id":11,"device_name":"iPad","ip_masked":"9.9.*.*","current":false}]}
        """.data(using: .utf8)!
        let fromWrapped = try decoder.decode(SessionsListResponse.self, from: wrapped)
        XCTAssertEqual(fromWrapped.items.first?.id, "11")
    }

    func testDeletionBlockedWithBlockers() throws {
        let errJSON = """
        {"data":null,"error":{"code":"deletion_blocked","message":"存在未完结订单"}}
        """.data(using: .utf8)!
        let env = try decoder.decode(Envelope<Empty>.self, from: errJSON)
        XCTAssertEqual(env.error?.code, AuthErrorCode.deletionBlocked.rawValue)

        let statusJSON = """
        {
          "status":"none",
          "blockers":[
            {"code":"open_order","message":"未完结订单 #1001","ref":"1001"}
          ]
        }
        """.data(using: .utf8)!
        let status = try decoder.decode(DeletionStatusResponse.self, from: statusJSON)
        XCTAssertFalse(status.isPending)
        XCTAssertEqual(status.blockers.count, 1)
        XCTAssertEqual(status.coolOffDaysHint, 15)
    }

    func testDeletionPendingStatus() throws {
        let json = """
        {"status":"pending_deletion","execute_at":"2026-11-19T00:00:00Z","blockers":[]}
        """.data(using: .utf8)!
        let status = try decoder.decode(DeletionStatusResponse.self, from: json)
        XCTAssertTrue(status.isPending)
        XCTAssertNotNil(status.executeAt)
    }

    func testLoginRequestEncodeInviteOptional() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let withInvite = LoginRequestBody(phone: "13800000001", code: "123456", inviteCode: "ABCD", deviceId: "dev-1")
        let data = try encoder.encode(withInvite)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["invite_code"] as? String, "ABCD")
        XCTAssertEqual(obj["device_id"] as? String, "dev-1")
    }
}
