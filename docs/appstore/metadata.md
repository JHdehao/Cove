# App Store 文案

## 名称（30 字符内）
Cove

## 副标题（30 字符内）
本机转录的会议纪要，每句可溯源

## 推广文本（170 字符内）
录音在手机上转成文字，不上传；散会即出结构化纪要，每条结论点一下就回到原话核对。用 Apple 本机模型，或你自己的 Claude / OpenAI / DeepSeek / 本地 Ollama，不按分钟收费。

## 描述
Cove 把会议录音变成可以直接发出去的纪要——而且每一条都能核对。

【转录在你的手机上完成】
• 开源语音模型（X-ASR）或苹果系统识别，离线运行，录音和文字都不离开手机
• 边说边出字幕，约 0.2 秒延迟；会议室远场也能听清（自动增益）
• 会后本机识别说话人，长按改成真名
• 不限时长，不按分钟收费

【散会即出纪要】
• 结论、决策、待办（负责人 + 截止时间）、未决问题、按议题分章节
• 每条结论带出处：点一下跳到原话并播放录音，AI 有没有说错一目了然
• 会中手记几个关键词，纪要会围绕它们展开
• 通用会议、站会、1:1、客户访谈、需求评审、课程、面试，或写你自己的模板
• 会议进行中就有实时纪要，迟到的人看一眼就跟上

【和会议对话】
• 「张三对预算怎么说的？」「把待办整理成跟进邮件」——回答同样带出处

【模型由你选】
• Apple 本机模型：不联网、零配置
• 你自己的 API：Claude、OpenAI、Gemini、DeepSeek、通义千问、Kimi、智谱、OpenRouter
• 电脑上的本地模型：Ollama、LM Studio 或任何 OpenAI 兼容接口
• 第一次把会议内容发到某个云端服务前，都会先征得你的同意

【录得稳】
• 锁屏、后台持续录音；来电、换耳机后自动接上
• 录音每分钟落盘一次，App 被关掉也只丢最后一分钟，重开自动恢复

【顺手的小事】
• 待办一键导入提醒事项；日历自动带入会议标题和参会人
• 纪要自动导出 Markdown 到你选的文件夹（比如 Obsidian）
• 导入语音备忘录、音视频文件或已有字幕

Cove 开源（AGPL-3.0），不收集任何数据：没有账号、没有统计、没有广告。

请在录音前告知参会者，并遵守当地关于录音的法律。

## 关键词（100 字符内，逗号分隔）
会议纪要,录音转文字,语音转写,会议记录,转录,AI总结,说话人,离线,本地,待办,录音笔,字幕,Claude,DeepSeek

## 类别
主要：效率（Productivity）　次要：商务（Business）

## 版权
© 2026 JHdehao

## 审核备注（App Review Information → Notes）
Cove records meetings, transcribes them on device, and writes minutes with a language model the user chooses. No account or login is required.

How to review quickly:
1. On the empty home screen tap "看看示例会议" (View sample meeting). It opens a finished meeting: the minutes (纪要), transcript with speakers (转录) and a Q&A chat (对话). Tap any blue timestamp in the minutes to jump to the source line in the transcript.
2. Tap the red microphone button to record. A one-time reminder asks the user to inform participants. On iOS 26 live captions use Apple's built-in speech recognizer with nothing to download; the open-source engine (X-ASR, ~370 MB, downloaded from GitHub/Hugging Face) is optional in Settings.
3. Minutes after recording: if Apple Intelligence is enabled on the device, the on-device Apple model is set up automatically, so minutes are generated with no configuration and nothing leaves the device. Otherwise the user adds their own model endpoint in Settings → 模型接口 (e.g. Anthropic, OpenAI, or a local Ollama server) with their own API key.

Privacy: recordings and transcripts stay on device. Before meeting content is first sent to any third-party AI service, the app shows an explicit consent prompt naming the service; consent can be withdrawn in Settings → 隐私. The developer collects no data (no analytics, no crash reporting, no ads).

Background audio (UIBackgroundModes: audio) is used only to keep recording a meeting while the screen is locked or another app is in front.

Local network permission is used only when the user points the app at a model server on their own network (e.g. Ollama on a computer).

## 隐私政策 URL
https://github.com/JHdehao/Cove/blob/main/PRIVACY.md

## 技术支持 URL
https://github.com/JHdehao/Cove/issues
