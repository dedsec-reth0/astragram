import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import EmojiTextAttachmentView
import TextFormat

/// AstraGram: a profile's pinned gifts as jelly bubbles around the avatar. They drift, push each other and the avatar
/// away, and can be pulled with a finger: a pulled bubble swells into a see-through lens and lets go with a spring.
/// Touching one tells the header (`touched`), which takes on the gift's colors; holding one opens it. While the
/// profile's music plays the bubbles pulse and glow on the beat, and every few bars the header moves on to the next
/// gift's colors, as a light flickering behind the avatar. A ring around the avatar glows in the bubbles' colors.
final class AstraGiftBubblesView: UIView {
    struct Item {
        let id: AnyHashable
        let gift: ProfileGiftsContext.State.StarGift
    }

    private final class Bubble {
        let id: AnyHashable
        var gift: ProfileGiftsContext.State.StarGift
        let view: AstraGiftBubbleView
        /// The bubble's own resting size (they differ, as in the concept).
        let baseRadius: CGFloat
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
        /// A hair off the beat, so they do not move as one.
        let beatLag: CGFloat = CGFloat.random(in: 0.0 ..< 0.06)
        var placed = false

        init(id: AnyHashable, gift: ProfileGiftsContext.State.StarGift, view: AstraGiftBubbleView, baseRadius: CGFloat) {
            self.id = id
            self.gift = gift
            self.view = view
            self.baseRadius = baseRadius
            self.radius = 2.0
            self.targetRadius = baseRadius
        }
    }

    /// The middle resting size: in the concept a bubble is about 0.4 of the avatar wide, an egg a bit taller than wide.
    static let radius: CGFloat = 19.0
    static let eggHeight: CGFloat = 1.2
    static let pulledRadius: CGFloat = 64.0
    private static let sizeFactors: [CGFloat] = [1.08, 0.86, 1.0, 0.8, 1.12, 0.92, 0.84, 1.04, 0.9, 0.98]
    /// Beats a minute of the pulse while music plays.
    private static let bpm: CGFloat = 112.0

    var touched: ((ProfileGiftsContext.State.StarGift) -> Void)?
    var opened: ((ProfileGiftsContext.State.StarGift) -> Void)?

    private var context: AccountContext?
    private var bubbles: [Bubble] = []
    private var avatarCenter: CGPoint = .zero
    private var avatarRadius: CGFloat = 45.0
    private var area: CGRect = .zero
    private var displayLink: CADisplayLink?
    private var time: CGFloat = 0.0

    private var musicPlaying = false
    private var musicTime: CGFloat = 0.0
    private var beatsSinceCycle: Int = 0
    private var lastBeatIndex: Int = -1
    private var cycleIndex = 0
    private var beatEnergy: CGFloat = 0.0

    /// The light behind the avatar that flickers on the beat, in the gifts' colors one after another.
    private let flickerLayer = CAGradientLayer()
    private let ringContainer = CALayer()
    private let ringGlow = CAShapeLayer()
    private let ringGradient = CAGradientLayer()
    private let ringMask = CAShapeLayer()

    private var dragged: Bubble?
    private var dragPoint: CGPoint = .zero
    private var dragStart: CGPoint = .zero
    private var dragMoved = false
    private var holdTimer: Foundation.Timer?
    private var disabledScrollViews: [UIScrollView] = []
    private let haptic = HapticFeedback()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isMultipleTouchEnabled = false
        self.isExclusiveTouch = true

        self.ringGlow.fillColor = UIColor.clear.cgColor
        self.ringGlow.lineWidth = 3.0
        self.ringGlow.shadowOffset = .zero
        self.ringGlow.shadowRadius = 8.0
        self.ringGlow.shadowOpacity = 0.9
        self.ringContainer.addSublayer(self.ringGlow)
        self.ringGradient.type = .conic
        self.ringGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.ringGradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        self.ringMask.fillColor = UIColor.clear.cgColor
        self.ringMask.strokeColor = UIColor.white.cgColor
        self.ringMask.lineWidth = 3.0
        self.ringGradient.mask = self.ringMask
        self.ringContainer.addSublayer(self.ringGradient)
        self.ringContainer.opacity = 0.0
        self.flickerLayer.type = .radial
        self.flickerLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.flickerLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.flickerLayer.opacity = 0.0
        // Light: it brightens what is under it and never covers it.
        self.flickerLayer.compositingFilter = "screenBlendMode"
        self.layer.addSublayer(self.flickerLayer)
        self.layer.addSublayer(self.ringContainer)
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

