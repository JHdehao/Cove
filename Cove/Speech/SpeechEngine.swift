import AVFoundation
import Foundation
import SherpaOnnx

/// Turns 16 kHz mono audio into text as it arrives. Silero VAD cuts the audio into
/// utterances; while someone is still talking, SenseVoice re-reads the open utterance
/// about twice a second (a draft line), and when they pause it reads the whole
/// utterance once more for the final line. SenseVoice is non-streaming but fast enough
/// (well under 0.2 s per utterance on a recent iPhone) that this feels live.
final class SpeechEngine: @unchecked Sendable {
    static let sampleRate = 16_000

    struct Update: Sendable {
        /// The utterance still being spoken; "" once it's finished.
        var draft: String
        var finished: [Segment]
    }

    private let queue = DispatchQueue(label: "cove.speech", qos: .userInitiated)
    private let recognizer: SherpaOnnxOfflineRecognizer
    private let vad: SherpaOnnxVoiceActivityDetectorWrapper
    private let window = 512

    private var pending: [Float] = []
    /// The open utterance's audio so far, for drafts.
    private var open: [Float] = []
    private var lastDraftSize = 0
    private var lastDraftCost: TimeInterval = 0
    private var backlog = 0
    private let lock = NSLock()

    /// Called on the main queue.
    var onUpdate: (@MainActor (Update) -> Void)?

    /// Fails if the models aren't downloaded (sherpa-onnx would abort on a missing file).
    /// `offset`: where in the recording this engine's audio starts (when it's created mid-meeting).
    init(drafts: Bool = true, offset: TimeInterval = 0) throws {
        guard SpeechModels.filesPresent else { throw CocoaError(.fileNoSuchFile) }
        self.drafts = drafts
        self.offset = offset

        let senseVoice = sherpaOnnxOfflineSenseVoiceModelConfig(model: SpeechModels.modelPath, language: "", useInverseTextNormalization: true)
        let modelConfig = sherpaOnnxOfflineModelConfig(tokens: SpeechModels.tokensPath, numThreads: 2, senseVoice: senseVoice)
        var config = sherpaOnnxOfflineRecognizerConfig(featConfig: sherpaOnnxFeatureConfig(sampleRate: Self.sampleRate, featureDim: 80),
                                                       modelConfig: modelConfig)
        recognizer = SherpaOnnxOfflineRecognizer(config: &config)

        // Up to 20 s per utterance: long enough for a sentence, short enough to keep finals coming.
        let silero = sherpaOnnxSileroVadModelConfig(model: SpeechModels.vadPath, threshold: 0.5, minSilenceDuration: 0.5,
                                                    minSpeechDuration: 0.25, windowSize: window, maxSpeechDuration: 20)
        var vadConfig = sherpaOnnxVadModelConfig(sileroVad: silero, sampleRate: Int32(Self.sampleRate), numThreads: 1)
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &vadConfig, buffer_size_in_seconds: 60)
    }

    private let drafts: Bool
    private let offset: TimeInterval

    /// Feed audio from any thread; it's processed in order on the engine's queue.
    func accept(_ samples: [Float]) {
        lock.withLock { backlog += samples.count }
        queue.async { self.process(samples) }
    }

    /// Ends the last utterance and calls back once everything fed so far is final.
    func finish(_ done: @escaping @Sendable () -> Void) {
        queue.async {
            self.vad.flush()
            let finished = self.drain()
            self.open = []
            self.deliver(Update(draft: "", finished: finished))
            DispatchQueue.main.async(execute: done)
        }
    }

    /// Transcribes a whole file (an imported recording, or one made without the models).
    static func transcribe(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [Segment] {
        let engine = try SpeechEngine(drafts: false)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let file = try AVAudioFile(forReading: url)
                    let resampler = try Resampler(from: file.processingFormat)
                    let frames = AVAudioFrameCount(file.processingFormat.sampleRate * 10)
                    var segments: [Segment] = []
                    while file.framePosition < file.length {
                        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { break }
                        try file.read(into: buffer, frameCount: frames)
                        if buffer.frameLength == 0 { break }
                        segments += engine.processNow(resampler.convert(buffer))
                        progress(Double(file.framePosition) / Double(max(1, file.length)))
                    }
                    engine.vad.flush()
                    segments += engine.drain()
                    continuation.resume(returning: segments)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Work (on `queue`, or the caller's thread for files)

    private func process(_ samples: [Float]) {
        let finished = processNow(samples)
        lock.withLock { backlog -= samples.count }
        var draft: String?
        if drafts, vad.isSpeechDetected() {
            // A draft every half second of new speech, less often if decoding can't keep up.
            let grown = open.count - lastDraftSize
            let behind = lock.withLock { backlog } > Self.sampleRate
            if grown >= Self.sampleRate / 2, !behind, lastDraftCost < 0.4 {
                let start = Date()
                draft = decode(Array(open.suffix(Self.sampleRate * 20)))
                lastDraftCost = Date().timeIntervalSince(start)
                lastDraftSize = open.count
            }
        } else if !finished.isEmpty {
            draft = ""
        }
        if draft != nil || !finished.isEmpty {
            deliver(Update(draft: draft ?? "", finished: finished))
        }
    }

    private func processNow(_ samples: [Float]) -> [Segment] {
        pending += samples
        var finished: [Segment] = []
        var consumed = 0
        while pending.count - consumed >= window {
            let chunk = Array(pending[consumed..<consumed + window])
            consumed += window
            vad.acceptWaveform(samples: chunk)
            if vad.isSpeechDetected() { open += chunk }
            if !vad.isEmpty() {
                finished += drain()
                open = []
                lastDraftSize = 0
            }
        }
        pending.removeFirst(consumed)
        return finished
    }

    /// Reads every utterance the VAD has closed.
    private func drain() -> [Segment] {
        var segments: [Segment] = []
        while !vad.isEmpty() {
            let segment = vad.front()
            let text = decode(segment.samples)
            if !text.isEmpty {
                let start = offset + Double(segment.start) / Double(Self.sampleRate)
                segments.append(Segment(start: start, end: start + Double(segment.n) / Double(Self.sampleRate), speaker: nil, text: text))
            }
            vad.pop()
        }
        return segments
    }

    private func decode(_ samples: [Float]) -> String {
        guard samples.count > Self.sampleRate / 10 else { return "" }
        return recognizer.decode(samples: samples, sampleRate: Self.sampleRate).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deliver(_ update: Update) {
        guard let onUpdate else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { onUpdate(update) } }
    }
}

/// Converts any PCM format to 16 kHz mono Float32.
final class Resampler {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(SpeechEngine.sampleRate), channels: 1, interleaved: false)!
    private let converter: AVAudioConverter
    private let ratio: Double

    init(from input: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: input, to: Self.format) else { throw CocoaError(.featureUnsupported) }
        self.converter = converter
        ratio = Self.format.sampleRate / input.sampleRate
    }

    func convertBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            if given {
                status.pointee = .noDataNow
                return nil
            }
            given = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let output = convertBuffer(buffer), let data = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}
