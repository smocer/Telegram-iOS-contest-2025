import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import LiquidGlassUI

final class LiquidGlassSwitchItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let systemStyle: ItemListSystemStyle
    let title: String
    let value: Bool
    let enabled: Bool
    let sectionId: ItemListSectionId
    let style: ItemListStyle
    let updated: (Bool) -> Void
    let tag: ItemListItemTag?
    
    init(
        presentationData: ItemListPresentationData,
        systemStyle: ItemListSystemStyle,
        title: String,
        value: Bool,
        enabled: Bool = true,
        sectionId: ItemListSectionId,
        style: ItemListStyle,
        updated: @escaping (Bool) -> Void,
        tag: ItemListItemTag? = nil
    ) {
        self.presentationData = presentationData
        self.systemStyle = systemStyle
        self.title = title
        self.value = value
        self.enabled = enabled
        self.sectionId = sectionId
        self.style = style
        self.updated = updated
        self.tag = tag
    }
    
    func nodeConfiguredForParams(
        async: @escaping (@escaping () -> Void) -> Void,
        params: ListViewItemLayoutParams,
        synchronousLoads: Bool,
        previousItem: ListViewItem?,
        nextItem: ListViewItem?,
        completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void
    ) {
        async {
            let node = LiquidGlassSwitchItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply(false) })
                })
            }
        }
    }
    
    func updateNode(
        async: @escaping (@escaping () -> Void) -> Void,
        node: @escaping () -> ListViewItemNode,
        params: ListViewItemLayoutParams,
        previousItem: ListViewItem?,
        nextItem: ListViewItem?,
        animation: ListViewItemUpdateAnimation,
        completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void
    ) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? LiquidGlassSwitchItemNode {
                let makeLayout = nodeValue.asyncLayout()
                
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            let animated: Bool
                            switch animation {
                            case .None:
                                animated = false
                            default:
                                animated = true
                            }
                            apply(animated)
                        })
                    }
                }
            }
        }
    }
    
    var selectable: Bool {
        false
    }
    
    func selected(listView: ListView) {
    }
}

