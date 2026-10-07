import Combine
import SwiftData
import SwiftUI

/// What's been said so far in the meeting being recorded.
@MainActor @Observable
final class LiveTranscript {
    var segments: [Segment] = []
    var draft = ""

    func apply(_ update: SpeechEngine.Update) {
        segments += update.finished
        draft = update.draft
    }
}

/// Recording: live captions and running notes while the meeting goes on, markers,
/// pause and stop. On stop the last utterance is finished and the meeting opens,
/// where the full minutes start writing straight away.
struct RecordView: View {
    let onFinish: (Meeting) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("record.consentAcknowledged") private var consentAcknowledged = false
    @AppStorage(SummaryKey.language) private var language = SummaryLanguage.auto.rawValue
    @AppStorage(SummaryKey.glossary) private var glossary = ""
    @AppStorage(SummaryKey.liveRefresh) private var liveRefresh = LiveRefresh.standard.rawValue
    @State private var recorder = Recorder()
    @State private var transcript = LiveTranscript()
    @State private var notes = LiveSummarizer()
    @State private var models = SpeechModels.shared
    @State private var engine: LiveTranscriber?
    @State private var engineError: String?
    @State private var loadingEngine = false
    @State private var tab = Tab.captions
    @State private var finishing = false
    @State private var confirmDiscard = false
    /// Made as soon as recording starts and saved as it goes, so nothing is lost if the app is killed.
    @State private var meeting: Meeting?
    @State private var askConsent = false
    @State private var writingNote = false
    @State private var noteText = ""
    /// Live captions were stopped because the phone got too hot.
    @State private var cooledDown = false

    enum Tab: String, CaseIterable {
        case captions = "实时字幕"
        case notes = "实时纪要"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)

            Group {
                switch tab {
                case .captions: captions
                case .notes: liveNotes
                }
            }
            .frame(maxHeight: .infinity)

