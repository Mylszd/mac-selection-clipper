import AppKit
import ClipperCore

final class HistoryWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    unowned let owner: AppDelegate
    let window: NSWindow
    let table = NSTableView()
    let search = NSSearchField()
    let body = NSTextView()
    let status = NSTextField(wrappingLabelWithString: "正在读取…")
    var records = [HistoryEntry]()
    var filtered = [HistoryEntry]()
    var generation = 0
    init(owner: AppDelegate) {
        self.owner = owner
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Selection Clipper 历史"; window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 620, height: 420); window.center()
        search.placeholderString = "搜索正文、来源应用"; search.delegate = self
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip")))
        table.tableColumns[0].title = "摘录 · 来源 · 时间"; table.tableColumns[0].width = 740
        table.delegate = self; table.dataSource = self; table.allowsMultipleSelection = true; table.rowHeight = 44
        table.setAccessibilityLabel("已保存摘录")
        let list = NSScrollView(); list.documentView = table; list.hasVerticalScroller = true; list.borderType = .bezelBorder
        body.isEditable = false; body.isSelectable = true; body.isRichText = false
        body.font = .systemFont(ofSize: 14); body.textContainerInset = NSSize(width: 10, height: 10)
        body.isVerticallyResizable = true; body.autoresizingMask = [.width]; body.textContainer?.widthTracksTextView = true
        let detail = NSScrollView(); detail.documentView = body; detail.hasVerticalScroller = true; detail.borderType = .bezelBorder
        let copy = NSButton(title: "复制所选为 Markdown", target: self, action: #selector(copySelected))
        let trash = NSButton(title: "移到废纸篓…", target: self, action: #selector(trashSelected))
        let refresh = NSButton(title: "刷新", target: self, action: #selector(reload))
        let folder = NSButton(title: "打开目录", target: owner, action: #selector(AppDelegate.openFolder))
        let actions = NSStackView(views: [copy, trash, refresh, folder])
        let root = NSStackView(views: [search, list, detail, actions, status]); root.orientation = .vertical; root.alignment = .leading; root.spacing = 10
        let content = window.contentView!; content.addSubview(root); root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), root.topAnchor.constraint(equalTo: content.topAnchor, constant: 16), root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16), search.widthAnchor.constraint(equalTo: root.widthAnchor), list.widthAnchor.constraint(equalTo: root.widthAnchor), detail.widthAnchor.constraint(equalTo: root.widthAnchor), list.heightAnchor.constraint(equalTo: detail.heightAnchor), list.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)])
    }
    func show() { reload(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    @objc func reload() {
        generation += 1; let token = generation, store = owner.store
        owner.disk.async { [weak self] in
            let result = Result { try store.load() }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                switch result {
                case .success(let load):
                    self.records = load.entries; self.applyFilter()
                    self.status.stringValue = "\(load.records.count) 条已保存摘录" + (load.unreadableFiles > 0 ? " · \(load.unreadableFiles) 个文件无法读取，原文件已保留" : "")
                case .failure(let error): self.status.stringValue = "读取失败：\(error.localizedDescription)"
                }
            }
        }
    }
    func controlTextDidChange(_ obj: Notification) { applyFilter() }
    func applyFilter() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = records.filter { query.isEmpty || $0.record.text.localizedCaseInsensitiveContains(query) || $0.record.sourceApp.localizedCaseInsensitiveContains(query) }
        table.deselectAll(nil); table.reloadData(); body.string = "选择一条摘录查看全文；可用 Command / Shift 多选后复制。"
    }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let clip = filtered[row].record
        let label = NSTextField(wrappingLabelWithString: String(clip.text.replacingOccurrences(of: "\n", with: " ").prefix(100)) + "\n" + clip.sourceApp + " · " + clip.createdAt.formatted(date: .abbreviated, time: .shortened))
        label.font = .systemFont(ofSize: 12); label.maximumNumberOfLines = 2
        return label
    }
    var selected: [HistoryEntry] { table.selectedRowIndexes.compactMap { filtered.indices.contains($0) ? filtered[$0] : nil } }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let clip = selected.first?.record else { return }
        body.string = "来源：\(clip.sourceApp)\n应用 ID：\(clip.sourceBundleID)\n时间：\(clip.createdAt.formatted())\nUUID：\(clip.id.uuidString.lowercased())\n\n\(clip.text)"
    }
    @objc private func copySelected() {
        let clips = selected; guard !clips.isEmpty else { status.stringValue = "请先选择摘录"; return }
        let text = MarkdownFileStore.export(clips.map(\.record))
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(text, forType: .string) { status.stringValue = "已复制 \(clips.count) 条摘录" }
        else { status.stringValue = "写入剪贴板失败，请重试" }
    }
    @objc private func trashSelected() {
        let clips = selected; guard !clips.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "将 \(clips.count) 条摘录移到废纸篓？"; alert.informativeText = "可在 Finder 废纸篓中放回。"; alert.addButton(withTitle: "移到废纸篓"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.owner.disk.async { [weak self] in
                var failure: Error?
                for clip in clips {
                    do { try FileManager.default.trashItem(at: clip.url, resultingItemURL: nil) }
                    catch { failure = error }
                }
                let message = failure.map { "部分操作失败：\($0.localizedDescription)" }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.reload()
                    if let message { self.status.stringValue = message }
                }
            }
        }
    }
}
