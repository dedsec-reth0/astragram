import Foundation
internal import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer


private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    
    private var wasOnline: Bool = false

    // AstraGram ghost mode: see `astraMarkAsOnline`.
    private var astraMarkDisposable: Disposable?
    private var astraOwnPresenceDisposable: Disposable?
    private var astraSettingsDisposable: Disposable?
    private var astraOfflineTimer: SignalKitTimer?
    private var astraLastImmediateOffline: Double = 0.0
    private var astraLastOwnPresenceMark: Double = 0.0

    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, astraOwnPresenceOnline: Signal<Void, NoError>, network: Network) {
        self.queue = queue
        self.network = network
        
        // AstraGram ghost mode: with "hide online status" on, the account is always reported offline (turning it on
        // while online sends `updateStatus(offline: true)` at once).
        let effectiveShouldKeepOnlinePresence = combineLatest(
            shouldKeepOnlinePresence,
            AstraGramSettings.signal
            |> map { settings -> Bool in
                return settings.hideOnlineStatus
            }
            |> distinctUntilChanged
        )
        |> map { shouldKeepOnline, hideOnline -> Bool in
            return shouldKeepOnline && !hideOnline
        }
        self.shouldKeepOnlinePresenceDisposable = (effectiveShouldKeepOnlinePresence
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            if self.wasOnline != value {
                self.wasOnline = value
                self.updatePresence(value)
            }
        })

        self.astraMarkDisposable = (AstraGhostMode.markedAsOnline()
        |> deliverOn(self.queue)).start(next: { [weak self] _ in
            self?.astraMarkAsOnline()
        })
        self.astraOwnPresenceDisposable = (astraOwnPresenceOnline
        |> deliverOn(self.queue)).start(next: { [weak self] _ in
            guard let self else {
                return
            }
            // Never more often: an answer to the server's report must not be able to turn into a loop.
            let now = CFAbsoluteTimeGetCurrent()
            if now - self.astraLastOwnPresenceMark < 10.0 {
                return
            }
            self.astraLastOwnPresenceMark = now
            self.astraMarkAsOnline()
        })
        // At launch with the online status hidden, and whenever hiding it is turned on.
        self.astraSettingsDisposable = (AstraGramSettings.signal
        |> map { settings -> Bool in
            return settings.hideOnlineStatus
        }
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] hideOnline in
            if hideOnline {
                self?.astraMarkAsOnline()
            }
        })
    }

    /// AstraGram ghost mode, as AyuGram's worker does it: the server has just shown the account online (a message was
    /// sent, a chat was read, another device came online), so it is told the account is offline: at once, and again
    /// 3 seconds after the last such event, when everything the event caused has reached the server. A request that
    /// shows the account online marks twice, as it goes out and when it is done, and both answers go out: the first
    /// right behind the request, the second once the server has applied it.
    private func astraMarkAsOnline() {
        guard AstraGramSettings.current.hideOnlineStatus else {
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        if now - self.astraLastImmediateOffline >= 0.25 {
            self.astraLastImmediateOffline = now
            self.astraSendOffline()
        }
        self.astraOfflineTimer?.invalidate()
        let timer = SignalKitTimer(timeout: 3.0, repeat: false, completion: { [weak self] in
            guard let self else {
                return
            }
            self.astraOfflineTimer = nil
            self.astraSendOffline()
        }, queue: self.queue)
        self.astraOfflineTimer = timer
        timer.start()
    }

    private func astraSendOffline() {
        guard AstraGramSettings.current.hideOnlineStatus else {
            return
        }
        // Not cancelled by the next one: each "offline" is answering its own event and must reach the server.
        let _ = (self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }).start()
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.onlineTimer?.invalidate()
        self.astraMarkDisposable?.dispose()
        self.astraOwnPresenceDisposable?.dispose()
        self.astraSettingsDisposable?.dispose()
        self.astraOfflineTimer?.invalidate()
    }
    
    private func updatePresence(_ isOnline: Bool) {
        let request: Signal<Api.Bool, MTRpcError>
        if isOnline {
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, astraOwnPresenceOnline: Signal<Void, NoError>, network: Network) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, astraOwnPresenceOnline: astraOwnPresenceOnline, network: network)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
