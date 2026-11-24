import Foundation
import UIKit
import CoreMotion

// AstraGram «Liquid Glass»: the effects every module can use. The design itself (theme, cards, bubbles) is switched by
// `AstraLook.liquidGlass`; what moves also listens to Reduce Motion, and what is see-through to Reduce Transparency.

public extension AstraLook {
    /// The Liquid Glass design is on (the app delegate keeps it current).
    static var liquidGlass: Bool {
        get { return AstraLookStorage.liquidGlass }
        set { AstraLookStorage.liquidGlass = newValue }
    }
    /// The value the app launched with, for what is set up once per process.
    static var liquidGlassAtLaunch: Bool {
        get { return AstraLookStorage.liquidGlassAtLaunch }
        set { AstraLookStorage.liquidGlassAtLaunch = newValue }
    }
    /// Liquid Glass motion may play: the design is on and Reduce Motion is off.
    static var liquidGlassMotion: Bool {
        return AstraLookStorage.liquidGlass && !UIAccessibility.isReduceMotionEnabled
    }
    /// Liquid Glass may be see-through: Reduce Transparency is off.
    static var liquidGlassTransparency: Bool {
        return !UIAccessibility.isReduceTransparencyEnabled
    }
    /// A touch began somewhere in the app's window (set by the app delegate: the glass module answers it with a ripple).
    static var liquidGlassTouchBegan: ((UITouch) -> Void)? {
        get { return AstraLookStorage.touchBegan }
        set { AstraLookStorage.touchBegan = newValue }
    }
}

private enum AstraLookStorage {
    static var liquidGlass: Bool = false
    static var liquidGlassAtLaunch: Bool = false
    static var touchBegan: ((UITouch) -> Void)?
}

/// Where the light on glass comes from. With a gyroscope the light follows the phone's tilt (30 updates a second, only
/// while some glass is on screen and the app is active); without one (the simulator) or with Reduce Motion the light
/// orbits slowly on the render server, or stands still at the top left.
public final class AstraGlassLight {
    public static let shared = AstraGlassLight()

    /// A light-following element: it is told the light's angle (radians, 0 = from the top, clockwise).
    public protocol Receiver: AnyObject {
        func astraGlassLightChanged(angle: CGFloat)
        /// No gyroscope: the receiver animates the light round on its own.
        func astraGlassLightOrbit(enabled: Bool)
    }

    private let receivers = NSHashTable<AnyObject>.weakObjects()
    private let motionManager = CMMotionManager()
    private var isRunning = false
    private var isActive = true
    private var smoothedAngle: CGFloat = -0.6
    private var observers: [NSObjectProtocol] = []

    public var hasGyro: Bool {
        return self.motionManager.isDeviceMotionAvailable
    }

    private init() {
        self.motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        let center = NotificationCenter.default
        self.observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.isActive = false
            self?.updateRunning()
        }))
        self.observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.isActive = true
            self?.updateRunning()
        }))
        self.observers.append(center.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateRunning()
            self?.refreshAll()
        }))
        self.observers.append(center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateRunning()
            self?.refreshAll()
        }))
    }

    /// The light moves (gyro or orbit) rather than standing still.
    public var isMoving: Bool {
        return AstraLook.liquidGlassMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    public var currentAngle: CGFloat {
        return self.smoothedAngle
    }

    public func add(_ receiver: Receiver) {
        assert(Thread.isMainThread)
        self.receivers.add(receiver)
        self.refresh(receiver)
        self.updateRunning()
    }

    public func remove(_ receiver: Receiver) {
        self.receivers.remove(receiver)
        self.updateRunning()
    }

    private func refresh(_ receiver: Receiver) {
        let orbit = self.isMoving && !self.hasGyro
        receiver.astraGlassLightOrbit(enabled: orbit)
        if !orbit {
            receiver.astraGlassLightChanged(angle: self.smoothedAngle)
        }
    }

    private func refreshAll() {
        for case let receiver as Receiver in self.receivers.allObjects {
            self.refresh(receiver)
        }
    }

    private func updateRunning() {
        let shouldRun = self.isActive && self.isMoving && self.hasGyro && !self.receivers.allObjects.isEmpty
        if shouldRun == self.isRunning {
            return
        }
        self.isRunning = shouldRun
        if shouldRun {
            self.motionManager.startDeviceMotionUpdates(to: .main, withHandler: { [weak self] motion, _ in
                guard let self, let motion else {
                    return
                }
                // The light hangs above the phone: tilting it slides the highlight round the glass edge.
                let gravity = motion.gravity
                let target = CGFloat(atan2(gravity.x, -gravity.y)) * 1.6 - 0.6
                var delta = target - self.smoothedAngle
                while delta > .pi { delta -= 2.0 * .pi }
                while delta < -.pi { delta += 2.0 * .pi }
                if abs(delta) < 0.004 {
                    return
                }
                self.smoothedAngle += delta * 0.35
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                for case let receiver as Receiver in self.receivers.allObjects {
                    receiver.astraGlassLightChanged(angle: self.smoothedAngle)
                }
                CATransaction.commit()
            })
        } else {
            self.motionManager.stopDeviceMotionUpdates()
        }
    }
}

