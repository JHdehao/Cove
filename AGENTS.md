# Cove 仓库约定（Codex / Claude Code 通用）

Cove：会议录音 → 本机实时转录（sherpa-onnx：X-ASR 流式出草稿 + X-ASR 离线定稿，自动增益）→ 实时纪要 / 会后纪要 / 对话（云 API 或本地模型接口）。SwiftUI，iOS 18+。计划与进度见 `PLAN.md`。

- 本机没有 Xcode / Swift，**无法本地编译**；靠 GitHub Actions（`.github/workflows/build-ipa.yml`）编译出无签名 IPA，流程照搬 Conch（`~/data/projects/Conch/HANDOFF.md`）。
- **出包装机：`tools/ipa.sh`**（要求 HEAD 已 push）：等 CI 绿 → oci 从 GitHub 拉产物 → 发布 SideStore 源 `https://jhai.cc.cd/<令牌>/cove/source.json`（令牌在仓库外 `~/.config/conch/sidestore-token`，与 Conch 共用 oci 上的 conch-www.service 与 cloudflared 规则；仓库公开，令牌绝不能进仓库）。版本号 = `0.1.<CI 运行序号>`，设置页底部显示 build 号和提交号。
- 新 .swift 放 `Cove/` 下即可（`PBXFileSystemSynchronizedRootGroup`，不用登记）。
- Bundle ID `com.tj.cove.CK5DY89VN5`。
- 样式统一用 `Cove/Style/CoveStyle.swift`（Claude 昼/夜配色，与 Conch 一致）。
- 模型接口层：`Cove/AI/LLMClient.swift`（三种请求格式 + SSE 流式），预设在 `Provider.swift`。加服务商 = 加一个 `ProviderPreset`。
- 正则字面量用 `#/…/#`（Swift 5 模式下裸 `/…/` 需额外开关）。
- 下载源一律境外官方（HuggingFace / GitHub），不用国内镜像。
- **界面七语**（简 / 繁 / 英 / 日 / 韩 / 俄 / 阿）：SwiftUI 字面量自动本地化，`String` 类型的文案一律 `String(localized:)`。加了新文案就跑 `export-strings.yml` 取编译器生成的准确 key（插值变 `%@` / `%lld`），在 `Cove/Localizable.xcstrings` 补齐七语；源语言 en，key 是中文原文（zh-Hans 值 = key）。繁体用 `opencc -c s2twp.json` 出初稿。
- **Cove Pro**（`App/Pro.swift`）：非消耗型内购，只锁说话人识别，其余功能保持免费。SideStore 包 `COVE_UNLOCKED` 直接解锁。上架清单 `docs/appstore/RELEASE.md`。
