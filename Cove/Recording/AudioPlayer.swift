import AVFoundation
import Observation

/// Plays a meeting's recording; the transcript and citations seek it.
@MainActor @Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var rate: Float = 1 {
        didSet { player?.rate = rate }
    }

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(_ url: URL) {
        guard player?.url != url else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        currentTime = 0
    }

    var isLoaded: Bool { player != nil }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.rate = rate
        player.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying { self.pause() }
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func seek(_ time: TimeInterval, play: Bool = true) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
        if play, !isPlaying { self.play() }
    }

    func skip(_ seconds: TimeInterval) {
        seek(currentTime + seconds, play: isPlaying)
    }

    func stop() {
        pause()
        player = nil
    }
}
