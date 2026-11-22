import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import EmojiTextAttachmentView
import TextFormat

/// AstraGram: a profile's pinned gifts as jelly bubbles around the avatar. They drift, push each other and the avatar
/// away, and can be pulled with a finger: a pulled bubble grows and wobbles, and lets go with a spring. Touching one
/// tells the header (`touched`), which tints the profile's background with the gift's colors; holding one opens it.
final class AstraGiftBubblesView: UIView {
    struct Item {
        let id: AnyHashable
        let gift: ProfileGiftsContext.State.StarGift
    }

    private final class Bubble {
        let id: AnyHashable
        var gift: ProfileGiftsContext.State.StarGift
        let view: AstraGiftBubbleView
        var home: CGPoint = .zero
        var position: CGPoint = .zero
        var velocity: CGPoint = .zero
        var radius: CGFloat
        var radiusVelocity: CGFloat = 0.0
        var targetRadius: CGFloat
        /// The squash of the jelly, a damped spring driven by the bubble's motion.
        var deform: CGPoint = .zero
        var deformVelocity: CGPoint = .zero
        let phase: CGFloat = CGFloat.random(in: 0.0 ..< 100.0)
        let speed: CGFloat = CGFloat.random(in: 0.6 ..< 1.1)
        var placed = false

        init(id: AnyHashable, gift: ProfileGiftsContext.State.StarGift, view: AstraGiftBubbleView, radius: CGFloat) {
            self.id = id
            self.gift = gift
            self.view = view
            self.radius = radius
            self.targetRadius = radius
        }
    }

    static let radius: CGFloat = 25.0
    static let pulledRadius: CGFloat = 92.0

    var touched: ((ProfileGiftsContext.State.StarGift) -> Void)?
    var opened: ((ProfileGiftsContext.State.StarGift) -> Void)?

    private var context: AccountContext?
    private var bubbles: [Bubble] = []
    private var avatarCenter: CGPoint = .zero
    private var avatarRadius: CGFloat = 45.0
    private var area: CGRect = .zero
    private var displayLink: CADisplayLink?
    private var time: CGFloat = 0.0

