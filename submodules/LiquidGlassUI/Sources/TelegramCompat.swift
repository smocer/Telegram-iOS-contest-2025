import ComponentFlow
import Display
import GlassBackgroundComponent
import TelegramPresentationData
import UIKit

extension PresentationTheme {
    var isDark: Bool {
        self.overallDarkAppearance
    }
}

extension GlassBackgroundView.TintColor {
    func liquidTint(isDark: Bool) -> LiquidGlassTint {
        switch kind {
        case .panel:
            return LiquidGlassTint(r: 0.92, g: 0.92, b: 0.95, a: isDark ? 0.18 : 0.22)
        case .custom:
            return color.liquidTint(userInterfaceStyle: isDark ? .dark : .light)
        }
    }

    var tint: LiquidGlassTint {
        color.liquidTint(userInterfaceStyle: nil)
    }
}

private extension UIColor {
    func liquidTint(userInterfaceStyle: UIUserInterfaceStyle?) -> LiquidGlassTint {
        let resolvedColor: UIColor
        if let userInterfaceStyle {
            resolvedColor = self.resolvedColor(with: UITraitCollection(userInterfaceStyle: userInterfaceStyle))
        } else {
            resolvedColor = self
        }

        var r: CGFloat = 1.0
        var g: CGFloat = 1.0
        var b: CGFloat = 1.0
        var a: CGFloat = 0.0
        if !resolvedColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var white: CGFloat = 1.0
            if resolvedColor.getWhite(&white, alpha: &a) {
                r = white
                g = white
                b = white
            }
        }

        return LiquidGlassTint(r: Float(r), g: Float(g), b: Float(b), a: Float(a))
    }
}

extension ComponentTransition {
    static func animated(duration: Double, curve: ContainedViewLayoutTransitionCurve) -> ComponentTransition {
        let mappedCurve: ComponentTransition.Animation.Curve
        switch curve {
        case .linear:
            mappedCurve = .linear
        case .easeInOut:
            mappedCurve = .easeInOut
        case .spring, .customSpring:
            mappedCurve = .spring
        case let .custom(a, b, c, d):
            mappedCurve = .custom(a, b, c, d)
        }
        return ComponentTransition(animation: .curve(duration: duration, curve: mappedCurve))
    }

    func perform(_ f: @escaping () -> Void) {
        switch self.animation {
        case .none:
            f()
        case let .curve(duration, curve):
            let options: UIView.AnimationOptions
            switch curve {
            case .linear:
                options = [.curveLinear]
            case .easeInOut:
                options = [.curveEaseInOut]
            case .spring:
                options = UIView.AnimationOptions(rawValue: 7 << 16)
            case .custom:
                options = []
            }
            UIView.animate(withDuration: duration, delay: 0.0, options: options, animations: {
                f()
            }, completion: nil)
        }
    }
}
