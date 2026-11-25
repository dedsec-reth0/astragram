import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import AppBundle

// MARK: - The look

/// AstraGram "Серийчик": the little flame that lives in a chat with a streak. It grows with the streak, shows how
/// today goes, and can be dressed up with things unlocked by the best streak reached.
struct AstraStreakPetLook: Codable, Equatable {
    var name: String
    var head: String?
    var face: String?
    var extra: String?
    var best: Int
    var top: String?
    var bottom: String?
    var feet: String?

    static let `default` = AstraStreakPetLook(name: "", head: nil, face: nil, extra: nil, best: 0, top: nil, bottom: nil, feet: nil)

    func item(in slot: AstraStreakPetSlot) -> String? {
        switch slot {
        case .head:
            return self.head
        case .face:
            return self.face
        case .top:
            return self.top
        case .bottom:
            return self.bottom
        case .feet:
            return self.feet
        case .extra:
            return self.extra
        }
    }

    mutating func setItem(_ id: String?, in slot: AstraStreakPetSlot) {
        switch slot {
        case .head:
            self.head = id
        case .face:
            self.face = id
        case .top:
            self.top = id
        case .bottom:
            self.bottom = id
        case .feet:
            self.feet = id
        case .extra:
            self.extra = id
        }
    }
}

enum AstraStreakPetSlot: Int, CaseIterable {
    case head
    case face
    case top
    case bottom
    case feet
    case extra
}

/// Where a thing sits on the pet, in the pet's 100 x 104 drawing box (y down; the feet stand on y = 100).
struct AstraStreakPetPlacement {
    enum Anchor {
        case top
        case center
        case bottom
    }

    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    /// nil keeps the picture's own proportions; clothes are given a height to sit on the round body.
    let height: CGFloat?
    let anchor: Anchor
    /// Drawn under the face things and hats (a scarf), not over everything (a microphone in the hand).
    let underFace: Bool

    init(x: CGFloat = 50.0, y: CGFloat, width: CGFloat, height: CGFloat? = nil, anchor: Anchor, underFace: Bool = false) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.anchor = anchor
        self.underFace = underFace
    }

    static func hat(width: CGFloat, bottom: CGFloat = 32.0, x: CGFloat = 50.0) -> AstraStreakPetPlacement {
        return AstraStreakPetPlacement(x: x, y: bottom, width: width, anchor: .bottom)
    }

    static let glasses = AstraStreakPetPlacement(y: 45.0, width: 46.0, anchor: .center)
    static let clothesTop = AstraStreakPetPlacement(y: 59.0, width: 70.0, height: 30.0, anchor: .top)
    static let clothesBottom = AstraStreakPetPlacement(y: 84.0, width: 38.0, height: 16.0, anchor: .top)
    static let shoes = AstraStreakPetPlacement(y: 103.0, width: 34.0, anchor: .bottom)
}

struct AstraStreakPetItem {
    let id: String
    let slot: AstraStreakPetSlot
    /// The best streak (in days) that unlocks it.
    let unlockDays: Int
    let titleRu: String
    let titleEn: String
    let placement: AstraStreakPetPlacement

    var image: UIImage? {
        return UIImage(bundleImageName: "Astra Pet/\(self.id)")
    }
}

enum AstraStreakPetWardrobe {
    static let items: [AstraStreakPetItem] = [
        AstraStreakPetItem(id: "beanie", slot: .head, unlockDays: 0, titleRu: "Шапка", titleEn: "Beanie", placement: .hat(width: 52.0, bottom: 30.0)),
        AstraStreakPetItem(id: "cap", slot: .head, unlockDays: 3, titleRu: "Кепка", titleEn: "Cap", placement: .hat(width: 56.0, x: 54.0)),
        AstraStreakPetItem(id: "flowers", slot: .head, unlockDays: 5, titleRu: "Венок", titleEn: "Flower Crown", placement: .hat(width: 56.0)),
        AstraStreakPetItem(id: "fedora", slot: .head, unlockDays: 14, titleRu: "Шляпа", titleEn: "Fedora", placement: .hat(width: 62.0)),
        AstraStreakPetItem(id: "pirate", slot: .head, unlockDays: 30, titleRu: "Пират", titleEn: "Pirate Hat", placement: .hat(width: 66.0, bottom: 31.0)),
        AstraStreakPetItem(id: "sunglasses", slot: .face, unlockDays: 7, titleRu: "Очки", titleEn: "Sunglasses", placement: .glasses),
        AstraStreakPetItem(id: "tshirt", slot: .top, unlockDays: 0, titleRu: "Футболка", titleEn: "T-Shirt", placement: .clothesTop),
        AstraStreakPetItem(id: "hoodie", slot: .top, unlockDays: 2, titleRu: "Худи", titleEn: "Hoodie", placement: .clothesTop),
        AstraStreakPetItem(id: "sweater", slot: .top, unlockDays: 10, titleRu: "Свитер", titleEn: "Sweater", placement: .clothesTop),
        AstraStreakPetItem(id: "hawaii", slot: .top, unlockDays: 21, titleRu: "Гавайка", titleEn: "Hawaiian", placement: .clothesTop),
        AstraStreakPetItem(id: "vest", slot: .top, unlockDays: 40, titleRu: "Жилетка", titleEn: "Denim Vest", placement: .clothesTop),
        AstraStreakPetItem(id: "tuxedo", slot: .top, unlockDays: 100, titleRu: "Смокинг", titleEn: "Tuxedo", placement: .clothesTop),
        AstraStreakPetItem(id: "jeans", slot: .bottom, unlockDays: 0, titleRu: "Шорты", titleEn: "Denim Shorts", placement: .clothesBottom),
        AstraStreakPetItem(id: "cargo", slot: .bottom, unlockDays: 4, titleRu: "Карго", titleEn: "Cargo Shorts", placement: .clothesBottom),
        AstraStreakPetItem(id: "pinkSkirt", slot: .bottom, unlockDays: 6, titleRu: "Юбка", titleEn: "Skirt", placement: .clothesBottom),
        AstraStreakPetItem(id: "graySkirt", slot: .bottom, unlockDays: 12, titleRu: "Мини", titleEn: "Mini Skirt", placement: .clothesBottom),
        AstraStreakPetItem(id: "plaid", slot: .bottom, unlockDays: 25, titleRu: "Пижама", titleEn: "Plaid Pants", placement: .clothesBottom),
        AstraStreakPetItem(id: "sneakers", slot: .feet, unlockDays: 1, titleRu: "Кеды", titleEn: "Sneakers", placement: .shoes),
        AstraStreakPetItem(id: "bag", slot: .extra, unlockDays: 3, titleRu: "Сумка", titleEn: "Bag", placement: AstraStreakPetPlacement(x: 12.0, y: 76.0, width: 22.0, anchor: .center)),
        AstraStreakPetItem(id: "scarf", slot: .extra, unlockDays: 8, titleRu: "Шарф", titleEn: "Scarf", placement: AstraStreakPetPlacement(y: 57.0, width: 38.0, height: 30.0, anchor: .top, underFace: true)),
        AstraStreakPetItem(id: "mic", slot: .extra, unlockDays: 15, titleRu: "Микрофон", titleEn: "Microphone", placement: AstraStreakPetPlacement(x: 92.0, y: 64.0, width: 14.0, anchor: .center)),
        AstraStreakPetItem(id: "skateboard", slot: .extra, unlockDays: 30, titleRu: "Скейт", titleEn: "Skateboard", placement: AstraStreakPetPlacement(x: 88.0, y: 92.0, width: 34.0, anchor: .center)),
        AstraStreakPetItem(id: "boombox", slot: .extra, unlockDays: 50, titleRu: "Магнитофон", titleEn: "Boombox", placement: AstraStreakPetPlacement(x: 10.0, y: 76.0, width: 30.0, anchor: .center)),
        AstraStreakPetItem(id: "watch", slot: .extra, unlockDays: 70, titleRu: "Часы", titleEn: "Watch", placement: AstraStreakPetPlacement(x: 89.0, y: 71.0, width: 13.0, anchor: .center))
    ]

