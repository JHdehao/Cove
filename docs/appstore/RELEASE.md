# 上架 App Store：清单

代码侧已就绪（隐私清单、权限说明、ATS、出口合规、第三方 AI 同意、隐私政策、示例会议、上传与截图流水线）。下面是**只能由账号持有人做**的步骤，按顺序。

## 1. 账号与 App 记录（一次性）
1. 加入 Apple Developer Program（个人 99 美元/年）。记下 **Team ID**（developer.apple.com → Membership）。
2. developer.apple.com → Identifiers → 注册 App ID：`com.jhdehao.cove`（或自定，记得同步到仓库变量 `BUNDLE_ID`）。Capabilities 不用勾任何项。
3. App Store Connect → 我的 App → 新建：名称 `Cove`（被占用可用 `Cove 会议纪要`），主要语言 简体中文，Bundle ID 选上一步的，SKU 填 `cove`。
4. App Store Connect → 用户和访问 → 集成 → App Store Connect API → 生成密钥，角色选 **管理（Admin）**（云端自动签名需要）。下载 `AuthKey_XXXX.p8`（只能下载一次），记下 Key ID 与 Issuer ID。

## 2. 仓库密钥（一次性）
GitHub → Cove → Settings → Secrets and variables → Actions：
| 名称 | 类型 | 值 |
|---|---|---|
| `APPLE_TEAM_ID` | Secret | Team ID |
| `ASC_KEY_ID` | Secret | Key ID |
| `ASC_ISSUER_ID` | Secret | Issuer ID |
| `ASC_KEY_P8` | Secret | `base64 -w0 AuthKey_XXXX.p8` 的输出 |
| `BUNDLE_ID` | Variable（可选） | 默认 `com.jhdehao.cove` |

## 3. 出包上传
Actions → **App Store (TestFlight upload)** → Run workflow，填版本号（首发 `1.0.0`）。10–30 分钟后在 TestFlight 里出现，可先装到自己手机真机验收（见 §5）。

## 4. 商店页面
- 文案：`docs/appstore/metadata.md`（名称、副标题、描述、关键词、审核备注都已写好，直接粘贴）。
- 截图：Actions → **App Store screenshots** → Run，下载产物 `Cove-screenshots`：iPhone 6.9" 与 iPad 13" 各 4 张（资料库 / 纪要 / 转录 / 对话），昼夜两套任选。
- 隐私政策 URL：`https://github.com/JHdehao/Cove/blob/main/PRIVACY.md`
- 技术支持 URL：`https://github.com/JHdehao/Cove/issues`
- App 隐私（营养标签）：选 **「不收集数据」**。依据：无账号、无统计/崩溃上报/广告 SDK；转录只在用户主动选择、逐服务同意后发给用户自己配置的模型服务，开发者不经手。
- 年龄分级：问卷全部选「无」；如问到生成式 AI / 聊天功能，按实际勾选（会议内容问答，无开放式网络访问）。
- 价格：免费。
- **销售地区：首发建议去掉「中国大陆」**。中国大陆上架需 ICP 备案，且含生成式 AI 对话功能可能被要求提供相关资质；港澳台与其他地区不受影响。之后要上大陆再单独办。

## 5. 提审前真机验收（TestFlight）
CI 只验证了编译，以下需要在真机上过一遍（审核员也会做类似操作）：
- [ ] 首次打开：空状态 →「看看示例会议」→ 纪要里的时间戳点得动、跳到转录
- [ ] 录 1 分钟：开录提醒 → 实时字幕 → 结束 → 自动出纪要（Apple 智能开启时用本机模型）
- [ ] 锁屏录 10 分钟以上，期间连上 / 断开 AirPods，录音不断、计时继续
- [ ] 录音中从多任务界面划掉 App → 重开 → 提示「已恢复未结束的录音」，内容在
- [ ] 来电（或用 FaceTime 打进来）中断后自动继续，转录里有「中断」标记
- [ ] 添加一个云端接口 → 第一次生成纪要时弹出发送同意 → 设置 → 隐私 里能撤回
- [ ] 下载说话人模型 → 会议菜单「识别说话人」→ 转录出现「说话人 1/2」，长按能改名
- [ ] 待办导入提醒事项（确认页可取消勾选）；日历联动；自动导出到文件夹
- [ ] iPad 上各页面能正常打开（App 支持 iPad，审核员可能用 iPad 测）

## 6. 关于 AGPL 与 App Store
Cove 的全部代码版权属于作者本人，作者自己通过 App Store 分发不受 AGPL 限制（AGPL 约束的是他人再分发）。第三方依赖均为 Apache-2.0 / MIT，可以上架。若将来接受外部贡献，需要贡献者同意以便继续上架（可加 CLA 或贡献须知）。
