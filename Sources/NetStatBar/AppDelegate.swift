import AppKit
import NetStatCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let samplingWorker = NetworkSamplingWorker()
    let processSamplingWorker = ProcessSamplingWorker()
    let usageTracker = UsageTracker()
    let rateHistory = RateHistory()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var samplingTask: Task<Void, Never>?
    var processSamplingTask: Task<Void, Never>?
    var isDashboardOpen = false
    var dashboardPanel: NSPanel?
    var localEventMonitor: Any?
    var globalEventMonitor: Any?
    weak var dashboardView: DashboardMenuView?
    var settings = AppSettings()
    var lastRate = NetworkRate.zero
    var latestProcessActivities: [ProcessActivity] = []
    var hasProcessActivitySnapshot = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        applyAppearance()
        configureStatusItem()
        startSampling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        samplingTask?.cancel()
        processSamplingTask?.cancel()
        removeDashboardEventMonitors()
        usageTracker.flush()
    }

    func startSampling() {
        samplingTask?.cancel()
        lastRate = .zero
        updateStatusItem()

        let interfaceMode = settings.interfaceMode
        let delay = Duration.milliseconds(Int64(settings.updateInterval * 1_000))
        let samplingWorker = samplingWorker

        samplingTask = Task { [weak self] in
            await samplingWorker.reset()
            _ = await samplingWorker.sample(interfaceMode: interfaceMode)

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }

                let measurement = await samplingWorker.sample(interfaceMode: interfaceMode)
                guard !Task.isCancelled, let self else { return }
                lastRate = measurement.rate
                rateHistory.append(
                    measurement.rate,
                    at: ProcessInfo.processInfo.systemUptime
                )
                usageTracker.record(measurement)
                updateStatusItem()
                if isDashboardOpen {
                    updateDashboard()
                }
            }
        }
    }

    func saveSettings() {
        settings.save()
    }

    func applyAppearance() {
        let appearance: NSAppearance?

        switch settings.appearance {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }

        dashboardPanel?.appearance = appearance
        dashboardView?.appearance = appearance
        dashboardView?.refreshAppearance()
    }
}
