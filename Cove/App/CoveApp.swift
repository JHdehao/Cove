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
