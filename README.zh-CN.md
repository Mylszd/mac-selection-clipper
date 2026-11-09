# Mac Selection Clipper

[English](README.md) | 中文

在任意 Mac 应用里**用鼠标划选文字**，屏幕底部的小横条立刻显示预览；点一下「保存」，这段文字连同来源（App、窗口标题、网址）就追加到你指定的 Markdown 文件里。适合边读边摘，攒够了再统一整理（比如放进 Obsidian 的 Inbox，再让 AI 帮你归类）。

- 不用按快捷键，不用先复制，划完就有
- 原生 macOS 应用（Swift + AppKit），无第三方依赖，**不联网**，不截图、不 OCR
- 所有摘录追加到**同一个**文件，整理完删掉已处理的条目即可
- 在 ChatGPT、微信、Chrome、Terminal 等常见 App 里实测可用

> 界面目前只有中文。

## 系统要求

- macOS 13 或更高（在 macOS 27 / Apple Silicon 上开发测试）
- Swift 工具链：装 Xcode，或只装命令行工具 `xcode-select --install`

## 下载安装（推荐）

1. 在 [Releases](https://github.com/Mylszd/mac-selection-clipper/releases/latest) 下载 `MacSelectionClipper-x.y.z.zip`，双击解压，把 **Mac Selection Clipper.app** 拖进「应用程序」文件夹。
2. **第一次打开会被系统拦下**：这个 App 没有经过 Apple 公证（需要付费开发者账号），macOS 会提示「无法验证……是否包含恶意软件」。点「完成」，然后任选一种方式放行，只需一次：
   - 打开 系统设置 → 隐私与安全性，拉到下方，在「已阻止打开 Mac Selection Clipper」旁点 **仍要打开**，输入开机密码确认；
   - 或在终端运行：`xattr -dr com.apple.quarantine "/Applications/Mac Selection Clipper.app"`
3. 再打开 App，按下文授予辅助功能权限。

下载版同时支持 Apple Silicon 和 Intel（Intel 作者没有实测）。**更新到新版本后需要重新授权一次**：在辅助功能列表里删掉旧条目，再打开新版点「授权」。

不放心下载的二进制，可以从源码构建，见下一节。

## 从源码构建

没有 Apple 开发者账号，下载版没有公证；从源码构建则不会被拦截，配合本机证书后重新构建也不用重新授权。

```bash
git clone https://github.com/Mylszd/mac-selection-clipper.git
cd mac-selection-clipper
./scripts/test.sh                       # 可选：跑一遍自检
./scripts/create-signing-identity.sh    # 推荐：建本机签名证书（只需一次，见下文）
./scripts/build.sh                      # 生成 dist/Mac Selection Clipper.app
open "dist/Mac Selection Clipper.app"
```

想放进「应用程序」文件夹也可以：把 `dist/Mac Selection Clipper.app` 拖进 `/Applications`，以后从那里打开。构建出来的是本机架构（Apple Silicon 或 Intel）的程序；Intel 机器作者没有测试过。

### 为什么推荐建签名证书

macOS 是按「签名」来记住辅助功能权限的。不建证书时，每次重新构建签名都会变，系统就会忘记之前的授权，需要重新授权。

`scripts/create-signing-identity.sh` 会在你的「登录」钥匙串里建一个本机自签名证书（名称 `Mac Selection Clipper Local Signing`）。之后 `build.sh` 会自动用它签名，**授权一次以后就一直有效**。运行时 macOS 可能会：

- 要你输入开机密码（把证书设为信任）
- 在第一次构建签名时问「codesign 想使用钥匙串中的密钥」：点**始终允许**

这个证书只在你自己的电脑上有效，不是 Apple 开发者证书，也不能用来发布给别人。不想要了，可以在「钥匙串访问」里删除它。已有 Apple 开发证书的话，也可以用 `CLIPPER_SIGN_IDENTITY="证书名" ./scripts/build.sh` 指定。

## 第一次打开：授予辅助功能权限

1. 打开 App 后，横条上的按钮会显示「授权」，点它（或打开 系统设置 → 隐私与安全性 → 辅助功能）。
2. 在列表里打开 **Mac Selection Clipper**；如果列表里没有，点 `+` 选中这个 `.app`。
3. 授权后横条会提示「已获得辅助功能权限」，不用重启就能开始用。

只需要「辅助功能」权限。不需要屏幕录制、自动化或网络权限。

## 使用

App 没有 Dock 图标，打开后会出现**屏幕底部的横条**和**菜单栏图标**。

```
┌──────────────────────────────────────────────────────────────┐
│ [App图标]  ChatGPT · 14:32 · 120 字          [＋保存] [📌] [⌃] [⋯] │
│            选中文字的单行预览……                                 │
└──────────────────────────────────────────────────────────────┘
```

- **划词**：在任意 App 里拖选文字（或双击选词）并松开鼠标，横条就会显示预览。鼠标停在预览上能看到全文。
- **保存**：点「保存」，这条摘录追加到摘录文件；按钮会变成「✓ 已存」。不点保存就不会写进文件。
- **置顶**（图钉）：蓝色实心表示横条始终在所有窗口上方；点一下取消置顶，横条就会被其他窗口遮住，点横条可以把它调回前面。选择会被记住。
- **展开**（⌃）：在横条上方展开全文。
- **更多**（⋯）：打开摘录文件、复制当前全文、从剪贴板手动粘贴、清空预览、暂停/恢复、置顶/取消置顶、显示/隐藏横条、测试读取当前选区、设置、退出。菜单栏图标里是同一套菜单。
- 横条可以拖到任何位置，也可以拖左右边缘调宽（宽一些预览能显示更多字，按钮始终在最右侧）；位置和宽度会被记住。暂停时横条变半透明。

## 摘录存在哪里、长什么样

默认文件：`~/Library/Application Support/MacSelectionClipper/划词摘录.md`。
在 **设置 → 摘录文件** 里可以换成任何 `.md` 文件，比如 Obsidian 库里的 `Inbox/划词摘录.md`。如果文件在 Obsidian 库里，「打开摘录文件」会直接在 Obsidian 里打开它。

每次保存，在文件末尾追加一条：

```markdown
### 2026-11-09 14:32 · Google Chrome
> 来源：Google Chrome — 页面标题 · <https://example.com/article>

> 选中的原文，每一行都加了引用前缀
> 所以正文里的 # 标题、--- 分隔线不会打乱文件结构

<!-- clip:7A1C…（隐藏标记，防止重复保存） -->

---
```

App **只往末尾追加，不会改动已有内容**。整理时把有价值的内容挪走，再删掉对应条目（从 `###` 到 `---`）就行，新的摘录会继续追加。

## 能在哪些 App 里用

按以下顺序尝试读取，前一种读不到才用下一种：

1. **系统辅助功能接口（AX）**：直接读选中的文字，不碰剪贴板。对 Electron 应用（VS Code、Slack、Obsidian、飞书等）会先打开它们默认关闭的无障碍支持。
2. **点击该 App 的「拷贝」菜单**：AX 读不到时（比如微信），自动拷贝一次，读完**恢复你原来的剪贴板**。对所有 App 生效，Finder、程序坞等拖动文件/图标的地方除外。
3. **模拟 ⌘C**：只对设置里白名单中的 App（ChatGPT、微信、VS Code 等菜单状态不准的应用）在找不到可用拷贝菜单时使用。

作者实测（2026-11，macOS 27）：

| App | 结果 |
|---|---|
| ChatGPT 桌面版 | ✅ 可用 |
| 微信 4.x | ✅ 可用（通过拷贝菜单） |
| Chrome 网页 | ✅ 可用 |
| Terminal（包括在里面跑的 Claude Code） | ✅ 可用（需关闭「允许鼠标报告」，见下文） |
| 其他 App | 未逐一测试，欢迎在 Issues 里反馈 |

## 设置

菜单 → 设置…

- **摘录文件**：保存到哪个 `.md` 文件；可以选已有文件，或直接输入新路径（不存在会自动创建）。
- **忽略的应用**：这些 App 里划词完全不处理（默认已忽略钥匙串访问、1Password）。
- **增强兼容**：AX 读不到时是否自动「拷贝」取词；可以只对白名单启用，也可以完全关闭。
- **登录后启动**：开机自动运行（需要保持 App 的路径不变）。
- **本地诊断日志**：只记录 App 包名、结果和耗时，不记录正文。

## 常见问题

**划词没反应**
- 确认辅助功能权限已打开；横条上方一行会提示权限状态。
- 用 ⋯ →「测试读取当前选区」：先在目标 App 里选中文字，再点它，横条会说明读取结果。

**Terminal 里读不到（尤其是 Claude Code、vim 这类全屏程序）**
Terminal 的「显示 → 允许鼠标报告」开着时，鼠标拖选交给了终端里运行的程序，Terminal 本身没有选区，任何外部工具都读不到。按 **⌘R** 关闭它再划选。横条也会给出这个提示。

**某个 App 一直读不到**
有些 App 既不提供 AX 文字，也没有可用的拷贝菜单。可以在设置里把它的 bundle ID 加进增强兼容白名单（允许模拟 ⌘C）。bundle ID 用 `osascript -e 'id of app "应用名"'` 查。还不行就手动 ⌘C，再用 ⋯ →「从剪贴板手动粘贴」。

**重新构建后又要授权**
说明没有用本机证书签名，运行一次 `./scripts/create-signing-identity.sh` 再构建。

**会不会弄乱剪贴板？**
只有 AX 读不到时才会自动拷贝，并在约半秒内恢复原来的剪贴板（包括图片、富文本等全部格式）。如果这期间你自己也复制了东西，App 会保留你的新内容，把旧内容放在内存里，让你手动决定是否恢复。剪贴板历史工具可能会记下这一次自动拷贝。不需要的话在设置里关掉「增强兼容」。

## 隐私

- 不联网，不上传任何内容。
- 只监听鼠标按下、拖动、松开，不记录键盘输入，不截图、不 OCR。
- 预览只在内存里，点「保存」才写入你指定的文件。
- 密码框、安全输入状态、忽略列表里的 App 一律跳过。这是尽力保护，不能识别所有敏感内容；看机密内容前可以先暂停。

## 卸载

1. 菜单 →「退出 Selection Clipper」，删除 `Mac Selection Clipper.app`。
2. 系统设置 → 隐私与安全性 → 辅助功能：选中 Mac Selection Clipper，点 `−` 删除。
3. 可选：删除设置 `defaults delete io.github.mylszd.MacSelectionClipper`，删除文件夹 `~/Library/Application Support/MacSelectionClipper/`（**默认摘录文件也在里面，先确认不再需要**），在「钥匙串访问」里删除证书 `Mac Selection Clipper Local Signing`。

## 开发

- 构建、测试、目录结构：[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- 架构：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 已知限制：[docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)
- AX 诊断脚本（排查某个 App 为什么读不到）：[scripts/diag/](scripts/diag/)

欢迎提 Issue 和 PR，尤其是「某个 App 能不能用」的反馈。

## 许可证

[MIT](LICENSE)