/// The edge of a glass surface: a faint rim with two specular glints (a bright one where the light falls and a dim one
/// opposite) that slide round the edge with the light, and the liquid ripple a touch sends through the glass. It is a
/// plain layer tree clipped by a rounded rect, so it costs nothing per frame while the light stands still.
public final class AstraGlassEdgeLayer: CALayer, AstraGlassLight.Receiver {
    private let rimLayer = CAShapeLayer()
    private let glintLayer = CAGradientLayer()
    private let counterGlintLayer = CAGradientLayer()
    private var cornerRadiusValue: CGFloat = 0.0
    private var isDarkValue = true
    private var orbitEnabled = false
    private var lightAngle: CGFloat = -0.6
    private var isRegistered = false
    private var edgeSize = CGSize()

    override public init() {
        super.init()
        self.masksToBounds = true
        self.cornerCurve = .continuous
        self.allowsGroupOpacity = false

        self.rimLayer.fillColor = UIColor.clear.cgColor
        self.rimLayer.lineWidth = 1.0
        self.addSublayer(self.rimLayer)

        for layer in [self.glintLayer, self.counterGlintLayer] {
            layer.type = .radial
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1.0, y: 1.0)
            layer.locations = [0.0, 0.35, 1.0]
            self.addSublayer(layer)
        }
        self.updateColors()
    }

    override public init(layer: Any) {
        super.init(layer: layer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateColors() {
        let rimAlpha: CGFloat = self.isDarkValue ? 0.16 : 0.55
        self.rimLayer.strokeColor = UIColor(white: 1.0, alpha: rimAlpha).cgColor
        let glint = UIColor(white: 1.0, alpha: self.isDarkValue ? 0.42 : 0.75)
        self.glintLayer.colors = [glint.cgColor, glint.withAlphaComponent(glint.cgColor.alpha * 0.35).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
        let counter = UIColor(white: 1.0, alpha: self.isDarkValue ? 0.18 : 0.4)
        self.counterGlintLayer.colors = [counter.cgColor, counter.withAlphaComponent(counter.cgColor.alpha * 0.3).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
    }

    /// Lays the edge out for a glass of this size and corner radius.
    public func update(size: CGSize, cornerRadius: CGFloat, isDark: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if self.isDarkValue != isDark {
            self.isDarkValue = isDark
            self.updateColors()
        }
        let radius = min(cornerRadius, min(size.width, size.height) * 0.5)
        let sizeChanged = self.edgeSize != size || self.cornerRadiusValue != radius
        self.cornerRadiusValue = radius
        self.cornerRadius = radius
        // The owner sets this layer's frame (and animates it); the edge lays its own sublayers out for that size.
        self.edgeSize = size
        if sizeChanged {
            let rect = CGRect(origin: CGPoint(), size: size)
            self.rimLayer.frame = rect
            self.rimLayer.path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: max(0.0, radius - 0.5)).cgPath
            let glintSide = min(90.0, max(28.0, min(size.width, size.height) * 1.5))
            self.glintLayer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: glintSide * 1.6, height: glintSide))
            self.counterGlintLayer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: glintSide * 1.2, height: glintSide * 0.8))
            if self.orbitEnabled {
                self.installOrbit()
            } else {
                self.placeGlints(angle: self.lightAngle)
            }
        }
        CATransaction.commit()
    }

    /// Follows the shared light while the glass is in a window.
    public func setInWindow(_ inWindow: Bool) {
        if inWindow == self.isRegistered {
            return
        }
        self.isRegistered = inWindow
        if inWindow {
            AstraGlassLight.shared.add(self)
        } else {
            AstraGlassLight.shared.remove(self)
        }
    }

    /// The point on the edge the light at this angle falls on (0 = top, clockwise), a little inside the rim.
    private func edgePoint(angle: CGFloat) -> CGPoint {
        let size = self.edgeSize
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let dx = sin(angle)
        let dy = -cos(angle)
        let halfW = max(1.0, size.width * 0.5)
        let halfH = max(1.0, size.height * 0.5)
        let t = min(halfW / max(0.0001, abs(dx)), halfH / max(0.0001, abs(dy)))
        return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
    }

    private func placeGlints(angle: CGFloat) {
        self.lightAngle = angle
        let point = self.edgePoint(angle: angle)
        let counterPoint = self.edgePoint(angle: angle + .pi)
        self.glintLayer.position = point
        self.counterGlintLayer.position = counterPoint
        // The glint lies along the edge it sits on.
        let size = self.edgeSize
        let onSide = abs(point.x) < 1.0 || abs(point.x - size.width) < 1.0
        let rotation: CGFloat = onSide ? .pi * 0.5 : 0.0
        self.glintLayer.transform = CATransform3DMakeRotation(rotation, 0.0, 0.0, 1.0)
        let counterOnSide = abs(counterPoint.x) < 1.0 || abs(counterPoint.x - size.width) < 1.0
        self.counterGlintLayer.transform = CATransform3DMakeRotation(counterOnSide ? .pi * 0.5 : 0.0, 0.0, 0.0, 1.0)
    }

    public func astraGlassLightChanged(angle: CGFloat) {
        if self.orbitEnabled {
            return
        }
        self.placeGlints(angle: angle)
    }

    public func astraGlassLightOrbit(enabled: Bool) {
        if self.orbitEnabled == enabled {
            return
        }
        self.orbitEnabled = enabled
        if enabled {
            self.installOrbit()
        } else {
            self.glintLayer.removeAnimation(forKey: "astraOrbit")
            self.counterGlintLayer.removeAnimation(forKey: "astraOrbit")
            self.placeGlints(angle: self.lightAngle)
        }
    }

    /// No gyroscope: the glints travel round the edge on the render server, one lap in 9 seconds.
    private func installOrbit() {
        let size = self.edgeSize
        if size.width < 2.0 || size.height < 2.0 {
            return
        }
        let radius = self.cornerRadiusValue
        // A rounded-rect path starting at the top centre, clockwise.
        let path = CGMutablePath()
        let rect = CGRect(origin: CGPoint(), size: size)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.midX, y: rect.minY), radius: radius)
        path.closeSubpath()

        let duration: CFTimeInterval = 9.0
        // Every glass shares the same phase, so the light seems to come from one place.
        let phase = CACurrentMediaTime().truncatingRemainder(dividingBy: duration)
        for (layer, offset) in [(self.glintLayer, 0.0), (self.counterGlintLayer, 0.5)] as [(CALayer, Double)] {
            layer.transform = CATransform3DIdentity
            let animation = CAKeyframeAnimation(keyPath: "position")
            animation.path = path
            animation.calculationMode = .paced
            animation.rotationMode = .rotateAuto
            animation.duration = duration
            animation.repeatCount = .infinity
            animation.timeOffset = phase + duration * offset
            animation.isRemovedOnCompletion = false
            // Slow light: a low frame rate keeps the screen from redrawing at full speed for it.
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 8.0, maximum: 30.0, preferred: 20.0)
            layer.add(animation, forKey: "astraOrbit")
        }
    }

    /// A liquid ripple from this point: a ring of light runs out through the glass and a soft bloom fades behind it.
    public func ripple(at point: CGPoint) {
        let size = self.edgeSize
        if size.width < 4.0 || size.height < 4.0 {
            return
        }
        let reach = sqrt(size.width * size.width + size.height * size.height)
        let start: CGFloat = 6.0

        let ring = CAShapeLayer()
        ring.frame = CGRect(x: point.x - start, y: point.y - start, width: start * 2.0, height: start * 2.0)
        ring.path = UIBezierPath(ovalIn: CGRect(x: 0.0, y: 0.0, width: start * 2.0, height: start * 2.0)).cgPath
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor(white: 1.0, alpha: self.isDarkValue ? 0.55 : 0.9).cgColor
        ring.lineWidth = 1.2
        self.addSublayer(ring)

        let bloom = CAGradientLayer()
        bloom.type = .radial
        bloom.startPoint = CGPoint(x: 0.5, y: 0.5)
        bloom.endPoint = CGPoint(x: 1.0, y: 1.0)
        bloom.colors = [UIColor(white: 1.0, alpha: self.isDarkValue ? 0.28 : 0.5).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
        bloom.frame = CGRect(x: point.x - start, y: point.y - start, width: start * 2.0, height: start * 2.0)
        self.insertSublayer(bloom, below: self.rimLayer)

        let scale = reach / start
        let duration: CFTimeInterval = 0.62
        let timing = CAMediaTimingFunction(controlPoints: 0.15, 0.7, 0.3, 1.0)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            ring.removeFromSuperlayer()
            bloom.removeFromSuperlayer()
        }
        let ringScale = CABasicAnimation(keyPath: "transform.scale")
        ringScale.fromValue = 0.4
        ringScale.toValue = scale
        let ringOpacity = CAKeyframeAnimation(keyPath: "opacity")
        ringOpacity.values = [0.0, 1.0, 0.0]
        ringOpacity.keyTimes = [0.0, 0.12, 1.0]
        let ringWidth = CABasicAnimation(keyPath: "lineWidth")
        ringWidth.fromValue = 3.0 / 0.4
        ringWidth.toValue = 0.6 / scale
        let ringGroup = CAAnimationGroup()
        ringGroup.animations = [ringScale, ringOpacity, ringWidth]
        ringGroup.duration = duration
        ringGroup.timingFunction = timing
        ringGroup.fillMode = .forwards
        ringGroup.isRemovedOnCompletion = false
        ring.opacity = 0.0
        ring.add(ringGroup, forKey: "astraRipple")

        let bloomScale = CABasicAnimation(keyPath: "transform.scale")
        bloomScale.fromValue = 1.0
        bloomScale.toValue = scale * 0.7
        let bloomOpacity = CAKeyframeAnimation(keyPath: "opacity")
        bloomOpacity.values = [0.0, 1.0, 0.0]
        bloomOpacity.keyTimes = [0.0, 0.1, 1.0]
        let bloomGroup = CAAnimationGroup()
        bloomGroup.animations = [bloomScale, bloomOpacity]
        bloomGroup.duration = duration * 0.9
        bloomGroup.timingFunction = timing
        bloomGroup.fillMode = .forwards
        bloomGroup.isRemovedOnCompletion = false
        bloom.opacity = 0.0
        bloom.add(bloomGroup, forKey: "astraRipple")
        CATransaction.commit()
    }
}

