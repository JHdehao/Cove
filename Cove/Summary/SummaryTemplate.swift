import Foundation

/// What kind of meeting it was, and so what the minutes should pull out.
struct SummaryTemplate: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let symbol: String
    /// Sections and emphasis particular to this kind of meeting.
    let focus: String

    static let custom = "custom"

    static let builtIn: [SummaryTemplate] = [
        SummaryTemplate(id: "general", name: "通用会议", symbol: "person.3", focus: """
        ## 要点
        ## 决策
        ## 待办
        ## 未决问题
        ## 章节
        """),
        SummaryTemplate(id: "standup", name: "站会", symbol: "figure.stand", focus: """
        按人汇总：昨天完成、今天计划、阻碍（每人一个 ### 小节）。
        ## 阻碍与需要协调
        ## 待办
        """),
        SummaryTemplate(id: "oneOnOne", name: "1:1 面谈", symbol: "person.2", focus: """
        ## 近况与反馈
        ## 关注的问题
        ## 达成的共识
        ## 待办
        ## 下次跟进
        """),
        SummaryTemplate(id: "client", name: "客户访谈", symbol: "briefcase", focus: """
        ## 客户背景
        ## 需求与痛点（尽量保留客户原话，加引号）
        ## 异议与顾虑
        ## 预算、时间线、决策人
        ## 承诺与下一步
        ## 待办
        """),
        SummaryTemplate(id: "review", name: "需求 / 方案评审", symbol: "checklist", focus: """
        ## 评审对象
        ## 结论（通过 / 有条件通过 / 不通过）
        ## 问题与修改意见（按严重程度排序）
        ## 风险
        ## 待办
        """),
        SummaryTemplate(id: "lecture", name: "课程 / 讲座", symbol: "graduationcap", focus: """
        ## 核心观点
        ## 概念与定义
        ## 例子与案例
        ## 值得复习的问题
        ## 章节
        """),
        SummaryTemplate(id: "interview", name: "面试", symbol: "person.crop.rectangle", focus: """
        ## 候选人概况
        ## 问答记录（问题 → 回答要点）
        ## 亮点
        ## 疑虑
        ## 综合评价（只依据对话内容，不下录用结论）
        """),
    ]

    static func named(_ id: String, customPrompt: String) -> SummaryTemplate {
        if id == custom {
            return SummaryTemplate(id: custom, name: "自定义", symbol: "slider.horizontal.3", focus: customPrompt)
        }
        return builtIn.first { $0.id == id } ?? builtIn[0]
    }
}

enum SummaryLanguage: String, CaseIterable, Identifiable {
    case auto, zhHans, en
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "跟随会议语言"
        case .zhHans: "简体中文"
        case .en: "English"
        }
    }
    var instruction: String {
        switch self {
        case .auto: "用会议的主要语言书写。"
        case .zhHans: "用简体中文书写（人名、术语保留原文）。"
        case .en: "Write in English (keep names and terms as spoken)."
        }
    }
}

enum SummaryKey {
    static let template = "summary.template"
    static let language = "summary.language"
    static let customPrompt = "summary.customPrompt"
    static let glossary = "summary.glossary"
    /// Write the minutes as soon as a transcript is ready.
    static let auto = "summary.auto"
}
