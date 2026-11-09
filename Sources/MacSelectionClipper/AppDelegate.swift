import AppKit
import ApplicationServices
import ClipperCore

final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// When not pinned, other windows may cover the bar; a click brings it back to the front
    /// (a non-activating panel is never raised by clicking on its own).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, level == .normal { orderFrontRegardless() }
        super.sendEvent(event)
    }
}

/// Bottom-of-screen horizontal bar: [app icon] [meta line / one-line preview] ……… [保存][置顶][展开][⋯] (buttons pinned right)
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let capture = SelectionCaptureCoordinator()
    var state = SelectionState()
    var panel: PreviewPanel!
    var statusItem: NSStatusItem!
    // Bar views
    let iconView = NSImageView()
    let metaLabel = NSTextField(labelWithString: "")
    let previewLabel = NSTextField(labelWithString: "")
    let saveButton = PillButton()
    var expandButton: NSButton!
    var moreButton: NSButton!
    var detailScroll: NSScrollView!
    var textView = NSTextView()
    var expanded = false
    var pinButton: NSButton!
    var pinned: Bool {
        get { UserDefaults.standard.object(forKey: "barPinned") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "barPinned") }
    }
    static let barHeight: CGFloat = 58, detailHeight: CGFloat = 190
    // State
    var saves = SaveLedger()
    var terminating = false
    var pausedBeforeTermination = false
    var saveFailureMessage: String?
    var metaResetWork: DispatchWorkItem?
    let disk = DispatchQueue(label: "clipper.disk", qos: .userInitiated)
    var historyWindow: HistoryWindowController?
    var settingsWindow: SettingsWindowController?

    /// Apps that may also receive a synthesized ⌘C when no usable Copy menu item is found.
    static let defaultKeyCopyApps = ["com.openai.codex", "com.openai.chat", "com.anthropic.claudefordesktop", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "md.obsidian", "abnerworks.Typora", "com.tinyspeck.slackmacgap", "com.electron.lark", "com.apple.Terminal", "com.tencent.xinWeChat"]
    var lastTrusted = AXIsProcessTrusted()
    /// The single inbox file every saved clip is appended to.
    /// Default when the user has not chosen a file in Settings (e.g. a note inside an Obsidian vault).
    static var defaultInboxURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacSelectionClipper/划词摘录.md")
    }
    var inboxURL: URL {
        if let custom = UserDefaults.standard.string(forKey: "inboxFilePath"), !custom.isEmpty { return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath) }
        return Self.defaultInboxURL
    }
    var inbox: InboxFileStore { InboxFileStore(fileURL: inboxURL) }
    // Legacy one-file-per-clip store, still used by the (hidden) history window.
    var store: MarkdownFileStore { MarkdownFileStore(root: storageURL) }
    var storageURL: URL {
        if let custom = UserDefaults.standard.string(forKey: "storagePath"), !custom.isEmpty { return URL(fileURLWithPath: custom) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacSelectionClipper/clips")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel(); applyPinned(); buildMenu()
        capture.ignored = Set(UserDefaults.standard.stringArray(forKey: "ignoredApps") ?? ["com.apple.keychainaccess", "com.1password.1password", "com.agilebits.onepassword7"])
        // Default ON for a narrow allowlist of apps whose selections AX often cannot read
        // (Electron/Chromium chat & editors). Turn off in Settings at any time.
        capture.compatibilityEnabled = UserDefaults.standard.object(forKey: "copyFallbackEnabled") as? Bool ?? true
        capture.compatibilityAllApps = UserDefaults.standard.object(forKey: "copyFallbackAllApps") as? Bool ?? true
        capture.compatibilityApps = Set(UserDefaults.standard.stringArray(forKey: "copyFallbackApps") ?? Self.defaultKeyCopyApps)
        capture.clipboard.onRecoveryChanged = { [weak self] exists in
            if exists { self?.showMeta("原剪贴板备份待处理 · 点 ⋯ 处理", tone: .warning, sticky: true) }
        }
        capture.excludedPoint = { point in NSApp.windows.contains { $0.isVisible && $0.frame.contains(point) } }
        capture.onActivity = { [weak self] in self?.renderMeta() }
        capture.onResult = { [weak self] request, result, ms in self?.receive(request, result, ms) }
        capture.onDiagnostic = { message in if UserDefaults.standard.bool(forKey: "diagnostics") { NSLog("mouse %@", message) } }
        capture.start(); panel.orderFrontRegardless(); panel.invalidateShadow()
        renderIdle(); refreshPermissions()
        // Refresh permission status only, never scan foreground text on a timer.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermissions() }
    }

    // MARK: - Bar UI

    func buildPanel() {
        panel = PreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: Self.barHeight), styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.minSize = NSSize(width: 420, height: Self.barHeight)
        panel.maxSize = NSSize(width: 1600, height: Self.barHeight)
        panel.setFrameAutosaveName("ClipperBar")
        if !panel.setFrameUsingName("ClipperBar"), let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrame(NSRect(x: vf.midX - 320, y: vf.minY + 24, width: 640, height: Self.barHeight), display: false)
        }

        let background = BarBackground()
        background.material = .popover; background.blendingMode = .behindWindow; background.state = .active
        // Behind-window materials ignore layer masking, so clip the material with a
        // stretchable rounded mask image; otherwise square corners show behind the bar.
        background.maskImage = Self.roundedMask(radius: 14)
        background.wantsLayer = true; background.layer?.cornerRadius = 14
        background.layer?.borderWidth = 0.5; background.layer?.borderColor = NSColor.separatorColor.cgColor
        panel.contentView = background

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([iconView.widthAnchor.constraint(equalToConstant: 26), iconView.heightAnchor.constraint(equalToConstant: 26)])

        metaLabel.font = .systemFont(ofSize: 11, weight: .medium); metaLabel.textColor = .secondaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingTail; metaLabel.maximumNumberOfLines = 1
        previewLabel.font = .systemFont(ofSize: 13); previewLabel.lineBreakMode = .byTruncatingTail; previewLabel.maximumNumberOfLines = 1
        [metaLabel, previewLabel].forEach { $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal); $0.cell?.truncatesLastVisibleLine = true }
        let texts = NSStackView(views: [metaLabel, previewLabel]); texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 2
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)

        saveButton.target = self; saveButton.action = #selector(save)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([saveButton.widthAnchor.constraint(equalToConstant: PillButton.size.width), saveButton.heightAnchor.constraint(equalToConstant: PillButton.size.height)])
        expandButton = iconButton("chevron.up", "展开全文", #selector(toggleExpand))
        moreButton = iconButton("ellipsis.circle", "更多", #selector(showMore(_:)))
        pinButton = iconButton("pin.fill", "取消置顶", #selector(togglePin))

        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Icon + text hug the left edge; the buttons sit in the trailing gravity area so they
        // stay pinned to the right edge whatever the preview length or bar width.
        let row = NSStackView(); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 10
        row.setViews([iconView, texts], in: .leading)
        row.setViews([saveButton, pinButton, expandButton, moreButton], in: .trailing)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 10)
        row.setCustomSpacing(4, after: saveButton); row.setCustomSpacing(2, after: pinButton); row.setCustomSpacing(2, after: expandButton)

        textView.isEditable = false; textView.isSelectable = true; textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8); textView.drawsBackground = false
        textView.isRichText = false; textView.autoresizingMask = [.width]; textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        detailScroll = NSScrollView(); detailScroll.documentView = textView; detailScroll.hasVerticalScroller = true
        detailScroll.drawsBackground = false; detailScroll.borderType = .noBorder; detailScroll.isHidden = true
        let divider = NSBox(); divider.boxType = .separator; divider.isHidden = true; divider.identifier = .init("divider")

        let root = NSStackView(views: [detailScroll, divider, row]); root.orientation = .vertical; root.spacing = 0
        root.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        background.addSubview(root); root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: background.leadingAnchor), root.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            root.topAnchor.constraint(equalTo: background.topAnchor), root.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: Self.barHeight), row.widthAnchor.constraint(equalTo: root.widthAnchor),
            detailScroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -16), divider.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24)
        ])
    }
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill(); return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
    /// Pinned: floats above every window and joins full-screen spaces. Unpinned: an ordinary
    /// window level, so other windows can cover it; click the bar to raise it again.
    func applyPinned() {
        panel.level = pinned ? .floating : .normal
        panel.isFloatingPanel = pinned
        panel.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.canJoinAllSpaces]
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        pinButton.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = pinned ? "已置顶 · 点击取消置顶" : "未置顶 · 点击置顶"
        panel.orderFrontRegardless()
    }
    @objc func togglePin() {
        pinned.toggle(); applyPinned()
        showMeta(pinned ? "已置顶：横条始终在最上层" : "已取消置顶：可被其他窗口遮挡，点横条可调回前面")
    }
    func iconButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
        b.isBordered = false; b.bezelStyle = .regularSquare; b.contentTintColor = .secondaryLabelColor; b.toolTip = tip
        b.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 26), b.heightAnchor.constraint(equalToConstant: 26)])
        return b
    }
    @objc func toggleExpand() {
        expanded.toggle()
        let divider = (panel.contentView?.subviews.first as? NSStackView)?.arrangedSubviews.first { $0.identifier?.rawValue == "divider" }
        detailScroll.isHidden = !expanded; divider?.isHidden = !expanded
        expandButton.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.up", accessibilityDescription: nil)
        expandButton.toolTip = expanded ? "收起" : "展开全文"
        let height = Self.barHeight + (expanded ? Self.detailHeight : 0)
        var frame = panel.frame
        // Grow upward when the bar sits in the lower half of the screen, downward otherwise.
        let growUp = frame.midY < (panel.screen ?? NSScreen.main!).visibleFrame.midY
        if growUp { frame.size.height = height } else { frame.origin.y += frame.height - height; frame.size.height = height }
        panel.minSize.height = height; panel.maxSize.height = height
        panel.setFrame(frame, display: true, animate: true)
        panel.invalidateShadow()
    }

    enum Tone { case normal, success, warning }
    /// Temporary status in the meta line; reverts to the preview's meta after a few seconds.
    func showMeta(_ text: String, tone: Tone = .normal, sticky: Bool = false) {
        metaResetWork?.cancel()
        metaLabel.stringValue = text
        metaLabel.textColor = tone == .warning ? .systemOrange : tone == .success ? .systemGreen : .secondaryLabelColor
        guard !sticky else { return }
        let work = DispatchWorkItem { [weak self] in self?.renderMeta() }
        metaResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }
    func renderMeta() {
        metaResetWork?.cancel(); metaLabel.textColor = .secondaryLabelColor
        if !AXIsProcessTrusted() { metaLabel.stringValue = "需要辅助功能权限 · 点右侧「授权」"; metaLabel.textColor = .systemOrange; return }
        if capture.clipboard.recovery != nil { metaLabel.stringValue = "原剪贴板备份待处理 · 点 ⋯ 处理"; metaLabel.textColor = .systemOrange; return }
        if let failure = saveFailureMessage { metaLabel.stringValue = failure; metaLabel.textColor = .systemOrange; return }
        if capture.paused { metaLabel.stringValue = "已暂停自动划词"; return }
        guard let clip = state.preview else { metaLabel.stringValue = "划词摘录 · 存入 \(inboxURL.lastPathComponent)"; return }
        let time = clip.capturedAt.formatted(date: .omitted, time: .shortened)
        metaLabel.stringValue = "\(clip.sourceApp) · \(time) · \(clip.text.count) 字"
    }
    func renderIdle() {
        iconView.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: nil); iconView.contentTintColor = .tertiaryLabelColor
        previewLabel.stringValue = "在任意应用中划选文字，这里会显示预览"; previewLabel.textColor = .tertiaryLabelColor
        previewLabel.toolTip = nil; textView.string = ""
        updateSaveButton(); renderMeta()
    }
    func renderPreview(_ clip: ClipRecord, method: String?) {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == clip.sourceBundleID }), let icon = app.icon { iconView.image = icon }
        else { iconView.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) }
        iconView.contentTintColor = nil
        let flat = clip.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "  ")
        previewLabel.stringValue = flat; previewLabel.textColor = .labelColor
        previewLabel.toolTip = clip.text.count > 1500 ? String(clip.text.prefix(1500)) + "…" : clip.text
        textView.string = clip.text
        updateSaveButton(); renderMeta()
        if let method, method != "AX" { showMeta("\(clip.sourceApp) · 通过\(method)读取", tone: .normal) }
    }
    func updateSaveButton() {
        if !AXIsProcessTrusted() {
            saveButton.label = "授权"; saveButton.symbol = "lock.open"; saveButton.fill = .systemOrange; saveButton.ink = .white
            saveButton.toolTip = "打开 系统设置 → 辅助功能"
            saveButton.action = #selector(requestPermission); saveButton.isEnabled = true; return
        }
        saveButton.action = #selector(save)
        if state.preview != nil && state.isSaved {
            // Stays "enabled" so it is drawn at full strength; save() ignores already-saved clips.
            saveButton.label = "已存"; saveButton.symbol = "checkmark"; saveButton.fill = .systemGreen.withAlphaComponent(0.2); saveButton.ink = .systemGreen
            saveButton.toolTip = "已追加到 \(inboxURL.lastPathComponent)"; saveButton.isEnabled = true
        } else {
            saveButton.label = "保存"; saveButton.symbol = "plus"; saveButton.fill = .controlAccentColor; saveButton.ink = .white
            saveButton.toolTip = "追加到 \(inboxURL.lastPathComponent)"
            saveButton.isEnabled = state.preview != nil && !(state.preview.map { saves.pending[$0.id] != nil } ?? false)
        }
    }

    // MARK: - Menus

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: "Mac Selection Clipper")
        let menu = NSMenu(); menu.delegate = self
        statusItem.menu = menu
    }
    /// Shared by the status-bar menu and the bar's ⋯ button; rebuilt on open so titles reflect state.
    func fillMenu(_ menu: NSMenu, includeQuit: Bool) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector?, symbol: String? = nil, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: ""); item.target = self
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(item)
        }
        add("打开摘录文件", #selector(openInbox), symbol: "book")
        add("复制当前全文", #selector(copyPreview), symbol: "doc.on.doc", enabled: state.preview != nil)
        add("从剪贴板手动粘贴", #selector(manualPaste), symbol: "doc.on.clipboard")
        add("清空预览", #selector(clear), symbol: "xmark.circle", enabled: state.preview != nil)
        menu.addItem(.separator())
        if !saves.failed.isEmpty { add("重试保存失败的 \(saves.failed.count) 条", #selector(retryFailedSaves), symbol: "arrow.clockwise") }
        if capture.clipboard.recovery != nil { add("处理原剪贴板备份…", #selector(handleClipboardRecovery), symbol: "exclamationmark.triangle") }
        add(capture.paused ? "恢复自动划词" : "暂停自动划词", #selector(togglePause), symbol: capture.paused ? "play.circle" : "pause.circle")
        add(pinned ? "取消置顶" : "置顶横条", #selector(togglePin), symbol: pinned ? "pin.slash" : "pin")
        add(panel.isVisible ? "隐藏横条" : "显示横条", #selector(togglePanel), symbol: "rectangle.bottomthird.inset.filled")
        add("测试读取当前选区", #selector(diagnoseSelection), symbol: "stethoscope")
        // add("查看历史", #selector(showHistory))  // 旧版一文件一条的历史；改为单文件 Inbox 后隐藏
        add("设置…", #selector(showSettings), symbol: "gearshape")
        if !AXIsProcessTrusted() { add("开启辅助功能权限…", #selector(requestPermission), symbol: "lock.open") }
        menu.addItem(.separator())
        let info = NSMenuItem(title: "\(capture.monitorStrategy) · 存入 \(inboxURL.lastPathComponent)", action: nil, keyEquivalent: ""); info.isEnabled = false
        menu.addItem(info)
        if includeQuit { add("退出 Selection Clipper", #selector(quit), symbol: "power") }
    }
    func menuNeedsUpdate(_ menu: NSMenu) { fillMenu(menu, includeQuit: true) }
    @objc func showMore(_ sender: NSButton) {
        let menu = NSMenu(); fillMenu(menu, includeQuit: true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    // MARK: - Capture results

    func refreshPermissions() {
        let trusted = AXIsProcessTrusted()
        // Taps installed before the grant never start delivering events: reinstall on grant.
        if trusted && !lastTrusted && !capture.paused { capture.stop(); capture.start(); showMeta("已获得辅助功能权限，可以开始划词", tone: .success) }
        lastTrusted = trusted
        if trusted != (saveButton.action == #selector(save)) { updateSaveButton(); renderMeta() }
    }
    @objc func requestPermission() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func receive(_ request: CaptureRequest, _ result: AXReadResult, _ ms: Double) {
        if let text = result.selectedText {
            let previousID = state.preview?.id
            let clip = ClipRecord(capturedAt: request.capturedAt, sourceApp: request.appName, sourceBundleID: request.bundleID, sourceTitle: request.sourceTitle, sourceURL: request.sourceURL, text: text)
            state.accept(clip, sequence: state.beginCapture())
            if state.preview?.id != previousID, let preview = state.preview { renderPreview(preview, method: result.method) }
        } else if request.trigger != "鼠标" {
            showMeta(result.label, tone: .warning) // explicit test: always explain
        } else {
            switch result {
            // Ordinary drags (windows, scrollbars, canvases) end here in every app: stay quiet.
            case .empty, .changedApp, .unsupported, .timeout: break
            case .terminalMouseReporting, .clipboardIssue, .denied, .tooLong, .complexSelection: showMeta(result.label, tone: .warning)
            case .secure: showMeta(result.label)
            default: break
            }
        }
        if UserDefaults.standard.bool(forKey: "diagnostics") {
            NSLog("capture bundle=%@ result=%@ latency_ms=%.1f", request.bundleID, result.label, ms)
        }
    }
    @objc func diagnoseSelection() { showMeta("正在读取前台应用的选区…"); capture.diagnoseCurrentSelection() }
    @objc func handleClipboardRecovery() {
        let alert = NSAlert(); alert.messageText = "如何处理原剪贴板备份？"
        alert.informativeText = "恢复会替换你当前的剪贴板内容；放弃备份会保留当前内容。备份只在内存中，退出后不保留。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "恢复原剪贴板"); alert.addButton(withTitle: "放弃备份")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertSecondButtonReturn: showMeta(capture.clipboard.restoreByUser() ? "原剪贴板已恢复" : "恢复失败，备份仍在内存中", tone: .warning)
        case .alertThirdButtonReturn: capture.clipboard.discardRecoveryByUser(); renderMeta()
        default: break
        }
    }

    // MARK: - Save

    @objc func save() {
        guard let clip = state.preview, !state.isSaved else { return }
        persist(clip)
    }
    @objc func retryFailedSaves() {
        for clip in Array(saves.failed.values) { persist(clip) }
    }
    func persist(_ clip: ClipRecord) {
        guard !terminating, saves.begin(clip) else { return }
        if state.preview?.id == clip.id { saveButton.isEnabled = false; showMeta("正在保存…", sticky: true) }
        let target = inbox
        disk.async { [weak self] in
            let result = Result { try target.append(clip) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success: self.saves.finish(clip.id, succeeded: true)
                case .failure: self.saves.finish(clip.id, succeeded: false)
                }
                if case .failure(let error) = result { self.saveFailureMessage = "\(self.saves.failed.count) 条保存失败（\(error.localizedDescription)）· 点 ⋯ 重试" }
                else if self.saves.failed.isEmpty { self.saveFailureMessage = nil }
                if self.state.preview?.id == clip.id, case .success = result { self.state.markSaved(clip.id) }
                self.updateSaveButton()
                if case .success = result { self.showMeta("✓ 已追加到 \(target.fileURL.lastPathComponent)", tone: .success) } else { self.renderMeta() }
            }
        }
    }

    // MARK: - Actions

    @objc func clear() { capture.invalidate(); state.clear(); renderIdle() }
    @objc func copyPreview() {
        guard let text = state.preview?.text else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        showMeta("已复制全文", tone: .success)
    }
    @objc func togglePause() {
        capture.paused.toggle(); state.setPaused(capture.paused)
        statusItem.button?.image = NSImage(systemSymbolName: capture.paused ? "pause.circle" : "text.badge.plus", accessibilityDescription: "Selection Clipper")
        panel.alphaValue = capture.paused ? 0.6 : 1
        renderMeta()
    }
    @objc func togglePanel() { if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
    @objc func manualPaste() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { showMeta("剪贴板没有纯文本", tone: .warning); return }
        guard text.count <= 100_000 else { showMeta("文本超过 100,000 字符，请分段粘贴", tone: .warning); return }
        capture.invalidate()
        let clip = ClipRecord(sourceApp: "手动粘贴", sourceBundleID: "manual", text: text)
        state.setManualPreview(clip); renderPreview(clip, method: nil)
    }
    @objc func openInbox() {
        let url = inboxURL
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                 try Data(InboxFileStore.header.utf8).write(to: url, options: .withoutOverwriting) }
            catch { showMeta("无法创建摘录文件：\(error.localizedDescription)", tone: .warning); return }
        }
        var components = URLComponents(); components.scheme = "obsidian"; components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: url.path)]
        if let obsidian = components.url, NSWorkspace.shared.urlForApplication(toOpen: obsidian) != nil, Self.isInsideObsidianVault(url) {
            NSWorkspace.shared.open(obsidian)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    /// True when some parent folder contains `.obsidian` (the vault marker).
    static func isInsideObsidianVault(_ file: URL) -> Bool {
        var dir = file.deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".obsidian").path) { return true }
            dir = dir.deletingLastPathComponent()
        }
        return false
    }
    @objc func showHistory() { if historyWindow == nil { historyWindow = HistoryWindowController(owner: self) }; historyWindow?.show() }
    @objc func showSettings() { if settingsWindow == nil { settingsWindow = SettingsWindowController(owner: self) }; settingsWindow?.show() }
    @objc func openFolder() { openInbox() }
    @objc func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        if capture.clipboard.isBusy { showMeta("正在完成剪贴板保护，请稍后退出。", tone: .warning); return .terminateCancel }
        if capture.clipboard.recovery != nil { handleClipboardRecovery(); if capture.clipboard.recovery != nil { return .terminateCancel } }
        if !saves.pending.isEmpty {
            terminating = true; pausedBeforeTermination = capture.paused; capture.paused = true
            showMeta("正在完成已确认的保存，再退出…", sticky: true)
            disk.async { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { sender.reply(toApplicationShouldTerminate: true); return }
                    let success = self.saves.failed.isEmpty
                    if !success {
                        self.terminating = false; self.capture.paused = self.pausedBeforeTermination
                        self.panel.orderFrontRegardless(); self.showMeta("保存失败，已取消退出；请重试或再次退出选择放弃。", tone: .warning, sticky: true)
                    }
                    sender.reply(toApplicationShouldTerminate: success)
                }
            }
            return .terminateLater
        }
        if !saves.failed.isEmpty {
            let alert = NSAlert(); alert.messageText = "仍有 \(saves.failed.count) 条保存失败的摘录"
            alert.informativeText = "失败摘录只保留在内存中。退出会丢弃它们；可取消后重试保存。"
            alert.addButton(withTitle: "取消并重试"); alert.addButton(withTitle: "放弃失败摘录并退出")
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
        }
        return .terminateNow
    }
}