/// A short liquid wobble: the layer squashes towards the press and springs back past its shape twice, like a drop of
/// gel. Only for small things (buttons, chips), never for screens.
public func astraLiquidWobble(_ layer: CALayer, strength: CGFloat = 1.0) {
    if !AstraLook.liquidGlassMotion {
        return
    }
    let size = layer.bounds.size
    if size.width < 8.0 || size.height < 8.0 || max(size.width, size.height) > 260.0 {
        return
    }
    let amount = 0.06 * strength
    // Additive, so a scale the owner set is kept.
    let x = CASpringAnimation(keyPath: "transform.scale.x")
    x.isAdditive = true
    x.fromValue = amount
    x.toValue = 0.0
    x.mass = 1.0
    x.stiffness = 300.0
    x.damping = 9.0
    x.duration = x.settlingDuration
    let y = CASpringAnimation(keyPath: "transform.scale.y")
    y.isAdditive = true
    y.fromValue = -amount
    y.toValue = 0.0
    y.mass = 1.0
    y.stiffness = 300.0
    y.damping = 9.0
    y.duration = y.settlingDuration
    layer.add(x, forKey: "astraWobbleX")
    layer.add(y, forKey: "astraWobbleY")
}

/// The aurora behind Liquid Glass lists: deep space (or a pale morning sky) with four soft colour clouds that drift and
/// breathe on the render server. Glass needs colour behind it to have something to bend; this is that colour. With
/// Reduce Motion the clouds stand still, with Reduce Transparency the backdrop is the plain base.
public final class AstraAuroraView: UIView {
    private let baseLayer = CAGradientLayer()
    private var blobLayers: [CALayer] = []
    private var isDarkValue: Bool?
    private var animating = false

