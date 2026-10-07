import Foundation
import Observation

/// The request format an endpoint speaks.
enum WireFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Anthropic Messages (`/v1/messages`). Also offered by some other services.
    case anthropic
    /// OpenAI Chat Completions (`/chat/completions`): nearly every cloud service, Ollama, LM Studio, vLLM, LiteLLM.
    case chatCompletions
    /// OpenAI Responses (`/responses`): OpenAI's newer models.
    case responses
    /// Apple's on-device model (`AppleModel`); no address or key.
    case appleOnDevice

    /// The formats a user can pick for an endpoint they add themselves.
    static let network: [WireFormat] = [.anthropic, .chatCompletions, .responses]

    var id: String { rawValue }

    var label: String {
        switch self {
        case .anthropic: "Anthropic Messages"
        case .chatCompletions: "Chat Completions"
        case .responses: "Responses"
        case .appleOnDevice: String(localized: "Apple 本机")
        }
    }
}

/// A starting point for a new endpoint. Model names change often, so most presets
/// leave the model empty and the user picks one from the service's own list.
struct ProviderPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let baseURL: String
    let wire: WireFormat
    var model = ""
    var needsKey = true
    var isLocal = false
    /// Characters of transcript one request may carry before long meetings are summarized in parts.
    var contextChars = 120_000
    var note = ""

    static let apple = ProviderPreset(id: "apple", name: String(localized: "Apple 本机模型"), baseURL: AppleModel.baseURL, wire: .appleOnDevice,
                                      model: AppleModel.modelID, needsKey: false, isLocal: true, contextChars: 1800,
                                      note: String(localized: "Apple 智能自带的模型，在手机上运行，不联网、不用 Key。上下文较小，长会议会分很多段整理，纪要质量不如大模型。"))

    static let all: [ProviderPreset] = [
        ProviderPreset(id: "anthropic", name: "Claude（Anthropic）", baseURL: "https://api.anthropic.com", wire: .anthropic,
                       model: "claude-sonnet-5-5", contextChars: 300_000),
        ProviderPreset(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", wire: .responses, contextChars: 200_000),
        ProviderPreset(id: "gemini", name: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
                       wire: .chatCompletions, contextChars: 400_000),
        ProviderPreset(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", wire: .chatCompletions,
                       model: "deepseek-chat", contextChars: 100_000),
        ProviderPreset(id: "qwen", name: String(localized: "通义千问（阿里云国际）"), baseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
                       wire: .chatCompletions, contextChars: 150_000),
        ProviderPreset(id: "kimi", name: "Kimi（Moonshot）", baseURL: "https://api.moonshot.ai/v1", wire: .chatCompletions,
                       contextChars: 150_000),
        ProviderPreset(id: "glm", name: String(localized: "智谱 GLM（Z.ai）"), baseURL: "https://api.z.ai/api/paas/v4", wire: .chatCompletions,
                       contextChars: 150_000),
        ProviderPreset(id: "opencode-go", name: "OpenCode Go", baseURL: "https://opencode.ai/zen/go/v1", wire: .chatCompletions,
                       contextChars: 150_000,
                       note: String(localized: "订阅 Go 后在 OpenCode 控制台取 Key。选模型时按官方文档自动切换请求格式，可以手动改：MiniMax、Qwen 走 Anthropic Messages，Grok、Muse、GPT 走 Responses，其余走 Chat Completions。")),
        ProviderPreset(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", wire: .chatCompletions,
                       contextChars: 150_000),
        ProviderPreset(id: "ollama", name: String(localized: "Ollama（本地）"), baseURL: "http://192.168.1.2:11434/v1", wire: .chatCompletions,
                       needsKey: false, isLocal: true, contextChars: 24_000,
                       note: String(localized: "电脑上 Ollama 要监听 0.0.0.0（OLLAMA_HOST=0.0.0.0），手机经 Tailscale 或同一 Wi-Fi 访问。上下文长度按模型的 num_ctx 调整。")),
        ProviderPreset(id: "lmstudio", name: String(localized: "LM Studio（本地）"), baseURL: "http://192.168.1.2:1234/v1", wire: .chatCompletions,
                       needsKey: false, isLocal: true, contextChars: 24_000,
                       note: String(localized: "在 LM Studio 的 Developer 页打开 Serve on Local Network。")),
        ProviderPreset(id: "custom-openai", name: String(localized: "自定义（OpenAI 兼容）"), baseURL: "", wire: .chatCompletions, needsKey: false,
                       note: String(localized: "vLLM、LiteLLM、llama.cpp server、one-api 等都可以用这个。")),
        ProviderPreset(id: "custom-anthropic", name: String(localized: "自定义（Anthropic 兼容）"), baseURL: "", wire: .anthropic),
    ]

    static func named(_ id: String) -> ProviderPreset? { id == apple.id ? apple : all.first { $0.id == id } }

    /// OpenCode Go serves each model family in its own format (opencode.ai/docs/go).
    static func openCodeGoWire(for model: String) -> WireFormat {
        let id = model.lowercased()
        if ["minimax", "qwen"].contains(where: id.hasPrefix) { return .anthropic }
        if ["grok", "muse", "gpt"].contains(where: id.hasPrefix) { return .responses }
        return .chatCompletions
    }
}

