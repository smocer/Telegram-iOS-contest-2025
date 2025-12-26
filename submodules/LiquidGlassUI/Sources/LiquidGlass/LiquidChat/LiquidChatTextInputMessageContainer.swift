import ComponentFlow
import UIKit

final class LiquidChatTextInputMessageContainer: ChatTextInputMessageContainerType {
    let view: UIView
    let backgroundView: ChatInputPanelBackgroundViewType
    let contentView: UIView

    init(backgroundView: ChatInputPanelBackgroundViewType) {
        self.backgroundView = backgroundView

        let rootView = UIView()
        rootView.backgroundColor = .clear
        rootView.clipsToBounds = true
        view = rootView

        let contentView = UIView()
        contentView.backgroundColor = .clear
        self.contentView = contentView
        rootView.addSubview(contentView)
    }

    func update(
        presentation: ChatTextInputMessageContainerPresentation,
        size: CGSize,
        cornerRadius: CGFloat,
        transition: ComponentTransition
    ) {
        transition.perform { [weak self] in
            guard let self else { return }
            self.view.layer.cornerRadius = cornerRadius
        }
    }

    func layoutContent(insets: UIEdgeInsets) {
        contentView.frame = view.bounds.inset(by: insets)
    }
}
