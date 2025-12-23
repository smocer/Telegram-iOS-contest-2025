import UIKit

struct LiquidGlassMotionSnapshot: Equatable {
    var stretch: CGFloat
    var bias: CGFloat
    var squash: CGFloat
    var overshoot: CGFloat

    static let zero = LiquidGlassMotionSnapshot(stretch: 0, bias: 0, squash: 0, overshoot: 0)
}

struct LiquidGlassMotionTuning: Equatable {
    var velocityFilterStrength: CGFloat = 10
    var velocitySampleResetThreshold: CFTimeInterval = 0.5
    var minimumDeltaTime: CFTimeInterval = 0.03
    var maximumDeltaTime: CFTimeInterval = 0.2

    var stretchGain: CGFloat = 0.6
    var maxStretch: CGFloat = 0.4
    /// Overdrag pull: distance (points) that maps to full pull "speed" (and thus max stretch).
    /// Lower value = more stretch for the same pull distance.
    var pullDistanceForMaxStretch: CGFloat = 60

    /// Travel-only. Portion of travel time spent in anticipation (no translation).
    var anticipationFraction: CGFloat = 0.15
    /// Travel-only. Minimum internal stretch during anticipation.
    var anticipationStretchMax: CGFloat = 0.25

    /// Boost stretch while accelerating (makes peak deformation occur slightly before peak velocity).
    var accelerationStretchBoostGain: CGFloat = 1.45
    var accelerationStretchBoostMax: CGFloat = 0.45

    /// Settling wobble (2–3 cycles), driven after arrival.
    var settleDelay: CFTimeInterval = 0.05
    var settleDuration: CFTimeInterval = 1.0
    var settleCycles: CGFloat = 2.0
    var settlePhaseExponent: CGFloat = 1.0
    var settleAmplitudeDecayPerCycle: CGFloat = 0.5
    var settlePhaseDistortion: CGFloat = 0.0
    var settleStretchAmplitude: CGFloat = 0.02
    var settleSquashAmplitude: CGFloat = 0.05
    /// Overall multiplier for the settling wobble (used as the "pulse" strength).
    var pulseGain: CGFloat = 2.45
    var settleCooldown: CFTimeInterval = 0.0

    var arrivalSpeedThreshold: CGFloat = 0.08
    var arrivalDecelThreshold: CGFloat = 0.06
    var movingSpeedThreshold: CGFloat = 0.12
}

struct LiquidGlassMotionModel {
    struct Context: Equatable {
        var speedDenominator: CGFloat
        var travelProgress: CGFloat?
        var directionSign: CGFloat?
        /// Signed horizontal pull distance past the end (points). Used to deform the blob on overdrag.
        var pullDistance: CGFloat?
    }

    var tuning: LiquidGlassMotionTuning = .init()

    private(set) var snapshot: LiquidGlassMotionSnapshot = .zero

    private var lastSampleTime: CFTimeInterval?
    private var lastCenterSample: CGPoint = .zero
    private var filteredVelocityX: CGFloat = 0
    private var previousSpeed: CGFloat = 0
    private var previousRawSpeed: CGFloat = 0
    private var previousPullSpeed: CGFloat = 0
    private var peakSpeed: CGFloat = 0
    private var lastDirectionSign: CGFloat = 1

    private var settleStartTime: CFTimeInterval?
    private var settleDirectionSign: CGFloat = 1
    private var settleIntensity: CGFloat = 0
    private var settleAmplitudeScale: CGFloat = 1
    private var lastSettleTriggerTime: CFTimeInterval = 0

    var isSettling: Bool {
        settleStartTime != nil
    }

    mutating func reset(center: CGPoint) {
        lastSampleTime = nil
        lastCenterSample = center
        filteredVelocityX = 0
        previousSpeed = 0
        previousRawSpeed = 0
        previousPullSpeed = 0
        peakSpeed = 0
        lastDirectionSign = 1
        settleStartTime = nil
        settleDirectionSign = 1
        settleIntensity = 0
        settleAmplitudeScale = 1
        lastSettleTriggerTime = 0
        snapshot = .zero
    }

    mutating func triggerSettleWobble(
        directionSign: CGFloat? = nil,
        intensity: CGFloat? = nil,
        now: CFTimeInterval = CACurrentMediaTime(),
        skipDelay: Bool = false
    ) {
        settleStartTime = now - (skipDelay ? tuning.settleDelay : 0)
        settleDirectionSign = {
            if let directionSign, abs(directionSign) > 0.001 {
                return directionSign >= 0 ? 1 : -1
            }
            return lastDirectionSign
        }()
        settleAmplitudeScale = max(0, tuning.pulseGain)

        if let intensity {
            settleIntensity = max(0, min(1, intensity))
        } else {
            settleIntensity = max(0, min(1, peakSpeed / 0.75))
        }
        lastSettleTriggerTime = now
    }

