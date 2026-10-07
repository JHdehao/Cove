import Foundation
import SwiftData

/// A finished meeting to look around in before recording one: minutes with citations,
/// speakers, notes, to-dos and a chat. Also what the App Store screenshots show.
/// In Simplified or Traditional Chinese, or English for every other language.
enum SampleMeeting {
    struct Content {
        let title: String
        let speakers: [String]
        let attendees: String
        /// Seconds from the start, index into `speakers`, text.
        let lines: [(TimeInterval, Int, String)]
        let summary: String
        let note: String
        let question: String
        let answer: String
    }

    static var content: Content {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        if language.hasPrefix("zh-Hant") { return hant }
        if language.hasPrefix("zh") { return hans }
        return english
    }

    static var title: String { content.title }

    @MainActor
    static func insert(into context: ModelContext) -> Meeting {
        let content = content
        let meeting = Meeting(title: content.title, createdAt: .now.addingTimeInterval(-3600))
        meeting.segments = content.lines.enumerated().map { index, line in
            let end = index + 1 < content.lines.count ? content.lines[index + 1].0 - 0.5 : line.0 + 3
            return Segment(start: line.0, end: end, speaker: content.speakers[line.1], text: line.2)
        }
        meeting.duration = 220
        meeting.markers = [Marker(time: 92, kind: .note, text: content.note), Marker(time: 146, kind: .star)]
        meeting.summary = content.summary
        meeting.summaryTemplateID = "general"
        meeting.summaryModel = String(localized: "示例")
        meeting.summarizedAt = .now
        meeting.attendees = content.attendees
        meeting.titleIsFixed = true
        meeting.diarizedAt = .now
        meeting.chat = [ChatMessage(role: .user, content: content.question), ChatMessage(role: .assistant, content: content.answer)]
        context.insert(meeting)
        try? context.save()
        return meeting
    }

