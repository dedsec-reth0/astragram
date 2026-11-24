import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData

/// AstraGram Liquid Glass: rows of a grouped list round their section's corners with an overlay image painted in the
/// page colour. Over the aurora that colour shows as dark wedges, so here the overlay cuts the corners out of the row
/// instead: it is drawn with `destOut` inside the row, which is flattened into one cached bitmap (the cut needs a group
/// to cut within; rasterized, it costs nothing while the list scrolls).
public func astraPunchListCorners(in node: ASDisplayNode) {
    guard let subnodes = node.subnodes else {
        return
    }
    var found = false
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