    static func item(_ id: String?) -> AstraStreakPetItem? {
        guard let id = id else {
            return nil
        }
        return AstraStreakPetWardrobe.items.first(where: { $0.id == id })
    }
}

enum AstraStreakPetStore {
    private static func key(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) -> String {
        return "astragram.streakPet.\(accountPeerId.toInt64()).\(peerId.toInt64())"
    }

    static func look(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) -> AstraStreakPetLook {
        guard let data = UserDefaults.standard.data(forKey: AstraStreakPetStore.key(accountPeerId: accountPeerId, peerId: peerId)), let look = try? JSONDecoder().decode(AstraStreakPetLook.self, from: data) else {
            return .default
        }
        return look
    }

    /// Fires when a look is saved, so the buddy floating in an open chat dresses at once.
    static let lookChanged = ValuePipe<Void>()

    static func setLook(_ look: AstraStreakPetLook, accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) {
        if let data = try? JSONEncoder().encode(look) {
            UserDefaults.standard.set(data, forKey: AstraStreakPetStore.key(accountPeerId: accountPeerId, peerId: peerId))
        }
        AstraStreakPetStore.lookChanged.putNext(Void())
    }

    /// Where the floating pet sits in chats, as fractions of the chat's size.
    static var position: CGPoint? {
        get {
            guard let values = UserDefaults.standard.array(forKey: "astragram.streakPet.position") as? [Double], values.count == 2 else {
                return nil
            }
            return CGPoint(x: values[0], y: values[1])
        }
        set {
            if let newValue = newValue {
                UserDefaults.standard.set([Double(newValue.x), Double(newValue.y)], forKey: "astragram.streakPet.position")
            } else {
                UserDefaults.standard.removeObject(forKey: "astragram.streakPet.position")
            }
        }
    }
}

// MARK: - Growth and mood

struct AstraStreakPetStage {
    let index: Int
    let nameRu: String
    let nameEn: String
    let fromDays: Int
    let nextDays: Int?
    /// The light core, the body and the rim (also the arms and legs).
    let colors: (core: UIColor, body: UIColor, rim: UIColor)
    let scale: CGFloat

    static func forDays(_ days: Int) -> AstraStreakPetStage {
        switch days {
        case ..<3:
            return AstraStreakPetStage(index: 0, nameRu: "Искорка", nameEn: "Spark", fromDays: 0, nextDays: 3, colors: (UIColor(rgb: 0xFFF3A0), UIColor(rgb: 0xFFB02E), UIColor(rgb: 0xFF6A13)), scale: 0.8)
        case ..<7:
            return AstraStreakPetStage(index: 1, nameRu: "Огонёк", nameEn: "Flicker", fromDays: 3, nextDays: 7, colors: (UIColor(rgb: 0xFFF0A0), UIColor(rgb: 0xFF9A22), UIColor(rgb: 0xF2470F)), scale: 0.87)
        case ..<30:
            return AstraStreakPetStage(index: 2, nameRu: "Пламя", nameEn: "Flame", fromDays: 7, nextDays: 30, colors: (UIColor(rgb: 0xFFE7A0), UIColor(rgb: 0xFF7F1E), UIColor(rgb: 0xE0300C)), scale: 0.94)
        case ..<100:
            return AstraStreakPetStage(index: 3, nameRu: "Костёр", nameEn: "Blaze", fromDays: 30, nextDays: 100, colors: (UIColor(rgb: 0xFFD9EC), UIColor(rgb: 0xFF6FA8), UIColor(rgb: 0xD6245B)), scale: 1.0)
        default:
            return AstraStreakPetStage(index: 4, nameRu: "Звезда", nameEn: "Star", fromDays: 100, nextDays: nil, colors: (UIColor(rgb: 0xE4FAFF), UIColor(rgb: 0x6FC8FF), UIColor(rgb: 0x5B3DF0)), scale: 1.0)
        }
    }
}

enum AstraStreakPetMood {
    case happy
    case waiting
    case sad
    case sleepy

    static func of(_ state: AstraStreakState?) -> AstraStreakPetMood {
        guard let state = state else {
            return .sleepy
        }
        if state.todayDone {
            return .happy
        }
        if state.restorableDay != nil {
            return .sad
        }
        if state.count == 0 {
            return .sleepy
        }
        return .waiting
    }
}

// MARK: - The pet itself

/// The flame creature: a round glowing body with flame tongues on top, big eyes, little arms and legs. It breathes,
/// sways, flickers and blinks, and wears its things (pictures placed on the body).
final class AstraStreakPetView: UIView {
    private let bodyContainer = UIView()
    private let legsLayer = CAShapeLayer()
    private let armsLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private let bodyLayer = CALayer()
    private let cheeksLayer = CAShapeLayer()
    private let eyesLayer = CALayer()
    private let leftEye = CALayer()
    private let rightEye = CALayer()
    private let closedEyesLayer = CAShapeLayer()
    private let browsLayer = CAShapeLayer()
    private let mouthLayer = CAShapeLayer()
    private let tearLayer = CAShapeLayer()
    private var itemLayers: [AstraStreakPetSlot: CALayer] = [:]

    private var stage = AstraStreakPetStage.forDays(0)
    private var mood: AstraStreakPetMood = .waiting
    private var look = AstraStreakPetLook.default
    private var renderedKey: String?

    /// The order the pet is put together in, back to front.
    private enum Part {
        case item(AstraStreakPetSlot)
        case legs
        case arms
        case body
        case face
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.addSubview(self.bodyContainer)
        let root = self.bodyContainer.layer

        for slot in AstraStreakPetSlot.allCases {
            let layer = CALayer()
            layer.contentsGravity = .resize
            layer.minificationFilter = .trilinear
            self.itemLayers[slot] = layer
        }
        let order: [Part] = [.legs, .item(.feet), .item(.bottom), .arms, .body, .face, .item(.top), .item(.face), .item(.head), .item(.extra)]
        for part in order {
            switch part {
            case .legs:
                root.addSublayer(self.legsLayer)
            case .arms:
                root.addSublayer(self.armsLayer)
            case .body:
                root.addSublayer(self.glowLayer)
                root.addSublayer(self.bodyLayer)
            case .face:
                root.addSublayer(self.cheeksLayer)
                self.eyesLayer.addSublayer(self.leftEye)
                self.eyesLayer.addSublayer(self.rightEye)
                root.addSublayer(self.eyesLayer)
                root.addSublayer(self.closedEyesLayer)
                root.addSublayer(self.browsLayer)
                root.addSublayer(self.mouthLayer)
                root.addSublayer(self.tearLayer)
            case let .item(slot):
                if let layer = self.itemLayers[slot] {
                    root.addSublayer(layer)
                }
            }
        }

