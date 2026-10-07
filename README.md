# Cove

会议录音 → 手机本机实时转录 → 会中实时纪要 → 散会即出结构化纪要 → 和会议对话。Claude 风格界面，SwiftUI，iOS 18+。

- **转录在本机**：[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 两段式——[X-ASR](https://github.com/Gilgamesh-J/X-ASR) 流式出字（约 0.2 秒），X-ASR 离线版句末定稿，自动增益让远处的声音也能听清，Silero VAD 断句；离线运行，录音不上传。
- **总结用你自己的模型接口**：Claude、OpenAI、Gemini、DeepSeek、通义千问、Kimi、智谱、OpenRouter，或本地 Ollama / LM Studio / 任何 OpenAI 兼容接口。
- 纪要每条结论带出处，点一下跳到原话并播放。
- **说话人识别在本机**：会后用 pyannote 分割 + 3D-Speaker 声纹分出「说话人 1/2/3」，长按改名；转录逐句可改。
- **录得稳**：每分钟落盘一段，App 被杀最多丢一分钟、重开自动恢复；来电、换耳机自动接续；过热自动降级。
- **零配置可用**：iOS 26 默认苹果系统识别，Apple 智能开着时自动用 Apple 本机模型写纪要；空状态可打开示例会议。
- 界面七语：简体中文、繁體中文、English、日本語、한국어、Русский、العربية。
- **Cove Pro**（一次性 0.99 美元）只解锁说话人识别，其余全部免费；自行编译加 `COVE_UNLOCKED` 即解锁。
- 会中手写笔记（纪要围绕它展开）、待办确认后导入提醒事项、日历带入标题与参会人、纪要自动导出到文件夹（Obsidian）。

## 隐私

不收集任何数据（无账号、统计、崩溃上报、广告）。会议内容第一次发往某个云端模型服务前逐服务征得同意，可在设置里撤回。见 [PRIVACY.md](PRIVACY.md)。

## 上架

清单与文案在 [`docs/appstore/`](docs/appstore/RELEASE.md)；`appstore.yml` 云端签名上传 TestFlight，`screenshots.yml` 自动出商店截图。

## 许可证

本项目以 **GNU Affero General Public License v3.0（AGPL-3.0-only）** 发布，见 [LICENSE](LICENSE)。修改后分发，或以网络服务方式提供，都必须以同一许可证公开完整源码。

## 第三方组件

| 组件 | 许可证 | 方式 |
|---|---|---|
| sherpa-onnx | Apache-2.0 | Swift Package 依赖 |
| onnxruntime | MIT | sherpa-onnx 的依赖 |
| X-ASR-zh-en 模型 | Apache-2.0 | 运行时由用户下载，本仓库不分发 |
| Silero VAD 模型 | MIT | 运行时由用户下载，本仓库不分发 |