/// One saved endpoint. The API key lives in the Keychain, keyed by `id`.
struct ProviderConfig: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var presetID: String
    var baseURL: String
    var wire: WireFormat
    var model: String
    var isLocal: Bool
    var contextChars: Int

    init(preset: ProviderPreset) {
        name = preset.name
        presetID = preset.id
        baseURL = preset.baseURL
        wire = preset.wire
        model = preset.model
        isLocal = preset.isLocal
        contextChars = preset.contextChars
    }

    var keyAccount: String { "provider-key-\(id.uuidString)" }
    var apiKey: String { Keychain.string(for: keyAccount) ?? "" }

    /// Ready to send: an address and a model.
    var isUsable: Bool {
        if wire == .appleOnDevice { return AppleModel.isAvailable }
        return URL(string: baseURL)?.host != nil && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var host: String { URL(string: baseURL)?.host ?? baseURL }
}

/// The saved endpoints and which one summaries use.
@MainActor @Observable
final class ProviderStore {
    static let shared = ProviderStore()

    private(set) var providers: [ProviderConfig] = []
    var activeID: UUID? {
        didSet { UserDefaults.standard.set(activeID?.uuidString, forKey: Self.activeKey) }
    }

    private static let listKey = "providers.v1"
    private static let activeKey = "providers.active"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.listKey),
           let list = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            providers = list
        }
        activeID = UserDefaults.standard.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:))
        // Works out of the box where Apple Intelligence is on: minutes without setting anything up.
        if providers.isEmpty, AppleModel.isAvailable {
            providers = [ProviderConfig(preset: .apple)]
            persist()
        }
        if active == nil { activeID = providers.first?.id }
    }

    var active: ProviderConfig? { providers.first { $0.id == activeID } }

    func provider(_ id: UUID?) -> ProviderConfig? { providers.first { $0.id == id } }

    func save(_ config: ProviderConfig, key: String?) {
        if let index = providers.firstIndex(where: { $0.id == config.id }) {
            providers[index] = config
        } else {
            providers.append(config)
        }
        if let key {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { Keychain.delete(config.keyAccount) } else { try? Keychain.set(trimmed, for: config.keyAccount) }
        }
        if active == nil { activeID = config.id }
        persist()
    }

    func delete(_ id: UUID) {
        guard let config = provider(id) else { return }
        Keychain.delete(config.keyAccount)
        providers.removeAll { $0.id == id }
        if activeID == id { activeID = providers.first?.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: Self.listKey)
        }
    }
}
