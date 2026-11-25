import Foundation
import UIKit
import CoreImage
import Display

/// AstraGram: the light round the input field while a message is translated before it is sent, a copy of Telegram's
/// own translate-on-send: a thin blue-to-violet rim with a soft halo that breathes, a faint blue wash inside, slanted
/// beams sweeping left to right, twinkling sparks, and (when the translation arrives) the light gathering at the left
/// end, where the new text comes in.
final class AstraTranslateGlowView: UIView {
    /// How far the halo reaches out of the field on every side.
    static let outset: CGFloat = 10.0

    private static let rimColors: [CGColor] = [
        UIColor(rgb: 0x64B2FF).cgColor,
        UIColor(rgb: 0x4D82FF).cgColor,
        UIColor(rgb: 0x7A5CFF).cgColor,
        UIColor(rgb: 0x9D6CFF).cgColor
    ]

    private let haloHolder = CALayer()
    private let haloGradient = CAGradientLayer()
    private let haloMask = CAShapeLayer()

    private let insideHolder = CALayer()
    private let insideMask = CAShapeLayer()
    private let washGradient = CAGradientLayer()
    private let beams: [CAGradientLayer] = [CAGradientLayer(), CAGradientLayer()]
    private let leftGlow = CAGradientLayer()

    private let rimHolder = CALayer()
    private let rimGradient = CAGradientLayer()
    private let rimMask = CAShapeLayer()

    private let sparks = CAEmitterLayer()

    private var fieldRect: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false

        for gradient in [self.haloGradient, self.rimGradient] {
            gradient.colors = AstraTranslateGlowView.rimColors
            gradient.startPoint = CGPoint(x: 0.0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1.0, y: 0.5)
        }

        self.haloMask.fillColor = UIColor.clear.cgColor
        self.haloMask.strokeColor = UIColor.black.cgColor
        self.haloMask.lineWidth = 3.0
        self.haloMask.shadowColor = UIColor.black.cgColor
        self.haloMask.shadowOpacity = 1.0
        self.haloMask.shadowRadius = 3.0
        self.haloMask.shadowOffset = .zero
        self.haloHolder.addSublayer(self.haloGradient)
        self.haloHolder.mask = self.haloMask
        self.haloHolder.opacity = 0.4
        self.layer.addSublayer(self.haloHolder)

        self.insideMask.fillColor = UIColor.black.cgColor
        self.insideHolder.mask = self.insideMask
        self.washGradient.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.washGradient.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.washGradient.colors = [
            UIColor(rgb: 0x4D8BFF, alpha: 0.26).cgColor,
            UIColor(rgb: 0x5A6CFF, alpha: 0.14).cgColor,
            UIColor(rgb: 0x7A5CFF, alpha: 0.10).cgColor
        ]
        self.insideHolder.addSublayer(self.washGradient)
        for beam in self.beams {
            beam.startPoint = CGPoint(x: 0.0, y: 0.5)
            beam.endPoint = CGPoint(x: 1.0, y: 0.5)
            beam.colors = [
                UIColor(rgb: 0x6FA8FF, alpha: 0.0).cgColor,
                UIColor(rgb: 0x6FA8FF, alpha: 0.55).cgColor,
                UIColor(rgb: 0xA4B9FF, alpha: 0.75).cgColor,
                UIColor(rgb: 0x8C6BFF, alpha: 0.4).cgColor,
                UIColor(rgb: 0x8C6BFF, alpha: 0.0).cgColor
            ]
            beam.locations = [0.0, 0.38, 0.5, 0.62, 1.0]
            self.insideHolder.addSublayer(beam)
        }
        self.leftGlow.type = .radial
        self.leftGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.leftGlow.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.leftGlow.colors = [
            UIColor(rgb: 0x8CC2FF, alpha: 0.95).cgColor,
            UIColor(rgb: 0x4D82FF, alpha: 0.45).cgColor,
            UIColor(rgb: 0x4D82FF, alpha: 0.0).cgColor
        ]
        self.leftGlow.locations = [0.0, 0.45, 1.0]
        self.leftGlow.opacity = 0.0
        self.insideHolder.addSublayer(self.leftGlow)
        self.layer.addSublayer(self.insideHolder)

