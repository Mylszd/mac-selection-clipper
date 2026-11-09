# Mac Selection Clipper

English | [中文](README.zh-CN.md)

**Select text with the mouse in any Mac app**, and a slim bar at the bottom of the screen shows a preview right away. Click **Save** and the text is appended, together with its source (app, window title, URL), to a Markdown file of your choice. Made for clipping while you read and sorting it all out later — for example into an Obsidian inbox that you (or an AI) tidy up periodically.

- No hotkey, no copying first — just select
- Native macOS app (Swift + AppKit), no third-party dependencies, **no network access**, no screenshots, no OCR
- Every clip goes into **one** file; delete entries once you have processed them
- Verified in ChatGPT, WeChat, Chrome and Terminal

> The user interface is currently in Chinese only. The labels you will see are listed in [UI labels](#ui-labels) below.

## Requirements

- macOS 13 or later (developed and tested on macOS 27, Apple Silicon)
- A Swift toolchain: Xcode, or just the Command Line Tools (`xcode-select --install`)

## Download (recommended)

1. Download `MacSelectionClipper-x.y.z.zip` from [Releases](https://github.com/Mylszd/mac-selection-clipper/releases/latest), unzip it, and drag **Mac Selection Clipper.app** into Applications.
2. **macOS blocks the first launch.** The app is not notarized by Apple (that needs a paid developer account), so macOS says it cannot verify the app is free of malware. Click **Done**, then allow it once, either way:
   - System Settings → Privacy & Security, scroll down, click **Open Anyway** next to "Mac Selection Clipper was blocked", and confirm with your password; or
   - in Terminal: `xattr -dr com.apple.quarantine "/Applications/Mac Selection Clipper.app"`
3. Open the app again and grant the Accessibility permission (below).

The download is a universal build for Apple Silicon and Intel (Intel has not been tested). **After updating to a new version, grant the permission again**: remove the old entry from the Accessibility list, open the new version and click 授权.

If you would rather not run a downloaded binary, build from source (next section).

## Build from source

Builds made on your own Mac are not blocked by Gatekeeper, and with the local certificate rebuilds keep the permission.

```bash
git clone https://github.com/Mylszd/mac-selection-clipper.git
cd mac-selection-clipper
./scripts/test.sh                       # optional: run the self-checks
./scripts/create-signing-identity.sh    # recommended: one-time local signing certificate (see below)
./scripts/build.sh                      # produces dist/Mac Selection Clipper.app
open "dist/Mac Selection Clipper.app"
```

You can drag `dist/Mac Selection Clipper.app` into `/Applications` and launch it from there. The build targets your machine's architecture; Intel Macs have not been tested.

### Why create a signing certificate?

macOS remembers the Accessibility permission by code signature. Without a stable certificate, every rebuild changes the signature, macOS forgets the permission, and you have to grant it again.

`scripts/create-signing-identity.sh` creates a local self-signed certificate (`Mac Selection Clipper Local Signing`) in your login keychain. `build.sh` then signs with it automatically, so **you grant the permission once and it sticks**. While it runs, macOS may:

- ask for your login password (to trust the certificate), and
- on the first build, ask whether codesign may use the key: choose **Always Allow**.

The certificate only works on your own Mac. It is not an Apple Developer certificate and cannot be used to distribute the app. Delete it in Keychain Access whenever you like. If you already have an Apple development certificate, use `CLIPPER_SIGN_IDENTITY="<name>" ./scripts/build.sh` instead.

## First launch: grant Accessibility permission

1. After launch, the button on the bar reads **授权** (Authorize). Click it, or open System Settings → Privacy & Security → Accessibility.
2. Turn on **Mac Selection Clipper**. If it is not in the list, click `+` and pick the `.app`.
3. The bar then says it has the permission. No restart needed.

Accessibility is the only permission it needs — no Screen Recording, Automation or network.

## Usage

There is no Dock icon. After launch you get **a bar at the bottom of the screen** and **a menu bar icon**.

```
┌──────────────────────────────────────────────────────────────┐
│ [app icon]  ChatGPT · 14:32 · 120 chars     [+Save] [📌] [⌃] [⋯] │
│             one-line preview of the selection…                │
└──────────────────────────────────────────────────────────────┘
```

- **Select**: drag-select text (or double-click a word) in any app and release the mouse; the bar shows a preview. Hover the preview to see the full text.
- **Save** (保存): appends the clip to your clip file; the button turns into **✓ 已存** (Saved). Nothing is written unless you click Save.
- **Pin** (📌): filled blue = the bar stays above all windows. Click to unpin; other windows can then cover it, and clicking the bar brings it back. The choice is remembered.
- **Expand** (⌃): shows the full text above the bar.
- **More** (⋯): open the clip file, copy the full text, paste manually from the clipboard, clear the preview, pause/resume, pin/unpin, show/hide the bar, test-read the current selection, settings, quit. The menu bar icon has the same menu.
- Drag the bar anywhere, or drag its left/right edge to resize (wider = more preview text; the buttons stay on the right). Position and width are remembered. The bar turns translucent while paused.

### UI labels

| Label | Meaning |
|---|---|
| 保存 / ✓ 已存 / 授权 | Save / Saved / Grant permission |
| 打开摘录文件 | Open clip file |
| 复制当前全文 | Copy the full text |
| 从剪贴板手动粘贴 | Paste from clipboard manually |
| 清空预览 | Clear the preview |
| 暂停自动划词 / 恢复自动划词 | Pause / Resume capturing |
| 置顶横条 / 取消置顶 | Pin the bar on top / Unpin |
| 显示横条 / 隐藏横条 | Show / Hide the bar |
| 测试读取当前选区 | Test-read the current selection |
| 设置… / 退出 Selection Clipper | Settings… / Quit |

## Where clips go and what they look like

Default file: `~/Library/Application Support/MacSelectionClipper/划词摘录.md` ("划词摘录" = "selection clips").
Change it under **Settings → 摘录文件** (clip file) to any `.md` file, e.g. `Inbox/clips.md` in an Obsidian vault. When the file is inside a vault, "Open clip file" opens it in Obsidian.

Each save appends one entry to the end of the file:

```markdown
### 2026-11-09 14:32 · Google Chrome
> 来源：Google Chrome — Page title · <https://example.com/article>

> The selected text, with every line quoted,
> so headings or --- rules inside it cannot break the file structure

<!-- clip:7A1C… (hidden marker that prevents duplicate saves) -->

---
```

(`来源` = "source".) The app **only appends; it never rewrites existing content**. To process clips, move what you want elsewhere and delete those entries (from `###` to `---`); new clips keep being appended.

## Which apps work

It tries these methods in order, falling back only when the previous one finds nothing:

1. **Accessibility API (AX)** reads the selected text directly, without touching the clipboard. For Electron apps (VS Code, Slack, Obsidian, Lark, …) it first turns on their accessibility tree, which is off by default.
2. **The app's own Copy menu item.** When AX finds nothing (WeChat, for example), it copies once and then **restores your previous clipboard**. This applies to every app except places where dragging moves files or icons (Finder, the Dock, …).
3. **Simulated ⌘C**, only for apps on the allowlist in Settings (ChatGPT, WeChat, VS Code and others whose menu state is unreliable), and only when no usable Copy menu item is found.

Tested by the author (2026-11, macOS 27):

| App | Result |
|---|---|
| ChatGPT desktop | ✅ Works |
| WeChat 4.x | ✅ Works (via the Copy menu) |
| Web pages in Chrome | ✅ Works |
| Terminal (including Claude Code running inside it) | ✅ Works (turn off "Allow Mouse Reporting", see below) |
| Other apps | Not tested one by one — reports welcome in Issues |

## Settings

Menu → 设置… (Settings…)

- **摘录文件** (clip file): which `.md` file to append to. Pick an existing file or type a new path (it is created if missing).
- **忽略的应用** (ignored apps): selections in these apps are ignored entirely (Keychain Access and 1Password by default).
- **增强兼容** (enhanced compatibility): whether to fall back to copying when AX finds nothing — for every app, only for the allowlist, or never.
- **登录后启动** (launch at login): keep the app at a fixed path for this to work.
- **本地诊断日志** (local diagnostic log): records only app bundle IDs, results and timings — never the text.

## FAQ

**Nothing happens when I select text**
- Check that Accessibility permission is on; the top line of the bar shows the permission state.
- Use ⋯ → 测试读取当前选区 (test-read the current selection): select text in the target app first, then click it; the bar explains what happened.

**It cannot read Terminal (especially full-screen programs such as Claude Code or vim)**
When Terminal's View → Allow Mouse Reporting is on, mouse drags go to the program running inside the terminal, so Terminal itself has no selection and no external tool can read one. Press **⌘R** to turn it off, then select again. The bar shows this hint too.

**One particular app never works**
Some apps expose neither AX text nor a usable Copy menu item. Add the app's bundle ID to the compatibility allowlist in Settings (allows simulated ⌘C). Find the bundle ID with `osascript -e 'id of app "App Name"'`. If that still fails, press ⌘C yourself and use ⋯ → 从剪贴板手动粘贴 (paste from clipboard manually).

**It asks for permission again after every rebuild**
You are not signing with the local certificate. Run `./scripts/create-signing-identity.sh` once and rebuild.

**Will it mess up my clipboard?**
It copies only when AX finds nothing, and restores your previous clipboard (all formats, including images and rich text) within about half a second. If you copy something yourself in that window, the app keeps your new content and holds the old one in memory so you can restore it by hand. Clipboard history tools may record that one automatic copy. Turn off enhanced compatibility in Settings if you do not want any of this.

## Privacy

- No network access; nothing is uploaded.
- It only listens to mouse down, drag and up. No keyboard logging, no screenshots, no OCR.
- Previews live in memory only; text is written to disk only when you click Save, and only to the file you chose.
- Password fields, Secure Input and ignored apps are always skipped. This is best-effort and cannot recognize every kind of sensitive text; pause the app before reading confidential material.

## Uninstall

1. Menu → 退出 Selection Clipper (Quit), then delete `Mac Selection Clipper.app`.
2. System Settings → Privacy & Security → Accessibility: select Mac Selection Clipper and click `−`.
3. Optional: remove its settings with `defaults delete io.github.mylszd.MacSelectionClipper`, delete `~/Library/Application Support/MacSelectionClipper/` (**the default clip file lives there — make sure you no longer need it**), and delete the `Mac Selection Clipper Local Signing` certificate in Keychain Access.

## Development

- Build, test and project layout: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Known limitations: [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)
- AX diagnostic scripts (find out why an app cannot be read): [scripts/diag/](scripts/diag/)

Issues and pull requests are welcome — especially reports on whether a particular app works.

## License

[MIT](LICENSE)
