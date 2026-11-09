import AppKit
import ApplicationServices
let bid = CommandLine.arguments[1]
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first else { exit(0) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
func get(_ e: AXUIElement, _ k: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
var seen = [String: Int]()
func walk(_ e: AXUIElement, _ d: Int) {
    guard d < 30 else { return }
    let role = get(e, "AXRole") as? String ?? "?"
    var names: CFArray?; AXUIElementCopyAttributeNames(e, &names)
    var pnames: CFArray?; AXUIElementCopyParameterizedAttributeNames(e, &pnames)
    let n = (names as? [String]) ?? [], p = (pnames as? [String]) ?? []
    let key = "\(role) | sel:\(n.contains("AXSelectedText")) range:\(n.contains("AXSelectedTextRange")) marker:\(n.contains("AXSelectedTextMarkerRange")) strForRange:\(p.contains("AXStringForRange")) strForMarker:\(p.contains("AXStringForTextMarkerRange"))"
    if role.contains("Text") || role.contains("Web") || n.contains("AXSelectedText") || n.contains("AXSelectedTextMarkerRange") { seen[key, default: 0] += 1 }
    for k in (get(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(k, d+1) }
}
walk(ax, 0)
print("== \(bid)"); for (k, v) in seen.sorted(by: { $0.key < $1.key }) { print("  \(v)x \(k)") }
