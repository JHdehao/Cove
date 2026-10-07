import Foundation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device language model (Apple Intelligence, iOS 26): nothing to set up, nothing
/// leaves the phone, but a small context (about 4,000 tokens), so long meetings are written
/// up in many small parts (see `Summarizer`). Offered whenever the device has it switched on.
enum AppleModel {
    static let baseURL = "apple://on-device"
    static let modelID = "apple-on-device"

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Why it can't be used, for Settings.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible): return String(localized: "这台设备不支持 Apple 智能。")
            case .unavailable(.appleIntelligenceNotEnabled): return String(localized: "请先在系统设置里打开 Apple 智能。")
            case .unavailable(.modelNotReady): return String(localized: "Apple 智能模型还在下载，稍后再试。")
            default: return String(localized: "Apple 智能暂不可用。")
            }
        }
        #endif
        return String(localized: "需要 iOS 26 和支持 Apple 智能的设备。")
    }

    static func stream(system: String, messages: [ChatMessage], yield: (String) -> Void) async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let session = LanguageModelSession(instructions: system)
            let prompt = messages.count == 1
                ? messages[0].content
                : messages.map { "\($0.role == .user ? "用户" : "助手")：\($0.content)" }.joined(separator: "\n\n")
            var sent = ""
            do {
                // Each snapshot is the reply so far; pass on what's new.
                for try await snapshot in session.streamResponse(to: prompt) {
                    let text = snapshot.content
                    if text.hasPrefix(sent) { yield(String(text.dropFirst(sent.count))) }
                    sent = text
                }
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize(_) = error {
                    throw LLMError.service(String(localized: "内容超出了苹果本机模型能处理的长度。可以把接口的「单次最多字数」调小，或换用云端 / 电脑上的模型。"))
                }
                if case .guardrailViolation(_) = error {
                    throw LLMError.service(String(localized: "苹果本机模型拒绝处理这段内容（安全限制）。可以换用其他模型接口。"))
                }
                throw LLMError.service(String(localized: "苹果本机模型出错：\(error.localizedDescription)"))
            }
            return
        }
        #endif
        throw LLMError.service(unavailableReason ?? String(localized: "苹果本机模型不可用。"))
    }
}

/// Meeting content leaves the phone only after the user has agreed, once per service
/// (App Review Guideline 5.1.2(i): say which third-party AI gets personal data, and ask first).
/// Local endpoints and Apple's on-device model need no asking.
@MainActor @Observable
final class AIConsent {
    static let shared = AIConsent()

    struct Request: Identifiable {
        let id = UUID()
        let name: String
        let host: String
        let continuation: CheckedContinuation<Bool, Never>
    }

    private(set) var pending: Request?
    private static let key = "ai.consent.hosts"
    private var hosts: Set<String> = Set(UserDefaults.standard.stringArray(forKey: AIConsent.key) ?? [])

    nonisolated static func exempt(_ config: ProviderConfig) -> Bool {
        config.isLocal || config.wire == .appleOnDevice
    }

    func isGranted(_ config: ProviderConfig) -> Bool {
        Self.exempt(config) || hosts.contains(config.host)
    }

    /// Asks if needed (one question at a time); throws if the user says no.
    func ensure(_ config: ProviderConfig) async throws {
        while pending != nil { try await Task.sleep(for: .milliseconds(200)) }
        if isGranted(config) { return }
        let agreed = await withCheckedContinuation { pending = Request(name: config.name, host: config.host, continuation: $0) }
        if !agreed { throw LLMError.consentDeclined(config.name) }
    }

    func answer(_ agreed: Bool) {
        guard let request = pending else { return }
        pending = nil
        if agreed {
            hosts.insert(request.host)
            UserDefaults.standard.set(Array(hosts), forKey: Self.key)
        }
        request.continuation.resume(returning: agreed)
    }

    var grantedHosts: [String] { hosts.sorted() }

    func revokeAll() {
        hosts = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

/// Shows the question whenever some part of the app is about to send meeting content.
struct AIConsentPrompt: ViewModifier {
    @State private var consent = AIConsent.shared

    func body(content: Content) -> some View {
        content.alert(
            "发送到 \(consent.pending?.name ?? "")？",
            isPresented: Binding(get: { consent.pending != nil }, set: { if !$0 { consent.answer(false) } })
        ) {
            Button("同意并发送") { consent.answer(true) }
            Button("不发送", role: .cancel) { consent.answer(false) }
        } message: {
            let name = consent.pending?.name ?? ""
            let host = consent.pending?.host ?? ""
            Text("生成纪要、实时纪要和对话需要把会议转录（可能包含人名、公司信息等个人数据）发送到「\(name)」（\(host)）处理，适用该服务自己的隐私政策。Cove 本身不收集任何数据。\n\n只问这一次，可在设置 → 隐私里撤回。")
        }
    }
}
