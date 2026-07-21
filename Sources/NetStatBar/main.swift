import AppKit
import Darwin

struct NetworkSnapshot {
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let timestamp: TimeInterval
}

struct NetworkRate {
    let downBytesPerSecond: Double
    let upBytesPerSecond: Double
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

enum ScaleMode: String, CaseIterable {
    case binary = "binary"
    case decimal = "decimal"

    var title: String {
        switch self {
        case .binary:
            return "Binary (KiB/MiB)"
        case .decimal:
            return "Decimal (KB/MB)"
        }
    }
}

struct AppSettings {
    static let updateIntervals: [TimeInterval] = [0.5, 1, 2, 5]

    var updateInterval: TimeInterval
    var displayStyle: DisplayStyle
    var unitMode: UnitMode
    var scaleMode: ScaleMode
    var interfaceMode: InterfaceMode
    var showZeroDecimals: Bool

    static let defaults = AppSettings(
        updateInterval: 1,
        displayStyle: .arrows,
        unitMode: .bytes,
        scaleMode: .binary,
        interfaceMode: .builtIn,
        showZeroDecimals: false
    )

    init(
        updateInterval: TimeInterval,
        displayStyle: DisplayStyle,
        unitMode: UnitMode,
        scaleMode: ScaleMode,
        interfaceMode: InterfaceMode,
        showZeroDecimals: Bool
    ) {
        self.updateInterval = updateInterval
        self.displayStyle = displayStyle
        self.unitMode = unitMode
        self.scaleMode = scaleMode
        self.interfaceMode = interfaceMode
        self.showZeroDecimals = showZeroDecimals
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
        scaleMode = ScaleMode(rawValue: defaults.string(forKey: Keys.scaleMode) ?? "") ?? fallback.scaleMode
        interfaceMode = InterfaceMode(rawValue: defaults.string(forKey: Keys.interfaceMode) ?? "") ?? fallback.interfaceMode
        showZeroDecimals = defaults.object(forKey: Keys.showZeroDecimals) as? Bool ?? fallback.showZeroDecimals
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(updateInterval, forKey: Keys.updateInterval)
        defaults.set(displayStyle.rawValue, forKey: Keys.displayStyle)
        defaults.set(unitMode.rawValue, forKey: Keys.unitMode)
        defaults.set(scaleMode.rawValue, forKey: Keys.scaleMode)
        defaults.set(interfaceMode.rawValue, forKey: Keys.interfaceMode)
        defaults.set(showZeroDecimals, forKey: Keys.showZeroDecimals)
    }

    static func reset(defaults: UserDefaults = .standard) {
        Keys.all.forEach(defaults.removeObject(forKey:))
    }

    private enum Keys {
        static let updateInterval = "updateInterval"
        static let displayStyle = "displayStyle"
        static let unitMode = "unitMode"
        static let scaleMode = "scaleMode"
        static let interfaceMode = "interfaceMode"
        static let showZeroDecimals = "showZeroDecimals"

        static let all = [
            updateInterval,
            displayStyle,
            unitMode,
            scaleMode,
            interfaceMode,
            showZeroDecimals
        ]
    }
}

final class NetworkSampler {
    private var previousSnapshot: NetworkSnapshot?

    func sampleRate(interfaceMode: InterfaceMode) -> NetworkRate {
        let current = snapshot(interfaceMode: interfaceMode)
        defer { previousSnapshot = current }

        guard let previousSnapshot else {
            return NetworkRate(downBytesPerSecond: 0, upBytesPerSecond: 0)
        }

        let elapsed = max(current.timestamp - previousSnapshot.timestamp, 0.001)
        let downDelta = current.receivedBytes >= previousSnapshot.receivedBytes
            ? current.receivedBytes - previousSnapshot.receivedBytes
            : 0
        let upDelta = current.sentBytes >= previousSnapshot.sentBytes
            ? current.sentBytes - previousSnapshot.sentBytes
            : 0

        return NetworkRate(
            downBytesPerSecond: Double(downDelta) / elapsed,
            upBytesPerSecond: Double(upDelta) / elapsed
        )
    }

    func reset() {
        previousSnapshot = nil
    }