        self.armsLayer.fillColor = UIColor.clear.cgColor
        self.armsLayer.lineCap = .round
        self.glowLayer.shadowOffset = CGSize()
        self.cheeksLayer.fillColor = UIColor(rgb: 0xFF5A6E).withAlphaComponent(0.38).cgColor
        self.closedEyesLayer.fillColor = UIColor.clear.cgColor
        self.closedEyesLayer.strokeColor = UIColor(rgb: 0x5A2412).cgColor
        self.closedEyesLayer.lineCap = .round
        self.browsLayer.fillColor = UIColor.clear.cgColor
        self.browsLayer.strokeColor = UIColor(rgb: 0x9B3A10).cgColor
        self.browsLayer.lineCap = .round
        self.mouthLayer.lineCap = .round
        self.mouthLayer.lineJoin = .round
        self.tearLayer.fillColor = UIColor(rgb: 0x7CCBFF).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(days: Int, mood: AstraStreakPetMood, look: AstraStreakPetLook) {
        self.stage = AstraStreakPetStage.forDays(days)
        self.mood = mood
        self.look = look
        self.setNeedsLayout()
        self.layoutIfNeeded()
        self.startAnimations()
    }

    /// The body in the 100 x 104 box: a round belly with three flame tongues on top.
    private static func bodyPath(_ t: (CGFloat, CGFloat) -> CGPoint) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: t(50, 4))
        path.addCurve(to: t(70, 30), controlPoint1: t(56, 14), controlPoint2: t(66, 18))
        path.addCurve(to: t(78, 17), controlPoint1: t(72, 24), controlPoint2: t(74, 20))
        path.addCurve(to: t(86, 54), controlPoint1: t(80, 27), controlPoint2: t(86, 38))
        path.addCurve(to: t(50, 86), controlPoint1: t(86, 74), controlPoint2: t(70, 86))
        path.addCurve(to: t(14, 54), controlPoint1: t(30, 86), controlPoint2: t(14, 74))
        path.addCurve(to: t(24, 22), controlPoint1: t(14, 40), controlPoint2: t(20, 30))
        path.addCurve(to: t(31, 33), controlPoint1: t(27, 27), controlPoint2: t(29, 30))
        path.addCurve(to: t(50, 4), controlPoint1: t(33, 22), controlPoint2: t(42, 14))
        path.close()
        return path
    }

    /// The body picture: a radial glow from a light core to the rim, and a lighter inner flame.
    private static func renderBody(size: CGFloat, stage: AstraStreakPetStage) -> UIImage {
        let unit = size / 100.0
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size * 1.04), format: format).image { rendererContext in
            let context = rendererContext.cgContext
            let t: (CGFloat, CGFloat) -> CGPoint = { x, y in CGPoint(x: x * unit, y: y * unit) }
            let body = AstraStreakPetView.bodyPath(t)
            context.saveGState()
            context.addPath(body.cgPath)
            context.clip()
            let colors = [stage.colors.core.cgColor, stage.colors.body.cgColor, stage.colors.rim.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.55, 1.0]) {
                context.drawRadialGradient(gradient, startCenter: t(50, 60), startRadius: 4.0 * unit, endCenter: t(50, 56), endRadius: 44.0 * unit, options: [.drawsAfterEndLocation])
            }
            let inner = UIBezierPath()
            inner.move(to: t(50, 22))
            inner.addCurve(to: t(62, 50), controlPoint1: t(56, 32), controlPoint2: t(62, 40))
            inner.addCurve(to: t(50, 62), controlPoint1: t(62, 58), controlPoint2: t(56, 62))
            inner.addCurve(to: t(38, 50), controlPoint1: t(44, 62), controlPoint2: t(38, 58))
            inner.addCurve(to: t(50, 22), controlPoint1: t(38, 40), controlPoint2: t(44, 32))
            inner.close()
            context.setFillColor(stage.colors.core.withAlphaComponent(0.35).cgColor)
            context.addPath(inner.cgPath)
            context.fillPath()
            context.restoreGState()
        }
    }

    /// One eye: white, a warm brown iris, the pupil and two highlights.
    private static func renderEye(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            let w = size.width
            let h = size.height
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
            let iris = CGRect(x: w * 0.125, y: h * 0.195, width: w * 0.75, height: h * 0.756)
            context.saveGState()
            context.addEllipse(in: iris)
            context.clip()
            let colors = [UIColor(rgb: 0x8A4A22).cgColor, UIColor(rgb: 0x3B1A0C).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                context.drawRadialGradient(gradient, startCenter: CGPoint(x: iris.midX, y: iris.midY + h * 0.03), startRadius: 0.0, endCenter: CGPoint(x: iris.midX, y: iris.midY), endRadius: iris.width * 0.56, options: [.drawsAfterEndLocation])
            }
            context.restoreGState()
            context.setFillColor(UIColor(rgb: 0x1D0C05).cgColor)
            context.fillEllipse(in: CGRect(x: w * 0.5 - w * 0.195, y: h * 0.598 - h * 0.195, width: w * 0.39, height: h * 0.39))
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: CGRect(x: w * 0.5 - w * 0.4, y: h * 0.4 - h * 0.13, width: w * 0.26, height: h * 0.26))
            context.fillEllipse(in: CGRect(x: w * 0.65, y: h * 0.65, width: w * 0.125, height: w * 0.125))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(self.bounds.width, self.bounds.height)
        guard side > 0.0 else {
            return
        }
        self.bodyContainer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: side, height: side))
        self.bodyContainer.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)

        // The 100 x 104 drawing box, standing on the bottom with room above it for a hat.
        let unit = side * self.stage.scale / 118.0
        let originX = (side - 100.0 * unit) / 2.0
        let originY = side - 104.0 * unit
        let t: (CGFloat, CGFloat) -> CGPoint = { x, y in CGPoint(x: originX + x * unit, y: originY + y * unit) }
        let full = CGRect(origin: CGPoint(), size: CGSize(width: side, height: side))

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for layer in [self.legsLayer, self.armsLayer, self.glowLayer, self.cheeksLayer, self.closedEyesLayer, self.browsLayer, self.mouthLayer, self.tearLayer] {
            layer.frame = full
        }

        let rim = self.stage.colors.rim
        let legs = UIBezierPath()
        for x: CGFloat in [41.0, 59.0] {
            let top = t(x - 3.6, 78.0)
            legs.append(UIBezierPath(roundedRect: CGRect(x: top.x, y: top.y, width: 7.2 * unit, height: 18.0 * unit), cornerRadius: 3.6 * unit))
            let foot = t(x + (x < 50.0 ? -1.5 : 1.5), 96.0)
            legs.append(UIBezierPath(ovalIn: CGRect(x: foot.x - 5.2 * unit, y: foot.y - 3.0 * unit, width: 10.4 * unit, height: 6.0 * unit)))
        }
        self.legsLayer.path = legs.cgPath
        self.legsLayer.fillColor = rim.cgColor

        let arms = UIBezierPath()
        arms.move(to: t(18, 58))
        arms.addQuadCurve(to: t(11, 75), controlPoint: t(10, 66))
        arms.move(to: t(82, 58))
        arms.addQuadCurve(to: t(89, 75), controlPoint: t(90, 66))
        self.armsLayer.path = arms.cgPath
        self.armsLayer.strokeColor = rim.cgColor
        self.armsLayer.lineWidth = 6.0 * unit

        let body = AstraStreakPetView.bodyPath(t)
        self.glowLayer.path = body.cgPath
        self.glowLayer.fillColor = self.stage.colors.body.cgColor
        self.glowLayer.shadowPath = body.cgPath
        self.glowLayer.shadowColor = rim.cgColor
        self.glowLayer.shadowOpacity = 0.8
        self.glowLayer.shadowRadius = 9.0 * unit

        let bodySize = 100.0 * unit
        let key = "\(self.stage.index)-\(Int(bodySize * 10.0))"
        if self.renderedKey != key {
            self.renderedKey = key
            self.bodyLayer.contents = AstraStreakPetView.renderBody(size: bodySize, stage: self.stage).cgImage
            let eye = AstraStreakPetView.renderEye(size: CGSize(width: 14.4 * unit, height: 16.4 * unit)).cgImage
            self.leftEye.contents = eye
            self.rightEye.contents = eye
        }
        self.bodyLayer.frame = CGRect(origin: t(0, 0), size: CGSize(width: bodySize, height: bodySize * 1.04))

        // The face.
        let eyeY: CGFloat = 45.0
        self.eyesLayer.transform = CATransform3DIdentity
        let eyesOrigin = t(0, eyeY)
        self.eyesLayer.anchorPoint = CGPoint(x: 0.5, y: eyesOrigin.y / side)
        self.eyesLayer.frame = full
        let eyeSize = CGSize(width: 14.4 * unit, height: 16.4 * unit)
        for (layer, x) in [(self.leftEye, CGFloat(38.0)), (self.rightEye, CGFloat(62.0))] {
            let center = t(x, eyeY)
            layer.frame = CGRect(x: center.x - eyeSize.width / 2.0, y: center.y - eyeSize.height / 2.0, width: eyeSize.width, height: eyeSize.height)
        }
        self.eyesLayer.isHidden = self.mood == .sleepy
        let closed = UIBezierPath()
        for x: CGFloat in [38.0, 62.0] {
            closed.move(to: t(x - 5.5, eyeY + 0.5))
            closed.addQuadCurve(to: t(x + 5.5, eyeY + 0.5), controlPoint: t(x, eyeY + 4.0))
        }
        self.closedEyesLayer.path = closed.cgPath
        self.closedEyesLayer.lineWidth = 1.8 * unit
        self.closedEyesLayer.isHidden = self.mood != .sleepy

        let brows = UIBezierPath()
        if self.mood == .sad {
            brows.move(to: t(33, 33.5))
            brows.addQuadCurve(to: t(42.5, 31.0), controlPoint: t(38, 33.5))
            brows.move(to: t(57.5, 31.0))
            brows.addQuadCurve(to: t(67, 33.5), controlPoint: t(62, 33.5))
        } else {
            brows.move(to: t(33, 33.5))
            brows.addQuadCurve(to: t(42.5, 33.0), controlPoint: t(38, 31.0))
            brows.move(to: t(57.5, 33.0))
            brows.addQuadCurve(to: t(67, 33.5), controlPoint: t(62, 31.0))
        }
        self.browsLayer.path = brows.cgPath
        self.browsLayer.lineWidth = 1.8 * unit

        let cheeks = UIBezierPath()
        for x: CGFloat in [31.0, 69.0] {
            let center = t(x, 54.5)
            cheeks.append(UIBezierPath(ovalIn: CGRect(x: center.x - 6.0 * unit, y: center.y - 3.6 * unit, width: 12.0 * unit, height: 7.2 * unit)))
        }
        self.cheeksLayer.path = cheeks.cgPath
        self.cheeksLayer.isHidden = self.mood == .sad

        let mouth = UIBezierPath()
        let mouthColor = UIColor(rgb: 0x7A2412)
        switch self.mood {
        case .happy:
            mouth.move(to: t(45, 56))
            mouth.addQuadCurve(to: t(55, 56), controlPoint: t(50, 63))
            mouth.close()
            self.mouthLayer.fillColor = mouthColor.cgColor
        case .waiting:
            mouth.move(to: t(46, 57))
            mouth.addQuadCurve(to: t(54, 57), controlPoint: t(50, 60))
            self.mouthLayer.fillColor = UIColor.clear.cgColor
        case .sleepy:
            mouth.append(UIBezierPath(ovalIn: CGRect(origin: t(48.5, 56.5), size: CGSize(width: 3.0 * unit, height: 3.4 * unit))))
            self.mouthLayer.fillColor = mouthColor.cgColor
        case .sad:
            mouth.move(to: t(46, 60))
            mouth.addQuadCurve(to: t(54, 60), controlPoint: t(50, 56))
            self.mouthLayer.fillColor = UIColor.clear.cgColor
        }
        self.mouthLayer.path = mouth.cgPath
        self.mouthLayer.strokeColor = mouthColor.cgColor
        self.mouthLayer.lineWidth = 2.0 * unit

        let tearCenter = t(64.5, 54.5)
        self.tearLayer.path = UIBezierPath(ovalIn: CGRect(x: tearCenter.x - 2.0 * unit, y: tearCenter.y - 2.6 * unit, width: 4.0 * unit, height: 5.6 * unit)).cgPath
        self.tearLayer.isHidden = self.mood != .sad

        // The things it wears.
        for slot in AstraStreakPetSlot.allCases {
            guard let layer = self.itemLayers[slot] else {
                continue
            }
            guard let item = AstraStreakPetWardrobe.item(self.look.item(in: slot)), let image = item.image else {
                layer.contents = nil
                layer.isHidden = true
                continue
            }
            let placement = item.placement
            let width = placement.width * unit
            let height = (placement.height ?? (placement.width * image.size.height / max(1.0, image.size.width))) * unit
            let anchor = t(placement.x, placement.y)
            let y: CGFloat
            switch placement.anchor {
            case .top:
                y = anchor.y
            case .center:
                y = anchor.y - height / 2.0
            case .bottom:
                y = anchor.y - height
            }
            layer.contents = image.cgImage
            layer.frame = CGRect(x: anchor.x - width / 2.0, y: y, width: width, height: height)
            layer.isHidden = false
            if slot == .extra, let face = self.itemLayers[.face] {
                // A scarf goes over the shirt, under the glasses and hats; a thing in the hand goes over everything.
                if placement.underFace {
                    self.bodyContainer.layer.insertSublayer(layer, below: face)
                } else if layer !== self.bodyContainer.layer.sublayers?.last {
                    self.bodyContainer.layer.addSublayer(layer)
                }
            }
        }

        CATransaction.commit()
    }

    private func startAnimations() {
        let layer = self.bodyContainer.layer
        if layer.animation(forKey: "astraBreath") == nil {
            let breath = CABasicAnimation(keyPath: "transform.scale.y")
            breath.fromValue = 0.97
            breath.toValue = 1.04
            breath.duration = 1.1
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(breath, forKey: "astraBreath")

            let sway = CABasicAnimation(keyPath: "transform.rotation.z")
            sway.fromValue = -0.04
            sway.toValue = 0.04
            sway.duration = 1.7
            sway.autoreverses = true
            sway.repeatCount = .infinity
            sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(sway, forKey: "astraSway")

            let flicker = CAKeyframeAnimation(keyPath: "shadowOpacity")
            flicker.values = [0.6, 0.95, 0.7, 0.9, 0.6]
            flicker.duration = 1.3
            flicker.repeatCount = .infinity
            self.glowLayer.add(flicker, forKey: "astraFlicker")

            // The arms wave a little now and then.
            let wave = CAKeyframeAnimation(keyPath: "transform.translation.y")
            wave.values = [0.0, 0.0, -1.5, 0.5, -1.0, 0.0, 0.0]
            wave.keyTimes = [0.0, 0.6, 0.68, 0.76, 0.84, 0.92, 1.0]
            wave.duration = 4.2
            wave.repeatCount = .infinity
            self.armsLayer.add(wave, forKey: "astraWave")
        }
        self.eyesLayer.removeAnimation(forKey: "astraBlink")
        if self.mood != .sleepy {
            let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
            blink.values = [1.0, 1.0, 0.1, 1.0, 1.0]
            blink.keyTimes = [0.0, 0.9, 0.94, 0.98, 1.0]
            blink.duration = 3.6
            blink.repeatCount = .infinity
            self.eyesLayer.add(blink, forKey: "astraBlink")
        }
        self.tearLayer.removeAnimation(forKey: "astraTear")
        if self.mood == .sad {
            let tear = CABasicAnimation(keyPath: "transform.translation.y")
            tear.fromValue = 0.0
            tear.toValue = self.bounds.height * 0.08
            tear.duration = 1.4
            tear.repeatCount = .infinity
            self.tearLayer.add(tear, forKey: "astraTear")
        }
    }

    /// A happy hop, when something changes.
    func bounce() {
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0.0, -self.bounds.height * 0.18, 0.0, -self.bounds.height * 0.06, 0.0]
        hop.keyTimes = [0.0, 0.3, 0.6, 0.8, 1.0]
        hop.duration = 0.6
        self.layer.add(hop, forKey: "astraHop")
    }
}

