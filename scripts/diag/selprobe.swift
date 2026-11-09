import AppKit
import ApplicationServices
// Usage: selprobe [delaySeconds]  -> select text in target app, switch to it, wait.
let delay = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1])! : 5
print("请在 \(Int(delay)) 秒内切到目标 App 并保持选区…"); Thread.sleep(forTimeInterval: delay)
guard let app = NSWorkspace.shared.frontmostApplication else { exit(1) }
print("目标: \(app.localizedName ?? "?") \(app.bundleIdentifier ?? "?") pid=\(app.processIdentifier)")
let ax = AXUIElementCreateApplication(app.processIdentifier)
func get(_ e: AXUIElement, _ k: String) -> (AXError, CFTypeRef?) { var v: CFTypeRef?; let r = AXUIElementCopyAttributeValue(e, k as CFString, &v); return (r, v) }
func pget(_ e: AXUIElement, _ k: String, _ p: CFTypeRef) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyParameterizedAttributeValue(e, k as CFString, p, &v) == .success ? v : nil }
func show(_ s: String) -> String { let t = s.replacingOccurrences(of: "\n", with: "⏎"); return "len=\(s.count) \"\(t.prefix(50))\(t.count > 50 ? "…" : "")\"" }
func focused() -> AXUIElement? {
    let sys = AXUIElementCreateSystemWide()
    if let f = get(sys, "AXFocusedUIElement").1 { return (f as! AXUIElement) }
    if let f = get(ax, "AXFocusedUIElement").1 { return (f as! AXUIElement) }
    return nil
}
func tryAll(_ tag: String) -> Bool {
    guard let f = focused() else { print("[\(tag)] 拿不到焦点元素"); return false }
    var ok = false, node: AXUIElement? = f, depth = 0
    while let n = node, depth < 12 {
        let role = get(n, "AXRole").1 as? String ?? "?"
        let (e1, st) = get(n, "AXSelectedText")
        if let s = st as? String, !s.isEmpty { print("[\(tag)] ✅ AXSelectedText @\(role)(d\(depth)) \(show(s))"); ok = true }
        if let r = get(n, "AXSelectedTextRange").1, let s = pget(n, "AXStringForRange", r) as? String, !s.isEmpty { print("[\(tag)] ✅ Range+StringForRange @\(role)(d\(depth)) \(show(s))"); ok = true }
        if let m = get(n, "AXSelectedTextMarkerRange").1, let s = pget(n, "AXStringForTextMarkerRange", m) as? String, !s.isEmpty { print("[\(tag)] ✅ TextMarker @\(role)(d\(depth)) \(show(s))"); ok = true }
        if depth == 0 { print("[\(tag)] focused role=\(role) AXSelectedText err=\(e1.rawValue)") }
        if ok { return true }
        if role == "AXWindow" { break }
        node = get(n, "AXParent").1.map { $0 as! AXUIElement }; depth += 1
    }
    print("[\(tag)] ❌ 焦点链上所有方法都没读到选区"); return false
}
if tryAll("纯读取") { exit(0) }
let r = AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
print("设置 AXManualAccessibility -> \(r.rawValue == 0 ? "成功(Electron)" : "err \(r.rawValue)")")
Thread.sleep(forTimeInterval: 0.5)
if tryAll("开启无障碍树后") { exit(0) }
print("→ 该 App/控件 AX 拿不到，只能走 ⌘C 复制兜底")
