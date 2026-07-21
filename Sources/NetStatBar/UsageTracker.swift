import Foundation
import NetStatCore

struct UsageAmount: Equatable {
    let downloadedBytes: UInt64
    let uploadedBytes: UInt64

    var totalBytes: UInt64 {
        let (total, overflow) = downloadedBytes.addingReportingOverflow(uploadedBytes)
        return overflow ? UInt64.max : total
    }
}

struct UsageSummary: Equatable {
    let today: UsageAmount
    let month: UsageAmount
    let year: UsageAmount
}

final class UsageTracker {
    private struct StoredState: Codable {
        var dayID = ""
        var monthID = ""
        var yearID = ""
        var dayDownloaded: UInt64 = 0
        var dayUploaded: UInt64 = 0
        var monthDownloaded: UInt64 = 0
        var monthUploaded: UInt64 = 0
        var yearDownloaded: UInt64 = 0
        var yearUploaded: UInt64 = 0
    }

    private static let storageKey = "trackedNetworkUsage"
    private static let saveInterval: TimeInterval = 30

    private let defaults: UserDefaults
    private var calendar: Calendar
    private var state: StoredState
    private var lastSavedAt: Date?

    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.defaults = defaults
        self.calendar = calendar

        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(StoredState.self, from: data) {
            state = decoded
        } else {
            state = StoredState()
        }
    }

    func record(_ measurement: NetworkMeasurement, at date: Date = Date()) {
        let periodChanged = normalizePeriods(at: date)
        state.dayDownloaded = addingClamped(state.dayDownloaded, measurement.downloadedBytes)
        state.dayUploaded = addingClamped(state.dayUploaded, measurement.uploadedBytes)
        state.monthDownloaded = addingClamped(state.monthDownloaded, measurement.downloadedBytes)
        state.monthUploaded = addingClamped(state.monthUploaded, measurement.uploadedBytes)
        state.yearDownloaded = addingClamped(state.yearDownloaded, measurement.downloadedBytes)
        state.yearUploaded = addingClamped(state.yearUploaded, measurement.uploadedBytes)

        if periodChanged
            || lastSavedAt == nil
            || date.timeIntervalSince(lastSavedAt ?? date) >= Self.saveInterval {
            save(at: date)
        }
    }

    func summary(at date: Date = Date()) -> UsageSummary {
        if normalizePeriods(at: date) {
            save(at: date)
        }

        return UsageSummary(
            today: UsageAmount(
                downloadedBytes: state.dayDownloaded,
                uploadedBytes: state.dayUploaded
            ),
            month: UsageAmount(
                downloadedBytes: state.monthDownloaded,
                uploadedBytes: state.monthUploaded
            ),
            year: UsageAmount(
                downloadedBytes: state.yearDownloaded,
                uploadedBytes: state.yearUploaded
            )
        )
    }

    func reset(at date: Date = Date()) {
        state = StoredState()
        _ = normalizePeriods(at: date)
        save(at: date)
    }

    func flush(at date: Date = Date()) {
        _ = normalizePeriods(at: date)
        save(at: date)
    }

    private func normalizePeriods(at date: Date) -> Bool {
        let identifiers = periodIdentifiers(at: date)
        var changed = false

        if state.dayID != identifiers.day {
            state.dayID = identifiers.day
            state.dayDownloaded = 0
            state.dayUploaded = 0
            changed = true
        }

        if state.monthID != identifiers.month {
            state.monthID = identifiers.month
            state.monthDownloaded = 0
            state.monthUploaded = 0
            changed = true
        }

        if state.yearID != identifiers.year {
            state.yearID = identifiers.year
            state.yearDownloaded = 0
            state.yearUploaded = 0
            changed = true
        }

        return changed
    }

    private func periodIdentifiers(at date: Date) -> (day: String, month: String, year: String) {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let era = components.era ?? 0
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0

        return (
            "\(era)-\(year)-\(month)-\(day)",
            "\(era)-\(year)-\(month)",
            "\(era)-\(year)"
        )
    }

    private func save(at date: Date) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
        lastSavedAt = date
    }

    private func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }
}

enum DataAmountFormatter {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    static func string(bytes: UInt64) -> String {
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }

        let number: String
        if unitIndex == 0 || value >= 100 {
            number = "\(Int(value.rounded()))"
        } else if value >= 10 {
            number = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
                .replacingOccurrences(of: ".0", with: "")
        } else {
            number = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        }

        return "\(number) \(units[unitIndex])"
    }
}
