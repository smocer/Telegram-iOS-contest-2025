import ComponentFlow
import Display
import UIKit

public final class LiquidChatTextInputPanelChromeView: ChatTextInputPanelChromeViewType {
    static let defaultGlassConfig: LiquidGlassConfig = LiquidGlassConfig(
        refThickness: 18,
        refFactor: 1.35,
        refDispersion: 3,
        glareRange: 0,
        blurRadius: 20,
        tint: LiquidGlassTint(r: 0.92, g: 0.92, b: 0.95, a: 0.22),
        shadowExpand: 3,
        shadowFactor: 10,
        shapeRoundness: 2,
        mergeRate: 0.04
    )

    public let view: UIView

    public let messageContainer: ChatTextInputMessageContainerType
    public let attachmentButton: ChatTextInputAttachmentButtonType
    public let mediaRecordingButton: ChatTextInputMediaRecordingButtonType

    public let textInputHostView: UIView
    public var focusTapView: UIView { textInputHostView }
    public let accessoryPanelHostView: UIView
    public let contextPanelHostView: UIView

    public var gesturePolicy: ChatTextInputPanelChromeGesturePolicy {
        ChatTextInputPanelChromeGesturePolicy(
            interactiveTransitionEdgeOnlyViews: [
                attachmentButton.view,
                mediaRecordingButton.view
            ],
            interactiveTransitionDisabledViews: [
                attachmentButton.view
            ],
            interactiveKeyboardDisabledViews: [
                attachmentButton.view,
                mediaRecordingButton.view
            ]
        )
    }

    private let glassBackgroundView: LiquidChatGlassBackgroundView
    private let attachmentButtonImpl: LiquidChatAttachmentButton
    private let mediaRecordingButtonImpl: LiquidChatMediaRecordingButton
    private var glassConfigValue: LiquidGlassConfig

    var glassConfig: LiquidGlassConfig {
        get { glassConfigValue }
        set {
            glassConfigValue = newValue
            glassBackgroundView.updateGlassConfig(newValue)
        }
    }

    var gooeyTuning: LiquidChatGooeyTuning = .init() {
        didSet {
            if leftGooey.targetScale != 1 {
                leftGooey.targetScale = gooeyTuning.expandedScale
                startDisplayLinkIfNeeded()
            }
            if rightGooey.targetScale != 1 {
                rightGooey.targetScale = gooeyTuning.expandedScale
                startDisplayLinkIfNeeded()
            }
        }
    }

    private struct GooeyButtonState {
        var restFrame: CGRect = .zero
        var currentCenter: CGPoint = .zero
        var targetCenter: CGPoint = .zero
        var velocity: CGVector = .zero

        var trackingLocation: CGPoint?
        var grabOffset: CGVector = .zero

        var scale: CGFloat = 1.0
        var scaleVelocity: CGFloat = 0.0
        var targetScale: CGFloat = 1.0

        var lastDirection: CGVector = CGVector(dx: 1, dy: 0)

        var isHighlighted: Bool = false

        var releasePulseArmed: Bool = false
        var releaseStartScale: CGFloat = 1.0
        var pulseElapsed: CGFloat = 0
        var pulseDuration: CGFloat = 0

        mutating func setRestFrame(_ frame: CGRect) {
            let hadRest = restFrame.width > 0.1 && restFrame.height > 0.1
            let oldRestCenter = CGPoint(x: restFrame.midX, y: restFrame.midY)
            restFrame = frame
            let newRestCenter = CGPoint(x: frame.midX, y: frame.midY)

            if !hadRest {
                currentCenter = newRestCenter
                targetCenter = newRestCenter
                return
            }

            let dx = newRestCenter.x - oldRestCenter.x
            let dy = newRestCenter.y - oldRestCenter.y
            currentCenter.x += dx
            currentCenter.y += dy
            targetCenter.x += dx
            targetCenter.y += dy
            if let currentTracking = trackingLocation {
                trackingLocation = CGPoint(x: currentTracking.x + dx, y: currentTracking.y + dy)
            }
        }

