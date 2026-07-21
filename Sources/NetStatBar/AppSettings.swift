import Foundation
import NetStatCore

enum DisplayStyle: String, CaseIterable {
    case arrows
    case labels
    case compact
    case downloadOnly
    case uploadOnly

    var title: String {
        switch self {
        case .arrows:
            return "Arrows"
        case .labels:
            return "Labels"
        case .compact:
            return "Compact"
        case .downloadOnly:
            return "Download Only"
        case .uploadOnly:
            return "Upload Only"
        }
    }
}

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

struct AppSettings {
    static let updateIntervals: [TimeInterval] = [0.5, 1, 2, 5]
    static let itemWidthRange = 60.0...250.0
    static let fontSizeRange = 9.0...18.0

    var updateInterval: TimeInterval
    var displayStyle: DisplayStyle
    var unitMode: UnitMode
    var interfaceMode: InterfaceMode
    var appearance: AppAppearance
    var customItemWidth: Double
    var fontSize: Double

    static let defaults = AppSettings(
        updateInterval: 1,
        displayStyle: .arrows,
        unitMode: .bytes,
        interfaceMode: .automatic,
        appearance: .system,
        customItemWidth: 0,
        fontSize: 12
    )

    init(
        updateInterval: TimeInterval,
        displayStyle: DisplayStyle,
        unitMode: UnitMode,
        interfaceMode: InterfaceMode,
        appearance: AppAppearance,
        customItemWidth: Double,
        fontSize: Double
    ) {
        self.updateInterval = updateInterval
        self.displayStyle = displayStyle
        self.unitMode = unitMode
        self.interfaceMode = interfaceMode
        self.appearance = appearance
        self.customItemWidth = customItemWidth
        self.fontSize = fontSize
    }

    init(defaults: UserDefaults = .standard) {
        let fallback = Self.defaults
        let storedInterval = defaults.double(forKey: Keys.updateInterval)

        if Self.updateIntervals.contains(storedInterval) {
            updateInterval = storedInterval
        } else {
            updateInterval = fallback.updateInterval
        }

        displayStyle = DisplayStyle(rawValue: defaults.string(forKey: Keys.displayStyle) ?? "")
            ?? fallback.displayStyle
        unitMode = UnitMode(rawValue: defaults.string(forKey: Keys.unitMode) ?? "")
            ?? fallback.unitMode
        interfaceMode = InterfaceMode(rawValue: defaults.string(forKey: Keys.interfaceMode) ?? "")
            ?? fallback.interfaceMode
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "")
            ?? fallback.appearance

        let storedWidth = defaults.double(forKey: Keys.customItemWidth)
        if storedWidth.isFinite && (storedWidth == 0 || Self.itemWidthRange.contains(storedWidth)) {
            customItemWidth = storedWidth
        } else {
            customItemWidth = fallback.customItemWidth
        }

        let storedFontSize = defaults.double(forKey: Keys.fontSize)
        if storedFontSize.isFinite && Self.fontSizeRange.contains(storedFontSize) {
            fontSize = storedFontSize
        } else {
            fontSize = fallback.fontSize
        }
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(updateInterval, forKey: Keys.updateInterval)
        defaults.set(displayStyle.rawValue, forKey: Keys.displayStyle)
        defaults.set(unitMode.rawValue, forKey: Keys.unitMode)
        defaults.set(interfaceMode.rawValue, forKey: Keys.interfaceMode)
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
        defaults.set(customItemWidth, forKey: Keys.customItemWidth)
        defaults.set(fontSize, forKey: Keys.fontSize)
    }

    static func reset(defaults: UserDefaults = .standard) {
        Keys.all.forEach(defaults.removeObject(forKey:))
    }

    private enum Keys {
        static let updateInterval = "updateInterval"
        static let displayStyle = "displayStyle"
        static let unitMode = "unitMode"
        static let interfaceMode = "interfaceMode"
        static let appearance = "appearance"
        static let customItemWidth = "customItemWidth"
        static let fontSize = "fontSize"

        static let all = [
            updateInterval,
            displayStyle,
            unitMode,
            interfaceMode,
            appearance,
            customItemWidth,
            fontSize
        ]
    }
}
