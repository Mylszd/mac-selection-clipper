import AppKit
import ApplicationServices
let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first!
let ax = AXUIElementCreateApplication(app.processIdentifier)
func get(_ e: AXUIElement, _ k: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
var last = ""
let end = Date().addingTimeInterval(180)
while Date() < end {
    var lines = [String]()
    func walk(_ e: AXUIElement) { if (get(e,"AXRole") as? String) == "AXTextArea" { let s = get(e,"AXSelectedText") as? String ?? "nil"; lines.append("selLen=\(s.count)") }; for k in (get(e,"AXChildren") as? [AXUIElement]) ?? [] { walk(k) } }
    walk(ax)
    let cur = lines.joined(separator: ",") + " clipboardChange=\(NSPasteboard.general.changeCount)"; if cur != last { print(Date(), cur); fflush(stdout); last = cur }
    Thread.sleep(forTimeInterval: 0.2)
}
