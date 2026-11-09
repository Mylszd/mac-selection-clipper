import Foundation

public struct HistoryEntry: Identifiable {
    public let record: ClipRecord
    public let url: URL
    public var id: URL { url }
}
public struct HistoryLoad {
    public var entries: [HistoryEntry]
    public var records: [ClipRecord] { entries.map(\.record) }
    public var unreadableFiles: Int
}
public enum StoreError: LocalizedError {
    case malformed, conflictingID
    public var errorDescription: String? {
        switch self { case .malformed: return "Markdown 元数据不完整或格式无法读取。"
        case .conflictingID: return "同一 UUID 已有不同内容，未覆盖原文件。" }
    }
}

public struct MarkdownFileStore {
    public let root: URL
    public init(root: URL) { self.root = root }
    private static func formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }
    public static func markdown(_ clip: ClipRecord) throws -> String {
        let f = formatter()
        let fields: [(String, Any?)] = [
            ("id", clip.id.uuidString.lowercased()), ("created_at", f.string(from: clip.createdAt)),
            ("captured_at", f.string(from: clip.capturedAt)), ("source_app", clip.sourceApp),
            ("source_bundle_id", clip.sourceBundleID), ("source_title", clip.sourceTitle), ("source_url", clip.sourceURL)
        ]
        let lines = try fields.map { key, value in
            let data = try JSONSerialization.data(withJSONObject: value ?? NSNull(), options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return key + ": " + String(decoding: data, as: UTF8.self)
        }
        return "---\n" + lines.joined(separator: "\n") + "\n---\n\n" + clip.text
    }
    public static func parse(_ raw: String) throws -> ClipRecord {
        guard raw.hasPrefix("---\n"), let boundary = raw.range(of: "\n---\n", range: raw.index(raw.startIndex, offsetBy: 4)..<raw.endIndex) else { throw StoreError.malformed }
        let header = raw[raw.index(raw.startIndex, offsetBy: 4)..<boundary.lowerBound]
        var values = [String: Any]()
        for line in header.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { throw StoreError.malformed }
            let key = String(line[..<colon]), value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            values[key] = try JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])
        }
        guard let idString = values["id"] as? String, let id = UUID(uuidString: idString),
              let createdString = values["created_at"] as? String,
              let date = formatter().date(from: createdString) ?? ISO8601DateFormatter().date(from: createdString),
              let app = values["source_app"] as? String, let bundle = values["source_bundle_id"] as? String else { throw StoreError.malformed }
        let captured = (values["captured_at"] as? String).flatMap { formatter().date(from: $0) } ?? date
        var body = String(raw[boundary.upperBound...]); if body.hasPrefix("\n") { body.removeFirst() }
        return ClipRecord(id: id, createdAt: date, capturedAt: captured, sourceApp: app, sourceBundleID: bundle, sourceTitle: values["source_title"] as? String, sourceURL: values["source_url"] as? String, text: body)
    }
    public func fileURL(for clip: ClipRecord) -> URL {
        let stamp = Self.formatter().string(from: clip.createdAt)
        let year = String(stamp.prefix(4)), month = String(stamp.dropFirst(5).prefix(2))
        return root.appendingPathComponent(year).appendingPathComponent(month)
            .appendingPathComponent(stamp.replacingOccurrences(of: ":", with: "-") + "_" + clip.id.uuidString.lowercased() + ".md")
    }
    @discardableResult public func save(_ clip: ClipRecord) throws -> URL {
        let url = fileURL(for: clip), data = Data(try Self.markdown(clip).utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == data else { throw StoreError.conflictingID }
            return url
        }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
    public func load() throws -> HistoryLoad {
        guard FileManager.default.fileExists(atPath: root.path) else { return HistoryLoad(entries: [], unreadableFiles: 0) }
        var failed = 0
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in failed += 1; return true }) else { throw CocoaError(.fileReadUnknown) }
        var entries = [HistoryEntry]()
        for case let url as URL in enumerator where url.pathExtension == "md" {
            do {
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                entries.append(HistoryEntry(record: try Self.parse(String(contentsOf: url, encoding: .utf8)), url: url))
            } catch { failed += 1 }
        }
        return HistoryLoad(entries: entries.sorted { $0.record.createdAt > $1.record.createdAt }, unreadableFiles: failed)
    }
    public static func export(_ clips: [ClipRecord]) -> String {
        "# 摘录合集\n\n" + clips.enumerated().map { index, clip in
            "## 摘录 \(index + 1)\n来源：\(clip.sourceApp)\n时间：\(formatter().string(from: clip.createdAt))\n" +
            (clip.sourceURL.map { "链接：\($0)\n" } ?? "") + "\n" + clip.text
        }.joined(separator: "\n\n")
    }
}
