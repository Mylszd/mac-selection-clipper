import AppKit
import ApplicationServices
import ServiceManagement

final class SettingsWindowController: NSObject {
    unowned let owner: AppDelegate
    let window: NSWindow
    let path = NSTextField()
    let ignored = NSTextView()
    let diagnostic = NSButton(checkboxWithTitle: "本地诊断日志（仅应用 ID、结果与耗时，不含正文）", target: nil, action: nil)
    let login = NSButton(checkboxWithTitle: "登录后启动（需要保持此 App 的路径不变）", target: nil, action: nil)
    let compatibility = NSButton(checkboxWithTitle: "增强兼容：AX 读不到时自动「拷贝」取词并恢复剪贴板", target: nil, action: nil)
    let allApps = NSButton(checkboxWithTitle: "对所有应用启用（通过应用自己的「拷贝」菜单；Finder/程序坞除外）", target: nil, action: nil)
    let compatibleApps = NSTextView()
    let status = NSTextField(wrappingLabelWithString: "")
    init(owner: AppDelegate) {
        self.owner = owner
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Selection Clipper 设置"; window.isReleasedWhenClosed = false; window.center()
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        let storage = NSTextField(labelWithString: "摘录文件（每次保存追加到这个 Markdown 文件末尾；可手动输入新路径）")
        path.isEditable = true; path.placeholderString = AppDelegate.defaultInboxURL.path
        let choose = NSButton(title: "选择文件…", target: self, action: #selector(chooseDirectory))
        let reset = NSButton(title: "默认", target: self, action: #selector(resetPath))
        let row = NSStackView(views: [path, choose, reset])
        let exclude = NSTextField(wrappingLabelWithString: "忽略的应用 bundle ID（每行一个）。自身与安全输入始终排除；这无法识别全部敏感内容，阅读机密资料前请暂停。")
        ignored.font = .monospacedSystemFont(ofSize: 12, weight: .regular); ignored.isRichText = false
        let scroll = NSScrollView(); scroll.documentView = ignored; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        ignored.isVerticallyResizable = true; ignored.autoresizingMask = [.width]; ignored.textContainer?.widthTracksTextView = true
        let compatibleLabel = NSTextField(wrappingLabelWithString: "下列应用在找不到可用「拷贝」菜单时还会模拟 ⌘C（bundle ID，每行一个）；关闭「所有应用」时只对它们启用。忽略列表与安全输入始终优先。")
        compatibleApps.font = .monospacedSystemFont(ofSize: 12, weight: .regular); compatibleApps.isRichText = false
        compatibleApps.isVerticallyResizable = true; compatibleApps.autoresizingMask = [.width]; compatibleApps.textContainer?.widthTracksTextView = true
        let compatibleScroll = NSScrollView(); compatibleScroll.documentView = compatibleApps; compatibleScroll.hasVerticalScroller = true; compatibleScroll.borderType = .bezelBorder
        let save = NSButton(title: "应用设置", target: self, action: #selector(apply))
        let note = NSTextField(wrappingLabelWithString: "增强复制会短暂改动剪贴板并尽量恢复全部格式；并发复制存在无法完全避免的竞态。图片/文件承诺、密码标记或超过16MB备份会跳过。只在选区失败时短暂检查，不持续监听剪贴板；不会上传或自动保存。")
        note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize: 11)
        [storage, row, exclude, scroll, compatibility, allApps, compatibleLabel, compatibleScroll, diagnostic, login, note, save, status].forEach { root.addArrangedSubview($0) }
        let content = window.contentView!; content.addSubview(root); root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18), root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18), root.topAnchor.constraint(equalTo: content.topAnchor, constant: 18), root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18), row.widthAnchor.constraint(equalTo: root.widthAnchor), scroll.widthAnchor.constraint(equalTo: root.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 70), compatibleScroll.widthAnchor.constraint(equalTo: root.widthAnchor), compatibleScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 65)])
    }
    func show() {
        path.stringValue = owner.inboxURL.path
        ignored.string = owner.capture.ignored.sorted().joined(separator: "\n")
        diagnostic.state = UserDefaults.standard.bool(forKey: "diagnostics") ? .on : .off
        compatibility.state = owner.capture.compatibilityEnabled ? .on : .off
        allApps.state = owner.capture.compatibilityAllApps ? .on : .off
        compatibleApps.string = owner.capture.compatibilityApps.sorted().joined(separator: "\n")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        status.stringValue = "辅助功能：\(AXIsProcessTrusted() ? "已授权" : "未授权") · 输入监听：\(CGPreflightListenEventAccess() ? "已允许" : "未允许（仅在鼠标监听不可用时需要进一步排查）")"
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    @objc private func chooseDirectory() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = false; picker.canChooseFiles = true; picker.canCreateDirectories = true
        picker.allowedContentTypes = [.init(filenameExtension: "md")!]
        picker.prompt = "使用此文件"; picker.message = "选择一个已有的 Markdown 文件；要新建文件，直接在路径框里输入新路径。"
        picker.directoryURL = owner.inboxURL.deletingLastPathComponent()
        picker.beginSheetModal(for: window) { [weak self] result in
            if result == .OK, let url = picker.url { self?.path.stringValue = url.path }
        }
    }
    @objc private func resetPath() { path.stringValue = AppDelegate.defaultInboxURL.path }
    @objc private func apply() {
        if compatibility.state == .on && !owner.capture.compatibilityEnabled {
            let alert = NSAlert(); alert.messageText = "开启增强复制兼容？"
            alert.informativeText = "在明确拖选/双击且 AX 未读取到文字时，点击该应用的「拷贝」菜单（白名单应用必要时模拟 ⌘C）。会备份可读取的所有剪贴板格式并尝试恢复；无法完全避免与手动复制竞争、剪贴板历史工具记录复制内容、菜单闪烁或提示音。检测到其他写入时保留新内容，并提供手动恢复备份。机密内容请暂停。"
            alert.addButton(withTitle: "保持关闭"); alert.addButton(withTitle: "开启增强兼容")
            if alert.runModal() != .alertSecondButtonReturn { compatibility.state = .off }
        }
        let apps = Set(ignored.string.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        owner.capture.ignored = apps; owner.capture.invalidate()
        owner.capture.compatibilityEnabled = compatibility.state == .on
        owner.capture.compatibilityAllApps = allApps.state == .on
        UserDefaults.standard.set(allApps.state == .on, forKey: "copyFallbackAllApps")
        owner.capture.compatibilityApps = Set(compatibleApps.string.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        UserDefaults.standard.set(owner.capture.compatibilityEnabled, forKey: "copyFallbackEnabled")
        UserDefaults.standard.set(Array(owner.capture.compatibilityApps).sorted(), forKey: "copyFallbackApps")
        UserDefaults.standard.set(Array(apps).sorted(), forKey: "ignoredApps")
        UserDefaults.standard.set(diagnostic.state == .on, forKey: "diagnostics")
        let chosen = (path.stringValue.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        if chosen.isEmpty || chosen == AppDelegate.defaultInboxURL.path { UserDefaults.standard.removeObject(forKey: "inboxFilePath") }
        else { UserDefaults.standard.set(chosen.hasSuffix(".md") ? chosen : chosen + ".md", forKey: "inboxFilePath") }
        path.stringValue = owner.inboxURL.path; owner.renderMeta()
        do {
            if login.state == .on && SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            else if login.state == .off && SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            status.stringValue = "设置已应用。\(SMAppService.mainApp.status == .requiresApproval ? "请在系统登录项中完成批准。" : "")"
        } catch { status.stringValue = "其他设置已应用；登录启动设置失败：\(error.localizedDescription)" }
        owner.historyWindow?.reload()
    }
}
