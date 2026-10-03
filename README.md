# Cove

会议录音 → 手机本机实时转录 → 会中实时纪要 → 散会即出结构化纪要 → 和会议对话。Claude 风格界面，SwiftUI，iOS 18+。

- **转录在本机**：[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 两段式——[X-ASR](https://github.com/Gilgamesh-J/X-ASR) 流式出字（约 0.2 秒），SenseVoice 句末定稿，Silero VAD 断句；离线运行，录音不上传。
- **总结用你自己的模型接口**：Claude、OpenAI、Gemini、DeepSeek、通义千问、Kimi、智谱、OpenRouter，或本地 Ollama / LM Studio / 任何 OpenAI 兼容接口。
- 纪要每条结论带出处，点一下跳到原话并播放。

## 许可证

本项目以 **GNU Affero General Public License v3.0（AGPL-3.0-only）** 发布，见 [LICENSE](LICENSE)。修改后分发，或以网络服务方式提供，都必须以同一许可证公开完整源码。

## 第三方组件

| 组件 | 许可证 | 方式 |
|---|---|---|
| sherpa-onnx | Apache-2.0 | Swift Package 依赖 |
| onnxruntime | MIT | sherpa-onnx 的依赖 |
| X-ASR-zh-en 模型 | Apache-2.0 | 运行时由用户下载，本仓库不分发 |
| SenseVoice 模型（FunAudioLLM） | 模型自带许可（见其模型仓库） | 运行时由用户下载，本仓库不分发 |
| Silero VAD 模型 | MIT | 运行时由用户下载，本仓库不分发 |
