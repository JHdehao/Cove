import SwiftUI

/// Add or change one endpoint: address, format, key, model; fetch the model list and test it.
struct ProviderEditView: View {
    @State var config: ProviderConfig
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var models: [String] = []
    @State private var loadingModels = false
    @State private var testing = false
    @State private var result: (ok: Bool, text: String)?
    @State private var confirmDelete = false

    private var isNew: Bool { ProviderStore.shared.provider(config.id) == nil }
    private var preset: ProviderPreset? { ProviderPreset.named(config.presetID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $config.name)
                    TextField("接口地址", text: $config.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Picker("请求格式", selection: $config.wire) {
                        ForEach(WireFormat.allCases) { Text($0.label).tag($0) }
                    }
                    SecureField(preset?.needsKey == false ? "API Key（本地接口可留空）" : "API Key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    if let note = preset?.note, !note.isEmpty { Text(note) }
                }
                .coveCard()

                Section {
                    HStack {
                        TextField("模型", text: $config.model)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if loadingModels {
                            ProgressView()
                        } else {
                            Button("获取列表") { Task { await loadModels() } }
                                .buttonStyle(.borderless)
                        }
                    }
                    if !models.isEmpty {
                        Picker("从列表选择", selection: $config.model) {
                            if !models.contains(config.model) { Text(config.model.isEmpty ? "—" : config.model).tag(config.model) }
                            ForEach(models, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Stepper(value: $config.contextChars, in: 4000...1_000_000, step: config.contextChars >= 100_000 ? 50_000 : 4000) {
                        LabeledContent("单次最多字数", value: config.contextChars.formatted())
                    }
                    Toggle("本地模型", isOn: $config.isLocal)
                } header: {
                    Text("模型")
                } footer: {
                    Text("会议转录超过「单次最多字数」时先分段整理再合并，按模型的上下文长度设置（中文约 1 字 ≈ 1 token）。")
                }
                .coveCard()

                Section {
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("测试连接")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    .disabled(testing || !config.isUsable)
                    if let result {
                        Text(result.text)
                            .font(.callout)
                            .foregroundStyle(result.ok ? Color.green : Color.red)
                    }
                }
                .coveCard()

                if !isNew {
                    Section {
                        Button("删除这个接口", role: .destructive) { confirmDelete = true }
                    }
                    .coveCard()
                }
            }
            .coveGroupedBackground()
            .navigationTitle(isNew ? "添加接口" : config.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        ProviderStore.shared.save(config, key: key)
                        dismiss()
                    }
                    .disabled(URL(string: config.baseURL)?.host == nil)
                }
            }
            .confirmationDialog("删除这个接口？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    ProviderStore.shared.delete(config.id)
                    dismiss()
                }
            }
            .onAppear { key = config.apiKey }
            .onChange(of: config.model) { _, model in
                if config.presetID == "opencode-go" { config.wire = ProviderPreset.openCodeGoWire(for: model) }
            }
        }
    }

    /// The client for what's on screen, key included, before it's saved.
    private var client: LLMClient {
        var client = LLMClient(config)
        client.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return client
    }

    private func loadModels() async {
        loadingModels = true
        defer { loadingModels = false }
        do {
            models = try await client.listModels()
            if config.model.isEmpty, let first = models.first { config.model = first }
            result = (true, "找到 \(models.count) 个模型。")
        } catch {
            result = (false, error.localizedDescription)
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        let start = Date()
        do {
            let reply = try await client.complete(system: "只回复两个字母 OK。", messages: [.init(role: .user, content: "ping")], maxTokens: 200)
            let seconds = Date().timeIntervalSince(start).formatted(.number.precision(.fractionLength(1)))
            result = (true, "连接成功（\(seconds) 秒）：\(reply.prefix(60))")
        } catch {
            result = (false, error.localizedDescription)
        }
    }
}
