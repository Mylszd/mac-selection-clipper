import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipperCore

struct CaptureRequest {
    let pid: pid_t
    let bundleID: String
    let appName: String
    let point: CGPoint // AX coordinates: top-left origin
    let capturedAt: Date
    let sequence: UInt64
    let startedAt: TimeInterval
    let trigger: String
    var sourceTitle: String? = nil
    var sourceURL: String? = nil
}
enum AXReadResult {
    case text(String), copied(String), clipboardIssue(String), terminalMouseReporting, empty, unsupported, denied, timeout, secure, tooLong, complexSelection, changedApp
    var selectedText: String? { switch self { case .text(let text), .copied(let text): return text; default: return nil } }
    var method: String { if case .copied = self { return "复制兼容" }; return "AX" }
    var label: String {
        switch self {
        case .text: return "AX 读取成功"
        case .copied: return "复制兼容成功 · 原剪贴板已恢复"
        case .clipboardIssue(let message): return message
        case .terminalMouseReporting: return "Terminal 开着「允许鼠标报告」，选区归终端程序 · 按 ⌘R 关闭后再划选"
        case .empty: return "没有读到选中文字"
        case .unsupported: return "此处文字不可读取"
        case .denied: return "需要辅助功能权限"
        case .timeout: return "来源应用响应超时 · 保留上次预览"
        case .secure: return "安全输入或密码控件 · 已跳过"
        case .tooLong: return "选区超过 100,000 字符 · 未截断，请分段选取"
        case .complexSelection: return "多段选区超过32段 · 未截断，请分段选取"
        case .changedApp: return "来源应用已切换 · 保留上次预览"
        }
    }
}

final class AXSelectionReader {
    /// PIDs for which we already asked Electron/Chromium to build its AX tree.
    /// Only touched on the serial clipper.ax queue.
    private var prepared = Set<pid_t>()

    /// Electron apps (VS Code, Slack, Obsidian, Lark…) keep their renderer
    /// accessibility tree off until an assistive client sets the documented
    /// `AXManualAccessibility` attribute (public AXUIElementSetAttributeValue).
    /// Non-Electron apps simply return attributeUnsupported. Returns true when
    /// this call newly enabled the tree, so the caller can give it time to build.
    @discardableResult func prepare(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted(), pid > 0, !prepared.contains(pid) else { return false }
        prepared.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        return AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
    }

    /// Locates the app's Copy menu item (⌘C, no other modifiers) for menu-action
    /// copy fallback. Returns nil when not found or disabled.
    func enabledCopyMenuItem(pid: pid_t) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        func get(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
            AXUIElementSetMessagingTimeout(e, 0.15)
            var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
        }
        guard let barRaw = get(app, kAXMenuBarAttribute), CFGetTypeID(barRaw) == AXUIElementGetTypeID() else { return nil }
        let bar = barRaw as! AXUIElement
        for top in (get(bar, kAXChildrenAttribute) as? [AXUIElement] ?? []).dropFirst() {
            for menu in get(top, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                for item in get(menu, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                    let identifier = get(item, kAXIdentifierAttribute) as? String
                    let char = (get(item, kAXMenuItemCmdCharAttribute) as? String)?.uppercased()
                    let mods = (get(item, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? -1
                    guard identifier == "copy:" || (char == "C" && mods == 0) else { continue }
                    return (get(item, kAXEnabledAttribute) as? Bool) == true ? item : nil
                }
            }
        }
        return nil
    }

    /// Window title and document/web URL for the source note line. Best effort, bounded.
    func sourceContext(pid: pid_t) -> (title: String?, url: String?) {
        let app = AXUIElementCreateApplication(pid)
        func get(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
            AXUIElementSetMessagingTimeout(e, 0.1)
            var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
        }
        func element(_ raw: CFTypeRef?) -> AXUIElement? {
            guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }; return (raw as! AXUIElement)
        }
        func urlString(_ raw: CFTypeRef?) -> String? {
            if let url = raw as? URL { return url.isFileURL ? url.path : url.absoluteString }
            if let s = raw as? String, !s.isEmpty { return s.hasPrefix("file://") ? (URL(string: s)?.path ?? s) : s }
            return nil
        }
        let window = element(get(app, kAXFocusedWindowAttribute))
        let title = window.flatMap { get($0, kAXTitleAttribute) as? String }.flatMap { $0.isEmpty ? nil : $0 }
        var url: String?
        // Web content: walk up from the focused element to the AXWebArea, which carries AXURL.
        var node = element(get(app, kAXFocusedUIElementAttribute))
        for _ in 0..<30 {
            guard let current = node else { break }
            let role = get(current, kAXRoleAttribute) as? String
            if role == "AXWebArea", let found = urlString(get(current, kAXURLAttribute)) { url = found; break }
            if role == kAXWindowRole { break }
            node = element(get(current, kAXParentAttribute))
        }
        if url == nil, let window { url = urlString(get(window, kAXDocumentAttribute)) }
        if let u = url, !(u.hasPrefix("http") || u.hasPrefix("/")) { url = nil } // skip about:blank, chrome:// etc.
        return (title, url)
    }

