import UIKit

final class LiquidChatSettingsView: UIView {
    enum Section: Int {
        case gooey = 0
        case glass = 1
    }

    var onGooeyChanged: ((LiquidChatGooeyTuning) -> Void)?
    var onGlassChanged: ((LiquidGlassConfig) -> Void)?

    private let segmentedControl: UISegmentedControl
    private let containerView = UIView()

    private let gooeySettingsView: LiquidChatGooeySettingsView
    private let glassSettingsView: GlassSettingsView

    init(
        initialGooeyTuning: LiquidChatGooeyTuning,
        initialGlassConfig: LiquidGlassConfig,
        initialSection: Section = .gooey
    ) {
        segmentedControl = UISegmentedControl(items: ["Gooey", "Glass"])
        gooeySettingsView = LiquidChatGooeySettingsView(initialTuning: initialGooeyTuning)
        glassSettingsView = GlassSettingsView(initialConfig: initialGlassConfig)
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        segmentedControl.backgroundColor = .secondarySystemBackground
        segmentedControl.selectedSegmentTintColor = .systemBackground
        segmentedControl.selectedSegmentIndex = initialSection.rawValue
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segmentedControl)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            segmentedControl.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            segmentedControl.heightAnchor.constraint(equalToConstant: 32),

            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 10),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        gooeySettingsView.translatesAutoresizingMaskIntoConstraints = false
        glassSettingsView.translatesAutoresizingMaskIntoConstraints = false
        [gooeySettingsView, glassSettingsView].forEach { view in
            containerView.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                view.topAnchor.constraint(equalTo: containerView.topAnchor),
                view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
        }

        gooeySettingsView.onValuesChanged = { [weak self] tuning in
            self?.onGooeyChanged?(tuning)
        }
        glassSettingsView.onValuesChanged = { [weak self] config in
            self?.onGlassChanged?(config)
        }

        updateSectionVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func segmentChanged() {
        updateSectionVisibility()
    }

    private func updateSectionVisibility() {
        let selected = Section(rawValue: segmentedControl.selectedSegmentIndex) ?? .gooey
        gooeySettingsView.isHidden = selected != .gooey
        glassSettingsView.isHidden = selected != .glass
    }
}