// MARK: - In the chat

/// The pet floating over a chat that has a streak: it can be dragged anywhere, and a tap opens it.
public final class AstraStreakPetAttachment {
    private let context: AccountContext
    private let peerId: EnginePeer.Id
    private weak var hostView: UIView?
    private var floatingView: AstraStreakPetFloatingView?
    private var resizeObserver: AstraStreakPetResizeObserver?
    private var disposable: Disposable?

    public init(context: AccountContext, peerId: EnginePeer.Id, hostView: UIView) {
        self.context = context
        self.peerId = peerId
        self.hostView = hostView
        AstraStreakManager.start(context: context)

        let accountPeerId = context.account.peerId
        let states: Signal<[EnginePeer.Id: AstraStreakState], NoError> = (Signal<Void, NoError>.single(Void()) |> deliverOnMainQueue)
        |> mapToSignal { _ -> Signal<[EnginePeer.Id: AstraStreakState], NoError> in
            return AstraStreakManager.forAccount(accountPeerId)?.statesSignal ?? .single([:])
        }
        let lookChanged: Signal<Void, NoError> = .single(Void()) |> then(AstraStreakPetStore.lookChanged.signal())
        self.disposable = (combineLatest(queue: .mainQueue(), AstraMessageStore.forAccount(context.account).streaks(), states, lookChanged)
        |> deliverOnMainQueue).start(next: { [weak self] streaks, states, _ in
            guard let self = self else {
                return
            }
            if streaks[peerId] != nil {
                self.show(state: states[peerId])
            } else {
                self.hide()
            }
        })
    }

