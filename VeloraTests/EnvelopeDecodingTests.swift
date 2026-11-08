import XCTest
@testable import Velora

private struct FixtureUser: Decodable, Equatable {
    let id: Int64
    let nickname: String
}

final class EnvelopeDecodingTests: XCTestCase {
    func testDecodeEnvelopeOkFixture() throws {
        let url = try XCTUnwrap(
            Bundle(for: EnvelopeDecodingTests.self).url(forResource: "envelope_ok", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle(for: EnvelopeDecodingTests.self).url(forResource: "envelope_ok", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        let env = try APIClient.decoder.decode(Envelope<FixtureUser>.self, from: data)
        XCTAssertNil(env.error)
        XCTAssertEqual(env.data, FixtureUser(id: 42, nickname: "测试用户"))
    }

    func testDecodeEnvelopeErrorBody() throws {
        let json = """
        {"data":null,"error":{"code":"missing_idempotency_key","message":"写接口必须携带 Idempotency-Key"}}
        """.data(using: .utf8)!
        let env = try APIClient.decoder.decode(Envelope<Empty>.self, from: json)
        XCTAssertNil(env.data)
        XCTAssertEqual(env.error?.code, "missing_idempotency_key")
    }
}
