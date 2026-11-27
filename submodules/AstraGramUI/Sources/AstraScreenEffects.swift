import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore

/// AstraGram screen effects: snow, sakura petals, autumn leaves and the like drift over the whole app
/// (Settings → AstraGram → Appearance → Effects). Drawn by one `CAEmitterLayer` in a view on top of the main window
/// that takes no touches; the keyboard (its own window) stays clear of it.
public enum AstraScreenEffect: Int, CaseIterable {
    case off = 0
    case auto = 1
    case snow = 2
    case sakura = 3
    case leaves = 4
    case stars = 5
    case hearts = 6
    case fireflies = 7

    /// What `auto` shows today: snow in winter, sakura in spring, fireflies in summer, leaves in autumn.
    public static func seasonal(date: Date = Date()) -> AstraScreenEffect {
        switch Calendar.current.component(.month, from: date) {
        case 12, 1, 2:
            return .snow
        case 3, 4, 5:
            return .sakura
        case 6, 7, 8:
            return .fireflies
        default:
            return .leaves
        }
    }

    public var resolved: AstraScreenEffect {
        return self == .auto ? AstraScreenEffect.seasonal() : self
    }

    public func title(isRussian ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Выключено" : "Off"
        case .auto: return ru ? "По сезону" : "By Season"
        case .snow: return ru ? "Снег" : "Snow"
        case .sakura: return ru ? "Сакура" : "Sakura"
        case .leaves: return ru ? "Листопад" : "Falling Leaves"
        case .stars: return ru ? "Звёзды" : "Stars"
        case .hearts: return ru ? "Сердечки" : "Hearts"
        case .fireflies: return ru ? "Светлячки" : "Fireflies"
        }
    }

    public func subtitle(isRussian ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Без эффектов" : "No effects"
        case .auto: return ru ? "Сейчас: \(AstraScreenEffect.seasonal().title(isRussian: ru).lowercased())" : "Now: \(AstraScreenEffect.seasonal().title(isRussian: ru).lowercased())"
        case .snow: return ru ? "Мягкие снежинки" : "Soft snowflakes"
        case .sakura: return ru ? "Лепестки вишни" : "Cherry petals"
        case .leaves: return ru ? "Осенние листья" : "Autumn leaves"
        case .stars: return ru ? "Мерцающее небо" : "A twinkling sky"
        case .hearts: return ru ? "Плывут вверх" : "Floating up"
        case .fireflies: return ru ? "Тёплые огоньки" : "Warm glows"
        }
    }

    /// The card's background in the picker, top to bottom.
    var cardColors: [UIColor] {
        switch self {
        case .off: return [UIColor(rgb: 0x2a2a2e), UIColor(rgb: 0x161618)]
        case .auto: return [UIColor(rgb: 0x3a7bd5), UIColor(rgb: 0xe8889c), UIColor(rgb: 0xd9822b)]
        case .snow: return [UIColor(rgb: 0x1b2a4a), UIColor(rgb: 0x3f6fa8)]
        case .sakura: return [UIColor(rgb: 0x3d1f3f), UIColor(rgb: 0xc2678d)]
        case .leaves: return [UIColor(rgb: 0x3a2312), UIColor(rgb: 0xb5651d)]
        case .stars: return [UIColor(rgb: 0x07071a), UIColor(rgb: 0x2b2160)]
        case .hearts: return [UIColor(rgb: 0x3a0f2a), UIColor(rgb: 0xd1457a)]
        case .fireflies: return [UIColor(rgb: 0x0b1f17), UIColor(rgb: 0x1f5244)]
        }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1.0) {
        self.init(red: CGFloat((rgb >> 16) & 0xff) / 255.0, green: CGFloat((rgb >> 8) & 0xff) / 255.0, blue: CGFloat(rgb & 0xff) / 255.0, alpha: alpha)
    }
}

// MARK: - Particle images (white, tinted per cell)