        mutating func setHighlighted(_ highlighted: Bool, expandedScale: CGFloat) {
            let wasHighlighted = isHighlighted
            isHighlighted = highlighted
            if highlighted && !wasHighlighted {
                releasePulseArmed = false
                releaseStartScale = 1.0
                pulseElapsed = 0
                pulseDuration = 0
            } else if !highlighted && wasHighlighted {
                releasePulseArmed = true
                releaseStartScale = scale
                pulseElapsed = 0
                pulseDuration = 0
            }
            targetScale = highlighted ? expandedScale : 1.0
        }

	        mutating func updateTrackingLocation(_ location: CGPoint?) {
	            guard let location else {
	                trackingLocation = nil
	                grabOffset = .zero
	                return
	            }

	            if trackingLocation == nil {
	                grabOffset = CGVector(dx: currentCenter.x - location.x, dy: currentCenter.y - location.y)
	            }
	            trackingLocation = location
	        }

        mutating func step(dt: CGFloat, tuning: LiquidChatGooeyTuning) {
            let restCenter = CGPoint(x: restFrame.midX, y: restFrame.midY)
            let rawDesiredCenter: CGPoint = {
                if let trackingLocation {
                    return CGPoint(x: trackingLocation.x + grabOffset.dx, y: trackingLocation.y + grabOffset.dy)
                } else {
                    return restCenter
                }
            }()
            let baseSide = max(0.1, min(restFrame.width, restFrame.height))
            let maxDragDistance = baseSide * max(0.0, tuning.maxDragDistanceFactor)

            let desiredCenter: CGPoint = {
                guard trackingLocation != nil else { return restCenter }
                let dx = rawDesiredCenter.x - restCenter.x
                let dy = rawDesiredCenter.y - restCenter.y
                let dist = hypot(dx, dy)
                guard dist > 0.001, maxDragDistance > 0.001 else { return restCenter }
                let normalized = dist / maxDragDistance
                let magnetStrength = max(0.01, tuning.magnetStrength)
                let scaledDist = maxDragDistance * CGFloat(tanh(Double(normalized / magnetStrength)))
                let t = scaledDist / dist
                return CGPoint(x: restCenter.x + dx * t, y: restCenter.y + dy * t)
            }()

            targetCenter = trackingLocation != nil ? rawDesiredCenter : restCenter

            let dx = desiredCenter.x - currentCenter.x
            let dy = desiredCenter.y - currentCenter.y
            let ax = tuning.centerStiffness * dx - tuning.centerDamping * velocity.dx
            let ay = tuning.centerStiffness * dy - tuning.centerDamping * velocity.dy
            velocity.dx += ax * dt
            velocity.dy += ay * dt
            currentCenter.x += velocity.dx * dt
            currentCenter.y += velocity.dy * dt

            let hardMaxDistance = maxDragDistance * max(1.0, tuning.hardClampFactor)
            if hardMaxDistance > 0.001 {
                let cx = currentCenter.x - restCenter.x
                let cy = currentCenter.y - restCenter.y
                let dist = hypot(cx, cy)
                if dist > hardMaxDistance {
                    let inv = hardMaxDistance / max(0.001, dist)
                    currentCenter = CGPoint(x: restCenter.x + cx * inv, y: restCenter.y + cy * inv)

                    let nx = cx / max(0.001, dist)
                    let ny = cy / max(0.001, dist)
                    let radialVelocity = velocity.dx * nx + velocity.dy * ny
                    if radialVelocity > 0 {
                        velocity.dx -= radialVelocity * nx
                        velocity.dy -= radialVelocity * ny
                    }
                }
            }

            let scaleDelta = targetScale - scale
            let scaleAcc = tuning.scaleStiffness * scaleDelta - tuning.scaleDamping * scaleVelocity
            scaleVelocity += scaleAcc * dt
            scale += scaleVelocity * dt
            scale = max(0.75, min(2.2, scale))

            let pulseCount = max(0, tuning.pulseCount)
            let amplitude = max(0, tuning.pulseAmplitude)
            let frequency = max(0.001, tuning.pulseFrequency)
            let pulseEnabled = pulseCount > 0 && amplitude > 0 && frequency > 0.0001

            if !pulseEnabled {
                releasePulseArmed = false
                pulseElapsed = 0
                pulseDuration = 0
                return
            }

            let threshold = max(0.0, min(0.999, tuning.pulseStartThreshold))
            if !isHighlighted && releasePulseArmed {
                let startScale = max(1.0, releaseStartScale)
                let triggerScale = 1.0 + (startScale - 1.0) * (1.0 - threshold)
                if scale <= triggerScale {
                    releasePulseArmed = false
                    pulseElapsed = 0
                    pulseDuration = pulseCount / frequency
                }
            }

            if pulseDuration > 0 {
                pulseElapsed += dt
                if pulseElapsed >= pulseDuration {
                    pulseElapsed = pulseDuration
                    pulseDuration = 0
                }
            }
        }

