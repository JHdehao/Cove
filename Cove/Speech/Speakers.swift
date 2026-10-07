import AVFoundation
import Foundation
import Observation
import SherpaOnnx

/// The models for telling speakers apart, downloaded once (about 35 MB), separately from the
/// speech models since not every meeting needs them:
/// - pyannote segmentation 3.0 (MIT): where each voice talks;
/// - 3D-Speaker CAM++ zh-cn (Apache-2.0): a voiceprint for each stretch, clustered into people.
@MainActor @Observable
final class SpeakerModels {
    static let shared = SpeakerModels()

    nonisolated static let downloads: [SpeechModels.Download] = [
        .init(url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2")!,
              size: 6_958_444, save: .archive(["model.int8.onnx": "speaker-segmentation.int8.onnx"])),
        .init(url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx")!,
              size: 28_281_138, save: .file("speaker-embedding.onnx")),
    ]

    nonisolated static var filesPresent: Bool {
        downloads.flatMap(\.names).allSatisfy { FileManager.default.fileExists(atPath: SpeechModels.path($0)) }
    }

    nonisolated static var totalMB: Int { Int(downloads.reduce(0) { $0 + $1.size } / 1_000_000) }

    private(set) var isInstalled = SpeakerModels.filesPresent
    private(set) var isDownloading = false
    private(set) var progress: Double = 0
    var error: String?

    func download() async {
        guard !isDownloading else { return }
        isDownloading = true
        error = nil
        progress = 0
        defer { isDownloading = false }
        let total = Double(Self.downloads.reduce(0) { $0 + $1.size })
        var done: Int64 = 0
        do {
            for item in Self.downloads {
                if item.names.allSatisfy({ FileManager.default.fileExists(atPath: SpeechModels.path($0)) }) {
                    done += item.size
                    continue
                }
                let base = Double(done)
                let temporary = try await SpeechModels.fetch(item.url) { received in
                    Task { @MainActor in self.progress = min(1, (base + Double(received)) / total) }
                }
                defer { try? FileManager.default.removeItem(at: temporary) }
                switch item.save {
                case .file(let name):
                    let destination = SpeechModels.directory.appending(path: name)
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: temporary, to: destination)
                case .archive(let map):
                    try await Task.detached(priority: .userInitiated) {
                        try ModelArchive.extract(temporary, files: map, to: SpeechModels.directory)
                    }.value
                }
                done += item.size
            }
            isInstalled = Self.filesPresent
        } catch {
            self.error = "说话人模型下载失败：\(error.localizedDescription)"
        }
    }

    func remove() {
        for name in Self.downloads.flatMap(\.names) { try? FileManager.default.removeItem(atPath: SpeechModels.path(name)) }
        isInstalled = false
    }
}

/// Works out who spoke each line, after the meeting, on the phone.
enum Diarizer {
    /// Longer recordings would need more memory than a phone should give one app (about 230 MB an hour).
    static let maxSeconds: TimeInterval = 3 * 3600

    /// Labels each segment "说话人 1", "说话人 2"… in order of first appearance. `speakers`: how many, if known.
    static func label(_ segments: [Segment], audio url: URL, speakers: Int?) async throws -> [Segment] {
        guard SpeakerModels.filesPresent else { throw CocoaError(.fileNoSuchFile) }
        return try await Task.detached(priority: .userInitiated) {
            let file = try AVAudioFile(forReading: url)
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            guard seconds <= maxSeconds else {
                throw LLMError.service("录音超过 3 小时，手机上无法一次识别说话人。")
            }
            let samples = try read(file)

            let segmentation = sherpaOnnxOfflineSpeakerSegmentationModelConfig(
                pyannote: sherpaOnnxOfflineSpeakerSegmentationPyannoteModelConfig(model: SpeechModels.path("speaker-segmentation.int8.onnx")),
                numThreads: 2)
            let embedding = sherpaOnnxSpeakerEmbeddingExtractorConfig(model: SpeechModels.path("speaker-embedding.onnx"), numThreads: 2)
            let clustering = sherpaOnnxFastClusteringConfig(numClusters: speakers ?? -1, threshold: 0.5)
            var config = sherpaOnnxOfflineSpeakerDiarizationConfig(segmentation: segmentation, embedding: embedding, clustering: clustering)
            let diarizer = SherpaOnnxOfflineSpeakerDiarizationWrapper(config: &config)
            guard diarizer.impl != nil else { throw CocoaError(.fileReadCorruptFile) }
            let turns = diarizer.process(samples: samples)
            return assign(turns.map { (TimeInterval($0.start), TimeInterval($0.end), $0.speaker) }, to: segments)
        }.value
    }

    /// Each segment goes to the speaker who talks the most within it.
    static func assign(_ turns: [(start: TimeInterval, end: TimeInterval, speaker: Int)], to segments: [Segment]) -> [Segment] {
        var names: [Int: String] = [:]
        return segments.map { segment in
            var overlap: [Int: TimeInterval] = [:]
            for turn in turns where turn.end > segment.start && turn.start < segment.end {
                overlap[turn.speaker, default: 0] += min(turn.end, segment.end) - max(turn.start, segment.start)
            }
            var labeled = segment
            if let speaker = overlap.max(by: { $0.value < $1.value })?.key {
                if names[speaker] == nil { names[speaker] = "说话人 \(names.count + 1)" }
                labeled.speaker = names[speaker]
            }
            return labeled
        }
    }

    /// The whole file as 16 kHz mono.
    private static func read(_ file: AVAudioFile) throws -> [Float] {
        let resampler = try Resampler(from: file.processingFormat)
        let frames = AVAudioFrameCount(file.processingFormat.sampleRate * 30)
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) / file.processingFormat.sampleRate * Double(SpeechEngine.sampleRate)) + 16_000)
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { break }
            try file.read(into: buffer, frameCount: frames)
            if buffer.frameLength == 0 { break }
            samples += resampler.convert(buffer)
        }
        return samples
    }
}

enum SpeakerKey {
    static let auto = "speakers.auto"
}
