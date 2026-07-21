import AppKit
import NetStatCore

@MainActor
final class DashboardMenuView: NSView {
    static let preferredSize = NSSize(width: 308, height: 370)

    private let downloadLabel = NSTextField(labelWithString: "")
    private let uploadLabel = NSTextField(labelWithString: "")
    private let trafficChart = TrafficChartView()
    private let usageValueLabels = (0..<3).map { _ in NSTextField(labelWithString: "") }
    private let processIconViews = (0..<3).map { _ in NSImageView() }
    private let processNameLabels = (0..<3).map { _ in NSTextField(labelWithString: "") }
    private let processRateLabels = (0..<3).map { _ in NSTextField(labelWithString: "") }
    var onPreferences: ((DashboardMenuView) -> Void)?
    var onQuit: (() -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var allowsVibrancy: Bool { false }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.isOpaque = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        setupView()
        updatePanelBackground()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        panelBackgroundColor.setFill()
        bounds.fill()

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let borderColor = isDark
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.black.withAlphaComponent(0.12)
        borderColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.25, dy: 0.25))
        border.lineWidth = 0.5
        border.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePanelBackground()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePanelBackground()
    }

    func refreshAppearance() {
        updatePanelBackground()
    }

    func update(
        rate: NetworkRate,
        usage: UsageSummary,
        history: [RateHistoryPoint],
        unitMode: UnitMode
    ) {
        downloadLabel.stringValue = "↓ \(formattedRate(rate.downBytesPerSecond, unitMode: unitMode))"
        uploadLabel.stringValue = "↑ \(formattedRate(rate.upBytesPerSecond, unitMode: unitMode))"
        trafficChart.update(points: history)

        let usageAmounts = [usage.today, usage.month, usage.year]
        for (label, amount) in zip(usageValueLabels, usageAmounts) {
            label.stringValue = DataAmountFormatter.string(bytes: amount.totalBytes)
            label.toolTip = "Downloaded \(DataAmountFormatter.string(bytes: amount.downloadedBytes)) · Uploaded \(DataAmountFormatter.string(bytes: amount.uploadedBytes))"
        }
    }

    func showProcessMeasurementPending() {
        setProcessRows(message: "Measuring…")
    }

    func update(processes: [ProcessActivity], unitMode: UnitMode) {
        guard !processes.isEmpty else {
            setProcessRows(message: "No active traffic")
            return
        }

        for index in processNameLabels.indices {
            guard index < processes.count else {
                clearProcessRow(at: index)
                continue
            }

            let process = processes[index]
            processIconViews[index].image = process.icon
                ?? NSImage(systemSymbolName: "app", accessibilityDescription: process.name)
            processNameLabels[index].stringValue = process.name
            processNameLabels[index].toolTip = process.name
            processRateLabels[index].stringValue = formattedRate(
                Double(process.totalBytesPerSecond),
                unitMode: unitMode
            )
        }
    }

    private func setupView() {
        addSubview(makeLabel(
            "NetStatBar",
            frame: NSRect(x: 16, y: 13, width: 108, height: 20),
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .labelColor
        ))

        configureRateLabel(
            downloadLabel,
            frame: NSRect(x: 125, y: 14, width: 99, height: 18),
            color: .systemBlue
        )
        configureRateLabel(
            uploadLabel,
            frame: NSRect(x: 225, y: 14, width: 68, height: 18),
            color: .systemGreen
        )
        addSubview(downloadLabel)
        addSubview(uploadLabel)

        addSubview(sectionLabel("LAST 60 SECONDS", y: 48))
        trafficChart.frame = NSRect(x: 16, y: 68, width: 276, height: 48)
        addSubview(trafficChart)

        addSubview(MenuSeparatorView(frame: NSRect(x: 16, y: 125, width: 276, height: 1)))

        let usageTitles = ["Today", "This Month", "This Year"]
        let columnOrigins = [16.0, 112.0, 208.0]
        for index in usageTitles.indices {
            addSubview(makeLabel(
                usageTitles[index],
                frame: NSRect(x: columnOrigins[index], y: 136, width: 84, height: 16),
                font: .systemFont(ofSize: 10),
                color: .secondaryLabelColor
            ))

            let valueLabel = usageValueLabels[index]
            valueLabel.frame = NSRect(x: columnOrigins[index], y: 155, width: 84, height: 18)
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            valueLabel.textColor = .labelColor
            addSubview(valueLabel)
        }

        addSubview(MenuSeparatorView(frame: NSRect(x: 105, y: 136, width: 1, height: 38)))
        addSubview(MenuSeparatorView(frame: NSRect(x: 201, y: 136, width: 1, height: 38)))
        addSubview(MenuSeparatorView(frame: NSRect(x: 16, y: 181, width: 276, height: 1)))
        addSubview(sectionLabel("ACTIVE NOW", y: 193))

        for index in processNameLabels.indices {
            let y = 215.0 + Double(index) * 29
            let iconView = processIconViews[index]
            iconView.frame = NSRect(x: 16, y: y, width: 21, height: 21)
            iconView.imageScaling = .scaleProportionallyUpOrDown
            addSubview(iconView)

            let nameLabel = processNameLabels[index]
            nameLabel.frame = NSRect(x: 46, y: y + 2, width: 178, height: 18)
            nameLabel.font = .systemFont(ofSize: 11.5)
            nameLabel.textColor = .labelColor
            nameLabel.lineBreakMode = .byTruncatingTail
            addSubview(nameLabel)

            let rateLabel = processRateLabels[index]
            rateLabel.frame = NSRect(x: 226, y: y + 2, width: 66, height: 18)
            rateLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            rateLabel.textColor = .secondaryLabelColor
            rateLabel.alignment = .right
            addSubview(rateLabel)
        }

        addSubview(MenuSeparatorView(frame: NSRect(x: 16, y: 303, width: 276, height: 1)))

        let preferencesButton = actionButton(
            title: "Preferences",
            action: #selector(openPreferences),
            frame: NSRect(x: 16, y: 308, width: 276, height: 27)
        )
        addSubview(preferencesButton)
        addSubview(makeLabel(
            "›",
            frame: NSRect(x: 278, y: 310, width: 14, height: 19),
            font: .systemFont(ofSize: 18, weight: .regular),
            color: .labelColor
        ))

        addSubview(MenuSeparatorView(frame: NSRect(x: 16, y: 338, width: 276, height: 1)))
        addSubview(actionButton(
            title: "Quit NetStatBar",
            action: #selector(quitApplication),
            frame: NSRect(x: 16, y: 341, width: 276, height: 25),
            color: .systemRed
        ))

        setProcessRows(message: "Open menu to measure")
    }

    private var panelBackgroundColor: NSColor {
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        if match == .darkAqua {
            return .black
        }
        return .white
    }

    private func updatePanelBackground() {
        let backgroundColor = panelBackgroundColor
        layer?.backgroundColor = backgroundColor.cgColor
        window?.backgroundColor = backgroundColor
        window?.isOpaque = true
        window?.alphaValue = 1
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.borderColor = (isDark
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.black.withAlphaComponent(0.12)).cgColor
        needsDisplay = true
    }

    private func configureRateLabel(_ label: NSTextField, frame: NSRect, color: NSColor) {
        label.frame = frame
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = color
        label.alignment = .right
        label.lineBreakMode = .byClipping
    }

    private func sectionLabel(_ text: String, y: Double) -> NSTextField {
        makeLabel(
            text,
            frame: NSRect(x: 16, y: y, width: 276, height: 15),
            font: .systemFont(ofSize: 9.5, weight: .semibold),
            color: .secondaryLabelColor
        )
    }

    private func makeLabel(
        _ text: String,
        frame: NSRect,
        font: NSFont,
        color: NSColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = font
        label.textColor = color
        return label
    }

    private func actionButton(
        title: String,
        action: Selector,
        frame: NSRect,
        color: NSColor = .labelColor
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = frame
        button.isBordered = false
        button.font = .systemFont(ofSize: 12)
        button.alignment = .left
        button.contentTintColor = color
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: color
            ]
        )
        button.focusRingType = .none
        return button
    }

    @objc private func openPreferences() {
        onPreferences?(self)
    }

    @objc private func quitApplication() {
        onQuit?()
    }

    private func setProcessRows(message: String) {
        for index in processNameLabels.indices {
            clearProcessRow(at: index)
            if index == 0 {
                processNameLabels[index].stringValue = message
            }
        }
    }

    private func clearProcessRow(at index: Int) {
        processIconViews[index].image = nil
        processNameLabels[index].stringValue = ""
        processNameLabels[index].toolTip = nil
        processRateLabels[index].stringValue = ""
    }

    private func formattedRate(_ bytesPerSecond: Double, unitMode: UnitMode) -> String {
        RateFormatter.string(fromBytesPerSecond: bytesPerSecond, unitMode: unitMode)
            .trimmingCharacters(in: .whitespaces)
    }
}

