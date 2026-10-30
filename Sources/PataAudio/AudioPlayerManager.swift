import Foundation
import AVFoundation

@MainActor
public final class AudioPlayerManager: ObservableObject {
    public static let shared = AudioPlayerManager()

    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentPositionMs: Int = 0
    @Published public private(set) var durationMs: Int = 0
    @Published public private(set) var currentAudioPath: String?

    private var player: AVPlayer?
    private var timeObserverToken: Any?

    public init() {}

    isolated deinit {
        if let token = timeObserverToken, let p = player {
            p.removeTimeObserver(token)
        }
    }

    public func loadAudio(url: URL, relativePath: String) {
        if currentAudioPath == relativePath && player != nil {
            return
        }

        stop()
        currentAudioPath = relativePath

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)

        Task {
            if let duration = try? await item.asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                if !seconds.isNaN && seconds > 0 {
                    self.durationMs = Int(seconds * 1000)
                }
            }
        }

        let interval = CMTime(value: 50, timescale: 1000) // 50ms updates
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let sec = CMTimeGetSeconds(time)
            if !sec.isNaN {
                Task { @MainActor [weak self] in
                    self?.currentPositionMs = Int(sec * 1000)
                }
            }
        }
    }

    public func play() {
        guard let p = player else { return }
        p.play()
        isPlaying = true
    }

    public func pause() {
        guard let p = player else { return }
        p.pause()
        isPlaying = false
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func seek(toMilliseconds ms: Int, autoPlay: Bool = false) {
        guard let p = player else { return }
        let targetTime = CMTime(value: Int64(ms), timescale: 1000)
        p.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            if autoPlay {
                Task { @MainActor [weak self] in
                    self?.play()
                }
            }
        }
        currentPositionMs = ms
    }

    public func stop() {
        pause()
        if let token = timeObserverToken, let p = player {
            p.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player = nil
        currentAudioPath = nil
        currentPositionMs = 0
        durationMs = 0
    }
}
