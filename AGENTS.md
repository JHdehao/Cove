# Cove 仓库约定（Codex / Claude Code 通用）

Cove：会议录音 → 本机实时转录（sherpa-onnx：X-ASR 流式 + SenseVoice 定稿）→ 实时纪要 / 会后纪要 / 对话（云 API 或本地模型接口）。SwiftUI，iOS 18+。计划与进度见 `PLAN.md`。

- 本机没有 Xcode / Swift，**无法本地编译**；靠 GitHub Actions（`.github/workflows/build-ipa.yml`）编译出无签名 IPA，流程照搬 Conch（`~/data/projects/Conch/HANDOFF.md`）。
- 新 .swift 放 `Cove/` 下即可（`PBXFileSystemSynchronizedRootGroup`，不用登记）。
- Bundle ID `com.tj.cove.CK5DY89VN5`。
- 样式统一用 `Cove/Style/CoveStyle.swift`（Claude 昼/夜配色，与 Conch 一致）。
- 模型接口层：`Cove/AI/LLMClient.swift`（三种请求格式 + SSE 流式），预设在 `Provider.swift`。加服务商 = 加一个 `ProviderPreset`。
- 正则字面量用 `#/…/#`（Swift 5 模式下裸 `/…/` 需额外开关）。
- 下载源一律境外官方（HuggingFace / GitHub），不用国内镜像。
