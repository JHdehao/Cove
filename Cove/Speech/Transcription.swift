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
        case .open: String(localized: "开源（X-ASR）")
        case .apple: String(localized: "苹果系统")
        }
    }
}

/// Languages offered for Apple's engine (X-ASR does Mandarin and English together).
enum AppleSpeechLanguage: String, CaseIterable, Identifiable {
    case mandarin = "zh-CN", cantonese = "zh-HK", taiwan = "zh-TW", english = "en-US", japanese = "ja-JP", korean = "ko-KR",
         russian = "ru-RU", arabic = "ar-SA"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mandarin: String(localized: "普通话")
        case .cantonese: String(localized: "粤语")
        case .taiwan: String(localized: "中文（台湾）")
        case .english: String(localized: "英语")
        case .japanese: String(localized: "日语")
        case .korean: String(localized: "韩语")
        case .russian: String(localized: "俄语")
        case .arabic: String(localized: "阿拉伯语")
        }
    }
}

extension AppleSpeechLanguage {
    /// The phone's language, before the user picks one.
    static var systemDefault: AppleSpeechLanguage {
        let language = Locale.current.language
        switch language.languageCode?.identifier {
        case "zh":
            if language.script?.identifier == "Hant" { return Locale.current.region?.identifier == "HK" ? .cantonese : .taiwan }
            return .mandarin
        case "en": return .english
        case "ja": return .japanese
        case "ko": return .korean
        case "ru": return .russian
        case "ar": return .arabic
        default: return .english
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

    /// Before the user picks: Apple's where there is one and the open models aren't downloaded (so
    /// the first meeting is captioned straight away), or the phone isn't in Chinese (X-ASR does only
    /// Mandarin and English).
    static var defaultEngine: TranscriptionEngine {
        let chinese = Locale.current.language.languageCode?.identifier == "zh"
        return appleSupported && (!SpeechModels.filesPresent || !chinese) ? .apple : .open
    }

    /// The engine chosen in Settings, falling back to the open one where Apple's isn't available.
    static var engine: TranscriptionEngine {
        let chosen = TranscriptionEngine(rawValue: UserDefaults.standard.string(forKey: SpeechKey.engine) ?? "") ?? defaultEngine
        return chosen == .apple && appleSupported ? .apple : .open
    }

    static var appleLanguage: String {
        UserDefaults.standard.string(forKey: SpeechKey.appleLanguage) ?? AppleSpeechLanguage.systemDefault.rawValue
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
