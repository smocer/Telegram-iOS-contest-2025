import ComponentFlow
import GlassBackgroundComponent
import UIKit

final class LiquidChatGlassBackgroundView: ChatInputPanelBackgroundViewType {
    let view: UIView
    let contentView: UIView
    let maskContentView: UIView

    var captureView: UIView? {
        get { metalView.captureView }
        set { metalView.captureView = newValue }
    }

    private let metalView: LiquidChatGlassMetalView
    private var config: LiquidGlassConfig
    private var presentationTint: LiquidGlassTint
    private var isTintLockedToPresentation: Bool = true
    private var lastSettingsTint: LiquidGlassTint

    private var messageState = LiquidChatGlassShapeState(center: .zero, size: .zero, cornerRadius: 0, isEnabled: false)
    private var leftButtonState = LiquidChatGlassShapeState(center: .zero, size: .zero, cornerRadius: 0, isEnabled: false)
    private var rightButtonState = LiquidChatGlassShapeState(center: .zero, size: .zero, cornerRadius: 0, isEnabled: false)

    init(config: LiquidGlassConfig, metalContext: MetalContext) {
        self.config = config
        presentationTint = config.tint
        lastSettingsTint = config.tint

        let containerView = UIView()
        containerView.isUserInteractionEnabled = false
        containerView.backgroundColor = .clear
        view = containerView

        metalView = LiquidChatGlassMetalView(config: config, metalContext: metalContext)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(metalView)
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            metalView.topAnchor.constraint(equalTo: containerView.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        let contentView = UIView()
        contentView.isUserInteractionEnabled = false
        contentView.backgroundColor = .clear
        contentView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: containerView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        self.contentView = contentView

        let maskContentView = UIView()
        maskContentView.isUserInteractionEnabled = false
        maskContentView.backgroundColor = .clear
        self.maskContentView = maskContentView

        metalView.shapesProvider = { [weak self] in
            guard let self else {
                return (
                    LiquidChatGlassShapeState(center: .zero, size: .zero, cornerRadius: 0, isEnabled: false),
                    LiquidChatGlassShapeState(center: .zero, size: .zero, cornerRadius: 0, isEnabled: false),
                    LiquidChatGlassShapeState(center: .zero, size: .zero, cornerRadius: 0, isEnabled: false)
                )
            }
            return (
                self.messageState,
                self.leftButtonState,
                self.rightButtonState
            )
        }

        metalView.roiProvider = { [weak self] in
            guard let self, let captureView = self.metalView.captureView else { return .zero }
            return captureView.convert(self.metalView.bounds, from: self.metalView)
        }
    }

    func updateGlassConfig(_ config: LiquidGlassConfig) {
        let userTintChanged = !isApproximatelyEqual(config.tint, lastSettingsTint)
        lastSettingsTint = config.tint

        var resolvedConfig = config

        if isTintLockedToPresentation {
            if userTintChanged {
                isTintLockedToPresentation = isApproximatelyEqual(resolvedConfig.tint, presentationTint)
            }
        } else {
            if userTintChanged, isApproximatelyEqual(resolvedConfig.tint, presentationTint) {
                isTintLockedToPresentation = true
            }
        }

        if isTintLockedToPresentation {
            resolvedConfig = resolvedConfig.copyWith(tint: presentationTint)
        }

        self.config = resolvedConfig
        metalView.updateSettings(config: resolvedConfig)
    }

    func update(
        size: CGSize,
        cornerRadius: CGFloat,
        isDark: Bool,
        tintColor: GlassBackgroundView.TintColor,
        isInteractive: Bool,
        transition: ComponentTransition
    ) {
        transition.perform { [weak self] in
            guard let self else { return }
            self.presentationTint = tintColor.liquidTint(isDark: isDark)

            guard self.isTintLockedToPresentation else { return }
            let updatedConfig = self.config.copyWith(tint: self.presentationTint)
            guard updatedConfig != self.config else { return }
            self.config = updatedConfig
            self.metalView.updateSettings(config: updatedConfig)
        }
    }

    func updateLayout(
        messageFrame: CGRect,
        messageCornerRadius: CGFloat,
        leftButtonFrame: CGRect,
        leftButtonCornerRadius: CGFloat,
        rightButtonFrame: CGRect,
        rightButtonCornerRadius: CGFloat
    ) {
        messageState = shapeState(frame: messageFrame, cornerRadius: messageCornerRadius, direction: CGVector(dx: 1, dy: 0))
        leftButtonState = shapeState(frame: leftButtonFrame, cornerRadius: leftButtonCornerRadius, direction: CGVector(dx: 1, dy: 0))
        rightButtonState = shapeState(frame: rightButtonFrame, cornerRadius: rightButtonCornerRadius, direction: CGVector(dx: 1, dy: 0))

        metalView.setNeedsDisplay()
    }

    func setSideButtonStates(left: LiquidChatGlassShapeState, right: LiquidChatGlassShapeState) {
        leftButtonState = left
        rightButtonState = right
        metalView.setNeedsDisplay()
    }

    func invalidateBackgroundCapture() {
        metalView.invalidateBackgroundCapture()
    }
}

private func isApproximatelyEqual(_ a: LiquidGlassTint, _ b: LiquidGlassTint, epsilon: Float = 0.001) -> Bool {
    abs(a.r - b.r) <= epsilon &&
        abs(a.g - b.g) <= epsilon &&
        abs(a.b - b.b) <= epsilon &&
        abs(a.a - b.a) <= epsilon
}

private extension LiquidChatGlassBackgroundView {
    func shapeState(frame: CGRect, cornerRadius: CGFloat, direction: CGVector) -> LiquidChatGlassShapeState {
        let enabled = frame.width > 0.1 && frame.height > 0.1
        let minSide = max(0.001, min(frame.width, frame.height))
        let resolvedCornerRadius = min(cornerRadius, minSide / 2)
        return LiquidChatGlassShapeState(
            center: CGPoint(x: frame.midX, y: frame.midY),
            size: frame.size,
            cornerRadius: resolvedCornerRadius,
            isEnabled: enabled,
            direction: direction
        )
    }
}
