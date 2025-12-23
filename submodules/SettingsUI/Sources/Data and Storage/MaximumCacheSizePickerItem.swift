import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import LiquidGlassUI

private func totalDiskSpace() -> Int64 {
    do {
        let systemAttributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory() as String)
        return (systemAttributes[FileAttributeKey.systemSize] as? NSNumber)?.int64Value ?? 0
    } catch {
        return 0
    }
}

private func stringForCacheSize(strings: PresentationStrings, size: Int32) -> String {
    if size > 100 {
        return strings.Cache_NoLimit
    } else {
        return dataSizeString(Int64(size) * 1024 * 1024 * 1024, formatting: DataSizeStringFormatting(strings: strings, decimalSeparator: "."))
    }
}

private let maximumCacheSizeValues: [Int32] = {
    let diskSpace = totalDiskSpace()
    if diskSpace > 100 * 1024 * 1024 * 1024 {
        return [5, 20, 50, Int32.max]
    } else if diskSpace > 50 * 1024 * 1024 * 1024 {
        return [5, 16, 32, Int32.max]
    } else if diskSpace > 24 * 1024 * 1024 * 1024 {
        return [2, 8, 16, Int32.max]
    } else {
        return [1, 4, 8, Int32.max]
    }
}()

final class MaximumCacheSizePickerItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let strings: PresentationStrings
    let value: Int32
    let sectionId: ItemListSectionId
    let updated: (Int32) -> Void
    
    init(theme: PresentationTheme, strings: PresentationStrings, value: Int32, sectionId: ItemListSectionId, updated: @escaping (Int32) -> Void) {
        self.theme = theme
        self.strings = strings
        self.value = value
        self.sectionId = sectionId
        self.updated = updated
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = MaximumCacheSizePickerItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            
            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? MaximumCacheSizePickerItemNode {
                let makeLayout = nodeValue.asyncLayout()
                
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

private final class MaximumCacheSizePickerItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode
    
    private let textNodes: [TextNode]
    private var sliderView: LiquidGlassSlider<Int32>?
    
    private var item: MaximumCacheSizePickerItem?
    private var layoutParams: ListViewItemLayoutParams?
    
    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        
        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true
        
        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true
        
        self.maskNode = ASImageNode()
        
        var textNodes: [TextNode] = []
        for _ in 0 ..< 4 {
            let textNode = TextNode()
            textNode.isUserInteractionEnabled = false
            textNode.displaysAsynchronously = false
            textNodes.append(textNode)
        }
        self.textNodes = textNodes

        super.init(layerBacked: false, dynamicBounce: false)
        
        for textNode in textNodes {
            self.addSubnode(textNode)
        }
    }
    
    func updateSliderView() {
        if let sliderView = self.sliderView, let item = self.item {
            let value = maximumCacheSizeValues.firstIndex(where: { $0 == item.value }) ?? 0
            sliderView.setSelectedIndex(value, animated: false)
        }
    }
    
    override func didLoad() {
        super.didLoad()
        
        let sliderView = LiquidGlassSlider<Int32>(metalContext: LiquidGlassSharedContext.metalContext, snappingValues: maximumCacheSizeValues)
        if let item = self.item, let params = self.layoutParams {
            let value = maximumCacheSizeValues.firstIndex(where: { $0 == item.value }) ?? 0
            sliderView.setSelectedIndex(value, animated: false)
            
            sliderView.frame = CGRect(origin: CGPoint(x: params.leftInset + 15.0, y: 37.0), size: CGSize(width: params.width - params.leftInset - params.rightInset - 15.0 * 2.0, height: 44.0))
            
            sliderView.backgroundHostColor = item.theme.list.itemBlocksBackgroundColor
            sliderView.trackTintColor = item.theme.list.itemSwitchColors.frameColor
            sliderView.fillTintColor = item.theme.list.itemAccentColor
            sliderView.knobColor = item.theme.list.itemSwitchColors.handleColor
        }
        self.view.addSubview(sliderView)
        sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
        self.sliderView = sliderView
        
        self.updateSliderView()
    }
    
    func asyncLayout() -> (_ item: MaximumCacheSizePickerItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let currentItem = self.item
        var makeTextLayouts: [(TextNodeLayoutArguments) -> (TextNodeLayout, () -> TextNode)] = []
        for textNode in self.textNodes {
            makeTextLayouts.append(TextNode.asyncLayout(textNode))
        }

        return { item, params, neighbors in
            var themeUpdated = false
            if currentItem?.theme !== item.theme {
                themeUpdated = true
            }
            
            let contentSize: CGSize
            let insets: UIEdgeInsets
            let separatorHeight = UIScreenPixel
            
            var textLayouts: [TextNodeLayout] = []
            var textApplies: [() -> TextNode] = []
                                    
            for i in 0 ..< makeTextLayouts.count {
                let makeTextLayout = makeTextLayouts[i]
                let (textLayout, textApply) = makeTextLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: stringForCacheSize(strings: item.strings, size: maximumCacheSizeValues[i]), font: Font.regular(13.0), textColor: item.theme.list.itemSecondaryTextColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width, height: CGFloat.greatestFiniteMagnitude), alignment: .center, lineSpacing: 0.0, cutout: nil, insets: UIEdgeInsets()))
                textLayouts.append(textLayout)
                textApplies.append(textApply)
            }
            
            contentSize = CGSize(width: params.width, height: 88.0)
            insets = itemListNeighborsGroupedInsets(neighbors, params)
            
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            let layoutSize = layout.size
            
            return (layout, { [weak self] in
                if let strongSelf = self {
                    strongSelf.item = item
                    strongSelf.layoutParams = params
                    
                    strongSelf.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                    strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                    strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                    
                    if strongSelf.backgroundNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    }
                    if strongSelf.topStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                    }
                    if strongSelf.bottomStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                    }
                    if strongSelf.maskNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.maskNode, at: 3)
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
                    let bottomStripeOffset: CGFloat
                    switch neighbors.bottom {
                    case .sameSection(false):
                        bottomStripeInset = 0.0
                        bottomStripeOffset = -separatorHeight
                        strongSelf.bottomStripeNode.isHidden = false
                    default:
                        bottomStripeInset = 0.0
                        bottomStripeOffset = 0.0
                        hasBottomCorners = true
                        strongSelf.bottomStripeNode.isHidden = hasCorners
                    }
                    
                    strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners) : nil
                    
                    strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                    strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                    strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layoutSize.width, height: separatorHeight))
                    strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layoutSize.width - bottomStripeInset, height: separatorHeight))
                    
                    for apply in textApplies {
                        let _ = apply()
                    }
                    
                    var textNodes: [(TextNode, CGSize)] = []
                    for (node, size) in zip(strongSelf.textNodes, textLayouts.map { $0.size }) {
                        textNodes.append((node, size))
                    }
                    
                    let delta = (params.width - params.leftInset - params.rightInset - 18.0 * 2.0) / CGFloat(textNodes.count - 1)
                    for i in 0 ..< textNodes.count {
                        let (textNode, textSize) = textNodes[i]
                        
                        var position = params.leftInset + 18.0 + delta * CGFloat(i)
                        if i == textNodes.count - 1 {
                            position -= textSize.width
                        } else if i > 0 {
                            position -= textSize.width / 2.0
                        }
                        
                        textNode.frame = CGRect(origin: CGPoint(x: position, y: 15.0), size: textSize)
                    }
                    
                    if let sliderView = strongSelf.sliderView {
                        if themeUpdated {
                            sliderView.backgroundHostColor = item.theme.list.itemBlocksBackgroundColor
                            sliderView.trackTintColor = item.theme.list.itemSwitchColors.frameColor
                            sliderView.fillTintColor = item.theme.list.itemAccentColor
                            sliderView.knobColor = item.theme.list.itemSwitchColors.handleColor
                        }
                        
                        sliderView.frame = CGRect(origin: CGPoint(x: params.leftInset + 15.0, y: 37.0), size: CGSize(width: params.width - params.leftInset - params.rightInset - 15.0 * 2.0, height: 44.0))
                        
                        strongSelf.updateSliderView()
                    }
                }
            })
        }
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
    
    @objc private func sliderValueChanged() {
        guard let sliderView = self.sliderView else {
            return
        }
        self.item?.updated(sliderView.selectedValue)
    }
}
