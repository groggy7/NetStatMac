import Foundation
import NetStatCore
import XCTest
@testable import NetStatBar

final class AppBehaviorTests: XCTestCase {
    func testStatusTitlePreservesDualAndNarrowLayouts() {
        let rate = NetworkRate(downBytesPerSecond: 1_000, upBytesPerSecond: 2_000)

        XCTAssertEqual(
            StatusTitleFormatter.title(
                for: rate,
                displayStyle: .arrows,
                unitMode: .bytes,
                isNarrow: false
            ),
            "↓   1 KB/s  ↑   2 KB/s"
        )
        XCTAssertEqual(
            StatusTitleFormatter.title(
                for: rate,
                displayStyle: .labels,
                unitMode: .bytes,
                isNarrow: true
            ),
            "D   1 KB/s"
        )
    }

    func testInvalidPersistedLayoutValuesFallBackToDefaults() throws {
        let suiteName = "NetStatBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(1_000, forKey: "customItemWidth")
        defaults.set(-5, forKey: "fontSize")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.customItemWidth, AppSettings.defaults.customItemWidth)
        XCTAssertEqual(settings.fontSize, AppSettings.defaults.fontSize)
    }
}
