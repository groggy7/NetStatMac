import AppKit
import Darwin

struct NetworkSnapshot {
    let countersByInterface: [String: NetworkInterfaceCounters]
    let timestamp: TimeInterval
}

struct NetworkInterfaceCounters {
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

struct NetworkRate {
    let downBytesPerSecond: Double
    let upBytesPerSecond: Double

    static let zero = NetworkRate(downBytesPerSecond: 0, upBytesPerSecond: 0)
}

enum InterfaceMode: String, CaseIterable {
    case builtIn = "builtIn"
    case allActive = "allActive"

    var title: String {
        switch self {
        case .builtIn:
            return "Built-in Wi-Fi/Ethernet"
        case .allActive:
            return "All Active Interfaces"
        }
    }
}

enum DisplayStyle: String, CaseIterable {
    case arrows = "arrows"
    case labels = "labels"
    case compact = "compact"
    case downloadOnly = "downloadOnly"
    case uploadOnly = "uploadOnly"

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

enum UnitMode: String, CaseIterable {
    case bytes = "bytes"
    case bits = "bits"

    var title: String {
        switch self {
        case .bytes:
            return "Bytes/s"
        case .bits:
            return "Bits/s"
        }
    }
}

struct AppSettings {
    static let updateIntervals: [TimeInterval] = [0.5, 1, 2, 5]

    var updateInterval: TimeInterval
    var displayStyle: DisplayStyle
    var unitMode: UnitMode
    var interfaceMode: InterfaceMode
    var customItemWidth: Double
    var fontSize: Double

    static let defaults = AppSettings(
        updateInterval: 1,
        displayStyle: .arrows,
        unitMode: .bytes,
        interfaceMode: .builtIn,
        customItemWidth: 0,
        fontSize: 12
    )

    init(
        updateInterval: TimeInterval,
        displayStyle: DisplayStyle,
        unitMode: UnitMode,
        interfaceMode: InterfaceMode,
        customItemWidth: Double,
        fontSize: Double
    ) {
        self.updateInterval = updateInterval
        self.displayStyle = displayStyle
        self.unitMode = unitMode
        self.interfaceMode = interfaceMode
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

        displayStyle = DisplayStyle(rawValue: defaults.string(forKey: Keys.displayStyle) ?? "") ?? fallback.displayStyle
        unitMode = UnitMode(rawValue: defaults.string(forKey: Keys.unitMode) ?? "") ?? fallback.unitMode
        interfaceMode = InterfaceMode(rawValue: defaults.string(forKey: Keys.interfaceMode) ?? "") ?? fallback.interfaceMode
        customItemWidth = defaults.double(forKey: Keys.customItemWidth)

        let storedFontSize = defaults.double(forKey: Keys.fontSize)
        fontSize = storedFontSize > 0 ? storedFontSize : fallback.fontSize
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(updateInterval, forKey: Keys.updateInterval)
        defaults.set(displayStyle.rawValue, forKey: Keys.displayStyle)
        defaults.set(unitMode.rawValue, forKey: Keys.unitMode)
        defaults.set(interfaceMode.rawValue, forKey: Keys.interfaceMode)
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
        static let customItemWidth = "customItemWidth"
        static let fontSize = "fontSize"

        static let all = [
            updateInterval,
            displayStyle,
            unitMode,
            interfaceMode,
            customItemWidth,
            fontSize
        ]
    }
}

final class NetworkSampler {
    private var previousSnapshot: NetworkSnapshot?

