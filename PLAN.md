# Cove —— 会议转录与总结 App（计划）

> 2026-10-04 立项，尚未开工。名字暂定 Cove（海湾，和 Conch 同一系列），可改。
> 定位：**录音 → 本机实时字幕 → 会中实时纪要 → 散会即出结构化纪要 → 和会议对话**。转录用开源模型在本机跑，总结走云 API 或本地模型接口。

---

## 0. 进度（2026-10-04）

M0–M3 + M5 部分**代码已写完，未编译**（本机无 Xcode，等 GitHub 仓库建好后由 CI 编译）。
- 已有：录音（AVAudioEngine，16 kHz AAC）、本机实时字幕、会中实时纪要、会后纪要（模板 / 出处跳转 / 长会议分段）、对话、导入音频与转录文本、播放跟随、待办导入提醒事项、Markdown / SRT 导出、模型接口管理（预设 + 获取模型列表 + 测试连接）、语音模型下载。
- 2026-10-04 SideStore 源已通（build 6 起），出包用 `tools/ipa.sh`。
- 2026-10-04 加入可切换识别引擎：开源 X-ASR（默认，iOS 18+）/ 苹果 SpeechAnalyzer（iOS 26+，免下载、省电、多语言，闭源），待真机 A/B 对比准确率。
- 未做：说话人分离（M4）、实时活动 / 灵动岛、Mac 版、跨会议搜索。

## 1. 关键决策（2026-10-04 用户定）

| 项 | 决定 |
|---|---|
| 形态 | **独立 App**，SwiftUI，iOS 18+；出包照搬 Conch（CI → SideStore 源） |
| 转录 | 开源模型**在手机本机**跑：sherpa-onnx 1.13.8（官方 SPM 包）；X-ASR 流式出字 + SenseVoice 句末定稿 + Silero VAD（见 §2.0） |
| 总结 / 对话 | **云 API**，同时支持**本地模型接口**；App 内置接口层，三种请求格式全部流式 |
| 实时性 | 用户要求「转录和总结尽可能实时」：录音时实时字幕 + 会中滚动纪要，散会即出完整纪要 |
| UI | Claude 昼/夜配色，与 Conch 同一套样式（`Cove/Style/CoveStyle.swift`） |

## 2. 实时链路（2026-10-04 改为两段式流式）

```
麦克风 ─ AVAudioEngine tap ─ 重采样 16 kHz ─┬─ 写 AAC 文件
                                            └─ SpeechEngine（串行队列）
                                                 ├─ X-ASR 流式（160 ms 一块）→ 灰色草稿字幕，约 0.2 s 出字
                                                 └─ Silero VAD 判句末（静音 0.5 s）→ SenseVoice 重读整句 → 定稿行
定稿行 ─ LiveSummarizer：新增 ≥280 字且距上次 ≥30 s → 发「当前笔记 + 新增行」→ 流式更新实时纪要
停止 ─ flush 最后一句 → 打开会议页 → 自动用完整转录生成正式纪要（流式）
```

### 2.0 转录模型选型（2026-10-04 社区调研）

| 模型 | 发布 | 流式 | 大小（int8） | 中文会议 CER | 结论 |
|---|---|---|---|---|---|
| **X-ASR-zh-en**（上交 / 复旦 / 华科等，Apache-2.0，约 100 万小时数据） | 2026-06 | ✅ 160/480/960/1920 ms | 128 MB | 160 ms：10.5%；480 ms：9.1%（WenetSpeech-meeting） | **选用：实时字幕** |
| SenseVoice-small | 2024 / 2025-09 | ❌（非自回归，单句约 0.1 s） | 237 MB | 6.5% | 原用于句末定稿，实测远场不如 X-ASR 离线版，已换掉（见 §2.0.1） |
| Qwen3-ASR 0.6B / 1.7B | 2026-01 | ❌ | 837 MB（0.6B） | 6.9% / 5.5% | 更准但大、慢（大模型解码），手机实时不划算 |
| Nemotron 3.5 ASR Streaming 0.6B（NVIDIA） | 2026-06 | ✅ 80 ms 起 | 453 MB | 普通话约 19%（FLEURS） | 中文太弱，不用 |
| Fun-ASR-Nano / FireRedASR2 / MiMo-V2.5-ASR | 2025-12 ~ 2026-04 | ❌ | 0.5–7.6B | — | 太大，留作会后服务器精修候选 |


**HuggingFace 补充调研（2026-10-04，按 trending / 本周点赞）**

