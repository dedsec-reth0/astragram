import Foundation
import UIKit
import TelegramCore
import TelegramPresentationData
import Display
import AsyncDisplayKit

/// AstraGram "Liquid Glass+ (beta)": the chat list over a soft gradient, as a floating rounded card (after the Liquid Glass
/// Telegram concept). Read once at launch: switching it applies after the app restarts.
enum AstraLiquidGlass {
    /// The gradient-and-card background is off: the concept's gradient turned out to be the backdrop of its
    /// presentation picture, not part of the app. The beta look now changes the tab bar (TelegramRootController).
    static let isEnabled: Bool = AstraGramSettings.current.liquidGlassBeta && AstraLiquidGlass.gradientBackground
    private static let gradientBackground: Bool = UserDefaults.standard.bool(forKey: "astragram.liquidGlass.gradientBackground")

    /// The chat list background: clear in the beta look, so the gradient and the card show through.
    static func chatListBackgroundColor(_ theme: PresentationTheme) -> UIColor {
        // The Liquid Glass design shows its aurora (behind the controller node) through the list.
        return (AstraLiquidGlass.isEnabled || theme.isAstraLiquidGlass) ? .clear : theme.chatList.backgroundColor
    }
}

final class AstraLiquidGlassBackgroundView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let cardView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.gradientLayer)
        self.cardView.layer.cornerRadius = 26.0
        self.cardView.layer.cornerCurve = .continuous
        self.cardView.layer.shadowColor = UIColor.black.cgColor
        self.cardView.layer.shadowOpacity = 0.08
        self.cardView.layer.shadowRadius = 18.0
        self.cardView.layer.shadowOffset = CGSize(width: 0.0, height: 6.0)
        self.addSubview(self.cardView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(theme: PresentationTheme, size: CGSize, cardTop: CGFloat) {
        let isDark = theme.overallDarkAppearance
        if isDark {
            self.gradientLayer.colors = [
                UIColor(red: 0.04, green: 0.03, blue: 0.04, alpha: 1.0).cgColor,
                UIColor(red: 0.09, green: 0.20, blue: 0.33, alpha: 1.0).cgColor,
                UIColor(red: 0.13, green: 0.29, blue: 0.33, alpha: 1.0).cgColor
            ]
            self.cardView.backgroundColor = UIColor(white: 0.11, alpha: 0.92)
        } else {
            self.gradientLayer.colors = [
                UIColor(red: 0.47, green: 0.70, blue: 0.92, alpha: 1.0).cgColor,
                UIColor(red: 0.42, green: 0.73, blue: 0.80, alpha: 1.0).cgColor,
                UIColor(red: 0.62, green: 0.88, blue: 0.86, alpha: 1.0).cgColor
            ]
            self.cardView.backgroundColor = UIColor(white: 1.0, alpha: 0.94)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.frame = CGRect(origin: CGPoint(), size: size)
        self.gradientLayer.frame = CGRect(origin: CGPoint(), size: size)
        CATransaction.commit()
        let inset: CGFloat = 8.0
        let cardFrame = CGRect(x: inset, y: max(0.0, cardTop), width: max(0.0, size.width - inset * 2.0), height: max(0.0, size.height - max(0.0, cardTop) - inset))
        self.cardView.frame = cardFrame
        self.cardView.layer.shadowPath = UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: cardFrame.size), cornerRadius: 26.0).cgPath
    }
}

/// AstraGram Liquid Glass: the rows on screen rise into place one after another on springs, like bubbles surfacing.
/// One-shot additive animations on the render server, played when a chat list appears or a folder is switched to.
func astraCascadeIn(_ listNode: ListView) {
    if !AstraLook.liquidGlassMotion {
        return
    }
    var nodes: [ASDisplayNode] = []
    listNode.forEachVisibleItemNode { node in
        nodes.append(node)
    }
    nodes.sort(by: { $0.frame.minY < $1.frame.minY })
    let now = CACurrentMediaTime()
    for (index, node) in nodes.prefix(14).enumerated() {
        let layer = node.layer
        let beginTime = layer.convertTime(now, from: nil) + Double(index) * 0.035
        let rise = CASpringAnimation(keyPath: "position.y")
        rise.isAdditive = true
        rise.fromValue = 30.0 + CGFloat(index) * 5.0
        rise.toValue = 0.0
        rise.mass = 1.0
        rise.stiffness = 170.0
        rise.damping = 15.0
        rise.duration = rise.settlingDuration
        rise.beginTime = beginTime
        rise.fillMode = .backwards
        layer.add(rise, forKey: "astraCascadeRise")
        let squash = CASpringAnimation(keyPath: "transform.scale.x")
        squash.isAdditive = true
        squash.fromValue = -0.05
        squash.toValue = 0.0
        squash.stiffness = 200.0
        squash.damping = 12.0
        squash.duration = squash.settlingDuration
        squash.beginTime = beginTime
        squash.fillMode = .backwards
        layer.add(squash, forKey: "astraCascadeSquash")
    }
}
