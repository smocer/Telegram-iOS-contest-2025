import UIKit

public final class AccountContext {
    public init() {}
}

public final class ViewController: UIViewController {
}

public struct PresentationTheme: Equatable {
    public var isDark: Bool

    public init(isDark: Bool) {
        self.isDark = isDark
    }
}

public struct PresentationStrings: Equatable {
    public init() {}
}

public struct ComponentTransition: Equatable {
    public struct Animation: Equatable {
        public var duration: Double
        public var curve: UIView.AnimationCurve

        public init(duration: Double, curve: UIView.AnimationCurve) {
            self.duration = duration
            self.curve = curve
        }
    }

    public var animation: Animation?

    public init(animation: Animation?) {
        self.animation = animation
    }

    public static var immediate: ComponentTransition {
        ComponentTransition(animation: nil)
    }

    public static func animated(duration: Double, curve: UIView.AnimationCurve = .easeInOut) -> ComponentTransition {
        ComponentTransition(animation: Animation(duration: duration, curve: curve))
    }

    public func perform(_ animations: @escaping () -> Void) {
        guard let animation else {
            animations()
            return
        }
        UIView.animate(
            withDuration: animation.duration,
            delay: 0,
            options: UIView.AnimationOptions(curve: animation.curve),
            animations: animations
        )
    }
}

public enum ContainedViewLayoutTransition: Equatable {
    case immediate
    case animated(duration: Double, curve: UIView.AnimationCurve)

    public func updateFrame(view: UIView, frame: CGRect) {
        switch self {
        case .immediate:
            view.frame = frame
        case let .animated(duration, curve):
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: UIView.AnimationOptions(curve: curve),
                animations: { view.frame = frame }
            )
        }
    }

    public func updateAlpha(view: UIView, alpha: CGFloat) {
        switch self {
        case .immediate:
            view.alpha = alpha
        case let .animated(duration, curve):
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: UIView.AnimationOptions(curve: curve),
                animations: { view.alpha = alpha }
            )
        }
    }
}

public protocol StatusBarHost: AnyObject {
}

public final class ManagedAudioRecorder {
    public init() {}
}

public struct InstantVideoControllerRecordingStatus: Equatable {
    public init() {}
}

public enum ChatTextInputMediaRecordingButtonMode: Int32 {
    case audio = 0
    case video = 1
}

public final class GlassBackgroundView {
    public struct TintColor: Equatable {
        public var tint: LiquidGlassTint

        public init(tint: LiquidGlassTint) {
            self.tint = tint
        }

        public static let clear = TintColor(tint: .clear)
    }
}

extension UIView.AnimationOptions {
    init(curve: UIView.AnimationCurve) {
        switch curve {
        case .easeInOut:
            self = .curveEaseInOut
        case .easeIn:
            self = .curveEaseIn
        case .easeOut:
            self = .curveEaseOut
        case .linear:
            self = .curveLinear
        @unknown default:
            self = .curveEaseInOut
        }
    }
}