@MainActor
private final class TrafficChartView: NSView {
    private var points: [RateHistoryPoint] = []

    override var isFlipped: Bool { false }

    func update(points: [RateHistoryPoint]) {
        self.points = points
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawGuide(at: bounds.height * 0.34)
        drawGuide(at: bounds.height * 0.68)

        guard !points.isEmpty else { return }
        drawSeries(
            values: points.map(\.rate.downBytesPerSecond),
            color: .systemBlue,
            baseline: bounds.height * 0.54,
            trackHeight: bounds.height * 0.40
        )
        drawSeries(
            values: points.map(\.rate.upBytesPerSecond),
            color: .systemGreen,
            baseline: bounds.height * 0.08,
            trackHeight: bounds.height * 0.28
        )
    }

    private func drawGuide(at y: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: y))
        path.line(to: NSPoint(x: bounds.width, y: y))
        path.lineWidth = 0.5
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        path.stroke()
    }

    private func drawSeries(
        values: [Double],
        color: NSColor,
        baseline: CGFloat,
        trackHeight: CGFloat
    ) {
        let safeValues = values.map { $0.isFinite ? max(0, $0) : 0 }
        guard let maximum = safeValues.max(), maximum > 0 else { return }

        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.lineCapStyle = .round

        let latestTimestamp = points.last?.timestamp ?? 0
        let startTimestamp = latestTimestamp - 60

        for index in points.indices {
            let elapsed = max(0, min(60, points[index].timestamp - startTimestamp))
            let x = CGFloat(elapsed / 60) * bounds.width
            let normalizedValue = safeValues[index] / maximum
            let y = baseline + CGFloat(normalizedValue) * trackHeight
            let point = NSPoint(x: x, y: y)

            if index == points.startIndex {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }

        color.setStroke()
        path.stroke()

        if points.count == 1 {
            let point = path.currentPoint
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)).fill()
        }
    }
}

private final class MenuSeparatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        bounds.fill()
    }
}