        mutating func makeShapeState(tuning: LiquidChatGooeyTuning) -> LiquidChatGlassShapeState {
            let enabled = restFrame.width > 0.1 && restFrame.height > 0.1
            let baseSide = max(0.1, min(restFrame.width, restFrame.height))
            let pullDx = targetCenter.x - currentCenter.x
            let pullDy = targetCenter.y - currentCenter.y
            let pull = hypot(pullDx, pullDy)
            let speed = hypot(velocity.dx, velocity.dy)

            let tensionDenom = max(1.0, baseSide * max(0.01, tuning.pullForMaxDeformationFactor))
            let tension = min(1.0, pull / tensionDenom)
            let speedFactor = min(1.0, speed / max(1.0, tuning.speedForMaxDeformation))
            let intensity = max(tension, speedFactor)

            let direction: CGVector = {
                if pull > 0.5 {
                    return CGVector(dx: pullDx / pull, dy: pullDy / pull)
                }
                if speed > 0.5 {
                    return CGVector(dx: velocity.dx / speed, dy: velocity.dy / speed)
                }
                return lastDirection
            }()
            lastDirection = direction

            let stretch = 1.0 + intensity * max(0.0, tuning.stretchFactor)
            let squash = max(0.68, 1.0 - intensity * max(0.0, tuning.squashFactor))

            let pulseScale: CGFloat = {
                guard pulseDuration > 0 else { return 1.0 }
                let frequency = max(0.001, tuning.pulseFrequency)
                let decay = max(0.0, tuning.pulseDecay)
                let amplitude = max(0.0, tuning.pulseAmplitude)
                let wave = sin(2 * CGFloat.pi * frequency * pulseElapsed)
                let envelope = exp(-decay * pulseElapsed)
                let v = 1.0 + amplitude * envelope * wave
                return max(0.2, min(2.5, v))
            }()

            let effectiveScale = scale * pulseScale
            let width = baseSide * effectiveScale * stretch
            let height = baseSide * effectiveScale * squash
            let cornerRadius = min(width, height) / 2

            return LiquidChatGlassShapeState(
                center: currentCenter,
                size: CGSize(width: width, height: height),
                cornerRadius: cornerRadius,
                isEnabled: enabled,
                direction: direction
            )
        }

        var isSettled: Bool {
            guard restFrame.width > 0.1 && restFrame.height > 0.1 else { return true }
            let restCenter = CGPoint(x: restFrame.midX, y: restFrame.midY)
            let dx = currentCenter.x - restCenter.x
            let dy = currentCenter.y - restCenter.y
            let dist = hypot(dx, dy)
            let speed = hypot(velocity.dx, velocity.dy)
            let scaleDelta = abs(scale - targetScale)
            let isTracking = trackingLocation != nil
            let isPulsing = pulseDuration > 0
            let hasPendingPulse = releasePulseArmed
            return !isTracking && !isPulsing && !hasPendingPulse && dist < 0.25 && speed < 0.25 && scaleDelta < 0.01
        }
    }

    private var leftGooey = GooeyButtonState()
    private var rightGooey = GooeyButtonState()

    private var displayLink: CADisplayLink?
    private var lastDisplayLinkTimestamp: CFTimeInterval?
    private let glassOverflowTop: CGFloat = 200

