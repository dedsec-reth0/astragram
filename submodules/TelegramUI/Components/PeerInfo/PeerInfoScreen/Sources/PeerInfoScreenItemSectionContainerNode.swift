import Foundation
import UIKit
import Display
import AsyncDisplayKit
import AccountContext
import TelegramPresentationData

final class PeerInfoScreenItemSectionContainerNode: ASDisplayNode {
    private let backgroundNode: ASDisplayNode
    private let topSeparatorNode: ASDisplayNode
    private let bottomSeparatorNode: ASDisplayNode
    private let itemContainerNode: ASDisplayNode
    
    private var currentItems: [PeerInfoScreenItem] = []
    var itemNodes: [AnyHashable: PeerInfoScreenItemNode] = [:]
    
    override init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true
        
        self.topSeparatorNode = ASDisplayNode()
        self.topSeparatorNode.isLayerBacked = true
        
        self.bottomSeparatorNode = ASDisplayNode()
        self.bottomSeparatorNode.isLayerBacked = true
        
        self.itemContainerNode = ASDisplayNode()
        self.itemContainerNode.clipsToBounds = true
        
        super.init()
        
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.itemContainerNode)
        self.addSubnode(self.topSeparatorNode)
        self.addSubnode(self.bottomSeparatorNode)
    }
    
    /// AstraGram: the card's color while the profile flows through its gifts' colors (nil: the theme's).
    var astraTint: UIColor? {
        didSet {
            if let astraTint, !AstraLook.design2027 {
                self.backgroundNode.backgroundColor = astraTint
            } else if let themeColor = self.themeBackgroundColor {
                // Folio keeps one card material everywhere: the see-through tint (white @0.09 over the profile's
                // surface, which read lighter than the settings cards) gives way to the theme's card fill.
                self.backgroundNode.backgroundColor = themeColor
            }
            if (oldValue == nil) != (astraTint == nil) {
                self.astraUpdateClipping()
            }
        }
    }
    private var themeBackgroundColor: UIColor?
    /// The card's rect and the whole content's height, for clipping the theme-colored corners away while tinted.
    private var astraCardRect: CGRect = .zero
    private var astraContentHeight: CGFloat = 0.0
    private var astraWidth: CGFloat = 0.0
    private var astraHasCorners = false
    
    /// While tinted the items' corner images (painted in the theme's background) would show as dark corners: the card
    /// is clipped to its rounded shape instead.
    private func astraUpdateClipping() {
        guard self.astraUsesRoundedCard, self.astraCardRect.height > 0.0 else {
            self.itemContainerNode.layer.mask = nil
            self.backgroundNode.cornerRadius = 0.0
            return
        }
        let card = self.astraCardRect
        let path = UIBezierPath(rect: CGRect(x: 0.0, y: 0.0, width: self.astraWidth, height: card.minY))
        // A hair inside the items' own corner images, whose edge is painted in the theme's background.
        path.append(UIBezierPath(roundedRect: card.insetBy(dx: 0.75, dy: 0.75), cornerRadius: AstraLook.design2027 ? AstraLook.Folio.cardClipRadius : 25.25))
        path.append(UIBezierPath(rect: CGRect(x: 0.0, y: card.maxY, width: self.astraWidth, height: max(0.0, self.astraContentHeight - card.maxY))))
        let mask = (self.itemContainerNode.layer.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.frame = CGRect(x: 0.0, y: 0.0, width: self.astraWidth, height: self.astraContentHeight)
        mask.path = path.cgPath
        self.itemContainerNode.layer.mask = mask
    }
    
    /// Whether the card is drawn as a rounded slab of its own. Stock does so only while the card is tinted; Folio
    /// always does, so every profile card has the same 20pt continuous corners whatever its items' corner images say.
    private var astraUsesRoundedCard: Bool {
        if AstraLook.design2027 {
            return self.astraHasCorners
        } else {
            return self.astraTint != nil && self.astraHasCorners
        }
    }
    
    func update(context: AccountContext, width: CGFloat, safeInsets: UIEdgeInsets, hasCorners: Bool, presentationData: PresentationData, items: [PeerInfoScreenItem], transition: ContainedViewLayoutTransition) -> CGFloat {
        self.themeBackgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        if AstraLook.design2027 {
            // Folio: the same card material as the settings cards, whatever the profile's flow tint.
            self.backgroundNode.backgroundColor = presentationData.theme.list.itemBlocksBackgroundColor
        } else {
            self.backgroundNode.backgroundColor = self.astraTint ?? presentationData.theme.list.itemBlocksBackgroundColor
        }
        self.topSeparatorNode.backgroundColor = presentationData.theme.list.itemBlocksSeparatorColor
        self.bottomSeparatorNode.backgroundColor = presentationData.theme.list.itemBlocksSeparatorColor
        
        self.topSeparatorNode.isHidden = hasCorners
        self.bottomSeparatorNode.isHidden = hasCorners
        
        var contentHeight: CGFloat = 0.0
        var contentWithBackgroundHeight: CGFloat = 0.0
        var contentWithBackgroundOffset: CGFloat = 0.0
        
        for i in 0 ..< items.count {
            let item = items[i]
            
            let itemNode: PeerInfoScreenItemNode
            var wasAdded = false
            if let current = self.itemNodes[item.id] {
                itemNode = current
            } else {
                wasAdded = true
                itemNode = item.node()
                self.itemNodes[item.id] = itemNode
                self.itemContainerNode.addSubnode(itemNode)
                itemNode.bringToFrontForHighlight = { [weak self, weak itemNode] in
                    guard let strongSelf = self, let itemNode = itemNode else {
                        return
                    }
                    strongSelf.view.bringSubviewToFront(itemNode.view)
                }
            }
            
            let itemTransition: ContainedViewLayoutTransition = wasAdded ? .immediate : transition
            
            let topItem: PeerInfoScreenItem?
            if i == 0 {
                topItem = nil
            } else if items[i - 1] is PeerInfoScreenHeaderItem {
                topItem = nil
            } else {
                topItem = items[i - 1]
            }
            
            let bottomItem: PeerInfoScreenItem?
            if i == items.count - 1 {
                bottomItem = nil
            } else if items[i + 1] is PeerInfoScreenCommentItem {
                bottomItem = nil
            } else {
                bottomItem = items[i + 1]
            }
            
            let itemHeight = itemNode.update(context: context, width: width, safeInsets: safeInsets, presentationData: presentationData, item: item, topItem: topItem, bottomItem: bottomItem, hasCorners: hasCorners, transition: itemTransition)
            let itemFrame = CGRect(origin: CGPoint(x: 0.0, y: contentHeight), size: CGSize(width: width, height: itemHeight))
            itemTransition.updateFrame(node: itemNode, frame: itemFrame)
            if wasAdded {
                itemNode.alpha = 0.0
                let alphaTransition: ContainedViewLayoutTransition = transition.isAnimated ? .animated(duration: 0.35, curve: .linear) : .immediate
                alphaTransition.updateAlpha(node: itemNode, alpha: 1.0)
            }
            
            if item is PeerInfoScreenCommentItem {
            } else {
                contentWithBackgroundHeight += itemHeight
            }
            contentHeight += itemHeight
            
            if item is PeerInfoScreenHeaderItem {
                contentWithBackgroundOffset = contentHeight
            }
        }
        
        var removeIds: [AnyHashable] = []
        for (id, _) in self.itemNodes {
            if !items.contains(where: { $0.id == id }) {
                removeIds.append(id)
            }
        }
        for id in removeIds {
            if let itemNode = self.itemNodes.removeValue(forKey: id) {
                itemNode.view.superview?.sendSubviewToBack(itemNode.view)
                transition.updateAlpha(node: itemNode, alpha: 0.0, completion: { [weak itemNode] _ in
                    itemNode?.removeFromSupernode()
                })
            }
        }
        
        transition.updateFrame(node: self.itemContainerNode, frame: CGRect(origin: CGPoint(), size: CGSize(width: width, height: contentHeight)))
        let cardRect = CGRect(x: safeInsets.left, y: contentWithBackgroundOffset, width: width - safeInsets.left - safeInsets.right, height: max(0.0, contentWithBackgroundHeight - contentWithBackgroundOffset))
        self.astraCardRect = cardRect
        self.astraContentHeight = contentHeight
        self.astraWidth = width
        self.astraHasCorners = hasCorners
        if self.astraUsesRoundedCard {
            // The tinted card (or, under Folio, every card) in its rounded shape.
            transition.updateFrame(node: self.backgroundNode, frame: cardRect)
            if AstraLook.design2027 {
                self.backgroundNode.layer.cornerCurve = .continuous
                self.backgroundNode.cornerRadius = AstraLook.Folio.cardRadius
            } else {
                self.backgroundNode.layer.cornerCurve = .circular
                self.backgroundNode.cornerRadius = 26.0
            }
        } else {
            // The stock corner curve is restored too, so turning Folio off on a live card leaves no trace.
            self.backgroundNode.layer.cornerCurve = .circular
            self.backgroundNode.cornerRadius = 0.0
            transition.updateFrame(node: self.backgroundNode, frame: CGRect(origin: CGPoint(x: 0.0, y: contentWithBackgroundOffset), size: CGSize(width: width, height: max(0.0, contentWithBackgroundHeight - contentWithBackgroundOffset))))
        }
        self.astraUpdateClipping()
        transition.updateFrame(node: self.topSeparatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: contentWithBackgroundOffset - UIScreenPixel), size: CGSize(width: width, height: UIScreenPixel)))
        transition.updateFrame(node: self.bottomSeparatorNode, frame: CGRect(origin: CGPoint(x: 0.0, y: contentWithBackgroundHeight), size: CGSize(width: width, height: UIScreenPixel)))
        
        if contentHeight.isZero {
            transition.updateAlpha(node: self.topSeparatorNode, alpha: 0.0)
            transition.updateAlpha(node: self.bottomSeparatorNode, alpha: 0.0)
        } else {
            transition.updateAlpha(node: self.topSeparatorNode, alpha: 1.0)
            transition.updateAlpha(node: self.bottomSeparatorNode, alpha: 1.0)
        }
        
        return contentHeight
    }
    
    func animateErrorIfNeeded() {
        for (_, itemNode) in self.itemNodes {
            if let itemNode = itemNode as? PeerInfoScreenMultilineInputItemNode {
                itemNode.animateErrorIfNeeded()
            }
        }
    }
}