private enum AstraParticleImages {
    static let snowflake: CGImage? = render(size: CGSize(width: 24.0, height: 24.0)) { context, rect in
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.45, 1.0]) {
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0.0, endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width / 2.0, options: [])
        }
    }

    /// A six-armed crystal with side branches, for the big flakes in front.
    static let crystal: CGImage? = render(size: CGSize(width: 40.0, height: 40.0)) { context, rect in
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width / 2.0 - 2.0
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineCap(.round)
        context.setShadow(offset: .zero, blur: 2.5, color: UIColor.white.withAlphaComponent(0.8).cgColor)
        for i in 0 ..< 6 {
            let angle = CGFloat(i) * .pi / 3.0
            let dx = cos(angle), dy = sin(angle)
            context.setLineWidth(2.2)
            context.move(to: c)
            context.addLine(to: CGPoint(x: c.x + dx * r, y: c.y + dy * r))
            context.strokePath()
            context.setLineWidth(1.6)
            for (along, length) in [(0.45, 0.28), (0.72, 0.2)] as [(CGFloat, CGFloat)] {
                let base = CGPoint(x: c.x + dx * r * along, y: c.y + dy * r * along)
                for side in [-1.0, 1.0] as [CGFloat] {
                    let branch = angle + side * .pi / 4.0
                    context.move(to: base)
                    context.addLine(to: CGPoint(x: base.x + cos(branch) * r * length, y: base.y + sin(branch) * r * length))
                }
            }
            context.strokePath()
        }
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5.0, height: 5.0))
    }

    static let petal: CGImage? = render(size: CGSize(width: 26.0, height: 30.0)) { context, rect in
        let w = rect.width, h = rect.height
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w * 0.5, y: h))
        path.addCurve(to: CGPoint(x: w * 0.04, y: h * 0.34), controlPoint1: CGPoint(x: w * 0.18, y: h * 0.86), controlPoint2: CGPoint(x: w * 0.0, y: h * 0.6))
        path.addCurve(to: CGPoint(x: w * 0.38, y: h * 0.02), controlPoint1: CGPoint(x: w * 0.08, y: h * 0.12), controlPoint2: CGPoint(x: w * 0.24, y: h * 0.0))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.16))
        path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.02))
        path.addCurve(to: CGPoint(x: w * 0.96, y: h * 0.34), controlPoint1: CGPoint(x: w * 0.76, y: h * 0.0), controlPoint2: CGPoint(x: w * 0.92, y: h * 0.12))
        path.addCurve(to: CGPoint(x: w * 0.5, y: h), controlPoint1: CGPoint(x: w * 1.0, y: h * 0.6), controlPoint2: CGPoint(x: w * 0.82, y: h * 0.86))
        path.close()
        context.addPath(path.cgPath)
        context.clip()
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.78).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: w * 0.5, y: 0.0), end: CGPoint(x: w * 0.5, y: h), options: [])
        }
    }

    static let leaf: CGImage? = render(size: CGSize(width: 28.0, height: 28.0)) { context, rect in
        let w = rect.width, h = rect.height
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.02))
        path.addCurve(to: CGPoint(x: w * 0.96, y: h * 0.55), controlPoint1: CGPoint(x: w * 0.82, y: h * 0.12), controlPoint2: CGPoint(x: w * 1.0, y: h * 0.34))
        path.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.9), controlPoint1: CGPoint(x: w * 0.9, y: h * 0.76), controlPoint2: CGPoint(x: w * 0.68, y: h * 0.88))
        path.addCurve(to: CGPoint(x: w * 0.04, y: h * 0.55), controlPoint1: CGPoint(x: w * 0.32, y: h * 0.88), controlPoint2: CGPoint(x: w * 0.1, y: h * 0.76))
        path.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.02), controlPoint1: CGPoint(x: w * 0.0, y: h * 0.34), controlPoint2: CGPoint(x: w * 0.18, y: h * 0.12))
        path.close()
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        // The vein and the stem, cut out of the leaf.
        context.setBlendMode(.clear)
        context.setLineWidth(1.4)
        context.move(to: CGPoint(x: w * 0.5, y: h * 0.14))
        context.addLine(to: CGPoint(x: w * 0.5, y: h * 0.98))
        context.strokePath()
        context.setLineWidth(0.9)
        for y in [0.36, 0.52, 0.68] as [CGFloat] {
            context.move(to: CGPoint(x: w * 0.5, y: h * y))
            context.addLine(to: CGPoint(x: w * 0.24, y: h * (y - 0.12)))
            context.move(to: CGPoint(x: w * 0.5, y: h * y))
            context.addLine(to: CGPoint(x: w * 0.76, y: h * (y - 0.12)))
        }
        context.strokePath()
    }

    static let sparkle: CGImage? = render(size: CGSize(width: 22.0, height: 22.0)) { context, rect in
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width / 2.0
        let path = UIBezierPath()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), controlPoint: c)
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), controlPoint: c)
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), controlPoint: c)
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), controlPoint: c)
        path.close()
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
        let colors = [UIColor.white.withAlphaComponent(0.9).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
            context.drawRadialGradient(gradient, startCenter: c, startRadius: 0.0, endCenter: c, endRadius: r * 0.45, options: [])
        }
    }

    static let heart: CGImage? = render(size: CGSize(width: 26.0, height: 24.0)) { context, rect in
        let w = rect.width, h = rect.height
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.96))
        path.addCurve(to: CGPoint(x: w * 0.02, y: h * 0.32), controlPoint1: CGPoint(x: w * 0.2, y: h * 0.74), controlPoint2: CGPoint(x: w * 0.02, y: h * 0.56))
        path.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.18), controlPoint1: CGPoint(x: w * 0.02, y: h * 0.02), controlPoint2: CGPoint(x: w * 0.4, y: h * 0.0))
        path.addCurve(to: CGPoint(x: w * 0.98, y: h * 0.32), controlPoint1: CGPoint(x: w * 0.6, y: h * 0.0), controlPoint2: CGPoint(x: w * 0.98, y: h * 0.02))
        path.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.96), controlPoint1: CGPoint(x: w * 0.98, y: h * 0.56), controlPoint2: CGPoint(x: w * 0.8, y: h * 0.74))
        path.close()
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
    }

    static let glow: CGImage? = render(size: CGSize(width: 30.0, height: 30.0)) { context, rect in
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.35).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.18, 1.0]) {
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0.0, endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width / 2.0, options: [])
        }
    }

    private static func render(size: CGSize, _ draw: (CGContext, CGRect) -> Void) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3.0
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(context.cgContext, CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

// MARK: - Emitter setup

/// Configures `layer` to show `effect` over a region of `size`. `density` scales the particle count: 1 is the
/// "medium" amount for a full phone screen; a preview card passes less, in proportion to its area.
func astraConfigureEmitter(_ layer: CAEmitterLayer, effect: AstraScreenEffect, size: CGSize, density: Float, particleScale: CGFloat) {
    let effect = effect.resolved
    layer.emitterCells = nil
    layer.birthRate = 1.0
    guard effect != .off, size.width > 1.0, size.height > 1.0 else {
        layer.birthRate = 0.0
        return
    }
    let fallLifetime = Float(size.height / 40.0) + 4.0

    func cell(_ image: CGImage?, color: UIColor, birthRate: Float, lifetime: Float, velocity: CGFloat, velocityRange: CGFloat, scale: CGFloat, scaleRange: CGFloat, spin: CGFloat = 0.0, spinRange: CGFloat = 0.0, emissionLongitude: CGFloat = .pi, emissionRange: CGFloat = .pi / 10.0, xAcceleration: CGFloat = 0.0, yAcceleration: CGFloat = 0.0, alphaRange: Float = 0.25, alphaSpeed: Float = 0.0) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = image
        cell.color = color.cgColor
        cell.birthRate = birthRate * density
        cell.lifetime = lifetime
        cell.lifetimeRange = lifetime * 0.15
        cell.velocity = velocity * particleScale
        cell.velocityRange = velocityRange * particleScale
        cell.emissionLongitude = emissionLongitude
        cell.emissionRange = emissionRange
        cell.scale = scale * particleScale
        cell.scaleRange = scaleRange * particleScale
        cell.spin = spin
        cell.spinRange = spinRange
        cell.xAcceleration = xAcceleration * particleScale
        cell.yAcceleration = yAcceleration * particleScale
        cell.alphaRange = alphaRange
        cell.alphaSpeed = alphaSpeed
        return cell
    }

    // Falling effects enter above the top edge; rising ones below the bottom; stars appear anywhere. An emission
    // longitude of π points down the screen, 0 up.
    switch effect {
    case .hearts, .fireflies:
        layer.emitterShape = .line
        layer.emitterPosition = CGPoint(x: size.width / 2.0, y: size.height + 20.0)
        layer.emitterSize = CGSize(width: size.width * 1.1, height: 1.0)
    case .stars:
        layer.emitterShape = .rectangle
        layer.emitterMode = .surface
        layer.emitterPosition = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        layer.emitterSize = size
    default:
        layer.emitterShape = .line
        layer.emitterPosition = CGPoint(x: size.width / 2.0, y: -24.0)
        layer.emitterSize = CGSize(width: size.width * 1.2, height: 1.0)
    }

    switch effect {
    case .snow:
        layer.emitterCells = [
            // Big crystals in front, slowly turning; soft flakes behind them.
            cell(AstraParticleImages.crystal, color: UIColor(white: 1.0, alpha: 0.95), birthRate: 1.3, lifetime: fallLifetime, velocity: 54.0, velocityRange: 16.0, scale: 0.75, scaleRange: 0.25, spin: 0.25, spinRange: 0.9, emissionRange: .pi / 9.0, xAcceleration: 4.0, yAcceleration: 3.0),
            cell(AstraParticleImages.snowflake, color: UIColor(white: 1.0, alpha: 0.9), birthRate: 3.0, lifetime: fallLifetime, velocity: 42.0, velocityRange: 16.0, scale: 0.6, scaleRange: 0.25, emissionRange: .pi / 8.0, xAcceleration: 3.0, yAcceleration: 3.0),
            cell(AstraParticleImages.snowflake, color: UIColor(white: 1.0, alpha: 0.5), birthRate: 3.5, lifetime: fallLifetime * 1.4, velocity: 26.0, velocityRange: 10.0, scale: 0.3, scaleRange: 0.12, emissionRange: .pi / 6.0, xAcceleration: -2.0, yAcceleration: 2.0)
        ]
    case .sakura:
        let pinks: [UInt32] = [0xffc4d6, 0xff9ebb, 0xffe0ea, 0xffb3c9]
        layer.emitterCells = pinks.map { rgb in
            cell(AstraParticleImages.petal, color: UIColor(rgb: rgb, alpha: 0.95), birthRate: 0.9, lifetime: fallLifetime, velocity: 50.0, velocityRange: 20.0, scale: 0.85, scaleRange: 0.3, spin: 1.1, spinRange: 2.6, emissionRange: .pi / 5.0, xAcceleration: 10.0, yAcceleration: 4.0)
        }
    case .leaves:
        let autumn: [UInt32] = [0xe5622a, 0xf2a93b, 0xc1392b, 0xd98e32]
        layer.emitterCells = autumn.map { rgb in
            cell(AstraParticleImages.leaf, color: UIColor(rgb: rgb, alpha: 0.97), birthRate: 0.6, lifetime: fallLifetime, velocity: 56.0, velocityRange: 22.0, scale: 0.95, scaleRange: 0.3, spin: 1.0, spinRange: 3.0, emissionRange: .pi / 4.0, xAcceleration: -8.0, yAcceleration: 6.0)
        }
    case .stars:
        let tints: [UInt32] = [0xffffff, 0xfff2c4, 0xcfe3ff]
        layer.emitterCells = tints.map { rgb in
            cell(AstraParticleImages.sparkle, color: UIColor(rgb: rgb, alpha: 0.95), birthRate: 1.4, lifetime: 3.4, velocity: 3.0, velocityRange: 2.0, scale: 0.75, scaleRange: 0.35, spin: 0.4, spinRange: 0.8, emissionRange: .pi * 2.0, alphaRange: 0.3, alphaSpeed: -0.3)
        }
    case .hearts:
        let reds: [UInt32] = [0xff4f81, 0xff8fb1, 0xe0245e]
        layer.emitterCells = reds.map { rgb in
            cell(AstraParticleImages.heart, color: UIColor(rgb: rgb, alpha: 0.9), birthRate: 0.6, lifetime: fallLifetime, velocity: 46.0, velocityRange: 16.0, scale: 0.9, scaleRange: 0.35, spin: 0.0, spinRange: 0.8, emissionLongitude: 0.0, emissionRange: .pi / 6.0, alphaSpeed: -0.04)
        }
    case .fireflies:
        let warm: [UInt32] = [0xfff3a3, 0xd9ff8a, 0xffd36e]
        layer.emitterCells = warm.map { rgb in
            cell(AstraParticleImages.glow, color: UIColor(rgb: rgb, alpha: 0.95), birthRate: 1.0, lifetime: fallLifetime * 1.2, velocity: 22.0, velocityRange: 14.0, scale: 0.75, scaleRange: 0.35, emissionLongitude: 0.0, emissionRange: .pi / 3.0, xAcceleration: 4.0, alphaRange: 0.5, alphaSpeed: -0.05)
        }
    case .off, .auto:
        break
    }
}

