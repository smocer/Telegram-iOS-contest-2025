import UIKit

public final class LiquidGlassSwitch: UIControl, UIGestureRecognizerDelegate {
    enum KnobFrameMode {
        case resting
        case liquid
    }

    private enum TargetMode: Equatable {
        case tap(toIsOn: Bool)
        case interactivePan
    }

    private enum SwitchState: Equatable {
        case resting(isOn: Bool)
        case transitioningToLiquid(isOn: Bool, target: TargetMode)
        case liquidAnimating(fromIsOn: Bool, toIsOn: Bool)
        case liquidInteractive(isOn: Bool)
        case snapping(fromIsOn: Bool, toIsOn: Bool)
        case transitioningToResting(isOn: Bool)
    }

    public var isOn: Bool = false {
        didSet {
            guard isOn != oldValue else { return }
            accessibilityValue = isOn ? "1" : "0"
            if case .resting = switchState {
                layoutResting()
            }
        }
    }

    public var onTintColor: UIColor = .systemGreen {
        didSet {
            trackFillLayer.backgroundColor = onTintColor.cgColor
        }
    }

    public var offTintColor: UIColor = UIColor(white: 0.86, alpha: 1) {
        didSet {
            trackLayer.backgroundColor = offTintColor.cgColor
        }
    }

    public var knobColor: UIColor = .white {
        didSet {
            knobLayer.backgroundColor = knobColor.cgColor
        }
    }

    public var backgroundHostColor: UIColor? {
        get { backgroundHostView.backgroundColor }
        set { backgroundHostView.backgroundColor = newValue }
    }

