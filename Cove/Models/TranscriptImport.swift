import Foundation

/// Reads transcripts made elsewhere: SRT / WebVTT subtitles, or plain text with
/// optional "Name: words" speaker prefixes and "[00:12:34]" timestamps.
enum TranscriptImport {
    static func parse(_ text: String) -> [Segment] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.contains("-->") { return subtitles(normalized) }
        return plain(normalized)
    }

    private static func subtitles(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = seconds(parts[0]), let end = seconds(parts[1]) else { continue }
            var body = lines[(timing + 1)...].joined(separator: " ")
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            var speaker: String?
            // WebVTT voice tag <v Name> was stripped above; "Name: text" is common too.
            if let voice = lines[(timing + 1)...].first?.firstMatch(of: #/<v\s+([^>]+)>/#) { speaker = String(voice.1) }
            if speaker == nil, let (name, rest) = speakerPrefix(body) { speaker = name; body = rest }
            body = body.trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { continue }
            segments.append(Segment(start: start, end: end, speaker: speaker, text: body))
        }
        return segments
    }

    private static func plain(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var clock: TimeInterval = 0
        for raw in text.split(separator: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var start = clock
            if let match = line.firstMatch(of: #/^\[?((?:\d{1,2}:)?\d{1,2}:\d{2})\]?\s*/#), let time = seconds(String(match.1)) {
                start = time
                line = String(line[match.range.upperBound...])
            }
            var speaker: String?
            if let (name, rest) = speakerPrefix(line) { speaker = name; line = rest }
            guard !line.isEmpty else { continue }
            // Without timestamps, estimate about four characters a second so the order and rough place hold.
            clock = start + max(2, Double(line.count) / 4)
            if var last = segments.last, last.end > start { last.end = start; segments[segments.count - 1] = last }
            segments.append(Segment(start: start, end: clock, speaker: speaker, text: line))
        }
        return segments
    }

    /// "张三：今天…" or "Alice: today…", with a short name before the colon.
    private static func speakerPrefix(_ line: String) -> (String, String)? {
        guard let match = line.firstMatch(of: #/^([^:：\s][^:：]{0,19})[:：]\s*(.+)$/#) else { return nil }
        let name = String(match.1).trimmingCharacters(in: .whitespaces)
        // A time ("10:30") or a URL isn't a speaker.
        guard name.rangeOfCharacter(from: .decimalDigits.inverted) != nil, !name.lowercased().hasPrefix("http") else { return nil }
        return (name, String(match.2))
    }

    /// "01:02:03,456", "02:03.4", "1:02:03" → seconds.
    static func seconds(_ string: String) -> TimeInterval? {
        let cleaned = string.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let parts = cleaned.replacingOccurrences(of: ",", with: ".").split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }
}
