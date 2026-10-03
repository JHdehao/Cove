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
    @AppStorage(SummaryKey.language) private var language = SummaryLanguage.auto.rawValue
    @AppStorage(SummaryKey.glossary) private var glossary = ""
    @State private var recorder = Recorder()
    @State private var transcript = LiveTranscript()
    @State private var notes = LiveSummarizer()
    @State private var models = SpeechModels.shared
    @State private var engine: SpeechEngine?
    @State private var engineError: String?
    @State private var tab = Tab.captions
    @State private var finishing = false
    @State private var confirmDiscard = false

    enum Tab: String, CaseIterable {
        case captions = "实时字幕"
        case notes = "实时纪要"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
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
        .task { await begin() }
        .onChange(of: models.isInstalled) { _, installed in
            // Models finished downloading mid-meeting: captions start from here.
            if installed, engine == nil, recorder.isRecording { startEngine(offset: recorder.elapsed) }
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
                    Label(recorder.isPaused ? "已暂停" : "录音中", systemImage: "circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(recorder.isPaused ? Color.secondary : CoveColor.accent)
                }
            }
            Text(clockString(recorder.elapsed))
                .font(.system(size: 44, weight: .light, design: .serif).monospacedDigit())
                .foregroundStyle(CoveColor.text)
            waveform.frame(height: 36)
        }
        .padding(.horizontal)
        .padding(.top, 8)
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
                    if engine == nil { modelCard }
                    ForEach(Array(transcript.segments.enumerated()), id: \.offset) { _, segment in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(clockString(segment.start))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            Text(segment.text)
                                .foregroundStyle(CoveColor.text)
                        }
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
                Text("正在下载语音模型… \(Int(models.progress * 100))%").font(.subheadline)
                ProgressView(value: models.progress)
            } else {
                Text("实时字幕需要先下载语音模型（SenseVoice，约 240 MB，只需一次）。录音不受影响，下载完成后字幕从那一刻开始；之前的部分可以在会后转录。")
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
                        Text("说到一定内容后自动生成，约每半分钟更新一次。")
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
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Marker.Kind.allCases, id: \.self) { kind in
                    Button { recorder.mark(kind) } label: {
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
        notes.configure(provider: ProviderStore.shared.active, language: SummaryLanguage(rawValue: language) ?? .auto, glossary: glossary)
        if models.isInstalled { startEngine(offset: 0) }
        await recorder.start()
    }

    private func startEngine(offset: TimeInterval) {
        do {
            let engine = try SpeechEngine(offset: offset)
            engine.onUpdate = { update in
                transcript.apply(update)
                if !update.finished.isEmpty { notes.consider(transcript.segments) }
            }
            recorder.onSamples = { engine.accept($0) }
            self.engine = engine
        } catch {
            engineError = "语音模型加载失败，本次只录音，会后可以再转录。"
        }
    }

    private func finish() {
        guard let result = recorder.stop() else {
            dismiss()
            return
        }
        let meeting = Meeting(title: "会议 \(Date.now.formatted(date: .abbreviated, time: .shortened))")
        meeting.audioFileName = result.fileName
        meeting.duration = result.duration
        meeting.markers = result.markers
        guard let engine else {
            close(with: meeting)
            return
        }
        finishing = true
        engine.finish {
            Task { @MainActor in
                meeting.segments = transcript.segments
                close(with: meeting)
            }
        }
    }

    private func close(with meeting: Meeting) {
        notes.cancel()
        meeting.liveNotes = notes.notes
        dismiss()
        onFinish(meeting)
    }
}
