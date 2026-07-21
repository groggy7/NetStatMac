import Foundation

public enum UnitMode: String, CaseIterable, Sendable {
    case bytes = "bytes"
    case bits = "bits"

    public var title: String {
        switch self {
        case .bytes:
            return "Bytes/s"
        case .bits:
            return "Bits/s"
        }
    }
}

public enum RateFormatter {
    private static let base = 1000.0

    public static func string(fromBytesPerSecond bytesPerSecond: Double, unitMode: UnitMode) -> String {
        let multiplier = unitMode == .bits ? 8.0 : 1.0
        let units = units(for: unitMode)
        let nonnegativeRate = bytesPerSecond.isFinite ? max(bytesPerSecond, 0) : 0

        var value = (nonnegativeRate * multiplier) / base
        var unitIndex = 0
        var formattedNumber: String

        while true {
            while value >= 100.0, unitIndex < units.count - 1 {
                value /= base
                unitIndex += 1
            }

            formattedNumber = formatNumber(value, unitIndex: unitIndex)

            guard formattedNumber == "100", unitIndex < units.count - 1 else {
                break
            }

            value /= base
            unitIndex += 1
        }

        let paddedNumber = String(repeating: " ", count: max(0, 3 - formattedNumber.count)) + formattedNumber
        return "\(paddedNumber) \(units[unitIndex])"
    }

    private static func formatNumber(_ value: Double, unitIndex: Int) -> String {
        if value == 0 {
            return "0"
        }

        if unitIndex == 0 || value >= 10.0 {
            return "\(Int(value.rounded()))"
        }

        let formatted = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )

        if formatted == "10.0" || formatted.hasSuffix(".0") {
            return "\(Int(value.rounded()))"
        }

        return formatted
    }

    private static func units(for unitMode: UnitMode) -> [String] {
        switch unitMode {
        case .bytes:
            return ["KB/s", "MB/s", "GB/s", "TB/s"]
        case .bits:
            return ["Kb/s", "Mb/s", "Gb/s", "Tb/s"]
        }
    }
}
