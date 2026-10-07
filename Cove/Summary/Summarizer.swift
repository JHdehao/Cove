import Foundation
import Observation

/// "[#12]" or "[#12, #15]" in model output: the transcript lines a statement rests on.
enum Citations {
    static let pattern = #"\[#\d+(?:\s*[,，]\s*#?\d+)*\]"#

    /// Markdown with each citation turned into links that jump to the line ("cove://seg/12").
    static func linked(_ markdown: String, segments: [Segment]) -> String {
        replace(markdown) { numbers in
            numbers.filter { $0 < segments.count }
                .map { "[\(clockString(segments[$0].start))](cove://seg/\($0))" }
                .joined(separator: " ")
        }
    }

    static func stripped(_ text: String) -> String {
        replace(text) { _ in "" }.trimmingCharacters(in: .whitespaces)
    }

    private static func replace(_ text: String, with transform: ([Int]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let numbers = result[range].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            result.replaceSubrange(range, with: transform(numbers))
        }
        return result
    }
}

/// Writes the minutes for one meeting, streaming them as they come. Long meetings
/// are summarized part by part first, then the parts' notes are written up together.
@MainActor @Observable
final class Summarizer {
    var text = ""
    var phase = ""
    var error: String?
    var isRunning = false
    private var task: Task<Void, Never>?

