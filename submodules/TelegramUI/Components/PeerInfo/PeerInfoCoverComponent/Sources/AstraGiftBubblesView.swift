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
final class AstraGiftBubblesView: UIView, UIGestureRecognizerDelegate {
    struct Item {
        let id: AnyHashable
        let gift: ProfileGiftsContext.State.StarGift
    }

    private final class Bubble {
        let id: AnyHashable
        var gift: ProfileGiftsContext.State.StarGift
        let view: AstraGiftBubbleView
        /// The bubble's own resting size (they differ, as in the concept).
        /// A share of the middle size (`AstraGiftBubblesView.radius`).
        let sizeFactor: CGFloat
        var baseRadius: CGFloat {
            return AstraGiftBubblesView.radius * self.sizeFactor
        }
        var home: CGPoint = .zero
        /// The resting place as distance and angle from the avatar: it turns slowly, so the bubbles swirl.
        var homeDistance: CGFloat = 0.0
        var homeAngle: CGFloat = 0.0
        var snapUntil: CGFloat = 0.0
        /// Its place on the tilted ring around the avatar (as a carousel seen a little from above): the angle grows
        /// clockwise; at the bottom it passes in front of the avatar, at the top behind it.
        var orbitAngle: CGFloat = 0.0
        /// Its fixed place on the ring (evenly spread): the ring turns as one, so they never bunch up.
        var orbitSlot: CGFloat = 0.0
        var orbitRadius: CGFloat = 0.0
        var depth: CGFloat = 0.0
        var inFront = false
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
        var placed = false

        init(id: AnyHashable, gift: ProfileGiftsContext.State.StarGift, view: AstraGiftBubbleView, baseRadius: CGFloat) {
            self.id = id
            self.gift = gift
            self.view = view
            self.sizeFactor = baseRadius
            self.radius = 2.0
            self.targetRadius = AstraGiftBubblesView.radius * baseRadius
        }
    }

    /// The middle resting size: in the concept a bubble is about 0.4 of the avatar wide, an egg a bit taller than wide.
    static var radius: CGFloat { return AstraBubbleTuning.current.radius }
    static var eggHeight: CGFloat { return AstraBubbleTuning.current.eggHeight }
    static let pulledRadius: CGFloat = 86.0
    private static let sizeFactors: [CGFloat] = [1.25, 0.8, 1.05, 0.7, 1.15, 0.9, 0.78, 1.1, 0.85, 1.0]

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
    private var cycleIndex = 0
    private var beatEnergy: CGFloat = 0.0

    /// The screen's color, flowing slowly through the gifts' colors one after another (the header and the whole
    /// profile take it on). A touched bubble brings its color in.
    var tintChanged: ((UIColor) -> Void)?
    private var flowPosition: CGFloat = 0.0
    private var flowTarget: CGFloat?
    private var lastTint: UIColor?
    /// Seconds each gift's color stays (the change between them takes most of it).
    private static let flowPeriod: CGFloat = 3.2
    /// A snapshot of what is under the bubbles, for the lens of a pulled one.
    private var lensImage: CGImage?
    private var lensTime: CGFloat = -1.0
    private let ringContainer = CALayer()
    private let ringGlow = CAShapeLayer()
    private let ringGradient = CAGradientLayer()
    private let ringMask = CAShapeLayer()

