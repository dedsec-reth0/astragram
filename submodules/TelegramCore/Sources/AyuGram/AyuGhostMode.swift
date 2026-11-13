import Foundation
import Postbox
import SwiftSignalKit

/// Ghost mode decisions that are not a single settings flag.
///
/// The flags themselves are checked where the requests are made:
/// - online status: `ManagedAccountPresence.swift`
/// - typing and other input activities: `ManagedLocalInputActivities.swift`
/// - read receipts: `SynchronizePeerReadState.swift`, `ApplyMaxReadIndexInteractively.swift`, `ReplyThreadHistory.swift`
/// - listened voice messages and opened media: `ManagedSynchronizeConsumeMessageContentsOperations.swift`,
///   `ManagedConsumePersonalMessagesActions.swift`, `ManagedSynchronizeMarkAllUnseenPersonalMessagesOperations.swift`
/// - stories: `ManagedSynchronizeViewStoriesOperations.swift`, `Stories.swift`
///
/// While read receipts are hidden the chat is still marked read locally; the server keeps it unread, and the read
/// state validation keeps the local mark that is ahead of the server's.
public enum AyuGhostMode {
    private static let readAllowances = Atomic<Set<PeerId>>(value: Set())

    /// Whether a read receipt for `peerId` may be sent now. Consumes a one-time allowance granted by sending a
    /// message ("mark read after send").
    static func mayPushReadState(peerId: PeerId) -> Bool {
        if !AyuGramSettings.current.hideReadReceipts {
            return true
        }
        var allowed = false
        let _ = AyuGhostMode.readAllowances.modify { current in
            var current = current
            if current.remove(peerId) != nil {
                allowed = true
            }
            return current
        }
        return allowed
    }

    /// Called when the user sends a message: with "mark read after send" on, the chat's read state is pushed once.
    static func didSendMessage(account: Account, peerId: PeerId) {
        let settings = AyuGramSettings.current
        guard settings.hideReadReceipts && settings.markReadAfterSend else {
            return
        }
        guard peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup || peerId.namespace == Namespaces.Peer.CloudChannel else {
            return
        }
        guard let stateManager = account.stateManager else {
            return
        }
        let _ = AyuGhostMode.readAllowances.modify { current in
            var current = current
            current.insert(peerId)
            return current
        }
        let _ = (synchronizePeerReadState(network: account.network, postbox: account.postbox, stateManager: stateManager, peerId: peerId, push: true, validate: false)
        |> `catch` { _ -> Signal<Never, NoError> in
            return .complete()
        }).start()
    }
}