    func start(_ meeting: Meeting, template: SummaryTemplate, language: SummaryLanguage, glossary: String, provider: ProviderConfig) {
        cancel()
        let segments = meeting.segments
        let markers = meeting.markers
        let attendees = meeting.attendees
        let session = meeting.id.uuidString
        text = ""
        error = nil
        isRunning = true
        task = Task {
            defer { isRunning = false; phase = "" }
            do {
                let client = LLMClient(provider, session: session)
                let lines = Self.transcriptLines(segments)
                let budget = max(800, provider.contextChars)
                let chunks = Self.chunk(lines, budget: budget)
                var material: String
                if chunks.count == 1 {
                    material = "会议转录：\n" + chunks[0]
                } else {
                    var notes: [String] = []
                    for (index, chunk) in chunks.enumerated() {
                        phase = String(localized: "分段整理 \(index + 1)/\(chunks.count)")
                        notes.append(try await client.complete(system: Self.notesSystem(language), messages: [.init(role: .user, content: chunk)]))
                    }
                    // A small model (Apple's on-device one) can't take all the notes at once: fold them again until they fit.
                    var round = 1
                    while notes.reduce(0, { $0 + $1.count }) > budget, notes.count > 1, round < 5 {
                        round += 1
                        let groups = Self.chunk(notes, budget: budget)
                        guard groups.count < notes.count else { break }
                        var folded: [String] = []
                        for (index, group) in groups.enumerated() {
                            phase = String(localized: "合并笔记 \(index + 1)/\(groups.count)")
                            folded.append(try await client.complete(system: Self.notesSystem(language), messages: [.init(role: .user, content: group)]))
                        }
                        notes = folded
                    }
                    material = "会议很长，已分 \(chunks.count) 段整理成笔记（编号仍指向原转录行）：\n\n"
                        + notes.enumerated().map { "### 第 \($0.offset + 1) 段\n\($0.element)" }.joined(separator: "\n\n")
                }
                material += Self.markerNotes(markers)
                if !attendees.isEmpty {
                    material += "\n\n参会人（来自日历邀请）：\(attendees)。转录里的「说话人 N」只有在内容明确（如自我介绍、被点名回应）时才对应到具体的人，不确定就保留「说话人 N」。"
                }
                phase = String(localized: "撰写纪要")
                let system = Self.minutesSystem(template: template, language: language, glossary: glossary)
                for try await delta in client.stream(system: system, messages: [.init(role: .user, content: material)]) {
                    text += delta
                }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw LLMError.badResponse }
                meeting.summary = text
                meeting.summaryTemplateID = template.id
                meeting.summaryModel = provider.model
                meeting.summarizedAt = .now
                if !meeting.titleIsFixed, let title = Self.title(in: text) { meeting.title = title }
                if let problem = AutoExport.save(meeting) { self.error = problem }
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: Prompts

    /// The user's own notes and flags from the recording, for the model to build the minutes around.
    static func markerNotes(_ markers: [Marker]) -> String {
        var text = ""
        let notes = markers.filter { $0.kind == .note }
        if !notes.isEmpty {
            text += "\n\n用户在会上亲手记的笔记（最能代表用户关心什么：纪要要围绕它们展开，每条都要在纪要相应位置体现并补全细节和出处）：\n"
                + notes.map { "- \(clockString($0.time)) \($0.text ?? "")" }.joined(separator: "\n")
        }
        let flags = markers.filter { Marker.Kind.buttons.contains($0.kind) }
        if !flags.isEmpty {
            text += "\n\n用户录音时做的标记（时间点附近的内容请优先体现）：\n"
                + flags.map { "- \(clockString($0.time)) \($0.kind.label)" }.joined(separator: "\n")
        }
        let gaps = markers.filter { $0.kind == .gap }
        if !gaps.isEmpty {
            text += "\n\n录音中断（这段时间的内容没有录到，不要臆测）：\n"
                + gaps.map { "- \(clockString($0.time)) \($0.text ?? "")" }.joined(separator: "\n")
        }
        return text
    }

    /// "[12] 08:31 张三：…" — the number is what citations point back to.
    static func transcriptLines(_ segments: [Segment]) -> [String] {
        segments.enumerated().map { index, segment in
            "[\(index)] \(clockString(segment.start)) \(segment.speaker.map { "\($0)：" } ?? "")\(segment.text)"
        }
    }

    static func chunk(_ lines: [String], budget: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for line in lines {
            if !current.isEmpty, current.count + line.count > budget {
                chunks.append(current)
                current = ""
            }
            current += line + "\n"
        }
        if !current.isEmpty || chunks.isEmpty { chunks.append(current) }
        return chunks
    }

    private static let groundRules = """
    规则：
    - 只依据转录内容，不编造、不推测没说过的事；转录里的错别字按上下文理解。
    - 每条结论、决策、待办末尾用 [#编号] 标注出处，编号是转录行首方括号里的数字，可写多个如 [#12, #15]。
    - 简洁具体：写清谁、做什么、什么时候，不写空话。某一节没有内容就写「无」。
    """

    static func minutesSystem(template: SummaryTemplate, language: SummaryLanguage, glossary: String) -> String {
        var prompt = """
        你是会议纪要助手，把会议转录整理成结构化纪要，输出 Markdown。

        \(groundRules)
        - \(language.instruction)

        格式：
        第一行是 `# 会议标题`（10–20 字，概括主题）。
        第二行是 `> 一句话结论`。
        然后按下面的结构写：
        \(template.focus)

        「待办」一节每条写成：`- [ ] 任务 — 负责人 — 截止时间 [#编号]`，不知道的写「待定」。
        「章节」一节每条写成：`- mm:ss 小标题：一句话 [#编号]`，按时间顺序。
        """
        let terms = glossary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !terms.isEmpty {
            prompt += "\n\n术语表（转录可能把这些词识别错，请按它们纠正）：\n\(terms)"
        }
        return prompt
    }

    static func notesSystem(_ language: SummaryLanguage) -> String {
        """
        你在整理一场长会议中的一段转录，供之后合并成完整纪要。按时间顺序列出这段的要点、决策、待办（含负责人和时间）、未决问题，用 Markdown 列表。

        \(groundRules)
        - \(language.instruction)
        """
    }

    /// The text after the leading "# ", if the minutes start with a heading.
    static func title(in markdown: String) -> String? {
        guard let first = markdown.split(separator: "\n").first, first.hasPrefix("# ") else { return nil }
        let title = Citations.stripped(String(first.dropFirst(2)))
        return title.isEmpty ? nil : title
    }

    /// The to-dos: every "- [ ] task — owner — due" line (only the to-do section uses checkboxes,
    /// whatever language its heading is in).
    static func actionItems(in markdown: String) -> [String] {
        var items: [String] = []
        for line in markdown.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            guard line.hasPrefix("- [ ]") || line.hasPrefix("- [x]") else { continue }
            let item = Citations.stripped(String(line.dropFirst(5)))
            if !item.isEmpty, item != "无" { items.append(item) }
        }
        return items
    }
}
