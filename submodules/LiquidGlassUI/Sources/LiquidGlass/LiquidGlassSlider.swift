import UIKit

public final class LiquidGlassSlider<T>: UIControl, UIGestureRecognizerDelegate {
    enum KnobFrameMode {
        case resting
        case liquid
    }

    private enum SliderState: Equatable {
        case resting
        case transitioningToLiquid
        case liquidInteractive
        case snapping
        case transitioningToResting
    }

    public var trackTintColor: UIColor = UIColor(white: 0.86, alpha: 1) {
        didSet { trackLayer.backgroundColor = trackTintColor.cgColor }
    }

    public var fillTintColor: UIColor = .systemBlue {
        didSet { trackFillLayer.backgroundColor = fillTintColor.cgColor }
    }

    public var knobColor: UIColor = .white {
        didSet { knobLayer.backgroundColor = knobColor.cgColor }
    }

    public var trackInsets: UIEdgeInsets = UIEdgeInsets(top: 18, left: 18, bottom: 24, right: 18) {
        didSet { setNeedsLayout() }
    }

    public var trackHeight: CGFloat = 6 {
        didSet { setNeedsLayout() }
    }

    public var dotDiameter: CGFloat = 3 {
        didSet { setNeedsLayout() }
    }

    public var dotSpacing: CGFloat = 5 {
        didSet { setNeedsLayout() }
    }

    public var magnetRadius: CGFloat = 26
    /// Multiplier for snapping magnet strength (1 = current behavior, >1 = stronger pull).
    public var magnetPullStrength: CGFloat = 1.8

    public var restingKnobSize: CGSize? {
        didSet { setNeedsLayout() }
    }

    public var liquidKnobSize: CGSize? {
        didSet { setNeedsLayout() }
    }

    public var isAlwaysPopped: Bool = false {
        didSet {
            guard isAlwaysPopped != oldValue else { return }
            if case .resting = sliderState {
                setNeedsLayout()
                layoutIfNeeded()
                layoutResting()
            }
        }
    }

    public let snappingValues: [T]
    public let isContinuous: Bool

    public var selectedIndex: Int? {
        get { isContinuous ? nil : committedSelectedIndex }
        set {
            guard !isContinuous, let index = newValue else { return }
            setSelectedIndex(index, animated: windowIsAvailable, shouldSendActions: true)
        }
    }

    public var selectedValue: T {
        if isContinuous {
            return Float(committedNormalizedValue) as! T
        }
        return snappingValues[committedSelectedIndex]
    }

    public var normalizedValue: CGFloat {
        get { committedNormalizedValue }
        set { setNormalizedValue(newValue, animated: windowIsAvailable, shouldSendActions: true) }
    }

    public var backgroundHostColor: UIColor? {
        get { backgroundHostView.backgroundColor }
        set { backgroundHostView.backgroundColor = newValue }
    }

