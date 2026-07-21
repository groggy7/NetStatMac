import XCTest
@testable import NetStatCore

final class RateFormatterTests: XCTestCase {
    func testZeroUsesKilobytesAndPadding() {
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: 0, unitMode: .bytes),
            "  0 KB/s"
        )
    }

    func testKilobytesUseRoundedIntegers() {
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: 12_400, unitMode: .bytes),
            " 12 KB/s"
        )
    }

    func testBitsModeConvertsBytesToBits() {
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: 1_500, unitMode: .bits),
            " 12 Kb/s"
        )
    }

    func testMegabytesBelowTenUseOneDecimalPlace() {
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: 1_260_000, unitMode: .bytes),
            "1.3 MB/s"
        )
    }

    func testWholeMegabytesDropDecimalPlace() {
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: 2_000_000, unitMode: .bytes),
            "  2 MB/s"
        )
    }

    func testExactUnitBoundaryMovesToNextUnit() {
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: 100_000, unitMode: .bytes),
            "0.1 MB/s"
        )
    }

    func testRoundedHundredMovesToNextUnit() {
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: 99_500, unitMode: .bytes),
            "0.1 MB/s"
        )
    }

    func testValueBelowRoundedBoundaryStaysInCurrentUnit() {
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: 99_499, unitMode: .bytes),
            " 99 KB/s"
        )
    }

    func testHigherUnitsUseTheSameBoundaryRule() {
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: 99_500_000, unitMode: .bytes),
            "0.1 GB/s"
        )
    }

    func testNegativeAndNonfiniteRatesAreRenderedAsZero() {
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: -1, unitMode: .bytes),
            "  0 KB/s"
        )
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: .infinity, unitMode: .bytes),
            "  0 KB/s"
        )
        XCTAssertEqual(
            RateFormatter.string(fromBytesPerSecond: .nan, unitMode: .bytes),
            "  0 KB/s"
        )
    }
}
