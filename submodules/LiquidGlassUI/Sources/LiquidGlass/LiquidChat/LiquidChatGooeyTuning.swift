import UIKit

struct LiquidChatGooeyTuning: Equatable {
    var maxDragDistanceFactor: CGFloat = 0.3

    var magnetStrength: CGFloat = 3.0

    var hardClampFactor: CGFloat = 1.4

    var centerStiffness: CGFloat = 240
    var centerDamping: CGFloat = 28

    var scaleStiffness: CGFloat = 260
    var scaleDamping: CGFloat = 30

    var pullForMaxDeformationFactor: CGFloat = 8

    var speedForMaxDeformation: CGFloat = 200

    var stretchFactor: CGFloat = 0.06

    var squashFactor: CGFloat = 0.07

    var expandedScale: CGFloat = 1.5

    /// Pulse count emitted while returning to rest.
    var pulseCount: CGFloat = 2

    /// Return-to-rest threshold (0...1) at which pulses start.
    var pulseStartThreshold: CGFloat = 0.5

    /// Relative amplitude applied to scale: `scale * (1 + pulseAmplitude * wave)`.
    var pulseAmplitude: CGFloat = 0.14

    /// Pulse frequency in Hz.
    var pulseFrequency: CGFloat = 2.8

    /// Exponential decay rate (1/sec).
    var pulseDecay: CGFloat = 3.7
}