    func sampleRate(interfaceMode: InterfaceMode) -> NetworkRate {
        guard let current = snapshot(interfaceMode: interfaceMode) else {
            previousSnapshot = nil
            return .zero
        }

        defer { previousSnapshot = current }

        guard let previousSnapshot,
              current.timestamp > previousSnapshot.timestamp,
              current.countersByInterface.count == previousSnapshot.countersByInterface.count else {
            return .zero
        }

        var downDelta: UInt64 = 0
        var upDelta: UInt64 = 0

        for (name, currentCounters) in current.countersByInterface {
            guard let previousCounters = previousSnapshot.countersByInterface[name],
                  currentCounters.receivedBytes >= previousCounters.receivedBytes,
                  currentCounters.sentBytes >= previousCounters.sentBytes else {
                return .zero
            }

            let (nextDownDelta, downOverflow) = downDelta.addingReportingOverflow(
                currentCounters.receivedBytes - previousCounters.receivedBytes
            )
            let (nextUpDelta, upOverflow) = upDelta.addingReportingOverflow(
                currentCounters.sentBytes - previousCounters.sentBytes
            )

            guard !downOverflow, !upOverflow else {
                return .zero
            }

            downDelta = nextDownDelta
            upDelta = nextUpDelta
        }

        let elapsed = current.timestamp - previousSnapshot.timestamp

        return NetworkRate(
            downBytesPerSecond: Double(downDelta) / elapsed,
            upBytesPerSecond: Double(upDelta) / elapsed
        )
    }

    func reset() {
        previousSnapshot = nil
    }

    private func snapshot(interfaceMode: InterfaceMode) -> NetworkSnapshot? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        var countersByInterface: [String: NetworkInterfaceCounters] = [:]

        guard getifaddrs(&interfaces) == 0 else {
            return nil
        }

        if let interfaces {
            defer { freeifaddrs(interfaces) }
            var cursor: UnsafeMutablePointer<ifaddrs>? = interfaces

            while let current = cursor {
                guard shouldCount(current.pointee, interfaceMode: interfaceMode) else {
                    cursor = current.pointee.ifa_next
                    continue
                }

                let name = String(cString: current.pointee.ifa_name)
                let data = current.pointee.ifa_data.assumingMemoryBound(to: if_data.self).pointee
                countersByInterface[name] = NetworkInterfaceCounters(
                    receivedBytes: UInt64(data.ifi_ibytes),
                    sentBytes: UInt64(data.ifi_obytes)
                )
                cursor = current.pointee.ifa_next
            }
        }

        return NetworkSnapshot(
            countersByInterface: countersByInterface,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }

    private func shouldCount(_ interface: ifaddrs, interfaceMode: InterfaceMode) -> Bool {
        guard let address = interface.ifa_addr,
              interface.ifa_data != nil,
              address.pointee.sa_family == UInt8(AF_LINK) else {
            return false
        }

        let name = String(cString: interface.ifa_name)
        let flags = Int32(interface.ifa_flags)
        let isActive = (flags & IFF_UP) != 0
            && (flags & IFF_RUNNING) != 0
            && (flags & IFF_LOOPBACK) == 0

        guard isActive else {
            return false
        }

        switch interfaceMode {
        case .builtIn:
            return name.hasPrefix("en")
        case .allActive:
            return true
        }
    }
}

@MainActor
final class WidthSliderView: NSView {
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")
    var onChange: ((Double) -> Void)?

    init(currentWidth: Double, defaultWidth: Double) {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 32))

        let titleLabel = NSTextField(labelWithString: "Custom Width:")
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.frame = NSRect(x: 14, y: 7, width: 90, height: 18)

        let initialVal = currentWidth > 0 ? currentWidth : defaultWidth
        slider.minValue = 60
        slider.maxValue = 250
        slider.doubleValue = initialVal
        slider.frame = NSRect(x: 108, y: 6, width: 70, height: 18)
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.isContinuous = true

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = NSColor.secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 178, y: 7, width: 34, height: 18)
        valueLabel.stringValue = "\(Int(initialVal.rounded())) pt"

        addSubview(titleLabel)
        addSubview(slider)
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let val = sender.doubleValue.rounded()
        valueLabel.stringValue = "\(Int(val)) pt"
        onChange?(val)
    }
}

@MainActor
final class FontSizeSliderView: NSView {
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")
    var onChange: ((Double) -> Void)?