    deinit {
        self.disposable?.dispose()
        self.floatingView?.removeFromSuperview()
        self.resizeObserver?.removeFromSuperview()
    }

    private func show(state: AstraStreakState?) {
        guard let hostView = self.hostView else {
            return
        }
        let accountPeerId = self.context.account.peerId
        var look = AstraStreakPetStore.look(accountPeerId: accountPeerId, peerId: self.peerId)
        let days = state?.displayCount ?? 0
        if days > look.best {
            look.best = days
            AstraStreakPetStore.setLook(look, accountPeerId: accountPeerId, peerId: self.peerId)
        }
        let view: AstraStreakPetFloatingView
        if let current = self.floatingView {
            view = current
        } else {
            let context = self.context
            let peerId = self.peerId
            view = AstraStreakPetFloatingView(frame: CGRect(x: 0.0, y: 0.0, width: 72.0, height: 88.0))
            view.tapped = {
                guard let top = astraTopViewController() else {
                    return
                }
                top.present(AstraStreakPetController(context: context, peerId: peerId), animated: true)
            }
            hostView.addSubview(view)
            self.floatingView = view
            view.placeInitially(in: hostView.bounds)
            view.appear()
            if self.resizeObserver == nil {
                // The chat resizes while it stays open (rotation, split view, Stage Manager): the pet is put back at its
                // saved spot within the new size, or it could be left outside the view, where it cannot be dragged back.
                let observer = AstraStreakPetResizeObserver(frame: hostView.bounds)
                observer.resized = { [weak self] in
                    guard let self = self, let hostView = self.hostView, let view = self.floatingView, hostView.bounds.width > 0.0, hostView.bounds.height > 0.0 else {
                        return
                    }
                    view.placeInitially(in: hostView.bounds)
                }
                hostView.insertSubview(observer, at: 0)
                self.resizeObserver = observer
            }
        }
        hostView.bringSubviewToFront(view)
        view.update(days: days, mood: AstraStreakPetMood.of(state), look: look)
    }

    private func hide() {
        self.floatingView?.removeFromSuperview()
        self.floatingView = nil
    }
}

/// An empty view that follows the size of the view it is in (by autoresizing) and says when that size changes, as the
/// chat's view cannot be subclassed to hear about its own layout.
final class AstraStreakPetResizeObserver: UIView {
    var resized: (() -> Void)?
    private var lastSize: CGSize?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        self.isAccessibilityElement = false
        self.lastSize = frame.size
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Only a change of size moves the pet, so a layout pass during a drag does not undo it.
        if self.lastSize != self.bounds.size {
            self.lastSize = self.bounds.size
            self.resized?()
        }
    }
}

