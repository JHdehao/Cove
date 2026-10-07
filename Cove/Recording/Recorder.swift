import AVFoundation
import Observation

/// Records one meeting from the microphone into 16 kHz mono AAC (what speech models
/// take, about 15 MB an hour) and hands the same audio to the live transcriber.
///
/// The audio goes to a new file every minute (`AudioParts`): an .m4a is only readable once
/// it's closed, so if the app is killed mid-meeting at most the last minute is lost, and the
/// parts are joined at the end or at the next launch. It keeps going in the background,
/// picks up after calls, and follows the microphone when the route changes (AirPods
/// connected or gone); if the audio stops arriving anyway, `stalled` says so.
@MainActor @Observable
final class Recorder {
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    /// 0…1, for the waveform.
    private(set) var levels: [Float] = Array(repeating: 0, count: 48)
    private(set) var markers: [Marker] = []
    /// No audio for a few seconds while recording: the microphone was taken and couldn't be got back.
    private(set) var stalled = false
    /// Something the user should know that doesn't stop the recording.
    var notice: String?
    var error: String?

    /// Called on the audio thread with each piece of 16 kHz mono audio that was recorded.
    @ObservationIgnored var onSamples: (@Sendable ([Float]) -> Void)? {
        didSet { tap?.onSamples = onSamples }
    }

    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private var tap: TapState?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var interruptedAt: Date?
    @ObservationIgnored private var lastAudio = Date()
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    func start(into directory: URL) async {
        guard await AVAudioApplication.requestRecordPermission() else {
            error = String(localized: "没有麦克风权限。请到系统设置 → 隐私与安全性 → 麦克风里打开 Cove。")
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try activateSession()
            let tap = TapState(directory: directory, onSamples: onSamples) { [weak self] level, seconds in
                Task { @MainActor in self?.update(level: level, seconds: seconds) }
            }
            try tap.openFirstPart()
            self.tap = tap
            try attachInput()
            markers = []
            elapsed = 0
            isRecording = true
            isPaused = false
            stalled = false
            lastAudio = .now
            observe()
            startWatchdog()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            tap?.close()
            tap = nil
            self.error = String(localized: "无法开始录音：\(error.localizedDescription)")
        }
    }

    func togglePause() {
        isPaused.toggle()
        tap?.isPaused = isPaused
        lastAudio = .now
        // Resuming after a call that didn't hand the microphone back: try again now.
        if !isPaused, !engine.isRunning { restart() }
    }

    func mark(_ kind: Marker.Kind, text: String? = nil) {
        markers.append(Marker(time: elapsed, kind: kind, text: text))
    }

    /// Stops and returns the length, or nil if nothing was recording. The parts still need joining (`AudioParts.join`).
    func stop() -> (duration: TimeInterval, markers: [Marker])? {
        guard let tap else { return nil }
        let duration = tap.seconds
        teardown()
        return (duration, markers)
    }

    /// Stops without keeping anything; the caller deletes the parts.
    func discard() {
        teardown()
    }

    private func update(level: Float, seconds: TimeInterval) {
        elapsed = seconds
        levels.removeFirst()
        levels.append(level)
        lastAudio = .now
        if stalled { stalled = false }
    }

    // MARK: Engine

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
    }

    /// Taps the current input in whatever format it has now and starts the engine.
    private func attachInput() throws {
        guard let tap else { return }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        // No input (sample rate 0) happens briefly while the route is changing.
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
        tap.resampler = try Resampler(from: format)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in tap.handle(buffer) }
        engine.prepare()
        try engine.start()
    }

    /// Gets the microphone going again after a call, a route change or the media services restarting.
    private func restart() {
        guard isRecording else { return }
        do {
            try activateSession()
            try attachInput()
        } catch {
            // Most often the route is still settling; the watchdog tries again.
            stalled = true
        }
    }

    private func teardown() {
        watchdog?.cancel()
        watchdog = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        tap?.close()
        tap = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        isRecording = false
        isPaused = false
        stalled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observe() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
                MainActor.assumeIsolated { self?.interruption(type) }
            },
            // AirPods connected or taken out, a wired mic plugged in: the input format changes and the engine stops.
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restart() }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isRecording else { return }
                    // The old engine is dead; build a new one on the same files.
                    self.engine = AVAudioEngine()
                    self.restart()
                }
            },
        ]
    }

    private func interruption(_ type: AVAudioSession.InterruptionType?) {
        guard isRecording else { return }
        switch type {
        case .began:
            interruptedAt = .now
        case .ended:
            restart()
            if let interruptedAt {
                let seconds = Date().timeIntervalSince(interruptedAt)
                if seconds >= 1 {
                    mark(.gap, text: String(localized: "录音中断约 \(Int(seconds.rounded())) 秒"))
                    notice = String(localized: "录音被打断约 \(Int(seconds.rounded())) 秒，已自动继续。")
                }
            }
            interruptedAt = nil
        default:
            break
        }
    }

    /// Every 2 s: if no audio has come for 3 s while recording, say so and try to get the microphone back.
    private func startWatchdog() {
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                guard self.isRecording, !self.isPaused, self.interruptedAt == nil else { continue }
                if Date().timeIntervalSince(self.lastAudio) > 3 {
                    self.stalled = true
                    self.restart()
                }
            }
        }
    }
}

