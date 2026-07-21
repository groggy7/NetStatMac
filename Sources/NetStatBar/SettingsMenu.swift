import AppKit
import NetStatCore

extension AppDelegate {
    func rebuildMenu() {
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

        let currentWidth = settings.customItemWidth > 0
            ? settings.customItemWidth
            : calculatedAutoWidth()
        let sliderView = SliderMenuView(
            title: "Custom Width:",
            currentValue: currentWidth,
            range: AppSettings.itemWidthRange
        )
        sliderView.onChange = { [weak self] width in
            guard let self else { return }
            settings.customItemWidth = width
            saveSettings()
            updateStatusItemWidth()
            updateStatusItem()
        }

        let sliderMenuItem = NSMenuItem()
        sliderMenuItem.view = sliderView
        menu.addItem(sliderMenuItem)

        return menu
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

        let sliderView = SliderMenuView(
            title: "Font Size:",
            currentValue: settings.fontSize,
            range: AppSettings.fontSizeRange
        )
        sliderView.onChange = { [weak self] size in
            guard let self else { return }
            settings.fontSize = size
            saveSettings()
            updateFont()
            updateStatusItemWidth()
            updateStatusItem()
        }

        let sliderMenuItem = NSMenuItem()
        sliderMenuItem.view = sliderView
        menu.addItem(sliderMenuItem)

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

    @objc private func setFontSizePreset(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Double else { return }
        settings.fontSize = size
        saveSettings()
        updateFont()
        updateStatusItemWidth()
        updateStatusItem()
    }

    @objc private func setUpdateInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
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
}
