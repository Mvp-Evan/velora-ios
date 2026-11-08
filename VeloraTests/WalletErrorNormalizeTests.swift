import XCTest
@testable import Velora

/// PAY-09: legacy platform payout / payout-account errors are not client error codes.
final class WalletErrorNormalizeTests: XCTestCase {
    func testNormalizeIgnoresRemovedPayoutAccountRequired() {
        XCTAssertNil(WalletErrorCode.normalize("payout_account_required"))
        XCTAssertNil(WalletErrorCode.normalize("PAYOUT_ACCOUNT_REQUIRED"))
    }

    func testNormalizeMapsWithdrawWhitelist() {
        XCTAssertEqual(WalletErrorCode.normalize("withdraw_not_whitelisted"), .withdrawNotWhitelisted)
    }
}