    public override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1 : 0.45
            touchGesture.isEnabled = isEnabled
        }
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: 240, height: 64)
    }

    // MARK: - Private

    private var sliderState: SliderState = .resting
    private var pendingSnapTarget: CGFloat?
    private var committedNormalizedValue: CGFloat = 0
    private var committedSelectedIndex: Int = 0

    private let liquidContainerView = UIView()
    private let backgroundHostView = UIView()
    private let trackLayer = CALayer()
    private let trackFillLayer = CALayer()
    private let knobLayer = CALayer()
    private var snapDotLayers: [CALayer] = []
    private let knobView: LiquidGlassKnob
    private let metalContext: MetalContext

    private var knobVisualConfig: LiquidGlassConfig
    private var knobAppliedConfig: LiquidGlassConfig

    private var liquidContainerInsets: UIEdgeInsets = .zero
    private var fillSyncDisplayLink: CADisplayLink?
    private var lastTrackOverscroll: CGFloat = 0
    private var dragStartTouchX: CGFloat?
    private var dragStartKnobCenterX: CGFloat?

    private lazy var touchGesture: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleTouch(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = self
        return recognizer
    }()

    public init(metalContext: MetalContext, snappingValues: [T], initialKnobConfig: LiquidGlassConfig = .sliderKnob) {
        self.metalContext = metalContext
        self.snappingValues = snappingValues
        isContinuous = snappingValues.isEmpty

        precondition(!isContinuous || T.self == Float.self, "Continuous mode is only supported for LiquidGlassSlider<Float> (use LiquidGlassSlider(metalContext:) convenience init).")

        knobVisualConfig = initialKnobConfig
        knobAppliedConfig = knobVisualConfig
        knobView = LiquidGlassKnob(config: knobAppliedConfig, metalContext: metalContext)

        super.init(frame: .zero)

        isOpaque = false
        backgroundColor = .clear
        accessibilityTraits = [.adjustable]
        if isContinuous {
            accessibilityValue = "\(committedNormalizedValue)"
        } else {
            committedSelectedIndex = max(0, min(snappingValues.count - 1, committedSelectedIndex))
            committedNormalizedValue = snapNormalizedPositions()[committedSelectedIndex]
            accessibilityValue = "\(committedSelectedIndex)"
        }

        setupViews()
        transition(to: .resting)
        applyKnobMotionSettings(.sliderKnobMotion)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopFillSync()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        layoutLiquidContainer()
        updateKnobMaterialIfNeeded()
        layoutTrack()
        layoutSnapDots()

        if case .resting = sliderState {
            layoutResting()
        }
    }

    func applyKnobMotionSettings(_ settings: LiquidGlassKnobMotionSettings) {
        knobView.engine.applyMotionSettings(settings)
    }

    public func setNormalizedValue(_ value: CGFloat, animated: Bool, shouldSendActions: Bool = false) {
        let clamped = max(0, min(1, value))
        if !isContinuous {
            let index = nearestSnapIndex(to: clamped)
            setSelectedIndex(index, animated: animated, shouldSendActions: shouldSendActions)
            return
        }
        committedNormalizedValue = clamped
        accessibilityValue = "\(clamped)"
        if shouldSendActions {
            sendActions(for: .valueChanged)
        }
        guard animated, windowIsAvailable else {
            if case .resting = sliderState {
                layoutResting()
            }
            return
        }
        if case .resting = sliderState {
            layoutResting()
        }
    }

    public func setSelectedIndex(_ index: Int, animated: Bool, shouldSendActions: Bool = false) {
        guard !isContinuous else { return }
        let clamped = max(0, min(snappingValues.count - 1, index))
        committedNormalizedValue = snapNormalizedPositions()[clamped]
        committedSelectedIndex = clamped
        accessibilityValue = "\(clamped)"
        if shouldSendActions {
            sendActions(for: .valueChanged)
        }
        guard animated, windowIsAvailable else {
            if case .resting = sliderState {
                layoutResting()
            }
            return
        }
        if case .resting = sliderState {
            layoutResting()
        }
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

        trackLayer.backgroundColor = trackTintColor.cgColor
        trackLayer.masksToBounds = true
        backgroundHostView.layer.addSublayer(trackLayer)

        trackFillLayer.backgroundColor = fillTintColor.cgColor
        trackLayer.addSublayer(trackFillLayer)

        knobLayer.backgroundColor = knobColor.cgColor
        knobLayer.opacity = 1
        knobLayer.shadowColor = UIColor.black.cgColor
        knobLayer.shadowOpacity = 0.08
        knobLayer.shadowRadius = 12
        knobLayer.shadowOffset = CGSize(width: 0, height: 6)
        liquidContainerView.layer.insertSublayer(knobLayer, above: backgroundHostView.layer)

        knobView.translatesAutoresizingMaskIntoConstraints = true
        knobView.isUserInteractionEnabled = false
        knobView.isHidden = true
        knobView.backgroundView = backgroundHostView
        liquidContainerView.addSubview(knobView)

        addGestureRecognizer(touchGesture)

        rebuildSnapDots()
    }

    // MARK: - Geometry

    private var windowIsAvailable: Bool {
        window != nil
    }

    private func trackFrame() -> CGRect {
        let width = max(0, bounds.width - trackInsets.left - trackInsets.right)
        let availableHeight = max(0, bounds.height - trackInsets.top - trackInsets.bottom)
        let y = trackInsets.top + max(0, (availableHeight - trackHeight) / 2).rounded(.down)
        return CGRect(x: trackInsets.left, y: y, width: width, height: trackHeight)
    }

    private func knobSize(for mode: KnobFrameMode) -> CGSize {
        let derivedHeight = max(28, trackHeight * 4.0)
        let derivedResting = CGSize(width: derivedHeight * 1.35, height: derivedHeight)
        let resting = restingKnobSize ?? derivedResting
        switch mode {
        case .resting:
            return resting
        case .liquid:
            return liquidKnobSize ?? CGSize(width: resting.width * 1.5, height: resting.height * 1.3)
        }
    }

    private func knobCenterXRange() -> ClosedRange<CGFloat> {
        let track = trackFrame()
        let resting = knobSize(for: .resting)
        let minX = track.minX + resting.width / 2
        let maxX = track.maxX - resting.width / 2
        return minX...max(minX, maxX)
    }

    private func centerX(for normalized: CGFloat) -> CGFloat {
        let t = max(0, min(1, normalized))
        let range = knobCenterXRange()
        return range.lowerBound + (range.upperBound - range.lowerBound) * t
    }

    private func normalized(for centerX: CGFloat) -> CGFloat {
        let range = knobCenterXRange()
        let denom = max(0.001, range.upperBound - range.lowerBound)
        return max(0, min(1, (centerX - range.lowerBound) / denom))
    }

    private func knobFrame(normalized: CGFloat, mode: KnobFrameMode) -> CGRect {
        let track = trackFrame()
        let size = knobSize(for: mode)
        let center = CGPoint(x: centerX(for: normalized), y: track.midY)
        return centeredFrame(size: size, center: center)
    }

    private func trackMidYInContainer() -> CGFloat {
        if trackLayer.bounds.height > 0 {
            return trackLayer.frame.midY
        }
        return trackFrame().midY + liquidContainerOffset().y
    }

    private func containerCenter(normalized: CGFloat) -> CGPoint {
        let offset = liquidContainerOffset()
        return CGPoint(x: centerX(for: normalized) + offset.x, y: trackMidYInContainer())
    }

    private func knobFrameInContainer(normalized: CGFloat, mode: KnobFrameMode) -> CGRect {
        centeredFrame(size: knobSize(for: mode), center: containerCenter(normalized: normalized))
    }

    private func centeredFrame(size: CGSize, center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Layout

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
    }

    private func layoutTrack() {
        let offset = liquidContainerOffset()
        let frame = trackFrame().offsetBy(dx: offset.x, dy: offset.y)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = frame
        trackLayer.cornerRadius = frame.height / 2
        let t = max(0, min(1, committedNormalizedValue))
        let fillWidth = frame.width * t
        trackFillLayer.frame = CGRect(x: 0, y: 0, width: min(frame.width, max(0, fillWidth)), height: frame.height)
        trackFillLayer.cornerRadius = min(trackLayer.cornerRadius, trackFillLayer.frame.width / 2)
        CATransaction.commit()
    }

    private func applyTrackJelly(overscroll: CGFloat, animateBack: Bool = false) {
        let offset = liquidContainerOffset()
        let baseFrame = trackFrame().offsetBy(dx: offset.x, dy: offset.y)

        let pull = abs(overscroll)
        if pull <= 0.001 {
            guard lastTrackOverscroll != 0 else { return }
            lastTrackOverscroll = 0

            CATransaction.begin()
            CATransaction.setDisableActions(!animateBack)
            if animateBack {
                CATransaction.setAnimationDuration(0.22)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            }
            trackLayer.frame = baseFrame
            trackLayer.cornerRadius = baseFrame.height / 2
            updateSnapDots(baseTrackFrame: baseFrame, displayTrackFrame: baseFrame, xOffset: 0)
            CATransaction.commit()

            updateTrackFill(normalized: committedNormalizedValue)
            return
        }

        lastTrackOverscroll = overscroll

        let maxExtraWidth: CGFloat = 10
        let maxHeightReductionFraction: CGFloat = 0.35
        let pullNormalized = 1 - exp(-pull / 30)
        let extraWidth = maxExtraWidth * pullNormalized
        let heightScale = 1 - maxHeightReductionFraction * pullNormalized

        let newHeight = max(1, baseFrame.height * heightScale)
        let newWidth = max(1, baseFrame.width + extraWidth)
        let y = baseFrame.midY - newHeight / 2
        let x: CGFloat
        if overscroll < 0 {
            x = baseFrame.maxX - newWidth
        } else {
            x = baseFrame.minX
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let frame = CGRect(x: x, y: y, width: newWidth, height: newHeight)
        trackLayer.frame = frame
        trackLayer.cornerRadius = newHeight / 2
        let xOffset = (overscroll < 0 ? -extraWidth : extraWidth)
        updateSnapDots(baseTrackFrame: baseFrame, displayTrackFrame: frame, xOffset: xOffset)
        CATransaction.commit()
        updateTrackFill(normalized: committedNormalizedValue)
    }

    private func updateTrackFill(normalized: CGFloat) {
        let t = max(0, min(1, normalized))
        let track = trackLayer.bounds
        let width = track.width * t
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackFillLayer.frame = CGRect(x: 0, y: 0, width: min(track.width, max(0, width)), height: track.height)
        trackFillLayer.cornerRadius = min(trackLayer.cornerRadius, trackFillLayer.frame.width / 2)
        CATransaction.commit()
    }

    private func updateSnapDots(baseTrackFrame: CGRect, displayTrackFrame: CGRect, xOffset: CGFloat) {
        guard !snapDotLayers.isEmpty else { return }
        let y = displayTrackFrame.maxY + dotSpacing
        let positions = snapNormalizedPositions()

        let knobHalfWidth = knobSize(for: .resting).width / 2
        let minX = baseTrackFrame.minX + knobHalfWidth
        let maxX = max(minX, baseTrackFrame.maxX - knobHalfWidth)
        let denom = max(0.001, maxX - minX)

        for (layer, t) in zip(snapDotLayers, positions) {
            let x = minX + denom * t + xOffset
            layer.bounds = CGRect(x: 0, y: 0, width: dotDiameter, height: dotDiameter)
            layer.position = CGPoint(x: x, y: y)
            layer.cornerRadius = dotDiameter / 2
        }
    }

    private func layoutSnapDots() {
        guard !snapDotLayers.isEmpty else { return }
        let track = trackLayer.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateSnapDots(baseTrackFrame: track, displayTrackFrame: track, xOffset: 0)
        CATransaction.commit()
    }

    private func layoutResting() {
        let mode: KnobFrameMode = isAlwaysPopped ? .liquid : .resting
        let knobFrame = knobFrameInContainer(normalized: committedNormalizedValue, mode: mode)
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
        CATransaction.commit()
        knobView.engine.snapToSelection(center: CGPoint(x: knobFrame.midX, y: knobFrame.midY))
    }

    private func computeLiquidContainerInsets() -> UIEdgeInsets {
        guard !bounds.isEmpty else { return .zero }
        let leftFrame = knobFrame(normalized: 0, mode: .liquid)
        let rightFrame = knobFrame(normalized: 1, mode: .liquid)
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
        let liquidFrame = knobFrame(normalized: committedNormalizedValue, mode: .liquid)
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

    private func rebuildSnapDots() {
        snapDotLayers.forEach { $0.removeFromSuperlayer() }
        snapDotLayers.removeAll()
        guard !snappingValues.isEmpty else { return }
        for _ in snappingValues {
            let dot = CALayer()
            dot.backgroundColor = UIColor(white: 0.75, alpha: 1).cgColor
            backgroundHostView.layer.addSublayer(dot)
            snapDotLayers.append(dot)
        }
    }

    private func snapNormalizedPositions() -> [CGFloat] {
        let count = snappingValues.count
        guard count > 0 else { return [] }
        if count == 1 {
            return [0.5]
        }
        let denom = CGFloat(max(1, count - 1))
        return (0..<count).map { CGFloat($0) / denom }
    }

    private func nearestSnapIndex(to normalized: CGFloat) -> Int {
        let positions = snapNormalizedPositions()
        guard !positions.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDistance = abs(normalized - positions[0])
        for index in 1..<positions.count {
            let distance = abs(normalized - positions[index])
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func applyMagnet(to normalized: CGFloat) -> CGFloat {
        guard !isContinuous else { return normalized }
        let range = knobCenterXRange()
        let rangeWidth = max(1, range.upperBound - range.lowerBound)
        let radiusNormalized = max(0, magnetRadius / rangeWidth)
        guard radiusNormalized > 0 else { return normalized }

        let positions = snapNormalizedPositions()
        guard !positions.isEmpty else { return normalized }

        var nearest = positions[0]
        var nearestDistance = abs(normalized - positions[0])
        for position in positions.dropFirst() {
            let distance = abs(normalized - position)
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = position
            }
        }

        guard nearestDistance < radiusNormalized else { return normalized }
        let t = 1 - (nearestDistance / radiusNormalized)
        let baseStrength = t * t * (3 - 2 * t)
        let strength = min(1, max(0, magnetPullStrength) * baseStrength)
        return normalized + (nearest - normalized) * strength
    }

    // MARK: - Fill sync

    private func startFillSyncIfNeeded() {
        guard fillSyncDisplayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleFillSyncTick))
        link.add(to: .main, forMode: .common)
        fillSyncDisplayLink = link
    }

    private func stopFillSync() {
        fillSyncDisplayLink?.invalidate()
        fillSyncDisplayLink = nil
    }

    @objc private func handleFillSyncTick() {
        guard !knobView.isHidden else { return }
        let offset = liquidContainerOffset().x
        let centerXInView = knobView.engine.shapeDriver.presentationState.center.x - offset
        let t = normalized(for: centerXInView)
        updateTrackFill(normalized: t)
    }

    // MARK: - Interactions

    @objc private func handleTouch(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)

        switch recognizer.state {
        case .began:
            guard case .resting = sliderState else { return }
            beginInteraction(at: location)
        case .changed:
            updateInteractive(at: location)
        case .ended, .cancelled, .failed:
            endInteraction(at: location)
        default:
            break
        }
    }

    private func beginInteraction(at location: CGPoint) {
        pendingSnapTarget = nil
        dragStartTouchX = location.x
        dragStartKnobCenterX = currentKnobCenterXInView()
        transition(to: .transitioningToLiquid)

        let restingFrame = knobFrameInContainer(normalized: committedNormalizedValue, mode: .resting)
        let liquidFrame = knobFrameInContainer(normalized: committedNormalizedValue, mode: .liquid)
        knobView.engine.beginHandoff(restingFrame: restingFrame, liquidFrame: liquidFrame, staticLayer: knobLayer) { [weak self] in
            self?.handleTransitionInCompleted()
        }
        updateInteractive(at: location)
    }

    private func currentKnobCenterXInView() -> CGFloat {
        let offsetX = liquidContainerOffset().x
        if isAlwaysPopped, !knobView.isHidden {
            return knobView.engine.shapeDriver.presentationState.center.x - offsetX
        }
        let frame = knobLayer.presentation()?.frame ?? knobLayer.frame
        return frame.midX - offsetX
    }

    private func endInteraction(at location: CGPoint) {
        guard allowsInteractiveUpdates(in: sliderState) else { return }
        applyTrackJelly(overscroll: 0, animateBack: true)
        let rawX = rawKnobCenterX(forTouchX: location.x)
        let clampedX = clampInteractiveX(rawX)
        let rawNormalized = normalized(for: clampedX)
        dragStartTouchX = nil
        dragStartKnobCenterX = nil
        if isContinuous {
            snap(to: rawNormalized)
            return
        }

        let adjusted = applyMagnet(to: rawNormalized)
        let index = nearestSnapIndex(to: adjusted)
        committedSelectedIndex = index
        let target = snapNormalizedPositions()[index]
        snap(to: target)
    }

    private func handleTransitionInCompleted() {
        guard case .transitioningToLiquid = sliderState else { return }
        transition(to: .liquidInteractive)
        if let pending = pendingSnapTarget {
            pendingSnapTarget = nil
            snap(to: pending)
        }
    }

    private func allowsInteractiveUpdates(in state: SliderState) -> Bool {
        switch state {
        case .transitioningToLiquid, .liquidInteractive:
            return true
        default:
            return false
        }
    }

    private func updateInteractive(at location: CGPoint) {
        guard allowsInteractiveUpdates(in: sliderState) else { return }
        let rawX = rawKnobCenterX(forTouchX: location.x)
        let clampedX = clampInteractiveX(rawX)
        let raw = normalized(for: clampedX)
        let track = trackFrame()
        let overscroll: CGFloat
        if location.x < track.minX {
            overscroll = location.x - track.minX
        } else if location.x > track.maxX {
            overscroll = location.x - track.maxX
        } else {
            overscroll = 0
        }
        if isContinuous {
            committedNormalizedValue = raw
            accessibilityValue = "\(raw)"
            sendActions(for: .valueChanged)
            applyTrackJelly(overscroll: overscroll)

            let center: CGPoint
            if overscroll < 0 {
                let knobHalfWidth = knobSize(for: .resting).width / 2
                center = CGPoint(x: trackLayer.frame.minX + knobHalfWidth, y: trackMidYInContainer())
            } else if overscroll > 0 {
                let knobHalfWidth = knobSize(for: .resting).width / 2
                center = CGPoint(x: trackLayer.frame.maxX - knobHalfWidth, y: trackMidYInContainer())
            } else {
                center = containerCenter(normalized: raw)
            }
            knobView.engine.updateCenter(center, staticLayer: knobLayer)
            return
        }

        let t = applyMagnet(to: raw)
        committedNormalizedValue = t
        applyTrackJelly(overscroll: overscroll)

        let center: CGPoint
        if overscroll < 0 {
            let knobHalfWidth = knobSize(for: .resting).width / 2
            center = CGPoint(x: trackLayer.frame.minX + knobHalfWidth, y: trackMidYInContainer())
        } else if overscroll > 0 {
            let knobHalfWidth = knobSize(for: .resting).width / 2
            center = CGPoint(x: trackLayer.frame.maxX - knobHalfWidth, y: trackMidYInContainer())
        } else {
            center = containerCenter(normalized: t)
        }
        knobView.engine.updateCenter(center, staticLayer: knobLayer)

        let nextIndex = nearestSnapIndex(to: t)
        if nextIndex != committedSelectedIndex {
            committedSelectedIndex = nextIndex
            accessibilityValue = "\(nextIndex)"
            sendActions(for: .valueChanged)
        }
    }

    private func rawKnobCenterX(forTouchX touchX: CGFloat) -> CGFloat {
        guard let dragStartTouchX, let dragStartKnobCenterX else {
            return touchX
        }
        return dragStartKnobCenterX + (touchX - dragStartTouchX)
    }

    private func clampInteractiveX(_ x: CGFloat) -> CGFloat {
        let range = knobCenterXRange()
        return max(range.lowerBound, min(range.upperBound, x))
    }

    private func snap(to targetNormalized: CGFloat) {
        switch sliderState {
        case .transitioningToLiquid:
            pendingSnapTarget = targetNormalized
        case .liquidInteractive:
            transition(to: .snapping)
            if isContinuous {
                commit(to: targetNormalized)
            } else {
                startTravel(to: targetNormalized, timing: .spring(dampingRatio: knobView.engine.snapSpringDampingRatio))
            }
        default:
            break
        }
    }

    private func startTravel(to targetNormalized: CGFloat, timing: LiquidGlassPositionTiming) {
        let targetCenter = containerCenter(normalized: targetNormalized)
        let duration = knobView.engine.snapDuration(to: targetCenter)

        knobView.engine.startTravel(to: targetCenter, duration: duration, timing: timing) { [weak self] in
            guard let self else { return }
            self.commit(to: targetNormalized)
        }
    }

    private func commit(to finalNormalized: CGFloat) {
        committedNormalizedValue = max(0, min(1, finalNormalized))
        if isContinuous {
            accessibilityValue = "\(committedNormalizedValue)"
        } else {
            let index = nearestSnapIndex(to: committedNormalizedValue)
            committedSelectedIndex = index
            committedNormalizedValue = snapNormalizedPositions()[index]
            accessibilityValue = "\(index)"
            sendActions(for: .valueChanged)
        }

        transition(to: .transitioningToResting)
        let restingFrame = knobFrameInContainer(normalized: committedNormalizedValue, mode: .resting)
        let liquidFrame = knobFrameInContainer(normalized: committedNormalizedValue, mode: .liquid)
        knobView.engine.endHandoff(restingFrame: restingFrame, liquidFrame: liquidFrame, staticLayer: knobLayer) { [weak self] in
            guard let self else { return }
            self.transition(to: .resting)
            self.layoutResting()
        }
    }

    // MARK: - State

    private func transition(to newState: SliderState) {
        let oldState = sliderState
        sliderState = newState

        if isRestingState(oldState), !isRestingState(newState) {
            startFillSyncIfNeeded()
        } else if !isRestingState(oldState), isRestingState(newState) {
            stopFillSync()
        }

        if case .resting = newState {
            knobView.engine.motionMode = .travel
        } else {
            knobView.engine.motionMode = allowsInteractiveUpdates(in: newState) ? .interactive : .travel
        }
    }

    private func isRestingState(_ state: SliderState) -> Bool {
        if case .resting = state { return true }
        return false
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === touchGesture {
            guard case .resting = sliderState else { return false }
            let location = gestureRecognizer.location(in: self)
            let mode: KnobFrameMode = isAlwaysPopped ? .liquid : .resting
            return knobFrame(normalized: committedNormalizedValue, mode: mode).contains(location)
        }
        return true
    }
}

extension LiquidGlassSlider where T == Float {
    convenience init(metalContext: MetalContext, initialKnobConfig: LiquidGlassConfig = .sliderKnob) {
        self.init(metalContext: metalContext, snappingValues: [], initialKnobConfig: initialKnobConfig)
    }

    var value: Float {
        get { Float(normalizedValue) }
        set { setNormalizedValue(CGFloat(newValue), animated: window != nil, shouldSendActions: true) }
    }
}
