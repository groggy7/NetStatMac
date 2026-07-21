import NetStatCore

enum StatusTitleFormatter {
    static func title(
        for rate: NetworkRate,
        displayStyle: DisplayStyle,
        unitMode: UnitMode,
        isNarrow: Bool
    ) -> String {
        let down = RateFormatter.string(
            fromBytesPerSecond: rate.downBytesPerSecond,
            unitMode: unitMode
        )
        let up = RateFormatter.string(
            fromBytesPerSecond: rate.upBytesPerSecond,
            unitMode: unitMode
        )

        if isNarrow {
            switch displayStyle {
            case .arrows, .compact, .downloadOnly:
                return "↓ \(down)"
            case .labels:
                return "D \(down)"
            case .uploadOnly:
                return "↑ \(up)"
            }
        }

        switch displayStyle {
        case .arrows:
            return "↓ \(down)  ↑ \(up)"
        case .labels:
            return "D \(down)  U \(up)"
        case .compact:
            return "\(down) | \(up)"
        case .downloadOnly:
            return "↓ \(down)"
        case .uploadOnly:
            return "↑ \(up)"
        }
    }
}