// MARK: - The chat overlay

/// The effect over a chat's messages: placed by the chat screen above the history and below its header and input
/// panel. It takes no touches and follows the settings by itself. Low Power Mode pauses it.
public final class AstraChatEffectsView: UIView {
    private let emitter = CAEmitterLayer()
    private var effect: AstraScreenEffect = .off
    private var intensity: Int = 1
    private var configuredSize: CGSize = .zero
    private var disposable: Disposable?
    private var lowPowerObserver: NSObjectProtocol?

    override public init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        self.clipsToBounds = true
        self.layer.addSublayer(self.emitter)
        self.disposable = (AstraGramSettings.signal
        |> map { settings -> [Int] in
            return [settings.screenEffect, settings.screenEffectIntensity]
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { [weak self] values in
            self?.apply(effect: values[0], intensity: values[1])
        })
        self.lowPowerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main, using: { [weak self] _ in
            let settings = AstraGramSettings.current
            self?.apply(effect: settings.screenEffect, intensity: settings.screenEffectIntensity)
        })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable?.dispose()
        if let lowPowerObserver = self.lowPowerObserver {
            NotificationCenter.default.removeObserver(lowPowerObserver)
        }
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return nil
    }

    private func apply(effect rawEffect: Int, intensity: Int) {
        var effect = AstraScreenEffect(rawValue: rawEffect) ?? .off
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            effect = .off
        }
        guard effect != self.effect || intensity != self.intensity else {
            return
        }
        self.effect = effect
        self.intensity = intensity
        self.configuredSize = .zero
        self.setNeedsLayout()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        self.emitter.frame = self.bounds
        if self.configuredSize != self.bounds.size {
            self.configuredSize = self.bounds.size
            let density: Float = [0.45, 0.9, 1.7][max(0, min(2, self.intensity))]
            astraConfigureEmitter(self.emitter, effect: self.effect, size: self.bounds.size, density: density, particleScale: 1.0)
            if self.effect != .off {
                // Fast-forward so the chat is already filled when it opens.
                self.emitter.beginTime = CACurrentMediaTime() - CFTimeInterval(self.bounds.height / 40.0)
            }
        }
        self.isHidden = self.effect == .off
    }
}
