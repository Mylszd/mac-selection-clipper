# AX diagnostic scripts

Standalone scripts for finding out why a particular app cannot be read. They are not part of the app build.

The terminal that runs them needs the Accessibility permission. Compile with `swiftc -O <file>.swift -o /tmp/<name>`.

| Script | Purpose |
|---|---|
| `selprobe.swift [seconds]` | Select text in the target app, run this, and switch back to the target app within N seconds. Reports whether AXSelectedText / range + StringForRange / TextMarker each return text; if not, enables AXManualAccessibility and retries. |
| `axtree.swift <bundleID> [enable]` | Counts nodes in the app's AX tree. With `enable`, compares before and after setting AXManualAccessibility / AXEnhancedUserInterface (is the Electron tree switched off?). |
| `attrs.swift <bundleID>` | Lists which roles support SelectedText / Range / TextMarker attributes. |
| `roles.swift <bundleID>` | Role histogram, number of nodes with a string AXValue, and the ⌘C menu item (does the app expose any text at all?). |
| `termwatch.swift` | Watches Terminal's text-area selection length and the pasteboard changeCount for 180 seconds. |
| `tmenu.swift` | Reads the state of Terminal's Copy and Allow Mouse Reporting menu items. |
