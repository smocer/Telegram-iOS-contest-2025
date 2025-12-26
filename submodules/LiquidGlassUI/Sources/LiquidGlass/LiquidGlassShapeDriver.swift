import UIKit

struct LiquidGlassShapeState: Equatable {
    var center: CGPoint
    var size: CGSize
    var cornerRadius: CGFloat
}

struct LiquidGlassEaseInOutTimingTuning: Equatable {
    /// Portion of travel time with no translation.
    var anticipationFraction: CGFloat = 0.15
    /// Portion of travel distance used for the overshoot.
    var overshootFraction: CGFloat = 0.05
    /// Absolute cap for the overshoot distance.
    var maxOvershootPoints: CGFloat = 12
    /// Time (fraction) where overshoot peak occurs.
    var overshootTimeFraction: CGFloat = 0.55
}

enum LiquidGlassPositionTiming: Equatable {
    case easeInOut
    case spring(dampingRatio: CGFloat)
}

final class LiquidGlassShapeDriver {
    let layer: CALayer
    private(set) var modelState: LiquidGlassShapeState
    var easeInOutTuning: LiquidGlassEaseInOutTimingTuning = .init()

    init(layer: CALayer = CALayer(), initialState: LiquidGlassShapeState) {
        self.layer = layer
        modelState = initialState

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(initialState, to: layer)
        CATransaction.commit()
    }

    var presentationState: LiquidGlassShapeState {
        state(from: layer.presentation() ?? layer)
    }

    func snap(to state: LiquidGlassShapeState) {
        modelState = state
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(state, to: layer)
        CATransaction.commit()
    }

    func setCenter(_ center: CGPoint) {
        setCenter(center, disableActions: true)
    }

    func setSize(_ size: CGSize, cornerRadius: CGFloat) {
        setSize(size, cornerRadius: cornerRadius, disableActions: true)
    }

    func setCenter(_ center: CGPoint, disableActions: Bool) {
        modelState.center = center
        if disableActions {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.position = center
            CATransaction.commit()
        } else {
            layer.position = center
        }
    }

    func setSize(_ size: CGSize, cornerRadius: CGFloat, disableActions: Bool) {
        modelState.size = size
        modelState.cornerRadius = cornerRadius
        let apply = {
            self.layer.bounds = CGRect(origin: .zero, size: size)
            let minSide = max(0.001, min(size.width, size.height))
            self.layer.cornerRadius = min(cornerRadius, minSide / 2)
        }
        if disableActions {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            apply()
            CATransaction.commit()
        } else {
            apply()
        }
    }

    func removeAllAnimations() {
        layer.removeAllAnimations()
    }

    func hasAnimation(forKey key: String) -> Bool {
        layer.animation(forKey: key) != nil
    }

    func animatePosition(
        to targetCenter: CGPoint,
        duration: TimeInterval,
        timing: LiquidGlassPositionTiming,
        animationKey: String,
        completion: @escaping () -> Void
    ) {
        let fromPosition = (layer.presentation() ?? layer).position
        modelState.center = targetCenter

        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)

        let animation: CAAnimation
        switch timing {
        case .easeInOut:
            let tuning = easeInOutTuning
            let anticipationFraction = max(0, min(0.75, tuning.anticipationFraction))
            let overshootFraction = max(0, tuning.overshootFraction)
            let maxOvershootPoints = max(0, tuning.maxOvershootPoints)
            let overshootTimeFraction = max(anticipationFraction, min(0.99, tuning.overshootTimeFraction))

            let deltaX = targetCenter.x - fromPosition.x
            let overshootDistance = min(abs(deltaX) * overshootFraction, maxOvershootPoints) * (deltaX >= 0 ? 1 : -1)
            let overshootCenter = CGPoint(x: targetCenter.x + overshootDistance, y: targetCenter.y)
            let hasOvershoot = abs(overshootDistance) > 0.5
            if anticipationFraction <= 0.0001, !hasOvershoot {
                let basic = CABasicAnimation(keyPath: "position")
                basic.fromValue = fromPosition
                basic.toValue = targetCenter
                basic.duration = duration
                basic.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation = basic
                break
            }

            let keyframe = CAKeyframeAnimation(keyPath: "position")
            if hasOvershoot {
                keyframe.values = [fromPosition, fromPosition, overshootCenter, targetCenter]
                keyframe.keyTimes = [
                    0,
                    anticipationFraction,
                    overshootTimeFraction,
                    1
                ]
                .map { NSNumber(value: Float($0)) }
                keyframe.calculationMode = .cubic
                keyframe.timingFunctions = [
                    CAMediaTimingFunction(name: .linear),
                    CAMediaTimingFunction(name: .easeIn),
                    CAMediaTimingFunction(name: .easeOut)
                ]
            } else {
                keyframe.values = [fromPosition, fromPosition, targetCenter]
                keyframe.keyTimes = [
                    0,
                    anticipationFraction,
                    1
                ]
                .map { NSNumber(value: Float($0)) }
                keyframe.calculationMode = .cubic
                keyframe.timingFunctions = [
                    CAMediaTimingFunction(name: .linear),
                    CAMediaTimingFunction(name: .easeInEaseOut)
                ]
            }
            keyframe.duration = duration
            animation = keyframe
        case .spring(let dampingRatio):
            let settle = max(0.001, duration)
            let omega = 4.0 / (max(0.001, dampingRatio) * CGFloat(settle))
            let stiffness = omega * omega
            let damping = 2.0 * dampingRatio * omega
            let springAnim = CASpringAnimation(keyPath: "position")
            springAnim.mass = 1
            springAnim.stiffness = stiffness
            springAnim.damping = damping
            springAnim.initialVelocity = 0
            springAnim.fromValue = fromPosition
            springAnim.toValue = targetCenter
            springAnim.duration = duration
            animation = springAnim
        }

        CATransaction.setDisableActions(true)
        layer.position = targetCenter
        layer.add(animation, forKey: animationKey)
        CATransaction.commit()
    }

    // MARK: - Helpers

    private func apply(_ state: LiquidGlassShapeState, to layer: CALayer) {
        layer.bounds = CGRect(origin: .zero, size: state.size)
        layer.position = state.center
        let minSide = max(0.001, min(state.size.width, state.size.height))
        layer.cornerRadius = min(state.cornerRadius, minSide / 2)
    }

    private func state(from layer: CALayer) -> LiquidGlassShapeState {
        let minSide = max(0.001, min(layer.bounds.width, layer.bounds.height))
        let radius = min(layer.cornerRadius, minSide / 2)
        return LiquidGlassShapeState(
            center: layer.position,
            size: layer.bounds.size,
            cornerRadius: radius
        )
    }
}