    private static var blobImageCache: [UInt32: UIImage] = [:]

    private static func blobImage(color: UIColor) -> UIImage? {
        var r: CGFloat = 0.0, g: CGFloat = 0.0, b: CGFloat = 0.0, a: CGFloat = 0.0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = (UInt32(r * 255.0) << 24) | (UInt32(g * 255.0) << 16) | (UInt32(b * 255.0) << 8) | UInt32(a * 255.0)
        if let cached = AstraAuroraView.blobImageCache[key] {
            return cached
        }
        let side: CGFloat = 96.0
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let colors = [color.cgColor, color.withAlphaComponent(a * 0.45).cgColor, color.withAlphaComponent(0.0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.45, 1.0]) {
                context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: side * 0.5, y: side * 0.5), startRadius: 0.0, endCenter: CGPoint(x: side * 0.5, y: side * 0.5), endRadius: side * 0.5, options: [])
            }
        }
        AstraAuroraView.blobImageCache[key] = image
        return image
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.clipsToBounds = true
        self.baseLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.baseLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.baseLayer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The aurora's base colours: what lists sit on where the clouds do not reach.
    public static func baseColors(isDark: Bool) -> [UIColor] {
        if isDark {
            return [UIColor(rgb: 0x07061A), UIColor(rgb: 0x0B0A26), UIColor(rgb: 0x050512)]
        } else {
            return [UIColor(rgb: 0xEEF1FF), UIColor(rgb: 0xF6EEFF), UIColor(rgb: 0xEAF6FF)]
        }
    }

    private static func cloudColors(isDark: Bool) -> [UIColor] {
        if isDark {
            return [UIColor(rgb: 0x7B5CFF, alpha: 0.62), UIColor(rgb: 0x16C8F0, alpha: 0.42), UIColor(rgb: 0xFF4FD8, alpha: 0.36), UIColor(rgb: 0x3B6BFF, alpha: 0.5)]
        } else {
            return [UIColor(rgb: 0x9B85FF, alpha: 0.5), UIColor(rgb: 0x5FE0FF, alpha: 0.42), UIColor(rgb: 0xFF8FE6, alpha: 0.38), UIColor(rgb: 0x7FA2FF, alpha: 0.42)]
        }
    }

    public func update(size: CGSize, isDark: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let sizeChanged = self.baseLayer.frame.size != size
        self.baseLayer.frame = CGRect(origin: CGPoint(), size: size)
        let clouds = AstraLook.liquidGlassTransparency
        if self.isDarkValue != isDark || sizeChanged {
            self.isDarkValue = isDark
            self.baseLayer.colors = AstraAuroraView.baseColors(isDark: isDark).map { $0.cgColor }
            for layer in self.blobLayers {
                layer.removeFromSuperlayer()
            }
            self.blobLayers.removeAll()
            if clouds && size.width > 1.0 && size.height > 1.0 {
                // Where each cloud rests, as fractions of the size, and how big it is relative to the width.
                let places: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 0.12, 1.25), (0.92, 0.38, 1.1), (0.1, 0.72, 1.15), (0.85, 0.95, 1.3)]
                for (index, color) in AstraAuroraView.cloudColors(isDark: isDark).enumerated() {
                    let place = places[index % places.count]
                    let layer = CALayer()
                    layer.contents = AstraAuroraView.blobImage(color: color)?.cgImage
                    let side = size.width * place.2
                    layer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: side, height: side))
                    layer.position = CGPoint(x: size.width * place.0, y: size.height * place.1)
                    self.layer.addSublayer(layer)
                    self.blobLayers.append(layer)
                }
            }
            self.animating = false
        }
        CATransaction.commit()
        self.updateAnimations()
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        self.updateAnimations()
    }

    private func updateAnimations() {
        let shouldAnimate = self.window != nil && AstraLook.liquidGlassMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
        if shouldAnimate == self.animating {
            return
        }
        self.animating = shouldAnimate
        let size = self.bounds.size
        for (index, layer) in self.blobLayers.enumerated() {
            if !shouldAnimate {
                layer.removeAnimation(forKey: "astraDrift")
                layer.removeAnimation(forKey: "astraBreathe")
                continue
            }
            // Each cloud wanders on its own slow loop, so the sky never repeats in an obvious way.
            let base = layer.position
            let reach = CGSize(width: size.width * 0.22, height: size.height * 0.1)
            let angles: [CGFloat] = [0.0, 1.7, 3.1, 4.6]
            let a = angles[index % angles.count]
            let drift = CAKeyframeAnimation(keyPath: "position")
            drift.values = (0...4).map { step -> NSValue in
                let t = a + CGFloat(step) * .pi * 0.5
                return NSValue(cgPoint: CGPoint(x: base.x + cos(t) * reach.width, y: base.y + sin(t * 1.3) * reach.height))
            }
            drift.duration = 22.0 + Double(index) * 5.0
            drift.calculationMode = .cubic
            drift.repeatCount = .infinity
            drift.timeOffset = Double(index) * 3.0
            drift.isRemovedOnCompletion = false
            // The clouds move slowly: a low frame rate keeps the list from redrawing at full speed while it stands.
            drift.preferredFrameRateRange = CAFrameRateRange(minimum: 8.0, maximum: 24.0, preferred: 15.0)
            layer.add(drift, forKey: "astraDrift")

            let breathe = CABasicAnimation(keyPath: "transform.scale")
            breathe.fromValue = 0.9
            breathe.toValue = 1.12
            breathe.duration = 7.0 + Double(index) * 1.3
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breathe.isRemovedOnCompletion = false
            breathe.preferredFrameRateRange = CAFrameRateRange(minimum: 8.0, maximum: 24.0, preferred: 15.0)
            layer.add(breathe, forKey: "astraBreathe")
        }
    }
}