| 模型 | 发布 | 大小 | 中文 | WenetSpeech-meeting CER（160 ms 流式，有道评测） | 适合 |
|---|---|---|---|---|---|
| **网易有道 Confucius4-R2T2**（基于 Qwen3-ASR，真流式 80 ms–2 s，只追加不回改，支持热词 / 上下文） | 2026-09 | 2B（GGUF Q4_K_M 可用） | ✅ 中英优化 | **7.27** | 服务器（RTX 3060 够用）；模型许可为有道自有协议，月活 1 亿以下免费 |
| Audio8-ASR-Infinite（Voxtral 音频塔 + Qwen2.5-3B，语义 VAD，无限时长） | 2026-09 | 4B（bf16 8.2 GB） | ✅ 中英 | AISHELL-4 会议 2.9（480 ms，自报） | 服务器；Apache-2.0；预览版 |
| X-ASR-zh-en | 2026-06 | 160M（int8 128 MB） | ✅ | 11.33 | **手机端**，同量级里中文流式最好 |
| Nemotron 3.5 Streaming / Voxtral Realtime | 2026 | 0.6B / 4B | 弱 | 20.18 / 60.54 | 不用 |
| Phonon-2、Parakeet Ultra/Redux、Cactus Whistle | 2026-09 | 17–180 MB | ❌ 仅英语 / 欧洲语言 | — | 不适用 |

**微软 VibeVoice-ASR 系列（2026-10-04 补查，MIT 许可）**：
- VibeVoice-ASR-Streaming 7B / 1.5B（2026-09）：边转写边标说话人，但平均延迟约 2 秒（2.9 s 分块）；微软自己的表里 AISHELL-1 CER 4.01，不如 X-ASR 的 3.61；7B 需约 17 GB 显存，3060 放不下 → 不用于实时字幕。
- VibeVoice-ASR（2026-01，8.7B，非流式）：60 分钟音频一次处理，同时出说话人、时间戳、文字，支持热词；VibeVoice-ASR-BitNet（2026-07，1.6 GB，CPU 实时）是它的压缩版，配 VibeASR.cpp → **M4「会后说话人分离 + 精修」候选**，可在 omarchy CPU 上跑，不占显卡。

### 2.0.1 omarchy 实测（2026-10-04）

测试集：AISHELL-4 官方测试集 M_R003S01C01（6 人会议，会议室远场阵列第 1 路，带东北口音），前 10 分钟，参考答案取官方逐句人工转录（82 段 2207 字）。CER 统一去标点、数字逐位转汉字。脚本与结果在 `~/data/ai/cove-asr/`（`run_phone_pipeline.py`、`r2t2_client.py`、`cer.py`、`out/`）。

| 方案 | CER | 备注 |
|---|---|---|
| **X-ASR 流式 + X-ASR 离线定稿 + 自动增益 + VAD 阈值 0.3** | **13.46%** | **改为 App 默认**；电脑上 10 分钟音频 103 s 跑完，流式每 0.1 s 块平均 14 ms |
| X-ASR 流式单独（加增益） | 14.18% | 草稿质量 |
| X-ASR 流式 + SenseVoice 定稿 + 增益 + 阈值 0.3 | 16.99% | |
| X-ASR 流式 + SenseVoice 定稿（原 App 设置，无增益，阈值 0.5） | 58.68% | 录音只有约 -43 dBFS，VAD 漏掉一半语音 → 定稿只出 1018/2207 字 |
| 有道 R2T2 流式（官方默认：不开服务端 VAD，zhen） | 17.13% | RTX 3060，显存 9.9 GB；每 160 ms 块服务端耗时平均 86 ms |
| 有道 R2T2（开服务端 VAD） | 21.30% | |
| 有道 R2T2（增益后音频） | 19.62% | |
| 微软 VibeVoice-ASR-BitNet（CPU，3 分钟片段） | 94–113% | 反复复读 / 编造内容；3 分钟就占 36.7 GB 内存，10 分钟被 OOM 杀掉；没有输出说话人 |

结论：
1. 手机端改为 X-ASR 双模型（流式草稿 + 离线定稿）+ 自动增益 + VAD 阈值 0.3。代价：SenseVoice 的粤语 / 日语 / 韩语支持没了，只剩普通话和英语。
2. 「家里电脑加速」不做：R2T2 在远场会议上不比手机端准，还要占 9.9 GB 显存。
3. 说话人分离不用 VibeVoice-BitNet，M4 改用 sherpa-onnx 自带的离线分离（pyannote 分割 + 声纹聚类）再实测。
4. 只测了一段远场录音，近讲（手机就在说话人面前）时各模型排名可能不同，真机上再验证。

