import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage(SummaryKey.template) private var templateID = "general"
    @AppStorage(SummaryKey.language) private var language = SummaryLanguage.auto.rawValue
    @AppStorage(SummaryKey.customPrompt) private var customPrompt = ""
    @AppStorage(SummaryKey.glossary) private var glossary = ""
    @AppStorage(SummaryKey.auto) private var autoSummarize = true
    @State private var store = ProviderStore.shared
    @State private var models = SpeechModels.shared
    @State private var adding = false
    @State private var editing: ProviderConfig?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.providers) { provider in
                        HStack {
                            Button {
                                store.activeID = provider.id
                            } label: {
                                HStack {
                                    Image(systemName: store.activeID == provider.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(store.activeID == provider.id ? CoveColor.accent : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(provider.name)
                                            if provider.isLocal { CoveTag(text: "本地") }
                                        }
                                        Text(provider.model.isEmpty ? "未选模型" : provider.model)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .foregroundStyle(CoveColor.text)
                            Spacer()
                            Button { editing = provider } label: { Image(systemName: "info.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button { adding = true } label: { Label("添加接口", systemImage: "plus") }
                } header: {
                    Text("模型接口")
                } footer: {
                    Text("纪要、实时纪要和对话用选中的接口。云端 API（Claude、OpenAI、DeepSeek…）与本地模型（Ollama、LM Studio 等任何 OpenAI 兼容接口）都可以。")
                }
                .coveCard()

                Section {
                    if models.isInstalled {
                        LabeledContent("X-ASR + SenseVoice + Silero VAD", value: "已下载")
                        Button("删除语音模型", role: .destructive) { models.remove() }
                    } else if models.isDownloading {
                        ProgressView(value: models.progress) { Text("\(models.phase)… \(Int(models.progress * 100))%") }
                    } else {
                        Button("下载语音模型（约 \(SpeechModels.totalMB) MB）") { Task { await models.download() } }
                        if let error = models.error { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                } header: {
                    Text("语音识别（本机）")
                } footer: {
                    Text("全部开源、在手机上离线运行，录音不会上传：X-ASR 流式识别（中英，约 0.2 秒出字）边说边出字幕，SenseVoice 在每句话结束时重读一遍定稿（中、英、粤、日、韩）。")
                }
                .coveCard()

                Section {
                    Toggle("转录完成后自动生成纪要", isOn: $autoSummarize)
                    Picker("默认模板", selection: $templateID) {
                        ForEach(SummaryTemplate.builtIn) { Text($0.name).tag($0.id) }
                        Text("自定义").tag(SummaryTemplate.custom)
                    }
                    Picker("纪要语言", selection: $language) {
                        ForEach(SummaryLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    NavigationLink("自定义模板") {
                        TextPage(title: "自定义模板", text: $customPrompt,
                                 hint: "写你想要的纪要结构，比如：\n## 背景\n## 结论\n## 待办\n标题、一句话结论和出处标注会自动加上。")
                    }
                    NavigationLink("术语表") {
                        TextPage(title: "术语表", text: $glossary,
                                 hint: "人名、项目名、专业词，一行一个。转录认错时，模型会按这里纠正。")
                    }
                } header: {
                    Text("纪要")
                }
                .coveCard()

                Section {
                    Picker("外观", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } footer: {
                    Text(AppInfo.version).frame(maxWidth: .infinity).padding(.top, 16)
                }
                .coveCard()
            }
            .coveGroupedBackground()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .sheet(isPresented: $adding) { PresetPicker { editing = ProviderConfig(preset: $0) } }
            .sheet(item: $editing) { ProviderEditView(config: $0) }
        }
    }
}

/// Pick where a new endpoint starts from.
struct PresetPicker: View {
    let onPick: (ProviderPreset) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("云端 API") { rows(ProviderPreset.all.filter { !$0.isLocal && !$0.id.hasPrefix("custom") }) }
                    .coveCard()
                Section("本地模型") { rows(ProviderPreset.all.filter(\.isLocal)) }
                    .coveCard()
                Section("其他") { rows(ProviderPreset.all.filter { $0.id.hasPrefix("custom") }) }
                    .coveCard()
            }
            .coveGroupedBackground()
            .navigationTitle("添加接口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func rows(_ presets: [ProviderPreset]) -> some View {
        ForEach(presets) { preset in
            Button {
                dismiss()
                // Let this sheet close before the editor opens.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onPick(preset) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).foregroundStyle(CoveColor.text)
                    if !preset.baseURL.isEmpty {
                        Text(preset.baseURL).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// A full-page text editor for longer settings.
struct TextPage: View {
    let title: String
    @Binding var text: String
    let hint: String

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text).frame(minHeight: 260)
            } footer: {
                Text(hint)
            }
            .coveCard()
        }
        .coveGroupedBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
