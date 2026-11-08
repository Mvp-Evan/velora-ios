import XCTest
@testable import VeloraCore

final class TrustModelsTests: XCTestCase {
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

    func testRealNameChannelRawValues() {
        XCTAssertEqual(RealNameChannel.alipay.rawValue, "alipay")
        XCTAssertEqual(RealNameChannel.wechat.rawValue, "wechat")
        XCTAssertEqual(RealNameChannel.nationalNid.rawValue, "national_nid")
        XCTAssertEqual(RealNameChannel.allCases.count, 3)
    }

    func testRealNameSessionCreateEncode() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = RealNameSessionCreateRequest(channel: .nationalNid)
        let data = try encoder.encode(body)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["channel"] as? String, "national_nid")
    }

    func testRealNameSessionJumpDecode() throws {
        let json = """
        {
          "session_id":"sess-1",
          "status":"pending_jump",
          "channel":"alipay",
          "jump":{"url":"alipays://platformapi/startapp","app_store_url":"https://apps.apple.com/app/alipay"}
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(RealNameSessionResponse.self, from: json)
        XCTAssertEqual(resp.sessionId, "sess-1")
        XCTAssertEqual(resp.statusValue, .pendingJump)
        XCTAssertEqual(resp.jump?.openURL?.scheme, "alipays")
        XCTAssertNotNil(resp.jump?.installURL)
        XCTAssertFalse(resp.isAlreadyVerified)
    }

    func testRealNameAlreadyVerifiedShortCircuit() throws {
        let json = #"{"status":"verified","name_masked":"张*","id_no_masked":"**************1234"}"#.data(using: .utf8)!
        let resp = try decoder.decode(RealNameSessionResponse.self, from: json)
        XCTAssertTrue(resp.isAlreadyVerified)
        XCTAssertEqual(resp.nameMasked, "张*")
    }

    func testRealNameStatusWithNestedMasked() throws {
        let json = """
        {
          "status":"failed",
          "channel":"wechat",
          "fail_reason":"user_cancelled",
          "masked":{"name":"李*","id_no":"**************5678"}
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(RealNameStatusResponse.self, from: json)
        XCTAssertEqual(resp.statusValue, .failed)
        XCTAssertEqual(resp.failCode, .userCancelled)
        XCTAssertEqual(resp.nameMasked, "李*")
        XCTAssertEqual(resp.idNoMasked, "**************5678")
    }

    func testTrustErrorFallbackCopy() {
        XCTAssertTrue(TrustErrorCode.idNoTaken.fallbackMessage.contains("客服"))
        XCTAssertTrue(TrustErrorCode.vendorUnavailable.fallbackMessage.contains("支付宝"))
        XCTAssertEqual(TrustErrorCode(rawValue: "kyc_daily_limit"), .kycDailyLimit)
    }

    func testSellerOnboardingStepsOrderAndCurrent() throws {
        let json = """
        {
          "onboarding_status":"in_progress",
          "seller_type":null,
          "steps":[
            {"step":"real_name","status":"done"},
            {"step":"protocol","status":"pending"},
            {"step":"deposit","status":"pending"},
            {"step":"sub_merchant","status":"pending"}
          ],
          "protocol":{"protocol_code":"seller_service","protocol_version":"2026.1","content_hash":"abc"}
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(SellerOnboardingResponse.self, from: json)
        XCTAssertEqual(resp.steps.count, 4)
        XCTAssertEqual(resp.currentStepKey, .protocolStep)
        XCTAssertEqual(resp.protocolCode, "seller_service")
        XCTAssertEqual(resp.protocolVersion, "2026.1")
        XCTAssertFalse(resp.isFinished)
        XCTAssertTrue(resp.step(.realName)?.statusValue.isComplete == true)
    }

    func testSellerOnboardingFinished() throws {
        let json = """
        {
          "onboarding_status":"finished",
          "seller_type":"personal",
          "steps":[
            {"step":"real_name","status":"done"},
            {"step":"protocol","status":"done"},
            {"step":"deposit","status":"done"},
            {"step":"sub_merchant","status":"done"}
          ]
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(SellerOnboardingResponse.self, from: json)
        XCTAssertTrue(resp.isFinished)
        XCTAssertNil(resp.currentStepKey)
        XCTAssertEqual(resp.sellerType, "personal")
    }

    func testSellerActionSignEncode() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = SellerActionRequest.sign(protocolCode: "seller_service", protocolVersion: "1", scrollEnd: true)
        let data = try encoder.encode(body)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["action"] as? String, "sign")
        XCTAssertEqual(obj["protocol_code"] as? String, "seller_service")
        XCTAssertEqual(obj["scroll_end"] as? Bool, true)
    }

    func testSellerDepositPending() throws {
        let json = #"{"deposit_id":"d1","status":"pending","amount_fen":50000}"#.data(using: .utf8)!
        let resp = try decoder.decode(SellerDepositResponse.self, from: json)
        XCTAssertTrue(resp.isPending)
        XCTAssertFalse(resp.isFrozen)
        XCTAssertEqual(resp.amountFen, 50000)
    }

    func testMerchantApplicationDualProgress() throws {
        let json = """
        {
          "id":9,
          "apply_type":"proxy_agent",
          "review_status":"approved",
          "sub_merchant_status":"to_sign",
          "onboarding_status":"applying",
          "sign_url":"https://pay.example/sign"
        }
        """.data(using: .utf8)!
        let resp = try decoder.decode(MerchantApplicationResponse.self, from: json)
        XCTAssertEqual(resp.reviewLabel, "已通过")
        XCTAssertEqual(resp.subMerchantLabel, "处理中")
        XCTAssertFalse(resp.isFinished)
        XCTAssertEqual(resp.signUrl, "https://pay.example/sign")
    }

    func testKYCReturnDeepLinkAppScheme() {
        let url = URL(string: "paddock43://kyc/return?session_id=s1&code=c1&channel=alipay")!
        let payload = KYCReturnPayload.parse(url: url)
        XCTAssertEqual(payload?.sessionId, "s1")
        XCTAssertEqual(payload?.code, "c1")
        XCTAssertEqual(payload?.channel, "alipay")
    }

    func testKYCReturnUniversalLinkWithChannelPath() {
        let url = URL(string: "https://api.example.com/kyc/return/wechat?session_id=abc&code=xyz")!
        let payload = KYCReturnPayload.parse(url: url)
        XCTAssertEqual(payload?.sessionId, "abc")
        XCTAssertEqual(payload?.code, "xyz")
        XCTAssertEqual(payload?.channel, "wechat")
    }

    func testKYCReturnRejectsUnrelatedURL() {
        XCTAssertNil(KYCReturnPayload.parse(url: URL(string: "https://example.com/other")!))
        XCTAssertNil(KYCReturnPayload.parse(url: URL(string: "paddock43://kyc/return")!))
    }

    func testMerchantCreateRequestEncode() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = MerchantApplicationCreateRequest(inviteCode: " AB12 ", applyType: "brand", docs: ["doc1"])
        let data = try encoder.encode(body)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["invite_code"] as? String, " AB12 ")
        XCTAssertEqual(obj["apply_type"] as? String, "brand")
    }
}
