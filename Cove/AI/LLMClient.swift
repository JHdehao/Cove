import Foundation

struct ChatMessage: Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var role: Role
    var content: String
}

enum LLMError: LocalizedError {
    case http(Int, String)
    case badResponse
    case invalidURL
    case notConfigured
    case service(String)

    var errorDescription: String? {
        switch self {
        case .http(let status, let body):
            switch status {
            case 401: "API Key 无效或已过期（401）。请到设置 → 模型接口检查。"
            case 403: "没有权限访问这个模型（403）。"
            case 404: "接口地址或模型名不对（404）。\n\(body.prefix(300))"
            case 429: "请求太频繁或额度用完了（429），稍后再试。"
            case 503, 529: "服务暂时繁忙（\(status)），稍后再试。"
            default: "服务返回错误（\(status)）：\(body.prefix(400))"
            }
        case .badResponse: "无法解析服务的响应。"
        case .invalidURL: "接口地址格式不正确。"
        case .notConfigured: "还没有可用的模型接口。请到设置 → 模型接口添加一个，并选好模型。"
        case .service(let message): message
        }
    }
}

/// Talks to one endpoint in its own wire format. Replies are streamed as text deltas.
struct LLMClient: Sendable {
    let config: ProviderConfig
    var apiKey: String

    init(_ config: ProviderConfig) {
        self.config = config
        apiKey = config.apiKey
    }

    private var base: String {
        var base = config.baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        // Anthropic paths start with /v1; an OpenAI-style base often already ends in it.
        if config.wire == .anthropic, base.hasSuffix("/v1") { base = String(base.dropLast(3)) }
        return base
    }

    private var headers: [String: String] {
        var headers = ["User-Agent": "Cove/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")"]
        switch config.wire {
        case .anthropic:
            headers["anthropic-version"] = "2023-06-01"
            if !apiKey.isEmpty { headers["x-api-key"] = apiKey }
        case .chatCompletions, .responses:
            if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        }
        return headers
    }

    // MARK: Models

    /// The service's model ids (GET /v1/models, or /models on OpenAI-style APIs).
    func listModels() async throws -> [String] {
        let path = config.wire == .anthropic ? "/v1/models?limit=100" : "/models"
        guard let url = URL(string: base + path) else { throw LLMError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 15)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw LLMError.http(status, String(decoding: data, as: UTF8.self)) }
        guard let list = try JSONValue.parse(data)["data"]?.array else { throw LLMError.badResponse }
        // Gemini's OpenAI layer names them "models/gemini-…"; requests take the bare id.
        return list.compactMap { $0["id"]?.string.map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 } }.sorted()
    }

    // MARK: Completion

    /// The whole reply at once.
    func complete(system: String, messages: [ChatMessage], maxTokens: Int = 8000) async throws -> String {
        var text = ""
        for try await delta in stream(system: system, messages: messages, maxTokens: maxTokens) { text += delta }
        return text
    }

    /// The reply as it's written, a piece at a time.
    func stream(system: String, messages: [ChatMessage], maxTokens: Int = 8000) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(system: system, messages: messages, maxTokens: maxTokens) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(system: String, messages: [ChatMessage], maxTokens: Int, yield: (String) -> Void) async throws {
        guard config.isUsable else { throw LLMError.notConfigured }
        let history: [JSONValue] = messages.map { ["role": .string($0.role.rawValue), "content": .string($0.content)] }
        let path: String
        var body: [String: JSONValue] = ["model": .string(config.model), "stream": true]
        switch config.wire {
        case .anthropic:
            path = "/v1/messages"
            body["system"] = .string(system)
            body["messages"] = .array(history)
            body["max_tokens"] = .number(Double(maxTokens))
        case .chatCompletions:
            path = "/chat/completions"
            body["messages"] = .array([["role": "system", "content": .string(system)]] + history)
            body["max_tokens"] = .number(Double(maxTokens))
        case .responses:
            path = "/responses"
            body["instructions"] = .string(system)
            body["input"] = .array(history)
            body["store"] = false
            body["max_output_tokens"] = .number(Double(maxTokens))
        }
        guard let url = URL(string: base + path) else { throw LLMError.invalidURL }

        // A model may think for minutes before the first word; a long meeting takes a while to write up.
        var request = URLRequest(url: url, timeoutInterval: 600)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = JSONValue.object(body).encoded()

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 4000 { break }
            }
            throw LLMError.http(status, Self.errorMessage(data))
        }

        var sawData = false
        var plain = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else {
                // A server that ignored "stream": the whole JSON reply comes as ordinary lines.
                if !sawData { plain += line + "\n" }
                continue
            }
            sawData = true
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let event = JSONValue.parse(payload) else { continue }
            if let message = event["error"]?["message"]?.string ?? event["error"]?.string {
                throw LLMError.service(message)
            }
            switch config.wire {
            case .anthropic:
                if event["type"]?.string == "content_block_delta", event["delta"]?["type"]?.string == "text_delta",
                   let text = event["delta"]?["text"]?.string { yield(text) }
            case .chatCompletions:
                if let text = event["choices"]?.array?.first?["delta"]?["content"]?.string { yield(text) }
            case .responses:
                switch event["type"]?.string {
                case "response.output_text.delta":
                    if let text = event["delta"]?.string { yield(text) }
                case "response.failed":
                    throw LLMError.service(event["response"]?["error"]?["message"]?.string ?? "生成失败。")
                default:
                    break
                }
            }
        }
        if !sawData {
            guard let reply = JSONValue.parse(plain) else { throw LLMError.badResponse }
            yield(Self.text(of: reply))
        }
    }

    /// The text of a non-streamed reply in any of the three formats.
    private static func text(of reply: JSONValue) -> String {
        if let blocks = reply["content"]?.array {
            return blocks.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }.joined()
        }
        if let text = reply["choices"]?.array?.first?["message"]?["content"]?.string { return text }
        if let output = reply["output"]?.array {
            return output.flatMap { $0["content"]?.array ?? [] }
                .compactMap { $0["type"]?.string == "output_text" ? $0["text"]?.string : nil }.joined()
        }
        return ""
    }

    private static func errorMessage(_ data: Data) -> String {
        if let json = try? JSONValue.parse(data),
           let message = json["error"]?["message"]?.string ?? json["error"]?.string ?? json["message"]?.string {
            return message
        }
        return String(decoding: data, as: UTF8.self)
    }
}
