import UIKit

protocol LiquidGlassKnobAnimatingView: AnyObject {
    var layer: CALayer { get }
    var isHidden: Bool { get set }
    func setNeedsDisplay()
}

