import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import UndoUI

/// AstraGram: a bug report or an idea, sent to the developer from the app (through the streak bot's server, which
/// forwards it to the developer in Telegram). The sender's account goes along only when they allow it.
final class AstraFeedbackController: UIViewController, UITextViewDelegate {
    private let context: AccountContext
    private let presentationData: PresentationData
    private let isRussian: Bool
    private let kindControl: UISegmentedControl
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let includeAccount = UISwitch()
    private let includeLabel = UILabel()
    private let noteLabel = UILabel()
    private var isSending = false

    init(context: AccountContext, idea: Bool) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.isRussian = self.presentationData.strings.baseLanguageCode.astraUsesRussianTexts
        self.kindControl = UISegmentedControl(items: self.isRussian ? ["🐞 Ошибка", "💡 Идея"] : ["🐞 Bug", "💡 Idea"])
        self.kindControl.selectedSegmentIndex = idea ? 1 : 0
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func text(_ ru: String, _ en: String) -> String {
        return self.isRussian ? ru : en
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let theme = self.presentationData.theme
        self.view.backgroundColor = theme.list.blocksBackgroundColor
        self.title = self.text("Ошибки и идеи", "Bugs and Ideas")
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: self.text("Отмена", "Cancel"), style: .plain, target: self, action: #selector(self.cancelPressed))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.text("Отправить", "Send"), style: .done, target: self, action: #selector(self.sendPressed))
        self.navigationItem.rightBarButtonItem?.isEnabled = false

        self.kindControl.addTarget(self, action: #selector(self.kindChanged), for: .valueChanged)

        self.textView.font = UIFont.systemFont(ofSize: 17.0)
        self.textView.textColor = theme.list.itemPrimaryTextColor
        self.textView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.textView.layer.cornerRadius = 12.0
        self.textView.textContainerInset = UIEdgeInsets(top: 12.0, left: 8.0, bottom: 12.0, right: 8.0)
        self.textView.delegate = self

        self.placeholder.font = UIFont.systemFont(ofSize: 17.0)
        self.placeholder.textColor = theme.list.itemPlaceholderTextColor
        self.placeholder.numberOfLines = 0

        self.includeLabel.text = self.text("Указать мой аккаунт, чтобы мне ответили", "Include my account so I can get a reply")
        self.includeLabel.font = UIFont.systemFont(ofSize: 15.0)
        self.includeLabel.textColor = theme.list.itemPrimaryTextColor
        self.includeLabel.numberOfLines = 0
        self.includeAccount.isOn = true

        self.noteLabel.font = UIFont.systemFont(ofSize: 13.0)
        self.noteLabel.textColor = theme.list.freeTextColor
        self.noteLabel.numberOfLines = 0
        self.noteLabel.text = self.text(
            "Вместе с текстом уйдут версия AstraGram, модель iPhone и версия iOS — так ошибку легче найти. Переписка и номер телефона не отправляются. С аккаунтом разработчик сможет ответить вам в боте @\(AstraStreakBot.username).",
            "Along with the text go the AstraGram version, the iPhone model and the iOS version, so the bug is easier to find. No chats and no phone number are sent. With your account the developer can reply to you in @\(AstraStreakBot.username)."
        )

        let switchRow = UIStackView(arrangedSubviews: [self.includeLabel, self.includeAccount])
        switchRow.axis = .horizontal
        switchRow.alignment = .center
        switchRow.spacing = 12.0

        let stack = UIStackView(arrangedSubviews: [self.kindControl, self.textView, switchRow, self.noteLabel])
        stack.axis = .vertical
        stack.spacing = 14.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)
        self.placeholder.translatesAutoresizingMaskIntoConstraints = false
        self.textView.addSubview(self.placeholder)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 16.0),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16.0),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0),
            self.textView.heightAnchor.constraint(equalToConstant: 200.0),
            self.placeholder.topAnchor.constraint(equalTo: self.textView.topAnchor, constant: 12.0),
            self.placeholder.leadingAnchor.constraint(equalTo: self.textView.leadingAnchor, constant: 13.0),
            self.placeholder.widthAnchor.constraint(equalTo: self.textView.widthAnchor, constant: -26.0)
        ])
        self.kindChanged()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.textView.becomeFirstResponder()
    }

    @objc private func kindChanged() {
        self.placeholder.text = self.kindControl.selectedSegmentIndex == 1
            ? self.text("Что добавить или улучшить в AstraGram?", "What should AstraGram add or improve?")
            : self.text("Что случилось? Что вы делали перед этим и что ожидали увидеть?", "What happened? What did you do before, and what did you expect?")
    }

    func textViewDidChange(_ textView: UITextView) {
        self.placeholder.isHidden = !textView.text.isEmpty
        self.navigationItem.rightBarButtonItem?.isEnabled = textView.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && !self.isSending
    }

    @objc private func cancelPressed() {
        self.dismiss(animated: true)
    }

    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine
    }

    @objc private func sendPressed() {
        let text = self.textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3, !self.isSending else {
            return
        }
        self.isSending = true
        self.navigationItem.rightBarButtonItem?.isEnabled = false
        let context = self.context
        let isRussian = self.isRussian
        let includeAccount = self.includeAccount.isOn
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let buildNumber = Int(build) ?? 0
        var body: [String: Any] = [
            "kind": self.kindControl.selectedSegmentIndex == 1 ? "idea" : "bug",
            "text": text,
            "version": "AstraGram " + (buildNumber > 103783 ? "1.0.\(buildNumber - 103783)" : "1.0.0"),
            "build": build,
            "os": "iOS " + UIDevice.current.systemVersion,
            "device": AstraFeedbackController.deviceModel()
        ]
        let send = { [weak self] in
            AstraStreakBot.publicRequest(path: "/api/feedback", accountPeerId: includeAccount ? context.account.peerId : nil, body: body, completion: { object, status in
                Queue.mainQueue().async {
                    let message: String
                    if object != nil {
                        message = isRussian ? "Спасибо! Сообщение отправлено разработчику" : "Thank you! The message reached the developer"
                        self?.dismiss(animated: true)
                    } else if status == 429 {
                        message = isRussian ? "Слишком много сообщений за час. Попробуйте позже" : "Too many messages this hour. Try again later"
                    } else {
                        message = isRussian ? "Не отправилось. Проверьте интернет и попробуйте ещё раз" : "Not sent. Check the connection and try again"
                    }
                    if let self, object == nil {
                        self.isSending = false
                        self.textViewDidChange(self.textView)
                    }
                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                    context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: message, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), on: .root, blockInteraction: false, completion: {})
                }
            })
        }
        guard includeAccount else {
            send()
            return
        }
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
        |> deliverOnMainQueue).start(next: { peer in
            body["userId"] = NSNumber(value: context.account.peerId.id._internalGetInt64Value())
            if let peer {
                body["name"] = peer.compactDisplayTitle
                if let username = peer.addressName {
                    body["username"] = username
                }
            }
            send()
        })
    }
}

