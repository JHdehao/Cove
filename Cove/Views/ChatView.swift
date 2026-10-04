import SwiftUI

/// Ask about the meeting: "what did Zhang say about the budget?", "draft the follow-up email".
/// The transcript and minutes go along as context; answers cite lines like the minutes do.
struct ChatView: View {
    @Bindable var meeting: Meeting
    @State private var input = ""
    @State private var reply = ""
    @State private var isSending = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    private let suggestions = ["这次会议最重要的三件事是什么？", "每个人分别负责什么？", "有哪些分歧还没解决？", "写一封会后跟进邮件"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if meeting.chat.isEmpty, !isSending {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("问问这场会议").font(.system(.title3, design: .serif).weight(.semibold))
                                ForEach(suggestions, id: \.self) { text in
                                    Button { send(text) } label: {
                                        Text(text)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(CoveColor.card, in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    .foregroundStyle(CoveColor.text)
                                }
                            }
                        }
                        ForEach(Array(meeting.chat.enumerated()), id: \.offset) { _, message in
                            bubble(message)
                        }
                        if isSending {
                            if reply.isEmpty {
                                ProgressView().controlSize(.small)
                            } else {
                                MarkdownView(markdown: Citations.linked(reply, segments: meeting.segments))
                            }
                        }
                        if let error { Text(error).font(.callout).foregroundStyle(.red) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding()
                }
                .onChange(of: reply) { proxy.scrollTo("end") }
                .onChange(of: meeting.chat.count) { withAnimation { proxy.scrollTo("end") } }
            }
            inputBar
        }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(message.content)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(CoveColor.card, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(CoveColor.text)
            }
        } else {
            MarkdownView(markdown: Citations.linked(message.content, segments: meeting.segments))
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("问点什么…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
            Button {
                if isSending { task?.cancel() } else { send(input) }
            } label: {
                Image(systemName: isSending ? "stop.fill" : "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(CoveColor.accent.opacity(isSending || !input.isEmpty ? 1 : 0.4), in: Circle())
            }
            .disabled(!isSending && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(6)
        }
        .modifier(GlassCapsule())
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        guard let provider = ProviderStore.shared.active, provider.isUsable else {
            error = LLMError.notConfigured.localizedDescription
            return
        }
        input = ""
        error = nil
        meeting.chat.append(ChatMessage(role: .user, content: question))
        let history = meeting.chat
        let system = Self.system(meeting, budget: provider.contextChars)
        isSending = true
        reply = ""
        task = Task {
            defer { isSending = false }
            do {
                for try await delta in LLMClient(provider, session: "\(meeting.id.uuidString)-chat").stream(system: system, messages: history) { reply += delta }
                if !reply.isEmpty { meeting.chat.append(ChatMessage(role: .assistant, content: reply)) }
            } catch is CancellationError {
                if !reply.isEmpty { meeting.chat.append(ChatMessage(role: .assistant, content: reply)) }
            } catch {
                self.error = error.localizedDescription
            }
            reply = ""
        }
    }

    private static func system(_ meeting: Meeting, budget: Int) -> String {
        var transcript = Summarizer.transcriptLines(meeting.segments).joined(separator: "\n")
        var note = ""
        if transcript.count > budget {
            // Too long for one request: the minutes carry the rest.
            transcript = String(transcript.prefix(budget))
            note = "（转录过长，只附了开头部分，其余请依据纪要。）"
        }
        return """
        你是会议助手，依据下面这场会议的转录和纪要回答用户的问题。
        - 只依据会议内容；会议里没提到的就直说没提到。
        - 引用具体内容时在句末用 [#编号] 标注出处（转录行首方括号里的数字）。
        - 回答简洁，用 Markdown。

        会议：\(meeting.title)（\(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))）

        纪要：
        \(meeting.summary.isEmpty ? (meeting.liveNotes.isEmpty ? "（暂无）" : meeting.liveNotes) : meeting.summary)

        转录\(note)：
        \(transcript)
        """
    }
}