    private var dragged: Bubble?
    private var dragPoint: CGPoint = .zero
    private var dragStart: CGPoint = .zero
    private var dragStartTime: Double = 0.0
    private var dragMoved = false
    private var holdTimer: Foundation.Timer?
    private var disabledScrollViews: [UIScrollView] = []
    private let haptic = HapticFeedback()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isMultipleTouchEnabled = false
        self.isExclusiveTouch = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.displayLink?.invalidate()
        self.holdTimer?.invalidate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.updateDisplayLink()
    }

    private func updateDisplayLink() {
        if self.window != nil && !self.bubbles.isEmpty {
            if self.displayLink == nil {
                let link = CADisplayLink(target: AstraDisplayLinkTarget(self), selector: #selector(AstraDisplayLinkTarget.tick(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30.0, maximum: 60.0, preferred: 60.0)
                link.add(to: .main, forMode: .common)
                self.displayLink = link
            }
        } else {
            self.displayLink?.invalidate()
            self.displayLink = nil
        }
    }

    /// Lays the bubbles out around `avatarCenter`, with their resting places at `homes` (as many as there are items).
    func update(context: AccountContext, items: [Item], homes: [CGPoint], avatarCenter: CGPoint, avatarRadius: CGFloat, area: CGRect) {
        self.context = context
        self.avatarCenter = avatarCenter
        self.avatarRadius = avatarRadius
        self.area = area

        var next: [Bubble] = []
        for (index, item) in items.enumerated() {
            guard index < homes.count else {
                break
            }
            let bubble: Bubble
            if let current = self.bubbles.first(where: { $0.id == item.id }) {
                bubble = current
                if bubble.gift != item.gift {
                    bubble.gift = item.gift
                    bubble.view.update(context: context, gift: item.gift)
                }
            } else {
                let view = AstraGiftBubbleView(frame: CGRect(origin: .zero, size: CGSize(width: AstraGiftBubblesView.radius * 2.0, height: AstraGiftBubblesView.radius * 2.0)))
                view.update(context: context, gift: item.gift)
                bubble = Bubble(id: item.id, gift: item.gift, view: view, radius: 2.0)
                bubble.targetRadius = AstraGiftBubblesView.radius
                self.addSubview(view)
            }
            bubble.home = homes[index]
            if !bubble.placed {
                bubble.placed = true
                // Out of the avatar, as Telegram's gift icons come.
                bubble.position = avatarCenter
                bubble.velocity = CGPoint(x: (homes[index].x - avatarCenter.x) * 3.0, y: (homes[index].y - avatarCenter.y) * 3.0)
            }
            next.append(bubble)
        }
        for bubble in self.bubbles where !next.contains(where: { $0 === bubble }) {
            let view = bubble.view
            UIView.animate(withDuration: 0.25, animations: {
                view.alpha = 0.0
                view.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
            }, completion: { _ in
                view.removeFromSuperview()
            })
        }
        self.bubbles = next
        self.updateDisplayLink()
        self.layoutBubbles()
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = CGFloat(min(1.0 / 30.0, max(1.0 / 120.0, link.targetTimestamp - link.timestamp)))
        self.time += dt
        self.step(dt: dt)
        self.layoutBubbles()
    }

    private func step(dt: CGFloat) {
        for bubble in self.bubbles {
            var force = CGPoint.zero
            if bubble === self.dragged {
                // Follows the finger through a stiff spring, so it lags a little and wobbles.
                force.x += (self.dragPoint.x - bubble.position.x) * 260.0 - bubble.velocity.x * 22.0
                force.y += (self.dragPoint.y - bubble.position.y) * 260.0 - bubble.velocity.y * 22.0
            } else {
                // Home, plus a slow drift.
                let t = self.time * bubble.speed + bubble.phase
                let wander = CGPoint(x: sin(t * 0.9) * 7.0 + sin(t * 1.7 + 1.3) * 4.0, y: cos(t * 0.8 + 0.4) * 6.0 + sin(t * 1.3) * 3.0)
                force.x += (bubble.home.x + wander.x - bubble.position.x) * 9.0 - bubble.velocity.x * 3.2
                force.y += (bubble.home.y + wander.y - bubble.position.y) * 9.0 - bubble.velocity.y * 3.2
            }
            // Out of the avatar.
            if bubble !== self.dragged {
                let dx = bubble.position.x - self.avatarCenter.x
                let dy = bubble.position.y - self.avatarCenter.y
                let distance = max(0.001, sqrt(dx * dx + dy * dy))
                let minDistance = self.avatarRadius + bubble.radius * 0.55
                if distance < minDistance {
                    let push = (minDistance - distance) * 70.0
                    force.x += dx / distance * push
                    force.y += dy / distance * push
                }
            }
            bubble.velocity.x += force.x * dt
            bubble.velocity.y += force.y * dt
        }
        // The bubbles push each other away; a pulled one shoves the rest aside.
        for i in 0 ..< self.bubbles.count {
            for j in (i + 1) ..< self.bubbles.count {
                let a = self.bubbles[i], b = self.bubbles[j]
                let dx = b.position.x - a.position.x
                let dy = b.position.y - a.position.y
                let distance = max(0.001, sqrt(dx * dx + dy * dy))
                let minDistance = (a.radius + b.radius) * 0.92
                if distance < minDistance {
                    let overlap = (minDistance - distance)
                    let nx = dx / distance, ny = dy / distance
                    let aWeight: CGFloat = a === self.dragged ? 0.0 : (b === self.dragged ? 1.0 : 0.5)
                    let bWeight: CGFloat = 1.0 - aWeight
                    a.velocity.x -= nx * overlap * 60.0 * aWeight * dt * 10.0
                    a.velocity.y -= ny * overlap * 60.0 * aWeight * dt * 10.0
                    b.velocity.x += nx * overlap * 60.0 * bWeight * dt * 10.0
                    b.velocity.y += ny * overlap * 60.0 * bWeight * dt * 10.0
                    // The touching sides flatten a little.
                    a.deformVelocity.x -= nx * overlap * 0.6
                    a.deformVelocity.y -= ny * overlap * 0.6
                    b.deformVelocity.x += nx * overlap * 0.6
                    b.deformVelocity.y += ny * overlap * 0.6
                }
            }
        }
        for bubble in self.bubbles {
            bubble.position.x += bubble.velocity.x * dt
            bubble.position.y += bubble.velocity.y * dt
            // Soft walls.
            if self.area.width > 0.0 && bubble !== self.dragged {
                let r = bubble.radius
                if bubble.position.x < self.area.minX + r {
                    bubble.velocity.x += (self.area.minX + r - bubble.position.x) * 40.0 * dt
                }
                if bubble.position.x > self.area.maxX - r {
                    bubble.velocity.x -= (bubble.position.x - self.area.maxX + r) * 40.0 * dt
                }
                if bubble.position.y < self.area.minY + r {
                    bubble.velocity.y += (self.area.minY + r - bubble.position.y) * 40.0 * dt
                }
                if bubble.position.y > self.area.maxY - r {
                    bubble.velocity.y -= (bubble.position.y - self.area.maxY + r) * 40.0 * dt
                }
            }
            // The size springs with an overshoot: a pulled bubble swells, a released one shrinks back and jiggles.
            let radiusForce = (bubble.targetRadius - bubble.radius) * 180.0 - bubble.radiusVelocity * 11.0
            bubble.radiusVelocity += radiusForce * dt
            bubble.radius = max(1.0, bubble.radius + bubble.radiusVelocity * dt)
            // Squash and stretch along the motion, a spring that keeps wobbling after it stops.
            let speedFactor: CGFloat = 0.00045
            let target = CGPoint(x: bubble.velocity.x * speedFactor, y: bubble.velocity.y * speedFactor)
            let deformForce = CGPoint(x: (target.x - bubble.deform.x) * 220.0 - bubble.deformVelocity.x * 9.0, y: (target.y - bubble.deform.y) * 220.0 - bubble.deformVelocity.y * 9.0)
            bubble.deformVelocity.x += deformForce.x * dt
            bubble.deformVelocity.y += deformForce.y * dt
            bubble.deform.x += bubble.deformVelocity.x * dt
            bubble.deform.y += bubble.deformVelocity.y * dt
        }
    }

    private func layoutBubbles() {
        for bubble in self.bubbles {
            let view = bubble.view
            let side = AstraGiftBubblesView.radius * 2.0
            view.bounds = CGRect(origin: .zero, size: CGSize(width: side, height: side))
            view.center = bubble.position
            let scale = bubble.radius / AstraGiftBubblesView.radius
            // Stretch along the deformation's direction, squeeze across it, keeping the area.
            let amount = min(0.35, sqrt(bubble.deform.x * bubble.deform.x + bubble.deform.y * bubble.deform.y))
            let angle = atan2(bubble.deform.y, bubble.deform.x)
            let wobble = 1.0 + sin(self.time * 2.3 + bubble.phase) * 0.025
            var transform = CGAffineTransform(rotationAngle: angle)
            transform = transform.scaledBy(x: scale * (1.0 + amount) * wobble, y: scale / (1.0 + amount) / wobble)
            transform = transform.rotated(by: -angle)
            view.transform = transform
            view.setPulled(bubble === self.dragged ? min(1.0, max(0.0, (bubble.radius - AstraGiftBubblesView.radius) / (AstraGiftBubblesView.pulledRadius - AstraGiftBubblesView.radius))) : 0.0)
        }
    }

    private func bubble(at point: CGPoint) -> Bubble? {
        for bubble in self.bubbles.reversed() {
            let dx = point.x - bubble.position.x
            let dy = point.y - bubble.position.y
            if dx * dx + dy * dy <= (bubble.radius + 8.0) * (bubble.radius + 8.0) {
                return bubble
            }
        }
        return nil
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return self.bubble(at: point) != nil || self.dragged != nil
    }

    private func setScrollingEnabled(_ enabled: Bool) {
        if enabled {
            for scrollView in self.disabledScrollViews {
                scrollView.panGestureRecognizer.isEnabled = true
            }
            self.disabledScrollViews.removeAll()
        } else {
            var view = self.superview
            while let current = view {
                if let scrollView = current as? UIScrollView, scrollView.panGestureRecognizer.isEnabled {
                    scrollView.panGestureRecognizer.isEnabled = false
                    self.disabledScrollViews.append(scrollView)
                }
                view = current.superview
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let bubble = self.bubble(at: touch.location(in: self)) else {
            super.touchesBegan(touches, with: event)
            return
        }
        self.dragged = bubble
        self.dragPoint = touch.location(in: self)
        self.dragStart = self.dragPoint
        self.dragStartTime = CACurrentMediaTime()
        self.dragMoved = false
        self.bringSubviewToFront(bubble.view)
        // Above the name and the buttons while it is held.
        self.superview?.bringSubviewToFront(self)
        self.setScrollingEnabled(false)
        bubble.targetRadius = AstraGiftBubblesView.radius * 1.25
        self.haptic.impact(.light)
        self.touched?(bubble.gift)
        self.holdTimer?.invalidate()
        self.holdTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false, block: { [weak self] _ in
            guard let self, let dragged = self.dragged, !self.dragMoved else {
                return
            }
            let gift = dragged.gift
            self.release()
            self.haptic.impact(.medium)
            self.opened?(gift)
        })
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let bubble = self.dragged else {
            super.touchesMoved(touches, with: event)
            return
        }
        self.dragPoint = touch.location(in: self)
        let dx = self.dragPoint.x - self.dragStart.x
        let dy = self.dragPoint.y - self.dragStart.y
        if !self.dragMoved && dx * dx + dy * dy > 36.0 {
            self.dragMoved = true
            self.holdTimer?.invalidate()
            bubble.targetRadius = AstraGiftBubblesView.pulledRadius
            self.haptic.impact(.soft)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard self.dragged != nil else {
            super.touchesEnded(touches, with: event)
            return
        }
        self.release()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard self.dragged != nil else {
            super.touchesCancelled(touches, with: event)
            return
        }
        self.release()
    }

    private func release() {
        self.holdTimer?.invalidate()
        self.holdTimer = nil
        if let bubble = self.dragged {
            bubble.targetRadius = AstraGiftBubblesView.radius
            if !self.dragMoved {
                // A tap: a little jelly bounce.
                bubble.radiusVelocity -= 60.0
            }
        }
        self.dragged = nil
        self.setScrollingEnabled(true)
    }
}

private final class AstraDisplayLinkTarget: NSObject {
    private weak var view: AstraGiftBubblesView?

    init(_ view: AstraGiftBubblesView) {
        self.view = view
    }

    @objc func tick(_ link: CADisplayLink) {
        if let view = self.view {
            view.tick(link)
        } else {
            link.invalidate()
        }
    }
}

/// One jelly bubble: a translucent, glowing body in the gift's colors with a glossy highlight, and the gift inside.
final class AstraGiftBubbleView: UIView {
    private let glowLayer = CAGradientLayer()
    private let bodyLayer = CAGradientLayer()
    private let rimLayer = CAShapeLayer()
    private let shineLayer = CAGradientLayer()
    private let sparkleLayer = CAGradientLayer()
    private var stickerLayer: InlineStickerItemLayer?
    private var fileId: Int64?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false

        // A halo around the edge only, so the middle stays see-through.
        self.glowLayer.type = .radial
        self.glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.glowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.glowLayer.locations = [0.0, 0.6, 0.66, 1.0]
        self.layer.addSublayer(self.glowLayer)

        self.bodyLayer.type = .radial
        self.bodyLayer.startPoint = CGPoint(x: 0.42, y: 0.38)
        self.bodyLayer.endPoint = CGPoint(x: 1.05, y: 1.05)
        self.layer.addSublayer(self.bodyLayer)

        self.rimLayer.fillColor = UIColor.clear.cgColor
        self.rimLayer.strokeColor = UIColor(white: 1.0, alpha: 0.5).cgColor
        self.rimLayer.lineWidth = 1.0
        self.layer.addSublayer(self.rimLayer)

        self.shineLayer.type = .radial
        self.shineLayer.colors = [UIColor(white: 1.0, alpha: 0.75).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
        self.shineLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.shineLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.shineLayer)

        self.sparkleLayer.type = .radial
        self.sparkleLayer.colors = [UIColor(white: 1.0, alpha: 0.5).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
        self.sparkleLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.sparkleLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.sparkleLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The gift's colors: a unique gift's backdrop; a regular gift gets one of the bubble colors of the video.
    static func colors(gift: ProfileGiftsContext.State.StarGift) -> (UIColor, UIColor) {
        switch gift.gift {
        case let .unique(unique):
            for attribute in unique.attributes {
                if case let .backdrop(_, _, innerColor, outerColor, _, _, _) = attribute {
                    return (UIColor(rgb: UInt32(bitPattern: innerColor)), UIColor(rgb: UInt32(bitPattern: outerColor)))
                }
            }
        case let .generic(generic):
            let palette: [(UInt32, UInt32)] = [(0xff7ac8, 0xd23a95), (0x7db1ff, 0x3d63e0), (0x63f0a8, 0x1fa66a), (0xffd25e, 0xe58a1c), (0xc68bff, 0x7a3fe0), (0x6fe6f0, 0x2a9fc0)]
            let pair = palette[Int(UInt64(bitPattern: generic.id) % UInt64(palette.count))]
            return (UIColor(rgb: pair.0), UIColor(rgb: pair.1))
        }
        return (UIColor(rgb: 0xc68bff), UIColor(rgb: 0x7a3fe0))
    }

    func update(context: AccountContext, gift: ProfileGiftsContext.State.StarGift) {
        let (inner, outer) = AstraGiftBubbleView.colors(gift: gift)
        // See-through in the middle, denser and lighter at the edge, like a drop of jelly.
        self.bodyLayer.colors = [
            inner.withMultipliedBrightnessBy(1.3).withAlphaComponent(0.28).cgColor,
            inner.withAlphaComponent(0.42).cgColor,
            inner.withMultipliedBrightnessBy(1.15).withAlphaComponent(0.7).cgColor,
            outer.withMultipliedBrightnessBy(1.35).withAlphaComponent(0.9).cgColor
        ]
        self.bodyLayer.locations = [0.0, 0.5, 0.82, 1.0]
        let glow = inner.withMultipliedBrightnessBy(1.3)
        self.glowLayer.colors = [glow.withAlphaComponent(0.0).cgColor, glow.withAlphaComponent(0.0).cgColor, glow.withAlphaComponent(0.6).cgColor, glow.withAlphaComponent(0.0).cgColor]

        var file: TelegramMediaFile?
        switch gift.gift {
        case let .generic(generic):
            file = generic.file
        case let .unique(unique):
            for attribute in unique.attributes {
                if case let .model(_, value, _, _) = attribute {
                    file = value
                }
            }
        }
        guard let file, file.fileId.id != self.fileId else {
            return
        }
        self.fileId = file.fileId.id
        self.stickerLayer?.removeFromSuperlayer()
        let side = AstraGiftBubblesView.radius * 2.0 * 0.66
        let layer = InlineStickerItemLayer(
            context: .account(context),
            userLocation: .other,
            attemptSynchronousLoad: false,
            emoji: ChatTextInputTextCustomEmojiAttribute(interactivelySelectedFromPackId: nil, fileId: file.fileId.id, file: file),
            file: file,
            cache: context.animationCache,
            renderer: context.animationRenderer,
            unique: true,
            placeholderColor: UIColor(white: 1.0, alpha: 0.2),
            // Sharp when the bubble is pulled to its full size.
            pointSize: CGSize(width: side * 3.2, height: side * 3.2),
            loopCount: 1
        )
        layer.isVisibleForAnimations = true
        self.layer.insertSublayer(layer, below: self.rimLayer)
        self.stickerLayer = layer
        self.setNeedsLayout()
    }

    /// 0 at rest, 1 fully pulled: the gift plays and the glow grows.
    func setPulled(_ value: CGFloat) {
        self.glowLayer.opacity = Float(0.85 + 0.15 * value)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        let path = UIBezierPath(ovalIn: bounds).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let halo = bounds.width * 0.28
        self.glowLayer.frame = bounds.insetBy(dx: -halo, dy: -halo)
        self.bodyLayer.frame = bounds
        let mask = CAShapeLayer()
        mask.path = path
        self.bodyLayer.mask = mask
        self.rimLayer.frame = bounds
        self.rimLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).cgPath
        self.shineLayer.frame = CGRect(x: bounds.width * 0.16, y: bounds.height * 0.1, width: bounds.width * 0.42, height: bounds.height * 0.3)
        self.sparkleLayer.frame = CGRect(x: bounds.width * 0.6, y: bounds.height * 0.66, width: bounds.width * 0.2, height: bounds.height * 0.16)
        let side = bounds.width * 0.66
        self.stickerLayer?.frame = CGRect(x: (bounds.width - side) / 2.0, y: (bounds.height - side) / 2.0, width: side, height: side)
        CATransaction.commit()
    }
}

/// AstraGram: the colors of a gift's bubble (the header takes them on when it is touched).
public func astraGiftBubbleColors(gift: ProfileGiftsContext.State.StarGift) -> (UIColor, UIColor) {
    return AstraGiftBubbleView.colors(gift: gift)
}