public func astraOpenFeedback(context: AccountContext, idea: Bool) {
    guard let top = astraTopViewController() else {
        return
    }
    let navigation = UINavigationController(rootViewController: AstraFeedbackController(context: context, idea: idea))
    navigation.modalPresentationStyle = .pageSheet
    top.present(navigation, animated: true)
}

/// AstraGram: a donation in Telegram Stars. The streak bot's server makes an invoice link and Telegram's own payment
/// sheet opens over the app; the stars go to the bot's balance.
public func astraOpenDonation(context: AccountContext, navigationController: NavigationController?) {
    guard let top = astraTopViewController() else {
        return
    }
    let isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.astraUsesRussianTexts
    let sheet = UIAlertController(
        title: isRussian ? "Поддержать AstraGram" : "Support AstraGram",
        message: isRussian ? "AstraGram бесплатный и делается в свободное время. Поддержка звёздами Telegram помогает выпускать обновления. Спасибо!" : "AstraGram is free and made in spare time. Support in Telegram Stars helps ship updates. Thank you!",
        preferredStyle: .actionSheet
    )
    for stars in [50, 100, 250, 500, 1000] {
        sheet.addAction(UIAlertAction(title: "\(stars) ⭐", style: .default, handler: { _ in
            astraRequestDonation(context: context, stars: stars, navigationController: navigationController)
        }))
    }
    sheet.addAction(UIAlertAction(title: isRussian ? "Другая сумма" : "Other Amount", style: .default, handler: { _ in
        let input = UIAlertController(title: isRussian ? "Сколько звёзд?" : "How many stars?", message: nil, preferredStyle: .alert)
        input.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "1–10000"
        }
        input.addAction(UIAlertAction(title: isRussian ? "Отмена" : "Cancel", style: .cancel, handler: nil))
        input.addAction(UIAlertAction(title: isRussian ? "Дальше" : "Next", style: .default, handler: { [weak input] _ in
            if let value = Int(input?.textFields?.first?.text ?? ""), value >= 1, value <= 10000 {
                astraRequestDonation(context: context, stars: value, navigationController: navigationController)
            }
        }))
        astraTopViewController()?.present(input, animated: true)
    }))
    sheet.addAction(UIAlertAction(title: isRussian ? "Отмена" : "Cancel", style: .cancel, handler: nil))
    // iOS 26 draws an action sheet with a source as a narrow popover even on an iPhone: a source only on an iPad.
    if UIDevice.current.userInterfaceIdiom == .pad, let popover = sheet.popoverPresentationController {
        popover.sourceView = top.view
        popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1.0, height: 1.0)
    }
    top.present(sheet, animated: true)
}

private func astraRequestDonation(context: AccountContext, stars: Int, navigationController: NavigationController?) {
    let isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.astraUsesRussianTexts
    AstraStreakBot.publicRequest(path: "/api/donate", accountPeerId: nil, body: ["stars": stars, "lang": isRussian ? "ru" : "en"], completion: { object, _ in
        Queue.mainQueue().async {
            guard let link = object?["link"] as? String, link.hasPrefix("https://t.me/") else {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: isRussian ? "Не получилось открыть оплату. Попробуйте позже" : "Couldn't open the payment. Try again later", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), on: .root, blockInteraction: false, completion: {})
                return
            }
            // An invoice link: Telegram opens its own payment sheet for it.
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: link, forceExternal: false, presentationData: presentationData, navigationController: navigationController, dismissInput: {})
        }
    })
}
