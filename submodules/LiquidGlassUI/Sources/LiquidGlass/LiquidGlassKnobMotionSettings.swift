import UIKit

struct LiquidGlassKnobEngineTuning: Equatable {
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
}

struct LiquidGlassKnobMotionSettings: Equatable {
    var engine: LiquidGlassKnobEngineTuning = .init()
    var travelTiming: LiquidGlassEaseInOutTimingTuning = .init()
    var motion: LiquidGlassMotionTuning = .init()
}