        self.rimMask.fillColor = UIColor.clear.cgColor
        self.rimMask.strokeColor = UIColor.black.cgColor
        self.rimMask.lineWidth = 1.2
        self.rimHolder.addSublayer(self.rimGradient)
        self.rimHolder.mask = self.rimMask
        self.layer.addSublayer(self.rimHolder)

        self.sparks.emitterShape = .rectangle
        self.sparks.emitterMode = .surface
        self.sparks.renderMode = .additive
        self.sparks.birthRate = 0.0
        let cell = CAEmitterCell()
        cell.contents = AstraTranslateGlowView.sparkImage()?.cgImage
        cell.birthRate = 16.0
        cell.lifetime = 0.9
        cell.lifetimeRange = 0.35
        cell.velocity = 4.0
        cell.velocityRange = 4.0
        cell.emissionRange = .pi * 2.0
        cell.scale = 0.22
        cell.scaleRange = 0.12
        cell.scaleSpeed = -0.12
        cell.alphaRange = 0.4
        cell.alphaSpeed = -1.0
        cell.color = UIColor(white: 1.0, alpha: 1.0).cgColor
        self.sparks.emitterCells = [cell]
        self.layer.addSublayer(self.sparks)

        self.alpha = 0.0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func sparkImage() -> UIImage? {
        let size = CGSize(width: 14.0, height: 14.0)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.6).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.25, 1.0]) {
                context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 7.0, y: 7.0), startRadius: 0.0, endCenter: CGPoint(x: 7.0, y: 7.0), endRadius: 7.0, options: [])
            }
        }
    }

    /// Lays the light out round a field of `fieldSize` (the view itself is `outset` larger on every side).
    func update(fieldSize: CGSize, cornerRadius: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let outset = AstraTranslateGlowView.outset
        let fieldRect = CGRect(origin: CGPoint(x: outset, y: outset), size: fieldSize)
        self.fieldRect = fieldRect
        let radius = min(cornerRadius, fieldSize.height / 2.0)
        let rimPath = UIBezierPath(roundedRect: fieldRect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: max(0.0, radius - 0.75)).cgPath
        let fillPath = UIBezierPath(roundedRect: fieldRect, cornerRadius: radius).cgPath
        for holder in [self.haloHolder, self.insideHolder, self.rimHolder] {
            holder.frame = self.bounds
        }
        for mask in [self.haloMask, self.rimMask, self.insideMask] {
            mask.frame = self.bounds
        }
        self.haloMask.path = rimPath
        self.rimMask.path = rimPath
        self.insideMask.path = fillPath
        self.haloGradient.frame = self.bounds
        self.rimGradient.frame = self.bounds
        self.washGradient.frame = fieldRect

        let beamWidth: CGFloat = 56.0
        for beam in self.beams {
            beam.bounds = CGRect(x: 0.0, y: 0.0, width: beamWidth, height: fieldSize.height * 2.4)
            beam.position = CGPoint(x: fieldRect.minX - beamWidth, y: fieldRect.midY)
            beam.transform = CATransform3DMakeRotation(0.42, 0.0, 0.0, 1.0)
        }
        let glowSize = CGSize(width: fieldSize.height * 3.2, height: fieldSize.height * 2.2)
        self.leftGlow.frame = CGRect(x: fieldRect.minX - glowSize.width * 0.42, y: fieldRect.midY - glowSize.height / 2.0, width: glowSize.width, height: glowSize.height)

        self.sparks.frame = fieldRect
        self.sparks.emitterPosition = CGPoint(x: fieldRect.width * 0.45, y: fieldRect.height / 2.0)
        self.sparks.emitterSize = CGSize(width: max(10.0, fieldRect.width * 0.8), height: max(4.0, fieldRect.height - 12.0))
        CATransaction.commit()
    }

    /// The light comes on and the beams start to sweep.
    func start() {
        UIView.animate(withDuration: 0.15, animations: {
            self.alpha = 1.0
        })
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 0.25
        breathe.toValue = 0.55
        breathe.duration = 0.6
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        self.haloHolder.add(breathe, forKey: "breathe")

        let travel = self.fieldRect.width + 140.0
        for (index, beam) in self.beams.enumerated() {
            let sweep = CABasicAnimation(keyPath: "position.x")
            sweep.fromValue = self.fieldRect.minX - 70.0
            sweep.toValue = self.fieldRect.minX - 70.0 + travel
            sweep.duration = 1.15
            sweep.repeatCount = .infinity
            sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sweep.beginTime = CACurrentMediaTime() + Double(index) * 0.55
            sweep.fillMode = .backwards
            beam.add(sweep, forKey: "sweep")
        }
        self.sparks.birthRate = 1.0
    }

    /// The translation has arrived: the beams go and the light gathers at the left end, where the new text comes in.
    func gatherLeft() {
        for beam in self.beams {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.duration = 0.2
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            beam.add(fade, forKey: "fade")
        }
        let glow = CAKeyframeAnimation(keyPath: "opacity")
        glow.values = [0.0, 1.0, 0.8]
        glow.keyTimes = [0.0, 0.35, 1.0]
        glow.duration = 0.6
        glow.fillMode = .forwards
        glow.isRemovedOnCompletion = false
        self.leftGlow.add(glow, forKey: "gather")
        self.sparks.birthRate = 0.5
    }

    func stop(completion: @escaping () -> Void) {
        self.sparks.birthRate = 0.0
        UIView.animate(withDuration: 0.3, animations: {
            self.alpha = 0.0
        }, completion: { _ in
            completion()
        })
    }
}