    /// Terminal.app routes drags to the running program when "Allow Mouse Reporting" is
    /// checked; then no native selection exists and nothing external can read it.
    func terminalMouseReportingOn(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        func get(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
            AXUIElementSetMessagingTimeout(e, 0.15)
            var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
        }
        guard let raw = get(app, kAXMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
        for top in get(raw as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            for menu in get(top, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                for item in get(menu, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                    let title = get(item, kAXTitleAttribute) as? String ?? ""
                    guard title.contains("鼠标报告") || title.localizedCaseInsensitiveContains("mouse reporting") else { continue }
                    let mark = get(item, kAXMenuItemMarkCharAttribute) as? String ?? ""
                    return !mark.isEmpty
                }
            }
        }
        return false
    }

    func read(_ request: CaptureRequest, cancellation: CaptureCancellation) -> AXReadResult {
        guard AXIsProcessTrusted() else { return .denied }
        guard !IsSecureEventInputEnabled() else { return .secure }
        if prepare(pid: request.pid) { Thread.sleep(forTimeInterval: 0.25) } // first contact: let the tree build
        let app = AXUIElementCreateApplication(request.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.60
        var sawEmpty = false, sawTimeout = false
        func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            guard !cancellation.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.2)
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, key as CFString, &value)
            if error == .cannotComplete { sawTimeout = true }
            return error == .success ? value : nil
        }
        func element(_ raw: CFTypeRef?) -> AXUIElement? {
            guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
            return (raw as! AXUIElement)
        }
        func isSecure(_ node: AXUIElement) -> Bool {
            let subrole = attribute(node, kAXSubroleAttribute) as? String ?? ""
            let role = attribute(node, kAXRoleAttribute) as? String ?? ""
            return subrole == kAXSecureTextFieldSubrole || role.lowercased().contains("secure")
        }
        var seeds = [AXUIElement]()
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var systemFocused = element(attribute(system, kAXFocusedUIElementAttribute))
        if let node = systemFocused { var pid: pid_t = 0; if AXUIElementGetPid(node, &pid) != .success || pid != request.pid { systemFocused = nil } }
        if let focused = systemFocused ?? element(attribute(app, kAXFocusedUIElementAttribute)) {
            var ancestor: AXUIElement? = focused
            for _ in 0..<7 {
                guard let node = ancestor else { break }
                let role = attribute(node, kAXRoleAttribute) as? String
                if role == kAXApplicationRole { break }
                if isSecure(node) { return .secure }
                seeds.append(node); ancestor = element(attribute(node, kAXParentAttribute))
                if role == kAXWindowRole { break }
            }
        }
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(app, Float(request.point.x), Float(request.point.y), &hit) == .success, let hit {
            var ancestor: AXUIElement? = hit
            for _ in 0..<6 {
                guard let node = ancestor else { break }
                let role = attribute(node, kAXRoleAttribute) as? String
                if role == kAXApplicationRole { break }
                if isSecure(node) { return .secure }
                seeds.append(node); ancestor = element(attribute(node, kAXParentAttribute))
                if role == kAXWindowRole { break }
            }
        }
        if let window = element(attribute(app, kAXFocusedWindowAttribute)) { seeds.append(window) }
        var queue = seeds.map { ($0, 0) }, visited = Set<CFHashCode>(), count = 0
        while !cancellation.isCancelled, !queue.isEmpty, count < 180, ProcessInfo.processInfo.systemUptime < deadline {
            let (node, depth) = queue.removeFirst()
            guard visited.insert(CFHash(node)).inserted else { continue }
            count += 1
            if isSecure(node) { continue }
            if let text = attribute(node, kAXSelectedTextAttribute) as? String {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text.count > 100_000 ? .tooLong : .text(text)
                }
                sawEmpty = true
            }
            // Chromium/WebKit web content (non-editable text) exposes the document
            // selection as a text-marker range on the web area and its descendants.
            if let marker = attribute(node, "AXSelectedTextMarkerRange") {
                var text: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(node, "AXStringForTextMarkerRange" as CFString, marker, &text) == .success,
                   let text = text as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text.count > 100_000 ? .tooLong : .text(text)
                }
            }
            // Public single/multiple ranges; some read-only controls omit SelectedText
            // or do not implement StringForRange, but expose a range and string Value.
            var rangeValues = [AXValue]()
            if let value = attribute(node, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() { rangeValues = [value as! AXValue] }
            if let values = attribute(node, kAXSelectedTextRangesAttribute) as? [AXValue], !values.isEmpty {
                guard values.count <= 32 else { return .complexSelection }
                rangeValues = values
            }
            var ranges = [NSRange](), pieces = [String](), allParameterized = true
            for axValue in rangeValues {
                var range = CFRange()
                if AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range), range.length > 0 {
                    guard range.location >= 0 else { continue }
                    guard range.length <= 400_000 else { return .tooLong }
                    ranges.append(NSRange(location: range.location, length: range.length))
                    guard !cancellation.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return .timeout }
                    var text: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(node, kAXStringForRangeParameterizedAttribute as CFString, axValue, &text) == .success, let text = text as? String { pieces.append(text) }
                    else { allParameterized = false }
                }
            }
            if !ranges.isEmpty {
                var selected: String?
                if allParameterized && pieces.count == ranges.count && !pieces.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { selected = pieces.joined(separator: "\n") }
                else if let value = attribute(node, kAXValueAttribute) as? String { selected = SelectionTextRange.extract(from: value, ranges: ranges) }
                if let selected, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return selected.count > 100_000 ? .tooLong : .text(selected) }
            }
            if depth < 5, let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(50).map { ($0, depth + 1) })
            }
        }
        if sawTimeout || ProcessInfo.processInfo.systemUptime >= deadline { return .timeout }
        return sawEmpty ? .empty : .unsupported
    }
}
