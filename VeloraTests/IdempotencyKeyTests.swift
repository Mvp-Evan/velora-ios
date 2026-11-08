import XCTest
@testable import Velora

final class IdempotencyKeyTests: XCTestCase {
    func testIdempotencyKeyLooksLikeUUID() {
        let key = APIClient.shared.idempotencyKey()
        XCTAssertNotNil(UUID(uuidString: key), "expected UUID string, got \(key)")
    }

    func testIdempotencyKeysAreUnique() {
        let a = APIClient.shared.idempotencyKey()
        let b = APIClient.shared.idempotencyKey()
        XCTAssertNotEqual(a, b)
    }
}
