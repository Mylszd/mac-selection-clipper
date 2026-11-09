# Architecture

## Capture pipeline

```
mouse down / drag / up (CGEvent tap, mouse events only)
  -> MouseSelectionGesture: was this a selection (drag or double-click), not a plain click?
  -> resolve the app under the pointer at mouse-up (PID, bundle ID, name)
  -> CapturePolicy: skip own app, ignored apps, Secure Input
  -> 100 ms debounce, then a serial capture queue (a newer gesture cancels older work)
  -> AXSelectionReader
  -> if AX found nothing: ClipboardFallbackReader (per CopyFallbackPolicy)
  -> SelectionState accepts the result only if its sequence number is still the latest
  -> preview in the bottom bar (memory only)
```

The event monitor prefers a passive, listen-only `CGEvent` session tap for mouse down/drag/up and falls back to an `NSEvent` global monitor. Source and privacy checks are resolved at mouse-up, so clicking into another app does not invalidate a legitimate selection.

### Reading the selection with Accessibility

`AXSelectionReader` starts from the focused element and the element under the pointer, then explores a bounded neighbourhood (ancestors up to the window, a few levels of descendants; at most 180 nodes / 600 ms; each AX call has its own timeout). For each candidate it tries, in order:

1. `AXSelectedText`;
2. `AXSelectedTextMarkerRange` + `AXStringForTextMarkerRange` (WebKit / Chromium web content);
3. `AXSelectedTextRange(s)` + `AXStringForRange`, or a slice of `AXValue`.

Before the first read in an app (and whenever an app is activated) it sets `AXManualAccessibility = true` on the application element. That is Electron's documented switch for turning on its accessibility tree, which is off by default; it is set through the public `AXUIElementSetAttributeValue`.

Password fields (`AXSecureTextField`) are never read. More than 100,000 characters is rejected with a message rather than silently truncated.

### Copy fallback

Some apps expose no selected text through AX (WeChat, terminal emulators in some states, custom-drawn views). If AX returns empty / unsupported / timeout for a mouse selection, `CopyFallbackPolicy` decides:

- **menuOnly** (any app, when `copyFallbackAllApps` is on): press the app's own *enabled* Copy menu item via AX.
- **menuOrKey** (apps on the `copyFallbackApps` allowlist): as above, and if no usable Copy item exists, post ⌘C.
- **never**: Finder, Dock, SystemUIServer and similar places where a drag moves files or icons.

`PasteboardArchive` snapshots every item and type on the pasteboard first. If nothing is written within 600 ms there was no selection and the clipboard was never touched. Otherwise the plain text is read and the snapshot restored, guarded by `changeCount`. If another write races with the restore, the newer content wins and the old snapshot stays in memory for manual recovery. Non-text copies (files, images) are restored silently. If the current pasteboard holds concealed, transient or promised types (e.g. a copied password), it cannot be archived safely, so no copy is attempted and the bar reports a clipboard issue instead.

## Saving

Clicking **Save** freezes the current preview (UUID + text + source) into `SaveLedger` and hands it to a serial disk queue. `InboxFileStore` appends one entry to the end of the clip file through a `FileHandle`, never rewriting existing content. The entry ends with `<!-- clip:UUID -->`, which makes retries idempotent. A failed save stays in the ledger with a retry action even after newer selections. Quitting waits for the disk queue and cancels if a save failed.

If the clip file lives inside an Obsidian vault (a parent directory contains `.obsidian`), "Open clip file" uses an `obsidian://` URL; otherwise the file opens in the default app.

## UI

A borderless, non-activating `NSPanel` at the bottom of the screen (58 pt high, width resizable, frame autosaved as `ClipperBar`). It never becomes key, so it does not steal focus from the app you are reading. A horizontal `NSStackView` puts the icon and text in its leading gravity area and the buttons in its trailing area, so the buttons stay on the right edge. The primary button is drawn by hand (`PillButton`) because a stock bezel button renders gray in a window that is never key. Pinned = `.floating` level and visible over full-screen apps; unpinned = `.normal` level.

## References

- Apple: [AXUIElementCopyAttributeValue](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue), [kAXSelectedTextAttribute](https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute), [NSEvent global monitors](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)), [nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
- Electron: [AXManualAccessibility](https://www.electronjs.org/docs/latest/tutorial/accessibility)
- Prior art studied for usage and permission guidance (no code copied): [Easydict](https://github.com/tisfeng/Easydict) (GPL-3.0)
