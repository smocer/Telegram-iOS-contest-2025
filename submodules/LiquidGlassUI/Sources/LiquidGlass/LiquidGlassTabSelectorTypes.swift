import UIKit
import Metal

protocol LiquidGlassBackground: AnyObject {
    /// View used for snapshotting background content for the liquid knob.
    var backgroundView: UIView? { get }

    /// Optional pre-rendered background texture (used when `backgroundView` can't capture Metal content).
    var backgroundTexture: MTLTexture? { get }

    /// Static pill layer shown in `.resting`.
    var knobLayer: CALayer { get }

    func setLiquidGlassKnobSink(_ sink: LiquidGlassKnobSink)
}

enum BeginMode: Equatable {
    case tap(toIndex: Int)
    case pan
}

enum TargetMode: Equatable {
    case tapToIndex(Int)
    case interactivePan
}

enum SelectorState: Equatable {
    case resting(selectedIndex: Int)
    case transitioningToLiquid(fromIndex: Int, target: TargetMode)
    case liquidAnimating(fromIndex: Int, toIndex: Int)
    case liquidInteractive(fromIndex: Int)
    case snappingToIndex(fromIndex: Int, toIndex: Int)
    case transitioningToResting(selectedIndex: Int)
}

protocol LiquidGlassKnobSink: AnyObject {
    func beginAnimation(fromIndex: Int, mode: BeginMode)
    func updateInteractive(x: CGFloat, velocity: CGFloat)
    func snap(toIndex: Int)
    func endAnimation(finalIndex: Int)
}
