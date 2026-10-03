import AVFoundation
import Observation

/// Records one meeting from the microphone into a 16 kHz mono AAC file (what speech
/// models take, about 15 MB an hour) and hands the same audio to the live transcriber.
/// Keeps going in the background and picks up again after interruptions (calls).
@MainActor @Observable
final class Recorder {
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    /// 0…1, for the waveform.
    private(set) var levels: [Float] = Array(repeating: 0, count: 48)
    private(set) var markers: [Marker] = []
    private(set) var fileName: String?
    var error: String?

    /// Called on the audio thread with each piece of 16 kHz mono audio that was recorded.
    @ObservationIgnored var onSamples: (@Sendable ([Float]) -> Void)? {
        didSet { tap?.onSamples = onSamples }
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var tap: TapState?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "没有麦克风权限。请到系统设置 → 隐私与安全性 → 麦克风里打开 Cove。"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            let name = "\(UUID().uuidString).m4a"
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: SpeechEngine.sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ]
            let file = try AVAudioFile(forWriting: Meeting.audioDirectory.appending(path: name), settings: settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let tap = TapState(file: file, resampler: try Resampler(from: format), onSamples: onSamples) { [weak self] level, seconds in
                Task { @MainActor in self?.update(level: level, seconds: seconds) }
            }
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in tap.handle(buffer) }
            engine.prepare()
            try engine.start()

            self.tap = tap
            fileName = name
            markers = []
            elapsed = 0
            isRecording = true
            isPaused = false
            observeInterruptions()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            self.error = "无法开始录音：\(error.localizedDescription)"
        }
    }

    func togglePause() {
        isPaused.toggle()
        tap?.isPaused = isPaused
    }

    func mark(_ kind: Marker.Kind) {
        markers.append(Marker(time: elapsed, kind: kind))
    }

    /// Stops and returns the file name and length, or nil if nothing was recorded.
    func stop() -> (fileName: String, duration: TimeInterval, markers: [Marker])? {
        guard let fileName, let tap else { return nil }
        let duration = tap.seconds
        teardown()
        return (fileName, duration, markers)
    }

    /// Stops and deletes the file.
    func discard() {
        let url = fileName.map { Meeting.audioDirectory.appending(path: $0) }
        teardown()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func update(level: Float, seconds: TimeInterval) {
        elapsed = seconds
        levels.removeFirst()
        levels.append(level)
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        tap?.close()
        tap = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        fileName = nil
        isRecording = false
        isPaused = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated {
                // A call took the microphone; pick up again as soon as it's given back.
                guard let self, self.isRecording, type == .ended else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                try? self.engine.start()
            }
        }
    }
}

/// What the audio thread touches: the file, the resampler, the running length.
private final class TapState: @unchecked Sendable {
    private let file: AVAudioFile
    private let resampler: Resampler
    private var _onSamples: (@Sendable ([Float]) -> Void)?
    private let report: @Sendable (Float, TimeInterval) -> Void
    private let lock = NSLock()
    private var frames: AVAudioFramePosition = 0
    private var closed = false
    private var paused = false

    init(file: AVAudioFile, resampler: Resampler, onSamples: (@Sendable ([Float]) -> Void)?,
         report: @escaping @Sendable (Float, TimeInterval) -> Void) {
        self.file = file
        self.resampler = resampler
        _onSamples = onSamples
        self.report = report
    }

    /// Set when the transcriber starts after recording already began.
    var onSamples: (@Sendable ([Float]) -> Void)? {
        get { lock.withLock { _onSamples } }
        set { lock.withLock { _onSamples = newValue } }
    }

    var isPaused: Bool {
        get { lock.withLock { paused } }
        set { lock.withLock { paused = newValue } }
    }

    var seconds: TimeInterval { lock.withLock { Double(frames) / Double(SpeechEngine.sampleRate) } }

    func handle(_ buffer: AVAudioPCMBuffer) {
        guard !isPaused, let converted = resampler.convertBuffer(buffer), let data = converted.floatChannelData else { return }
        let count = Int(converted.frameLength)
        let samples = Array(UnsafeBufferPointer(start: data[0], count: count))
        lock.withLock {
            guard !closed else { return }
            try? file.write(from: converted)
            frames += AVAudioFramePosition(count)
        }
        onSamples?(samples)
        // Loudness in dB, -50 dB and below drawn as silence.
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, count)))
        let level = max(0, min(1, (20 * log10(max(rms, 1e-6)) + 50) / 50))
        report(level, seconds)
    }

    /// AVAudioFile finishes the file when it's released; stop writing first.
    func close() {
        lock.withLock { closed = true }
    }
}
