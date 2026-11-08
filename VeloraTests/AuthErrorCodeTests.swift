import XCTest
@testable import Velora

/// Thin app-target checks for auth error codes (heavier DTO coverage lives in VeloraCore `swift test`).
final class AuthErrorCodeTests: XCTestCase {
    func testInviteRequiredAndSessionRevokedConstants() {
        XCTAssertEqual(AuthErrorCode.inviteRequired.rawValue, "invite_required")
        XCTAssertEqual(AuthErrorCode.sessionRevokedEvent, "session_revoked")
        XCTAssertTrue(AuthErrorCode.unauthorized.clearsLocalSession)
        XCTAssertFalse(AuthErrorCode.inviteRequired.clearsLocalSession)
    }

    func testInviteRequiredEnvelopeViaAppDecoder() throws {
        let json = """
        {"data":null,"error":{"code":"invite_required","message":"新用户需填写邀请码"}}
        """.data(using: .utf8)!
        let env = try APIClient.decoder.decode(Envelope<Empty>.self, from: json)
        XCTAssertEqual(env.error?.code, AuthErrorCode.inviteRequired.rawValue)
        let apiErr = APIError(code: env.error!.code, message: env.error!.message, status: 400)
        XCTAssertEqual(apiErr.authCode, .inviteRequired)
    }

    func testSendSmsResultCooldown() throws {
        let json = #"{"retry_after":45,"sent":true}"#.data(using: .utf8)!
        let resp = try APIClient.decoder.decode(SendSmsResult.self, from: json)
        XCTAssertEqual(resp.cooldownSeconds, 45)
    }
}
