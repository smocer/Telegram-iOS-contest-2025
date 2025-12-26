import UIKit

public final class PassthroughHitTestView: UIView {
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, self.point(inside: point, with: event) else {
            return nil
        }
        
        for subview in subviews.reversed() {
            let convertedPoint = subview.convert(point, from: self)
            if let result = subview.hitTest(convertedPoint, with: event) {
                return result
            }
        }
        
        return nil
    }
}
