import Foundation
import SwiftData

/// One stretch of speech: who said what, and when (seconds from the start).
struct Segment: Codable, Hashable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var speaker: String?
    var text: String
}

/// A point the user flagged while recording.
struct Marker: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case star, todo, question
        /// A typed note; `text` holds it.
        case note
        /// The recording stopped for a while (a call, the microphone taken away); `text` says how long.
        case gap
        var label: String { ["star": "重点", "todo": "待办", "question": "疑问", "note": "笔记", "gap": "中断"][rawValue] ?? "" }
        var symbol: String {
            ["star": "star.fill", "todo": "checkmark.circle", "question": "questionmark.circle", "note": "note.text", "gap": "pause.circle"][rawValue] ?? ""
        }
        /// The one-tap buttons on the recording screen.
        static let buttons: [Kind] = [.star, .todo, .question]
    }
    var time: TimeInterval
    var kind: Kind
    var text: String? = nil
}

@Model
final class Meeting {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var duration: TimeInterval = 0
    /// File name in `Meeting.audioDirectory`; nil for an imported transcript.
    var audioFileName: String?

    @Attribute(.externalStorage) var segmentsData: Data = Data()
    var markersData: Data = Data()
    var chatData: Data = Data()

    var summary: String = ""
    /// The running notes kept during recording.
    var liveNotes: String = ""
    var summaryTemplateID: String = ""
    var summaryModel: String = ""
    var summarizedAt: Date?
    /// Still being recorded, or the app ended before the recording was closed (recovered at the next launch).
    var isRecording: Bool = false
    /// Live captions stopped partway (the phone got too hot): transcribe the whole recording again.
    var needsRetranscribe: Bool = false

    init(title: String, createdAt: Date = .now) {
        self.title = title
        self.createdAt = createdAt
    }

    var segments: [Segment] {
        get { (try? JSONDecoder().decode([Segment].self, from: segmentsData)) ?? [] }
        set { segmentsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var markers: [Marker] {
        get { (try? JSONDecoder().decode([Marker].self, from: markersData)) ?? [] }
        set { markersData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var chat: [ChatMessage] {
        get { (try? JSONDecoder().decode([ChatMessage].self, from: chatData)) ?? [] }
        set { chatData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    static let audioDirectory: URL = {
        let url = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    var audioURL: URL? { audioFileName.map { Self.audioDirectory.appending(path: $0) } }

    /// Where the recording is written a minute at a time while it goes on (see `AudioParts`).
    var partsDirectory: URL { Self.audioDirectory.appending(path: "parts-\(id.uuidString)", directoryHint: .isDirectory) }

    /// The first line of the summary that says something (the one-sentence conclusion).
    var gist: String {
        summary.split(separator: "\n").lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.replacingOccurrences(of: #"^>\s*"#, with: "", options: .regularExpression) }
            .map(Citations.stripped) ?? ""
    }

    func deleteAudio() {
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        try? FileManager.default.removeItem(at: partsDirectory)
    }
}
