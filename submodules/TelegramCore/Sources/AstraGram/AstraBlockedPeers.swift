import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
import MtProtoKit

/// The peers the account has blocked, kept in memory so messages of blocked users can be hidden from chat histories
/// ("Hide messages of blocked users"). The list is fetched while the option is on and refreshed every 10 minutes;
/// blocking and unblocking from this device update it immediately.
enum AstraBlockedPeers {
    /// Each account's list, by its network: with several accounts logged in, each poll replaced the one shared list
    /// with its own account's, so the lists of the accounts kept overwriting each other. A message is hidden when its
    /// author is blocked in any of the accounts (a message does not say which account shows it).
    private static let peerIds = Atomic<[ObjectIdentifier: Set<PeerId>]>(value: [:])

    static func isBlocked(_ peerId: PeerId) -> Bool {
        return AstraBlockedPeers.peerIds.with { lists in
            return lists.values.contains(where: { $0.contains(peerId) })
        }
    }

    static func update(peerId: PeerId, isBlocked: Bool) {
        let _ = AstraBlockedPeers.peerIds.modify { current in
            var current = current
            if current.isEmpty {
                return current
            }
            for key in Array(current.keys) {
                if isBlocked {
                    current[key]?.insert(peerId)
                } else {
                    current[key]?.remove(peerId)
                }
            }
            return current
        }
    }

    fileprivate static func set(_ value: Set<PeerId>, network: Network) {
        let id = ObjectIdentifier(network)
        let _ = AstraBlockedPeers.peerIds.modify { current in
            var current = current
            current[id] = value
            return current
        }
    }

    fileprivate static func fetch(network: Network, offset: Int32, collected: Set<PeerId>) -> Signal<Set<PeerId>?, NoError> {
        return network.request(Api.functions.contacts.getBlocked(flags: 0, offset: offset, limit: 100))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.contacts.Blocked?, NoError> in
            return .single(nil)
        }
        |> mapToSignal { result -> Signal<Set<PeerId>?, NoError> in
            guard let result = result else {
                return .single(offset == 0 ? nil : collected)
            }
            let blocked: [Api.PeerBlocked]
            var totalCount: Int?
            switch result {
            case let .blocked(data):
                blocked = data.blocked
            case let .blockedSlice(data):
                blocked = data.blocked
                totalCount = Int(data.count)
            }
            var updated = collected
            for item in blocked {
                switch item {
                case let .peerBlocked(data):
                    updated.insert(data.peerId.peerId)
                }
            }
            if let totalCount = totalCount, !blocked.isEmpty, Int(offset) + blocked.count < totalCount, offset < 10000 {
                return AstraBlockedPeers.fetch(network: network, offset: offset + Int32(blocked.count), collected: updated)
            }
            return .single(updated)
        }
    }
}

func managedAstraBlockedPeers(network: Network) -> Signal<Void, NoError> {
    let poll: Signal<Void, NoError> = (AstraBlockedPeers.fetch(network: network, offset: 0, collected: Set())
    |> map { value -> Void in
        if let value = value {
            AstraBlockedPeers.set(value, network: network)
        }
    })
    |> then(Signal<Void, NoError>.complete() |> delay(10.0 * 60.0, queue: Queue.concurrentDefaultQueue()))
    |> restart

    return AstraGramSettings.signal
    |> map { $0.hideBlockedUsersMessages }
    |> distinctUntilChanged
    |> mapToSignal { enabled -> Signal<Void, NoError> in
        return enabled ? poll : .complete()
    }
}
