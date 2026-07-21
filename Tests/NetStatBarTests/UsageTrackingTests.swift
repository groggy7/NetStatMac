import Foundation
import NetStatCore
import XCTest
@testable import NetStatBar

final class UsageTrackingTests: XCTestCase {
    func testUsageTrackerRollsPeriodsForwardAndPersists() throws {
        let suiteName = "NetStatBarUsageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let tracker = UsageTracker(defaults: defaults, calendar: calendar)

        tracker.record(measurement(downloaded: 1_000, uploaded: 500), at: date(2026, 7, 21, calendar))
        tracker.record(measurement(downloaded: 2_000, uploaded: 1_000), at: date(2026, 7, 22, calendar))

        var summary = tracker.summary(at: date(2026, 7, 22, calendar))
        XCTAssertEqual(summary.today.totalBytes, 3_000)
        XCTAssertEqual(summary.month.totalBytes, 4_500)
        XCTAssertEqual(summary.year.totalBytes, 4_500)

        tracker.record(measurement(downloaded: 4_000, uploaded: 2_000), at: date(2026, 8, 1, calendar))
        tracker.flush(at: date(2026, 8, 1, calendar))

        let restored = UsageTracker(defaults: defaults, calendar: calendar)
        summary = restored.summary(at: date(2026, 8, 1, calendar))
        XCTAssertEqual(summary.today.totalBytes, 6_000)
        XCTAssertEqual(summary.month.totalBytes, 6_000)
        XCTAssertEqual(summary.year.totalBytes, 10_500)

        summary = restored.summary(at: date(2027, 1, 1, calendar))
        XCTAssertEqual(summary.today.totalBytes, 0)
        XCTAssertEqual(summary.month.totalBytes, 0)
        XCTAssertEqual(summary.year.totalBytes, 0)
    }

    func testDataAmountFormatterUsesCompactDecimalUnits() {
        XCTAssertEqual(DataAmountFormatter.string(bytes: 0), "0 B")
        XCTAssertEqual(DataAmountFormatter.string(bytes: 1_500_000), "1.5 MB")
        XCTAssertEqual(DataAmountFormatter.string(bytes: 12_000_000), "12 MB")
    }

    func testRateHistoryKeepsOnlyTheLastMinute() {
        let history = RateHistory(duration: 60)
        history.append(NetworkRate(downBytesPerSecond: 1, upBytesPerSecond: 2), at: 100)
        history.append(NetworkRate(downBytesPerSecond: 3, upBytesPerSecond: 4), at: 159)
        history.append(NetworkRate(downBytesPerSecond: 5, upBytesPerSecond: 6), at: 161)

        XCTAssertEqual(
            history.points,
            [
                RateHistoryPoint(
                    timestamp: 159,
                    rate: NetworkRate(downBytesPerSecond: 3, upBytesPerSecond: 4)
                ),
                RateHistoryPoint(
                    timestamp: 161,
                    rate: NetworkRate(downBytesPerSecond: 5, upBytesPerSecond: 6)
                )
            ]
        )
    }

    func testRateHistoryResetsAfterNonmonotonicTime() {
        let history = RateHistory()
        history.append(NetworkRate(downBytesPerSecond: 1, upBytesPerSecond: 2), at: 100)
        history.append(NetworkRate(downBytesPerSecond: 3, upBytesPerSecond: 4), at: 99)

        XCTAssertEqual(history.points.count, 1)
        XCTAssertEqual(history.points.first?.timestamp, 99)
    }

    private func measurement(downloaded: UInt64, uploaded: UInt64) -> NetworkMeasurement {
        NetworkMeasurement(
            rate: .zero,
            downloadedBytes: downloaded,
            uploadedBytes: uploaded
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