    static let hans = Content(
        title: "小程序 2.0 上线评审",
        speakers: ["张敏", "李强", "王芳"],
        attendees: "张敏、李强、王芳",
        lines: [
            (2, 0, "人都到齐了，我们开始。今天主要定两件事：小程序 2.0 什么时候上线，还有支付页改版要不要一起上。"),
            (14, 0, "先请李强说一下研发这边的进度。"),
            (19, 1, "主流程都开发完了，测试这周提了 23 个缺陷，现在还剩 5 个没修，其中订单列表页在低端安卓机上滑动卡顿比较明显。"),
            (38, 1, "卡顿是图片没有懒加载导致的，我估计修复要两天，15 号之前可以搞定。"),
            (51, 2, "订单页我这边也有个小调整，空状态的插图还没换成新版，我今天下午就把切图给李强。"),
            (64, 0, "好。那支付页改版呢？我看设计稿已经出了。"),
            (71, 2, "设计稿出了，但是跟财务那边对接的优惠券叠加规则还没有最终确认，我担心上线后显示的金额和实际扣款对不上。"),
            (90, 1, "对，支付页涉及钱，我建议不要赶这一版。规则不确定的话，测试也没法写用例。"),
            (103, 0, "我同意。支付页改版延后到 2.1，这次先不上。"),
            (112, 0, "王芳你找财务把叠加规则在下周三之前定下来，定了之后我们再排期。"),
            (121, 2, "可以，我周三前给结果。"),
            (127, 0, "那上线时间，大家觉得 10 月 20 号灰度可以吗？"),
            (134, 1, "可以，前提是 15 号把缺陷清零，16、17 号做一轮回归测试。"),
            (145, 0, "行，那就定 10 月 20 号灰度上线，先放 10% 的用户，观察三天没问题再全量。"),
            (158, 1, "灰度期间的监控我来盯，崩溃率超过千分之三就自动回滚。"),
            (169, 2, "还有一个问题，新版的首页引导要不要加？有用户反馈找不到新入口。"),
            (181, 0, "这个我还没想好，加引导会影响首屏的转化，我先看下数据，下次会上再讨论。"),
            (194, 0, "最后确认一下分工：李强负责修缺陷和灰度监控，王芳负责订单页切图和优惠券规则，我负责写上线公告和通知客服。"),
            (210, 1, "没问题。"),
            (213, 2, "好的。"),
            (216, 0, "那今天就到这里，谢谢大家。"),
        ],
        summary: "# 小程序 2.0 上线评审\n> 定于 10 月 20 日灰度上线（10% 用户），支付页改版延后到 2.1。[#13, #8]\n\n## 要点\n- 主流程开发完成，剩余 5 个缺陷，订单列表页在低端安卓机上卡顿明显，原因是图片未懒加载。[#2, #3]\n- 支付页设计稿已完成，但优惠券叠加规则未与财务确认，存在金额显示与扣款不一致的风险。[#6]\n- 灰度期间监控崩溃率，超过千分之三自动回滚。[#14]\n\n## 决策\n- 支付页改版不进本版，延后到 2.1，规则确定后再排期。[#8, #9]\n- 10 月 20 日灰度上线，先放 10% 用户，观察三天无问题再全量。[#13]\n- 上线前提：15 日缺陷清零，16–17 日回归测试。[#12]\n\n## 待办\n- [ ] 修复订单列表页卡顿及剩余缺陷 — 李强 — 10 月 15 日 [#3, #12]\n- [ ] 提供订单页空状态新切图 — 王芳 — 今天下午 [#4]\n- [ ] 与财务确认优惠券叠加规则 — 王芳 — 下周三 [#9, #10]\n- [ ] 灰度期间监控与自动回滚 — 李强 — 灰度期间 [#14]\n- [ ] 撰写上线公告并通知客服 — 张敏 — 待定 [#17]\n\n## 未决问题\n- 新版首页是否加引导：担心影响首屏转化，张敏看数据后下次会议讨论。[#15, #16]\n\n## 章节\n- 00:02 议程：上线时间与支付页改版 [#0]\n- 00:19 研发进度与缺陷 [#2, #3]\n- 01:04 支付页改版延后 [#5, #8]\n- 02:07 上线时间与灰度方案 [#11, #13]\n- 02:49 首页引导（未决）[#15]\n- 03:14 分工确认 [#17]",
        note: "支付页先别上，钱的事不能赶",
        question: "每个人分别负责什么？",
        answer: "- **李强**：15 日前修复订单页卡顿和剩余缺陷，灰度期间盯监控、必要时回滚。[#3, #14]\n- **王芳**：今天下午给订单页切图；下周三前和财务确认优惠券叠加规则。[#4, #10]\n- **张敏**：写上线公告、通知客服；看数据决定首页是否加引导。[#17, #16]"
    )