结论：手机端没有比 X-ASR 更合适的中文小流式模型；想再提升准确率，下一步是「家里电脑加速」——omarchy 上跑 R2T2 的 WebSocket 流式服务，手机经 Tailscale 推 PCM，连得上用服务器结果，连不上自动回落本机。

- 旧方案（SenseVoice 每 0.5 s 重读整句做草稿）的延迟是「0.5 s 攒音频 + 重读时间」，句子越长越慢；改为 X-ASR 真流式后草稿延迟恒定在一块（160 ms）加解码几毫秒。
- X-ASR int8 只以 `.tar.bz2` 发布（GitHub sherpa-onnx asr-models），App 内用系统 libbz2 + 流式 tar 解析解出（`Speech/ModelArchive.swift`，逻辑已用 Python 移植版对真实压缩包验证）。
- 语音模型合计约 370 MB。

## 2.1 模型接口（`Cove/AI/`）

- 请求格式：Anthropic Messages / OpenAI Chat Completions / OpenAI Responses，全部 SSE 流式；服务端不支持流式时自动按整段 JSON 解析。
- 预设：Claude、OpenAI、Gemini、DeepSeek、通义千问（国际站）、Kimi、智谱 Z.ai、OpenRouter；本地 Ollama（默认 `http://omarchy:11434/v1`，经 Tailscale）、LM Studio；自定义 OpenAI / Anthropic 兼容（vLLM、LiteLLM、llama.cpp…）。
- 多个接口并存，一个设为当前；API Key 存钥匙串；本地接口可不填 Key；ATS 已放开 http。
- 出处标注：模型输出 `[#12]` → App 渲染成可点的时间戳，跳到转录第 12 行并播放。

## 3. 功能清单

### 3.1 录制
- 一键录音，**锁屏 / 灵动岛实时活动**显示时长、电平、最新一句字幕（复用 Conch 的 `ConchWidgets` 模式）。
- 后台持续录音，来电 / 打断后自动恢复；分段写盘（每 30 秒一个文件），崩溃不丢录音。
- 录制中**打标记**：⭐ 重点、✅ 待办、❓ 疑问，一点即落在时间轴上，总结时优先引用。
- 录制中**随手笔记**：文字笔记带时间戳，与转录合并。
- 输入源：内置麦克风 / 蓝牙耳机 / 外接麦；Mac 版可录系统音频 + 麦克风（线上会议）。
- 导入：语音备忘录、文件 App 里的音频视频（m4a/mp3/wav/mp4/mov），分享扩展「用 Cove 转录」。

### 3.2 转录
- 实时字幕（手机端流式），会后自动用离线模型重转一遍提精度（可选再交给 omarchy 精修）。
- 说话人分离：「说话人 1/2/3」→ 可重命名；**声纹库**记住常见同事，下次自动认出。
- 词级时间戳：点任一句跳到音频对应位置；播放时当前句高亮跟随；0.75–2× 倍速；跳过静音。
- 热词 / 术语表：人名、项目名、专业词，传给模型做 hotword 提升识别率，并在纠错时优先匹配。
- 手动校对：直接改文字，改动保留，重新总结时用改后的版本。
- 中英混说、粤语；自动识别语言。

### 3.3 总结（核心卖点）
- **模板**：通用会议 / 站会 / 1:1 / 客户访谈 / 需求评审 / 课程讲座 / 面试 / 自定义（用户写提示词，可保存）。
- 结构化输出：
  - 一句话结论 + 要点摘要
  - **决策**（谁定的、几分几秒）
  - **待办**（负责人、截止时间、出处时间戳）→ 一键导入「提醒事项」
  - 未决问题 / 风险
  - 按议题分章节（自动切章，带时间范围，可当目录跳转）
- 每条结论都带**出处引用**（点击跳到原话），防止模型编造。
- 长会议分段总结再合并；总结可重新生成、可选模型、可流式显示（Claude 风的打字效果）。

### 3.4 和会议对话
- 每场会议一个对话页（复用 Conch 助手的对话 UI 与输入栏）：「张三对预算怎么说的？」「把待办整理成邮件」。
- 跨会议问答：「上个月关于 A 项目的所有决定」——bge-m3 检索 + LLM 回答，带出处。
- 上下文占比圈圈（Conch 已有实现）。

### 3.5 资料库
- 列表按日期分组，卡片显示标题、时长、参会人、一句话摘要。
- 自动标题（LLM 根据内容起）；可关联日历事件，自动带入标题与参会人。
- 文件夹 / 标签、全文搜索 + 语义搜索、收藏。
- 导出：Markdown、PDF、DOCX、SRT/VTT 字幕、纯文本、原始音频；系统分享面板。

