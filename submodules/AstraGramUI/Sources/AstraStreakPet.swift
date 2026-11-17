import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext

// MARK: - The look

/// AstraGram "Серийчик": the little flame that lives in a chat with a streak. It grows with the streak, shows how
/// today goes, and can be dressed up with things unlocked by the best streak reached.
struct AstraStreakPetLook: Codable, Equatable {
    var name: String
    var head: String?
    var face: String?
    var extra: String?
    var best: Int

    static let `default` = AstraStreakPetLook(name: "", head: nil, face: nil, extra: nil, best: 0)
}

enum AstraStreakPetSlot: Int, CaseIterable {
    case head
    case face
    case extra
}

struct AstraStreakPetItem {
    let id: String
    let emoji: String
    let slot: AstraStreakPetSlot
    /// The best streak (in days) that unlocks it.
    let unlockDays: Int
    let titleRu: String
    let titleEn: String
}

enum AstraStreakPetWardrobe {
    static let items: [AstraStreakPetItem] = [
        AstraStreakPetItem(id: "bow", emoji: "🎀", slot: .head, unlockDays: 0, titleRu: "Бантик", titleEn: "Bow"),
        AstraStreakPetItem(id: "cap", emoji: "🧢", slot: .head, unlockDays: 3, titleRu: "Кепка", titleEn: "Cap"),
        AstraStreakPetItem(id: "tophat", emoji: "🎩", slot: .head, unlockDays: 7, titleRu: "Цилиндр", titleEn: "Top Hat"),
        AstraStreakPetItem(id: "grad", emoji: "🎓", slot: .head, unlockDays: 14, titleRu: "Шапка выпускника", titleEn: "Grad Cap"),
        AstraStreakPetItem(id: "crown", emoji: "👑", slot: .head, unlockDays: 30, titleRu: "Корона", titleEn: "Crown"),
        AstraStreakPetItem(id: "glasses", emoji: "👓", slot: .face, unlockDays: 0, titleRu: "Очки", titleEn: "Glasses"),
        AstraStreakPetItem(id: "shades", emoji: "🕶️", slot: .face, unlockDays: 5, titleRu: "Тёмные очки", titleEn: "Shades"),
        AstraStreakPetItem(id: "mask", emoji: "🥽", slot: .face, unlockDays: 21, titleRu: "Маска", titleEn: "Goggles"),
        AstraStreakPetItem(id: "flower", emoji: "🌸", slot: .extra, unlockDays: 0, titleRu: "Цветок", titleEn: "Flower"),
        AstraStreakPetItem(id: "heart", emoji: "💖", slot: .extra, unlockDays: 2, titleRu: "Сердце", titleEn: "Heart"),
        AstraStreakPetItem(id: "star", emoji: "⭐️", slot: .extra, unlockDays: 10, titleRu: "Звезда", titleEn: "Star"),
        AstraStreakPetItem(id: "gem", emoji: "💎", slot: .extra, unlockDays: 50, titleRu: "Кристалл", titleEn: "Gem"),
        AstraStreakPetItem(id: "rainbow", emoji: "🌈", slot: .extra, unlockDays: 100, titleRu: "Радуга", titleEn: "Rainbow")
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

    static func setLook(_ look: AstraStreakPetLook, accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) {
        if let data = try? JSONEncoder().encode(look) {
            UserDefaults.standard.set(data, forKey: AstraStreakPetStore.key(accountPeerId: accountPeerId, peerId: peerId))
        }
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
    let colors: (top: UIColor, bottom: UIColor, inner: UIColor)
    let scale: CGFloat

    static func forDays(_ days: Int) -> AstraStreakPetStage {
        switch days {
        case ..<3:
            return AstraStreakPetStage(index: 0, nameRu: "Искорка", nameEn: "Spark", fromDays: 0, nextDays: 3, colors: (UIColor(rgb: 0xFFD54A), UIColor(rgb: 0xFF8A1F), UIColor(rgb: 0xFFF3B0)), scale: 0.78)
        case ..<7:
            return AstraStreakPetStage(index: 1, nameRu: "Огонёк", nameEn: "Flicker", fromDays: 3, nextDays: 7, colors: (UIColor(rgb: 0xFFC233), UIColor(rgb: 0xFF6A13), UIColor(rgb: 0xFFE89A)), scale: 0.86)
        case ..<30:
            return AstraStreakPetStage(index: 2, nameRu: "Пламя", nameEn: "Flame", fromDays: 7, nextDays: 30, colors: (UIColor(rgb: 0xFFA41F), UIColor(rgb: 0xF2380F), UIColor(rgb: 0xFFD27A)), scale: 0.94)
        case ..<100:
            return AstraStreakPetStage(index: 3, nameRu: "Костёр", nameEn: "Blaze", fromDays: 30, nextDays: 100, colors: (UIColor(rgb: 0xFF7AB6), UIColor(rgb: 0xE0245E), UIColor(rgb: 0xFFC4DD)), scale: 1.0)
        default:
            return AstraStreakPetStage(index: 4, nameRu: "Звезда", nameEn: "Star", fromDays: 100, nextDays: nil, colors: (UIColor(rgb: 0x7FE3FF), UIColor(rgb: 0x6A4DFF), UIColor(rgb: 0xD9F6FF)), scale: 1.0)
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

/// The flame creature, drawn and animated with Core Animation: it breathes, sways, blinks and wears its things.
final class AstraStreakPetView: UIView {
    private let bodyContainer = UIView()
    private let glowLayer = CAShapeLayer()
    private let bodyGradient = CAGradientLayer()
    private let bodyMask = CAShapeLayer()
    private let innerLayer = CAShapeLayer()
    private let leftEye = CAShapeLayer()
    private let rightEye = CAShapeLayer()
    private let leftPupil = CAShapeLayer()
    private let rightPupil = CAShapeLayer()
    private let eyesLayer = CALayer()
    private let mouthLayer = CAShapeLayer()
    private let cheeksLayer = CAShapeLayer()
    private let tearLayer = CAShapeLayer()
    private let headLabel = UILabel()
    private let faceLabel = UILabel()
    private let extraLabel = UILabel()

    private var stage = AstraStreakPetStage.forDays(0)
    private var mood: AstraStreakPetMood = .waiting
    private var look = AstraStreakPetLook.default

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.addSubview(self.bodyContainer)
        self.bodyContainer.layer.addSublayer(self.glowLayer)
        self.bodyGradient.mask = self.bodyMask
        self.bodyContainer.layer.addSublayer(self.bodyGradient)
        self.bodyContainer.layer.addSublayer(self.innerLayer)
        self.bodyContainer.layer.addSublayer(self.cheeksLayer)
        self.eyesLayer.addSublayer(self.leftEye)
        self.eyesLayer.addSublayer(self.rightEye)
        self.eyesLayer.addSublayer(self.leftPupil)
        self.eyesLayer.addSublayer(self.rightPupil)
        self.bodyContainer.layer.addSublayer(self.eyesLayer)
        self.bodyContainer.layer.addSublayer(self.mouthLayer)
        self.bodyContainer.layer.addSublayer(self.tearLayer)
        for label in [self.extraLabel, self.faceLabel, self.headLabel] {
            label.textAlignment = .center
            self.bodyContainer.addSubview(label)
        }
        self.leftEye.fillColor = UIColor.white.cgColor
        self.rightEye.fillColor = UIColor.white.cgColor
        self.leftPupil.fillColor = UIColor(rgb: 0x2A1A12).cgColor
        self.rightPupil.fillColor = UIColor(rgb: 0x2A1A12).cgColor
        self.mouthLayer.fillColor = UIColor.clear.cgColor
        self.mouthLayer.strokeColor = UIColor(rgb: 0x5A2412).cgColor
        self.mouthLayer.lineCap = .round
        self.cheeksLayer.fillColor = UIColor(rgb: 0xFF5E7A).withAlphaComponent(0.45).cgColor
        self.tearLayer.fillColor = UIColor(rgb: 0x7CCBFF).cgColor
        self.glowLayer.fillColor = UIColor.clear.cgColor
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

    /// The flame outline in a 30 x 30 box (the same shape as the Streak icon), y down.
    private static func flamePath(in rect: CGRect) -> UIBezierPath {
        let sx = rect.width / 30.0
        let sy = rect.height / 30.0
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: rect.minX + x * sx, y: rect.minY + (30.0 - y) * sy)
        }
        let path = UIBezierPath()
        path.move(to: p(15, 29.4))
        path.addCurve(to: p(10.6, 20.4), controlPoint1: p(15.6, 25.6), controlPoint2: p(13.2, 23.0))
        path.addCurve(to: p(5.2, 11.0), controlPoint1: p(8.0, 17.8), controlPoint2: p(5.2, 15.0))
        path.addCurve(to: p(15, 1.2), controlPoint1: p(5.2, 5.4), controlPoint2: p(9.6, 1.2))
        path.addCurve(to: p(24.8, 10.6), controlPoint1: p(20.4, 1.2), controlPoint2: p(24.8, 5.2))
        path.addCurve(to: p(20.6, 19.4), controlPoint1: p(24.8, 14.2), controlPoint2: p(23.0, 17.2))
        path.addCurve(to: p(18.4, 15.2), controlPoint1: p(20.6, 17.6), controlPoint2: p(19.8, 16.2))
        path.addCurve(to: p(15, 29.4), controlPoint1: p(19.0, 19.8), controlPoint2: p(17.6, 24.0))
        path.close()
        return path
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(self.bounds.width, self.bounds.height)
        let size = side * self.stage.scale
        self.bodyContainer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: side, height: side))
        self.bodyContainer.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        let bodyRect = CGRect(x: (side - size) / 2.0, y: side - size, width: size, height: size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let flame = AstraStreakPetView.flamePath(in: bodyRect)
        self.glowLayer.frame = self.bodyContainer.bounds
        self.glowLayer.path = flame.cgPath
        self.glowLayer.shadowPath = flame.cgPath
        self.glowLayer.shadowColor = self.stage.colors.bottom.cgColor
        self.glowLayer.shadowOpacity = 0.75
        self.glowLayer.shadowRadius = size * 0.12
        self.glowLayer.shadowOffset = CGSize()

        self.bodyGradient.frame = self.bodyContainer.bounds
        self.bodyGradient.colors = [self.stage.colors.top.cgColor, self.stage.colors.bottom.cgColor]
        self.bodyGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.bodyGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.bodyMask.frame = self.bodyContainer.bounds
        self.bodyMask.path = flame.cgPath

        // A lighter belly.
        let innerRect = CGRect(x: bodyRect.minX + size * 0.3, y: bodyRect.minY + size * 0.5, width: size * 0.4, height: size * 0.42)
        self.innerLayer.frame = self.bodyContainer.bounds
        self.innerLayer.path = UIBezierPath(ovalIn: innerRect).cgPath
        self.innerLayer.fillColor = self.stage.colors.inner.withAlphaComponent(0.55).cgColor

        // The face.
        let eyeY = bodyRect.minY + size * 0.56
        let eyeSize = CGSize(width: size * 0.15, height: size * 0.19)
        let leftEyeRect = CGRect(x: bodyRect.midX - size * 0.17 - eyeSize.width / 2.0, y: eyeY - eyeSize.height / 2.0, width: eyeSize.width, height: eyeSize.height)
        let rightEyeRect = CGRect(x: bodyRect.midX + size * 0.17 - eyeSize.width / 2.0, y: eyeY - eyeSize.height / 2.0, width: eyeSize.width, height: eyeSize.height)
        self.eyesLayer.frame = self.bodyContainer.bounds
        self.eyesLayer.anchorPoint = CGPoint(x: 0.5, y: eyeY / max(1.0, side))
        self.eyesLayer.position = CGPoint(x: side / 2.0, y: eyeY)
        self.leftEye.path = UIBezierPath(ovalIn: leftEyeRect).cgPath
        self.rightEye.path = UIBezierPath(ovalIn: rightEyeRect).cgPath
        let pupilSize = eyeSize.width * 0.58
        let pupilOffsetY: CGFloat = self.mood == .sad ? eyeSize.height * 0.12 : 0.0
        self.leftPupil.path = UIBezierPath(ovalIn: CGRect(x: leftEyeRect.midX - pupilSize / 2.0 + eyeSize.width * 0.08, y: leftEyeRect.midY - pupilSize / 2.0 + pupilOffsetY, width: pupilSize, height: pupilSize)).cgPath
        self.rightPupil.path = UIBezierPath(ovalIn: CGRect(x: rightEyeRect.midX - pupilSize / 2.0 + eyeSize.width * 0.08, y: rightEyeRect.midY - pupilSize / 2.0 + pupilOffsetY, width: pupilSize, height: pupilSize)).cgPath
        self.eyesLayer.transform = self.mood == .sleepy ? CATransform3DMakeScale(1.0, 0.3, 1.0) : CATransform3DIdentity

        let cheekSize = size * 0.09
        let cheeks = UIBezierPath(ovalIn: CGRect(x: leftEyeRect.minX - cheekSize * 0.6, y: eyeY + eyeSize.height * 0.55, width: cheekSize * 1.3, height: cheekSize * 0.8))
        cheeks.append(UIBezierPath(ovalIn: CGRect(x: rightEyeRect.maxX - cheekSize * 0.7, y: eyeY + eyeSize.height * 0.55, width: cheekSize * 1.3, height: cheekSize * 0.8)))
        self.cheeksLayer.frame = self.bodyContainer.bounds
        self.cheeksLayer.path = cheeks.cgPath
        self.cheeksLayer.isHidden = self.mood == .sad || self.mood == .sleepy

        let mouthY = eyeY + size * 0.17
        let mouthWidth = size * 0.16
        let mouth = UIBezierPath()
        switch self.mood {
        case .happy:
            mouth.move(to: CGPoint(x: bodyRect.midX - mouthWidth / 2.0, y: mouthY))
            mouth.addQuadCurve(to: CGPoint(x: bodyRect.midX + mouthWidth / 2.0, y: mouthY), controlPoint: CGPoint(x: bodyRect.midX, y: mouthY + size * 0.1))
        case .waiting, .sleepy:
            mouth.move(to: CGPoint(x: bodyRect.midX - mouthWidth * 0.3, y: mouthY + size * 0.02))
            mouth.addQuadCurve(to: CGPoint(x: bodyRect.midX + mouthWidth * 0.3, y: mouthY + size * 0.02), controlPoint: CGPoint(x: bodyRect.midX, y: mouthY + size * 0.04))
        case .sad:
            mouth.move(to: CGPoint(x: bodyRect.midX - mouthWidth * 0.4, y: mouthY + size * 0.05))
            mouth.addQuadCurve(to: CGPoint(x: bodyRect.midX + mouthWidth * 0.4, y: mouthY + size * 0.05), controlPoint: CGPoint(x: bodyRect.midX, y: mouthY - size * 0.03))
        }
        self.mouthLayer.frame = self.bodyContainer.bounds
        self.mouthLayer.path = mouth.cgPath
        self.mouthLayer.lineWidth = max(1.2, size * 0.035)

        let tearRect = CGRect(x: rightEyeRect.midX - size * 0.03, y: rightEyeRect.maxY + size * 0.01, width: size * 0.06, height: size * 0.09)
        self.tearLayer.frame = self.bodyContainer.bounds
        self.tearLayer.path = UIBezierPath(ovalIn: tearRect).cgPath
        self.tearLayer.isHidden = self.mood != .sad

        CATransaction.commit()

        // The things it wears.
        let head = AstraStreakPetWardrobe.item(self.look.head)
        let face = AstraStreakPetWardrobe.item(self.look.face)
        let extra = AstraStreakPetWardrobe.item(self.look.extra)
        self.headLabel.text = head?.emoji
        self.headLabel.font = UIFont.systemFont(ofSize: size * 0.36)
        self.headLabel.sizeToFit()
        self.headLabel.center = CGPoint(x: bodyRect.midX + size * 0.04, y: bodyRect.minY + size * 0.24)
        self.faceLabel.text = face?.emoji
        self.faceLabel.font = UIFont.systemFont(ofSize: size * 0.34)
        self.faceLabel.sizeToFit()
        self.faceLabel.center = CGPoint(x: bodyRect.midX, y: eyeY + size * 0.01)
        self.eyesLayer.isHidden = face != nil
        self.extraLabel.text = extra?.emoji
        self.extraLabel.font = UIFont.systemFont(ofSize: size * 0.24)
        self.extraLabel.sizeToFit()
        self.extraLabel.center = CGPoint(x: bodyRect.maxX - size * 0.08, y: bodyRect.maxY - size * 0.2)
    }

    private func startAnimations() {
        let layer = self.bodyContainer.layer
        if layer.animation(forKey: "astraBreath") == nil {
            let breath = CABasicAnimation(keyPath: "transform.scale.y")
            breath.fromValue = 0.96
            breath.toValue = 1.05
            breath.duration = 1.1
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(breath, forKey: "astraBreath")

            let sway = CABasicAnimation(keyPath: "transform.rotation.z")
            sway.fromValue = -0.05
            sway.toValue = 0.05
            sway.duration = 1.7
            sway.autoreverses = true
            sway.repeatCount = .infinity
            sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(sway, forKey: "astraSway")

            let flicker = CAKeyframeAnimation(keyPath: "shadowOpacity")
            flicker.values = [0.55, 0.9, 0.6, 0.85, 0.55]
            flicker.duration = 1.3
            flicker.repeatCount = .infinity
            self.glowLayer.add(flicker, forKey: "astraFlicker")
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
        self.disposable = (combineLatest(queue: .mainQueue(), AstraMessageStore.forAccount(context.account).streaks(), states)
        |> deliverOnMainQueue).start(next: { [weak self] streaks, states in
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
            view = AstraStreakPetFloatingView(frame: CGRect(x: 0.0, y: 0.0, width: 64.0, height: 80.0))
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
        }
        hostView.bringSubviewToFront(view)
        view.update(days: days, mood: AstraStreakPetMood.of(state), look: look)
    }

    private func hide() {
        self.floatingView?.removeFromSuperview()
        self.floatingView = nil
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
        self.isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.lowercased().hasPrefix("ru")
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

        let close = UIButton(type: .system)
        close.setTitle("✕", for: .normal)
        close.titleLabel?.font = UIFont.systemFont(ofSize: 20.0, weight: .semibold)
        close.tintColor = .white
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
            close.widthAnchor.constraint(equalToConstant: 40.0),
            close.heightAnchor.constraint(equalToConstant: 40.0),
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
        self.restoreButton.addTarget(self, action: #selector(self.detailsPressed), for: .touchUpInside)
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
        self.subtitleLabel.text = self.text("дней подряд с \(self.peerName)", "days in a row with \(self.peerName)") + "\n" + moodText

        if let next = stage.nextDays {
            let nextStage = AstraStreakPetStage.forDays(next)
            self.stageLabel.text = self.text("Стадия: \(stage.nameRu). До «\(nextStage.nameRu)» ещё \(max(0, next - days)) дн.", "Stage: \(stage.nameEn). \(max(0, next - days)) days to \(nextStage.nameEn)")
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
            case .extra:
                title.text = self.text("Украшение", "Extra")
            }
            title.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
            title.textColor = UIColor(white: 1.0, alpha: 0.6)
            self.wardrobeStack.addArrangedSubview(title)

            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8.0
            row.distribution = .fillEqually
            let current: String?
            switch slot {
            case .head:
                current = self.look.head
            case .face:
                current = self.look.face
            case .extra:
                current = self.look.extra
            }
            row.addArrangedSubview(self.wardrobeButton(emoji: "∅", caption: self.text("Нет", "None"), selected: current == nil, locked: false, tag: slot.rawValue * 100 + 99))
            for (index, item) in AstraStreakPetWardrobe.items.enumerated() where item.slot == slot {
                let locked = self.look.best < item.unlockDays
                row.addArrangedSubview(self.wardrobeButton(emoji: item.emoji, caption: locked ? "🔒 \(item.unlockDays)" : (self.isRussian ? item.titleRu : item.titleEn), selected: current == item.id, locked: locked, tag: slot.rawValue * 100 + index))
            }
            self.wardrobeStack.addArrangedSubview(row)
        }
    }

    private func wardrobeButton(emoji: String, caption: String, selected: Bool, locked: Bool, tag: Int) -> UIView {
        let button = UIButton(type: .custom)
        button.tag = tag
        button.backgroundColor = selected ? UIColor(rgb: 0xFF8A1F).withAlphaComponent(0.35) : UIColor(white: 1.0, alpha: 0.06)
        button.layer.cornerRadius = 12.0
        button.layer.borderWidth = selected ? 1.5 : 0.0
        button.layer.borderColor = UIColor(rgb: 0xFFB13D).cgColor
        button.alpha = locked ? 0.4 : 1.0
        button.addTarget(self, action: #selector(self.wardrobePressed(_:)), for: .touchUpInside)
        let emojiLabel = UILabel()
        emojiLabel.text = emoji
        emojiLabel.font = UIFont.systemFont(ofSize: 24.0)
        emojiLabel.textAlignment = .center
        emojiLabel.textColor = .white
        let captionLabel = UILabel()
        captionLabel.text = caption
        captionLabel.font = UIFont.systemFont(ofSize: 9.0, weight: .medium)
        captionLabel.textColor = UIColor(white: 1.0, alpha: 0.75)
        captionLabel.textAlignment = .center
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.7
        let stack = UIStackView(arrangedSubviews: [emojiLabel, captionLabel])
        stack.axis = .vertical
        stack.spacing = 2.0
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: button.leadingAnchor, constant: 2.0),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -2.0),
            button.heightAnchor.constraint(equalToConstant: 58.0)
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
                let alert = UIAlertController(title: item.emoji, message: self.text("Откроется, когда огонёк дойдёт до \(item.unlockDays) дн.", "Unlocks when the streak reaches \(item.unlockDays) days."), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(alert, animated: true)
                return
            }
            id = item.id
        }
        switch slot {
        case .head:
            self.look.head = id
        case .face:
            self.look.face = id
        case .extra:
            self.look.extra = id
        }
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