    static let hant = Content(
        title: "小程式 2.0 上線評審",
        speakers: ["張敏", "李強", "王芳"],
        attendees: "張敏、李強、王芳",
        lines: [
            (2, 0, "人都到齊了，我們開始。今天主要定兩件事：小程式 2.0 什麼時候上線，還有支付頁改版要不要一起上。"),
            (14, 0, "先請李強說一下研發這邊的進度。"),
            (19, 1, "主流程都開發完了，測試這周提了 23 個缺陷，現在還剩 5 個沒修，其中訂單列表頁在低端安卓機上滑動卡頓比較明顯。"),
            (38, 1, "卡頓是圖片沒有懶載入導致的，我估計修復要兩天，15 號之前可以搞定。"),
            (51, 2, "訂單頁我這邊也有個小調整，空狀態的插圖還沒換成新版，我今天下午就把切圖給李強。"),
            (64, 0, "好。那支付頁改版呢？我看設計稿已經出了。"),
            (71, 2, "設計稿出了，但是跟財務那邊對接的優惠券疊加規則還沒有最終確認，我擔心上線後顯示的金額和實際扣款對不上。"),
            (90, 1, "對，支付頁涉及錢，我建議不要趕這一版。規則不確定的話，測試也沒法寫用例。"),
            (103, 0, "我同意。支付頁改版延後到 2.1，這次先不上。"),
            (112, 0, "王芳你找財務把疊加規則在下週三之前定下來，定了之後我們再排期。"),
            (121, 2, "可以，我週三前給結果。"),
            (127, 0, "那上線時間，大家覺得 10 月 20 號灰度可以嗎？"),
            (134, 1, "可以，前提是 15 號把缺陷清零，16、17 號做一輪迴歸測試。"),
            (145, 0, "行，那就定 10 月 20 號灰度上線，先放 10% 的使用者，觀察三天沒問題再全量。"),
            (158, 1, "灰度期間的監控我來盯，崩潰率超過千分之三就自動回滾。"),
            (169, 2, "還有一個問題，新版的首頁引導要不要加？有使用者反饋找不到新入口。"),
            (181, 0, "這個我還沒想好，加引導會影響首屏的轉化，我先看下資料，下次會上再討論。"),
            (194, 0, "最後確認一下分工：李強負責修缺陷和灰度監控，王芳負責訂單頁切圖和優惠券規則，我負責寫上線公告和通知客服。"),
            (210, 1, "沒問題。"),
            (213, 2, "好的。"),
            (216, 0, "那今天就到這裡，謝謝大家。"),
        ],
        summary: "# 小程式 2.0 上線評審\n> 定於 10 月 20 日灰度上線（10% 使用者），支付頁改版延後到 2.1。[#13, #8]\n\n## 要點\n- 主流程開發完成，剩餘 5 個缺陷，訂單列表頁在低端安卓機上卡頓明顯，原因是圖片未懶載入。[#2, #3]\n- 支付頁設計稿已完成，但優惠券疊加規則未與財務確認，存在金額顯示與扣款不一致的風險。[#6]\n- 灰度期間監控崩潰率，超過千分之三自動回滾。[#14]\n\n## 決策\n- 支付頁改版不進本版，延後到 2.1，規則確定後再排期。[#8, #9]\n- 10 月 20 日灰度上線，先放 10% 使用者，觀察三天無問題再全量。[#13]\n- 上線前提：15 日缺陷清零，16–17 日迴歸測試。[#12]\n\n## 待辦\n- [ ] 修復訂單列表頁卡頓及剩餘缺陷 — 李強 — 10 月 15 日 [#3, #12]\n- [ ] 提供訂單頁空狀態新切圖 — 王芳 — 今天下午 [#4]\n- [ ] 與財務確認優惠券疊加規則 — 王芳 — 下週三 [#9, #10]\n- [ ] 灰度期間監控與自動回滾 — 李強 — 灰度期間 [#14]\n- [ ] 撰寫上線公告並通知客服 — 張敏 — 待定 [#17]\n\n## 未決問題\n- 新版首頁是否加引導：擔心影響首屏轉化，張敏看資料後下次會議討論。[#15, #16]\n\n## 章節\n- 00:02 議程：上線時間與支付頁改版 [#0]\n- 00:19 研發進度與缺陷 [#2, #3]\n- 01:04 支付頁改版延後 [#5, #8]\n- 02:07 上線時間與灰度方案 [#11, #13]\n- 02:49 首頁引導（未決）[#15]\n- 03:14 分工確認 [#17]",
        note: "支付頁先別上，錢的事不能趕",
        question: "每個人分別負責什麼？",
        answer: "- **李強**：15 日前修復訂單頁卡頓和剩餘缺陷，灰度期間盯監控、必要時回滾。[#3, #14]\n- **王芳**：今天下午給訂單頁切圖；下週三前和財務確認優惠券疊加規則。[#4, #10]\n- **張敏**：寫上線公告、通知客服；看資料決定首頁是否加引導。[#17, #16]"
    )

