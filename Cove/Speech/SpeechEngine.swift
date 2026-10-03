import AVFoundation
import Foundation
import SherpaOnnx

/// Turns 16 kHz mono audio into text as it arrives, in two passes:
/// - X-ASR streaming, a true streaming transducer, reads every 160 ms of audio as it comes and
///   keeps a draft of the sentence being spoken (shown at once, in grey);
/// - when Silero VAD hears the sentence end (0.5 s of silence), X-ASR offline reads the
///   whole sentence again for the final line, which replaces the draft.
/// Audio first goes through an automatic gain: a phone lying on a meeting table hears
/// distant voices at around -43 dBFS, and without it the VAD dropped half the speech
/// (measured 2026-10-04, PLAN §2.0).
final class SpeechEngine: @unchecked Sendable {
    static let sampleRate = 16_000

    struct Update: Sendable {
        /// The sentence still being spoken; "" once it's finished.
        var draft: String
        var finished: [Segment]
    }

    private let queue = DispatchQueue(label: "cove.speech", qos: .userInitiated)
    /// Streaming drafts; nil when transcribing a file (only finals are needed).
    private let streamer: SherpaOnnxRecognizer?
    private let finisher: SherpaOnnxOfflineRecognizer
    private let vad: SherpaOnnxVoiceActivityDetectorWrapper
    private let window = 512
    /// Where in the recording this engine's audio starts (when it attaches mid-meeting). Set before feeding audio.
    var offset: TimeInterval = 0

    private var pending: [Float] = []
    private var lastDraft = ""
    /// The last 3 s of raw audio, for the automatic gain.
    private var recent: [Float] = []

    /// Called on the main queue.
    var onUpdate: (@MainActor (Update) -> Void)?

    /// Fails if the models aren't downloaded (sherpa-onnx would abort on a missing file).
    init(drafts: Bool = true) throws {
        guard SpeechModels.filesPresent else { throw CocoaError(.fileNoSuchFile) }
        let features = sherpaOnnxFeatureConfig(sampleRate: Self.sampleRate, featureDim: 80)

        if drafts {
            let transducer = sherpaOnnxOnlineTransducerModelConfig(encoder: SpeechModels.path("xasr-encoder.int8.onnx"),
                                                                   decoder: SpeechModels.path("xasr-decoder.onnx"),
                                                                   joiner: SpeechModels.path("xasr-joiner.int8.onnx"))
            let model = sherpaOnnxOnlineModelConfig(tokens: SpeechModels.path("xasr-tokens.txt"), transducer: transducer, numThreads: 2)
            var config = sherpaOnnxOnlineRecognizerConfig(featConfig: features, modelConfig: model)
            streamer = SherpaOnnxRecognizer(config: &config)
        } else {
            streamer = nil
        }

        let offline = sherpaOnnxOfflineTransducerModelConfig(encoder: SpeechModels.path("xasr-offline-encoder.int8.onnx"),
                                                             decoder: SpeechModels.path("xasr-offline-decoder.onnx"),
                                                             joiner: SpeechModels.path("xasr-offline-joiner.int8.onnx"))
        let model = sherpaOnnxOfflineModelConfig(tokens: SpeechModels.path("xasr-offline-tokens.txt"), transducer: offline, numThreads: 2)
        var config = sherpaOnnxOfflineRecognizerConfig(featConfig: features, modelConfig: model)
        finisher = SherpaOnnxOfflineRecognizer(config: &config)

        // Up to 20 s per sentence: long enough for one, short enough to keep finals coming.
        let silero = sherpaOnnxSileroVadModelConfig(model: SpeechModels.path("silero_vad.onnx"), threshold: 0.3, minSilenceDuration: 0.5,
                                                    minSpeechDuration: 0.25, windowSize: window, maxSpeechDuration: 20)
        var vadConfig = sherpaOnnxVadModelConfig(sileroVad: silero, sampleRate: Int32(Self.sampleRate), numThreads: 1)
        vad = SherpaOnnxVoiceActivityDetectorWrapper(config: &vadConfig, buffer_size_in_seconds: 60)
    }

    /// Feed audio from any thread; it's processed in order on the engine's queue.
    func accept(_ samples: [Float]) {
        queue.async { self.process(samples) }
    }

    /// Ends the last sentence and calls back once everything fed so far is final.
    func finish(_ done: @escaping @Sendable () -> Void) {
        queue.async {
            self.vad.flush()
            let finished = self.drain()
            self.streamer?.reset()
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
                        segments += engine.segment(engine.louder(resampler.convert(buffer)))
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

    private func process(_ input: [Float]) {
        let samples = louder(input)
        var draft = lastDraft
        if let streamer {
            streamer.acceptWaveform(samples: samples, sampleRate: Self.sampleRate)
            while streamer.isReady() { streamer.decode() }
            draft = streamer.getResult().text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let finished = segment(samples)
        if !finished.isEmpty {
            // The sentence is final; the next draft starts from scratch.
            streamer?.reset()
            draft = ""
        }
        if draft != lastDraft || !finished.isEmpty {
            lastDraft = draft
            deliver(Update(draft: draft, finished: finished))
        }
    }

    /// Brings speech up to about -20 dBFS by the loudness of the last 3 s, at most 30×,
    /// so far-off voices reach the VAD and the recognizers. The recording itself is untouched.
    private func louder(_ samples: [Float]) -> [Float] {
        recent += samples
        if recent.count > Self.sampleRate * 3 { recent.removeFirst(recent.count - Self.sampleRate * 3) }
        let rms = (recent.reduce(0) { $0 + $1 * $1 } / Float(max(1, recent.count))).squareRoot() + 1e-6
        let gain = min(30, 0.1 / rms)
        return samples.map { max(-1, min(1, $0 * gain)) }
    }

    /// Runs the VAD over new audio and returns the sentences it closed, read by X-ASR offline.
    private func segment(_ samples: [Float]) -> [Segment] {
        pending += samples
        var finished: [Segment] = []
        var consumed = 0
        while pending.count - consumed >= window {
            vad.acceptWaveform(samples: Array(pending[consumed..<consumed + window]))
            consumed += window
            if !vad.isEmpty() { finished += drain() }
        }
        pending.removeFirst(consumed)
        return finished
    }

    /// Reads every sentence the VAD has closed.
    private func drain() -> [Segment] {
        var segments: [Segment] = []
        while !vad.isEmpty() {
            let segment = vad.front()
            let samples = segment.samples
            if samples.count > Self.sampleRate / 10 {
                let text = finisher.decode(samples: samples, sampleRate: Self.sampleRate).text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    let start = offset + Double(segment.start) / Double(Self.sampleRate)
                    segments.append(Segment(start: start, end: start + Double(segment.n) / Double(Self.sampleRate), speaker: nil, text: text))
                }
            }
            vad.pop()
        }
        return segments
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
