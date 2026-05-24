import XCTest
@testable import CommitPyramid

final class MapSeedValidatorTests: XCTestCase {
    func testEmptyReturnsNil() {
        XCTAssertNil(MapSeedValidator.parse(""))
    }

    func testWhitespaceReturnsNil() {
        XCTAssertNil(MapSeedValidator.parse("   "))
    }

    func testNumericReturnsValue() {
        XCTAssertEqual(MapSeedValidator.parse("123"), 123)
    }

    func testAlphabeticReturnsNil() {
        XCTAssertNil(MapSeedValidator.parse("abc"))
    }

    func testMixedReturnsNil() {
        XCTAssertNil(MapSeedValidator.parse("12a3"))
    }

    func testHugeOverflowReturnsNil() {
        // UInt64.max + 1 causes overflow → nil
        XCTAssertNil(MapSeedValidator.parse("99999999999999999999999"))
    }

    func testNegativeReturnsNil() {
        XCTAssertNil(MapSeedValidator.parse("-1"))
    }

    func testMaxUInt64IsValid() {
        // UInt64.max = 18446744073709551615
        let maxStr = String(UInt64.max)
        XCTAssertEqual(MapSeedValidator.parse(maxStr), UInt64.max)
    }

    func testLeadingZerosAreValid() {
        XCTAssertEqual(MapSeedValidator.parse("00123"), 123)
    }
}
