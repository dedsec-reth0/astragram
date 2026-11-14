import Foundation
import UIKit
import TelegramCore
import TelegramPresentationData

/// AyuGram "Liquid Glass+ (beta)": the chat list over a soft gradient, as a floating rounded card (after the Liquid Glass
/// Telegram concept). Read once at launch: switching it applies after the app restarts.
enum AyuLiquidGlass {
    static let isEnabled: Bool = AyuGramSettings.current.liquidGlassBeta

    /// The chat list background: clear in the beta look, so the gradient and the card show through.
    static func chatListBackgroundColor(_ theme: PresentationTheme) -> UIColor {
        return AyuLiquidGlass.isEnabled ? .clear : theme.chatList.backgroundColor
    }
}

final class AyuLiquidGlassBackgroundView: UIView {
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
