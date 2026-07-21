import AppKit
import NetStatCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let samplingWorker = NetworkSamplingWorker()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var samplingTask: Task<Void, Never>?
    var settings = AppSettings()
    var lastRate = NetworkRate.zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        startSampling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        samplingTask?.cancel()
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
            _ = await samplingWorker.sampleRate(interfaceMode: interfaceMode)

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }

                let rate = await samplingWorker.sampleRate(interfaceMode: interfaceMode)
                guard !Task.isCancelled, let self else { return }
                lastRate = rate
                updateStatusItem()
            }
        }
    }

    func saveSettings() {
        settings.save()
    }
}
