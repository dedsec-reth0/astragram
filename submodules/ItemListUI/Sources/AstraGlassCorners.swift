import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData

/// AstraGram Liquid Glass: rows of a grouped list round their section's corners with an overlay image painted in the
/// page colour. Over the aurora that colour shows as dark wedges, so here the overlay cuts the corners out of the row
/// instead: it is drawn with `destOut` inside the row, which is flattened into one cached bitmap (the cut needs a group
/// to cut within; rasterized, it costs nothing while the list scrolls).
///
/// `band` is the list's card column in list coordinates: rows paint their background across the whole width (in stock
/// the side margins are covered with the page colour), so a glass row is clipped to the column.
public func astraPunchListCorners(in node: ASDisplayNode, band: (minX: CGFloat, maxX: CGFloat)?) {
    guard let subnodes = node.subnodes else {
        return
    }
    var found = false
    if let band {
        let maskLayer: CALayer
        if let current = node.layer.mask, current.name == "astraBand" {
            maskLayer = current
        } else if node.layer.mask == nil {
            maskLayer = CALayer()
            maskLayer.name = "astraBand"
            maskLayer.backgroundColor = UIColor.black.cgColor
            node.layer.mask = maskLayer
        } else {
            maskLayer = CALayer()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = CGRect(x: band.minX - node.frame.minX, y: -2.0, width: max(0.0, band.maxX - band.minX), height: node.bounds.height + 4.0)
        CATransaction.commit()
        // Masked, the row is cached as one bitmap, so the mask costs nothing while the list scrolls.
        found = true
    }
    for subnode in subnodes {
        guard let imageNode = subnode as? ASImageNode else {
            continue
        }
        if let image = imageNode.image, astraIsListCornerImage(image) {
            found = true

            if imageNode.layer.compositingFilter as? String != "destOut" {
                imageNode.layer.compositingFilter = "destOut"
            }
        } else if imageNode.layer.compositingFilter as? String == "destOut" {
            imageNode.layer.compositingFilter = nil
        }
    }
    if found {
        if !node.layer.shouldRasterize {
            node.layer.rasterizationScale = UIScreenScale
            node.layer.shouldRasterize = true
        }
    } else if node.layer.shouldRasterize && node.layer.rasterizationScale == UIScreenScale {
        node.layer.shouldRasterize = false
    }
}