final class AstraStreakPetFloatingView: UIView {
    private let petView = AstraStreakPetView(frame: CGRect())
    private let countLabel = UILabel()
    private let countBackground = UIView()
    var tapped: (() -> Void)?
    private var dragStart: CGPoint = CGPoint()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addSubview(self.petView)
        self.countBackground.backgroundColor = UIColor(white: 0.0, alpha: 0.55)
        self.countBackground.layer.cornerRadius = 9.0
        self.addSubview(self.countBackground)
        self.countLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .bold)
        self.countLabel.textColor = .white
        self.countLabel.textAlignment = .center
        self.addSubview(self.countLabel)
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture)))
        self.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:))))
        self.isAccessibilityElement = true
        self.accessibilityTraits = [.button]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.petView.frame = CGRect(x: 0.0, y: 0.0, width: self.bounds.width, height: self.bounds.width)
        let labelSize = self.countLabel.sizeThatFits(CGSize(width: 100.0, height: 18.0))
        let width = max(30.0, labelSize.width + 12.0)
        self.countBackground.frame = CGRect(x: (self.bounds.width - width) / 2.0, y: self.bounds.width - 4.0, width: width, height: 18.0)
        self.countLabel.frame = self.countBackground.frame
    }

    func update(days: Int, mood: AstraStreakPetMood, look: AstraStreakPetLook) {
        self.countLabel.text = "🔥\(days)"
        self.accessibilityLabel = "🔥 \(days)"
        self.petView.update(days: days, mood: mood, look: look)
        self.setNeedsLayout()
    }

    func placeInitially(in bounds: CGRect) {
        let fraction = AstraStreakPetStore.position ?? CGPoint(x: 0.86, y: 0.62)
        self.center = self.clamped(CGPoint(x: bounds.width * fraction.x, y: bounds.height * fraction.y), in: bounds)
    }

    func appear() {
        self.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        self.alpha = 0.0
        UIView.animate(withDuration: 0.5, delay: 0.15, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.0, options: [], animations: {
            self.transform = .identity
            self.alpha = 1.0
        })
    }

    private func clamped(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        let safe = self.superview?.safeAreaInsets ?? UIEdgeInsets()
        let halfWidth = self.bounds.width / 2.0
        let halfHeight = self.bounds.height / 2.0
        let x = min(max(point.x, halfWidth + 6.0), bounds.width - halfWidth - 6.0)
        let y = min(max(point.y, safe.top + 60.0 + halfHeight), bounds.height - safe.bottom - 70.0 - halfHeight)
        return CGPoint(x: x, y: y)
    }

    @objc private func tapGesture() {
        self.petView.bounce()
        AstraHaptics.toggle()
        self.tapped?()
    }

    @objc private func panGesture(_ recognizer: UIPanGestureRecognizer) {
        guard let superview = self.superview else {
            return
        }
        switch recognizer.state {
        case .began:
            self.dragStart = self.center
            UIView.animate(withDuration: 0.15, animations: {
                self.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
            })
        case .changed:
            let translation = recognizer.translation(in: superview)
            self.center = self.clamped(CGPoint(x: self.dragStart.x + translation.x, y: self.dragStart.y + translation.y), in: superview.bounds)
        case .ended, .cancelled, .failed:
            let velocity = recognizer.velocity(in: superview)
            let target = self.clamped(CGPoint(x: self.center.x + velocity.x * 0.08, y: self.center.y + velocity.y * 0.08), in: superview.bounds)
            UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.0, options: [], animations: {
                self.transform = .identity
                self.center = target
            })
            if superview.bounds.width > 0.0 && superview.bounds.height > 0.0 {
                AstraStreakPetStore.position = CGPoint(x: target.x / superview.bounds.width, y: target.y / superview.bounds.height)
            }
        default:
            break
        }
    }
}

// MARK: - The pet's screen

/// Opened from the floating pet: the pet up close, how the streak goes, and its wardrobe.
final class AstraStreakPetController: UIViewController {
    private let context: AccountContext
    private let peerId: EnginePeer.Id
    private let isRussian: Bool
    private var disposable: Disposable?
    private var state: AstraStreakState?
    private var peerName = ""
    private var look: AstraStreakPetLook

    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let petView = AstraStreakPetView(frame: CGRect())
    private let nameButton = UIButton(type: .system)
    private let countLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stageLabel = UILabel()
    private let stageProgress = UIProgressView(progressViewStyle: .default)
    private let todayCard = UIStackView()
    private let wardrobeStack = UIStackView()
    private let restoreButton = UIButton(type: .system)

    init(context: AccountContext, peerId: EnginePeer.Id) {
        self.context = context
        self.peerId = peerId
        self.isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.astraUsesRussianTexts
        self.look = AstraStreakPetStore.look(accountPeerId: context.account.peerId, peerId: peerId)
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .pageSheet
        self.overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable?.dispose()
    }

