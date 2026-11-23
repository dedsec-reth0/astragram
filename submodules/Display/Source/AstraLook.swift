import Foundation
import UIKit

/// AstraGram look: what the settings switch on, for the modules below the settings (Display cannot read them).
/// The app delegate keeps the values current.
public enum AstraLook {
    /// The material of glass panels and buttons: 0 Telegram's own, 1 clear, 2 matte.
    public static var glassMaterial: Int = 0
    /// Buttons answer a press with a spring.
    public static var springPresses: Bool = false
    /// The 2027 «Folio» design is on. It follows the setting live, so every reader checks it at the read site
    /// (never caches it in a `static let`), and the next layout pass after a toggle picks the new value up.
    public static var design2027: Bool = false
    /// The value of `design2027` when the app launched. Resources that are rendered once per process (the settings
    /// icons) follow this one, and the settings screen offers a restart while the two differ.
    public static var design2027AtLaunch: Bool = false
    /// With Folio, the chat background is the slowly rotating four-stop gradient instead of solid paper.
    public static var livingWallpaper: Bool = false

    /// Every Folio geometry constant lives here, so the work packages agree on one value and the stock value stays
    /// literally at each call site in the `else` branch.
    public enum Folio {
        /// Bubble corners: the main radius and the 4pt merged side that makes the "typeset column".
        public static let bubbleMain: CGFloat = 16.0
        public static let bubbleAux: CGFloat = 4.0
        /// Media inside a bubble clips to these.
        public static let bubbleMedia: CGFloat = 15.0
        public static let bubbleMediaMerged: CGFloat = 4.0
        /// Date and service chips are slabs, not capsules.
        public static let chipRadius: CGFloat = 8.0
        public static let serviceRadius: CGFloat = 8.0
        /// The chat input field is a slab with this radius at any height.
        public static let inputRadius: CGFloat = 16.0
        /// List cards (and the profile cards, which clip a little inside the card).
        public static let cardRadius: CGFloat = 20.0
        public static let cardClipRadius: CGFloat = 19.25
        /// The chat-list press plate and pinned plate.
        public static let rowPlateRadius: CGFloat = 16.0
        /// Context menus: the container, the item highlight and the legacy Display menu.
        public static let menuRadius: CGFloat = 22.0
        public static let menuHighlightRadius: CGFloat = 12.0
        public static let legacyMenuRadius: CGFloat = 16.0
        /// Action sheet groups (their clip and their dim cutout), alerts and modals.
        public static let sheetGroupRadius: CGFloat = 22.0
        public static let alertRadius: CGFloat = 28.0
        public static let legacyAlertRadius: CGFloat = 20.0
        public static let modalRadius: CGFloat = 16.0
        /// Toasts and undo panels.
        public static let toastRadius: CGFloat = 16.0
        /// The profile header buttons (the stock default already is 16; this names it).
        public static let profileButtonRadius: CGFloat = 16.0
        /// The 30x30 settings icon tiles.
        public static let settingsIconRadius: CGFloat = 9.0

        /// The dim behind sheets: warm ink in the light appearance, black in the dark one.
        public static let dimLight = UIColor(rgb: 0x0B0B0C).withAlphaComponent(0.40)
        public static let dimDark = UIColor(white: 0.0, alpha: 0.55)

        /// The dim for the given appearance.
        public static func dim(dark: Bool) -> UIColor {
            return dark ? Folio.dimDark : Folio.dimLight
        }

        /// The soft shadow of floating (Z2) surfaces that are not native glass. It must be applied to a sibling or
        /// container layer, never to a clipped or glass layer, because a clipped layer cuts its own shadow off.
        public static func z2Shadow(_ layer: CALayer, dark: Bool) {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = dark ? 0.40 : 0.10
            layer.shadowRadius = 24.0
            layer.shadowOffset = CGSize(width: 0.0, height: 8.0)
        }

        /// Removes what `z2Shadow` set, for when the flag is turned off on a live layer.
        public static func removeZ2Shadow(_ layer: CALayer) {
            layer.shadowOpacity = 0.0
            layer.shadowRadius = 3.0
            layer.shadowOffset = CGSize(width: 0.0, height: -3.0)
            layer.shadowColor = UIColor.black.cgColor
        }

        /// How far a pressed button shrinks under Folio, whatever its size.
        public static let pressedScale: CGFloat = 0.97
        /// The release spring under Folio: response 0.34s, damping ratio 0.80 (no overshoot).
        public static let releaseResponse: CGFloat = 0.34
        public static let releaseDampingRatio: CGFloat = 0.80
    }

    private static let pressAnimationKey = "astraLookPress"

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
            guard AstraLook.springPresses || AstraLook.design2027, CATransform3DIsIdentity(layer.transform), let stockScale = AstraLook.pressedScale(for: layer.bounds.size) else {
                return
            }
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = AstraLook.currentScale(of: layer) as NSNumber
            if AstraLook.design2027 {
                // Folio presses are still and precise: one small sink, and a plain ease when Reduce Motion is on.
                animation.toValue = Folio.pressedScale as NSNumber
                if UIAccessibility.isReduceMotionEnabled {
                    animation.duration = 0.2
                    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                } else {
                    animation.duration = 0.10
                    animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                }
            } else {
                animation.toValue = stockScale as NSNumber
                animation.duration = 0.16
                animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.0, 0.0, 1.0)
            }
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: AstraLook.pressAnimationKey)
        } else {
            guard layer.animation(forKey: AstraLook.pressAnimationKey) != nil else {
                return
            }
            var from = AstraLook.currentScale(of: layer)
            if AstraLook.design2027 {
                // A quick tap is released before the button has sunk: start the way back from halfway down.
                from = min(from, 1.0 - (1.0 - Folio.pressedScale) * 0.5)
                if UIAccessibility.isReduceMotionEnabled {
                    // Reduce Motion replaces the spring with a short plain ease.
                    let animation = CABasicAnimation(keyPath: "transform.scale")
                    animation.fromValue = from as NSNumber
                    animation.toValue = 1.0 as NSNumber
                    animation.duration = 0.2
                    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    layer.add(animation, forKey: AstraLook.pressAnimationKey)
                } else {
                    // The response/damping-ratio pair converted to the mass-spring terms CASpringAnimation takes
                    // (unit mass): stiffness = (2π / response)², damping = 4π · ratio / response.
                    let animation = CASpringAnimation(keyPath: "transform.scale")
                    animation.fromValue = from as NSNumber
                    animation.toValue = 1.0 as NSNumber
                    animation.mass = 1.0
                    let omega = 2.0 * CGFloat.pi / Folio.releaseResponse
                    animation.stiffness = omega * omega
                    animation.damping = 4.0 * CGFloat.pi * Folio.releaseDampingRatio / Folio.releaseResponse
                    animation.initialVelocity = 0.0
                    animation.duration = animation.settlingDuration
                    layer.add(animation, forKey: AstraLook.pressAnimationKey)
                }
                return
            }
            if let scale = AstraLook.pressedScale(for: layer.bounds.size) {
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
            layer.add(animation, forKey: AstraLook.pressAnimationKey)
        }
    }
}
