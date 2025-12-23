import UIKit

final class LiquidChatGooeySettingsView: UIView {
    var onValuesChanged: ((LiquidChatGooeyTuning) -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialLight))
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private struct MutableSettings {
        var maxDragDistanceFactor: Float
        var magnetStrength: Float
        var hardClampFactor: Float

        var centerStiffness: Float
        var centerDamping: Float
        var scaleStiffness: Float
        var scaleDamping: Float

        var pullForMaxDeformationFactor: Float
        var speedForMaxDeformation: Float
        var stretchFactor: Float
        var squashFactor: Float

        var expandedScale: Float

        var pulseCount: Float
        var pulseStartThreshold: Float
        var pulseAmplitude: Float
        var pulseFrequency: Float
        var pulseDecay: Float

        init(tuning: LiquidChatGooeyTuning) {
            maxDragDistanceFactor = Float(tuning.maxDragDistanceFactor)
            magnetStrength = Float(tuning.magnetStrength)
            hardClampFactor = Float(tuning.hardClampFactor)

            centerStiffness = Float(tuning.centerStiffness)
            centerDamping = Float(tuning.centerDamping)
            scaleStiffness = Float(tuning.scaleStiffness)
            scaleDamping = Float(tuning.scaleDamping)

            pullForMaxDeformationFactor = Float(tuning.pullForMaxDeformationFactor)
            speedForMaxDeformation = Float(tuning.speedForMaxDeformation)
            stretchFactor = Float(tuning.stretchFactor)
            squashFactor = Float(tuning.squashFactor)

            expandedScale = Float(tuning.expandedScale)

            pulseCount = Float(tuning.pulseCount)
            pulseStartThreshold = Float(tuning.pulseStartThreshold)
            pulseAmplitude = Float(tuning.pulseAmplitude)
            pulseFrequency = Float(tuning.pulseFrequency)
            pulseDecay = Float(tuning.pulseDecay)
        }

        func asTuning() -> LiquidChatGooeyTuning {
            var tuning = LiquidChatGooeyTuning()
            tuning.maxDragDistanceFactor = CGFloat(maxDragDistanceFactor)
            tuning.magnetStrength = CGFloat(magnetStrength)
            tuning.hardClampFactor = CGFloat(hardClampFactor)

            tuning.centerStiffness = CGFloat(centerStiffness)
            tuning.centerDamping = CGFloat(centerDamping)
            tuning.scaleStiffness = CGFloat(scaleStiffness)
            tuning.scaleDamping = CGFloat(scaleDamping)

            tuning.pullForMaxDeformationFactor = CGFloat(pullForMaxDeformationFactor)
            tuning.speedForMaxDeformation = CGFloat(speedForMaxDeformation)
            tuning.stretchFactor = CGFloat(stretchFactor)
            tuning.squashFactor = CGFloat(squashFactor)

            tuning.expandedScale = CGFloat(expandedScale)

            tuning.pulseCount = CGFloat(pulseCount)
            tuning.pulseStartThreshold = CGFloat(pulseStartThreshold)
            tuning.pulseAmplitude = CGFloat(pulseAmplitude)
            tuning.pulseFrequency = CGFloat(pulseFrequency)
            tuning.pulseDecay = CGFloat(pulseDecay)
            return tuning
        }
    }

    private struct SliderRow {
        var slider: UISlider
        var valueLabel: UILabel
        var set: (inout MutableSettings, Float) -> Void
        var get: (MutableSettings) -> Float
        var format: String
    }

    private var currentSettings: MutableSettings
    private var sliderRows: [SliderRow] = []

    init(initialTuning: LiquidChatGooeyTuning) {
        currentSettings = MutableSettings(tuning: initialTuning)
        super.init(frame: .zero)
        setupView()
        applyInitialValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = .clear

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.clipsToBounds = true
        blurView.layer.cornerRadius = 16
        addSubview(blurView)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            blurView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])

        addSection(title: "Magnet") {
            addSlider(title: "Max drag (x)", range: 0.0...3.50, format: "%.2f", getter: { $0.maxDragDistanceFactor }) { cfg, v in cfg.maxDragDistanceFactor = v }
            addSlider(title: "Magnet strength", range: 0.25...3.00, format: "%.2f", getter: { $0.magnetStrength }) { cfg, v in cfg.magnetStrength = v }
            addSlider(title: "Hard clamp (x)", range: 1.00...1.40, format: "%.2f", getter: { $0.hardClampFactor }) { cfg, v in cfg.hardClampFactor = v }
        }

        addSection(title: "Spring") {
            addSlider(title: "Center stiffness", range: 40...800, format: "%.0f", getter: { $0.centerStiffness }) { cfg, v in cfg.centerStiffness = v }
            addSlider(title: "Center damping", range: 1...120, format: "%.0f", getter: { $0.centerDamping }) { cfg, v in cfg.centerDamping = v }
            addSlider(title: "Scale stiffness", range: 40...900, format: "%.0f", getter: { $0.scaleStiffness }) { cfg, v in cfg.scaleStiffness = v }
            addSlider(title: "Scale damping", range: 1...140, format: "%.0f", getter: { $0.scaleDamping }) { cfg, v in cfg.scaleDamping = v }
        }

        addSection(title: "Deformation") {
            addSlider(title: "Pull for max (x)", range: 0.25...30.0, format: "%.2f", getter: { $0.pullForMaxDeformationFactor }) { cfg, v in cfg.pullForMaxDeformationFactor = v }
            addSlider(title: "Speed for max", range: 200...3500, format: "%.0f", getter: { $0.speedForMaxDeformation }) { cfg, v in cfg.speedForMaxDeformation = v }
            addSlider(title: "Stretch factor", range: 0...1.40, format: "%.2f", getter: { $0.stretchFactor }) { cfg, v in cfg.stretchFactor = v }
            addSlider(title: "Squash factor", range: 0...0.90, format: "%.2f", getter: { $0.squashFactor }) { cfg, v in cfg.squashFactor = v }
        }

        addSection(title: "Visual") {
            addSlider(title: "Expanded scale", range: 1.00...2.20, format: "%.2f", getter: { $0.expandedScale }) { cfg, v in cfg.expandedScale = v }
        }

        addSection(title: "Pulse (release)") {
            addSlider(title: "Pulse count", range: 0...8, format: "%.1f", getter: { $0.pulseCount }) { cfg, v in cfg.pulseCount = v }
            addSlider(title: "Start threshold", range: 0.50...1.00, format: "%.2f", getter: { $0.pulseStartThreshold }) { cfg, v in cfg.pulseStartThreshold = v }
            addSlider(title: "Amplitude", range: 0...0.35, format: "%.3f", getter: { $0.pulseAmplitude }) { cfg, v in cfg.pulseAmplitude = v }
            addSlider(title: "Frequency (Hz)", range: 0.50...8.00, format: "%.2f", getter: { $0.pulseFrequency }) { cfg, v in cfg.pulseFrequency = v }
            addSlider(title: "Decay", range: 0.0...12.0, format: "%.2f", getter: { $0.pulseDecay }) { cfg, v in cfg.pulseDecay = v }
        }
    }

    private func addSection(title: String, builder: () -> Void) {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .headline)
        contentStack.addArrangedSubview(label)
        builder()
    }

    private func addSlider(
        title: String,
        range: ClosedRange<Float>,
        format: String,
        getter: @escaping (MutableSettings) -> Float,
        setter: @escaping (inout MutableSettings, Float) -> Void
    ) {
        let slider = UISlider()
        slider.minimumValue = range.lowerBound
        slider.maximumValue = range.upperBound

        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        valueLabel.textColor = .secondaryLabel
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: {
            let label = UILabel()
            label.text = title
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.setContentHuggingPriority(.required, for: .horizontal)
            return [label, slider, valueLabel]
        }())
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        contentStack.addArrangedSubview(row)

        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        sliderRows.append(SliderRow(slider: slider, valueLabel: valueLabel, set: setter, get: getter, format: format))
    }

    private func applyInitialValues() {
        for entry in sliderRows {
            entry.slider.setValue(entry.get(currentSettings), animated: false)
            entry.valueLabel.text = String(format: entry.format, entry.slider.value)
        }
        emitValues()
    }

    @objc
    private func sliderChanged(_ sender: UISlider) {
        for entry in sliderRows where entry.slider === sender {
            entry.valueLabel.text = String(format: entry.format, sender.value)
            entry.set(&currentSettings, sender.value)
        }
        emitValues()
    }

    private func emitValues() {
        onValuesChanged?(currentSettings.asTuning())
    }
}
