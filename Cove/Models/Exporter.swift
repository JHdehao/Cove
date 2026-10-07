import Foundation

/// A meeting as Markdown (minutes then transcript) or as SRT subtitles.
enum Exporter {
    static func markdown(_ meeting: Meeting) -> String {
        let segments = meeting.segments
        // Citations become plain timestamps outside the app.
        let minutes = Citations.linked(meeting.summary, segments: segments)
            .replacingOccurrences(of: #"\[(\d{1,2}:\d{2}(?::\d{2})?)\]\(cove://seg/\d+\)"#, with: "($1)", options: .regularExpression)
        var text = minutes.isEmpty ? "# \(meeting.title)\n" : minutes
        text += String(localized: "\n\n---\n\n## 转录\n\n")
        text += segments.map { "**\(clockString($0.start))**\($0.speaker.map { " \($0)" } ?? "")：\($0.text)" }.joined(separator: "\n\n")
        return text
    }

    static func srt(_ meeting: Meeting) -> String {
        func stamp(_ t: TimeInterval) -> String {
            let ms = Int((t * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
        }
        return meeting.segments.enumerated().map { index, segment in
            "\(index + 1)\n\(stamp(segment.start)) --> \(stamp(segment.end))\n\(segment.speaker.map { "\($0)：" } ?? "")\(segment.text)\n"
        }.joined(separator: "\n")
    }
}
