import Foundation
import UIKit

/// AyuGram look: what the settings switch on, for the modules below the settings (Display cannot read them).
/// The app delegate keeps the values current.
public enum AyuLook {
    /// The material of glass panels and buttons: 0 Telegram's own, 1 clear, 2 matte.
    public static var glassMaterial: Int = 0
    /// Buttons answer a press with a spring.
    public static var springPresses: Bool = false

    private static let pressAnimationKey = "ayuLookPress"

    /// How far a pressed button of this size shrinks; nil for what is too large to be a button (a dimming area,
    /// a whole screen).
    private static func pressedScale(for size: CGSize) -> CGFloat? {
        let minSide = min(size.width, size.height)
        let maxSide = max(size.width, size.height)
        if minSide < 1.0 || minSide > 120.0 {
            return nil
        }
        return max(0.9, min(0.975, 1.0 - 5.0 / maxSide))
    }

    private static func currentScale(of layer: CALayer) -> CGFloat {
        if let value = layer.presentation()?.value(forKeyPath: "transform.scale") as? NSNumber {
            return CGFloat(value.doubleValue)
        }
        return 1.0
    }

    /// The press of a button: it sinks while held, and comes back on a spring when released.
    public static func press(_ layer: CALayer, down: Bool) {
        if down {
            guard AyuLook.springPresses, CATransform3DIsIdentity(layer.transform), let scale = AyuLook.pressedScale(for: layer.bounds.size) else {
                return
            }
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = AyuLook.currentScale(of: layer) as NSNumber
            animation.toValue = scale as NSNumber
            animation.duration = 0.16
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.0, 0.0, 1.0)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: AyuLook.pressAnimationKey)
        } else {
            guard layer.animation(forKey: AyuLook.pressAnimationKey) != nil else {
                return
            }
            var from = AyuLook.currentScale(of: layer)
            if let scale = AyuLook.pressedScale(for: layer.bounds.size) {
                // A quick tap is released before the button has sunk: start the way back from halfway down.
                from = min(from, 1.0 - (1.0 - scale) * 0.5)
            }
            let animation = CASpringAnimation(keyPath: "transform.scale")
            animation.fromValue = from as NSNumber
            animation.toValue = 1.0 as NSNumber
            animation.mass = 1.0
            animation.stiffness = 420.0
            animation.damping = 27.0
            animation.initialVelocity = 0.0
            animation.duration = animation.settlingDuration
            layer.add(animation, forKey: AyuLook.pressAnimationKey)
        }
    }
}
