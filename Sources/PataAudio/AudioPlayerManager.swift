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
    private var activeLoadId = UUID()

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

        // Reset previous player state immediately without blocking MainActor
        cleanUpCurrentPlayer()
        currentAudioPath = relativePath

        let loadId = UUID()
        activeLoadId = loadId

        // Asynchronously load asset and probe duration off the main thread to avoid UI hitch
        Task.detached(priority: .userInitiated) { [weak self] in
            let asset = AVURLAsset(url: url)
            var calculatedDurationMs = 0
            if let duration = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                if !seconds.isNaN && seconds > 0 {
                    calculatedDurationMs = Int(seconds * 1000)
                }
            }

            await MainActor.run { [weak self] in
                guard let self = self, self.activeLoadId == loadId else { return }

                let item = AVPlayerItem(asset: asset)
                let newPlayer = AVPlayer(playerItem: item)
                self.player = newPlayer
                self.durationMs = calculatedDurationMs

                let interval = CMTime(value: 100, timescale: 1000) // 100ms updates (10 fps scrubber)
                self.timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                    let sec = CMTimeGetSeconds(time)
                    guard !sec.isNaN else { return }
                    let ms = Int(sec * 1000)
                    MainActor.assumeIsolated {
                        self?.currentPositionMs = ms
                    }
                }
            }
        }
    }

    private func cleanUpCurrentPlayer() {
        pause()
        if let token = timeObserverToken, let p = player {
            p.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player = nil
        currentPositionMs = 0
        durationMs = 0
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
        activeLoadId = UUID()
        cleanUpCurrentPlayer()
        currentAudioPath = nil
    }
}
