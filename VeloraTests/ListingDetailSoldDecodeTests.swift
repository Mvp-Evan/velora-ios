import XCTest
@testable import Velora

final class ListingDetailSoldDecodeTests: XCTestCase {
    func testDecodeSoldListing91Fixture() throws {
        let url = Bundle(for: ListingDetailSoldDecodeTests.self)
            .url(forResource: "listing91_sold", withExtension: "json")
            ?? URL(fileURLWithPath: "/tmp/listing91.json")
        let data = try Data(contentsOf: url)
        do {
            let detail = try APIClient.decoder.decode(ListingDetail.self, from: data)
            XCTAssertEqual(detail.id, 91)
            XCTAssertEqual(detail.status, "sold")
            XCTAssertEqual(detail.soldPricePublic, 55900)
            XCTAssertNotNil(detail.soldAt)
        } catch {
            XCTFail("decode failed: \(error)")
        }
    }
}