    private func snapshot(interfaceMode: InterfaceMode) -> NetworkSnapshot {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        var received: UInt64 = 0
        var sent: UInt64 = 0

        if getifaddrs(&interfaces) == 0, let interfaces {
            var cursor: UnsafeMutablePointer<ifaddrs>? = interfaces

            while let current = cursor {
                defer { cursor = current.pointee.ifa_next }

                guard shouldCount(current.pointee, interfaceMode: interfaceMode) else {
                    continue
                }

                let data = current.pointee.ifa_data.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(data.ifi_ibytes)
                sent += UInt64(data.ifi_obytes)
            }

            freeifaddrs(interfaces)
        }

        return NetworkSnapshot(
            receivedBytes: received,
            sentBytes: sent,
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sampler = NetworkSampler()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var settings = AppSettings()
    private var lastRate = NetworkRate(downBytesPerSecond: 0, upBytesPerSecond: 0)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        startSampling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func configureStatusItem() {
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        statusItem.button?.alignment = .center
        updateStatusItemWidth()
        rebuildMenu()
        updateStatusItem()
    }

    private func updateStatusItemWidth() {
        guard let button = statusItem.button else { return }

        let sampleDown = "888.8 KiB/s"
        let sampleUp = "888.8 KiB/s"
        let sampleTitle: String

        switch settings.displayStyle {
        case .arrows:
            sampleTitle = "↓ \(sampleDown)  ↑ \(sampleUp)"
        case .labels:
            sampleTitle = "D \(sampleDown)  U \(sampleUp)"
        case .compact:
            sampleTitle = "\(sampleDown)/\(sampleUp)"
        case .downloadOnly:
            sampleTitle = "↓ \(sampleDown)"
        case .uploadOnly:
            sampleTitle = "↑ \(sampleUp)"
        }

        let font = button.font ?? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (sampleTitle as NSString).size(withAttributes: attributes)
        statusItem.length = ceil(textSize.width) + 14.0
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "NetStatBar", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(parentMenuItem(title: "Update Interval", submenu: updateIntervalMenu()))
        menu.addItem(parentMenuItem(title: "Display Style", submenu: displayStyleMenu()))
        menu.addItem(parentMenuItem(title: "Units", submenu: unitsMenu()))
        menu.addItem(parentMenuItem(title: "Interfaces", submenu: interfaceMenu()))

        let zeroDecimals = NSMenuItem(
            title: "Show 0.0 Instead of 0",
            action: #selector(toggleZeroDecimals),
            keyEquivalent: ""
        )
        zeroDecimals.target = self
        zeroDecimals.state = settings.showZeroDecimals ? .on : .off
        menu.addItem(zeroDecimals)

        menu.addItem(NSMenuItem.separator())

        let reset = NSMenuItem(title: "Reset to Defaults", action: #selector(resetSettings), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
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

    private func unitsMenu() -> NSMenu {
        let menu = NSMenu()

        for unitMode in UnitMode.allCases {
            let item = NSMenuItem(title: unitMode.title, action: #selector(setUnitMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = unitMode.rawValue
            item.state = settings.unitMode == unitMode ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        for scaleMode in ScaleMode.allCases {
            let item = NSMenuItem(title: scaleMode.title, action: #selector(setScaleMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scaleMode.rawValue
            item.state = settings.scaleMode == scaleMode ? .on : .off
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
        _ = sampler.sampleRate(interfaceMode: settings.interfaceMode)

        let timer = Timer(
            timeInterval: settings.updateInterval,
            target: self,
            selector: #selector(updateStatusItem),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        updateStatusItem()
    }

    @objc private func updateStatusItem() {
        lastRate = sampler.sampleRate(interfaceMode: settings.interfaceMode)
        statusItem.button?.title = title(for: lastRate)
        statusItem.button?.toolTip = tooltip()
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

    @objc private func setScaleMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let scaleMode = ScaleMode(rawValue: rawValue) else {
            return
        }

        settings.scaleMode = scaleMode
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

    @objc private func toggleZeroDecimals() {
        settings.showZeroDecimals.toggle()
        saveSettings()
        updateStatusItem()
    }

    @objc private func resetSettings() {
        AppSettings.reset()
        settings = AppSettings()
        saveSettings()
        startSampling()
    }

    private func saveSettings() {
        settings.save()
        updateStatusItemWidth()
        rebuildMenu()
    }

    private func title(for rate: NetworkRate) -> String {
        let down = format(rate.downBytesPerSecond)
        let up = format(rate.upBytesPerSecond)

        switch settings.displayStyle {
        case .arrows:
            return "↓ \(down)  ↑ \(up)"
        case .labels:
            return "D \(down)  U \(up)"
        case .compact:
            return "\(down)/\(up)"
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
        let base = settings.scaleMode == .binary ? 1024.0 : 1000.0
        let units = unitsForCurrentSettings()
        var value = (bytesPerSecond * multiplier) / base
        var unitIndex = 0

        while value >= base, unitIndex < units.count - 1 {
            value /= base
            unitIndex += 1
        }

        let formattedNumber: String
        if value >= 100, !settings.showZeroDecimals {
            formattedNumber = "\(Int(value.rounded()))"
        } else if value == 0, !settings.showZeroDecimals {
            formattedNumber = "0"
        } else {
            formattedNumber = String(format: "%.1f", value)
        }

        let paddedNumber = String(repeating: " ", count: max(0, 4 - formattedNumber.count)) + formattedNumber
        return "\(paddedNumber) \(units[unitIndex])"
    }

    private func unitsForCurrentSettings() -> [String] {
        switch (settings.unitMode, settings.scaleMode) {
        case (.bytes, .binary):
            return ["KiB/s", "MiB/s", "GiB/s", "TiB/s"]
        case (.bytes, .decimal):
            return ["KB/s", "MB/s", "GB/s", "TB/s"]
        case (.bits, .binary):
            return ["Kib/s", "Mib/s", "Gib/s", "Tib/s"]
        case (.bits, .decimal):
            return ["Kb/s", "Mb/s", "Gb/s", "Tb/s"]
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