private var astraGlassCardImages: [String: UIImage] = [:]

/// A stretchable plate of glass: a see-through tint, a sheen along the top and a bright rim that fades down the sides.
/// Drawn once per look and stretched, so a list of glass cards scrolls as cheaply as a list of plain rows.
public func astraGlassCardImage(isDark: Bool, fill: UIColor, cornerRadius: CGFloat, rimAlpha: CGFloat? = nil) -> UIImage? {
    var r: CGFloat = 0.0, g: CGFloat = 0.0, b: CGFloat = 0.0, a: CGFloat = 0.0
    fill.getRed(&r, green: &g, blue: &b, alpha: &a)
    let key = "\(isDark)-\(Int(r * 255))-\(Int(g * 255))-\(Int(b * 255))-\(Int(a * 1000))-\(cornerRadius)-\(rimAlpha ?? -1.0)"
    if let image = astraGlassCardImages[key] {
        return image
    }
    let side = cornerRadius * 2.0 + 2.0
    let size = CGSize(width: side, height: side + 24.0)
    let rect = CGRect(origin: CGPoint(), size: size)
    let image = UIGraphicsImageRenderer(size: size).image { rendererContext in
        let context = rendererContext.cgContext
        let path = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: cornerRadius - 0.5)
        context.addPath(path.cgPath)
        context.setFillColor(fill.cgColor)
        context.fillPath()

        // The sheen: light caught in the upper part of the glass.
        context.saveGState()
        context.addPath(path.cgPath)
        context.clip()
        let sheenAlpha: CGFloat = isDark ? 0.07 : 0.35
        let sheenColors = [UIColor(white: 1.0, alpha: sheenAlpha).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sheenColors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: cornerRadius * 1.2), options: [])
        }
        context.restoreGState()

        // The rim: bright along the top edge, fading down the sides, faint along the bottom.
        context.saveGState()
        context.addPath(path.cgPath)
        context.setLineWidth(1.0)
        context.replacePathWithStrokedPath()
        context.clip()
        let rimTop = rimAlpha ?? (isDark ? 0.24 : 0.95)
        let rimColors = [UIColor(white: 1.0, alpha: rimTop).cgColor, UIColor(white: 1.0, alpha: rimTop * 0.25).cgColor, UIColor(white: 1.0, alpha: rimTop * 0.45).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: rimColors, locations: [0.0, 0.55, 1.0]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: size.height), options: [])
        }
        context.restoreGState()
    }.resizableImage(withCapInsets: UIEdgeInsets(top: cornerRadius + 1.0, left: cornerRadius + 1.0, bottom: cornerRadius + 1.0, right: cornerRadius + 1.0), resizingMode: .stretch)
    astraGlassCardImages[key] = image
    return image
}

