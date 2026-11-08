import XCTest
@testable import Velora

final class MoneyFormattingTests: XCTestCase {
    func testYuanConversion() {
        XCTAssertEqual(Money(123_400).yuan, 1234)
        XCTAssertEqual(Money(12_350).yuan, 123.5, accuracy: 0.0001)
        XCTAssertEqual(Money(0).yuan, 0)
    }

    func testDisplayFixedAlwaysTwoFractionDigits() {
        XCTAssertEqual(Money(123_400).displayFixed, "¥1234.00")
        XCTAssertEqual(Money(12_350).displayFixed, "¥123.50")
        XCTAssertEqual(Money(0).displayFixed, "¥0.00")
    }

    func testDisplayPrefixAndWholeYuan() {
        let whole: Money = 100
        XCTAssertTrue(whole.display.hasPrefix("¥"))
        XCTAssertEqual(whole.displayNoSymbol, String(whole.display.dropFirst()))
        // Whole fen multiples omit fraction digits in `display`
        XCTAssertFalse(whole.display.contains("."))
    }
}
