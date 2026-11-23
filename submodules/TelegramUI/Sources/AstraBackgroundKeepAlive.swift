import Foundation
import AVFoundation

/// AstraGram: keeps the app running in the background, so it stays connected and new messages arrive (and are notified)
/// while it is closed. Without push notifications, iOS suspends a backgrounded app within seconds; an app playing audio
/// is not suspended, so this plays silence, mixed with other audio, while the app is in the background.
final class AstraBackgroundKeepAlive {
    private var player: AVAudioPlayer?
    private var interruptionObserver: NSObjectProtocol?
    private var resetObserver: NSObjectProtocol?

    /// Whether keeping alive is wanted now (the app is in the background and nothing else uses the audio session).
    private var isRequested = false

    /// Whether the silence is really playing. Only then does iOS keep the app running: when the audio session could
    /// not be started or is interrupted, the app is suspended as usual and must be treated so.
    var isActive: Bool {
        return self.isRequested && self.player?.isPlaying == true
    }

    /// Called on the main queue when an interruption of the audio session began or ended, or media services were reset, so
    /// `isActive` may have changed.
    var activeUpdated: (() -> Void)?

    init() {
        self.interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main, using: { [weak self] notification in
            guard let self, self.isRequested else {
                return
            }
            if let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, AVAudioSession.InterruptionType(rawValue: rawType) == .ended {
                self.startPlaying()
            }
            self.activeUpdated?()
        })
        // After a media services reset every AVAudioPlayer is invalid and has stopped, and nothing else would restart
        // the silence while the app sits in the background: the player is recreated at once.
        self.resetObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            self.player = nil
            if self.isRequested {
                self.startPlaying()
            }
            self.activeUpdated?()
        })
    }

    deinit {
        if let interruptionObserver = self.interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let resetObserver = self.resetObserver {
            NotificationCenter.default.removeObserver(resetObserver)
        }
    }

    func setActive(_ active: Bool) {
        if active == self.isRequested {
            if active, self.player?.isPlaying != true {
                self.startPlaying()
            }
            return
        }
        self.isRequested = active
        if active {
            self.startPlaying()
        } else {
            self.player?.stop()
            self.player = nil
        }
    }

    private func startPlaying() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return
        }
        if self.player == nil {
            self.player = try? AVAudioPlayer(data: AstraBackgroundKeepAlive.silenceWav())
            self.player?.numberOfLoops = -1
            self.player?.volume = 0.01
        }
        self.player?.play()
    }

    /// One second of silence as a WAV file (8 kHz, 16-bit mono).
    private static func silenceWav() -> Data {
        let sampleRate: UInt32 = 8000
        let sampleCount = Int(sampleRate)
        let dataSize = UInt32(sampleCount * 2)
        var data = Data()
        func append32(_ value: UInt32) {
            var littleEndian = value.littleEndian
            data.append(Data(bytes: &littleEndian, count: 4))
        }
        func append16(_ value: UInt16) {
            var littleEndian = value.littleEndian
            data.append(Data(bytes: &littleEndian, count: 2))
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(1)
        append16(1)
        append32(sampleRate)
        append32(sampleRate * 2)
        append16(2)
        append16(16)
        data.append(contentsOf: Array("data".utf8))
        append32(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }
}