    init(currentSize: Double) {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 32))

        let titleLabel = NSTextField(labelWithString: "Font Size:")
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.frame = NSRect(x: 14, y: 7, width: 90, height: 18)

        slider.minValue = 9
        slider.maxValue = 18
        slider.doubleValue = currentSize
        slider.frame = NSRect(x: 108, y: 6, width: 70, height: 18)
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.isContinuous = true

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = NSColor.secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 178, y: 7, width: 34, height: 18)
        valueLabel.stringValue = "\(Int(currentSize.rounded())) pt"

        addSubview(titleLabel)
        addSubview(slider)
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let val = sender.doubleValue.rounded()
        valueLabel.stringValue = "\(Int(val)) pt"
        onChange?(val)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let sampler = NetworkSampler()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var settings = AppSettings()
    private var lastRate = NetworkRate.zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        startSampling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func updateFont() {
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: settings.fontSize, weight: .regular)
    }

    private func configureStatusItem() {
        updateFont()
        statusItem.button?.alignment = .center
        statusItem.button?.lineBreakMode = .byClipping
        statusItem.button?.cell?.wraps = false
        updateStatusItemWidth()
        rebuildMenu()
        updateStatusItem()
    }

    private func updateStatusItemWidth() {
        if settings.customItemWidth > 0 {
            statusItem.length = settings.customItemWidth
        } else {
            statusItem.length = calculatedAutoWidth()
        }
    }

    private func calculatedAutoWidth() -> Double {
        guard statusItem.button != nil else { return 125.0 }

        let sampleDown = "88 KB/s"
        let sampleUp = "88 KB/s"
        let sampleTitle: String

        switch settings.displayStyle {
        case .arrows:
            sampleTitle = "↓ \(sampleDown)  ↑ \(sampleUp)"
        case .labels:
            sampleTitle = "D \(sampleDown)  U \(sampleUp)"
        case .compact:
            sampleTitle = "\(sampleDown) | \(sampleUp)"
        case .downloadOnly:
            sampleTitle = "↓ \(sampleDown)"
        case .uploadOnly:
            sampleTitle = "↑ \(sampleUp)"
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: settings.fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (sampleTitle as NSString).size(withAttributes: attributes)
        return ceil(textSize.width) + 14.0
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "NetStatBar", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(parentMenuItem(title: "Update Interval", submenu: updateIntervalMenu()))
        menu.addItem(parentMenuItem(title: "Display Style", submenu: displayStyleMenu()))
        menu.addItem(parentMenuItem(title: "Item Width", submenu: itemWidthMenu()))
        menu.addItem(parentMenuItem(title: "Font Size", submenu: fontSizeMenu()))
        menu.addItem(parentMenuItem(title: "Units", submenu: unitsMenu()))
        menu.addItem(parentMenuItem(title: "Interfaces", submenu: interfaceMenu()))

        menu.addItem(NSMenuItem.separator())

        let reset = NSMenuItem(title: "Reset to Defaults", action: #selector(resetSettings), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func menuDidClose(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func parentMenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func updateIntervalMenu() -> NSMenu {
        let menu = NSMenu()

        for interval in AppSettings.updateIntervals {
            let item = NSMenuItem(
                title: intervalTitle(interval),
                action: #selector(setUpdateInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = interval
            item.state = settings.updateInterval == interval ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    private func displayStyleMenu() -> NSMenu {
        let menu = NSMenu()

        for style in DisplayStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(setDisplayStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = settings.displayStyle == style ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    private func itemWidthMenu() -> NSMenu {
        let menu = NSMenu()

        let autoItem = NSMenuItem(title: "Auto (Fit Content)", action: #selector(setItemWidthAuto), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = settings.customItemWidth == 0 ? .on : .off
        menu.addItem(autoItem)

        menu.addItem(NSMenuItem.separator())

        let presets: [(String, Double)] = [
            ("Compact - Download Only (70 pt)", 70),
            ("Standard - Dual Speed (125 pt)", 125),
            ("Wide (160 pt)", 160),
            ("Extra Wide (200 pt)", 200)
        ]

        for (title, width) in presets {
            let item = NSMenuItem(title: title, action: #selector(setItemWidthPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = width
            item.state = settings.customItemWidth == width ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let sliderView = WidthSliderView(
            currentWidth: settings.customItemWidth,
            defaultWidth: calculatedAutoWidth()
        )
        sliderView.onChange = { [weak self] width in
            guard let self = self else { return }
            self.settings.customItemWidth = width
            self.saveSettings()
            self.updateStatusItemWidth()
            self.updateStatusItem()
        }

        let sliderMenuItem = NSMenuItem()
        sliderMenuItem.view = sliderView
        menu.addItem(sliderMenuItem)

        return menu
    }

    @objc private func setItemWidthAuto() {
        settings.customItemWidth = 0
        saveSettings()
        updateStatusItemWidth()
        updateStatusItem()
    }

    @objc private func setItemWidthPreset(_ sender: NSMenuItem) {
        guard let width = sender.representedObject as? Double else { return }
        settings.customItemWidth = width
        saveSettings()
        updateStatusItemWidth()
        updateStatusItem()
    }

    private func fontSizeMenu() -> NSMenu {
        let menu = NSMenu()

        let presets: [(String, Double)] = [
            ("Small (10 pt)", 10),
            ("Standard (12 pt)", 12),
            ("Large (14 pt)", 14)
        ]

        for (title, size) in presets {
            let item = NSMenuItem(title: title, action: #selector(setFontSizePreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size
            item.state = settings.fontSize == size ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let sliderView = FontSizeSliderView(currentSize: settings.fontSize)
        sliderView.onChange = { [weak self] size in
            guard let self = self else { return }
            self.settings.fontSize = size
            self.saveSettings()
            self.updateFont()
            self.updateStatusItemWidth()
            self.updateStatusItem()
        }

        let sliderMenuItem = NSMenuItem()
        sliderMenuItem.view = sliderView
        menu.addItem(sliderMenuItem)

        return menu
    }

    @objc private func setFontSizePreset(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Double else { return }
        settings.fontSize = size
        saveSettings()
        updateFont()
        updateStatusItemWidth()
        updateStatusItem()
    }

    private func unitsMenu() -> NSMenu {
        let menu = NSMenu()

        for unitMode in UnitMode.allCases {
            let item = NSMenuItem(title: unitMode.title, action: #selector(setUnitMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = unitMode.rawValue
            item.state = settings.unitMode == unitMode ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    private func interfaceMenu() -> NSMenu {
        let menu = NSMenu()

        for interfaceMode in InterfaceMode.allCases {
            let item = NSMenuItem(title: interfaceMode.title, action: #selector(setInterfaceMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = interfaceMode.rawValue
            item.state = settings.interfaceMode == interfaceMode ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    private func startSampling() {
        timer?.invalidate()
        sampler.reset()
        lastRate = .zero
        _ = sampler.sampleRate(interfaceMode: settings.interfaceMode)

        let timer = Timer(
            timeInterval: settings.updateInterval,
            target: self,
            selector: #selector(sampleAndUpdateStatusItem),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        updateStatusItem()
    }

    @objc private func sampleAndUpdateStatusItem() {
        lastRate = sampler.sampleRate(interfaceMode: settings.interfaceMode)
        updateStatusItem()
    }

    private func updateStatusItem() {
        statusItem.button?.toolTip = tooltip()

        let down = format(lastRate.downBytesPerSecond)
        let up = format(lastRate.upBytesPerSecond)
        let effectiveWidth = statusItem.length
        let isNarrow = effectiveWidth > 0 && effectiveWidth < 120

        if settings.displayStyle == .compact && !isNarrow {
            let font = NSFont.monospacedDigitSystemFont(ofSize: settings.fontSize, weight: .regular)
            let attrString = NSMutableAttributedString()
            let mainAttrs: [NSAttributedString.Key: Any] = [.font: font]
            let pipeAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.systemGreen
            ]

            attrString.append(NSAttributedString(string: "\(down) ", attributes: mainAttrs))
            attrString.append(NSAttributedString(string: "|", attributes: pipeAttrs))
            attrString.append(NSAttributedString(string: " \(up)", attributes: mainAttrs))

            statusItem.button?.attributedTitle = attrString
        } else {
            statusItem.button?.title = title(for: lastRate)
        }
    }

    @objc private func setUpdateInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else {
            return
        }

        settings.updateInterval = interval
        saveSettings()
        startSampling()
    }

    @objc private func setDisplayStyle(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let displayStyle = DisplayStyle(rawValue: rawValue) else {
            return
        }

        settings.displayStyle = displayStyle
        saveSettings()
        updateStatusItemWidth()
        updateStatusItem()
    }

    @objc private func setUnitMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let unitMode = UnitMode(rawValue: rawValue) else {
            return
        }

        settings.unitMode = unitMode
        saveSettings()
        updateStatusItem()
    }

    @objc private func setInterfaceMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let interfaceMode = InterfaceMode(rawValue: rawValue) else {
            return
        }

        settings.interfaceMode = interfaceMode
        saveSettings()
        startSampling()
    }

    @objc private func resetSettings() {
        AppSettings.reset()
        settings = AppSettings()
        saveSettings()
        updateFont()
        updateStatusItemWidth()
        startSampling()
    }

    private func saveSettings() {
        settings.save()
    }

    private func title(for rate: NetworkRate) -> String {
        let down = format(rate.downBytesPerSecond)
        let up = format(rate.upBytesPerSecond)

        let effectiveWidth = statusItem.length

        // If width is too constrained (< 120 pt) for dual speed, adaptively show Download speed only
        if effectiveWidth > 0 && effectiveWidth < 120 {
            switch settings.displayStyle {
            case .arrows, .compact:
                return "↓ \(down)"
            case .labels:
                return "D \(down)"
            case .downloadOnly:
                return "↓ \(down)"
            case .uploadOnly:
                return "↑ \(up)"
            }
        }

        switch settings.displayStyle {
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

    private func tooltip() -> String {
        let down = format(lastRate.downBytesPerSecond)
        let up = format(lastRate.upBytesPerSecond)

        return [
            "Download: \(down)",
            "Upload: \(up)",
            "Interval: \(intervalTitle(settings.updateInterval))",
            "Interfaces: \(settings.interfaceMode.title)"
        ].joined(separator: "\n")
    }

    private func intervalTitle(_ interval: TimeInterval) -> String {
        if interval == floor(interval) {
            return "\(Int(interval)) second\(interval == 1 ? "" : "s")"
        }

        return String(format: "%.1f seconds", interval)
    }

    private func format(_ bytesPerSecond: Double) -> String {
        let multiplier = settings.unitMode == .bits ? 8.0 : 1.0
        let base = 1000.0
        let units = unitsForCurrentSettings()

        var value = (bytesPerSecond * multiplier) / base
        var unitIndex = 0

        // Never exceed 99 in current unit; transition to next unit (0.1 MB/s, 0.1 GB/s, etc.) at >= 100
        while value >= 100.0, unitIndex < units.count - 1 {
            value /= base
            unitIndex += 1
        }

        let formattedNumber: String
        if value == 0 {
            formattedNumber = "0"
        } else if unitIndex == 0 {
            // For Kilo units (0 to 99): integer format
            formattedNumber = "\(Int(value.rounded()))"
        } else {
            // For Mega, Giga, Tera units
            if value < 10.0 {
                let formatted = String(format: "%.1f", value)
                if formatted == "10.0" || formatted.hasSuffix(".0") {
                    formattedNumber = "\(Int(value.rounded()))"
                } else {
                    formattedNumber = formatted
                }
            } else {
                formattedNumber = "\(Int(value.rounded()))"
            }
        }

        let paddedNumber = String(repeating: " ", count: max(0, 3 - formattedNumber.count)) + formattedNumber
        return "\(paddedNumber) \(units[unitIndex])"
    }

    private func unitsForCurrentSettings() -> [String] {
        switch settings.unitMode {
        case .bytes:
            return ["KB/s", "MB/s", "GB/s", "TB/s"]
        case .bits:
            return ["Kb/s", "Mb/s", "Gb/s", "Tb/s"]
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