### 3.6 隐私与设置
- 默认全部本地；用 omarchy 处理时明示「将发送到 omarchy」。
- 可选 Face ID 锁、音频保留期限（如 30 天后只留文字）。
- 模型管理页：下载 / 删除手机端模型，显示占用空间。
- 模型接口设置：多个云端 / 本地接口，选当前、获取模型列表、测试连接。

## 4. UI（Claude 风，和 Conch 一致）

- 配色：Claude 昼 `canvas #FAF9F5 / grouped #F5F4EE / card #FFFFFF / 文字 #3D3929`；Claude 夜 `canvas #262624 / grouped #1F1E1D / card #2B2A27 / 文字 #E8E6DC`；强调色赤陶 `#D97757`。
- 直接复用 Conch 的 `CurrentTheme`、`conchGroupedBackground()`、`conchCard()`、`conchCanvas()`、`ConchTag`、`GlassCapsule`（iOS 26 液态玻璃）、`PressableStyle`。
- 页面：
  - **首页**：资料库列表（分组卡片）+ 底部居中赤陶色圆形录音键（液态玻璃底座）。
  - **录音页**：全屏 canvas，中间是随音量起伏的赤陶色波形，下方滚动实时字幕，底部胶囊按钮组（标记 / 笔记 / 暂停 / 结束）。
  - **会议详情**：顶部分段控件「纪要 / 转录 / 对话」；纪要用衬线标题 + 正文排版（像 Claude 的回答）；转录按说话人分色（取主题 ansi 色）；底部悬浮迷你播放条。
  - 说话人标签、语言、引擎等小标识统一用 `ConchTag`。
- 文案三语（简 / 英 / 繁），沿用 Conch 的 `tools/add-strings.py`。

## 5. 架构

```
Cove/
  App/        入口、版本信息
  AI/         Provider（预设 / 已存接口 / 钥匙串）、LLMClient（三格式流式）
  Speech/     SpeechModels（模型下载）、SpeechEngine（VAD + SenseVoice、文件转录、重采样）
  Recording/  Recorder（AVAudioEngine 录音 + 送转录）、AudioPlayer
  Summary/    模板、Summarizer（会后纪要、出处、分段）、LiveSummarizer（会中滚动纪要）
  Models/     Meeting（SwiftData）、TranscriptImport（txt/srt/vtt）、Exporter
  Views/      会议列表、录音页、会议详情（纪要/转录/对话）、设置
  Style/      CoveStyle（Claude 昼/夜）
```
- 存储：SwiftData；音频在 Documents/Recordings（文件 App 可见）；模型在 Application Support/Models（不进 iCloud 备份）。
- 依赖只有 sherpa-onnx 官方 Swift 包（含 onnxruntime 预编译 xcframework）。

## 6. 里程碑

| 阶段 | 内容 | 验收 |
|---|---|---|
| M0 骨架 | 新仓库、CI 出包、SideStore 源、复制样式与主题、空页面 | 手机装上，昼/夜主题和 Conch 一致 |
| M1 录音 | 后台录音、分段写盘、实时活动、标记、导入文件 | 锁屏录 1 小时不中断，杀 App 不丢 |
| M2 手机端转录 | sherpa-onnx 集成：VAD + 流式字幕 + SenseVoice 离线 + 说话人分离；播放跟随 | 飞行模式下完成一场会议转录 |
| M3 总结 | 模板、结构化纪要、出处引用、待办导出提醒事项 | 30 分钟会议纪要的每条都能点回原话 |
| M4 说话人 | sherpa-onnx 离线分离（pyannote 分割 + 3D-Speaker 声纹），会后跑；声纹库认人 | 3 人会议说话人标对 |
| M5 对话与检索 | 会议内对话、跨会议语义搜索、导出 | 「上周谁答应了什么」能答且带出处 |
| M6 Mac 版 | 系统音频录制、菜单栏快捷录制 | 线上会议双声道录全 |

## 7. 风险 / 待定

- SideStore 签名 7 天有效期（Conch 同样问题），长期用要定期续签。
- iOS 后台录音需 `audio` 后台模式；长时间录音 + 实时转写的耗电与发热要实测，必要时录音时只跑 VAD、会后再转。
- 语音模型 240 MB，首次在 App 内从 HuggingFace / GitHub 下载（国内网络可能需要代理）。
- 本地模型接口：电脑上的 Ollama 要监听 0.0.0.0，手机经 Tailscale 访问；omarchy 现在只有 bge-m3，跑纪要要先拉一个对话模型（如 Qwen3 14B，Q4 约 9 GB）。
- 首次加载 SenseVoice 在主线程，可能卡顿约 1 秒，待真机实测后再挪到后台。
- 待用户定：App 名字（暂定 Cove）。
