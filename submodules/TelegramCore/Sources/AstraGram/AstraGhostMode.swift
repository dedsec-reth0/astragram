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
///
/// Hiding the online status is done the way AyuGram does it. Not sending `updateStatus(offline: false)` is not
/// enough: the server shows the account online by itself after a message is sent, a chat is read, a reaction is set.
/// So everything that does this marks the account as online here (`markAsOnline`), and the presence manager
/// (`ManagedAccountPresence.swift`) answers each mark with `account.updateStatus(offline: true)`.
public enum AstraGhostMode {
    private static let readAllowances = Atomic<Set<PeerId>>(value: Set())

    private static let onlinePipe = ValuePipe<Void>()

    /// Parts of the names of the requests after which the server shows the account online.
    private static let onlineRequestParts: [String] = [
        "messages.send", "messages.forward", "messages.read", "channels.read", "messages.startBot",
        "messages.setTyping", "messages.setEncryptedTyping", "messages.editMessage", "messages.deleteMessages",
        "channels.deleteMessages", "messages.getBotCallbackAnswer", "stories.send", "stories.readStories",
        "stories.incrementStoryViews"
    ]

    /// Whether the server shows the account online once the request named `name` is done.
    static func requestMarksOnline(_ name: String) -> Bool {
        let name = name.replacingOccurrences(of: "_", with: ".")
        if name.contains("updateStatus") {
            return false
        }
        for part in AstraGhostMode.onlineRequestParts {
            if name.contains(part) {
                return true
            }
        }
        return false
    }

    /// Something has just made the server show the account online. With the online status hidden, the presence
    /// manager of every account answers with `account.updateStatus(offline: true)`.
    public static func markAsOnline() {
        if !AstraGramSettings.current.hideOnlineStatus {
            return
        }
        AstraGhostMode.onlinePipe.putNext(Void())
    }

    static func markedAsOnline() -> Signal<Void, NoError> {
        return AstraGhostMode.onlinePipe.signal()
    }

    /// Fires when the server reports the account itself as online, whatever caused it (this device or another).
    static func ownPresenceOnline(postbox: Postbox, network: Network, accountPeerId: PeerId) -> Signal<Void, NoError> {
        return postbox.peerView(id: accountPeerId)
        |> map { view -> Int32 in
            if let presence = view.peerPresences[accountPeerId] as? TelegramUserPresence, case let .present(until) = presence.status {
                return until
            }
            return 0
        }
        |> distinctUntilChanged
        |> filter { [weak network] until -> Bool in
            guard let network = network else {
                return false
            }
            // "Was online at" is stored the same way, with a time that has passed.
            return until > Int32(network.globalTime) + 2
        }
        |> map { _ -> Void in
            return Void()
        }
    }

    /// Whether a read receipt for `peerId` may be sent now. Consumes a one-time allowance granted by sending a
    /// message ("mark read after send").
    static func mayPushReadState(peerId: PeerId) -> Bool {
        if !AstraGramSettings.current.hideReadReceipts {
            return true
        }
        var allowed = false
        let _ = AstraGhostMode.readAllowances.modify { current in
            var current = current
            if current.remove(peerId) != nil {
                allowed = true
            }
            return current
        }
        return allowed
    }

    /// The read states fetched from the server (chat list hole fill, account reset) with the local incoming read
    /// mark kept wherever it is ahead of the server's: while read receipts are hidden the server stays behind, and
    /// applying its state would make chats read in ghost mode unread again.
    static func keepingLocalReadMarks(transaction: Transaction, _ readStates: [PeerId: [MessageId.Namespace: PeerReadState]]) -> [PeerId: [MessageId.Namespace: PeerReadState]] {
        if !AstraGramSettings.current.hideReadReceipts {
            return readStates
        }
        var result = readStates
        for (peerId, states) in readStates {
            guard case let .idBased(serverMaxIncomingReadId, maxOutgoingReadId, maxKnownId, serverCount, serverMarkedUnread)? = states[Namespaces.Message.Cloud] else {
                continue
            }
            guard let currentReadState = transaction.getCombinedPeerReadState(peerId) else {
                continue
            }
            for (namespace, currentState) in currentReadState.states where namespace == Namespaces.Message.Cloud {
                if case let .idBased(localMaxIncomingReadId, _, _, localCount, localMarkedUnread) = currentState, localReadMarkIsAheadOfServer(localMaxIncomingReadId: localMaxIncomingReadId, serverMaxIncomingReadId: serverMaxIncomingReadId, serverCount: serverCount, serverMarkedUnread: serverMarkedUnread) {
                    var updatedStates = states
                    updatedStates[Namespaces.Message.Cloud] = .idBased(maxIncomingReadId: localMaxIncomingReadId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: maxKnownId, count: localCount, markedUnread: localMarkedUnread)
                    result[peerId] = updatedStates
                }
            }
        }
        return result
    }

    /// Called when the user sends a message: with "mark read after send" on, the chat's read state is pushed once.
    /// Not for a message sent via schedule while the online status is hidden: reading a chat shows the account online,
    /// which is what sending via schedule avoids.
    static func didSendMessage(account: Account, peerId: PeerId, scheduled: Bool) {
        let settings = AstraGramSettings.current
        guard settings.hideReadReceipts && settings.markReadAfterSend else {
            return
        }
        if scheduled && settings.hideOnlineStatus {
            return
        }
        AstraGhostMode.pushReadStateOnce(account: account, peerId: peerId)
    }

    /// Called when the user reacts to a message or votes in a poll: with "mark read after reaction" on, the chat's
    /// read state is pushed once.
    static func didInteract(account: Account, peerId: PeerId) {
        let settings = AstraGramSettings.current
        guard settings.hideReadReceipts && settings.markReadAfterReaction else {
            return
        }
        AstraGhostMode.pushReadStateOnce(account: account, peerId: peerId)
    }

    static func pushReadStateOnce(account: Account, peerId: PeerId) {
        guard peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup || peerId.namespace == Namespaces.Peer.CloudChannel else {
            return
        }
        guard let stateManager = account.stateManager else {
            return
        }
        let _ = AstraGhostMode.readAllowances.modify { current in
            var current = current
            current.insert(peerId)
            return current
        }
        let _ = (synchronizePeerReadState(network: account.network, postbox: account.postbox, stateManager: stateManager, peerId: peerId, push: true, validate: false)
        |> `catch` { _ -> Signal<Never, NoError> in
            return .complete()
        }).start(completed: {
            // The allowance is for this push only: when the push did not happen (no read state to push), it must not
            // let a later read through.
            let _ = AstraGhostMode.readAllowances.modify { current in
                var current = current
                current.remove(peerId)
                return current
            }
        })
    }
}
