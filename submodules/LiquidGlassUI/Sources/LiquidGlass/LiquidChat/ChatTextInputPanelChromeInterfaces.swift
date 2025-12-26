import AccountContext
import ChatInterfaceState
import ChatPresentationInterfaceState
import ComponentFlow
import Display
import GlassBackgroundComponent
import PresentationStrings
import TelegramPresentationData
import UIKit

// MARK: - Big "single root" interface

public struct ChatTextInputPanelChromeGesturePolicy {
    public var interactiveTransitionEdgeOnlyViews: [UIView]
    public var interactiveTransitionDisabledViews: [UIView]
    public var interactiveKeyboardDisabledViews: [UIView]

    public init(
        interactiveTransitionEdgeOnlyViews: [UIView] = [],
        interactiveTransitionDisabledViews: [UIView] = [],
        interactiveKeyboardDisabledViews: [UIView] = []
    ) {
        self.interactiveTransitionEdgeOnlyViews = interactiveTransitionEdgeOnlyViews
        self.interactiveTransitionDisabledViews = interactiveTransitionDisabledViews
        self.interactiveKeyboardDisabledViews = interactiveKeyboardDisabledViews
    }
}

public protocol ChatTextInputPanelChromeViewType: AnyObject {
    /// Telegram mounts exactly this one view into the panel hierarchy.
    var view: UIView { get }

    /// Your custom subcomponents (you can implement them directly or wrap existing ones).
    var messageContainer: ChatTextInputMessageContainerType { get }
    var attachmentButton: ChatTextInputAttachmentButtonType { get }
    var mediaRecordingButton: ChatTextInputMediaRecordingButtonType { get }

    /// Slots where Telegram continues to mount existing functional UI (no reimplementation):
    /// - ChatInputTextNode.view (and its clipping container)
    /// - accessory panel view (reply/edit header, etc.)
    /// - context panel view (autocomplete/contexts, etc.)
    var textInputHostView: UIView { get }
    
    /// Where Telegram installs the "tap to focus" gesture for lazy-loaded input.
    var focusTapView: UIView { get }
    var accessoryPanelHostView: UIView { get }
    var contextPanelHostView: UIView { get }

    /// Chrome-provided gesture conflict policy for global navigation / keyboard gestures.
    var gesturePolicy: ChatTextInputPanelChromeGesturePolicy { get }

    /// Called by Telegram whenever state/theme/layout changes.
    func update(
        presentation: ChatTextInputPanelChromePresentation,
        layout: ChatTextInputPanelChromeLayout,
        transition: ContainedViewLayoutTransition
    )
}

public extension ChatTextInputPanelChromeViewType {
    var gesturePolicy: ChatTextInputPanelChromeGesturePolicy {
        ChatTextInputPanelChromeGesturePolicy()
    }
}

public struct ChatTextInputPanelChromePresentation: Equatable {
    public var theme: PresentationTheme
    public var strings: PresentationStrings

    public var messageContainer: ChatTextInputMessageContainerPresentation
    public var attachment: ChatTextInputAttachmentButtonPresentation

    public init(
        theme: PresentationTheme,
        strings: PresentationStrings,
        messageContainer: ChatTextInputMessageContainerPresentation,
        attachment: ChatTextInputAttachmentButtonPresentation
    ) {
        self.theme = theme
        self.strings = strings
        self.messageContainer = messageContainer
        self.attachment = attachment
    }
    
    public static func == (lhs: ChatTextInputPanelChromePresentation, rhs: ChatTextInputPanelChromePresentation) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.strings !== rhs.strings {
            return false
        }
        if lhs.messageContainer != rhs.messageContainer {
            return false
        }
        if lhs.attachment != rhs.attachment {
            return false
        }
        return true
    }
}

public struct ChatTextInputPanelChromeLayout: Equatable {
    public var bounds: CGRect

    public var messageContainerFrame: CGRect
    public var textInputHostFrame: CGRect
    public var accessoryPanelHostFrame: CGRect
    public var contextPanelHostFrame: CGRect

    public var attachmentButtonFrame: CGRect
    public var mediaRecordingButtonFrame: CGRect

    public init(
        bounds: CGRect,
        messageContainerFrame: CGRect,
        textInputHostFrame: CGRect,
        accessoryPanelHostFrame: CGRect,
        contextPanelHostFrame: CGRect,
        attachmentButtonFrame: CGRect,
        mediaRecordingButtonFrame: CGRect
    ) {
        self.bounds = bounds
        self.messageContainerFrame = messageContainerFrame
        self.textInputHostFrame = textInputHostFrame
        self.accessoryPanelHostFrame = accessoryPanelHostFrame
        self.contextPanelHostFrame = contextPanelHostFrame
        self.attachmentButtonFrame = attachmentButtonFrame
        self.mediaRecordingButtonFrame = mediaRecordingButtonFrame
    }
}

// MARK: - Smaller sub-interfaces

