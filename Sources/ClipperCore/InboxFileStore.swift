import Foundation

/// Appends confirmed clips to ONE Markdown file (default: Obsidian `Inbox/划词摘录.md`).
/// The file is the user's working inbox: they (or Claude) organize entries and delete
/// processed ones, so the store only ever appends and never rewrites existing content.
/// Each entry carries a hidden `<!-- clip:UUID -->` marker so a retried save is idempotent.
public struct InboxFileStore {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public static let header = """
    ---
    tags: [inbox, 划词摘录]
    ---
    # 划词摘录

    > 由 Mac Selection Clipper 自动追加。整理完删除已处理的条目即可，新摘录会继续追加到末尾。

    """

    public static func marker(_ id: UUID) -> String { "<!-- clip:\(id.uuidString) -->" }

    public static func entry(for clip: ClipRecord, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        func oneLine(_ s: String) -> String {
            s.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
        var source = "> 来源：\(oneLine(clip.sourceApp))"
        if let title = clip.sourceTitle.map(oneLine), !title.isEmpty, title != oneLine(clip.sourceApp) { source += " — \(title)" }
        if let url = clip.sourceURL.map(oneLine), !url.isEmpty { source += " · <\(url)>" }
        // Quote every line so headings / rules / front-matter-like text inside the
        // selection cannot break the inbox structure.
        let body = clip.text.trimmingCharacters(in: .newlines)
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
        return """

        ### \(formatter.string(from: clip.capturedAt)) · \(oneLine(clip.sourceApp))
        \(source)

        \(body)

        \(marker(clip.id))

        ---

        """
    }

    /// Appends without replacing the file (keeps Obsidian's open buffer and any edits
    /// the user made elsewhere in the file). Creates parent folders and a header if needed.
    @discardableResult public func append(_ clip: ClipRecord) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            try Data(Self.header.utf8).write(to: fileURL, options: .withoutOverwriting)
        }
        let existing = try Data(contentsOf: fileURL)
        if existing.range(of: Data(Self.marker(clip.id).utf8)) != nil { return fileURL } // already saved
        var text = Self.entry(for: clip)
        if let last = existing.last, last != UInt8(ascii: "\n") { text = "\n" + text }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.synchronize()
        return fileURL
    }
}
