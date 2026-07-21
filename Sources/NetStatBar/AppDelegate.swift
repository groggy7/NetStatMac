import AppKit
import NetStatCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let sampler = NetworkSampler()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var timer: Timer?
    var settings = AppSettings()
    var lastRate = NetworkRate.zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        startSampling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    func startSampling() {
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

    func saveSettings() {
        settings.save()
    }
}
