import XCTest
@testable import Velora

final class IdempotencyKeyHTTPTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testPostIncludesIdempotencyKeyHeader() async throws {
        StubURLProtocol.handler = { request in
            let key = request.value(forHTTPHeaderField: "Idempotency-Key")
            XCTAssertNotNil(key)
            XCTAssertNotNil(UUID(uuidString: key ?? ""))
            let body = """
            {"data":null,"error":null}
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, body)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = APIClient(session: session)

        let _: Empty = try await client.request(.POST, "ping", auth: false)
        XCTAssertEqual(StubURLProtocol.lastMethod, "POST")
    }

    func testGetDoesNotIncludeIdempotencyKeyHeader() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
            let body = """
            {"data":{"items":[],"page":1,"page_size":20,"total":0,"has_more":false},"error":null}
            """.data(using: .utf8)!
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = APIClient(session: session)

        let _: Page<Empty> = try await client.request(.GET, "listings", auth: false)
        XCTAssertEqual(StubURLProtocol.lastMethod, "GET")
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    static private(set) var lastMethod: String?

    static func reset() {
        handler = nil
        lastMethod = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        Self.lastMethod = request.httpMethod
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
