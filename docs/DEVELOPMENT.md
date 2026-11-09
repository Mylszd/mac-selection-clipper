# Development

Swift package, macOS 13+, AppKit + ApplicationServices, no third-party dependencies. No Xcode project is needed: `swift build` plus a small bundling script produce the `.app`.

## Build and run

```bash
./scripts/test.sh     # behavioral checks (see below)
./scripts/build.sh    # release build -> dist/Mac Selection Clipper.app, signed
open "dist/Mac Selection Clipper.app"
```

- **Quit the running app before rebuilding.** Do not overwrite a running bundle.
- Run the packaged `.app`, not `swift run MacSelectionClipper`: the Accessibility permission belongs to the signed app bundle, not to your terminal.
- `build.sh` hashes its inputs; if nothing changed it keeps the existing bundle without re-signing.

### Signing

macOS ties the Accessibility (TCC) grant to the app's designated requirement. `build.sh` signs with, in order of preference:

1. `CLIPPER_SIGN_IDENTITY="<identity>"` if set (e.g. an existing Apple Development certificate);
2. the local identity `Mac Selection Clipper Local Signing`, if `scripts/create-signing-identity.sh` has created it — the designated requirement is then *bundle ID + certificate*, so rebuilds keep the permission;
3. otherwise an ad-hoc signature (`-`) — every code change alters the cdhash, so macOS may ask for the permission again.

`create-signing-identity.sh` makes a self-signed code-signing certificate with the system LibreSSL, imports it into the login keychain and marks it trusted for code signing. Set `CLIPPER_SIGN_BACKUP_DIR=<dir>` to also keep a `.p12` backup. None of this is a Developer ID; the app is not notarized.

Bundle ID: `io.github.mylszd.MacSelectionClipper`. Changing it invalidates existing Accessibility grants and starts with empty settings (UserDefaults are per bundle ID).

## Tests

```bash
./scripts/test.sh     # = swift run CoreChecks
```

Apple's Command Line Tools ship without XCTest, so `Tests/CoreChecks` is a plain executable with a few XCTest-style assertion helpers (`Tests/CoreChecks/main.swift`). It covers the pure logic in `ClipperCore` and `ClipperClipboard` — selection state and latest-wins sequencing, the mouse gesture filter, the save ledger, the inbox file format and idempotency, pasteboard archiving and the copy-fallback policy — and exits non-zero on failure.

These checks do **not** exercise Accessibility or real apps. Whether selection works in a given app can only be verified by hand with a real mouse; see [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

## Layout

```text
Package.swift
Sources/ClipperCore/            pure logic, no AppKit
  ClipRecord.swift              one captured clip (text, source app, window title, URL, time)
  SelectionState.swift          preview state, latest-wins sequence, CapturePolicy (privacy exclusions)
  MouseSelectionGesture.swift   tells a selection drag/double-click from an ordinary click
  SaveLedger.swift              pending/failed frozen saves, independent of the live preview
  InboxFileStore.swift          appends entries to the single Markdown clip file
  MarkdownFileStore.swift       legacy one-file-per-clip store (kept; its UI is hidden)
  SelectionTextRange.swift      range helpers for AX string ranges
Sources/ClipperClipboard/
  PasteboardArchive.swift       snapshot/restore all pasteboard formats; CopyFallbackPolicy
Sources/MacSelectionClipper/    the AppKit app
  main.swift, AppDelegate.swift bottom bar panel, menus, save flow
  BarControls.swift             hand-drawn save button and bar background
  SelectionEventMonitor.swift   mouse-only CGEvent tap (NSEvent global monitor as fallback)
  SelectionCaptureCoordinator.swift  debounce, serial capture queue, AX then copy fallback
  AXSelectionReader.swift       Accessibility reads (see ARCHITECTURE.md)
  ClipboardFallbackReader.swift Copy-menu / ⌘C fallback with clipboard restore
  CaptureCancellation.swift     cancels superseded captures
  SettingsWindowController.swift
  HistoryWindowController.swift legacy history window (menu entry hidden)
Tests/CoreChecks/               test executable
scripts/build.sh, test.sh, create-signing-identity.sh
scripts/diag/                   standalone AX diagnostic scripts (not part of the app)
```

## Settings keys

UserDefaults domain `io.github.mylszd.MacSelectionClipper`:

| Key | Meaning |
|---|---|
| `inboxFilePath` | clip file path (default `~/Library/Application Support/MacSelectionClipper/划词摘录.md`) |
| `ignoredApps` | bundle IDs never captured |
| `copyFallbackEnabled` | enable the copy fallback (default on) |
| `copyFallbackAllApps` | use the Copy-menu fallback in every app (default on) |
| `copyFallbackApps` | allowlist that may also receive a simulated ⌘C |
| `barPinned` | bar floats above other windows (default on) |
| `diagnostics` | metadata-only diagnostic log to stderr |

## Ground rules for changes

- Mouse events only. No keyboard monitoring, screenshots, OCR or network access.
- Diagnostic logs must never contain selected text.
- Never claim the clipboard is untouched: the fallback restores it, but restoration is not atomic.
- Use public APIs only (`AXManualAccessibility` is set through the public `AXUIElementSetAttributeValue`).
