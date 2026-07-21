import AppKit
import NetStatCore

final class DashboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension AppDelegate {
    func configureDashboardPanel() {
        let dashboard = DashboardMenuView()
        let panel = DashboardPanel(
            contentRect: NSRect(origin: .zero, size: DashboardMenuView.preferredSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = dashboard
        panel.backgroundColor = .white
        panel.isOpaque = true
        panel.alphaValue = 1
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]

        dashboardPanel = panel
        dashboardView = dashboard
        dashboard.onPreferences = { [weak self] dashboard in
            self?.showPreferencesMenu(from: dashboard)
        }
        dashboard.onQuit = {
            NSApp.terminate(nil)
        }
        updateDashboard()
        applyAppearance()
    }

    @objc func toggleDashboardPanel() {
        if isDashboardOpen {
            closeDashboardPanel()
        } else {
            showDashboardPanel()
        }
    }

    func showDashboardPanel() {
        guard let dashboardPanel, let dashboardView else { return }

        positionDashboardPanel(dashboardPanel)
        isDashboardOpen = true
        updateDashboard()
        if hasProcessActivitySnapshot {
            dashboardView.update(
                processes: latestProcessActivities,
                unitMode: settings.unitMode
            )
        } else {
            dashboardView.showProcessMeasurementPending()
        }
        dashboardPanel.orderFrontRegardless()
        installDashboardEventMonitors()
        startProcessMonitoring(for: dashboardView)
    }

    func closeDashboardPanel() {
        guard isDashboardOpen else { return }

        isDashboardOpen = false
        processSamplingTask?.cancel()
        processSamplingTask = nil
        dashboardPanel?.resignKey()
        dashboardPanel?.orderOut(nil)
        removeDashboardEventMonitors()
    }

    func removeDashboardEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    func updateDashboard() {
        dashboardView?.update(
            rate: lastRate,
            usage: usageTracker.summary(),
            history: rateHistory.points,
            unitMode: settings.unitMode
        )
    }

    private func startProcessMonitoring(for dashboard: DashboardMenuView) {
        processSamplingTask?.cancel()

        let worker = processSamplingWorker
        processSamplingTask = Task { [weak self, weak dashboard] in
            while !Task.isCancelled {
                let records = await worker.sampleTopProcesses()
                guard !Task.isCancelled,
                      let self,
                      let dashboard,
                      isDashboardOpen,
                      dashboardView === dashboard else {
                    return
                }

                let activities = ProcessActivityPresenter.topActivities(from: records)
                latestProcessActivities = activities
                hasProcessActivitySnapshot = true
                dashboard.update(
                    processes: activities,
                    unitMode: settings.unitMode
                )

                do {
                    // nettop itself samples for one second. This short pause prevents
                    // a tight retry loop if it exits early or temporarily fails.
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
            }
        }
    }

    private func positionDashboardPanel(_ panel: NSPanel) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let buttonInWindow = button.convert(button.bounds, to: nil)
        let buttonOnScreen = buttonWindow.convertToScreen(buttonInWindow)
        let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(
            x: buttonOnScreen.midX - panel.frame.width / 2,
            y: buttonOnScreen.minY - panel.frame.height - 5
        )

        origin.x = min(max(origin.x, visibleFrame.minX + 6), visibleFrame.maxX - panel.frame.width - 6)
        if origin.y < visibleFrame.minY + 6 {
            origin.y = buttonOnScreen.maxY + 5
        }

        panel.setFrameOrigin(NSPoint(x: round(origin.x), y: round(origin.y)))
    }

    private func installDashboardEventMonitors() {
        removeDashboardEventMonitors()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                closeDashboardPanel()
                return nil
            }

            if event.window === dashboardPanel || event.window === statusItem.button?.window {
                return event
            }

            closeDashboardPanel()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeDashboardPanel()
            }
        }
    }

    private func showPreferencesMenu(from dashboard: DashboardMenuView) {
        guard let panel = dashboardPanel else { return }

        let anchorInWindow = dashboard.convert(
            NSPoint(x: dashboard.bounds.maxX - 2, y: 317),
            to: nil
        )
        let anchorOnScreen = panel.convertPoint(toScreen: anchorInWindow)
        let menu = preferencesMenu()
        menu.appearance = panel.appearance

        menu.popUp(positioning: nil, at: anchorOnScreen, in: nil)
    }

    private func preferencesMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(parentMenuItem(title: "Appearance", submenu: appearanceMenu()))
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

        let resetUsage = NSMenuItem(
            title: "Reset Usage Statistics",
            action: #selector(resetUsageStatistics),
            keyEquivalent: ""
        )
        resetUsage.target = self
        menu.addItem(resetUsage)

        return menu
    }

    private func appearanceMenu() -> NSMenu {
        let menu = NSMenu()

        for appearance in AppAppearance.allCases {
            let item = NSMenuItem(
                title: appearance.title,
                action: #selector(setAppearance(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = appearance.rawValue
            item.state = settings.appearance == appearance ? .on : .off
            menu.addItem(item)
        }

        return menu
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

    @objc private func setAppearance(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let appearance = AppAppearance(rawValue: rawValue) else {
            return
        }

        settings.appearance = appearance
        saveSettings()
        applyAppearance()
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
        applyAppearance()
        updateFont()
        updateStatusItemWidth()
        startSampling()
    }

    @objc private func resetUsageStatistics() {
        usageTracker.reset()
        updateDashboard()
    }
}