/// What the audio thread touches: the current part file, the resampler, the running length.
private final class TapState: @unchecked Sendable {
    static let partSeconds = 60

    private let directory: URL
    private var file: AVAudioFile?
    private var part = 0
    private var partFrames: AVAudioFramePosition = 0
    private var _resampler: Resampler?
    private var _onSamples: (@Sendable ([Float]) -> Void)?
    private let report: @Sendable (Float, TimeInterval) -> Void
    private let lock = NSLock()
    private var frames: AVAudioFramePosition = 0
    private var closed = false
    private var paused = false

    init(directory: URL, onSamples: (@Sendable ([Float]) -> Void)?, report: @escaping @Sendable (Float, TimeInterval) -> Void) {
        self.directory = directory
        _onSamples = onSamples
        self.report = report
    }

    /// Set when the transcriber starts after recording already began.
    var onSamples: (@Sendable ([Float]) -> Void)? {
        get { lock.withLock { _onSamples } }
        set { lock.withLock { _onSamples = newValue } }
    }

    /// Replaced when the input format changes.
    var resampler: Resampler? {
        get { lock.withLock { _resampler } }
        set { lock.withLock { _resampler = newValue } }
    }

    var isPaused: Bool {
        get { lock.withLock { paused } }
        set { lock.withLock { paused = newValue } }
    }

    var seconds: TimeInterval { lock.withLock { Double(frames) / Double(SpeechEngine.sampleRate) } }

    func openFirstPart() throws {
        try lock.withLock { try openPart() }
    }

    /// Call with the lock held. Closes the current part (releasing an AVAudioFile finishes it) and starts the next.
    private func openPart() throws {
        file = nil
        part += 1
        partFrames = 0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: SpeechEngine.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        file = try AVAudioFile(forWriting: AudioParts.url(part, in: directory), settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func handle(_ buffer: AVAudioPCMBuffer) {
        guard !isPaused, let converted = resampler?.convertBuffer(buffer), let data = converted.floatChannelData else { return }
        let count = Int(converted.frameLength)
        guard count > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: data[0], count: count))
        lock.withLock {
            guard !closed else { return }
            if partFrames >= AVAudioFramePosition(Self.partSeconds * SpeechEngine.sampleRate) { try? openPart() }
            try? file?.write(from: converted)
            partFrames += AVAudioFramePosition(count)
            frames += AVAudioFramePosition(count)
        }
        onSamples?(samples)
        // Loudness in dB, -50 dB and below drawn as silence.
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, count)))
        let level = max(0, min(1, (20 * log10(max(rms, 1e-6)) + 50) / 50))
        report(level, seconds)
    }

    func close() {
        lock.withLock {
            closed = true
            file = nil
        }
    }
}

/// A recording kept as one-minute .m4a parts while it's made, joined into one file afterwards.
enum AudioParts {
    static func url(_ part: Int, in directory: URL) -> URL {
        directory.appending(path: String(format: "%05d.m4a", part))
    }

    /// Joins the readable parts in `directory` into `destination` and removes them. A part
    /// cut off by the app being killed can't be read and is skipped. Returns the length.
    @discardableResult
    static func join(_ directory: URL, into destination: URL) async throws -> TimeInterval {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.filter { $0.hasSuffix(".m4a") }.sorted() ?? []
        var readable: [(URL, AVAudioFile)] = []
        for name in names {
            let url = directory.appending(path: name)
            if let file = try? AVAudioFile(forReading: url), file.length > 0 { readable.append((url, file)) }
        }
        guard !readable.isEmpty else {
            try? FileManager.default.removeItem(at: directory)
            throw CocoaError(.fileReadCorruptFile)
        }
        try? FileManager.default.removeItem(at: destination)
        if readable.count == 1 {
            try FileManager.default.moveItem(at: readable[0].0, to: destination)
        } else {
            let composition = AVMutableComposition()
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw CocoaError(.featureUnsupported)
            }
            var cursor = CMTime.zero
            for (url, _) in readable {
                let asset = AVURLAsset(url: url)
                guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
                let range = try await source.load(.timeRange)
                try track.insertTimeRange(range, of: source, at: cursor)
                cursor = cursor + range.duration
            }
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
                throw CocoaError(.featureUnsupported)
            }
            try await export.export(to: destination, as: .m4a)
        }
        try? FileManager.default.removeItem(at: directory)
        let file = try AVAudioFile(forReading: destination)
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