    mutating func update(currentCenter: CGPoint, context: Context, now: CFTimeInterval = CACurrentMediaTime()) -> LiquidGlassMotionSnapshot {
        guard let lastSampleTime else {
            self.lastSampleTime = now
            lastCenterSample = currentCenter
            snapshot = .zero
            return snapshot
        }

        let rawDeltaTime = now - lastSampleTime
        if rawDeltaTime > tuning.velocitySampleResetThreshold {
            self.lastSampleTime = now
            lastCenterSample = currentCenter
            filteredVelocityX = 0
            previousSpeed = 0
            return snapshot
        }

        let deltaTime = min(max(rawDeltaTime, tuning.minimumDeltaTime), tuning.maximumDeltaTime)
        let deltaX = currentCenter.x - lastCenterSample.x
        let velocityX = deltaX / deltaTime
        let filterAlpha = 1 - exp(-tuning.velocityFilterStrength * deltaTime)
        filteredVelocityX += (velocityX - filteredVelocityX) * filterAlpha

        let denominator = max(context.speedDenominator, 1)
        let speed = min(1.0, abs(filteredVelocityX) / denominator)
        let rawSpeed = min(1.0, abs(velocityX) / denominator)
        peakSpeed = max(peakSpeed, speed)

        let directionSign: CGFloat = {
            if let contextDirection = context.directionSign, abs(contextDirection) > 0.001 {
                return contextDirection >= 0 ? 1 : -1
            }
            if abs(filteredVelocityX) > 0.001 {
                return filteredVelocityX >= 0 ? 1 : -1
            }
            return lastDirectionSign
        }()
        lastDirectionSign = directionSign

        // Base stretch tracks velocity, but peaks slightly before peak velocity via acceleration bias.
        let acceleration = speed - previousSpeed
        let accelBoost = min(tuning.accelerationStretchBoostMax, max(0, acceleration) * tuning.accelerationStretchBoostGain)
        var stretch = min(tuning.maxStretch, speed * tuning.stretchGain * (1 + accelBoost))

        // Overdrag pull: treat pull distance as a force proxy (F ~ x) and reuse the same
        // speed/acceleration stretch logic, but driven by "pull speed" instead of velocity.
        var pullDirectionSign: CGFloat = 0
        if let pullDistance = context.pullDistance, abs(pullDistance) > 0.001 {
            pullDirectionSign = pullDistance >= 0 ? 1 : -1
            let pullDenominator = max(1, tuning.pullDistanceForMaxStretch)
            let pullSpeed = min(1.0, abs(pullDistance) / pullDenominator)
            let pullAcceleration = pullSpeed - previousPullSpeed
            let pullAccelBoost = min(tuning.accelerationStretchBoostMax, max(0, pullAcceleration) * tuning.accelerationStretchBoostGain)
            let pullStretch = min(tuning.maxStretch, pullSpeed * tuning.stretchGain * (1 + pullAccelBoost))
            stretch = max(stretch, pullStretch)
            previousPullSpeed = pullSpeed
        } else {
            previousPullSpeed = 0
        }

        // Anticipation (travel-only): internal pressure build-up, no translation required.
        if let travelProgress = context.travelProgress, travelProgress < tuning.anticipationFraction {
            let t = max(0, min(1, travelProgress / max(0.001, tuning.anticipationFraction)))
            let pressure = t * t * t
            let anticipationStretch = tuning.anticipationStretchMax * pressure
            stretch = max(stretch, anticipationStretch)
        }

        // Arrival → settling wobble (shape-only), with decaying, slightly irregular oscillations.
        let deceleration = previousSpeed - speed
        let wasMoving = previousSpeed > tuning.movingSpeedThreshold
        let stoppedAbruptly = rawSpeed < tuning.arrivalSpeedThreshold && previousRawSpeed > tuning.movingSpeedThreshold
        let nearingEnd: Bool = {
            guard let travelProgress = context.travelProgress else { return false }
            return travelProgress > 0.85 && speed < tuning.arrivalSpeedThreshold
        }()
        let arrivalReady = speed < tuning.arrivalSpeedThreshold && deceleration > tuning.arrivalDecelThreshold
        let settleCooldownPassed = (now - lastSettleTriggerTime) > tuning.settleCooldown

        if settleCooldownPassed {
            if stoppedAbruptly {
                let stopIntensity = min(1, max(previousRawSpeed, peakSpeed) / 0.75)
                triggerSettleWobble(directionSign: directionSign, intensity: stopIntensity, now: now, skipDelay: true)
            } else if wasMoving && (arrivalReady || nearingEnd) {
                settleStartTime = now
                settleDirectionSign = directionSign
                settleIntensity = min(1, peakSpeed / 0.75)
                settleAmplitudeScale = max(0, tuning.pulseGain)
                lastSettleTriggerTime = now
            }
        }

        var settleStretch: CGFloat = 0
        var settleSquash: CGFloat = 0
        if let settleStartTime {
            let elapsed = now - settleStartTime
            if elapsed > (tuning.settleDelay + tuning.settleDuration) {
                self.settleStartTime = nil
            } else if elapsed >= tuning.settleDelay {
                let t = CGFloat((elapsed - tuning.settleDelay) / max(0.001, tuning.settleDuration))
                let clampedT = max(0, min(1, t))
                let phaseT = pow(clampedT, tuning.settlePhaseExponent)
                let phase = 2 * CGFloat.pi * tuning.settleCycles * phaseT
                let cycle = phase / (2 * CGFloat.pi)
                let decay = pow(tuning.settleAmplitudeDecayPerCycle, cycle) * pow(1 - clampedT, 1.35)
                let distortion = tuning.settlePhaseDistortion * sin(phase * 1.7 + 0.8) * (1 - clampedT)
                let wave = sin(phase + distortion)
                let wave2 = sin(phase + 1.35 + distortion * 0.5)

                settleStretch = tuning.settleStretchAmplitude * wave2 * decay * settleIntensity * settleAmplitudeScale
                settleSquash = tuning.settleSquashAmplitude * wave * decay * settleIntensity * settleAmplitudeScale
            }
        }

        let bias = stretch * directionSign

        let finalStretch = max(0, min(tuning.maxStretch, stretch + settleStretch))
        snapshot = LiquidGlassMotionSnapshot(
            stretch: finalStretch,
            bias: bias,
            squash: settleSquash,
            overshoot: pullDirectionSign == 0 ? 0 : pullDirectionSign * finalStretch
        )

        previousSpeed = speed
        previousRawSpeed = rawSpeed
        self.lastSampleTime = now
        lastCenterSample = currentCenter
        return snapshot
    }
}
