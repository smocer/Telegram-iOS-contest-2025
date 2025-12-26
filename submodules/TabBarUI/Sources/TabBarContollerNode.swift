import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import LiquidGlassUI

private extension ToolbarTheme {
    convenience init(theme: PresentationTheme) {
        self.init(barBackgroundColor: theme.rootController.tabBar.backgroundColor, barSeparatorColor: .clear, barTextColor: theme.rootController.tabBar.textColor, barSelectedTextColor: theme.rootController.tabBar.selectedTextColor)
    }
}

extension LiquidGlassTabBar: TabBarBackgroundCaptureInvalidating {
}

final class TabBarControllerNode: ASDisplayNode {
    private final class BadgeLabel: UILabel {
        var contentInsets = UIEdgeInsets(top: 1.0, left: 5.0, bottom: 1.0, right: 5.0)

        override func drawText(in rect: CGRect) {
            super.drawText(in: rect.inset(by: self.contentInsets))
        }

        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(
                width: size.width + self.contentInsets.left + self.contentInsets.right,
                height: size.height + self.contentInsets.top + self.contentInsets.bottom
            )
        }
    }

    private struct Params: Equatable {
        let layout: ContainerViewLayout
        let toolbar: Toolbar?
        let isTabBarHidden: Bool
        
        init(
            layout: ContainerViewLayout,
            toolbar: Toolbar?,
            isTabBarHidden: Bool
        ) {
            self.layout = layout
            self.toolbar = toolbar
            self.isTabBarHidden = isTabBarHidden
        }
    }
    
    private struct LayoutResult {
        let params: Params
        let bottomInset: CGFloat
        
        init(params: Params, bottomInset: CGFloat) {
            self.params = params
            self.bottomInset = bottomInset
        }
    }
    
    private final class View: UIView {
        var onLayout: (() -> Void)?
        
        override func layoutSubviews() {
            super.layoutSubviews()
            
            self.onLayout?()
        }
    }
    
    private var theme: PresentationTheme
    private let itemSelected: (Int, Bool, [ASDisplayNode]) -> Void
    private let contextAction: (Int, ContextExtractedContentContainingView, ContextGesture) -> Void
    
    private let liquidTabBar: LiquidGlassTabBar
    private let backgroundUpdateDriver: TabBarBackgroundUpdateDriver
    
    private let disabledOverlayNode: ASDisplayNode
    private var toolbarNode: ToolbarNode?
    private let toolbarActionSelected: (ToolbarActionOption) -> Void
    private let disabledPressed: () -> Void
    
    private(set) var tabBarItems: [TabBarNodeItem] = []
    private(set) var selectedIndex: Int = 0

    private(set) var currentControllerNode: ASDisplayNode?
    
    private var layoutResult: LayoutResult?
    private var isUpdateRequested: Bool = false
    private var isChangingSelectedIndex: Bool = false
    
    func setCurrentControllerNode(_ node: ASDisplayNode?, backgroundChangeSource: TabBarBackgroundChangeSource?) -> () -> Void {
        guard node !== self.currentControllerNode else {
            return {}
        }
        
        let previousNode = self.currentControllerNode
        self.currentControllerNode = node
            if let currentControllerNode = self.currentControllerNode {
            if let previousNode {
                self.insertSubnode(currentControllerNode, aboveSubnode: previousNode)
            } else {
                self.insertSubnode(currentControllerNode, at: 0)
            }
            self.view.bringSubviewToFront(self.liquidTabBar)
            self.view.bringSubviewToFront(self.disabledOverlayNode.view)
        }

        self.updateTabBarCaptureConfiguration()
        self.backgroundUpdateDriver.setSource(backgroundChangeSource)
        self.backgroundUpdateDriver.warmup(frames: 2)

        self.requestUpdate()
        
        return { [weak self, weak previousNode] in
            if previousNode !== self?.currentControllerNode {
                previousNode?.removeFromSupernode()
            }
        }
    }
    
    init(theme: PresentationTheme, itemSelected: @escaping (Int, Bool, [ASDisplayNode]) -> Void, contextAction: @escaping (Int, ContextExtractedContentContainingView, ContextGesture) -> Void, swipeAction: @escaping (Int, TabBarItemSwipeDirection) -> Void, toolbarActionSelected: @escaping (ToolbarActionOption) -> Void, disabledPressed: @escaping () -> Void) {
        self.theme = theme
        self.itemSelected = itemSelected
        self.contextAction = contextAction
        self.liquidTabBar = LiquidGlassTabBar(metalContext: LiquidGlassSharedContext.metalContext)
        self.backgroundUpdateDriver = TabBarBackgroundUpdateDriver(invalidator: self.liquidTabBar)
        self.disabledOverlayNode = ASDisplayNode()
        self.disabledOverlayNode.backgroundColor = theme.rootController.tabBar.backgroundColor.withAlphaComponent(0.5)
        self.disabledOverlayNode.alpha = 0.0
        self.disabledOverlayNode.isUserInteractionEnabled = false
        self.toolbarActionSelected = toolbarActionSelected
        self.disabledPressed = disabledPressed
        
        super.init()
        
        self.setViewBlock({
            return View(frame: CGRect())
        })
        
        (self.view as? View)?.onLayout = { [weak self] in
            guard let self else {
                return
            }
            if self.isUpdateRequested {
                self.isUpdateRequested = false
                if let layoutResult = self.layoutResult {
                    let _ = self.updateImpl(params: layoutResult.params, transition: .immediate)
                }
            }
        }
        
        self.backgroundColor = theme.list.plainBackgroundColor

        let tabBarHeight: CGFloat = 100.0
        let inset: CGFloat = 16.0
        self.liquidTabBar.cornerRadius = (tabBarHeight - inset * 2.0) / 2.0
        self.liquidTabBar.spacing = 6.0
        self.liquidTabBar.contentInsets = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        self.liquidTabBar.restingKnobSize = CGSize(width: 75.0, height: 50.0)
        self.liquidTabBar.liquidKnobSize = CGSize(width: 100.0, height: 75.0)
        self.liquidTabBar.onTabSelected = { [weak self] index in
            self?.itemSelected(index, false, [])
        }

        self.addSubnode(self.disabledOverlayNode)
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.disabledOverlayNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.disabledTapGesture(_:))))
    }
    
    @objc private func disabledTapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.disabledPressed()
        }
    }
    
    func updateTheme(_ theme: PresentationTheme) {
        self.theme = theme
        self.backgroundColor = theme.list.plainBackgroundColor
        
        self.disabledOverlayNode.backgroundColor = theme.rootController.tabBar.backgroundColor.withAlphaComponent(0.5)
        self.toolbarNode?.updateTheme(ToolbarTheme(theme: theme))
        self.requestUpdate()
    }
    
    func updateIsTabBarEnabled(_ value: Bool, transition: ContainedViewLayoutTransition) {
        self.disabledOverlayNode.isUserInteractionEnabled = !value
        transition.updateAlpha(node: self.disabledOverlayNode, alpha: value ? 0.0 : 1.0)
    }
    
    var tabBarHidden = false {
        didSet {
            if self.tabBarHidden != oldValue {
                self.requestUpdate()
            }
        }
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, toolbar: Toolbar?, transition: ContainedViewLayoutTransition) -> CGFloat {
        let params = Params(layout: layout, toolbar: toolbar, isTabBarHidden: self.tabBarHidden)
        if let layoutResult = self.layoutResult, layoutResult.params == params {
            return layoutResult.bottomInset
        } else {
            let bottomInset = self.updateImpl(params: params, transition: transition)
            self.layoutResult = LayoutResult(params: params, bottomInset: bottomInset)
            return bottomInset
        }
    }
    
    private func requestUpdate() {
        self.isUpdateRequested = true
        self.view.setNeedsLayout()
    }

    private func updateTabBarCaptureConfiguration() {
        let captureView = self.currentControllerNode?.view
        if self.liquidTabBar.captureView !== captureView {
            self.liquidTabBar.captureView = captureView
        }
        self.liquidTabBar.roiProvider = { [weak self] in
            guard let self, let captureView = self.liquidTabBar.captureView else {
                return .zero
            }
            return self.liquidTabBar.convert(self.liquidTabBar.bounds, to: captureView)
        }
    }

    private func makeLiquidTabItemView(item: UITabBarItem, isSelected: Bool) -> UIView {
        let container = UIView()

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = isSelected ? self.theme.rootController.tabBar.selectedIconColor : self.theme.rootController.tabBar.iconColor

        let label = UILabel()
        label.text = item.title
        label.textColor = isSelected ? self.theme.rootController.tabBar.selectedTextColor : self.theme.rootController.tabBar.textColor
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontSizeToFitWidth = true

        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let image = (isSelected ? (item.selectedImage ?? item.image) : (item.image ?? item.selectedImage))?.withRenderingMode(.alwaysTemplate)
        imageView.image = image

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 22.0),
            imageView.heightAnchor.constraint(equalToConstant: 22.0)
        ])

        if let badgeValue = item.badgeValue, !badgeValue.isEmpty {
            let badgeLabel = BadgeLabel()
            badgeLabel.translatesAutoresizingMaskIntoConstraints = false
            badgeLabel.isUserInteractionEnabled = false
            badgeLabel.text = badgeValue
            badgeLabel.font = .systemFont(ofSize: 12.0, weight: .semibold)
            badgeLabel.textAlignment = .center
            badgeLabel.textColor = self.theme.rootController.tabBar.badgeTextColor
            badgeLabel.backgroundColor = self.theme.rootController.tabBar.badgeBackgroundColor
            badgeLabel.layer.masksToBounds = true
            badgeLabel.layer.cornerRadius = 9.0
            container.addSubview(badgeLabel)

            NSLayoutConstraint.activate([
                badgeLabel.centerXAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 0.0),
                badgeLabel.centerYAnchor.constraint(equalTo: imageView.topAnchor, constant: 0.0),
                badgeLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 18.0),
                badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18.0)
            ])
        }

        return container
    }
    
    private func updateImpl(params: Params, transition: ContainedViewLayoutTransition) -> CGFloat {
        var options: ContainerViewLayoutInsetOptions = []
        if params.layout.metrics.widthClass == .regular {
            options.insert(.input)
        }
        
        var bottomInset: CGFloat = params.layout.insets(options: options).bottom
        if bottomInset == 0.0 {
            bottomInset = 8.0
        } else {
            bottomInset = max(bottomInset, 8.0)
        }
        let sideInset: CGFloat = 20.0
        let tabBarContentInset: CGFloat = 16.0

        let tabBarHeight: CGFloat = 100.0

        if self.liquidTabBar.superview == nil {
            self.view.addSubview(self.liquidTabBar)
        }
        self.view.bringSubviewToFront(self.liquidTabBar)
        self.view.bringSubviewToFront(self.disabledOverlayNode.view)

        let tabViews: [UIView] = self.tabBarItems.enumerated().map { index, item in
            self.makeLiquidTabItemView(item: item.item, isSelected: index == self.selectedIndex)
        }
        self.liquidTabBar.tabViews = tabViews
        if !tabViews.isEmpty {
        self.liquidTabBar.selectedIndex = max(0, min(self.selectedIndex, tabViews.count - 1))
        }

        self.updateTabBarCaptureConfiguration()
        self.backgroundUpdateDriver.setIsVisible(params.toolbar == nil && !params.isTabBarHidden)

        // The Metal view must span the full screen width so the knob can move beyond the visible pill
        // without being clipped. We preserve the previous visual margins by moving them into the
        // tab bar's internal content insets.
        self.liquidTabBar.contentInsets = UIEdgeInsets(
            top: tabBarContentInset,
            left: tabBarContentInset + sideInset,
            bottom: tabBarContentInset,
            right: tabBarContentInset + sideInset
        )
        
        let tabBarFrame = CGRect(
            x: 0.0,
            y: params.layout.size.height - (self.tabBarHidden ? 0.0 : (tabBarHeight + bottomInset)),
            width: params.layout.size.width,
            height: tabBarHeight
        )
        transition.updateFrame(view: self.liquidTabBar, frame: tabBarFrame)
        transition.updateAlpha(layer: self.liquidTabBar.layer, alpha: params.toolbar == nil ? 1.0 : 0.0)
        
        transition.updateFrame(node: self.disabledOverlayNode, frame: tabBarFrame)
        
        let toolbarHeight = 50.0 + params.layout.insets(options: options).bottom
        let toolbarFrame = CGRect(origin: CGPoint(x: 0.0, y: params.layout.size.height - toolbarHeight), size: CGSize(width: params.layout.size.width, height: toolbarHeight))
        
        if let toolbar = params.toolbar {
            if let toolbarNode = self.toolbarNode {
                transition.updateFrame(node: toolbarNode, frame: toolbarFrame)
                toolbarNode.updateLayout(size: toolbarFrame.size, leftInset: params.layout.safeInsets.left, rightInset: params.layout.safeInsets.right, additionalSideInsets: params.layout.additionalInsets, bottomInset: bottomInset, toolbar: toolbar, transition: transition)
            } else {
                let toolbarNode = ToolbarNode(theme: ToolbarTheme(theme: self.theme), displaySeparator: true, left: { [weak self] in
                    self?.toolbarActionSelected(.left)
                }, right: { [weak self] in
                    self?.toolbarActionSelected(.right)
                }, middle: { [weak self] in
                    self?.toolbarActionSelected(.middle)
                })
                toolbarNode.frame = toolbarFrame
                toolbarNode.updateLayout(size: toolbarFrame.size, leftInset: params.layout.safeInsets.left, rightInset: params.layout.safeInsets.right, additionalSideInsets: params.layout.additionalInsets, bottomInset: bottomInset, toolbar: toolbar, transition: .immediate)
                self.addSubnode(toolbarNode)
                self.toolbarNode = toolbarNode
                if transition.isAnimated {
                    toolbarNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            }
        } else if let toolbarNode = self.toolbarNode {
            self.toolbarNode = nil
            transition.updateAlpha(node: toolbarNode, alpha: 0.0, completion: { [weak toolbarNode] _ in
                toolbarNode?.removeFromSupernode()
            })
        }
        
        return params.layout.size.height - tabBarFrame.minY
    }
    
    func frameForControllerTab(at index: Int) -> CGRect? {
        guard let tabFrame = self.liquidTabBar.frameForTab(at: index) else {
            return nil
        }
        return self.liquidTabBar.convert(tabFrame, to: self.view)
    }
    
    func isPointInsideContentArea(point: CGPoint) -> Bool {
        if point.y < self.liquidTabBar.frame.minY {
            return true
        }
        return false
    }
    
    func updateTabBarItems(items: [TabBarNodeItem]) {
        self.tabBarItems = items
        self.requestUpdate()
    }
    
    func updateSelectedIndex(index: Int) {
        self.selectedIndex = index
        self.isChangingSelectedIndex = true
        self.requestUpdate()
    }
}
