import AppKit
import NetStatCore

extension AppDelegate {
    func configureStatusItem() {
        updateFont()
        statusItem.button?.alignment = .center
        statusItem.button?.lineBreakMode = .byClipping
        statusItem.button?.cell?.wraps = false
        updateStatusItemWidth()
        rebuildMenu()
        updateStatusItem()
    }

    func updateFont() {
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(
            ofSize: settings.fontSize,
            weight: .regular
        )
    }

    func updateStatusItemWidth() {
        if settings.customItemWidth > 0 {
            statusItem.length = settings.customItemWidth
        } else {
            statusItem.length = calculatedAutoWidth()
        }
    }

    func calculatedAutoWidth() -> Double {
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

    func updateStatusItem() {
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

    func intervalTitle(_ interval: TimeInterval) -> String {
        if interval == floor(interval) {
            return "\(Int(interval)) second\(interval == 1 ? "" : "s")"
        }

        return String(format: "%.1f seconds", interval)
    }

    private func title(for rate: NetworkRate) -> String {
        let down = format(rate.downBytesPerSecond)
        let up = format(rate.upBytesPerSecond)

        if statusItem.length > 0 && statusItem.length < 120 {
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

    private func format(_ bytesPerSecond: Double) -> String {
        RateFormatter.string(fromBytesPerSecond: bytesPerSecond, unitMode: settings.unitMode)
    }
}
