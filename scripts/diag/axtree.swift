import AppKit
import ApplicationServices
// Usage: probe <bundleID> [enable]
let args = CommandLine.arguments
let bid = args[1]; let enable = args.count > 2
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first else { print("\(bid): not running"); exit(0) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
func get(_ e: AXUIElement, _ k: String) -> (AXError, CFTypeRef?) { var v: CFTypeRef?; let r = AXUIElementCopyAttributeValue(e, k as CFString, &v); return (r, v) }
func count(_ e: AXUIElement, depth: Int, budget: inout Int) {
    guard depth < 25, budget > 0 else { return }; budget -= 1
    if let kids = get(e, "AXChildren").1 as? [AXUIElement] { for k in kids { count(k, depth: depth+1, budget: &budget) } }
}
func report(_ tag: String) {
    let wins = (get(ax, "AXWindows").1 as? [AXUIElement])?.count ?? -1
    let f = get(ax, "AXFocusedUIElement")
    var role = "-"
    if let fe = f.1 { role = (get(fe as! AXUIElement, "AXRole").1 as? String) ?? "?" }
    var budget = 3000; count(ax, depth: 0, budget: &budget)
    print("[\(tag)] windows=\(wins) focusedErr=\(f.0.rawValue) focusedRole=\(role) treeNodes=\(3000-budget)")
}
print("\(bid) pid=\(app.processIdentifier)")
report("before")
if enable {
    let r1 = AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    let r2 = AXUIElementSetAttributeValue(ax, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    print("set AXManualAccessibility=\(r1.rawValue) AXEnhancedUserInterface=\(r2.rawValue)")
    Thread.sleep(forTimeInterval: 1.5)
    report("after")
}
