import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage(SummaryKey.template) private var templateID = "general"
    @AppStorage(SummaryKey.language) private var language = SummaryLanguage.auto.rawValue
    @AppStorage(SummaryKey.customPrompt) private var customPrompt = ""
    @AppStorage(SummaryKey.glossary) private var glossary = ""
    @AppStorage(SummaryKey.auto) private var autoSummarize = true
    @AppStorage(SummaryKey.liveRefresh) private var liveRefresh = LiveRefresh.standard.rawValue
    @State private var store = ProviderStore.shared
    @State private var models = SpeechModels.shared
    @AppStorage(SpeechKey.engine) private var speechEngine = Transcription.defaultEngine.rawValue
    @AppStorage(SpeechKey.appleLanguage) private var appleLanguage = AppleSpeechLanguage.mandarin.rawValue
    @State private var adding = false
    @State private var consent = AIConsent.shared
    @State private var speakers = SpeakerModels.shared
    @AppStorage(SpeakerKey.auto) private var autoDiarize = true
    @AppStorage(CalendarLink.key) private var calendarLink = false
    @State private var exportFolder = AutoExport.folder?.lastPathComponent
    @State private var choosingFolder = false
    @State private var settingsError: String?
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
                    if Transcription.appleSupported {
                        Picker("识别引擎", selection: $speechEngine) {
                            ForEach(TranscriptionEngine.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    }
                    if Transcription.engine == .apple {
                        Picker("识别语言", selection: $appleLanguage) {
                            ForEach(AppleSpeechLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    } else if models.isInstalled {
                        LabeledContent("X-ASR 流式 + 离线 + Silero VAD", value: "已下载")
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
                    if Transcription.engine == .apple {
                        Text("苹果系统自带的识别（iOS 26），在手机上离线运行，录音不会上传。不用下载模型（首次使用某种语言时系统会自动准备），比开源引擎省电，支持粤语、日语、韩语；不开源。")
                    } else {
                        Text("全部开源、在手机上离线运行，录音不会上传：X-ASR 流式识别边说边出字幕（约 0.2 秒），每句话结束时用 X-ASR 离线版重读一遍定稿。支持普通话和英语（含中英混说）。")
                    }
                }
                .coveCard()

                Section {
                    if speakers.isInstalled {
                        Toggle("会后自动识别说话人", isOn: $autoDiarize)
                        Button("删除说话人模型", role: .destructive) { speakers.remove() }
                    } else if speakers.isDownloading {
                        ProgressView(value: speakers.progress) { Text("正在下载… \(Int(speakers.progress * 100))%") }
                    } else {
                        Button("下载说话人模型（约 \(SpeakerModels.totalMB) MB）") { Task { await speakers.download() } }
                        if let error = speakers.error { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                } header: {
                    Text("说话人识别（本机）")
                } footer: {
                    Text("会后在手机上分出「说话人 1 / 2 / 3」，长按转录里的名字可改成真名。人数已知时，在会议页菜单里指定人数会更准。模型：pyannote 分割 + 3D-Speaker 声纹，开源。")
                }
                .coveCard()

                Section {
                    Toggle("从日历带入标题和参会人", isOn: Binding(get: { calendarLink }, set: { on in
                        if on {
                            Task { calendarLink = await CalendarLink.requestAccess() }
                        } else {
                            calendarLink = false
                        }
                    }))
                    if let exportFolder {
                        LabeledContent("自动导出到", value: exportFolder)
                        Button("停止自动导出", role: .destructive) {
                            AutoExport.clear()
                            self.exportFolder = nil
                        }
                    } else {
                        Button("自动导出纪要到文件夹…") { choosingFolder = true }
                    }
                } header: {
                    Text("联动")
                } footer: {
                    Text("开录时如果日历里正好有会，会议用它的标题，参会人名单帮助纪要认人。自动导出：每次生成纪要后，把 Markdown 写进你选的文件夹（比如 iCloud 里的 Obsidian 库）。")
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
                    Picker("实时纪要刷新", selection: $liveRefresh) {
                        ForEach(LiveRefresh.allCases) { Text($0.label).tag($0.rawValue) }
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
                    LabeledContent("录音与转录", value: "只存在本机")
                    if !consent.grantedHosts.isEmpty {
                        LabeledContent("已同意发送到", value: consent.grantedHosts.joined(separator: "、"))
                        Button("撤回所有发送同意", role: .destructive) { consent.revokeAll() }
                    }
                    Link("隐私政策", destination: AppLinks.privacy)
                } header: {
                    Text("隐私")
                } footer: {
                    Text("Cove 不收集任何数据，没有账号、统计或广告。生成纪要时，会议转录只发送到你自己选的模型接口；第一次发送到某个云端服务前会先问你。")
                }
                .coveCard()

                Section {
                    Link("源代码（GitHub）", destination: AppLinks.source)
                    NavigationLink("开源许可") { LicensesView() }
                    Link("反馈问题", destination: AppLinks.issues)
                } header: {
                    Text("关于")
                } footer: {
                    Text("Cove 以 GNU AGPL-3.0 开源。")
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
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                do {
                    try AutoExport.setFolder(try result.get())
                    exportFolder = AutoExport.folder?.lastPathComponent
                } catch {
                    settingsError = error.localizedDescription
                }
            }
            .alert("出错了", isPresented: Binding(get: { settingsError != nil }, set: { if !$0 { settingsError = nil } })) {
                Button("好") {}
            } message: {
                Text(settingsError ?? "")
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
                Section("本地模型") { rows((AppleModel.isAvailable ? [ProviderPreset.apple] : []) + ProviderPreset.all.filter(\.isLocal)) }
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

enum AppLinks {
    static let source = URL(string: "https://github.com/JHdehao/Cove")!
    static let privacy = URL(string: "https://github.com/JHdehao/Cove/blob/main/PRIVACY.md")!
    static let issues = URL(string: "https://github.com/JHdehao/Cove/issues")!
}

/// The open-source parts Cove is built from, and their licenses.
struct LicensesView: View {
    private let items: [(String, String, String)] = [
        ("sherpa-onnx", "Apache-2.0", "https://github.com/k2-fsa/sherpa-onnx"),
        ("ONNX Runtime", "MIT", "https://github.com/microsoft/onnxruntime"),
        ("X-ASR-zh-en 语音模型", "Apache-2.0", "https://github.com/Gilgamesh-J/X-ASR"),
        ("Silero VAD", "MIT", "https://github.com/snakers4/silero-vad"),
        ("pyannote segmentation 3.0", "MIT", "https://huggingface.co/pyannote/segmentation-3.0"),
        ("3D-Speaker CAM++", "Apache-2.0", "https://github.com/modelscope/3D-Speaker"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(items, id: \.0) { name, license, url in
                    Link(destination: URL(string: url)!) {
                        LabeledContent(name, value: license)
                    }
                    .foregroundStyle(CoveColor.text)
                }
            } footer: {
                Text("语音模型由 App 在使用时从官方地址下载，不随 App 分发。")
            }
            .coveCard()
        }
        .coveGroupedBackground()
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
    }
}
