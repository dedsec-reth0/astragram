import Foundation
import AVFoundation

/// AyuGram: keeps the app running in the background, so it stays connected and new messages arrive (and are notified)
/// while it is closed. Without push notifications, iOS suspends a backgrounded app within seconds; an app playing audio
/// is not suspended, so this plays silence, mixed with other audio, while the app is in the background.
final class AyuBackgroundKeepAlive {
    private var player: AVAudioPlayer?
    private var interruptionObserver: NSObjectProtocol?

    private(set) var isActive = false

    init() {
        self.interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main, using: { [weak self] notification in
            guard let self, self.isActive else {
                return
            }
            if let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, AVAudioSession.InterruptionType(rawValue: rawType) == .ended {
                self.startPlaying()
            }
        })
    }

    deinit {
        if let interruptionObserver = self.interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    func setActive(_ active: Bool) {
        if active == self.isActive {
            if active, self.player?.isPlaying != true {
                self.startPlaying()
            }
            return
        }
        self.isActive = active
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
            self.player = try? AVAudioPlayer(data: AyuBackgroundKeepAlive.silenceWav())
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
