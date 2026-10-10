import SwiftData
import SwiftUI

@main
struct CoveApp: App {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Meeting.self)
        } catch {
            fatalError("无法打开数据库：\(error)")
        }
    }()

    @AppStorage("appearance") private var appearance = Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .tint(CoveColor.accent)
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
                .modifier(AIConsentPrompt())
        }
        .modelContainer(Self.container)
    }
}

enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        let commit = (info["CoveCommit"] as? String).flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""
        return "Cove \(short) (\(build))\(commit)"
    }
}

/// 界面语言：写本 app 的 AppleLanguages（和系统设置里「App 语言」是同一个值），重新打开后生效。
/// 侧载进 LiveContainer 时它每次启动都会重置这个值，要改用 LiveContainer 里该 app 的语言设置。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "", zhHans = "zh-Hans", zhHant = "zh-Hant", en, ja, ko, ru, ar
    var id: String { rawValue }

    /// 每种语言用它自己的写法显示，看不懂当前界面的人也能找到自己的语言。
    var label: String {
        self == .system ? String(localized: "跟随系统")
            : Locale(identifier: rawValue).localizedString(forIdentifier: rawValue) ?? rawValue
    }

    private static let key = "AppleLanguages"

    static var current: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let first = (domain?[key] as? [String])?.first else { return .system }
        return allCases.first { $0 != .system && first.hasPrefix($0.rawValue) } ?? .system
    }

    static func apply(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: key)
        }
    }
}