    public init(metalContext: MetalContext) {
        glassConfigValue = Self.defaultGlassConfig
        glassBackgroundView = LiquidChatGlassBackgroundView(config: glassConfigValue, metalContext: metalContext)
        let messageContainer = LiquidChatTextInputMessageContainer(backgroundView: glassBackgroundView)
        let attachmentButton = LiquidChatAttachmentButton(backgroundView: glassBackgroundView)
        let mediaButton = LiquidChatMediaRecordingButton()

        self.messageContainer = messageContainer
        self.attachmentButton = attachmentButton
        attachmentButtonImpl = attachmentButton
        mediaRecordingButton = mediaButton
        mediaRecordingButtonImpl = mediaButton

        textInputHostView = messageContainer.contentView
        accessoryPanelHostView = PassthroughHitTestView()
        contextPanelHostView = PassthroughHitTestView()

        let rootView = UIView()
        rootView.backgroundColor = .clear
        rootView.clipsToBounds = false
        view = rootView

        rootView.addSubview(glassBackgroundView.view)
        rootView.addSubview(messageContainer.view)
        rootView.addSubview(attachmentButton.view)
        rootView.addSubview(mediaButton.view)
        rootView.addSubview(accessoryPanelHostView)
        rootView.addSubview(contextPanelHostView)

        attachmentButton.onHighlightedChanged = { [weak self] highlighted in
            guard let self else { return }
            self.leftGooey.setHighlighted(highlighted, expandedScale: self.gooeyTuning.expandedScale)
            self.startDisplayLinkIfNeeded()
        }
        mediaButton.onHighlightedChanged = { [weak self] highlighted in
            guard let self else { return }
            self.rightGooey.setHighlighted(highlighted, expandedScale: self.gooeyTuning.expandedScale)
            self.startDisplayLinkIfNeeded()
        }

        attachmentButton.onTrackingLocationChanged = { [weak self] location in
            guard let self else { return }
            self.leftGooey.updateTrackingLocation(location)
            self.startDisplayLinkIfNeeded()
        }
        mediaButton.onTrackingLocationChanged = { [weak self] location in
            guard let self else { return }
            self.rightGooey.updateTrackingLocation(location)
            self.startDisplayLinkIfNeeded()
        }

        accessoryPanelHostView.backgroundColor = .clear
        contextPanelHostView.backgroundColor = .clear
    }

    public func setBackgroundCaptureView(_ view: UIView?) {
        glassBackgroundView.captureView = view
    }

    public func invalidateBackgroundCapture() {
        glassBackgroundView.invalidateBackgroundCapture()
    }

    public func update(
        presentation: ChatTextInputPanelChromePresentation,
        layout: ChatTextInputPanelChromeLayout,
        transition: ContainedViewLayoutTransition
    ) {
        leftGooey.setRestFrame(layout.attachmentButtonFrame)
        rightGooey.setRestFrame(layout.mediaRecordingButtonFrame)

        let glassFrame = CGRect(
            x: layout.bounds.minX,
            y: layout.bounds.minY - glassOverflowTop,
            width: layout.bounds.width,
            height: layout.bounds.height + glassOverflowTop
        )
        transition.updateFrame(view: glassBackgroundView.view, frame: glassFrame)
        transition.updateFrame(view: messageContainer.view, frame: layout.messageContainerFrame)
        transition.updateFrame(view: attachmentButton.view, frame: layout.attachmentButtonFrame)
        transition.updateFrame(view: mediaRecordingButton.view, frame: layout.mediaRecordingButtonFrame)
        transition.updateFrame(view: accessoryPanelHostView, frame: layout.accessoryPanelHostFrame)
        transition.updateFrame(view: contextPanelHostView, frame: layout.contextPanelHostFrame)

        let messageCornerRadius = layout.messageContainerFrame.height / 2
        let attachmentCornerRadius = layout.attachmentButtonFrame.height / 2
        let mediaCornerRadius = layout.mediaRecordingButtonFrame.height / 2

        glassBackgroundView.updateLayout(
            messageFrame: layout.messageContainerFrame.offsetBy(dx: 0, dy: glassOverflowTop),
            messageCornerRadius: messageCornerRadius,
            leftButtonFrame: layout.attachmentButtonFrame.offsetBy(dx: 0, dy: glassOverflowTop),
            leftButtonCornerRadius: attachmentCornerRadius,
            rightButtonFrame: layout.mediaRecordingButtonFrame.offsetBy(dx: 0, dy: glassOverflowTop),
            rightButtonCornerRadius: mediaCornerRadius
        )

        let componentTransition = componentTransition(from: transition)
        glassBackgroundView.update(
            size: glassFrame.size,
            cornerRadius: 0,
            isDark: presentation.messageContainer.isDark,
            tintColor: presentation.messageContainer.backgroundTintColor,
            isInteractive: presentation.messageContainer.isInteractive,
            transition: componentTransition
        )

        messageContainer.update(
            presentation: presentation.messageContainer,
            size: layout.messageContainerFrame.size,
            cornerRadius: messageCornerRadius,
            transition: componentTransition
        )

        attachmentButton.update(
            presentation: presentation.attachment,
            size: layout.attachmentButtonFrame.size,
            cornerRadius: attachmentCornerRadius,
            transition: transition
        )

        mediaRecordingButton.updateTheme(theme: presentation.theme)

        if let messageContainer = messageContainer as? LiquidChatTextInputMessageContainer {
            let relativeHostFrame = layout.textInputHostFrame.offsetBy(
                dx: -layout.messageContainerFrame.minX,
                dy: -layout.messageContainerFrame.minY
            )
            transition.updateFrame(view: messageContainer.contentView, frame: relativeHostFrame)
        }

        applyGooeyOutputs()
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLinkTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastDisplayLinkTimestamp = nil
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastDisplayLinkTimestamp = nil
    }