    private func text(_ ru: String, _ en: String) -> String {
        return self.isRussian ? ru : en
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let background = CAGradientLayer()
        background.colors = [UIColor(rgb: 0x2A1206).cgColor, UIColor(rgb: 0x0E0710).cgColor]
        background.frame = CGRect(x: 0.0, y: 0.0, width: 2000.0, height: 3000.0)
        self.view.layer.insertSublayer(background, at: 0)
        self.view.backgroundColor = UIColor(rgb: 0x0E0710)

        // The iOS sheet close button: a light glyph in a translucent circle.
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.0, weight: .bold)), for: .normal)
        close.tintColor = UIColor(white: 1.0, alpha: 0.85)
        close.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
        close.layer.cornerRadius = 15.0
        close.accessibilityLabel = self.text("Закрыть", "Close")
        close.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false

        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.alwaysBounceVertical = true
        self.view.addSubview(self.scrollView)
        self.view.addSubview(close)
        self.content.axis = .vertical
        self.content.alignment = .fill
        self.content.spacing = 14.0
        self.content.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.content)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 10.0),
            close.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0),
            close.widthAnchor.constraint(equalToConstant: 30.0),
            close.heightAnchor.constraint(equalToConstant: 30.0),
            self.scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.content.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 36.0),
            self.content.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -32.0),
            self.content.leadingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.leadingAnchor, constant: 20.0),
            self.content.trailingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.trailingAnchor, constant: -20.0)
        ])

        let petContainer = UIView()
        petContainer.translatesAutoresizingMaskIntoConstraints = false
        self.petView.translatesAutoresizingMaskIntoConstraints = false
        petContainer.addSubview(self.petView)
        NSLayoutConstraint.activate([
            petContainer.heightAnchor.constraint(equalToConstant: 190.0),
            self.petView.widthAnchor.constraint(equalToConstant: 190.0),
            self.petView.heightAnchor.constraint(equalToConstant: 190.0),
            self.petView.centerXAnchor.constraint(equalTo: petContainer.centerXAnchor),
            self.petView.centerYAnchor.constraint(equalTo: petContainer.centerYAnchor)
        ])
        petContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.petPressed)))
        self.content.addArrangedSubview(petContainer)

        self.nameButton.titleLabel?.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        self.nameButton.tintColor = .white
        self.nameButton.addTarget(self, action: #selector(self.renamePressed), for: .touchUpInside)
        self.content.addArrangedSubview(self.nameButton)

        self.countLabel.font = UIFont.systemFont(ofSize: 44.0, weight: .heavy)
        self.countLabel.textAlignment = .center
        self.countLabel.textColor = UIColor(rgb: 0xFFB13D)
        self.content.addArrangedSubview(self.countLabel)
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        self.subtitleLabel.numberOfLines = 0
        self.subtitleLabel.textAlignment = .center
        self.content.addArrangedSubview(self.subtitleLabel)

        let stageBox = UIStackView(arrangedSubviews: [self.stageLabel, self.stageProgress])
        stageBox.axis = .vertical
        stageBox.spacing = 8.0
        self.stageLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
        self.stageLabel.textColor = .white
        self.stageLabel.numberOfLines = 0
        self.stageProgress.progressTintColor = UIColor(rgb: 0xFF8A1F)
        self.stageProgress.trackTintColor = UIColor(white: 1.0, alpha: 0.12)
        self.content.addArrangedSubview(self.card(stageBox))

        self.todayCard.axis = .vertical
        self.todayCard.spacing = 10.0
        self.content.addArrangedSubview(self.card(self.todayCard))

        self.restoreButton.setTitle(self.text("🔥 Восстановить вчерашний день", "🔥 Restore Yesterday"), for: .normal)
        self.restoreButton.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .bold)
        self.restoreButton.tintColor = .white
        self.restoreButton.backgroundColor = UIColor(rgb: 0xF2380F)
        self.restoreButton.layer.cornerRadius = 14.0
        self.restoreButton.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        self.restoreButton.addTarget(self, action: #selector(self.restorePressed), for: .touchUpInside)
        self.content.addArrangedSubview(self.restoreButton)

        let wardrobeTitle = UILabel()
        wardrobeTitle.text = self.text("Гардероб", "Wardrobe")
        wardrobeTitle.font = UIFont.systemFont(ofSize: 18.0, weight: .bold)
        wardrobeTitle.textColor = .white
        self.wardrobeStack.axis = .vertical
        self.wardrobeStack.spacing = 12.0
        let wardrobeBox = UIStackView(arrangedSubviews: [wardrobeTitle, self.wardrobeStack])
        wardrobeBox.axis = .vertical
        wardrobeBox.spacing = 10.0
        self.content.addArrangedSubview(self.card(wardrobeBox))

        let details = UIButton(type: .system)
        details.setTitle(self.text("Подробнее об огоньке", "Streak Details"), for: .normal)
        details.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        details.tintColor = UIColor(rgb: 0xFFB13D)
        details.addTarget(self, action: #selector(self.detailsPressed), for: .touchUpInside)
        self.content.addArrangedSubview(details)

        let accountPeerId = self.context.account.peerId
        let peerId = self.peerId
        let states: Signal<[EnginePeer.Id: AstraStreakState], NoError> = (Signal<Void, NoError>.single(Void()) |> deliverOnMainQueue)
        |> mapToSignal { _ -> Signal<[EnginePeer.Id: AstraStreakState], NoError> in
            return AstraStreakManager.forAccount(accountPeerId)?.statesSignal ?? .single([:])
        }
        self.disposable = (combineLatest(queue: .mainQueue(), states, self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)))
        |> deliverOnMainQueue).start(next: { [weak self] states, peer in
            guard let self = self else {
                return
            }
            self.state = states[peerId] ?? AstraStreak.cached(accountPeerId: accountPeerId, peerId: peerId)
            self.peerName = peer?.compactDisplayTitle ?? ""
            self.reload()
        })
        self.reload()
    }

    private func card(_ inner: UIView) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor(white: 1.0, alpha: 0.07)
        box.layer.cornerRadius = 18.0
        inner.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(inner)
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 14.0),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14.0),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16.0),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16.0)
        ])
        return box
    }

    private func progressRow(title: String, value: Int, need: Int) -> UIView {
        let label = UILabel()
        label.text = "\(title)  \(min(value, need))/\(need)" + (value >= need ? " ✅" : "")
        label.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        label.textColor = .white
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progress = Float(min(value, need)) / Float(max(1, need))
        bar.progressTintColor = value >= need ? UIColor(rgb: 0x3DDC84) : UIColor(rgb: 0xFF8A1F)
        bar.trackTintColor = UIColor(white: 1.0, alpha: 0.12)
        let stack = UIStackView(arrangedSubviews: [label, bar])
        stack.axis = .vertical
        stack.spacing = 6.0
        return stack
    }

    private func reload() {
        guard self.isViewLoaded else {
            return
        }
        let days = self.state?.displayCount ?? 0
        if days > self.look.best {
            self.look.best = days
            self.saveLook()
        }
        let stage = AstraStreakPetStage.forDays(days)
        let mood = AstraStreakPetMood.of(self.state)
        self.petView.update(days: days, mood: mood, look: self.look)

        let name = self.look.name.isEmpty ? (self.isRussian ? stage.nameRu : stage.nameEn) : self.look.name
        self.nameButton.setTitle("\(name) ✎", for: .normal)
        self.countLabel.text = "🔥 \(days)"
        let moodText: String
        switch mood {
        case .happy:
            moodText = self.text("Сегодня день засчитан — серийчик счастлив!", "Today counts — your buddy is happy!")
        case .waiting:
            moodText = self.text("Серийчик ждёт сегодняшних сообщений", "Your buddy is waiting for today's messages")
        case .sad:
            moodText = self.text("Вчера пропустили — серийчику грустно. Восстановите день, пока не поздно", "Yesterday was missed — your buddy is sad. Restore the day while you can")
        case .sleepy:
            moodText = self.text("Серийчик спит. Напишите друг другу по \(AstraStreak.messagesPerDay) сообщения, чтобы разбудить", "Your buddy is asleep. Write \(AstraStreak.messagesPerDay) messages each to wake it")
        }
        let daysWord = astraDaysText(days, isRussian: self.isRussian).replacingOccurrences(of: "\(days) ", with: "")
        self.subtitleLabel.text = self.text("\(daysWord) подряд · \(self.peerName)", "\(daysWord) in a row · \(self.peerName)") + "\n" + moodText

        if let next = stage.nextDays {
            let nextStage = AstraStreakPetStage.forDays(next)
            self.stageLabel.text = self.text("Стадия: \(stage.nameRu). До «\(nextStage.nameRu)» ещё \(astraDaysText(max(0, next - days), isRussian: true))", "Stage: \(stage.nameEn). \(max(0, next - days)) days to \(nextStage.nameEn)")
            self.stageProgress.progress = Float(days - stage.fromDays) / Float(max(1, next - stage.fromDays))
        } else {
            self.stageLabel.text = self.text("Стадия: \(stage.nameRu) — высшая!", "Stage: \(stage.nameEn) — the highest!")
            self.stageProgress.progress = 1.0
        }

        for view in self.todayCard.arrangedSubviews {
            view.removeFromSuperview()
        }
        let need = AstraStreak.messagesPerDay
        let todayTitle = UILabel()
        todayTitle.text = self.text("Сегодня", "Today")
        todayTitle.font = UIFont.systemFont(ofSize: 18.0, weight: .bold)
        todayTitle.textColor = .white
        self.todayCard.addArrangedSubview(todayTitle)
        self.todayCard.addArrangedSubview(self.progressRow(title: self.text("Вы", "You"), value: self.state?.todayMine ?? 0, need: need))
        self.todayCard.addArrangedSubview(self.progressRow(title: self.peerName, value: self.state?.todayTheirs ?? 0, need: need))
        let restores = UILabel()
        restores.text = self.text("Восстановлений на неделе: \(self.state?.restoresLeft ?? AstraStreak.restoresPerWeek) из \(AstraStreak.restoresPerWeek)", "Restores this week: \(self.state?.restoresLeft ?? AstraStreak.restoresPerWeek) of \(AstraStreak.restoresPerWeek)")
        restores.font = UIFont.systemFont(ofSize: 13.0)
        restores.textColor = UIColor(white: 1.0, alpha: 0.6)
        self.todayCard.addArrangedSubview(restores)

        self.restoreButton.isHidden = self.state?.restorableDay == nil

        self.reloadWardrobe()
    }

    private func reloadWardrobe() {
        for view in self.wardrobeStack.arrangedSubviews {
            view.removeFromSuperview()
        }
        for slot in AstraStreakPetSlot.allCases {
            let title = UILabel()
            switch slot {
            case .head:
                title.text = self.text("На голову", "Head")
            case .face:
                title.text = self.text("На лицо", "Face")
            case .top:
                title.text = self.text("Верх", "Top")
            case .bottom:
                title.text = self.text("Низ", "Bottom")
            case .feet:
                title.text = self.text("Обувь", "Shoes")
            case .extra:
                title.text = self.text("Аксессуар", "Accessory")
            }
            title.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
            title.textColor = UIColor(white: 1.0, alpha: 0.6)
            self.wardrobeStack.addArrangedSubview(title)

            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8.0
            row.distribution = .fill
            row.alignment = .center
            let current = self.look.item(in: slot)
            row.addArrangedSubview(self.wardrobeButton(image: nil, caption: self.text("Нет", "None"), selected: current == nil, locked: false, tag: slot.rawValue * 100 + 99))
            for (index, item) in AstraStreakPetWardrobe.items.enumerated() where item.slot == slot {
                let locked = self.look.best < item.unlockDays
                row.addArrangedSubview(self.wardrobeButton(image: item.image, caption: locked ? "🔒 \(item.unlockDays)" : (self.isRussian ? item.titleRu : item.titleEn), selected: current == item.id, locked: locked, tag: slot.rawValue * 100 + index))
            }
            let rowScroll = UIScrollView()
            rowScroll.showsHorizontalScrollIndicator = false
            rowScroll.alwaysBounceHorizontal = true
            row.translatesAutoresizingMaskIntoConstraints = false
            rowScroll.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: rowScroll.contentLayoutGuide.topAnchor),
                row.bottomAnchor.constraint(equalTo: rowScroll.contentLayoutGuide.bottomAnchor),
                row.leadingAnchor.constraint(equalTo: rowScroll.contentLayoutGuide.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: rowScroll.contentLayoutGuide.trailingAnchor),
                rowScroll.heightAnchor.constraint(equalTo: row.heightAnchor)
            ])
            self.wardrobeStack.addArrangedSubview(rowScroll)
        }
    }

    private func wardrobeButton(image: UIImage?, caption: String, selected: Bool, locked: Bool, tag: Int) -> UIView {
        let button = UIButton(type: .custom)
        button.tag = tag
        button.backgroundColor = selected ? UIColor(rgb: 0xFF8A1F).withAlphaComponent(0.35) : UIColor(white: 1.0, alpha: 0.06)
        button.layer.cornerRadius = 12.0
        button.layer.borderWidth = selected ? 1.5 : 0.0
        button.layer.borderColor = UIColor(rgb: 0xFFB13D).cgColor
        button.alpha = locked ? 0.4 : 1.0
        button.addTarget(self, action: #selector(self.wardrobePressed(_:)), for: .touchUpInside)
        let picture: UIView
        if let image = image {
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 40.0),
                imageView.heightAnchor.constraint(equalToConstant: 34.0)
            ])
            picture = imageView
        } else {
            let noneLabel = UILabel()
            noneLabel.text = "∅"
            noneLabel.font = UIFont.systemFont(ofSize: 24.0)
            noneLabel.textAlignment = .center
            noneLabel.textColor = .white
            picture = noneLabel
        }
        let captionLabel = UILabel()
        captionLabel.text = caption
        captionLabel.font = UIFont.systemFont(ofSize: 9.0, weight: .medium)
        captionLabel.textColor = UIColor(white: 1.0, alpha: 0.75)
        captionLabel.textAlignment = .center
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.7
        let stack = UIStackView(arrangedSubviews: [picture, captionLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2.0
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: button.leadingAnchor, constant: 2.0),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -2.0),
            button.heightAnchor.constraint(equalToConstant: 64.0),
            button.widthAnchor.constraint(equalToConstant: 64.0)
        ])
        return button
    }

    private func saveLook() {
        AstraStreakPetStore.setLook(self.look, accountPeerId: self.context.account.peerId, peerId: self.peerId)
    }

    @objc private func wardrobePressed(_ sender: UIButton) {
        guard let slot = AstraStreakPetSlot(rawValue: sender.tag / 100) else {
            return
        }
        let index = sender.tag % 100
        var id: String?
        if index != 99 {
            guard index < AstraStreakPetWardrobe.items.count else {
                return
            }
            let item = AstraStreakPetWardrobe.items[index]
            if self.look.best < item.unlockDays {
                AstraHaptics.warning()
                let alert = UIAlertController(title: self.isRussian ? item.titleRu : item.titleEn, message: self.text("Откроется, когда огонёк дойдёт до \(astraDaysText(item.unlockDays, isRussian: true)).", "Unlocks when the streak reaches \(item.unlockDays) days."), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(alert, animated: true)
                return
            }
            id = item.id
        }
        self.look.setItem(id, in: slot)
        self.saveLook()
        AstraHaptics.success()
        self.reload()
        self.petView.bounce()
    }

    @objc private func petPressed() {
        AstraHaptics.toggle()
        self.petView.bounce()
    }

    @objc private func renamePressed() {
        let alert = UIAlertController(title: self.text("Имя серийчика", "Buddy's Name"), message: nil, preferredStyle: .alert)
        alert.addTextField(configurationHandler: { [weak self] field in
            field.text = self?.look.name
            field.placeholder = self?.text("Например, Искорка", "For example, Sparky")
        })
        alert.addAction(UIAlertAction(title: self.text("Отмена", "Cancel"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: self.text("Сохранить", "Save"), style: .default, handler: { [weak self, weak alert] _ in
            guard let self = self else {
                return
            }
            let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self.look.name = String(name.prefix(24))
            self.saveLook()
            self.reload()
        }))
        self.present(alert, animated: true)
    }

    /// Restores yesterday right here (the same rules and confirmation as on the streak screen).
    @objc private func restorePressed() {
        let context = self.context
        let peerId = self.peerId
        let accountPeerId = context.account.peerId
        guard let state = AstraStreak.cached(accountPeerId: accountPeerId, peerId: peerId), let day = state.restorableDay, state.restoresLeft > 0 else {
            return
        }
        let text = AstraStreak.restoreMessageText(day: day, isRussian: self.isRussian)
        let visibleText = text.trimmingCharacters(in: AstraStreak.invisibleCharacters)
        let alert = UIAlertController(
            title: self.text("Восстановить огонёк?", "Restore the streak?"),
            message: self.text("Вчерашний день засчитается. В чат уйдёт сообщение «\(visibleText)». Останется восстановлений на этой неделе: \(state.restoresLeft - 1).", "Yesterday will count. The message “\(visibleText)” goes to the chat. Restores left this week: \(state.restoresLeft - 1)."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: self.text("Отмена", "Cancel"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: self.text("Восстановить", "Restore"), style: .default, handler: { [weak self] _ in
            AstraMessageStore.forAccount(context.account).addStreakRestore(peerId: peerId, day: day)
            let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])]).startStandalone()
            AstraHaptics.success()
            AstraStreakManager.forAccount(accountPeerId)?.refresh()
            self?.restoreButton.isHidden = true
        }))
        self.present(alert, animated: true)
    }

    @objc private func detailsPressed() {
        let context = self.context
        let peerId = self.peerId
        self.dismiss(animated: true, completion: {
            astraOpenStreak(context: context, peerId: peerId)
        })
    }

    @objc private func closePressed() {
        self.dismiss(animated: true)
    }
}