/// A liquid splash where a selection lands (a tab, a chip): a glowing drop swells and fades, a ring runs out, and a
/// crown of small droplets jumps out and falls back into the surface. One-shot layers on the render server.
public func astraDropletSplash(in hostLayer: CALayer, at center: CGPoint, color: UIColor, radius: CGFloat = 22.0) {
    if !AstraLook.liquidGlassMotion {
        return
    }
    let container = CALayer()
    container.frame = CGRect(x: center.x - radius * 3.0, y: center.y - radius * 3.0, width: radius * 6.0, height: radius * 6.0)
    container.allowsGroupOpacity = false
    hostLayer.addSublayer(container)
    let localCenter = CGPoint(x: radius * 3.0, y: radius * 3.0)
    let duration: CFTimeInterval = 0.7

    CATransaction.begin()
    CATransaction.setCompletionBlock {
        container.removeFromSuperlayer()
    }

    // The swelling drop of light.
    let glow = CAGradientLayer()
    glow.type = .radial
    glow.startPoint = CGPoint(x: 0.5, y: 0.5)
    glow.endPoint = CGPoint(x: 1.0, y: 1.0)
    glow.colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0.0).cgColor]
    glow.bounds = CGRect(x: 0.0, y: 0.0, width: radius * 2.6, height: radius * 2.6)
    glow.position = localCenter
    glow.opacity = 0.0
    container.addSublayer(glow)
    let glowScale = CASpringAnimation(keyPath: "transform.scale")
    glowScale.fromValue = 0.3
    glowScale.toValue = 1.0
    glowScale.stiffness = 220.0
    glowScale.damping = 12.0
    glowScale.duration = duration
    let glowOpacity = CAKeyframeAnimation(keyPath: "opacity")
    glowOpacity.values = [0.0, 1.0, 0.0]
    glowOpacity.keyTimes = [0.0, 0.18, 1.0]
    glowOpacity.duration = duration
    glow.add(glowScale, forKey: "scale")
    glow.add(glowOpacity, forKey: "opacity")

    // The ring.
    let ring = CAShapeLayer()
    ring.bounds = CGRect(x: 0.0, y: 0.0, width: radius * 2.0, height: radius * 2.0)
    ring.position = localCenter
    ring.path = UIBezierPath(ovalIn: ring.bounds).cgPath
    ring.fillColor = UIColor.clear.cgColor
    ring.strokeColor = color.withAlphaComponent(0.8).cgColor
    ring.lineWidth = 1.5
    ring.opacity = 0.0
    container.addSublayer(ring)
    let ringScale = CABasicAnimation(keyPath: "transform.scale")
    ringScale.fromValue = 0.35
    ringScale.toValue = 1.45
    ringScale.timingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.7, 0.3, 1.0)
    ringScale.duration = duration * 0.8
    let ringOpacity = CAKeyframeAnimation(keyPath: "opacity")
    ringOpacity.values = [0.0, 1.0, 0.0]
    ringOpacity.keyTimes = [0.0, 0.15, 1.0]
    ringOpacity.duration = duration * 0.8
    ring.add(ringScale, forKey: "scale")
    ring.add(ringOpacity, forKey: "opacity")

    // The crown of droplets.
    let count = 7
    for index in 0 ..< count {
        let angle = -CGFloat.pi * 0.5 + (CGFloat(index) - CGFloat(count - 1) * 0.5) * 0.42
        let dropSide: CGFloat = index % 2 == 0 ? 4.0 : 3.0
        let drop = CALayer()
        drop.bounds = CGRect(x: 0.0, y: 0.0, width: dropSide, height: dropSide)
        drop.cornerRadius = dropSide * 0.5
        drop.backgroundColor = color.cgColor
        drop.position = localCenter
        drop.opacity = 0.0
        container.addSublayer(drop)
        let reach = radius * (index % 2 == 0 ? 1.25 : 1.05)
        let peak = CGPoint(x: localCenter.x + cos(angle) * reach, y: localCenter.y + sin(angle) * reach)
        let land = CGPoint(x: localCenter.x + cos(angle) * reach * 1.25, y: localCenter.y + sin(angle) * reach * 0.35 + radius * 0.5)
        let path = UIBezierPath()
        path.move(to: localCenter)
        path.addQuadCurve(to: land, controlPoint: CGPoint(x: peak.x, y: peak.y - radius * 0.35))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path.cgPath
        move.duration = duration
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.6, 0.6, 1.0)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0.0, 0.1, 0.6, 1.0]
        fade.duration = duration
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.2
        shrink.toValue = 0.2
        shrink.duration = duration
        drop.add(move, forKey: "move")
        drop.add(fade, forKey: "fade")
        drop.add(shrink, forKey: "shrink")
    }
    CATransaction.commit()
}

