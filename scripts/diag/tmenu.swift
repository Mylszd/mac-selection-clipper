import AppKit
import ApplicationServices
let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first!
let ax = AXUIElementCreateApplication(app.processIdentifier)
func get(_ e: AXUIElement, _ k: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
let bar = get(ax, "AXMenuBar") as! AXUIElement
for top in (get(bar,"AXChildren") as? [AXUIElement]) ?? [] { for m in (get(top,"AXChildren") as? [AXUIElement]) ?? [] { for i in (get(m,"AXChildren") as? [AXUIElement]) ?? [] {
  let t = get(i,"AXTitle") as? String ?? ""
  if t.contains("鼠标") || t.lowercased().contains("mouse") || t.contains("拷贝") || t.lowercased() == "copy" { print(t, "enabled=\(get(i,"AXEnabled") as? Bool ?? false)", "mark=\(get(i,"AXMenuItemMarkChar") as? String ?? "none")", "cmd=\(get(i,"AXMenuItemCmdChar") as? String ?? "")") }
}}}