    /// Insets from bounds to the outer track.
    public var trackInsets: UIEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12) {
        didSet { setNeedsLayout() }
    }

    /// Resting knob size (static CALayer). If `nil`, derives from track height.
    public var restingKnobSize: CGSize? {
        didSet { setNeedsLayout() }
    }

    /// Liquid knob size (Metal blob). If `nil`, derives from resting size.
    public var liquidKnobSize: CGSize? {
        didSet { setNeedsLayout() }
    }

    public var isAlwaysPopped: Bool = false {
        didSet {
            guard isAlwaysPopped != oldValue else { return }
            if case .resting = switchState {
                setNeedsLayout()
                layoutIfNeeded()
                layoutResting()
            }
        }
    }

    public override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1 : 0.45
            tapGesture.isEnabled = isEnabled
            knobTouchGesture.isEnabled = isEnabled
        }
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: 70, height: 36)
    }

    // MARK: - Private

    private var switchState: SwitchState = .resting(isOn: false)
    private var pendingSnapToIsOn: Bool?
    private var pendingTapToggleToIsOn: Bool?
    private var knobTouchBeganTime: CFTimeInterval?
    private var knobTouchStartLocation: CGPoint = .zero
    private var knobTouchStartIsOn: Bool = false
    private var knobTouchStartKnobCenterX: CGFloat?
    private var knobTouchMaxDistance: CGFloat = 0

    private let liquidContainerView = UIView()
    private let backgroundHostView = UIView()
    private let trackLayer = CALayer()
    private let trackFillLayer = CALayer()
    private let knobLayer = CALayer()
    private let knobView: LiquidGlassKnob
    private let metalContext: MetalContext

    private var knobVisualConfig: LiquidGlassConfig
    private var knobAppliedConfig: LiquidGlassConfig
    private var liquidContainerInsets: UIEdgeInsets = .zero
    private var dragPreviewIsOn: Bool?

    private lazy var tapGesture: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        return recognizer
    }()

    private lazy var knobTouchGesture: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleKnobTouch(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        return recognizer
    }()

    public init(metalContext: MetalContext, initialKnobConfig: LiquidGlassConfig = .switchKnob) {
        self.metalContext = metalContext
        knobVisualConfig = initialKnobConfig
        knobAppliedConfig = knobVisualConfig
        knobView = LiquidGlassKnob(config: knobAppliedConfig, metalContext: metalContext)

        super.init(frame: .zero)

        isOpaque = false
        backgroundColor = .clear

        accessibilityTraits = [.button]
        accessibilityValue = isOn ? "1" : "0"

        setupViews()
        transition(to: .resting(isOn: isOn))
        applyKnobMotionSettings(.switchKnobMotion)
    }

    @available(*, unavailable)
    override init(frame: CGRect) {
        fatalError("Use init(metalContext:initialKnobConfig:)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        layoutLiquidContainer()
        updateKnobMaterialIfNeeded()

        if case .resting = switchState {
            layoutResting()
        }
    }

    func applyKnobMotionSettings(_ settings: LiquidGlassKnobMotionSettings) {
        knobView.engine.applyMotionSettings(settings)
    }

    public func setOn(_ on: Bool, animated: Bool) {
        if !animated || !windowIsAvailable {
            isOn = on
            return
        }

        guard case .resting = switchState, on != isOn else { return }
        beginTap(toIsOn: on)
    }

    // MARK: - Setup

    private func setupViews() {
        liquidContainerView.isUserInteractionEnabled = false
        liquidContainerView.backgroundColor = .clear
        addSubview(liquidContainerView)

        backgroundHostView.isUserInteractionEnabled = false
        backgroundHostView.isOpaque = true
        backgroundHostView.backgroundColor = .systemBackground
        liquidContainerView.addSubview(backgroundHostView)

        trackLayer.backgroundColor = offTintColor.cgColor
        trackLayer.masksToBounds = true
        backgroundHostView.layer.addSublayer(trackLayer)

        trackFillLayer.backgroundColor = onTintColor.cgColor
        trackLayer.addSublayer(trackFillLayer)

        knobLayer.backgroundColor = knobColor.cgColor
        knobLayer.opacity = 1
        liquidContainerView.layer.insertSublayer(knobLayer, above: backgroundHostView.layer)

        knobView.translatesAutoresizingMaskIntoConstraints = true
        knobView.isUserInteractionEnabled = false
        knobView.isHidden = true
        knobView.backgroundView = backgroundHostView
        liquidContainerView.addSubview(knobView)

        addGestureRecognizer(tapGesture)
        addGestureRecognizer(knobTouchGesture)
        tapGesture.require(toFail: knobTouchGesture)
    }

    // MARK: - Geometry

    private var windowIsAvailable: Bool {
        window != nil
    }

    private func trackFrame() -> CGRect {
        bounds.inset(by: trackInsets)
    }

    private func knobSize(for mode: KnobFrameMode) -> CGSize {
        let track = trackFrame()
        let trackToKnobInset: CGFloat = 5
        let derivedHeight = max(0, track.height - trackToKnobInset)
        let derivedResting = CGSize(width: derivedHeight * 1.55, height: derivedHeight)
        let resting = restingKnobSize ?? derivedResting
        switch mode {
        case .resting:
            return resting
        case .liquid:
            return liquidKnobSize ?? CGSize(width: resting.width * 1.4, height: resting.height * 1.4)
        }
    }

    private func knobCenterXRange() -> ClosedRange<CGFloat> {
        let track = trackFrame()
        let resting = knobSize(for: .resting)
        let edgeInset = max(0, (track.height - resting.height) / 2)
        let minX = track.minX + edgeInset + resting.width / 2
        let maxX = track.maxX - edgeInset - resting.width / 2
        return minX...max(minX, maxX)
    }

    private func knobFrame(isOn: Bool, mode: KnobFrameMode) -> CGRect {
        let track = trackFrame()
        let size = knobSize(for: mode)
        let range = knobCenterXRange()
        let centerX = isOn ? range.upperBound : range.lowerBound
        let center = CGPoint(x: centerX, y: track.midY)
        return centeredFrame(size: size, center: center)
    }

    private func centeredFrame(size: CGSize, center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Layout/Appearance

    private func layoutLiquidContainer() {
        liquidContainerInsets = computeLiquidContainerInsets()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let extraPadding: CGFloat = 10

        liquidContainerInsets = UIEdgeInsets(
            top: liquidContainerInsets.top + extraPadding,
            left: liquidContainerInsets.left + extraPadding,
            bottom: liquidContainerInsets.bottom + extraPadding,
            right: liquidContainerInsets.right + extraPadding
        )

        liquidContainerInsets = UIEdgeInsets(
            top: pixelAligned(liquidContainerInsets.top, scale: scale),
            left: pixelAligned(liquidContainerInsets.left, scale: scale),
            bottom: pixelAligned(liquidContainerInsets.bottom, scale: scale),
            right: pixelAligned(liquidContainerInsets.right, scale: scale)
        )

        liquidContainerView.frame = CGRect(
            x: -liquidContainerInsets.left,
            y: -liquidContainerInsets.top,
            width: bounds.width + liquidContainerInsets.left + liquidContainerInsets.right,
            height: bounds.height + liquidContainerInsets.top + liquidContainerInsets.bottom
        )
        backgroundHostView.frame = liquidContainerView.bounds
        knobView.frame = liquidContainerView.bounds
        backgroundHostView.contentScaleFactor = scale
        knobView.contentScaleFactor = scale
        knobView.drawableSize = CGSize(
            width: (knobView.bounds.width * scale).rounded(),
            height: (knobView.bounds.height * scale).rounded()
        )
        layoutTrack()
    }

    private func layoutTrack() {
        let offset = liquidContainerOffset()
        let frame = trackFrame().offsetBy(dx: offset.x, dy: offset.y)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = frame
        trackLayer.cornerRadius = frame.height / 2
        trackFillLayer.frame = CGRect(origin: .zero, size: frame.size)
        trackFillLayer.cornerRadius = trackLayer.cornerRadius
        trackFillLayer.opacity = isOn ? 1 : 0
        CATransaction.commit()
    }

    private func layoutResting() {
        let mode: KnobFrameMode = isAlwaysPopped ? .liquid : .resting
        let knobFrame = knobFrame(isOn: isOn, mode: mode).offsetBy(dx: liquidContainerOffset().x, dy: liquidContainerOffset().y)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isAlwaysPopped {
            knobLayer.isHidden = true
            knobLayer.opacity = 0
            knobView.isHidden = false
            knobView.layer.opacity = 1
        } else {
            knobLayer.isHidden = false
            knobLayer.opacity = 1
            knobView.isHidden = true
            knobView.layer.opacity = 0
        }

        knobLayer.frame = knobFrame
        knobLayer.cornerRadius = knobFrame.height / 2
        trackFillLayer.removeAnimation(forKey: "liquid-glass.switch.track-fill-opacity")
        trackFillLayer.opacity = isOn ? 1 : 0
        CATransaction.commit()
        knobView.snapToSelection(center: CGPoint(x: knobFrame.midX, y: knobFrame.midY))
    }

    private func computeLiquidContainerInsets() -> UIEdgeInsets {
        guard !bounds.isEmpty else { return .zero }
        let leftFrame = knobFrame(isOn: false, mode: .liquid)
        let rightFrame = knobFrame(isOn: true, mode: .liquid)
        let union = leftFrame.union(rightFrame)

        let left = max(0, -union.minX)
        let top = max(0, -union.minY)
        let right = max(0, union.maxX - bounds.width)
        let bottom = max(0, union.maxY - bounds.height)
        return UIEdgeInsets(top: top, left: left, bottom: bottom, right: right)
    }

    private func liquidContainerOffset() -> CGPoint {
        CGPoint(x: liquidContainerInsets.left, y: liquidContainerInsets.top)
    }

    private func containerPoint(_ point: CGPoint) -> CGPoint {
        let offset = liquidContainerOffset()
        return CGPoint(x: point.x + offset.x, y: point.y + offset.y)
    }

    private func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return (value * scale).rounded() / scale
    }

    private func updateKnobMaterialIfNeeded() {
        let liquidFrame = knobFrame(isOn: isOn, mode: .liquid)
        guard liquidFrame.width > 0, liquidFrame.height > 0 else { return }

        let radius = Float(liquidFrame.height / 2)
        let desired = knobVisualConfig.copyWith(
            shapeWidth: Float(liquidFrame.width),
            shapeHeight: Float(liquidFrame.height),
            cornerRadius: radius
        )
        if desired != knobAppliedConfig {
            knobAppliedConfig = desired
            knobView.updateSettings(config: knobAppliedConfig)
        }
    }

    func applyKnobVisualConfig(_ config: LiquidGlassConfig) {
        knobVisualConfig = config
        updateKnobMaterialIfNeeded()
    }

    private func animateTrackColor(toIsOn: Bool, duration: CFTimeInterval) {
        let fromOpacity: Float = trackFillLayer.presentation()?.opacity ?? trackFillLayer.opacity
        let toOpacity: Float = toIsOn ? 1 : 0

        trackFillLayer.removeAnimation(forKey: "liquid-glass.switch.track-fill-opacity")
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = fromOpacity
        animation.toValue = toOpacity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        trackFillLayer.add(animation, forKey: "liquid-glass.switch.track-fill-opacity")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackFillLayer.opacity = toOpacity
        CATransaction.commit()
    }

    // MARK: - Interactions

    @objc private func handleTap() {
        guard case .resting = switchState else { return }
        beginTap(toIsOn: !isOn)
    }

    @objc private func handleKnobTouch(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)

        switch recognizer.state {
        case .began:
            guard case .resting = switchState else { return }
            knobTouchBeganTime = CACurrentMediaTime()
            knobTouchStartLocation = location
            knobTouchStartIsOn = isOn
            let startMode: KnobFrameMode = isAlwaysPopped ? .liquid : .resting
            knobTouchStartKnobCenterX = knobFrame(isOn: isOn, mode: startMode).midX
            knobTouchMaxDistance = 0
            pendingTapToggleToIsOn = nil
            let startIsOn = isOn
            pendingSnapToIsOn = nil
            transition(to: .transitioningToLiquid(isOn: startIsOn, target: .interactivePan))

            let offset = liquidContainerOffset()
            let restingFrame = knobFrame(isOn: startIsOn, mode: .resting).offsetBy(dx: offset.x, dy: offset.y)
            let liquidFrame = knobFrame(isOn: startIsOn, mode: .liquid).offsetBy(dx: offset.x, dy: offset.y)
            knobView.engine.beginHandoff(restingFrame: restingFrame, liquidFrame: liquidFrame, staticLayer: knobLayer) { [weak self] in
                self?.handleTransitionInCompleted(fromIsOn: startIsOn, target: .interactivePan)
            }
            updateInteractiveFromKnobTouch(fingerX: location.x)
        case .changed:
            knobTouchMaxDistance = max(knobTouchMaxDistance, hypot(location.x - knobTouchStartLocation.x, location.y - knobTouchStartLocation.y))
            updateInteractiveFromKnobTouch(fingerX: location.x)
        case .ended, .cancelled, .failed:
            guard allowsInteractiveUpdates(in: switchState) else { return }
            knobTouchStartKnobCenterX = nil
            knobView.engine.setPullDistance(0)
            let now = CACurrentMediaTime()
            let elapsed = now - (knobTouchBeganTime ?? now)
            let quickTapThreshold: CFTimeInterval = 0.18
            let quickTapMoveThreshold: CGFloat = 10

            if elapsed <= quickTapThreshold, knobTouchMaxDistance <= quickTapMoveThreshold {
                let target = !knobTouchStartIsOn
                switch switchState {
                case .transitioningToLiquid(_, target: .interactivePan):
                    pendingTapToggleToIsOn = target
                case .liquidInteractive:
                    transition(to: .liquidAnimating(fromIsOn: knobTouchStartIsOn, toIsOn: target))
                    startTravel(toIsOn: target, timing: .easeInOut)
                default:
                    pendingTapToggleToIsOn = target
                }
                return
            }

            let target = decideTargetIsOn(centerX: location.x, velocityX: 0)
            snap(toIsOn: target)
        default:
            break
        }
    }

    private func beginTap(toIsOn: Bool) {
        let startIsOn = isOn
        transition(to: .transitioningToLiquid(isOn: startIsOn, target: .tap(toIsOn: toIsOn)))

        let offset = liquidContainerOffset()
        let restingFrame = knobFrame(isOn: startIsOn, mode: .resting).offsetBy(dx: offset.x, dy: offset.y)
        let liquidFrame = knobFrame(isOn: startIsOn, mode: .liquid).offsetBy(dx: offset.x, dy: offset.y)
        knobView.engine.beginHandoff(restingFrame: restingFrame, liquidFrame: liquidFrame, staticLayer: knobLayer) { [weak self] in
            self?.handleTransitionInCompleted(fromIsOn: startIsOn, target: .tap(toIsOn: toIsOn))
        }
    }

    private func allowsInteractiveUpdates(in state: SwitchState) -> Bool {
        switch state {
        case .transitioningToLiquid(_, target: .interactivePan), .liquidInteractive:
            return true
        default:
            return false
        }
    }

    private func updateInteractive(centerX rawX: CGFloat) {
        guard allowsInteractiveUpdates(in: switchState) else { return }
        let y = trackFrame().midY
        let clampedX = clampInteractiveX(rawX)
        let overscroll = rawX - clampedX
        knobView.engine.setPullDistance(overscroll)
        let pullShiftX = overdragCenterShift(for: overscroll)
        knobView.engine.updateCenter(containerPoint(CGPoint(x: clampedX + pullShiftX, y: y)), staticLayer: knobLayer)
        updateTrackFillPreview(centerX: clampedX)
    }

    private func updateInteractiveFromKnobTouch(fingerX: CGFloat) {
        let startFingerX = knobTouchStartLocation.x
        let startCenterX = knobTouchStartKnobCenterX ?? fingerX
        let deltaX = fingerX - startFingerX
        updateInteractive(centerX: startCenterX + deltaX)
    }

    private func overdragCenterShift(for overscroll: CGFloat) -> CGFloat {
        guard abs(overscroll) > 0.001 else { return 0 }
        let sign: CGFloat = overscroll >= 0 ? 1 : -1
        let maxShift: CGFloat = 10
        let response: CGFloat = 20
        let t = 1 - exp(-abs(overscroll) / max(1, response))
        return sign * maxShift * t
    }

    private func updateTrackFillPreview(centerX: CGFloat) {
        let range = knobCenterXRange()
        let distance = max(range.upperBound - range.lowerBound, 0.0001)
        let normalized = (centerX - range.lowerBound) / distance

        let currentDesired = dragPreviewIsOn ?? isOn
        var nextDesired = currentDesired

        // Hysteresis:
        // - off -> on: becomes green after crossing the midpoint
        // - on -> off: becomes gray only when fully left
        if currentDesired {
            // Currently green.
            if normalized <= 0.0001 {
                nextDesired = false
            }
        } else {
            // Currently gray.
            if normalized > 0.5 {
                nextDesired = true
            }
        }

        let nextStored: Bool? = nextDesired == isOn ? nil : nextDesired

        guard nextDesired != currentDesired else {
            dragPreviewIsOn = nextStored
            return
        }

        dragPreviewIsOn = nextStored
        animateTrackColor(toIsOn: nextDesired, duration: 0.2)
    }

    private func clampInteractiveX(_ x: CGFloat) -> CGFloat {
        let range = knobCenterXRange()
        return max(range.lowerBound, min(range.upperBound, x))
    }

    private func decideTargetIsOn(centerX rawX: CGFloat, velocityX: CGFloat) -> Bool {
        let range = knobCenterXRange()
        let midpoint = (range.lowerBound + range.upperBound) / 2
        let clamped = max(range.lowerBound, min(range.upperBound, rawX))
        let flickVelocity: CGFloat = 320
        if abs(velocityX) > flickVelocity {
            return velocityX > 0
        }
        return clamped >= midpoint
    }

    private func snap(toIsOn: Bool) {
        switch switchState {
        case .transitioningToLiquid(_, target: .interactivePan):
            pendingSnapToIsOn = toIsOn
        case .liquidInteractive(let fromIsOn):
            transition(to: .snapping(fromIsOn: fromIsOn, toIsOn: toIsOn))
            startTravel(toIsOn: toIsOn, timing: .spring(dampingRatio: knobView.engine.snapSpringDampingRatio))
        default:
            break
        }
    }

    private func handleTransitionInCompleted(fromIsOn: Bool, target: TargetMode) {
        guard
            case .transitioningToLiquid(let currentIsOn, let currentTarget) = switchState,
            currentIsOn == fromIsOn,
            currentTarget == target
        else { return }

        switch target {
        case .tap(let toIsOn):
            transition(to: .liquidAnimating(fromIsOn: fromIsOn, toIsOn: toIsOn))
            startTravel(toIsOn: toIsOn, timing: .easeInOut)
        case .interactivePan:
            if let pendingTapToggleToIsOn {
                self.pendingTapToggleToIsOn = nil
                transition(to: .liquidAnimating(fromIsOn: fromIsOn, toIsOn: pendingTapToggleToIsOn))
                startTravel(toIsOn: pendingTapToggleToIsOn, timing: .easeInOut)
                return
            }
            transition(to: .liquidInteractive(isOn: fromIsOn))
            dragPreviewIsOn = nil
            if let pending = pendingSnapToIsOn {
                pendingSnapToIsOn = nil
                snap(toIsOn: pending)
            }
        }
    }

    private func startTravel(toIsOn: Bool, timing: LiquidGlassPositionTiming) {
        let targetFrame = knobFrame(isOn: toIsOn, mode: .resting)
        let targetCenter = containerPoint(CGPoint(x: targetFrame.midX, y: targetFrame.midY))
        let duration: TimeInterval
        switch timing {
        case .easeInOut:
            duration = knobView.engine.travelDuration(to: targetCenter)
        case .spring:
            duration = knobView.engine.snapDuration(to: targetCenter)
        }

        knobView.engine.startTravel(to: targetCenter, duration: duration, timing: timing) { [weak self] in
            guard let self else { return }
            self.commit(toIsOn: toIsOn)
        }
    }

    private func commit(toIsOn: Bool) {
        animateTrackColor(toIsOn: toIsOn, duration: knobView.engine.reverseTransitionDuration)
        isOn = toIsOn
        sendActions(for: .valueChanged)
        dragPreviewIsOn = nil

        transition(to: .transitioningToResting(isOn: toIsOn))
        let offset = liquidContainerOffset()
        let restingFrame = knobFrame(isOn: toIsOn, mode: .resting).offsetBy(dx: offset.x, dy: offset.y)
        let liquidFrame = knobFrame(isOn: toIsOn, mode: .liquid).offsetBy(dx: offset.x, dy: offset.y)
        knobView.engine.endHandoff(restingFrame: restingFrame, liquidFrame: liquidFrame, staticLayer: knobLayer) { [weak self] in
            guard let self else { return }
            self.transition(to: .resting(isOn: toIsOn))
            self.layoutResting()
        }
    }

    // MARK: - State + display updates

    private func transition(to newState: SwitchState) {
        switchState = newState

        if case .resting = newState {
            knobView.engine.motionMode = .travel
        } else {
            knobView.engine.motionMode = allowsInteractiveUpdates(in: newState) ? .interactive : .travel
        }
    }

    private func isRestingState(_ state: SwitchState) -> Bool {
        if case .resting = state { return true }
        return false
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === knobTouchGesture {
            guard case .resting = switchState else { return false }
            let location = gestureRecognizer.location(in: self)
            let mode: KnobFrameMode = isAlwaysPopped ? .liquid : .resting
            return knobFrame(isOn: isOn, mode: mode).contains(location)
        }
        return true
    }
}
