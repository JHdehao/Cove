import EventKit
import SwiftUI

/// One meeting: the minutes, the transcript and a chat about it, with the recording
/// playing underneath. Citations in the minutes and chat jump to the transcript line.
struct MeetingDetailView: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SummaryKey.template) private var templateID = "general"
    @AppStorage(SummaryKey.language) private var language = SummaryLanguage.auto.rawValue
    @AppStorage(SummaryKey.customPrompt) private var customPrompt = ""
    @AppStorage(SummaryKey.glossary) private var glossary = ""
    @AppStorage(SummaryKey.auto) private var autoSummarize = true
    @State private var tab = Tab.minutes
    @State private var summarizer = Summarizer()
    @State private var player = AudioPlayer()
    @State private var models = SpeechModels.shared
    @State private var transcribing: Double?
    @State private var transcribeError: String?
    @State private var focusedSegment: Int?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var editingTitle = false
    @State private var notice: String?
    @State private var providers = ProviderStore.shared

    enum Tab: String, CaseIterable {
        case minutes = "纪要"
        case transcript = "转录"
        case chat = "对话"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch tab {
            case .minutes: minutes
            case .transcript: TranscriptView(meeting: meeting, player: player, focused: $focusedSegment, rename: { renaming = $0; newName = $0 })
            case .chat: ChatView(meeting: meeting)
            }

            if player.isLoaded { PlayerBar(player: player) }
        }
        .coveCanvas()
        .navigationTitle(meeting.title.isEmpty ? "未命名会议" : meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { menu }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "cove", url.host == "seg", let index = Int(url.lastPathComponent) else { return .systemAction }
            jump(to: index)
            return .handled
        })
        .onAppear {
            if let url = meeting.audioURL, FileManager.default.fileExists(atPath: url.path) { player.load(url) }
            // An imported or uncaptioned recording: transcribe it now.
            if meeting.segments.isEmpty, meeting.audioURL != nil, models.isInstalled, transcribing == nil { transcribe() }
            if autoSummarize, meeting.summary.isEmpty, !meeting.segments.isEmpty, providers.active?.isUsable == true,
               !summarizer.isRunning { summarize() }
        }
        .onDisappear {
            player.stop()
        }
        .alert("重命名说话人", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名字", text: $newName)
            Button("取消", role: .cancel) {}
            Button("好") { renameSpeaker() }
        }
        .alert("会议标题", isPresented: $editingTitle) {
            TextField("标题", text: $newName)
            Button("取消", role: .cancel) {}
            Button("好") { meeting.title = newName }
        }
        .alert("", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("好") {}
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: Minutes

    private var template: SummaryTemplate { SummaryTemplate.named(templateID, customPrompt: customPrompt) }

    @ViewBuilder
    private var minutes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if meeting.segments.isEmpty {
                    untranscribed
                } else if summarizer.isRunning || !summarizer.text.isEmpty {
                    status
                    MarkdownView(markdown: Citations.linked(summarizer.text, segments: meeting.segments))
                } else if !meeting.summary.isEmpty {
                    MarkdownView(markdown: Citations.linked(meeting.summary, segments: meeting.segments))
                    footer
                } else {
                    if !meeting.liveNotes.isEmpty {
                        Text("会中实时纪要").font(.caption).foregroundStyle(.secondary)
                        MarkdownView(markdown: Citations.linked(meeting.liveNotes, segments: meeting.segments))
                        Divider()
                    }
                    templatePicker
                }
                if let error = summarizer.error {
                    Text(error).font(.callout).foregroundStyle(.red)
                    Button("重试") { summarize() }
                }
            }
            .padding()
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            if summarizer.isRunning {
                ProgressView().controlSize(.small)
                Text(summarizer.phase.isEmpty ? "正在生成纪要…" : summarizer.phase)
                Spacer()
                Button("停止") { summarizer.cancel() }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack {
            CoveTag(text: SummaryTemplate.named(meeting.summaryTemplateID, customPrompt: customPrompt).name)
            if !meeting.summaryModel.isEmpty { CoveTag(text: meeting.summaryModel) }
            Spacer()
            if let date = meeting.summarizedAt {
                Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 8)
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择纪要模板").font(.system(.title3, design: .serif).weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(SummaryTemplate.builtIn + (customPrompt.isEmpty ? [] : [SummaryTemplate.named(SummaryTemplate.custom, customPrompt: customPrompt)])) { item in
                    Button {
                        templateID = item.id
                    } label: {
                        Label(item.name, systemImage: item.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(CoveColor.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(item.id == templateID ? CoveColor.accent : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(CoveColor.text)
                }
            }
            Button(action: summarize) {
                Label("生成纪要", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(CoveColor.accent)
            Text(providers.active.map { "使用 \($0.name) · \($0.model.isEmpty ? "未选模型" : $0.model)" } ?? "还没有模型接口，请到设置里添加。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var untranscribed: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没有转录").font(.system(.title3, design: .serif).weight(.semibold))
            if meeting.audioURL == nil {
                Text("这场会议没有录音，也没有转录内容。").foregroundStyle(.secondary)
            } else if let transcribing {
                Text("正在本机转录… \(Int(transcribing * 100))%").foregroundStyle(.secondary)
                ProgressView(value: transcribing)
            } else if !models.isInstalled {
                Text("在本机用 SenseVoice 转录，需要先下载语音模型（约 240 MB，只需一次）。").foregroundStyle(.secondary)
                if models.isDownloading {
                    ProgressView(value: models.progress)
                } else {
                    Button("下载语音模型") { Task { await models.download() } }
                        .buttonStyle(.borderedProminent).tint(CoveColor.accent)
                }
            } else {
                Button("在本机转录") { transcribe() }
                    .buttonStyle(.borderedProminent).tint(CoveColor.accent)
            }
            if let error = transcribeError ?? models.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    // MARK: Menu

    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if !meeting.segments.isEmpty {
                    Menu {
                        ForEach(SummaryTemplate.builtIn) { item in
                            Button { templateID = item.id; summarize() } label: { Label(item.name, systemImage: item.symbol) }
                        }
                        if !customPrompt.isEmpty {
                            Button("自定义模板") { templateID = SummaryTemplate.custom; summarize() }
                        }
                    } label: {
                        Label("重新生成纪要", systemImage: "arrow.clockwise")
                    }
                    if providers.providers.count > 1 {
                        Picker(selection: Binding(get: { providers.activeID }, set: { providers.activeID = $0 })) {
                            ForEach(providers.providers) { Text("\($0.name) · \($0.model)").tag(Optional($0.id)) }
                        } label: {
                            Label("模型接口", systemImage: "cpu")
                        }
                    }
                }
                if meeting.audioURL != nil, models.isInstalled, transcribing == nil {
                    Button { transcribe() } label: { Label("重新转录", systemImage: "waveform") }
                }
                if !Summarizer.actionItems(in: meeting.summary).isEmpty {
                    Button { exportReminders() } label: { Label("待办导入提醒事项", systemImage: "checklist") }
                }
                ShareLink(item: Exporter.markdown(meeting), subject: Text(meeting.title)) {
                    Label("分享 Markdown", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: Exporter.srt(meeting)) {
                    Label("分享字幕（SRT）", systemImage: "captions.bubble")
                }
                Button { newName = meeting.title; editingTitle = true } label: { Label("重命名", systemImage: "pencil") }
                Button(role: .destructive) {
                    meeting.deleteAudio()
                    context.delete(meeting)
                    dismiss()
                } label: {
                    Label("删除会议", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: Actions

    private func summarize() {
        guard let provider = providers.active, provider.isUsable else {
            summarizer.error = LLMError.notConfigured.localizedDescription
            return
        }
        tab = .minutes
        summarizer.start(meeting, template: template, language: SummaryLanguage(rawValue: language) ?? .auto, glossary: glossary, provider: provider)
    }

    private func transcribe() {
        guard let url = meeting.audioURL else { return }
        transcribing = 0
        transcribeError = nil
        Task {
            do {
                let segments = try await SpeechEngine.transcribe(url) { value in
                    Task { @MainActor in if transcribing != nil { transcribing = value } }
                }
                meeting.segments = segments
                transcribing = nil
                if autoSummarize, !segments.isEmpty, providers.active?.isUsable == true { summarize() }
            } catch {
                transcribing = nil
                transcribeError = "转录失败：\(error.localizedDescription)"
            }
        }
    }

    private func jump(to index: Int) {
        let segments = meeting.segments
        guard segments.indices.contains(index) else { return }
        tab = .transcript
        focusedSegment = index
        player.seek(segments[index].start)
    }

    private func renameSpeaker() {
        guard let old = renaming else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != old else { return }
        meeting.segments = meeting.segments.map { var s = $0; if s.speaker == old { s.speaker = name }; return s }
        meeting.summary = meeting.summary.replacingOccurrences(of: old, with: name)
        renaming = nil
    }

    private func exportReminders() {
        let items = Summarizer.actionItems(in: meeting.summary)
        Task {
            let store = EKEventStore()
            do {
                guard try await store.requestFullAccessToReminders() else {
                    notice = "没有提醒事项的权限。"
                    return
                }
                for item in items {
                    let reminder = EKReminder(eventStore: store)
                    reminder.title = item.replacingOccurrences(of: " — 待定", with: "")
                    reminder.notes = "来自会议：\(meeting.title)"
                    reminder.calendar = store.defaultCalendarForNewReminders()
                    try store.save(reminder, commit: false)
                }
                try store.commit()
                notice = "已导入 \(items.count) 条待办。"
            } catch {
                notice = "导入失败：\(error.localizedDescription)"
            }
        }
    }
}

/// Play / pause, position and speed for the recording.
struct PlayerBar: View {
    @Bindable var player: AudioPlayer

    var body: some View {
        HStack(spacing: 14) {
            Button { player.skip(-15) } label: { Image(systemName: "gobackward.15") }
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
            }
            Button { player.skip(15) } label: { Image(systemName: "goforward.15") }
            Text("\(clockString(player.currentTime)) / \(clockString(player.duration))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach([0.75, 1, 1.25, 1.5, 2] as [Float], id: \.self) { rate in
                    Button("\(rate.formatted())×") { player.rate = rate }
                }
            } label: {
                Text("\(player.rate.formatted())×").font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(CoveColor.text)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .modifier(GlassCapsule())
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}
