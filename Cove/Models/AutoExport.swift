import Foundation

/// Optional (Settings): every finished set of minutes is also written as Markdown into a
/// folder the user picked in Files, such as an Obsidian vault in iCloud Drive.
enum AutoExport {
    private static let key = "export.folderBookmark"

    static var folder: URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? bookmark(url) { UserDefaults.standard.set(fresh, forKey: key) }
        return url
    }

    static func setFolder(_ url: URL) throws {
        UserDefaults.standard.set(try bookmark(url), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func bookmark(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Writes "2026-10-07 产品评审会.md" (replacing an earlier export of the same meeting). Returns an error message, if any.
    @MainActor @discardableResult
    static func save(_ meeting: Meeting) -> String? {
        guard let folder else { return nil }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>\n")
        let title = meeting.title.components(separatedBy: unsafe).joined(separator: "-").prefix(60)
        let name = "\(meeting.createdAt.formatted(.iso8601.year().month().day())) \(title).md"
        do {
            try Exporter.markdown(meeting).write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
            return nil
        } catch {
            return String(localized: "自动导出失败：\(error.localizedDescription)")
        }
    }
}
