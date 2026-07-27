import AppKit
import Foundation
import NetStatCore
import XCTest
@testable import NetStatBar

final class AppBehaviorTests: XCTestCase {
    func testStatusTitlePreservesDualAndNarrowLayouts() {
        let rate = NetworkRate(downBytesPerSecond: 1_000, upBytesPerSecond: 2_000)

        XCTAssertEqual(
            StatusTitleFormatter.title(
                for: rate,
                displayStyle: .arrows,
                unitMode: .bytes,
                isNarrow: false
            ),
            "↓   1 KB/s  ↑   2 KB/s"
        )
        XCTAssertEqual(
            StatusTitleFormatter.title(
                for: rate,
                displayStyle: .labels,
                unitMode: .bytes,
                isNarrow: true
            ),
            "D   1 KB/s"
        )
    }

    func testInvalidPersistedLayoutValuesFallBackToDefaults() throws {
        let suiteName = "NetStatBarTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(1_000, forKey: "customItemWidth")
        defaults.set(-5, forKey: "fontSize")
        defaults.set("ultraviolet", forKey: "appearance")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.customItemWidth, AppSettings.defaults.customItemWidth)
        XCTAssertEqual(settings.fontSize, AppSettings.defaults.fontSize)
        XCTAssertEqual(settings.appearance, .system)
    }

    @MainActor
    func testDashboardUsesOpaqueDarkSurface() throws {
        let dashboard = DashboardMenuView()
        let panel = DashboardPanel(
            contentRect: NSRect(origin: .zero, size: DashboardMenuView.preferredSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = dashboard
        dashboard.appearance = NSAppearance(named: .darkAqua)
        dashboard.viewDidChangeEffectiveAppearance()

        let color = try renderedCenterColor(of: dashboard)
        XCTAssertTrue(dashboard.isOpaque)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001)
        XCTAssertEqual(color.redComponent, 0, accuracy: 0.001)
        XCTAssertTrue(panel.isOpaque)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
        let windowColor = try XCTUnwrap(panel.backgroundColor.usingColorSpace(.sRGB))
        XCTAssertEqual(windowColor.redComponent, 0, accuracy: 0.001)
        XCTAssertEqual(windowColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertEqual(dashboard.frame.size, DashboardMenuView.preferredSize)
    }

    @MainActor
    func testDashboardUsesOpaqueWhiteSurface() throws {
        let dashboard = DashboardMenuView()
        let panel = DashboardPanel(
            contentRect: NSRect(origin: .zero, size: DashboardMenuView.preferredSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = dashboard
        dashboard.appearance = NSAppearance(named: .aqua)
        dashboard.viewDidChangeEffectiveAppearance()

        let color = try renderedCenterColor(of: dashboard)
        XCTAssertEqual(color.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 1, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 1, accuracy: 0.001)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001)
        XCTAssertTrue(panel.isOpaque)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.001)
    }

    @MainActor
    func testDashboardPanelCanBecomeKey() {
        let panel = DashboardPanel(
            contentRect: NSRect(origin: .zero, size: DashboardMenuView.preferredSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }

    @MainActor
    func testDashboardPreferencesButtonInvokesItsAction() throws {
        let dashboard = DashboardMenuView()
        var invoked = false
        dashboard.onPreferences = { receivedDashboard in
            invoked = receivedDashboard === dashboard
        }

        let button = try XCTUnwrap(
            dashboard.subviews
                .compactMap { $0 as? NSButton }
                .first { $0.title == "Preferences" }
        )
        XCTAssertEqual(button.frame.minX, 8)
        XCTAssertEqual(
            button.frame.minX + DashboardActionButton.horizontalContentInset,
            16
        )
        XCTAssertEqual(
            dashboard.bounds.maxX - button.frame.maxX,
            8
        )
        XCTAssertEqual(button.imagePosition, .imageTrailing)
        XCTAssertNotNil(button.image)
        button.performClick(nil)

        XCTAssertTrue(invoked)

        let quitButton = try XCTUnwrap(
            dashboard.subviews
                .compactMap { $0 as? NSButton }
                .first { $0.title == "Quit NetStatBar" }
        )
        XCTAssertEqual(dashboard.bounds.maxY - quitButton.frame.maxY, 4)
        let quitColor = try XCTUnwrap(
            quitButton.attributedTitle.attribute(
                .foregroundColor,
                at: 0,
                effectiveRange: nil
            ) as? NSColor
        )
        XCTAssertEqual(quitColor, .systemRed)
    }

    @MainActor
    func testDashboardActionButtonsUseAdaptiveHoverStates() throws {
        let dashboard = DashboardMenuView()
        dashboard.appearance = NSAppearance(named: .darkAqua)
        dashboard.viewDidChangeEffectiveAppearance()

        let buttons = dashboard.subviews.compactMap { $0 as? DashboardActionButton }
        let preferences = try XCTUnwrap(buttons.first { $0.title == "Preferences" })
        let quit = try XCTUnwrap(buttons.first { $0.title == "Quit NetStatBar" })

        preferences.setHovered(true, animated: false)
        XCTAssertTrue(preferences.isHovered)
        let preferencesColor = try layerBackgroundColor(of: preferences)
        XCTAssertGreaterThan(preferencesColor.alphaComponent, 0)

        preferences.setHovered(false, animated: false)
        XCTAssertFalse(preferences.isHovered)
        XCTAssertEqual(
            try layerBackgroundColor(of: preferences).alphaComponent,
            0,
            accuracy: 0.001
        )

        quit.setHovered(true, animated: false)
        let quitColor = try layerBackgroundColor(of: quit)
        XCTAssertGreaterThan(quitColor.redComponent, quitColor.greenComponent)
        XCTAssertGreaterThan(quitColor.alphaComponent, preferencesColor.alphaComponent)
    }

    @MainActor
    private func renderedCenterColor(of view: NSView) throws -> NSColor {
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        return try XCTUnwrap(
            representation.colorAt(
                x: representation.pixelsWide / 2,
                y: representation.pixelsHigh / 2
            )?.usingColorSpace(.sRGB)
        )
    }

    @MainActor
    private func layerBackgroundColor(of view: NSView) throws -> NSColor {
        let color = try XCTUnwrap(view.layer?.backgroundColor)
        return try XCTUnwrap(NSColor(cgColor: color)?.usingColorSpace(.sRGB))
    }

}
