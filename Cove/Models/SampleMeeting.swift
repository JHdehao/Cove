import Foundation
import SwiftData

/// A finished meeting to look around in before recording one: minutes with citations,
/// speakers, notes, to-dos and a chat. Also what the App Store screenshots show.
enum SampleMeeting {
    static let title = "小程序 2.0 上线评审"

    private static let lines: [(TimeInterval, String, String)] = [
        (2, "张敏", "人都到齐了，我们开始。今天主要定两件事：小程序 2.0 什么时候上线，还有支付页改版要不要一起上。"),
        (14, "张敏", "先请李强说一下研发这边的进度。"),
        (19, "李强", "主流程都开发完了，测试这周提了 23 个缺陷，现在还剩 5 个没修，其中订单列表页在低端安卓机上滑动卡顿比较明显。"),
        (38, "李强", "卡顿是图片没有懒加载导致的，我估计修复要两天，15 号之前可以搞定。"),
        (51, "王芳", "订单页我这边也有个小调整，空状态的插图还没换成新版，我今天下午就把切图给李强。"),
        (64, "张敏", "好。那支付页改版呢？我看设计稿已经出了。"),
        (71, "王芳", "设计稿出了，但是跟财务那边对接的优惠券叠加规则还没有最终确认，我担心上线后显示的金额和实际扣款对不上。"),
        (90, "李强", "对，支付页涉及钱，我建议不要赶这一版。规则不确定的话，测试也没法写用例。"),
        (103, "张敏", "我同意。支付页改版延后到 2.1，这次先不上。"),
        (112, "张敏", "王芳你找财务把叠加规则在下周三之前定下来，定了之后我们再排期。"),
        (121, "王芳", "可以，我周三前给结果。"),
        (127, "张敏", "那上线时间，大家觉得 10 月 20 号灰度可以吗？"),
        (134, "李强", "可以，前提是 15 号把缺陷清零，16、17 号做一轮回归测试。"),
        (145, "张敏", "行，那就定 10 月 20 号灰度上线，先放 10% 的用户，观察三天没问题再全量。"),
        (158, "李强", "灰度期间的监控我来盯，崩溃率超过千分之三就自动回滚。"),
        (169, "王芳", "还有一个问题，新版的首页引导要不要加？有用户反馈找不到新入口。"),
        (181, "张敏", "这个我还没想好，加引导会影响首屏的转化，我先看下数据，下次会上再讨论。"),
        (194, "张敏", "最后确认一下分工：李强负责修缺陷和灰度监控，王芳负责订单页切图和优惠券规则，我负责写上线公告和通知客服。"),
        (210, "李强", "没问题。"),
        (213, "王芳", "好的。"),
        (216, "张敏", "那今天就到这里，谢谢大家。"),
    ]

    private static let summary = """
    # 小程序 2.0 上线评审
    > 定于 10 月 20 日灰度上线（10% 用户），支付页改版延后到 2.1。[#13, #8]

    ## 要点
    - 主流程开发完成，剩余 5 个缺陷，订单列表页在低端安卓机上卡顿明显，原因是图片未懒加载。[#2, #3]
    - 支付页设计稿已完成，但优惠券叠加规则未与财务确认，存在金额显示与扣款不一致的风险。[#6]
    - 灰度期间监控崩溃率，超过千分之三自动回滚。[#14]

    ## 决策
    - 支付页改版不进本版，延后到 2.1，规则确定后再排期。[#8, #9]
    - 10 月 20 日灰度上线，先放 10% 用户，观察三天无问题再全量。[#13]
    - 上线前提：15 日缺陷清零，16–17 日回归测试。[#12]

    ## 待办
    - [ ] 修复订单列表页卡顿及剩余缺陷 — 李强 — 10 月 15 日 [#3, #12]
    - [ ] 提供订单页空状态新切图 — 王芳 — 今天下午 [#4]
    - [ ] 与财务确认优惠券叠加规则 — 王芳 — 下周三 [#9, #10]
    - [ ] 灰度期间监控与自动回滚 — 李强 — 灰度期间 [#14]
    - [ ] 撰写上线公告并通知客服 — 张敏 — 待定 [#17]

    ## 未决问题
    - 新版首页是否加引导：担心影响首屏转化，张敏看数据后下次会议讨论。[#15, #16]

    ## 章节
    - 00:02 议程：上线时间与支付页改版 [#0]
    - 00:19 研发进度与缺陷 [#2, #3]
    - 01:04 支付页改版延后 [#5, #8]
    - 02:07 上线时间与灰度方案 [#11, #13]
    - 02:49 首页引导（未决）[#15]
    - 03:14 分工确认 [#17]
    """

    @MainActor
    static func insert(into context: ModelContext) -> Meeting {
        let meeting = Meeting(title: title, createdAt: .now.addingTimeInterval(-3600))
        meeting.segments = lines.enumerated().map { index, line in
            let end = index + 1 < lines.count ? lines[index + 1].0 - 0.5 : line.0 + 3
            return Segment(start: line.0, end: end, speaker: line.1, text: line.2)
        }
        meeting.duration = 220
        meeting.markers = [Marker(time: 92, kind: .note, text: "支付页先别上，钱的事不能赶"), Marker(time: 146, kind: .star)]
        meeting.summary = summary
        meeting.summaryTemplateID = "general"
        meeting.summaryModel = "示例"
        meeting.summarizedAt = .now
        meeting.attendees = "张敏、李强、王芳"
        meeting.titleIsFixed = true
        meeting.diarizedAt = .now
        meeting.chat = [
            ChatMessage(role: .user, content: "每个人分别负责什么？"),
            ChatMessage(role: .assistant, content: """
            - **李强**：15 日前修复订单页卡顿和剩余缺陷，灰度期间盯监控、必要时回滚。[#3, #14]
            - **王芳**：今天下午给订单页切图；下周三前和财务确认优惠券叠加规则。[#4, #10]
            - **张敏**：写上线公告、通知客服；看数据决定首页是否加引导。[#17, #16]
            """),
        ]
        context.insert(meeting)
        try? context.save()
        return meeting
    }
}