final class LiquidGlassSwitchItemNode: ListViewItemNode, ItemListItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let highlightedBackgroundNode: ASDisplayNode
    private let maskNode: ASImageNode
    
    private let titleNode: TextNode
    private let switchNode: ASDisplayNode
    private var switchView: LiquidGlassSwitch?
    
    private let activateArea: AccessibilityAreaNode
    
    private var item: LiquidGlassSwitchItem?
    
    var tag: ItemListItemTag? {
        return self.item?.tag
    }
    
    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        self.backgroundNode.backgroundColor = .white
        
        self.maskNode = ASImageNode()
        self.maskNode.isUserInteractionEnabled = false
        
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        
        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isLayerBacked = true
        
        self.titleNode = TextNode()
        self.titleNode.anchorPoint = CGPoint()
        self.titleNode.isUserInteractionEnabled = false

        self.switchNode = ASDisplayNode(viewBlock: {
            let view = LiquidGlassSwitch(metalContext: LiquidGlassSharedContext.metalContext)
            view.trackInsets = UIEdgeInsets(top: 2.0, left: 2.0, bottom: 2.0, right: 2.0)
            return view
        })
        self.switchNode.clipsToBounds = true
        
        self.activateArea = AccessibilityAreaNode()
        
        super.init(layerBacked: false, dynamicBounce: false)
        
        self.addSubnode(self.switchNode)
        self.switchNode.addSubnode(self.titleNode)
        self.addSubnode(self.activateArea)
        
        self.activateArea.activate = { [weak self] in
            guard let self, let item = self.item, item.enabled else {
                return false
            }
            let value = !(self.switchView?.isOn ?? item.value)
            self.switchView?.setOn(value, animated: true)
            item.updated(value)
            return true
        }
    }
    
    override func didLoad() {
        super.didLoad()
        let switchView = self.switchNode.view as? LiquidGlassSwitch
        self.switchView = switchView
        switchView?.addTarget(self, action: #selector(self.switchValueChanged(_:)), for: .valueChanged)
    }
    
    func asyncLayout() -> (_ item: LiquidGlassSwitchItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, (Bool) -> Void) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        
        let currentItem = self.item
        
        return { item, params, neighbors in
            let separatorHeight = UIScreenPixel
            let separatorRightInset: CGFloat = item.systemStyle == .glass ? 16.0 : 0.0
            
            let titleFont = Font.regular(item.presentationData.fontSize.itemListBaseFontSize)
            
            var updatedTheme: PresentationTheme?
            if currentItem?.presentationData.theme !== item.presentationData.theme {
                updatedTheme = item.presentationData.theme
            }
            
            let itemBackgroundColor: UIColor
            let itemSeparatorColor: UIColor
            var contentSize = CGSize(width: params.width, height: 44.0)
            let insets: UIEdgeInsets
            switch item.style {
            case .plain:
                itemBackgroundColor = item.presentationData.theme.list.plainBackgroundColor
                itemSeparatorColor = item.presentationData.theme.list.itemPlainSeparatorColor
                insets = itemListNeighborsPlainInsets(neighbors)
            case .blocks:
                itemBackgroundColor = item.presentationData.theme.list.itemBlocksBackgroundColor
                itemSeparatorColor = item.presentationData.theme.list.itemBlocksSeparatorColor
                insets = itemListNeighborsGroupedInsets(neighbors, params)
            }
            
            var topInset: CGFloat = 11.0
            if case .glass = item.systemStyle {
                contentSize.height = 52.0
                topInset += 4.0
            }
            
            let leftInset = 16.0 + params.leftInset
            
            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: item.title, font: titleFont, textColor: item.presentationData.theme.list.itemPrimaryTextColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - leftInset - params.rightInset - 84.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            
            contentSize.height = max(contentSize.height, titleLayout.size.height + topInset * 2.0)
            
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size
            
            return (layout, { [weak self] animated in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.item = item
                
                strongSelf.activateArea.frame = CGRect(origin: CGPoint(x: params.leftInset, y: 0.0), size: CGSize(width: params.width - params.leftInset - params.rightInset, height: layout.contentSize.height))
                strongSelf.activateArea.accessibilityLabel = item.title
                strongSelf.activateArea.accessibilityValue = item.value ? "1" : "0"
                
                let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeInOut) : .immediate
                
                if let _ = updatedTheme {
                    strongSelf.topStripeNode.backgroundColor = itemSeparatorColor
                    strongSelf.bottomStripeNode.backgroundColor = itemSeparatorColor
                    strongSelf.backgroundNode.backgroundColor = itemBackgroundColor
                    strongSelf.highlightedBackgroundNode.backgroundColor = item.presentationData.theme.list.itemHighlightedBackgroundColor
                }
                
                switch item.style {
                case .plain:
                    if strongSelf.backgroundNode.supernode != nil {
                        strongSelf.backgroundNode.removeFromSupernode()
                    }
                    if strongSelf.topStripeNode.supernode != nil {
                        strongSelf.topStripeNode.removeFromSupernode()
                    }
                    if strongSelf.maskNode.supernode != nil {
                        strongSelf.maskNode.removeFromSupernode()
                    }
                    
                    if strongSelf.bottomStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.bottomStripeNode, aboveSubnode: strongSelf.switchNode)
                    }
                    strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: leftInset, y: contentSize.height - separatorHeight), size: CGSize(width: params.width - leftInset, height: separatorHeight))
                case .blocks:
                    if strongSelf.backgroundNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    }
                    if strongSelf.topStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.topStripeNode, aboveSubnode: strongSelf.switchNode)
                    }
                    if strongSelf.bottomStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.bottomStripeNode, aboveSubnode: strongSelf.topStripeNode)
                    }
                    if strongSelf.maskNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.maskNode, aboveSubnode: strongSelf.bottomStripeNode)
                    }
                    
                    let hasCorners = itemListHasRoundedBlockLayout(params)
                    var hasTopCorners = false
                    var hasBottomCorners = false
                    switch neighbors.top {
                    case .sameSection(false):
                        strongSelf.topStripeNode.isHidden = true
                    default:
                        hasTopCorners = true
                        strongSelf.topStripeNode.isHidden = hasCorners
                    }
                    
                    let bottomStripeInset: CGFloat
                    switch neighbors.bottom {
                    case .sameSection(false):
                        bottomStripeInset = leftInset
                        strongSelf.bottomStripeNode.isHidden = false
                    default:
                        bottomStripeInset = 0.0
                        hasBottomCorners = true
                        strongSelf.bottomStripeNode.isHidden = hasCorners
                    }
                    
                    strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.presentationData.theme, top: hasTopCorners, bottom: hasBottomCorners, glass: item.systemStyle == .glass) : nil
                    
                    transition.updateFrame(node: strongSelf.backgroundNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight))))
                    transition.updateFrame(node: strongSelf.maskNode, frame: strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0))
                    transition.updateFrame(node: strongSelf.topStripeNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight)))
                    transition.updateFrame(node: strongSelf.bottomStripeNode, frame: CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height - separatorHeight), size: CGSize(width: layoutSize.width - params.rightInset - bottomStripeInset - separatorRightInset, height: separatorHeight)))
                }
                
                let _ = titleApply()
                let titleFrame = CGRect(origin: CGPoint(x: leftInset, y: topInset), size: titleLayout.size)
                let switchFrame = CGRect(origin: CGPoint(x: params.leftInset, y: 0.0), size: CGSize(width: params.width - params.leftInset - params.rightInset, height: contentSize.height))
                let localTitleOrigin = CGPoint(x: titleFrame.minX - switchFrame.minX, y: titleFrame.minY - switchFrame.minY)
                transition.updatePosition(node: strongSelf.titleNode, position: localTitleOrigin)
                strongSelf.titleNode.bounds = CGRect(origin: CGPoint(), size: titleFrame.size)
                
                let _ = strongSelf.view
                transition.updateFrame(node: strongSelf.switchNode, frame: switchFrame)

                if let switchView = strongSelf.switchView {
                    let baseTrackInset: CGFloat = 2.0
                    let intrinsicSize = switchView.intrinsicContentSize
                    let trackSize = CGSize(width: intrinsicSize.width - baseTrackInset * 2.0, height: intrinsicSize.height - baseTrackInset * 2.0)
                    let verticalInset = max(0.0, floor((switchFrame.height - trackSize.height) * 0.5))
                    let rightInset: CGFloat = 20.0 + baseTrackInset
                    let leftInset = max(0.0, switchFrame.width - trackSize.width - rightInset)
                    let trackInsets = UIEdgeInsets(top: verticalInset, left: leftInset, bottom: verticalInset, right: rightInset)
                    if switchView.trackInsets != trackInsets {
                        switchView.trackInsets = trackInsets
                    }
                    
                    if switchView.isOn != item.value {
                        switchView.isOn = item.value
                    }
                    
                    switchView.isEnabled = item.enabled
                    
                    switchView.backgroundHostColor = itemBackgroundColor
                    let switchColors = item.presentationData.theme.list.itemSwitchColors
                    switchView.offTintColor = switchColors.frameColor
                    switchView.onTintColor = switchColors.contentColor
                    switchView.knobColor = switchColors.handleColor
                }
                
                transition.updateFrame(node: strongSelf.highlightedBackgroundNode, frame: CGRect(origin: CGPoint(x: 0.0, y: -UIScreenPixel), size: CGSize(width: params.width, height: layoutSize.height + UIScreenPixel + UIScreenPixel)))
            })
        }
    }
    
    override func accessibilityActivate() -> Bool {
        guard let item = self.item, item.enabled else {
            return false
        }
        let value = !(self.switchView?.isOn ?? item.value)
        self.switchView?.setOn(value, animated: true)
        item.updated(value)
        return true
    }
    
    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        super.setHighlighted(highlighted, at: point, animated: animated)
        
        if highlighted {
            self.highlightedBackgroundNode.alpha = 1.0
            if self.highlightedBackgroundNode.supernode == nil {
                var anchorNode: ASDisplayNode?
                if self.bottomStripeNode.supernode != nil {
                    anchorNode = self.bottomStripeNode
                } else if self.topStripeNode.supernode != nil {
                    anchorNode = self.topStripeNode
                } else if self.backgroundNode.supernode != nil {
                    anchorNode = self.backgroundNode
                }
                if let anchorNode = anchorNode {
                    self.insertSubnode(self.highlightedBackgroundNode, aboveSubnode: anchorNode)
                } else {
                    self.addSubnode(self.highlightedBackgroundNode)
                }
            }
        } else if self.highlightedBackgroundNode.supernode != nil {
            if animated {
                self.highlightedBackgroundNode.layer.animateAlpha(from: self.highlightedBackgroundNode.alpha, to: 0.0, duration: 0.4, completion: { [weak self] completed in
                    guard let self else { return }
                    if completed {
                        self.highlightedBackgroundNode.removeFromSupernode()
                    }
                })
                self.highlightedBackgroundNode.alpha = 0.0
            } else {
                self.highlightedBackgroundNode.removeFromSupernode()
            }
        }
    }
    
    @objc private func switchValueChanged(_ switchView: LiquidGlassSwitch) {
        if let item = self.item {
            item.updated(switchView.isOn)
        }
    }
}