// Background "glass-like" abstraction (works for message container background and circular button backgrounds)
public protocol ChatInputPanelBackgroundViewType: AnyObject {
    var view: UIView { get }
    var contentView: UIView { get }
    var maskContentView: UIView { get }

    func update(
        size: CGSize,
        cornerRadius: CGFloat,
        isDark: Bool,
        tintColor: GlassBackgroundView.TintColor,
        isInteractive: Bool,
        transition: ComponentTransition
    )
}

// Message container (the rounded “Message” field container)
public protocol ChatTextInputMessageContainerType: AnyObject {
    var view: UIView { get }
    var backgroundView: ChatInputPanelBackgroundViewType { get }

    /// Where Telegram places the actual functional text input (ChatInputTextNode.view or a clipping host).
    var contentView: UIView { get }

    func update(
        presentation: ChatTextInputMessageContainerPresentation,
        size: CGSize,
        cornerRadius: CGFloat,
        transition: ComponentTransition
    )
}

public struct ChatTextInputMessageContainerPresentation: Equatable {
    public var isDark: Bool
    public var backgroundTintColor: GlassBackgroundView.TintColor
    public var isInteractive: Bool

    public init(isDark: Bool, backgroundTintColor: GlassBackgroundView.TintColor, isInteractive: Bool) {
        self.isDark = isDark
        self.backgroundTintColor = backgroundTintColor
        self.isInteractive = isInteractive
    }
}

// Attachment button
public enum ChatTextInputAttachmentButtonVisualState: Equatable {
    case attachment
    case editAttachment
    case delete
    case comments(isExpanded: Bool, hasUnseen: Bool)
}

public struct ChatTextInputAttachmentButtonPresentation: Equatable {
    public var alpha: CGFloat
    public var isEnabled: Bool
    public var accessibilityLabel: String
    public var accessibilityTraits: UIAccessibilityTraits
    public var isDisabledOverlayVisible: Bool

    public var backgroundTintColor: GlassBackgroundView.TintColor
    public var isDark: Bool

    public var iconTintColor: UIColor
    public var state: ChatTextInputAttachmentButtonVisualState

    public init(
        alpha: CGFloat,
        isEnabled: Bool,
        accessibilityLabel: String,
        accessibilityTraits: UIAccessibilityTraits,
        isDisabledOverlayVisible: Bool,
        backgroundTintColor: GlassBackgroundView.TintColor,
        isDark: Bool,
        iconTintColor: UIColor,
        state: ChatTextInputAttachmentButtonVisualState
    ) {
        self.alpha = alpha
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityTraits = accessibilityTraits
        self.isDisabledOverlayVisible = isDisabledOverlayVisible
        self.backgroundTintColor = backgroundTintColor
        self.isDark = isDark
        self.iconTintColor = iconTintColor
        self.state = state
    }
}

public protocol ChatTextInputAttachmentButtonType: AnyObject {
    var view: UIView { get }
    var backgroundView: ChatInputPanelBackgroundViewType { get }
    var disabledOverlayView: UIView { get }

    var onPressed: (() -> Void)? { get set }
    var onHighlightedChanged: ((Bool) -> Void)? { get set }

    func update(
        presentation: ChatTextInputAttachmentButtonPresentation,
        size: CGSize,
        cornerRadius: CGFloat,
        transition: ContainedViewLayoutTransition
    )
}

// Voice/video record button (must preserve gesture behavior: hold-to-record, slide-to-cancel, lock, tap-to-switch-mode)
public protocol ChatTextInputMediaRecordingButtonType: AnyObject {
    var view: UIView { get }

    var mode: ChatTextInputMediaRecordingButtonMode { get }
    func updateMode(mode: ChatTextInputMediaRecordingButtonMode, animated: Bool)

    var fadeDisabled: Bool { get set }
    var statusBarHost: StatusBarHost? { get set }

    var audioRecorder: ManagedAudioRecorder? { get set }
    var videoRecordingStatus: InstantVideoControllerRecordingStatus? { get set }

    var cancelTranslation: CGFloat { get }

    var recordingDisabled: () -> Void { get set }
    var beginRecording: () -> Void { get set }
    var endRecording: (Bool) -> Void { get set }
    var stopRecording: () -> Void { get set }
    var offsetRecordingControls: () -> Void { get set }
    var switchMode: () -> Void { get set }
    var updateLocked: (Bool) -> Void { get set }
    var updateCancelTranslation: () -> Void { get set }

    func lock()
    func reset()
    func updateTheme(theme: PresentationTheme)
}

// Optional: single injection point
public protocol ChatTextInputPanelCustomUIFactory: AnyObject {
    func makeChromeView(
        context: AccountContext,
        initialTheme: PresentationTheme,
        strings: PresentationStrings,
        presentController: @escaping (ViewController) -> Void
    ) -> ChatTextInputPanelChromeViewType
}
