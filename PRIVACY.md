# Cove 隐私政策 / Privacy Policy

生效日期：2026-10-07

## 简体中文

Cove 是一款会议录音、转录与纪要 App。我们的原则是：**你的会议只属于你。**

**我们不收集任何数据。** Cove 没有账号系统，不包含任何统计、崩溃上报、广告或追踪 SDK，开发者无法看到你的录音、转录、纪要或使用情况。

**录音与转录只在本机。** 录音文件、转录文本、纪要和对话记录保存在你的设备上（App 的文稿目录与数据库），语音识别在设备上离线完成。删除会议或删除 App 即删除这些数据。它们会随你自己的 iCloud / 电脑备份一起备份。

**生成纪要时的数据流向（由你决定）。** 纪要、实时纪要和会议对话需要语言模型。你可以选择：
- **Apple 本机模型**（Apple 智能）：在设备上运行，不发送任何内容；
- **你自己的本地模型**（如电脑上的 Ollama、LM Studio）：转录只发送到你填写的地址；
- **云端服务**（如 Anthropic、OpenAI、Google、DeepSeek 等）：转录会通过 HTTPS 发送到你选择的服务处理，使用你自己的 API Key，适用该服务的隐私政策。**第一次向某个云端服务发送前，App 会明确询问并征得你的同意**，你可以随时在 设置 → 隐私 中撤回。

**API Key** 保存在系统钥匙串中，只用于向对应服务发起请求。

**内购。** Cove Pro 通过 Apple 的 App 内购买完成，付款和账户信息由 Apple 处理，开发者收不到你的姓名、邮箱或付款信息；App 只在本机读取「是否已购买」。

**模型下载。** 开源语音模型从 GitHub / Hugging Face 官方地址下载，下载过程不附带任何个人信息。

**权限。** 麦克风（录音）、提醒事项（你主动导入待办时）、日历（你在设置里打开「从日历带入会议信息」时）、本地网络（连接局域网中的模型接口时）。均只在对应功能中使用。

**录音合规。** 部分国家和地区要求在录音前取得所有参与者同意。请在录音前告知参会者，并遵守当地法律。

**儿童。** Cove 不面向 13 岁以下儿童，也不收集任何儿童信息。

**联系方式。** 有问题请在 https://github.com/JHdehao/Cove/issues 提出。政策如有变更会更新本页面。

## English

Cove records, transcribes and summarizes meetings. **We collect no data**: there is no account, analytics, crash reporting, advertising or tracking. Recordings, transcripts, minutes and chats stay on your device; speech recognition runs on device. Minutes are written by a language model you choose: Apple's on-device model (nothing leaves the device), your own local server, or a cloud provider using your own API key — in which case the transcript is sent over HTTPS to that provider under its privacy policy, **only after you explicitly agree the first time**; you can withdraw this in Settings → Privacy. API keys are kept in the system Keychain. Cove Pro is bought through Apple's In-App Purchase; Apple handles payment and the developer receives no personal or payment information. Please tell participants before recording and follow local law. Contact: https://github.com/JHdehao/Cove/issues