    /// On a light profile the bubbles are clear soap bubbles; on a dark one, glowing neon jelly (as in the concept).
    private var soap = true
    private var dragged: Bubble?
    private let avatarMask = CAShapeLayer()
    /// Bubbles behind the avatar (its circle cut out of them) and in front of it.
    private let backContainer = UIView()
    private let frontContainer = UIView()
    private static let orbitRadii: [CGFloat] = [1.3, 1.85, 1.5, 2.05, 1.38, 1.7, 1.95, 1.45, 1.6, 1.8]
    private weak var rotationHost: UIView?
    private var rotationRecognizer: UIPanGestureRecognizer?
    private var rotationLastX: CGFloat = 0.0
    private var rotationActive = false
    /// How far the ring of bubbles has turned.
    private var ringAngle: CGFloat = -CGFloat.pi / 2.0
    /// Radians a second the bubbles keep turning after a swipe (it dies away).
    private var spin: CGFloat = 0.0
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
        self.layer.addSublayer(self.ringContainer)
        self.backContainer.isUserInteractionEnabled = false
        self.frontContainer.isUserInteractionEnabled = false
        self.addSubview(self.backContainer)
        self.addSubview(self.frontContainer)
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
        }
        // With music the bubbles light up as neon jelly and more of them come out; without, clear soap bubbles.
        if let (context, items, homes, avatarCenter, avatarRadius, area) = self.lastUpdate {
            self.update(context: context, items: items, homes: homes, avatarCenter: avatarCenter, avatarRadius: avatarRadius, area: area)
        }
    }

    private var lastUpdate: (AccountContext, [Item], [CGPoint], CGPoint, CGFloat, CGRect)?

    /// Lays the bubbles out around `avatarCenter`, with their resting places at `homes` (as many as there are items).
    func update(context: AccountContext, items: [Item], homes: [CGPoint], avatarCenter: CGPoint, avatarRadius: CGFloat, area: CGRect) {
        self.context = context
        self.lastUpdate = (context, items, homes, avatarCenter, avatarRadius, area)
        let soap = !self.musicPlaying
        let soapChanged = self.soap != soap
        self.soap = soap
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
                if bubble.gift != item.gift || soapChanged {
                    bubble.view.soap = soap
                    bubble.gift = item.gift
                    bubble.view.update(context: context, gift: item.gift)
                }
            } else {
                let baseRadius = AstraGiftBubblesView.sizeFactors[index % AstraGiftBubblesView.sizeFactors.count]
                let view = AstraGiftBubbleView(frame: CGRect(origin: .zero, size: CGSize(width: AstraGiftBubblesView.radius * baseRadius * 2.0, height: AstraGiftBubblesView.radius * baseRadius * 2.0 * AstraGiftBubblesView.eggHeight)))
                view.soap = soap
                view.update(context: context, gift: item.gift)
                bubble = Bubble(id: item.id, gift: item.gift, view: view, baseRadius: baseRadius)
                self.backContainer.addSubview(view)
            }
            bubble.home = homes[index]
            bubble.homeDistance = sqrt(pow(homes[index].x - avatarCenter.x, 2.0) + pow(homes[index].y - avatarCenter.y, 2.0))
            bubble.homeAngle = atan2(homes[index].y - avatarCenter.y, homes[index].x - avatarCenter.x)
            if !bubble.placed {
                bubble.placed = true
                // Out of the avatar, as Telegram's gift icons come.
                bubble.position = avatarCenter
                bubble.velocity = CGPoint(x: (homes[index].x - avatarCenter.x) * 3.0, y: (homes[index].y - avatarCenter.y) * 3.0)
                bubble.snapUntil = self.time + 1.0
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
        if next.count != self.bubbles.count || next.contains(where: { bubble in !self.bubbles.contains(where: { $0 === bubble }) }) {
            // Spread evenly round the ring, turned as the ring is now (they glide to their new places).
            for (index, bubble) in next.enumerated() {
                bubble.orbitSlot = CGFloat(index) * 2.0 * .pi / CGFloat(next.count)
            }
        }
        self.bubbles = next
        self.updateOrbits()
        self.backContainer.frame = self.bounds
        self.frontContainer.frame = self.bounds
        self.updateAvatarMask()
        self.updateRing()
        self.updateDisplayLink()
        self.layoutBubbles()
    }

    /// The ring around the avatar, in the bubbles' colors (hidden over an expanded photo).
    private func updateRing() {
        let colors = self.bubbles.map { AstraGiftBubbleView.colors(gift: $0.gift).0 }
        let visible = false && !colors.isEmpty
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
        CATransaction.commit()
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = CGFloat(min(1.0 / 30.0, max(1.0 / 120.0, link.targetTimestamp - link.timestamp)))
        self.time += dt
        // shortcut: the picture under the bubbles is retaken 5 times a second, not every frame (cost); a faster
        // moving header (a video avatar) shows through a little behind.
        if self.time - self.lensTime > 0.2 || self.lensImage == nil {
            self.lensTime = self.time
            self.captureLens()
            if AstraBubbleTuning.reload() {
                self.updateOrbits()
                for bubble in self.bubbles {
                    if bubble !== self.dragged {
                        bubble.targetRadius = bubble.baseRadius
                    }
                    if let context = self.context {
                        bubble.view.update(context: context, gift: bubble.gift)
                    }
                    bubble.view.setNeedsLayout()
                }
            }
        }
        self.updateBeat(dt: dt)
        self.step(dt: dt)
        self.layoutBubbles()
    }

    /// A beat of the music (found in its loudness): the bubbles jump and glow, and the ring gets a push.
    func beat(strength: CGFloat) {
        self.beatKick = max(self.beatKick, 0.55 + 0.45 * strength)
        self.spin += (self.spin >= 0.0 ? 1.0 : -1.0) * (0.35 + 0.5 * strength)
        for bubble in self.bubbles where bubble !== self.dragged {
            bubble.radiusVelocity += bubble.baseRadius * (2.0 + 3.0 * strength)
        }
    }

    /// The pulse after a beat, fading out until the next one.
    private var beatKick: CGFloat = 0.0

    private func updateBeat(dt: CGFloat) {
        if self.musicPlaying {
            self.musicTime += dt
            self.beatEnergy = min(1.0, self.beatEnergy + dt * 2.0)
        } else {
            self.beatEnergy = max(0.0, self.beatEnergy - dt * 1.5)
        }
        self.beatKick *= exp(-dt * 6.0)
        let kick = self.beatEnergy * self.beatKick
        self.ringContainer.opacity = Float(0.55 + 0.45 * kick)
    }

    /// The flowing color: it rests on each gift's color, then glides on to the next one.
    private func updateFlow(dt: CGFloat) {
        let count = self.bubbles.count
        guard count > 0 else {
            return
        }
        if let target = self.flowTarget {
            // A touched bubble: the flow hurries to its color.
            let delta = target - self.flowPosition
            if abs(delta) < 0.01 {
                self.flowPosition = target
                self.flowTarget = nil
            } else {
                self.flowPosition += delta * min(1.0, dt * 4.0)
            }
        } else if count > 1 {
            self.flowPosition += dt / AstraGiftBubblesView.flowPeriod
        }
        let whole = floor(self.flowPosition)
        let fraction = self.flowPosition - whole
        // Rest for the first half, glide (smoothly) for the second.
        let t = max(0.0, (fraction - 0.45) / 0.55)
        let eased = t * t * (3.0 - 2.0 * t)
        let index = ((Int(whole) % count) + count) % count
        let from = AstraGiftBubbleView.flowColor(gift: self.bubbles[index].gift)
        let to = AstraGiftBubbleView.flowColor(gift: self.bubbles[(index + 1) % count].gift)
        let color = from.mixedWith(to, alpha: eased)
        if let last = self.lastTint, astraColorsClose(last, color) {
            return
        }
        self.lastTint = color
        self.tintChanged?(color)
    }

    private func step(dt: CGFloat) {
        self.ringAngle += (self.musicPlaying ? AstraBubbleTuning.current.orbitSpeedMusic : AstraBubbleTuning.current.orbitSpeed) * dt
        if abs(self.spin) > 0.02 {
            self.turn(by: self.spin * dt)
            self.spin *= exp(-dt * 2.6)
        } else {
            self.spin = 0.0
        }
        for bubble in self.bubbles {
            var force = CGPoint.zero
            if bubble === self.dragged {
                // Follows the finger through a stiff spring, so it lags a little and wobbles.
                // Held above the finger, so the finger never covers it (the bigger it grows, the higher).
                let lift = self.dragMoved ? bubble.radius * AstraGiftBubblesView.eggHeight + 16.0 : 0.0
                force.x += (self.dragPoint.x - bubble.position.x) * 260.0 - bubble.velocity.x * 22.0
                force.y += (self.dragPoint.y - lift - bubble.position.y) * 260.0 - bubble.velocity.y * 22.0
            } else {
                // Round the tilted ring, all together (quicker with music).
                bubble.orbitAngle = self.ringAngle + bubble.orbitSlot
                bubble.depth = sin(bubble.orbitAngle)
                let t = self.time * bubble.speed + bubble.phase
                let target = CGPoint(x: self.avatarCenter.x + cos(bubble.orbitAngle) * bubble.orbitRadius + sin(t * 0.9) * 2.0, y: self.avatarCenter.y + sin(bubble.orbitAngle) * bubble.orbitRadius * AstraBubbleTuning.current.orbitTilt + sin(t * 0.7 + 1.0) * 2.0)
                // Follows its place closely; let go, it flies back with a bounce.
                let snapping = self.time < bubble.snapUntil
                // Soft enough that the bubbles can push each other aside and never sink into one another.
                // While the ring is being turned they hold to it tighter, so they go round and do not cut across.
                let turning = min(1.0, abs(self.spin) / 2.0 + (self.rotationActive ? 1.0 : 0.0))
                let pull: CGFloat = snapping ? 26.0 : 16.0 + 44.0 * turning
                let damping: CGFloat = snapping ? 5.5 : 7.0 + 6.0 * turning
                force.x += (target.x - bubble.position.x) * pull - bubble.velocity.x * damping
                force.y += (target.y - bubble.position.y) * pull - bubble.velocity.y * damping
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
                // As drawn: nearer ones are bigger, and the egg is a little taller than wide.
                let minDistance = (self.drawnRadius(a) + self.drawnRadius(b)) * 1.04
                if distance < minDistance {
                    let overlap = (minDistance - distance)
                    let nx = dx / distance, ny = dy / distance
                    let aWeight: CGFloat = a === self.dragged ? 0.0 : (b === self.dragged ? 1.0 : 0.5)
                    let bWeight: CGFloat = 1.0 - aWeight
                    a.velocity.x -= nx * overlap * 600.0 * aWeight * dt
                    a.velocity.y -= ny * overlap * 600.0 * aWeight * dt
                    b.velocity.x += nx * overlap * 600.0 * bWeight * dt
                    b.velocity.y += ny * overlap * 600.0 * bWeight * dt
                    // And apart at once, so they never sink into one another.
                    a.position.x -= nx * overlap * 0.8 * aWeight
                    a.position.y -= ny * overlap * 0.8 * aWeight
                    b.position.x += nx * overlap * 0.8 * bWeight
                    b.position.y += ny * overlap * 0.8 * bWeight
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
        }
        // Hard: whatever pulls them, no two bubbles are ever drawn one inside the other.
        for _ in 0 ..< 4 {
            for i in 0 ..< self.bubbles.count {
                for j in (i + 1) ..< self.bubbles.count {
                    let a = self.bubbles[i], b = self.bubbles[j]
                    let dx = b.position.x - a.position.x
                    let dy = b.position.y - a.position.y
                    let distance = max(0.001, sqrt(dx * dx + dy * dy))
                    let minDistance = (self.drawnRadius(a) + self.drawnRadius(b)) * 1.04
                    if distance < minDistance {
                        let overlap = minDistance - distance
                        let nx = dx / distance, ny = dy / distance
                        let aWeight: CGFloat = a === self.dragged ? 0.0 : (b === self.dragged ? 1.0 : 0.5)
                        let bWeight: CGFloat = 1.0 - aWeight
                        a.position.x -= nx * overlap * aWeight
                        a.position.y -= ny * overlap * aWeight
                        b.position.x += nx * overlap * bWeight
                        b.position.y += ny * overlap * bWeight
                    }
                }
            }
        }
        for bubble in self.bubbles {
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
            let speedFactor: CGFloat = 0.0006
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
            let kick = self.beatEnergy * self.beatKick
            view.bounds = CGRect(origin: .zero, size: CGSize(width: bubble.baseRadius * 2.0, height: bubble.baseRadius * 2.0 * AstraGiftBubblesView.eggHeight))
            view.center = bubble.position
            // Nearer (lower on the ring) is bigger and in front of the avatar; farther is smaller and behind it.
            let front = bubble === self.dragged || bubble.depth > 0.0
            if front != bubble.inFront || view.superview == nil {
                bubble.inFront = front
                (front ? self.frontContainer : self.backContainer).addSubview(view)
            }
            let depthScale: CGFloat = bubble === self.dragged ? 1.0 : (1.0 + 0.16 * bubble.depth)
            view.alpha = bubble === self.dragged ? 1.0 : (0.82 + 0.18 * (bubble.depth + 1.0) / 2.0)
            let scale = bubble.radius / bubble.baseRadius * (1.0 + 0.1 * kick) * depthScale
            // Stretch along the deformation's direction, squeeze across it, keeping the area.
            let amount = min(0.16, sqrt(bubble.deform.x * bubble.deform.x + bubble.deform.y * bubble.deform.y))
            let angle = atan2(bubble.deform.y, bubble.deform.x)
            var transform = CGAffineTransform(rotationAngle: angle)
            transform = transform.scaledBy(x: scale * (1.0 + amount), y: scale / (1.0 + amount))
            transform = transform.rotated(by: -angle)
            view.transform = transform
            let pulled: CGFloat = bubble === self.dragged ? min(1.0, max(0.0, (bubble.radius - bubble.baseRadius) / (AstraGiftBubblesView.pulledRadius - bubble.baseRadius))) : 0.0
            view.updateShape(time: self.time + bubble.phase, pulled: pulled, glow: 0.3 * self.beatEnergy + 0.7 * kick)
            if let image = self.lensImage, self.bounds.width > 0.0, self.bounds.height > 0.0 {
                // What is under the bubble, magnified as through a drop of water (more when pulled big).
                let magnification = AstraBubbleTuning.current.magnification + 0.15 * pulled
                let shown = CGSize(width: view.bounds.width * scale / magnification, height: view.bounds.height * scale / magnification)
                let size = self.bounds.size
                let rect = CGRect(x: (bubble.position.x - shown.width / 2.0) / size.width, y: (bubble.position.y - shown.height / 2.0) / size.height, width: shown.width / size.width, height: shown.height / size.height)
                view.setLens(image: image, contentsRect: rect, amount: 1.0)
            } else {
                view.setLens(image: nil, contentsRect: .zero, amount: 0.0)
            }
        }
    }

    /// The bubbles are over everything in the header but the avatar: its circle is cut out of them, so they pass
    /// behind it. A held bubble is over the avatar too.
    private func updateAvatarMask() {
        guard self.avatarRadius > 10.0, self.avatarRadius < 80.0 else {
            self.backContainer.layer.mask = nil
            return
        }
        let path = UIBezierPath(rect: self.bounds.insetBy(dx: -400.0, dy: -400.0))
        path.append(UIBezierPath(ovalIn: CGRect(x: self.avatarCenter.x - self.avatarRadius, y: self.avatarCenter.y - self.avatarRadius, width: self.avatarRadius * 2.0, height: self.avatarRadius * 2.0)))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.avatarMask.frame = self.bounds
        self.avatarMask.fillRule = .evenOdd
        self.avatarMask.path = path.cgPath
        if self.backContainer.layer.mask !== self.avatarMask {
            self.backContainer.layer.mask = self.avatarMask
        }
        CATransaction.commit()
    }

    private func drawnRadius(_ bubble: Bubble) -> CGFloat {
        let depthScale: CGFloat = bubble === self.dragged ? 1.0 : (1.0 + 0.16 * bubble.depth)
        return bubble.radius * depthScale * (1.0 + AstraGiftBubblesView.eggHeight) / 2.0
    }

    private func updateOrbits() {
        let t = AstraBubbleTuning.current
        for (index, bubble) in self.bubbles.enumerated() {
            bubble.orbitRadius = self.avatarRadius * AstraGiftBubblesView.orbitRadii[index % AstraGiftBubblesView.orbitRadii.count] * t.orbitScale + bubble.baseRadius * 0.2
        }
    }

    /// Turns all the bubbles around the avatar by `angle`.
    private func turn(by angle: CGFloat) {
        self.ringAngle += angle
    }

    /// A sideways swipe around the avatar turns the bubbles (`host`: the header's view, which gets the gesture).
    func attachRotation(to host: UIView) {
        guard self.rotationHost !== host else {
            return
        }
        if let recognizer = self.rotationRecognizer {
            self.rotationHost?.removeGestureRecognizer(recognizer)
        }
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(self.rotationPan(_:)))
        recognizer.delegate = self
        host.addGestureRecognizer(recognizer)
        self.rotationHost = host
        self.rotationRecognizer = recognizer
        // No swipe back from inside the bubbles' ring: it turns them.
        host.interactiveTransitionGestureRecognizerTest = { [weak self, weak host] point in
            guard let self, let host else {
                return false
            }
            return self.isInRotationZone(host.convert(point, to: self))
        }
    }

    private func isInRotationZone(_ point: CGPoint) -> Bool {
        guard !self.bubbles.isEmpty, self.window != nil, !self.isHidden, self.alpha > 0.5, self.layer.opacity > 0.5, self.avatarRadius > 10.0, self.avatarRadius < 80.0 else {
            return false
        }
        let dx = point.x - self.avatarCenter.x, dy = point.y - self.avatarCenter.y
        // Anywhere in the header around the avatar, but not on it (a swipe there goes through its photos).
        return dx * dx + dy * dy > self.avatarRadius * self.avatarRadius && abs(dy) < self.avatarRadius * 2.6
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // The profile's scroll view would otherwise take the touch first; it is held still while the ring turns.
        return gestureRecognizer === self.rotationRecognizer
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === self.rotationRecognizer, let recognizer = self.rotationRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        guard self.dragged == nil, self.isInRotationZone(recognizer.location(in: self)) else {
            return false
        }
        let velocity = recognizer.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y) * 1.2
    }

    @objc private func rotationPan(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            self.rotationActive = true
            self.rotationLastX = point.x
            self.spin = 0.0
            self.setScrollingEnabled(false)
            self.haptic.impact(.light)
        case .changed:
            // Sideways: the near side of the ring follows the finger (right swipe, they go right in front).
            let delta = point.x - self.rotationLastX
            self.rotationLastX = point.x
            self.turn(by: -delta / max(30.0, self.avatarRadius * 1.6))
        case .ended, .cancelled:
            self.rotationActive = false
            self.setScrollingEnabled(true)
            let velocity = recognizer.velocity(in: self)
            // Let go, it keeps turning and slows down.
            self.spin = max(-4.0, min(4.0, -velocity.x / max(30.0, self.avatarRadius * 1.6)))
        default:
            break
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
        if self.dragged != nil {
            return true
        }
        // Behind the avatar a bubble cannot be touched: the avatar takes the touch.
        let dx = point.x - self.avatarCenter.x, dy = point.y - self.avatarCenter.y
        if dx * dx + dy * dy < self.avatarRadius * self.avatarRadius {
            return false
        }
        return self.bubble(at: point) != nil
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
        self.frontContainer.addSubview(bubble.view)
        bubble.inFront = true
        // The bubbles live behind the avatar and the name; a held one comes over everything.
        self.updateAvatarMask()
        self.setScrollingEnabled(false)
        self.touched?(bubble.gift)
        bubble.targetRadius = bubble.baseRadius * 1.25
        self.haptic.impact(.light)
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
            bubble.snapUntil = self.time + 1.1
            if !self.dragMoved {
                // A tap: a little jelly bounce.
                bubble.radiusVelocity -= 50.0
            }
        }
        self.dragged = nil
        self.setScrollingEnabled(true)
        // Back behind the avatar once it has shrunk and flown back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: { [weak self] in
            self?.updateAvatarMask()
        })
    }

    /// The header under the bubbles (without them), which each bubble shows through itself, refracted.
    private func captureLens() {
        guard let cover = self.superview, let host = cover.superview, self.window != nil, self.bounds.width > 0.0, self.bounds.height > 0.0 else {
            return
        }
        let rect = self.convert(self.bounds, to: host)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.5
        format.opaque = false
        // Hidden and shown again within this frame: nothing flickers, the picture just leaves the bubbles out.
        cover.isHidden = true
        let image = UIGraphicsImageRenderer(bounds: rect, format: format).image { context in
            host.layer.render(in: context.cgContext)
        }
        cover.isHidden = false
        self.lensImage = image.cgImage
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
    /// Colored light the bubble throws around it (neon), stronger on the beat.
    private let spillLayer = CAGradientLayer()
    private let lensLayer = CALayer()
    private let lensMask = CAShapeLayer()
    private let bodyLayer = CAGradientLayer()
    private let bodyMask = CAShapeLayer()
    private let rimLayer = CAShapeLayer()
    /// The light inside the edge (as in glass or water held to the light): a wide soft band and a thin bright one.
    private let innerGlowLayer = CAShapeLayer()
    private let innerEdgeLayer = CAShapeLayer()
    private let innerMask = CAShapeLayer()
    private let innerContainer = CALayer()
    private let shineLayer = CAGradientLayer()
    private let specularLayer = CAGradientLayer()
    private var sparkleLayers: [CALayer] = []
    private var stickerLayer: InlineStickerItemLayer?
    private var fileId: Int64?
    private var glowColor: UIColor = .white
    var soap = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false

        self.spillLayer.type = .radial
        self.spillLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.spillLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.spillLayer.compositingFilter = "screenBlendMode"
        self.layer.addSublayer(self.spillLayer)

        self.glowLayer.fillColor = UIColor.clear.cgColor
        self.glowLayer.shadowOffset = .zero
        self.layer.addSublayer(self.glowLayer)

        self.lensLayer.mask = self.lensMask
        self.lensLayer.contentsGravity = .resize
        self.lensLayer.isHidden = true
        self.layer.addSublayer(self.lensLayer)

        // Lit from above: light at the top, deep and saturated at the bottom.
        self.bodyLayer.type = .axial
        self.bodyLayer.startPoint = CGPoint(x: 0.35, y: 0.0)
        self.bodyLayer.endPoint = CGPoint(x: 0.65, y: 1.0)
        self.bodyLayer.mask = self.bodyMask
        self.layer.addSublayer(self.bodyLayer)

        self.innerGlowLayer.fillColor = UIColor.clear.cgColor
        self.innerEdgeLayer.fillColor = UIColor.clear.cgColor
        self.innerContainer.addSublayer(self.innerGlowLayer)
        self.innerContainer.addSublayer(self.innerEdgeLayer)
        self.innerContainer.mask = self.innerMask
        self.layer.addSublayer(self.innerContainer)

        self.rimLayer.fillColor = UIColor.clear.cgColor
        self.rimLayer.strokeColor = UIColor(white: 1.0, alpha: 0.38).cgColor
        self.rimLayer.lineWidth = 1.6
        self.layer.addSublayer(self.rimLayer)

        // A broad soft highlight over the upper part, and a small sharp one in it.
        self.shineLayer.type = .radial
        self.shineLayer.colors = [UIColor(white: 1.0, alpha: 0.42).cgColor, UIColor(white: 1.0, alpha: 0.16).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
        self.shineLayer.locations = [0.0, 0.5, 1.0]
        self.shineLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.shineLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.shineLayer)
        self.specularLayer.type = .radial
        self.specularLayer.colors = [UIColor(white: 1.0, alpha: 0.9).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
        self.specularLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.specularLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.specularLayer)

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
        let palette: [(UInt32, UInt32)] = [(0xff7ac8, 0xd23a95), (0x7db1ff, 0x3d63e0), (0x63f0a8, 0x1fa66a), (0xffd25e, 0xe58a1c), (0xc68bff, 0x7a3fe0), (0x6fe6f0, 0x2a9fc0)]
        func fromPalette(_ id: Int64) -> (UIColor, UIColor) {
            let pair = palette[Int(UInt64(bitPattern: id) % UInt64(palette.count))]
            return (UIColor(rgb: pair.0), UIColor(rgb: pair.1))
        }
        switch gift.gift {
        case let .unique(unique):
            for attribute in unique.attributes {
                if case let .backdrop(_, _, innerColor, outerColor, _, _, _) = attribute {
                    let inner = UIColor(rgb: UInt32(bitPattern: innerColor))
                    var saturation: CGFloat = 0.0
                    inner.getHue(nil, saturation: &saturation, brightness: nil, alpha: nil)
                    // A grey or black backdrop would make a dull bubble: the concept's are all vivid.
                    if saturation < 0.22 {
                        return fromPalette(unique.giftId)
                    }
                    return (inner, UIColor(rgb: UInt32(bitPattern: outerColor)))
                }
            }
            return fromPalette(unique.giftId)
        case let .generic(generic):
            return fromPalette(generic.id)
        }
    }

    func update(context: AccountContext, gift: ProfileGiftsContext.State.StarGift) {
        var (inner, outer) = AstraGiftBubbleView.colors(gift: gift)
        // The concept's jelly is vivid even for a muted backdrop.
        let t = AstraBubbleTuning.current
        inner = inner.withMultiplied(hue: 1.0, saturation: t.saturation, brightness: t.brightness)
        outer = outer.withMultiplied(hue: 1.0, saturation: t.saturation * 0.96, brightness: t.brightness * 1.04)
        if self.soap {
            // Clear jelly: what is behind shows through, refracted; the color thickens toward the bottom.
            self.bodyLayer.colors = [
                inner.mixedWith(.white, alpha: t.topWhite).withAlphaComponent(t.soapTop).cgColor,
                inner.withAlphaComponent(t.soapMiddle).cgColor,
                outer.withAlphaComponent(t.soapBottom).cgColor
            ]
            self.rimLayer.strokeColor = inner.mixedWith(.white, alpha: 0.7).withAlphaComponent(t.rimAlpha).cgColor
        } else {
            // Glowing jelly, nearly solid.
            self.bodyLayer.colors = [
                inner.mixedWith(.white, alpha: t.topWhite).withAlphaComponent(t.jellyTop).cgColor,
                inner.withAlphaComponent(t.jellyMiddle).cgColor,
                outer.withAlphaComponent(t.jellyBottom).cgColor
            ]
            self.rimLayer.strokeColor = inner.mixedWith(.white, alpha: 0.55).withAlphaComponent(t.rimAlpha).cgColor
        }
        self.bodyLayer.locations = [0.0, 0.5, 1.0]
        self.innerGlowLayer.strokeColor = inner.mixedWith(.white, alpha: 0.75).withAlphaComponent(t.innerGlowAlpha).cgColor
        self.innerEdgeLayer.strokeColor = UIColor(white: 1.0, alpha: t.innerEdgeAlpha).cgColor
        self.rimLayer.lineWidth = t.rimWidth
        self.shineLayer.colors = [UIColor(white: 1.0, alpha: t.shineAlpha).cgColor, UIColor(white: 1.0, alpha: t.shineAlpha * 0.38).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
        self.specularLayer.colors = [UIColor(white: 1.0, alpha: t.specularAlpha).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
        self.spillLayer.isHidden = false
        self.glowColor = inner
        self.glowLayer.shadowColor = inner.cgColor
        // The colored light it throws on the background around it (it moves with the bubble).
        self.spillLayer.colors = [inner.withAlphaComponent(0.5).cgColor, inner.withAlphaComponent(0.22).cgColor, inner.withAlphaComponent(0.07).cgColor, inner.withAlphaComponent(0.0).cgColor]
        self.spillLayer.locations = [0.0, 0.3, 0.65, 1.0]

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
        // A dark edge around the gift, so that it stands out from a bubble of its own color.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = 1.6
        layer.shadowOpacity = 0.75
        self.layer.insertSublayer(layer, above: self.innerContainer)
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
        let t = AstraBubbleTuning.current
        let path = self.blobPath(in: bounds, time: time, wobble: 1.0 + pulled * 1.5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.glowLayer.shadowPath = path
        self.glowLayer.shadowRadius = bounds.width * t.glowRadius + glow * bounds.width * 0.25
        self.glowLayer.shadowOpacity = self.soap ? Float(0.25 + 0.3 * glow) : Float(t.glowOpacity + (1.0 - t.glowOpacity) * glow)
        self.bodyMask.path = path
        self.lensMask.path = path
        self.rimLayer.path = path
        self.innerMask.path = path
        self.innerGlowLayer.path = path
        self.innerEdgeLayer.path = path
        // Stroked on the outline and clipped to it, so only the inner half shows: a band inside the edge.
        self.innerGlowLayer.lineWidth = bounds.width * t.innerGlowWidth
        self.innerEdgeLayer.lineWidth = max(1.0, bounds.width * t.innerEdgeWidth)
        let spillBase = self.soap ? t.spillOpacity * 0.45 : t.spillOpacity
        self.spillLayer.opacity = Float(min(1.0, spillBase + (1.0 - spillBase) * glow + 0.5 * pulled))
        // Pulled big, its light floods much of the screen (as in the concept).
        let spill = bounds.width * (t.spillSize + 4.0 * pulled)
        self.spillLayer.frame = bounds.insetBy(dx: -spill, dy: -spill)
        // Pulled big, the jelly thins out: the profile shows through it, as through a lens.
        self.bodyLayer.opacity = Float(1.0 - 0.5 * pulled)
        CATransaction.commit()
    }

    /// The magnified screen inside a pulled bubble.
    func setLens(image: CGImage?, contentsRect: CGRect, amount: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let image {
            if self.lensLayer.contents == nil || (self.lensLayer.contents as! CGImage) !== image {
                self.lensLayer.contents = image
            }
            self.lensLayer.contentsRect = contentsRect
            self.lensLayer.isHidden = false
            self.lensLayer.opacity = Float(amount)
        } else if !self.lensLayer.isHidden {
            self.lensLayer.isHidden = true
            self.lensLayer.contents = nil
        }
        CATransaction.commit()
    }

    /// The color the screen takes on for this gift: vivid, a little deep.
    static func flowColor(gift: ProfileGiftsContext.State.StarGift) -> UIColor {
        let (inner, outer) = AstraGiftBubbleView.colors(gift: gift)
        return inner.mixedWith(outer, alpha: 0.5).withMultiplied(hue: 1.0, saturation: 1.15, brightness: 1.0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.glowLayer.frame = bounds
        self.lensLayer.frame = bounds
        self.lensMask.frame = bounds
        self.bodyLayer.frame = bounds
        self.bodyMask.frame = bounds
        self.rimLayer.frame = bounds
        self.innerContainer.frame = bounds
        self.innerMask.frame = bounds
        self.innerGlowLayer.frame = bounds
        self.innerEdgeLayer.frame = bounds
        self.shineLayer.frame = CGRect(x: bounds.width * 0.08, y: bounds.height * 0.03, width: bounds.width * 0.7, height: bounds.height * 0.46)
        self.specularLayer.frame = CGRect(x: bounds.width * 0.2, y: bounds.height * 0.12, width: bounds.width * 0.2, height: bounds.height * 0.12)
        let positions: [CGPoint] = [CGPoint(x: 0.28, y: 0.62), CGPoint(x: 0.72, y: 0.7), CGPoint(x: 0.4, y: 0.8), CGPoint(x: 0.66, y: 0.3), CGPoint(x: 0.24, y: 0.4), CGPoint(x: 0.56, y: 0.86)]
        for (i, sparkle) in self.sparkleLayers.enumerated() {
            sparkle.position = CGPoint(x: bounds.width * positions[i].x, y: bounds.height * positions[i].y)
        }
        // The gift in the middle of its bubble, about half as wide.
        let side = bounds.width * AstraBubbleTuning.current.stickerSize
        self.stickerLayer?.frame = CGRect(x: (bounds.width - side) / 2.0, y: bounds.height * 0.5 - side / 2.0, width: side, height: side)
        CATransaction.commit()
        self.updateShape(time: 0.0, pulled: 0.0, glow: 0.0)
    }
}

/// AstraGram: the colors of a gift's bubble (the header takes them on when it is touched).
public func astraGiftBubbleColors(gift: ProfileGiftsContext.State.StarGift) -> (UIColor, UIColor) {
    return AstraGiftBubbleView.colors(gift: gift)
}

private func astraColorsClose(_ a: UIColor, _ b: UIColor) -> Bool {
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    return abs(r1 - r2) < 0.004 && abs(g1 - g2) < 0.004 && abs(b1 - b2) < 0.004
}

/// AstraGram: the bubbles' look in numbers. A file `Library/Caches/astra-bubbles.json` in the app's sandbox (written
/// by hand on a simulator) overrides any of them and is reread while the profile is open, so the look can be tuned
/// live. On a phone the file never exists and the defaults apply.
struct AstraBubbleTuning: Codable {
    var magnification: CGFloat = 1.22
    var soapTop: CGFloat = 0.16
    var soapMiddle: CGFloat = 0.2
    var soapBottom: CGFloat = 0.42
    var jellyTop: CGFloat = 0.8
    var jellyMiddle: CGFloat = 0.88
    var jellyBottom: CGFloat = 0.94
    var topWhite: CGFloat = 0.45
    var saturation: CGFloat = 1.35
    var brightness: CGFloat = 1.25
    var innerGlowWidth: CGFloat = 0.26
    var innerGlowAlpha: CGFloat = 0.3
    var innerEdgeWidth: CGFloat = 0.07
    var innerEdgeAlpha: CGFloat = 0.45
    var rimWidth: CGFloat = 1.6
    var rimAlpha: CGFloat = 0.9
    var shineAlpha: CGFloat = 0.32
    var specularAlpha: CGFloat = 0.9
    var stickerSize: CGFloat = 0.42
    var glowRadius: CGFloat = 0.34
    var glowOpacity: CGFloat = 0.75
    var spillOpacity: CGFloat = 0.6
    var spillSize: CGFloat = 1.8
    var radius: CGFloat = 19.5
    var eggHeight: CGFloat = 1.1
    var orbitScale: CGFloat = 1.2
    var orbitTilt: CGFloat = 0.55
    var orbitSpeed: CGFloat = 0.22
    var orbitSpeedMusic: CGFloat = 0.5

    init() {
    }

    init(from decoder: Decoder) throws {
        // Any field may be left out of the file.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = AstraBubbleTuning()
        func value(_ key: CodingKeys, _ fallback: CGFloat) -> CGFloat {
            return (try? container.decodeIfPresent(CGFloat.self, forKey: key)) ?? nil ?? fallback
        }
        self.magnification = value(.magnification, d.magnification)
        self.soapTop = value(.soapTop, d.soapTop)
        self.soapMiddle = value(.soapMiddle, d.soapMiddle)
        self.soapBottom = value(.soapBottom, d.soapBottom)
        self.jellyTop = value(.jellyTop, d.jellyTop)
        self.jellyMiddle = value(.jellyMiddle, d.jellyMiddle)
        self.jellyBottom = value(.jellyBottom, d.jellyBottom)
        self.topWhite = value(.topWhite, d.topWhite)
        self.saturation = value(.saturation, d.saturation)
        self.brightness = value(.brightness, d.brightness)
        self.innerGlowWidth = value(.innerGlowWidth, d.innerGlowWidth)
        self.innerGlowAlpha = value(.innerGlowAlpha, d.innerGlowAlpha)
        self.innerEdgeWidth = value(.innerEdgeWidth, d.innerEdgeWidth)
        self.innerEdgeAlpha = value(.innerEdgeAlpha, d.innerEdgeAlpha)
        self.rimWidth = value(.rimWidth, d.rimWidth)
        self.rimAlpha = value(.rimAlpha, d.rimAlpha)
        self.shineAlpha = value(.shineAlpha, d.shineAlpha)
        self.specularAlpha = value(.specularAlpha, d.specularAlpha)
        self.stickerSize = value(.stickerSize, d.stickerSize)
        self.glowRadius = value(.glowRadius, d.glowRadius)
        self.glowOpacity = value(.glowOpacity, d.glowOpacity)
        self.spillOpacity = value(.spillOpacity, d.spillOpacity)
        self.spillSize = value(.spillSize, d.spillSize)
        self.radius = value(.radius, d.radius)
        self.eggHeight = value(.eggHeight, d.eggHeight)
        self.orbitScale = value(.orbitScale, d.orbitScale)
        self.orbitTilt = value(.orbitTilt, d.orbitTilt)
        self.orbitSpeed = value(.orbitSpeed, d.orbitSpeed)
        self.orbitSpeedMusic = value(.orbitSpeedMusic, d.orbitSpeedMusic)
    }

    static var current = AstraBubbleTuning()
    private static var fileDate: Date?

    private static var url: URL? {
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("astra-bubbles.json")
    }

    /// Rereads the file when it changed; true when the numbers did.
    static func reload() -> Bool {
        guard let url = AstraBubbleTuning.url, let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else {
            return false
        }
        if date == AstraBubbleTuning.fileDate {
            return false
        }
        AstraBubbleTuning.fileDate = date
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(AstraBubbleTuning.self, from: data) else {
            return false
        }
        AstraBubbleTuning.current = value
        return true
    }
}