/// Glass that materializes like gel: it comes in squeezed, overshoots on two axes out of step and settles. Additive, so
/// the owner's own transform and animations are kept. `delay` lets a sliding sheet wobble as it lands.
public func astraJellyMaterialize(_ layer: CALayer, delay: CFTimeInterval = 0.0, landing: Bool = false) {
    if !AstraLook.liquidGlassMotion {
        return
    }
    let beginTime = delay > 0.0 ? layer.convertTime(CACurrentMediaTime(), from: nil) + delay : 0.0
    let x = CASpringAnimation(keyPath: "transform.scale.x")
    x.isAdditive = true
    x.fromValue = landing ? 0.04 : -0.16
    x.toValue = 0.0
    x.mass = 1.0
    x.stiffness = 260.0
    x.damping = 13.0
    x.duration = x.settlingDuration
    x.beginTime = beginTime
    x.fillMode = .backwards
    let y = CASpringAnimation(keyPath: "transform.scale.y")
    y.isAdditive = true
    y.fromValue = landing ? -0.05 : -0.28
    y.toValue = 0.0
    y.mass = 1.0
    y.stiffness = 190.0
    y.damping = 10.5
    y.duration = y.settlingDuration
    y.beginTime = beginTime
    y.fillMode = .backwards
    layer.add(x, forKey: "astraJellyX")
    layer.add(y, forKey: "astraJellyY")
}

