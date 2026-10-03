import AVFoundation
import Foundation
import Speech

/// Apple's on-device recognizer (SpeechAnalyzer, iOS 26), behind the same interface as
/// the open engine: volatile results are the grey draft, final results the finished lines.
/// The system downloads and manages its own model; nothing is bundled with Cove.
@available(iOS 26, *)
final class AppleSpeechEngine: LiveTranscriber, @unchecked Sendable {
    enum Failure: LocalizedError {
        case unsupportedLanguage
        case noAudioFormat

        var errorDescription: String? {
            switch self {
            case .unsupportedLanguage: "苹果语音识别不支持所选语言。"
            case .noAudioFormat: "苹果语音识别无法处理这种音频。"
            }
        }
    }

    var onUpdate: (@MainActor (SpeechEngine.Update) -> Void)?
    var offset: TimeInterval = 0

    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let format: AVAudioFormat
    private let converter: AVAudioConverter?
    private var results: Task<Void, Never>?
    private let lock = NSLock()
    private var finished: [Segment] = []

    private init(analyzer: SpeechAnalyzer, transcriber: SpeechTranscriber, input: AsyncStream<AnalyzerInput>.Continuation, format: AVAudioFormat) {
        self.analyzer = analyzer
        self.transcriber = transcriber
        self.input = input
        self.format = format
        converter = format == Resampler.format ? nil : AVAudioConverter(from: Resampler.format, to: format)
    }

    /// Sets up the recognizer for a language, installing the system's model for it if needed.
    static func make(language: String) async throws -> AppleSpeechEngine {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw Failure.unsupportedLanguage
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults],
                                            attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Failure.noAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: stream)
        let engine = AppleSpeechEngine(analyzer: analyzer, transcriber: transcriber, input: continuation, format: format)
        engine.listen()
        return engine
    }

    func accept(_ samples: [Float]) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: Resampler.format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        guard let converted = convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    func finish(_ done: @escaping @Sendable () -> Void) {
        input.finish()
        Task {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
            await results?.value
            DispatchQueue.main.async(execute: done)
        }
    }

    /// Transcribes a whole file: the same path as live audio, fed as fast as it reads.
    static func transcribe(_ url: URL, language: String, progress: @escaping @Sendable (Double) -> Void) async throws -> [Segment] {
        let engine = try await make(language: language)
        try await Task.detached(priority: .userInitiated) {
            let file = try AVAudioFile(forReading: url)
            let resampler = try Resampler(from: file.processingFormat)
            let frames = AVAudioFrameCount(file.processingFormat.sampleRate * 10)
            while file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { break }
                try file.read(into: buffer, frameCount: frames)
                if buffer.frameLength == 0 { break }
                engine.accept(resampler.convert(buffer))
                progress(Double(file.framePosition) / Double(max(1, file.length)))
            }
        }.value
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            engine.finish { continuation.resume() }
        }
        return engine.lock.withLock { engine.finished }
    }

    // MARK: Private

    private func listen() {
        results = Task { [weak self] in
            guard let transcriber = self?.transcriber else { return }
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if result.isFinal {
                        guard !text.isEmpty else { continue }
                        let segment = Segment(start: offset + result.range.start.seconds,
                                              end: offset + result.range.end.seconds, speaker: nil, text: text)
                        lock.withLock { finished.append(segment) }
                        deliver(SpeechEngine.Update(draft: "", finished: [segment]))
                    } else {
                        deliver(SpeechEngine.Update(draft: text, finished: []))
                    }
                }
            } catch {
                // The analyzer stopped (finished, or the system took the model away); nothing more will come.
            }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = format.sampleRate / Resampler.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
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

    private func deliver(_ update: SpeechEngine.Update) {
        guard let onUpdate else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { onUpdate(update) } }
    }
}
