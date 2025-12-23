import Display
import UIKit

final class LiquidChatAttachmentButton: ChatTextInputAttachmentButtonType {
    let view: UIView
    let backgroundView: ChatInputPanelBackgroundViewType
    let disabledOverlayView: UIView

    var onPressed: (() -> Void)?
    var onHighlightedChanged: ((Bool) -> Void)?
    var onTrackingLocationChanged: ((CGPoint?) -> Void)?

    private let control = TrackingControl()
    private let imageView = UIImageView()
    private struct TapTrackingState {
        var startPoint: CGPoint?
        var didExceedTapThreshold: Bool
    }
    private var tapTrackingState = TapTrackingState(startPoint: nil, didExceedTapThreshold: false)
    private var isHighlightedInternal = false {
        didSet {
            guard isHighlightedInternal != oldValue else { return }
            onHighlightedChanged?(isHighlightedInternal)
        }
    }

    init(backgroundView: ChatInputPanelBackgroundViewType) {
        self.backgroundView = backgroundView

        control.backgroundColor = .clear
        control.isExclusiveTouch = true
        view = control

        imageView.contentMode = .scaleToFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: control.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22)
        ])

        disabledOverlayView = UIView()
        disabledOverlayView.backgroundColor = UIColor(white: 0, alpha: 0.12)
        disabledOverlayView.isUserInteractionEnabled = false
        disabledOverlayView.alpha = 0
        disabledOverlayView.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(disabledOverlayView)
        NSLayoutConstraint.activate([
            disabledOverlayView.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            disabledOverlayView.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            disabledOverlayView.topAnchor.constraint(equalTo: control.topAnchor),
            disabledOverlayView.bottomAnchor.constraint(equalTo: control.bottomAnchor)
        ])

        control.addTarget(self, action: #selector(handleTouchDown), for: .touchDown)
        control.addTarget(self, action: #selector(handleTouchUpInside), for: .touchUpInside)
        control.addTarget(self, action: #selector(handleTouchUp), for: .touchUpOutside)
        control.addTarget(self, action: #selector(handleTouchUp), for: .touchCancel)

	        control.onLocationChanged = { [weak self] location in
	            guard let self else { return }
	            guard let location else {
	                self.tapTrackingState.startPoint = nil
	                self.tapTrackingState.didExceedTapThreshold = false
	                self.onTrackingLocationChanged?(nil)
	                return
	            }

	            if let start = self.tapTrackingState.startPoint {
	                let dx = location.x - start.x
	                let dy = location.y - start.y
	                if hypot(dx, dy) > 12 {
	                    self.tapTrackingState.didExceedTapThreshold = true
	                }
	            } else {
	                self.tapTrackingState.startPoint = location
	                self.tapTrackingState.didExceedTapThreshold = false
	            }

	            self.onTrackingLocationChanged?(location)
	        }
	    }

    func setIconTransform(_ transform: CGAffineTransform) {
        imageView.transform = transform
    }

    func update(
        presentation: ChatTextInputAttachmentButtonPresentation,
        size: CGSize,
        cornerRadius: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        transition.updateAlpha(layer: control.layer, alpha: presentation.alpha)
        control.isUserInteractionEnabled = presentation.isEnabled

        control.accessibilityLabel = presentation.accessibilityLabel
        control.accessibilityTraits = presentation.accessibilityTraits
        
        let overlayAlpha: CGFloat = presentation.isDisabledOverlayVisible ? 1.0 : 0.0
        transition.updateAlpha(layer: disabledOverlayView.layer, alpha: overlayAlpha)

        let imageName = imageName(for: presentation.state)
        imageView.image = UIImage(systemName: imageName)
        imageView.tintColor = presentation.iconTintColor

        control.layer.cornerRadius = cornerRadius
        disabledOverlayView.layer.cornerRadius = cornerRadius
        control.clipsToBounds = false
    }
}

private extension LiquidChatAttachmentButton {
    @objc func handleTouchDown() {
        isHighlightedInternal = true
    }

    @objc func handleTouchUpInside() {
        isHighlightedInternal = false
        if !tapTrackingState.didExceedTapThreshold {
            onPressed?()
        }
    }

    @objc func handleTouchUp() {
        isHighlightedInternal = false
    }

    func imageName(for state: ChatTextInputAttachmentButtonVisualState) -> String {
        switch state {
        case .attachment:
            return "paperclip"
        case .editAttachment:
            return "pencil"
        case .delete:
            return "trash"
        case .comments(let isExpanded, let hasUnseen):
            if hasUnseen {
                return isExpanded ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right"
            } else {
                return isExpanded ? "bubble.left.fill" : "bubble.left"
            }
        }
    }
}

private final class TrackingControl: UIControl {
    var onLocationChanged: ((CGPoint?) -> Void)?

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if let superview {
            onLocationChanged?(touch.location(in: superview))
        } else {
            onLocationChanged?(touch.location(in: self))
        }
        return super.beginTracking(touch, with: event)
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if let superview {
            onLocationChanged?(touch.location(in: superview))
        } else {
            onLocationChanged?(touch.location(in: self))
        }
        return super.continueTracking(touch, with: event)
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        onLocationChanged?(nil)
        super.endTracking(touch, with: event)
    }

    override func cancelTracking(with event: UIEvent?) {
        onLocationChanged?(nil)
        super.cancelTracking(with: event)
    }
}
