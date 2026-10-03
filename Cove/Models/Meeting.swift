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
        var label: String { ["star": "重点", "todo": "待办", "question": "疑问"][rawValue] ?? "" }
        var symbol: String { ["star": "star.fill", "todo": "checkmark.circle", "question": "questionmark.circle"][rawValue] ?? "" }
    }
    var time: TimeInterval
    var kind: Kind
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
    }
}
