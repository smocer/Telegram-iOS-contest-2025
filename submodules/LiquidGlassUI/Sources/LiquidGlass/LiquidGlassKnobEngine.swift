import UIKit

enum LiquidGlassMotionMode: Equatable {
    case interactive
    case travel
}

final class LiquidGlassKnobEngine {
    weak var liquidView: LiquidGlassKnobAnimatingView?
    let shapeDriver: LiquidGlassShapeDriver

    var motionMode: LiquidGlassMotionMode = .travel

    var transitionDuration: CFTimeInterval = 0.22
    var reverseTransitionDuration: CFTimeInterval = 0.22

    var minTravelDuration: CGFloat = 0.25
    var maxTravelDuration: CGFloat = 0.40
    var minSnapDuration: CGFloat = 0.18
    var maxSnapDuration: CGFloat = 0.28
    var durationDistanceNormalization: CGFloat = 350

    var velocityForMaxStretch: CGFloat = 1200
    var maxExpectedSpeedCeiling: CGFloat = 2400
    var maxExpectedSpeedFloor: CGFloat = 600
    var snapSpringDampingRatio: CGFloat = 0.86

    private var motionModel = LiquidGlassMotionModel()
    private var expectedPeakSpeed: CGFloat = 1800
    private var travelDuration: TimeInterval?
    private var movementStartTime: CFTimeInterval?
    private var travelDirectionSign: CGFloat?

    private let travelAnimationKey = "liquid-glass.knob.travel"
    private let crossfadeOpacityAnimationKey = "liquid-glass.knob.crossfade.opacity"

    private var pullDistance: CGFloat = 0

    init(liquidView: LiquidGlassKnobAnimatingView, shapeDriver: LiquidGlassShapeDriver) {
        self.liquidView = liquidView
        self.shapeDriver = shapeDriver
    }

    func setPullDistance(_ distance: CGFloat) {
        pullDistance = distance
        liquidView?.setNeedsDisplay()
    }

    func applyMotionSettings(_ settings: LiquidGlassKnobMotionSettings) {
        transitionDuration = settings.engine.transitionDuration
        reverseTransitionDuration = settings.engine.reverseTransitionDuration

        minTravelDuration = settings.engine.minTravelDuration
        maxTravelDuration = settings.engine.maxTravelDuration
        minSnapDuration = settings.engine.minSnapDuration
        maxSnapDuration = settings.engine.maxSnapDuration
        durationDistanceNormalization = settings.engine.durationDistanceNormalization

        velocityForMaxStretch = settings.engine.velocityForMaxStretch
        maxExpectedSpeedCeiling = settings.engine.maxExpectedSpeedCeiling
        maxExpectedSpeedFloor = settings.engine.maxExpectedSpeedFloor
        snapSpringDampingRatio = settings.engine.snapSpringDampingRatio

        shapeDriver.easeInOutTuning = settings.travelTiming
        motionModel.tuning = settings.motion

        liquidView?.setNeedsDisplay()
    }

    func motionSnapshot(currentCenter: CGPoint) -> LiquidGlassMotionSnapshot {
        motionSnapshot(currentCenter: currentCenter, mode: motionMode)
    }

    func motionSnapshot(currentCenter: CGPoint, mode: LiquidGlassMotionMode) -> LiquidGlassMotionSnapshot {
        let now = CACurrentMediaTime()
        let speedDenominator: CGFloat
        switch mode {
        case .interactive:
            speedDenominator = max(velocityForMaxStretch, 1)
        case .travel:
            speedDenominator = max(expectedPeakSpeed, 1)
        }

        let travelProgress: CGFloat?
        if
            shapeDriver.hasAnimation(forKey: travelAnimationKey),
            let movementStartTime,
            let travelDuration,
            travelDuration > 0
        {
            travelProgress = max(0, min(1, CGFloat((now - movementStartTime) / travelDuration)))
        } else {
            travelProgress = nil
        }

        let context = LiquidGlassMotionModel.Context(
            speedDenominator: speedDenominator,
            travelProgress: travelProgress,
            directionSign: travelDirectionSign,
            pullDistance: pullDistance
        )
        return motionModel.update(currentCenter: currentCenter, context: context, now: now)
    }