    @objc private func handleDisplayLinkTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt: CGFloat
        if let last = lastDisplayLinkTimestamp {
            dt = CGFloat(min(max(now - last, 1.0 / 240.0), 1.0 / 15.0))
        } else {
            dt = 1.0 / 60.0
        }
        lastDisplayLinkTimestamp = now

        leftGooey.step(dt: dt, tuning: gooeyTuning)
        rightGooey.step(dt: dt, tuning: gooeyTuning)

        applyGooeyOutputs()

        if leftGooey.isSettled && rightGooey.isSettled {
            stopDisplayLink()
        }
    }

    private func applyGooeyOutputs() {
        var leftShape = leftGooey.makeShapeState(tuning: gooeyTuning)
        var rightShape = rightGooey.makeShapeState(tuning: gooeyTuning)
        leftShape.center = CGPoint(x: leftShape.center.x, y: leftShape.center.y + glassOverflowTop)
        rightShape.center = CGPoint(x: rightShape.center.x, y: rightShape.center.y + glassOverflowTop)
        glassBackgroundView.setSideButtonStates(left: leftShape, right: rightShape)

        if leftGooey.restFrame.width > 0.1 {
            attachmentButton.view.center = leftGooey.currentCenter
        }
        if rightGooey.restFrame.width > 0.1 {
            mediaRecordingButton.view.center = rightGooey.currentCenter
        }

        attachmentButtonImpl.setIconTransform(iconTransform(for: leftShape, restFrame: leftGooey.restFrame))
        mediaRecordingButtonImpl.setIconTransform(iconTransform(for: rightShape, restFrame: rightGooey.restFrame))
    }
}

private extension LiquidChatTextInputPanelChromeView {
    func iconTransform(for shape: LiquidChatGlassShapeState, restFrame: CGRect) -> CGAffineTransform {
        let baseSide = max(0.001, min(restFrame.width, restFrame.height))
        guard baseSide > 0.001 else { return .identity }

        let sx = shape.size.width / baseSide
        let sy = shape.size.height / baseSide
        if !sx.isFinite || !sy.isFinite {
            return .identity
        }

        let scaleX = max(0.2, min(6.0, sx))
        let scaleY = max(0.2, min(6.0, sy))

        var dx = shape.direction.dx
        var dy = shape.direction.dy
        let dirLen = hypot(dx, dy)
        if !dirLen.isFinite || dirLen < 0.0001 {
            dx = 1.0
            dy = 0.0
        } else {
            dx /= dirLen
            dy /= dirLen
        }

        // Build a linear transform that scales along the shape's direction axis (dx, dy) without rotating the icon.
        // The shape width is aligned to `direction`, height to the perpendicular axis.
        let a = scaleX * dx * dx + scaleY * dy * dy
        let b = (scaleX - scaleY) * dx * dy
        let c = b
        let d = scaleX * dy * dy + scaleY * dx * dx
        return CGAffineTransform(a: a, b: b, c: c, d: d, tx: 0, ty: 0)
    }

    func componentTransition(from transition: ContainedViewLayoutTransition) -> ComponentTransition {
        switch transition {
        case .immediate:
            return .immediate
        case let .animated(duration, curve):
            return .animated(duration: duration, curve: curve)
        }
    }
}