            controls
        }
        .coveCanvas()
        .tint(CoveColor.text)
        .modifier(AIConsentPrompt())
        .task {
            if consentAcknowledged { await begin() } else { askConsent = true }
        }
        .alert("开始录音前", isPresented: $askConsent) {
            Button("已告知，开始录音") {
                consentAcknowledged = true
                Task { await begin() }
            }
            Button("取消", role: .cancel) { dismiss() }
        } message: {
            Text("请先告诉参会的人这场会议会被录音和转录。很多地方的法律要求所有参与者同意后才能录音。\n\n录音和转录只保存在这台手机上。")
        }
        .alert("会中笔记", isPresented: $writingNote) {
            TextField("记下重点，纪要会围绕它展开", text: $noteText)
            Button("取消", role: .cancel) {}
            Button("记下") { addNote() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persist() }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification).receive(on: DispatchQueue.main)) { _ in
            coolDownIfHot()
        }
        .onChange(of: models.isInstalled) { _, installed in
            // Models finished downloading mid-meeting: captions start from here.
            if installed, engine == nil, recorder.isRecording { startEngine() }
        }
        .overlay {
            if finishing {
                ProgressView("正在完成转录…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .confirmationDialog("放弃这段录音？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放弃录音", role: .destructive) {
                notes.cancel()
                recorder.discard()
                if let meeting {
                    meeting.deleteAudio()
                    context.delete(meeting)
                    try? context.save()
                }
                dismiss()
            }
        }
        .alert("录音出错", isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) {
            Button("好") { dismiss() }
        } message: {
            Text(recorder.error ?? "")
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Button("放弃") { confirmDiscard = true }
                    .foregroundStyle(.secondary)
                Spacer()
                if recorder.isRecording {
                    Label(recorder.isPaused ? String(localized: "已暂停") : String(localized: "录音中"), systemImage: "circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(recorder.isPaused ? Color.secondary : CoveColor.accent)
                }
            }
            Text(clockString(recorder.elapsed))
                .font(.system(size: 44, weight: .light, design: .serif).monospacedDigit())
                .foregroundStyle(CoveColor.text)
            waveform.frame(height: 36)
            banners
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// The recording's health, in order of how much it matters.
    @ViewBuilder
    private var banners: some View {
        if recorder.stalled {
            banner(String(localized: "麦克风被占用或断开，正在尝试恢复…已录的部分都已保存。"), symbol: "exclamationmark.triangle.fill", color: .red)
        } else if let notice = recorder.notice {
            banner(notice, symbol: "info.circle", color: .secondary) { recorder.notice = nil }
        } else if cooledDown {
            banner(String(localized: "手机过热，已停止实时字幕和实时纪要，录音继续。散会后会重新完整转录。"), symbol: "thermometer.high", color: .orange)
        } else if isQuiet {
            banner(String(localized: "声音很小：把手机放到桌子中间、靠近说话的人，识别会准很多。"), symbol: "speaker.wave.1", color: .orange)
        }
    }

    /// Nothing louder than about -44 dBFS for the last few seconds, well into the meeting.
    private var isQuiet: Bool {
        recorder.isRecording && !recorder.isPaused && recorder.elapsed > 10 && (recorder.levels.max() ?? 0) < 0.12
    }

    private func banner(_ text: String, symbol: String, color: Color, close: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.footnote).foregroundStyle(CoveColor.text)
            Spacer(minLength: 0)
            if let close {
                Button(action: close) { Image(systemName: "xmark").font(.caption) }.foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(CoveColor.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(CoveColor.accent.opacity(recorder.isPaused ? 0.3 : 0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, CGFloat(level) * 36))
            }
        }
        .animation(.linear(duration: 0.1), value: recorder.levels)
    }

    private var captions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if loadingEngine {
                        Label(String(localized: "正在加载语音模型…"), systemImage: "hourglass").font(.subheadline).foregroundStyle(.secondary)
                    } else if engine == nil {
                        modelCard
                    }
                    ForEach(Array(transcript.segments.enumerated()), id: \.offset) { _, segment in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(clockString(segment.start))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Text(segment.text)
                                .foregroundStyle(CoveColor.text)
                        }
                    }
                    ForEach(Array(recorder.markers.filter { $0.kind == .note }.enumerated()), id: \.offset) { _, note in
                        Label("\(clockString(note.time))  \(note.text ?? "")", systemImage: "note.text")
                            .font(.subheadline)
                            .foregroundStyle(CoveColor.accent)
                    }
                    if !transcript.draft.isEmpty {
                        Text(transcript.draft)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 46)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding()
            }
            .onChange(of: transcript.segments.count) { withAnimation { proxy.scrollTo("end") } }
            .onChange(of: transcript.draft) { proxy.scrollTo("end") }
        }
    }

    @ViewBuilder
    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let engineError {
                Text(engineError).font(.subheadline).foregroundStyle(.secondary)
            } else if models.isDownloading {
                Text("\(models.phase)语音模型… \(Int(models.progress * 100))%").font(.subheadline)
                ProgressView(value: models.progress)
            } else {
                Text("实时字幕需要先下载语音模型（约 \(SpeechModels.totalMB) MB，只需一次）。录音不受影响，下载完成后字幕从那一刻开始；之前的部分可以在会后转录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("下载语音模型") { Task { await models.download() } }
                    .buttonStyle(.borderedProminent)
                    .tint(CoveColor.accent)
                if let error = models.error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .padding()
        .background(CoveColor.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var liveNotes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    if notes.isUpdating {
                        ProgressView().controlSize(.mini)
                        Text("正在更新…")
                    } else if let updatedAt = notes.updatedAt {
                        Text("更新于 \(updatedAt.formatted(date: .omitted, time: .standard))")
                    } else if notes.isAvailable {
                        Text("说到一定内容后自动生成，按设置里的刷新档位逐段追加。")
                    } else {
                        Text("还没有可用的模型接口。请到设置 → 模型接口添加。")
                    }
                    Spacer()
                    if notes.isAvailable, !notes.isUpdating, !transcript.segments.isEmpty {
                        Button("立即更新") { notes.consider(transcript.segments, force: true) }
                            .font(.caption)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let error = notes.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                MarkdownView(markdown: Citations.stripped(notes.notes))
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button { noteText = ""; writingNote = true } label: {
                    Label(String(localized: "笔记"), systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .modifier(GlassCapsule())
                }
                .buttonStyle(PressableStyle())
                ForEach(Marker.Kind.buttons, id: \.self) { kind in
                    Button { recorder.mark(kind); persist() } label: {
                        Label(kind.label, systemImage: kind.symbol)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .modifier(GlassCapsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            HStack(spacing: 40) {
                Button { recorder.togglePause() } label: {
                    Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .modifier(GlassCapsule())
                }
                .buttonStyle(PressableStyle())
                Button(action: finish) {
                    Image(systemName: "stop.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(CoveColor.accent, in: Circle())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .disabled(!recorder.isRecording || finishing)
        .padding(.vertical, 12)
    }

    // MARK: Flow

    private func begin() async {
        // Ask about sending the transcript now, not mid-meeting; saying no just leaves the running notes off.
        var provider = ProviderStore.shared.active
        if let active = provider, active.isUsable, !AIConsent.shared.isGranted(active) {
            do { try await AIConsent.shared.ensure(active) } catch { provider = nil }
        }
        notes.configure(provider: provider, language: SummaryLanguage(rawValue: language) ?? .auto, glossary: glossary,
                        refresh: LiveRefresh(rawValue: liveRefresh) ?? .standard)
        if Transcription.isReady { startEngine() }
        let meeting = Meeting(title: String(localized: "会议 \(Date.now.formatted(date: .abbreviated, time: .shortened))"))
        meeting.audioFileName = "\(meeting.id.uuidString).m4a"
        meeting.isRecording = true
        if let event = CalendarLink.currentEvent() {
            if !event.title.isEmpty {
                meeting.title = event.title
                meeting.titleIsFixed = true
            }
            meeting.attendees = event.attendees.joined(separator: "、")
        }
        await recorder.start(into: meeting.partsDirectory)
        guard recorder.isRecording else { return }
        context.insert(meeting)
        try? context.save()
        self.meeting = meeting
        coolDownIfHot()
    }

    /// Loads the chosen engine off the main thread (the open one reads ~300 MB of models;
    /// Apple's may first install its system model), then attaches to the recording from
    /// wherever it has got to by then.
    private func startEngine() {
        guard !loadingEngine, !cooledDown else { return }
        loadingEngine = true
        Task {
            defer { loadingEngine = false }
            do {
                let engine = try await Transcription.makeLive()
                engine.offset = recorder.elapsed
                engine.onUpdate = { update in
                    transcript.apply(update)
                    if !update.finished.isEmpty {
                        notes.consider(transcript.segments)
                        persist()
                    }
                }
                recorder.onSamples = { engine.accept($0) }
                self.engine = engine
            } catch {
                engineError = String(localized: "语音识别没能启动（\(error.localizedDescription)），本次只录音，会后可以再转录。")
            }
        }
    }

    /// Writes what there is so far to the library.
    private func persist() {
        guard let meeting, meeting.isRecording else { return }
        meeting.segments = transcript.segments
        meeting.markers = recorder.markers
        meeting.duration = recorder.elapsed
        if !notes.notes.isEmpty { meeting.liveNotes = notes.notes }
        try? context.save()
    }

    private func addNote() {
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        recorder.mark(.note, text: text)
        persist()
    }

    /// Serious: stop the running notes (network and the model). Critical: stop the live
    /// captions too so the recording itself keeps going; the meeting is transcribed again afterwards.
    private func coolDownIfHot() {
        let state = ProcessInfo.processInfo.thermalState
        if state == .serious || state == .critical { notes.isPaused = true }
        guard state == .critical, !cooledDown else { return }
        cooledDown = true
        recorder.onSamples = nil
        engine = nil
        meeting?.needsRetranscribe = true
        persist()
    }

    private func finish() {
        guard let meeting, let result = recorder.stop() else {
            dismiss()
            return
        }
        finishing = true
        meeting.markers = result.markers
        let complete: @Sendable () -> Void = {
            Task { @MainActor in
                meeting.segments = transcript.segments
                notes.cancel()
                if !notes.notes.isEmpty { meeting.liveNotes = notes.notes }
                if let url = meeting.audioURL, let duration = try? await AudioParts.join(meeting.partsDirectory, into: url) {
                    meeting.duration = duration
                } else {
                    meeting.duration = result.duration
                    meeting.audioFileName = nil
                }
                meeting.isRecording = false
                try? context.save()
                dismiss()
                onFinish(meeting)
            }
        }
        if let engine { engine.finish(complete) } else { complete() }
    }
}
