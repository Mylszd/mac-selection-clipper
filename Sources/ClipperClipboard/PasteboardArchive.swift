import AppKit

public enum ClipboardArchiveError: LocalizedError {
    case unsafe, incomplete, tooLarge, changed
    public var errorDescription: String? {
        switch self {
        case .unsafe: return "剪贴板含密码标记或延迟文件承诺，已跳过增强复制。"
        case .incomplete: return "无法完整保留剪贴板的所有格式，已跳过增强复制。"
        case .tooLarge: return "剪贴板超过安全备份上限，已跳过增强复制。"
        case .changed: return "备份时剪贴板发生变化，已跳过增强复制。"
        }
    }
}

/// All AppKit pasteboard work is performed on the main thread. The archive is
/// memory-only and eagerly materializes EVERY offered representation or fails
/// before the caller sends Copy. Lazy file promises and concealed data fail closed.
public struct PasteboardArchive {
    public struct Representation { public let type: NSPasteboard.PasteboardType; public let data: Data }
    public let items: [[Representation]]
    public let changeCount: Int
    public static func capture(_ pasteboard: NSPasteboard, byteLimit: Int = 16 * 1024 * 1024) throws -> Self {
        precondition(Thread.isMainThread)
        let count = pasteboard.changeCount
        let offered = pasteboard.pasteboardItems
        if offered == nil && !(pasteboard.types?.isEmpty ?? true) { throw ClipboardArchiveError.incomplete }
        let original = offered ?? []
        guard original.count <= 32 else { throw ClipboardArchiveError.tooLarge }
        var bytes = 0, archived = [[Representation]]()
        for item in original {
            guard item.types.count <= 64 else { throw ClipboardArchiveError.tooLarge }
            var representations = [Representation]()
            for type in item.types {
                let name = type.rawValue.lowercased()
                if name.contains("promise") || name.contains("concealed") || name.contains("password") || name.contains("transient") { throw ClipboardArchiveError.unsafe }
                guard let data = item.data(forType: type) else { throw ClipboardArchiveError.incomplete }
                bytes += data.count
                guard bytes <= byteLimit else { throw ClipboardArchiveError.tooLarge }
                representations.append(Representation(type: type, data: data))
            }
            guard !representations.isEmpty else { throw ClipboardArchiveError.incomplete }
            archived.append(representations)
        }
        guard pasteboard.changeCount == count else { throw ClipboardArchiveError.changed }
        return Self(items: archived, changeCount: count)
    }
    /// Conservative race guard: never replace a newer observed write. NSPasteboard
    /// offers no atomic compare-and-swap; a cross-process write in the tiny gap
    /// between the final check and write cannot be excluded (documented opt-in risk).
    @discardableResult public func restore(_ pasteboard: NSPasteboard, expectedChangeCount: Int) -> Bool {
        precondition(Thread.isMainThread)
        var rebuilt = [NSPasteboardItem]()
        for representations in items {
            let item = NSPasteboardItem()
            for representation in representations { guard item.setData(representation.data, forType: representation.type) else { return false } }
            rebuilt.append(item)
        }
        guard pasteboard.changeCount == expectedChangeCount else { return false }
        let cleared = pasteboard.clearContents()
        guard pasteboard.changeCount == cleared else { return false }
        return rebuilt.isEmpty || pasteboard.writeObjects(rebuilt)
    }
}

public enum CopyFallbackPolicy {
    public enum Mode: Equatable { case none, menuOnly, menuOrKey }
    /// Apps where a drag means moving files/icons, never selecting text.
    public static let neverCopy: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.systemuiserver", "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.WindowManager", "com.apple.Spotlight"]
    /// All-apps mode: any app may get a Copy-menu press; only allowlisted apps (whose
    /// menu state is unreliable or missing) may also receive a synthesized ⌘C.
    public static func mode(enabled: Bool, allApps: Bool, bundleID: String, allowedApps: Set<String>, secure: Bool) -> Mode {
        guard enabled, !secure, !neverCopy.contains(bundleID) else { return .none }
        if allowedApps.contains(bundleID) { return .menuOrKey }
        return allApps ? .menuOnly : .none
    }
    public static func allows(enabled: Bool, bundleID: String, allowedApps: Set<String>, secure: Bool) -> Bool {
        enabled && !secure && allowedApps.contains(bundleID)
    }
    public static func hasFreshStableCopy(before: Int, observed: Int, current: Int) -> Bool {
        observed > before && current == observed
    }
}