/// AstraGram: the pieces of the send button's look while messages go out translated.
enum AstraTranslateSendButton {
    /// Two four-pointed stars by the arrow's tail and a speck by its tip, drawn over the send button (`size` is the
    /// button's).
    static func sparklesImage(size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { context in
            let c = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            UIColor.white.setFill()
            func star(_ center: CGPoint, _ radius: CGFloat) {
                let path = UIBezierPath()
                let inner = radius * 0.28
                for i in 0 ..< 8 {
                    let angle = CGFloat(i) * .pi / 4.0 - .pi / 2.0
                    let r = i % 2 == 0 ? radius : inner
                    let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                    if i == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                path.close()
                path.fill()
            }
            star(CGPoint(x: c.x - 7.5, y: c.y - 8.0), 3.4)
            star(CGPoint(x: c.x - 11.5, y: c.y - 3.0), 1.9)
            context.cgContext.fillEllipse(in: CGRect(x: c.x + 7.5, y: c.y + 7.0, width: 1.8, height: 1.8))
        }
    }

    /// The white arc that runs round the send button while the translation is on its way.
    static func makeSpinner(size: CGSize) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = CGRect(origin: .zero, size: size)
        let radius = min(size.width, size.height) / 2.0 - 2.0
        layer.path = UIBezierPath(arcCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0), radius: radius, startAngle: -.pi / 2.0, endAngle: .pi * 1.5, clockwise: true).cgPath
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.white.cgColor
        layer.lineWidth = 2.0
        layer.lineCap = .round
        layer.strokeStart = 0.0
        layer.strokeEnd = 0.26
        layer.shadowColor = UIColor.white.cgColor
        layer.shadowRadius = 3.0
        layer.shadowOpacity = 0.6
        layer.shadowOffset = .zero
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0.0
        spin.toValue = CGFloat.pi * 2.0
        spin.duration = 0.85
        spin.repeatCount = .infinity
        layer.add(spin, forKey: "spin")
        return layer
    }
}

/// AstraGram: a blurred copy of a picture, for text going out of or coming into focus.
enum AstraTextBlur {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func blurred(_ image: UIImage, radius: CGFloat) -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius * image.scale, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent), let result = AstraTextBlur.context.createCGImage(output, from: input.extent) else {
            return nil
        }
        return UIImage(cgImage: result, scale: image.scale, orientation: .up)
    }

    static func snapshot(_ view: UIView) -> UIImage? {
        guard view.bounds.width > 1.0, view.bounds.height > 1.0 else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }
}
