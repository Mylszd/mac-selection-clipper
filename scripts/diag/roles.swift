import AppKit
import ApplicationServices
let app = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]).first!
let ax = AXUIElementCreateApplication(app.processIdentifier)
func get(_ e: AXUIElement, _ k: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
var counts = [String: Int](); var withValue = 0
func walk(_ e: AXUIElement, _ d: Int) { guard d < 40 else { return }
  let r = get(e, "AXRole") as? String ?? "?"; counts[r, default: 0] += 1
  if let v = get(e, "AXValue") as? String, !v.isEmpty { withValue += 1 }
  for k in (get(e, "AXChildren") as? [AXUIElement]) ?? [] { walk(k, d+1) } }
walk(ax, 0); print(counts.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")); print("nodes with string AXValue:", withValue)
let bar = get(ax, "AXMenuBar") as! AXUIElement
for top in (get(bar,"AXChildren") as? [AXUIElement]) ?? [] { for m in (get(top,"AXChildren") as? [AXUIElement]) ?? [] { for i in (get(m,"AXChildren") as? [AXUIElement]) ?? [] {
  if (get(i,"AXMenuItemCmdChar") as? String) == "C" { print("copy menu:", get(i,"AXTitle") as? String ?? "", "mods", get(i,"AXMenuItemCmdModifiers") ?? "nil" as CFTypeRef) } } } }
