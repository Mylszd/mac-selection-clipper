# Known limitations

- **Build from source only.** There is no notarized build. Without the local signing certificate, every rebuild may require granting Accessibility again.
- **Tested on few apps.** Verified by hand (macOS 27, Apple Silicon) in ChatGPT, WeChat 4.x, Chrome and Terminal. Other apps, Intel Macs, macOS 13–15, multiple displays, Spaces and full-screen apps have not been tested systematically.
- **Some apps cannot be read at all.** Apps that expose neither selected text through Accessibility nor a usable Copy command (canvas-based editors, some games and remote-desktop clients) will not work. Manual ⌘C plus "paste from clipboard" is the workaround.
- **Electron apps on the first selection.** Turning on an Electron app's accessibility tree takes a moment; the very first selection after the app launches may come back empty. Select again.
- **Terminal with mouse reporting.** When a full-screen terminal program owns the mouse (Allow Mouse Reporting on), Terminal has no native selection. Turn it off with ⌘R.
- **The copy fallback briefly changes the clipboard.** The previous contents are restored within about half a second, but restoration is not atomic, and clipboard history tools may record the automatic copy. Turn the fallback off in Settings if that matters.
- **Privacy exclusions are best effort.** Password fields, Secure Input and ignored apps are skipped; other sensitive text cannot be recognized. Pause before reading confidential material.
- **Unsaved previews live in memory only.** A crash or force quit loses the current preview and any failed save waiting for retry.
- **Very long selections** (over 100,000 characters) are rejected rather than truncated.
- **Launch at login** uses `SMAppService` and may need approval in System Settings → General → Login Items. Keep the app at a fixed path.
- **Chinese-only UI** for now.
