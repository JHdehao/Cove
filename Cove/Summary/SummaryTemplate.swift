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
        SummaryTemplate(id: "general", name: String(localized: "通用会议"), symbol: "person.3", focus: """
        ## 要点
        ## 决策
        ## 待办
        ## 未决问题
        ## 章节
        """),
        SummaryTemplate(id: "standup", name: String(localized: "站会"), symbol: "figure.stand", focus: """
        按人汇总：昨天完成、今天计划、阻碍（每人一个 ### 小节）。
        ## 阻碍与需要协调
        ## 待办
        """),
        SummaryTemplate(id: "oneOnOne", name: String(localized: "1:1 面谈"), symbol: "person.2", focus: """
        ## 近况与反馈
        ## 关注的问题
        ## 达成的共识
        ## 待办
        ## 下次跟进
        """),
        SummaryTemplate(id: "client", name: String(localized: "客户访谈"), symbol: "briefcase", focus: """
        ## 客户背景
        ## 需求与痛点（尽量保留客户原话，加引号）
        ## 异议与顾虑
        ## 预算、时间线、决策人
        ## 承诺与下一步
        ## 待办
        """),
        SummaryTemplate(id: "review", name: String(localized: "需求 / 方案评审"), symbol: "checklist", focus: """
        ## 评审对象
        ## 结论（通过 / 有条件通过 / 不通过）
        ## 问题与修改意见（按严重程度排序）
        ## 风险
        ## 待办
        """),
        SummaryTemplate(id: "lecture", name: String(localized: "课程 / 讲座"), symbol: "graduationcap", focus: """
        ## 核心观点
        ## 概念与定义
        ## 例子与案例
        ## 值得复习的问题
        ## 章节
        """),
        SummaryTemplate(id: "interview", name: String(localized: "面试"), symbol: "person.crop.rectangle", focus: """
        ## 候选人概况
        ## 问答记录（问题 → 回答要点）
        ## 亮点
        ## 疑虑
        ## 综合评价（只依据对话内容，不下录用结论）
        """),
    ]

    static func named(_ id: String, customPrompt: String) -> SummaryTemplate {
        if id == custom {
            return SummaryTemplate(id: custom, name: String(localized: "自定义"), symbol: "slider.horizontal.3", focus: customPrompt)
        }
        return builtIn.first { $0.id == id } ?? builtIn[0]
    }
}

enum SummaryLanguage: String, CaseIterable, Identifiable {
    case auto, zhHans, zhHant, en, ja, ko, ru, ar
    var id: String { rawValue }
    /// Each language in its own name, so it reads the same in every UI language.
    var label: String {
        switch self {
        case .auto: String(localized: "跟随会议语言")
        case .zhHans: "简体中文"
        case .zhHant: "繁體中文"
        case .en: "English"
        case .ja: "日本語"
        case .ko: "한국어"
        case .ru: "Русский"
        case .ar: "العربية"
        }
    }
    /// For the model. Section headings are given in Chinese in the prompts; they follow the chosen language too.
    var instruction: String {
        let rest = "人名、术语保留原文；各节标题也翻译成这种语言，格式（`#` 标题、`- [ ]` 待办、`[#编号]` 出处）保持不变。"
        switch self {
        case .auto: return "用会议的主要语言书写；" + rest
        case .zhHans: return "用简体中文书写；" + rest
        case .zhHant: return "用繁體中文書寫；" + rest
        case .en: return "Write in English. " + rest
        case .ja: return "日本語で書くこと。" + rest
        case .ko: return "한국어로 작성할 것. " + rest
        case .ru: return "Пиши по-русски. " + rest
        case .ar: return "اكتب باللغة العربية. " + rest
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
    static let liveRefresh = "summary.liveRefresh"
}

/// How often the running notes catch up while recording.
enum LiveRefresh: String, CaseIterable, Identifiable {
    case fast, standard, slow, manual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fast: String(localized: "快（约 10 秒）")
        case .standard: String(localized: "标准（约 20 秒）")
        case .slow: String(localized: "省流量（约 45 秒）")
        case .manual: String(localized: "仅手动")
        }
    }
    /// New speech needed before an update, and the least time between updates; nil = only on demand.
    var threshold: (chars: Int, interval: TimeInterval)? {
        switch self {
        case .fast: (60, 10)
        case .standard: (120, 20)
        case .slow: (300, 45)
        case .manual: nil
        }
    }
}