    func resetMotion(center: CGPoint) {
        travelDuration = nil
        movementStartTime = nil
        travelDirectionSign = nil
        pullDistance = 0
        motionModel.reset(center: center)
    }

    func snapToSelection(center: CGPoint) {
        shapeDriver.removeAllAnimations()
        resetMotion(center: center)

        let current = shapeDriver.presentationState
        shapeDriver.snap(to: LiquidGlassShapeState(center: center, size: current.size, cornerRadius: current.cornerRadius))
        liquidView?.setNeedsDisplay()
    }

    func setShapeSize(_ size: CGSize, cornerRadius: CGFloat) {
        shapeDriver.setSize(size, cornerRadius: cornerRadius)
    }

    func updateCenter(_ center: CGPoint, staticLayer: CALayer?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeDriver.setCenter(center, disableActions: false)
        staticLayer?.position = center
        CATransaction.commit()
    }

    func beginHandoff(restingFrame: CGRect, liquidFrame: CGRect, staticLayer: CALayer, completion: @escaping () -> Void) {
        guard let liquidView else { return }

        let restingCenter = CGPoint(x: restingFrame.midX, y: restingFrame.midY)

        shapeDriver.removeAllAnimations()
        liquidView.layer.removeAnimation(forKey: crossfadeOpacityAnimationKey)

        shapeDriver.snap(to: LiquidGlassShapeState(center: restingCenter, size: restingFrame.size, cornerRadius: restingFrame.height / 2))
        resetMotion(center: restingCenter)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        staticLayer.isHidden = false
        staticLayer.position = restingCenter
        staticLayer.bounds = CGRect(origin: .zero, size: restingFrame.size)
        staticLayer.cornerRadius = restingFrame.height / 2
        staticLayer.opacity = 1
        CATransaction.commit()

        liquidView.isHidden = false
        setViewOpacity(liquidView, opacity: 0)

        CATransaction.begin()
        CATransaction.setAnimationDuration(transitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock(completion)
        staticLayer.bounds = CGRect(origin: .zero, size: liquidFrame.size)
        staticLayer.cornerRadius = liquidFrame.height / 2
        staticLayer.opacity = 0
        shapeDriver.setSize(liquidFrame.size, cornerRadius: liquidFrame.height / 2, disableActions: false)
        addCrossfadeOpacityAnimation(view: liquidView, from: 0, to: 1, duration: transitionDuration)
        CATransaction.commit()
    }

    func endHandoff(
        restingFrame: CGRect,
        liquidFrame: CGRect,
        staticLayer: CALayer,
        completion: @escaping () -> Void
    ) {
        guard let liquidView else { return }

        let restingCenter = CGPoint(x: restingFrame.midX, y: restingFrame.midY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        staticLayer.isHidden = false
        staticLayer.opacity = 0
        staticLayer.position = restingCenter
        staticLayer.bounds = CGRect(origin: .zero, size: liquidFrame.size)
        staticLayer.cornerRadius = liquidFrame.height / 2
        shapeDriver.setSize(liquidFrame.size, cornerRadius: liquidFrame.height / 2, disableActions: true)
        liquidView.layer.removeAnimation(forKey: crossfadeOpacityAnimationKey)
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setAnimationDuration(reverseTransitionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        CATransaction.setCompletionBlock { [weak self, weak liquidView] in
            liquidView?.isHidden = true
            if let self {
                self.resetMotion(center: restingCenter)
            }
            completion()
        }
        staticLayer.bounds = CGRect(origin: .zero, size: restingFrame.size)
        staticLayer.cornerRadius = restingFrame.height / 2
        staticLayer.opacity = 1
        shapeDriver.setSize(restingFrame.size, cornerRadius: restingFrame.height / 2, disableActions: false)
        addCrossfadeOpacityAnimation(view: liquidView, from: 1, to: 0, duration: reverseTransitionDuration, timingFunctionName: .easeOut)
        CATransaction.commit()
    }

    func startTravel(
        to targetCenter: CGPoint,
        duration: TimeInterval,
        timing: LiquidGlassPositionTiming,
        completion: @escaping () -> Void
    ) {
        let startState = shapeDriver.presentationState

        shapeDriver.removeAllAnimations()
        shapeDriver.snap(to: startState)

        movementStartTime = CACurrentMediaTime()
        travelDuration = duration
        let deltaX = targetCenter.x - startState.center.x
        travelDirectionSign = abs(deltaX) < 0.001 ? nil : (deltaX >= 0 ? 1 : -1)
        motionModel.reset(center: startState.center)

        let distance = abs(targetCenter.x - startState.center.x)
        expectedPeakSpeed = max(
            maxExpectedSpeedFloor,
            min(maxExpectedSpeedCeiling, (distance / max(CGFloat(duration), 0.001)) * 2.4)
        )

        shapeDriver.animatePosition(to: targetCenter, duration: duration, timing: timing, animationKey: travelAnimationKey) { [weak self] in
            guard let self else { return }
            self.travelDuration = nil
            self.motionModel.triggerSettleWobble(directionSign: self.travelDirectionSign, skipDelay: true)
            completion()
            self.liquidView?.setNeedsDisplay()
        }
    }

    func startTravelDuringHandoff(
        to targetCenter: CGPoint,
        duration: TimeInterval,
        timing: LiquidGlassPositionTiming,
        completion: @escaping () -> Void
    ) {
        let startState = shapeDriver.presentationState

        shapeDriver.layer.removeAnimation(forKey: travelAnimationKey)
        resetMotion(center: startState.center)

        movementStartTime = CACurrentMediaTime()
        travelDuration = duration
        let deltaX = targetCenter.x - startState.center.x
        travelDirectionSign = abs(deltaX) < 0.001 ? nil : (deltaX >= 0 ? 1 : -1)

        let distance = abs(targetCenter.x - startState.center.x)
        expectedPeakSpeed = max(
            maxExpectedSpeedFloor,
            min(maxExpectedSpeedCeiling, (distance / max(CGFloat(duration), 0.001)) * 2.4)
        )

        shapeDriver.animatePosition(to: targetCenter, duration: duration, timing: timing, animationKey: travelAnimationKey) { [weak self] in
            guard let self else { return }
            self.travelDuration = nil
            self.motionModel.triggerSettleWobble(directionSign: self.travelDirectionSign, skipDelay: true)
            completion()
            self.liquidView?.setNeedsDisplay()
        }
    }

    func travelDuration(to targetCenter: CGPoint) -> TimeInterval {
        let startCenter = shapeDriver.presentationState.center
        let distance = abs(targetCenter.x - startCenter.x)
        return durationInRange(minDuration: minTravelDuration, maxDuration: maxTravelDuration, distance: distance)
    }

    func snapDuration(to targetCenter: CGPoint) -> TimeInterval {
        let startCenter = shapeDriver.presentationState.center
        let distance = abs(targetCenter.x - startCenter.x)
        return durationInRange(minDuration: minSnapDuration, maxDuration: maxSnapDuration, distance: distance)
    }

    private func durationInRange(minDuration: CGFloat, maxDuration: CGFloat, distance: CGFloat) -> TimeInterval {
        let normalized = min(1, max(0, distance / max(0.001, durationDistanceNormalization)))
        return TimeInterval(minDuration + (maxDuration - minDuration) * normalized)
    }

    private func addCrossfadeOpacityAnimation(
        view: LiquidGlassKnobAnimatingView,
        from: Float,
        to: Float,
        duration: CFTimeInterval,
        timingFunctionName: CAMediaTimingFunctionName = .easeInEaseOut
    ) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timingFunctionName)
        view.layer.add(animation, forKey: crossfadeOpacityAnimationKey)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer.opacity = to
        CATransaction.commit()
    }

    private func setViewOpacity(_ view: LiquidGlassKnobAnimatingView, opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer.opacity = opacity
        CATransaction.commit()
    }
}
