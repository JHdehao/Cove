import AVFoundation
import Foundation

/// A live transcriber: fed 16 kHz mono audio, reports drafts and finished lines.
protocol LiveTranscriber: AnyObject, Sendable {
    /// Called on the main queue.
    var onUpdate: (@MainActor (SpeechEngine.Update) -> Void)? { get set }
    /// Where in the recording this engine's audio starts. Set before feeding audio.
    var offset: TimeInterval { get set }
    func accept(_ samples: [Float])
    /// Ends the last sentence and calls back (on the main queue) once everything fed so far is final.
    func finish(_ done: @escaping @Sendable () -> Void)
}

extension SpeechEngine: LiveTranscriber {}

/// Which recognizer turns speech into text.
enum TranscriptionEngine: String, CaseIterable, Identifiable {
    /// X-ASR via sherpa-onnx: open source, iOS 18+, downloaded once (~310 MB), Mandarin and English.
    case open
    /// Apple's SpeechAnalyzer: built into iOS 26, nothing to download, more languages.
    case apple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: "开源（X-ASR）"
        case .apple: "苹果系统"
        }
    }
}

/// Languages offered for Apple's engine (X-ASR does Mandarin and English together).
enum AppleSpeechLanguage: String, CaseIterable, Identifiable {
    case mandarin = "zh-CN", cantonese = "zh-HK", taiwan = "zh-TW", english = "en-US", japanese = "ja-JP", korean = "ko-KR"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mandarin: "普通话"
        case .cantonese: "粤语"
        case .taiwan: "中文（台湾）"
        case .english: "英语"
        case .japanese: "日语"
        case .korean: "韩语"
        }
    }
}

enum SpeechKey {
    static let engine = "speech.engine"
    static let appleLanguage = "speech.appleLanguage"
}

enum Transcription {
    /// Apple's engine needs iOS 26.
    static var appleSupported: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    /// The engine chosen in Settings, falling back to the open one where Apple's isn't available.
    static var engine: TranscriptionEngine {
        let chosen = TranscriptionEngine(rawValue: UserDefaults.standard.string(forKey: SpeechKey.engine) ?? "") ?? .open
        return chosen == .apple && appleSupported ? .apple : .open
    }

    static var appleLanguage: String {
        UserDefaults.standard.string(forKey: SpeechKey.appleLanguage) ?? AppleSpeechLanguage.mandarin.rawValue
    }

    /// Ready to transcribe without asking the user to download anything first.
    @MainActor static var isReady: Bool {
        engine == .apple || SpeechModels.shared.isInstalled
    }

    /// The chosen engine, loaded off the main thread.
    static func makeLive() async throws -> LiveTranscriber {
        if engine == .apple, #available(iOS 26, *) {
            return try await AppleSpeechEngine.make(language: appleLanguage)
        }
        return try await Task.detached(priority: .userInitiated) { try SpeechEngine() }.value
    }

    /// Transcribes a whole file with the chosen engine.
    static func transcribe(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> [Segment] {
        if engine == .apple, #available(iOS 26, *) {
            return try await AppleSpeechEngine.transcribe(url, language: appleLanguage, progress: progress)
        }
        return try await SpeechEngine.transcribe(url, progress: progress)
    }
}