/// A band of light sweeping across glass once (a message bubble that has just condensed out of the input field).
public func astraGlassSheen(on hostLayer: CALayer, frame: CGRect, cornerRadius: CGFloat, delay: CFTimeInterval = 0.0, isDark: Bool = true) {
    if !AstraLook.liquidGlassMotion || frame.width < 8.0 || frame.height < 8.0 {
        return
    }
    let clip = CALayer()
    clip.frame = frame
    clip.cornerRadius = min(cornerRadius, min(frame.width, frame.height) * 0.5)
    clip.cornerCurve = .continuous
    clip.masksToBounds = true
    hostLayer.addSublayer(clip)

    let bandWidth = max(40.0, min(110.0, frame.width * 0.45))
    let band = CAGradientLayer()
    band.startPoint = CGPoint(x: 0.0, y: 0.5)
    band.endPoint = CGPoint(x: 1.0, y: 0.5)
    let peak: CGFloat = isDark ? 0.32 : 0.55
    band.colors = [UIColor(white: 1.0, alpha: 0.0).cgColor, UIColor(white: 1.0, alpha: peak).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
    band.locations = [0.0, 0.5, 1.0]
    band.bounds = CGRect(x: 0.0, y: 0.0, width: bandWidth, height: frame.height * 2.0)
    band.position = CGPoint(x: -bandWidth, y: frame.height * 0.5)
    band.transform = CATransform3DMakeRotation(0.35, 0.0, 0.0, 1.0)
    clip.addSublayer(band)

    CATransaction.begin()
    CATransaction.setCompletionBlock {
        clip.removeFromSuperlayer()
    }
    let move = CABasicAnimation(keyPath: "position.x")
    move.fromValue = -bandWidth
    move.toValue = frame.width + bandWidth
    move.duration = 0.75
    move.beginTime = delay > 0.0 ? band.convertTime(CACurrentMediaTime(), from: nil) + delay : 0.0
    move.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
    move.fillMode = .both
    move.isRemovedOnCompletion = false
    band.add(move, forKey: "astraSheen")
    CATransaction.commit()
}
