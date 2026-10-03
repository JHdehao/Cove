import AVFoundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Home: every meeting, newest first, grouped by day, with the record button at the bottom.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @State private var path: [Meeting] = []
    @State private var search = ""
    @State private var showSettings = false
    @State private var showRecorder = false
    @State private var showPaste = false
    @State private var importing: [UTType]?
    @State private var importError: String?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if meetings.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .coveGroupedBackground()
            .navigationTitle("会议")
            .searchable(text: $search, prompt: "搜索标题、纪要、转录")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { importing = [.audio, .movie] } label: { Label("导入录音 / 视频", systemImage: "waveform") }
                        Button { importing = Self.transcriptTypes } label: { Label("导入转录文件（txt / srt / vtt）", systemImage: "doc.text") }
                        Button { showPaste = true } label: { Label("粘贴转录文本", systemImage: "doc.on.clipboard") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { recordButton }
            .navigationDestination(for: Meeting.self) { MeetingDetailView(meeting: $0) }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPaste) {
            PasteTranscriptView { title, text in addImported(title: title, text: text) }
        }
        .fullScreenCover(isPresented: $showRecorder) {
            RecordView { meeting in
                context.insert(meeting)
                path = [meeting]
            }
        }
        .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                      allowedContentTypes: importing ?? []) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let title = url.deletingPathExtension().lastPathComponent
                if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .audiovisualContent) {
                    try addAudio(title: title, from: url)
                } else {
                    addImported(title: title, text: try String(contentsOf: url, encoding: .utf8))
                }
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("导入失败", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("好") {}
        } message: {
            Text(importError ?? "")
        }
    }

    static let transcriptTypes: [UTType] = [.plainText, .text] + ["srt", "vtt", "md"].compactMap { UTType(filenameExtension: $0) }

    private func addImported(title: String, text: String) {
        let segments = TranscriptImport.parse(text)
        guard !segments.isEmpty else {
            importError = "没有读到内容。"
            return
        }
        let meeting = Meeting(title: title.isEmpty ? "导入的会议" : title)
        meeting.segments = segments
        meeting.duration = segments.last?.end ?? 0
        context.insert(meeting)
        path = [meeting]
    }

    /// Copies the file in; the meeting page transcribes it on device.
    private func addAudio(title: String, from url: URL) throws {
        let name = "\(UUID().uuidString).\(url.pathExtension.lowercased())"
        try FileManager.default.copyItem(at: url, to: Meeting.audioDirectory.appending(path: name))
        let meeting = Meeting(title: title)
        meeting.audioFileName = name
        if let file = try? AVAudioFile(forReading: Meeting.audioDirectory.appending(path: name)) {
            meeting.duration = Double(file.length) / file.processingFormat.sampleRate
        }
        context.insert(meeting)
        path = [meeting]
    }

    private var filtered: [Meeting] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return meetings }
        return meetings.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query)
                || $0.segments.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    private var list: some View {
        let days = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.createdAt) }
        return List {
            ForEach(days.keys.sorted(by: >), id: \.self) { day in
                Section {
                    ForEach(days[day] ?? []) { meeting in
                        NavigationLink(value: meeting) { MeetingRow(meeting: meeting) }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            guard let meeting = days[day]?[index] else { continue }
                            meeting.deleteAudio()
                            context.delete(meeting)
                        }
                    }
                } header: {
                    Text(day.formatted(.dateTime.month().day().weekday()))
                }
                .coveCard()
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(CoveColor.accent)
            Text("还没有会议")
                .font(.system(.title3, design: .serif).weight(.semibold))
            Text("点下方按钮开始录音，或从右上角导入转录文本。\n纪要由你在设置里配置的模型接口生成。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    private var recordButton: some View {
        Button { showRecorder = true } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(CoveColor.accent, in: Circle())
                .padding(8)
                .modifier(GlassCapsule())
        }
        .buttonStyle(PressableStyle())
        .padding(.bottom, 8)
    }
}

struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(meeting.title.isEmpty ? "未命名会议" : meeting.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if meeting.summary.isEmpty { CoveTag(text: meeting.segmentsData.isEmpty ? "未转录" : "未总结") }
            }
            if !meeting.gist.isEmpty {
                Text(meeting.gist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("\(meeting.createdAt.formatted(date: .omitted, time: .shortened)) · \(clockString(meeting.duration))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// Paste a transcript copied from elsewhere (another app's export, a chat log).
struct PasteTranscriptView: View {
    let onDone: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题（可空，总结后自动起）", text: $title)
                }
                .coveCard()
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 280)
                        .font(.callout)
                } footer: {
                    Text("每行一句；行首可带「[00:12:34]」时间和「张三：」说话人。也支持直接粘贴 SRT / VTT 字幕。")
                }
                .coveCard()
            }
            .coveGroupedBackground()
            .navigationTitle("粘贴转录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        onDone(title, text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