    static let english = Content(
        title: "App 2.0 Launch Review",
        speakers: ["Emma", "Liam", "Sophie"],
        attendees: "Emma, Liam, Sophie",
        lines: [
            (2, 0, "Looks like everyone's here, let's start. Two things to settle today: when the 2.0 app ships, and whether the checkout redesign goes out with it."),
            (14, 0, "Liam, can you start with where engineering is?"),
            (19, 1, "The main flows are done. QA filed 23 bugs this week and 5 are still open. The worst is the order list stuttering on low-end Android phones."),
            (38, 1, "The stutter is because images aren't lazy-loaded. I think it's two days to fix, so done before the 15th."),
            (51, 2, "I have a small change on the order page too: the empty-state illustration isn't the new one yet. I'll send Liam the assets this afternoon."),
            (64, 0, "Good. What about the checkout redesign? I saw the designs are ready."),
            (71, 2, "The designs are ready, but finance still hasn't confirmed the rules for stacking coupons. I'm worried the amount we show won't match what we charge."),
            (90, 1, "Right, it's money. I'd rather not rush it into this release. If the rules aren't settled, QA can't even write test cases."),
            (103, 0, "Agreed. The checkout redesign moves to 2.1, not this release."),
            (112, 0, "Sophie, please get the stacking rules settled with finance by next Wednesday, then we'll schedule it."),
            (121, 2, "Will do, I'll have an answer before Wednesday."),
            (127, 0, "So for the launch, does a staged rollout on October 20 work for everyone?"),
            (134, 1, "Yes, as long as the bugs are all closed by the 15th and we do a regression pass on the 16th and 17th."),
            (145, 0, "OK, then it's decided: staged rollout on October 20, 10% of users first, full release if three days look clean."),
            (158, 1, "I'll watch the monitoring during the rollout, and roll back automatically if the crash rate goes above 0.3%."),
            (169, 2, "One more thing: do we add onboarding hints to the new home screen? Users say they can't find the new entry points."),
            (181, 0, "I haven't decided. Onboarding might hurt first-screen conversion. Let me look at the data and we'll discuss it next time."),
            (194, 0, "Let's confirm owners: Liam fixes the bugs and watches the rollout, Sophie does the order page assets and the coupon rules, and I'll write the release notes and brief support."),
            (210, 1, "Sounds good."),
            (213, 2, "Sure."),
            (216, 0, "That's it for today, thanks everyone."),
        ],
        summary: "# App 2.0 Launch Review\n> Staged rollout on October 20 (10% of users); the checkout redesign moves to 2.1. [#13, #8]\n\n## Key points\n- Main flows are done with 5 bugs open; the order list stutters on low-end Android because images aren't lazy-loaded. [#2, #3]\n- Checkout designs are ready, but the coupon stacking rules aren't confirmed with finance, so displayed and charged amounts could differ. [#6]\n- Crash rate is monitored during the rollout, with automatic rollback above 0.3%. [#14]\n\n## Decisions\n- The checkout redesign is out of this release and moves to 2.1, to be scheduled once the rules are settled. [#8, #9]\n- October 20 staged rollout to 10% of users, full release after three clean days. [#13]\n- Launch requires all bugs closed by the 15th and regression testing on the 16th–17th. [#12]\n\n## Action items\n- [ ] Fix the order list stutter and remaining bugs — Liam — Oct 15 [#3, #12]\n- [ ] Send the new empty-state assets for the order page — Sophie — this afternoon [#4]\n- [ ] Confirm coupon stacking rules with finance — Sophie — next Wednesday [#9, #10]\n- [ ] Monitor the rollout and roll back automatically if needed — Liam — during rollout [#14]\n- [ ] Write release notes and brief customer support — Emma — TBD [#17]\n\n## Open questions\n- Whether to add onboarding hints to the new home screen: it may hurt first-screen conversion; Emma will check the data and bring it to the next meeting. [#15, #16]\n\n## Chapters\n- 00:02 Agenda: launch date and checkout redesign [#0]\n- 00:19 Engineering status and bugs [#2, #3]\n- 01:04 Checkout redesign postponed [#5, #8]\n- 02:07 Launch date and staged rollout [#11, #13]\n- 02:49 Home screen onboarding (open) [#15]\n- 03:14 Owners confirmed [#17]\n",
        note: "Don't rush the checkout, it's money",
        question: "Who is responsible for what?",
        answer: "- **Liam**: fix the order page stutter and remaining bugs before the 15th; watch the rollout and roll back if needed. [#3, #14]\n- **Sophie**: send the order page assets this afternoon; settle coupon stacking rules with finance by next Wednesday. [#4, #10]\n- **Emma**: write the release notes and brief support; decide on home screen onboarding from the data. [#17, #16]"
    )
}
