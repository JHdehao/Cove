import Foundation
import Observation

/// Keeps running notes while the meeting is still going: whenever enough new speech
/// has been transcribed, the model folds it into the notes so far. Each update only
/// sends the current notes and the new lines, so it stays quick however long the
/// meeting runs. At the end the full minutes are written from the whole transcript.
@MainActor @Observable
final class LiveSummarizer {
    private(set) var notes = ""
    private(set) var isUpdating = false
    private(set) var updatedAt: Date?
    var error: String?

    private var refresh = LiveRefresh.standard

    private var provider: ProviderConfig?
    private var language: SummaryLanguage = .auto
    private var glossary = ""
    private var covered = 0
    private var session = UUID().uuidString
    private var task: Task<Void, Never>?
    private var timedOut = false

    func configure(provider: ProviderConfig?, language: SummaryLanguage, glossary: String, refresh: LiveRefresh) {
        self.provider = provider
        self.refresh = refresh
        self.language = language
        self.glossary = glossary
        session = UUID().uuidString
    }

    var isAvailable: Bool { provider?.isUsable == true }

    /// Called whenever new final lines arrive; starts an update if one is due.
    func consider(_ segments: [Segment], force: Bool = false) {
        guard let provider, provider.isUsable, !isUpdating, covered < segments.count else { return }
        let fresh = segments[covered...]
        let chars = fresh.reduce(0) { $0 + $1.text.count }
        let waited = { (interval: TimeInterval) in self.updatedAt.map { Date().timeIntervalSince($0) >= interval } ?? true }
        let due = force || refresh.threshold.map { chars >= $0.chars && waited($0.interval) } ?? false
        guard due else { return }

        let upTo = segments.count
        let lines = Summarizer.transcriptLines(segments)[covered..<upTo].joined(separator: "\n")
        let previous = notes
        let system = Self.system(language: language, glossary: glossary)
        let message = (previous.isEmpty ? "（还没有笔记）" : "当前笔记：\n\(previous)") + "\n\n新增转录：\n\(lines)"
        isUpdating = true
        error = nil
        timedOut = false
        // A stalled stream would otherwise hold `isUpdating` and block every later update.
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, let self, self.isUpdating else { return }
            self.timedOut = true
            self.task?.cancel()
        }
        task = Task {
            defer { isUpdating = false; watchdog.cancel() }
            do {
                var draft = ""
                for try await delta in LLMClient(provider, session: session).stream(system: system, messages: [.init(role: .user, content: message)], maxTokens: 8000) {
                    draft += delta
                    notes = draft
                }
                try Task.checkCancellation()
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Thinking models can spend the whole budget before writing a word.
                    notes = previous
                    self.error = "模型这次没有返回内容（可能思考用完了输出额度），稍后会再试。可换不带思考的模型。"
                } else {
                    covered = upTo
                }
                updatedAt = .now
            } catch is CancellationError {
                notes = previous
                if timedOut {
                    self.error = "这次更新超过 2 分钟没完成，已放弃，稍后会再试。"
                    updatedAt = .now
                }
            } catch {
                notes = previous
                self.error = error.localizedDescription
                // Back off before trying again.
                updatedAt = .now
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private static func system(language: SummaryLanguage, glossary: String) -> String {
        var prompt = """
        你在会议进行中实时记笔记。给你当前笔记和刚转录出的新内容，输出更新后的完整笔记（Markdown），只输出笔记本身。

        结构固定为：
        ## 正在讨论
        一两句话说明眼下的话题。
        ## 要点
        ## 决策
        ## 待办
        ## 疑问

        规则：
        - 只依据转录，不编造；转录有错字时按上下文理解。
        - 保留旧笔记里仍然成立的内容，合并重复，修正被新内容推翻的。
        - 每条结论末尾用 [#编号] 标注出处（转录行首方括号里的数字）。
        - 简短，每节最多 6 条；没有内容的节写「无」。
        - \(language.instruction)
        """
        let terms = glossary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !terms.isEmpty { prompt += "\n\n术语表（按它们纠正识别错误）：\n\(terms)" }
        return prompt
    }
}