    /// The profile's music started or stopped: the beat follows it.
    func setMusicPlaying(_ playing: Bool) {
        guard self.musicPlaying != playing else {
            return
        }
        self.musicPlaying = playing
        if playing {
            self.musicTime = 0.0
            self.lastBeatIndex = -1
            self.beatsSinceCycle = 0
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
                let baseRadius = AstraGiftBubblesView.radius * AstraGiftBubblesView.sizeFactors[index % AstraGiftBubblesView.sizeFactors.count]
                let view = AstraGiftBubbleView(frame: CGRect(origin: .zero, size: CGSize(width: baseRadius * 2.0, height: baseRadius * 2.0 * AstraGiftBubblesView.eggHeight)))
                view.update(context: context, gift: item.gift)
                bubble = Bubble(id: item.id, gift: item.gift, view: view, baseRadius: baseRadius)
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
        self.updateRing()
        self.updateDisplayLink()
        self.layoutBubbles()
    }

    /// The ring around the avatar, in the bubbles' colors (hidden over an expanded photo).
    private func updateRing() {
        let colors = self.bubbles.map { AstraGiftBubbleView.colors(gift: $0.gift).0 }
        let visible = !colors.isEmpty && self.avatarRadius > 10.0 && self.avatarRadius < 80.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if visible {
            let radius = self.avatarRadius + 1.5
            let frame = CGRect(x: self.avatarCenter.x - radius - 20.0, y: self.avatarCenter.y - radius - 20.0, width: (radius + 20.0) * 2.0, height: (radius + 20.0) * 2.0)
            self.ringContainer.frame = frame
            let path = UIBezierPath(ovalIn: CGRect(x: 20.0, y: 20.0, width: radius * 2.0, height: radius * 2.0)).cgPath
            self.ringGlow.frame = self.ringContainer.bounds
            self.ringGlow.path = path
            self.ringGlow.strokeColor = colors[0].withAlphaComponent(0.6).cgColor
            self.ringGlow.shadowColor = colors[0].withMultipliedBrightnessBy(1.3).cgColor
            self.ringGradient.frame = self.ringContainer.bounds
            self.ringMask.frame = self.ringContainer.bounds
            self.ringMask.path = path
            var gradientColors = colors.map { $0.withMultipliedBrightnessBy(1.35).cgColor }
            if gradientColors.count == 1 {
                gradientColors.append(UIColor.white.withAlphaComponent(0.8).cgColor)
            }
            gradientColors.append(gradientColors[0])
            self.ringGradient.colors = gradientColors
            if self.ringContainer.animation(forKey: "spin") == nil {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0.0
                spin.toValue = CGFloat.pi * 2.0
                spin.duration = 9.0
                spin.repeatCount = .infinity
                self.ringGradient.add(spin, forKey: "spin")
            }
        }
        self.ringContainer.isHidden = !visible
        let flickerRadius = self.avatarRadius * 2.6
        self.flickerLayer.frame = CGRect(x: self.avatarCenter.x - flickerRadius, y: self.avatarCenter.y - flickerRadius, width: flickerRadius * 2.0, height: flickerRadius * 2.0)
        self.flickerLayer.isHidden = !visible
        if self.flickerLayer.colors == nil, let first = self.bubbles.first {
            self.setFlickerColor(AstraGiftBubbleView.colors(gift: first.gift).0, animated: false)
        }
        CATransaction.commit()
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = CGFloat(min(1.0 / 30.0, max(1.0 / 120.0, link.targetTimestamp - link.timestamp)))
        self.time += dt
        self.updateBeat(dt: dt)
        self.step(dt: dt)
        self.layoutBubbles()
    }

    /// The pulse: a sharp kick on every beat, fading out between them; silence lets it die away.
    private func pulse(at time: CGFloat) -> CGFloat {
        let beat = 60.0 / AstraGiftBubblesView.bpm
        let phase = (time.truncatingRemainder(dividingBy: beat)) / beat
        return exp(-phase * 7.0)
    }

    private func updateBeat(dt: CGFloat) {
        if self.musicPlaying {
            self.musicTime += dt
            self.beatEnergy = min(1.0, self.beatEnergy + dt * 2.0)
            let beatIndex = Int(self.musicTime / (60.0 / AstraGiftBubblesView.bpm))
            if beatIndex != self.lastBeatIndex {
                self.lastBeatIndex = beatIndex
                self.beatsSinceCycle += 1
                // Every two bars, the next gift's colors.
                if self.beatsSinceCycle >= 8 && !self.bubbles.isEmpty && self.dragged == nil {
                    self.beatsSinceCycle = 0
                    self.cycleIndex = (self.cycleIndex + 1) % self.bubbles.count
                    self.setFlickerColor(AstraGiftBubbleView.colors(gift: self.bubbles[self.cycleIndex].gift).0, animated: true)
                }
            }
        } else {
            self.beatEnergy = max(0.0, self.beatEnergy - dt * 1.5)
        }
        let kick = self.beatEnergy * self.pulse(at: self.musicTime)
        self.ringContainer.opacity = Float(0.55 + 0.45 * kick)
        // A flash on every beat with a quick random shimmer on top, gone in silence.
        let shimmer = 0.85 + 0.15 * sin(self.time * 31.0) * sin(self.time * 17.0)
        self.flickerLayer.opacity = Float(self.beatEnergy * (0.18 + 0.62 * kick) * shimmer)
    }

    private func setFlickerColor(_ color: UIColor, animated: Bool) {
        let bright = color.withMultiplied(hue: 1.0, saturation: 1.3, brightness: 1.4)
        let colors = [bright.withAlphaComponent(0.9).cgColor, bright.withAlphaComponent(0.35).cgColor, bright.withAlphaComponent(0.0).cgColor]
        if animated, let previous = self.flickerLayer.colors {
            let animation = CABasicAnimation(keyPath: "colors")
            animation.fromValue = previous
            animation.toValue = colors
            animation.duration = 0.5
            self.flickerLayer.add(animation, forKey: "colors")
        }
        self.flickerLayer.colors = colors
        self.flickerLayer.locations = [0.0, 0.45, 1.0]
    }

    private func step(dt: CGFloat) {
        for bubble in self.bubbles {
            var force = CGPoint.zero
            if bubble === self.dragged {
                // Follows the finger through a stiff spring, so it lags a little and wobbles.
                force.x += (self.dragPoint.x - bubble.position.x) * 260.0 - bubble.velocity.x * 22.0
                force.y += (self.dragPoint.y - bubble.position.y) * 260.0 - bubble.velocity.y * 22.0
            } else {
                // Home, plus a slow drift (livelier with music).
                let t = self.time * bubble.speed + bubble.phase
                let drift: CGFloat = 1.0 + self.beatEnergy * 0.6
                let wander = CGPoint(x: (sin(t * 0.9) * 7.0 + sin(t * 1.7 + 1.3) * 4.0) * drift, y: (cos(t * 0.8 + 0.4) * 6.0 + sin(t * 1.3) * 3.0) * drift)
                force.x += (bubble.home.x + wander.x - bubble.position.x) * 9.0 - bubble.velocity.x * 3.2
                force.y += (bubble.home.y + wander.y - bubble.position.y) * 9.0 - bubble.velocity.y * 3.2
                // Out of the avatar.
                let dx = bubble.position.x - self.avatarCenter.x
                let dy = bubble.position.y - self.avatarCenter.y
                let distance = max(0.001, sqrt(dx * dx + dy * dy))
                let minDistance = self.avatarRadius + bubble.radius * 0.6
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
                let minDistance = (a.radius + b.radius) * 1.02
                if distance < minDistance {
                    let overlap = (minDistance - distance)
                    let nx = dx / distance, ny = dy / distance
                    let aWeight: CGFloat = a === self.dragged ? 0.0 : (b === self.dragged ? 1.0 : 0.5)
                    let bWeight: CGFloat = 1.0 - aWeight
                    a.velocity.x -= nx * overlap * 600.0 * aWeight * dt
                    a.velocity.y -= ny * overlap * 600.0 * aWeight * dt
                    b.velocity.x += nx * overlap * 600.0 * bWeight * dt
                    b.velocity.y += ny * overlap * 600.0 * bWeight * dt
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
            let kick = self.beatEnergy * self.pulse(at: max(0.0, self.musicTime - bubble.beatLag))
            view.bounds = CGRect(origin: .zero, size: CGSize(width: bubble.baseRadius * 2.0, height: bubble.baseRadius * 2.0 * AstraGiftBubblesView.eggHeight))
            view.center = bubble.position
            let scale = bubble.radius / bubble.baseRadius * (1.0 + 0.1 * kick)
            // Stretch along the deformation's direction, squeeze across it, keeping the area.
            let amount = min(0.35, sqrt(bubble.deform.x * bubble.deform.x + bubble.deform.y * bubble.deform.y))
            let angle = atan2(bubble.deform.y, bubble.deform.x)
            var transform = CGAffineTransform(rotationAngle: angle)
            transform = transform.scaledBy(x: scale * (1.0 + amount), y: scale / (1.0 + amount))
            transform = transform.rotated(by: -angle)
            view.transform = transform
            let pulled: CGFloat = bubble === self.dragged ? min(1.0, max(0.0, (bubble.radius - bubble.baseRadius) / (AstraGiftBubblesView.pulledRadius - bubble.baseRadius))) : 0.0
            view.updateShape(time: self.time + bubble.phase, pulled: pulled, glow: 0.35 * self.beatEnergy + 0.65 * kick)
        }
    }

    private func bubble(at point: CGPoint) -> Bubble? {
        for bubble in self.bubbles.reversed() {
            let dx = point.x - bubble.position.x
            let dy = (point.y - bubble.position.y) / AstraGiftBubblesView.eggHeight
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
        self.dragMoved = false
        self.bringSubviewToFront(bubble.view)
        // Above the name and the buttons while it is held.
        self.superview?.bringSubviewToFront(self)
        self.setScrollingEnabled(false)
        bubble.targetRadius = bubble.baseRadius * 1.25
        self.haptic.impact(.light)
        if let index = self.bubbles.firstIndex(where: { $0 === bubble }) {
            self.cycleIndex = index
            self.beatsSinceCycle = 0
            self.setFlickerColor(AstraGiftBubbleView.colors(gift: bubble.gift).0, animated: true)
        }
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
            bubble.targetRadius = bubble.baseRadius
            if !self.dragMoved {
                // A tap: a little jelly bounce.
                bubble.radiusVelocity -= 50.0
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

/// One jelly bubble: a wobbly egg of colored jelly with a glow around it, a gloss, a few sparkles, and the gift inside.
/// Pulled big, it thins into a see-through lens.
final class AstraGiftBubbleView: UIView {
    private let glowLayer = CAShapeLayer()
    private let bodyLayer = CAGradientLayer()
    private let bodyMask = CAShapeLayer()
    private let rimLayer = CAShapeLayer()
    private let shineLayer = CAGradientLayer()
    private var sparkleLayers: [CALayer] = []
    private var stickerLayer: InlineStickerItemLayer?
    private var fileId: Int64?
    private var glowColor: UIColor = .white

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false

        self.glowLayer.fillColor = UIColor.clear.cgColor
        self.glowLayer.shadowOffset = .zero
        self.layer.addSublayer(self.glowLayer)

        self.bodyLayer.type = .radial
        self.bodyLayer.startPoint = CGPoint(x: 0.42, y: 0.36)
        self.bodyLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.bodyLayer.mask = self.bodyMask
        self.layer.addSublayer(self.bodyLayer)

        self.rimLayer.fillColor = UIColor.clear.cgColor
        self.rimLayer.strokeColor = UIColor(white: 1.0, alpha: 0.38).cgColor
        self.rimLayer.lineWidth = 1.2
        self.layer.addSublayer(self.rimLayer)

        self.shineLayer.type = .radial
        self.shineLayer.colors = [UIColor(white: 1.0, alpha: 0.7).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
        self.shineLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.shineLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.shineLayer)

        for i in 0 ..< 6 {
            let sparkle = CALayer()
            let side: CGFloat = i % 3 == 0 ? 2.2 : 1.5
            sparkle.bounds = CGRect(origin: .zero, size: CGSize(width: side, height: side))
            sparkle.cornerRadius = side / 2.0
            sparkle.backgroundColor = UIColor(white: 1.0, alpha: 0.75).cgColor
            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = 0.15
            twinkle.toValue = 1.0
            twinkle.duration = Double.random(in: 0.8 ..< 1.6)
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.beginTime = CACurrentMediaTime() + Double.random(in: 0.0 ..< 1.0)
            sparkle.add(twinkle, forKey: "twinkle")
            self.layer.addSublayer(sparkle)
            self.sparkleLayers.append(sparkle)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The gift's colors: a unique gift's backdrop; a regular gift gets one of the concept's bubble colors.
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
        var (inner, outer) = AstraGiftBubbleView.colors(gift: gift)
        // The concept's jelly is vivid even for a muted backdrop.
        inner = inner.withMultiplied(hue: 1.0, saturation: 1.35, brightness: 1.25)
        outer = outer.withMultiplied(hue: 1.0, saturation: 1.3, brightness: 1.3)
        self.bodyLayer.colors = [
            inner.withMultipliedBrightnessBy(1.2).withAlphaComponent(0.62).cgColor,
            inner.withAlphaComponent(0.74).cgColor,
            outer.withAlphaComponent(0.9).cgColor
        ]
        self.bodyLayer.locations = [0.0, 0.55, 1.0]
        self.glowColor = inner
        self.glowLayer.shadowColor = inner.cgColor

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
            pointSize: CGSize(width: 96.0, height: 96.0),
            loopCount: nil
        )
        layer.isVisibleForAnimations = true
        self.layer.insertSublayer(layer, below: self.rimLayer)
        self.stickerLayer = layer
        self.setNeedsLayout()
    }

    /// The wobbly egg outline in `bounds`: wider at the bottom, its edge rippling slowly.
    private func blobPath(in rect: CGRect, time: CGFloat, wobble: CGFloat) -> CGPath {
        let count = 18
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2.0, ry = rect.height / 2.0
        var points: [CGPoint] = []
        for i in 0 ..< count {
            let a = CGFloat(i) / CGFloat(count) * .pi * 2.0
            let ripple = 1.0 + wobble * (0.035 * sin(2.0 * a + time * 1.3) + 0.025 * sin(3.0 * a - time * 0.9 + 1.7) + 0.015 * sin(5.0 * a + time * 2.1))
            let y = sin(a)
            // An egg: the top a little narrower than the bottom.
            let eggX = 1.0 + 0.07 * y
            points.append(CGPoint(x: cx + cos(a) * rx * eggX * ripple, y: cy + sin(a) * ry * ripple))
        }
        let path = CGMutablePath()
        // Catmull-Rom through the points, closed.
        for i in 0 ..< count {
            let p0 = points[(i - 1 + count) % count], p1 = points[i], p2 = points[(i + 1) % count], p3 = points[(i + 2) % count]
            if i == 0 {
                path.move(to: p1)
            }
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0, y: p1.y + (p2.y - p0.y) / 6.0)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0, y: p2.y - (p3.y - p1.y) / 6.0)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    /// Redraws the outline (it ripples), the lens look when pulled and the glow on the beat.
    func updateShape(time: CGFloat, pulled: CGFloat, glow: CGFloat) {
        let bounds = self.bounds
        let path = self.blobPath(in: bounds, time: time, wobble: 1.0 + pulled * 1.5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.glowLayer.shadowPath = path
        self.glowLayer.shadowRadius = bounds.width * 0.28 + glow * bounds.width * 0.25
        self.glowLayer.shadowOpacity = Float(0.75 + 0.25 * glow)
        self.bodyMask.path = path
        self.rimLayer.path = path
        // Pulled big, the jelly thins out: the profile shows through it, as through a lens.
        self.bodyLayer.opacity = Float(1.0 - 0.4 * pulled)
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.glowLayer.frame = bounds
        self.bodyLayer.frame = bounds
        self.bodyMask.frame = bounds
        self.rimLayer.frame = bounds
        self.shineLayer.frame = CGRect(x: bounds.width * 0.18, y: bounds.height * 0.1, width: bounds.width * 0.36, height: bounds.height * 0.22)
        let positions: [CGPoint] = [CGPoint(x: 0.28, y: 0.62), CGPoint(x: 0.72, y: 0.7), CGPoint(x: 0.4, y: 0.8), CGPoint(x: 0.66, y: 0.3), CGPoint(x: 0.24, y: 0.4), CGPoint(x: 0.56, y: 0.86)]
        for (i, sparkle) in self.sparkleLayers.enumerated() {
            sparkle.position = CGPoint(x: bounds.width * positions[i].x, y: bounds.height * positions[i].y)
        }
        // The gift is small in its bubble, a little above the middle.
        let side = bounds.width * 0.46
        self.stickerLayer?.frame = CGRect(x: (bounds.width - side) / 2.0, y: bounds.height * 0.44 - side / 2.0, width: side, height: side)
        CATransaction.commit()
        self.updateShape(time: 0.0, pulled: 0.0, glow: 0.0)
    }
}

/// AstraGram: the colors of a gift's bubble (the header takes them on when it is touched).
public func astraGiftBubbleColors(gift: ProfileGiftsContext.State.StarGift) -> (UIColor, UIColor) {
    return AstraGiftBubbleView.colors(gift: gift)
}
