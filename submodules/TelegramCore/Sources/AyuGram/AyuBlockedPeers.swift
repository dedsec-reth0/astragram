import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
import MtProtoKit

/// The peers the account has blocked, kept in memory so messages of blocked users can be hidden from chat histories
/// ("Hide messages of blocked users"). The list is fetched while the option is on and refreshed every 10 minutes;
/// blocking and unblocking from this device update it immediately.
enum AyuBlockedPeers {
    private static let peerIds = Atomic<Set<PeerId>>(value: Set())

    static func isBlocked(_ peerId: PeerId) -> Bool {
        return AyuBlockedPeers.peerIds.with { $0.contains(peerId) }
    }

    static func update(peerId: PeerId, isBlocked: Bool) {
        let _ = AyuBlockedPeers.peerIds.modify { current in
            var current = current
            if isBlocked {
                current.insert(peerId)
            } else {
                current.remove(peerId)
            }
            return current
        }
    }

    fileprivate static func set(_ value: Set<PeerId>) {
        let _ = AyuBlockedPeers.peerIds.swap(value)
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
                return AyuBlockedPeers.fetch(network: network, offset: offset + Int32(blocked.count), collected: updated)
            }
            return .single(updated)
        }
    }
}

func managedAyuBlockedPeers(network: Network) -> Signal<Void, NoError> {
    let poll: Signal<Void, NoError> = (AyuBlockedPeers.fetch(network: network, offset: 0, collected: Set())
    |> map { value -> Void in
        if let value = value {
            AyuBlockedPeers.set(value)
        }
    })
    |> then(Signal<Void, NoError>.complete() |> delay(10.0 * 60.0, queue: Queue.concurrentDefaultQueue()))
    |> restart

    return AyuGramSettings.signal
    |> map { $0.hideBlockedUsersMessages }
    |> distinctUntilChanged
    |> mapToSignal { enabled -> Signal<Void, NoError> in
        return enabled ? poll : .complete()
    }
}
