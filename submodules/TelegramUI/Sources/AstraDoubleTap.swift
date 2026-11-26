import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import UndoUI
import AstraGramUI

extension ChatControllerImpl {
    /// AstraGram: a double tap on a message does what Settings → AstraGram → Chats chose instead of the quick reaction
    /// (`AstraGramSettingsValues.doubleTapAction`). Returns false when the quick reaction should be sent as usual.
    func astraHandleDoubleTap(message: EngineRawMessage) -> Bool {
        let action = AstraGramSettings.current.doubleTapAction
        if action == 0 {
            return false
        }
        let strings = AstraStrings(self.presentationData.strings)
        let canEdit = !message.flags.contains(.Incoming) && canEditMessage(context: self.context, limitsConfiguration: self.context.currentLimitsConfiguration.with { EngineConfiguration.Limits($0) }, message: message)
        switch action {
        case 1, 5:
            if action == 5 && canEdit {
                self.interfaceInteraction?.setupEditMessage(message.id, { _ in })
            } else if self.presentationInterfaceState.interfaceState.editMessage == nil {
                self.interfaceInteraction?.setupReplyMessage(message.id, nil, { _, f in f() })
            }
        case 2:
            guard !message.text.isEmpty, !(self.presentationInterfaceState.copyProtectionEnabled || message.isCopyProtected()) else {
                return true
            }
            UIPasteboard.general.string = message.text
            self.controllerInteraction?.displayUndo(.copy(text: strings.copied))
        case 3:
            self.forwardMessages(messageIds: [message.id])
        case 4:
            let _ = enqueueMessages(account: self.context.account, peerId: self.context.account.peerId, messages: [
                .forward(source: message.id, threadId: nil, grouping: .auto, attributes: [], correlationId: nil)
            ]).startStandalone()
            self.controllerInteraction?.displayUndo(.info(title: nil, text: strings.savedToSavedMessages, timeout: 2.0, customUndoText: nil))
        default:
            break
        }
        return true
    }
}
