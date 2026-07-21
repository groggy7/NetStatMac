import AppKit

@MainActor
final class SliderMenuView: NSView {
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "")
    var onChange: ((Double) -> Void)?

    init(title: String, currentValue: Double, range: ClosedRange<Double>) {
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 32))

        let initialValue = min(max(currentValue, range.lowerBound), range.upperBound)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.frame = NSRect(x: 14, y: 7, width: 90, height: 18)

        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = initialValue
        slider.frame = NSRect(x: 108, y: 6, width: 70, height: 18)
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.isContinuous = true

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = NSColor.secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 178, y: 7, width: 34, height: 18)
        updateValueLabel(initialValue)

        addSubview(titleLabel)
        addSubview(slider)
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let value = sender.doubleValue.rounded()
        updateValueLabel(value)
        onChange?(value)
    }

    private func updateValueLabel(_ value: Double) {
        valueLabel.stringValue = "\(Int(value.rounded())) pt"
    }
}
