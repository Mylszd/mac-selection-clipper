import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipperCore
import ClipperClipboard

final class SelectionCaptureCoordinator {
    private let monitor = SelectionEventMonitor()
    var monitorStrategy: String { monitor.strategy }
    private var work: DispatchWorkItem?
    private var cancellation = CaptureCancellation()
    private let queue = DispatchQueue(label: "clipper.ax", qos: .userInitiated)
    private let reader = AXSelectionReader()
    let clipboard = ClipboardFallbackReader()
    var compatibilityEnabled = false
    var compatibilityApps = Set<String>()
    var compatibilityAllApps = true
    private var gesture = MouseSelectionGesture()
    var paused = false { didSet { invalidate(); if paused { stop() } else { start() } } }
    var generation: UInt64 = 0
    var ignored = Set<String>()
    var excludedPoint: ((NSPoint) -> Bool)?
    var onResult: ((CaptureRequest, AXReadResult, Double) -> Void)?
    var onActivity: (() -> Void)?
    var onDiagnostic: ((String) -> Void)?
    func invalidate() { generation &+= 1; work?.cancel(); cancellation.cancel(); cancellation = CaptureCancellation(); gesture.clear() }
    private var activationObserver: NSObjectProtocol?
    /// Warm up Electron accessibility trees when an app comes to the front, so the
    /// first selection in it is not lost while the tree is still being built.
    private func observeActivations() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, !self.paused,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier, !self.ignored.contains(app.bundleIdentifier ?? "") else { return }
            let pid = app.processIdentifier
            self.queue.async { [weak self] in self?.reader.prepare(pid: pid) }
        }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { queue.async { [weak self] in self?.reader.prepare(pid: pid) } }
    }
    func start() {
        guard !paused else { return }
        observeActivations()
        monitor.onMouse = { [weak self] type, point, clicks, shift in self?.handle(type, axPoint: point, clicks: clicks, shift: shift) }
        monitor.start()
    }
    func stop() { monitor.stop(); invalidate() }
    private func handle(_ type: NSEvent.EventType, axPoint: CGPoint, clicks: Int, shift: Bool) {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let point = NSPoint(x: axPoint.x, y: top - axPoint.y)
        onDiagnostic?("鼠标事件 \(type.rawValue) · \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown") · secure=\(IsSecureEventInputEnabled())")
        if excludedPoint?(point) == true { onDiagnostic?("已跳过浮窗内鼠标事件"); invalidate(); return }
        guard !paused else { invalidate(); return }
        switch type {
        case .leftMouseDown:
            invalidate(); gesture.down(x: point.x, y: point.y)
            onActivity?()
        case .leftMouseDragged: gesture.move()
        case .leftMouseUp:
            guard gesture.finish(x: point.x, y: point.y, clicks: clicks, shift: shift),
                  let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier,
                  CapturePolicy.allows(bundleID: bundle, ownBundleID: Bundle.main.bundleIdentifier ?? "io.github.mylszd.MacSelectionClipper", ignored: ignored, secure: IsSecureEventInputEnabled()) else { return }
            generation &+= 1
            let token = generation
            let request = CaptureRequest(pid: app.processIdentifier, bundleID: bundle, appName: app.localizedName ?? bundle, point: axPoint, capturedAt: Date(), sequence: token, startedAt: ProcessInfo.processInfo.systemUptime, trigger: "鼠标")
            let cancellation = self.cancellation
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // No AX calls on the main thread; source identity is frozen at mouse-up.
                var result = self.reader.read(request, cancellation: cancellation)
                var request = request
                if result.selectedText != nil || Self.fallbackEligible(result) {
                    (request.sourceTitle, request.sourceURL) = self.reader.sourceContext(pid: request.pid)
                }
                if request.bundleID == "com.apple.Terminal", Self.fallbackEligible(result), self.reader.terminalMouseReportingOn(pid: request.pid) {
                    result = .terminalMouseReporting
                }
                let ms = (ProcessInfo.processInfo.systemUptime - request.startedAt) * 1000
                // Look up the Copy menu item off the main thread, only when a fallback may run.
                let copyItem = Self.fallbackEligible(result) ? self.reader.enabledCopyMenuItem(pid: request.pid) : nil
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.paused, self.generation == token else { return }
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == request.pid else {
                        self.onResult?(request, .changedApp, ms); return
                    }
                    self.deliver(request, result: result, copyItem: copyItem, cancellation: cancellation, elapsed: ms)
                }
            }
            work = item
            queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: item)
        default: break
        }
    }
    static func fallbackEligible(_ result: AXReadResult) -> Bool {
        switch result { case .empty, .unsupported, .timeout: return true; default: return false }
    }
    private func deliver(_ request: CaptureRequest, result: AXReadResult, copyItem: AXUIElement?, cancellation: CaptureCancellation, elapsed: Double) {
        let mode = CopyFallbackPolicy.mode(enabled: compatibilityEnabled, allApps: compatibilityAllApps, bundleID: request.bundleID, allowedApps: compatibilityApps, secure: IsSecureEventInputEnabled())
        guard request.trigger == "鼠标", Self.fallbackEligible(result), mode != .none,
              mode == .menuOrKey || copyItem != nil else { onResult?(request, result, elapsed); return }
        clipboard.capture(request, copyItem: copyItem, allowKey: mode == .menuOrKey, cancellation: cancellation) { [weak self] result in
            guard let self, !self.paused, self.generation == request.sequence, !cancellation.isCancelled else { return }
            self.onResult?(request, result, (ProcessInfo.processInfo.systemUptime - request.startedAt) * 1000)
        }
    }
    func diagnoseCurrentSelection() {
        guard !paused, let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleIdentifier,
              CapturePolicy.allows(bundleID: bundle, ownBundleID: Bundle.main.bundleIdentifier ?? "io.github.mylszd.MacSelectionClipper", ignored: ignored, secure: IsSecureEventInputEnabled()) else { return }
        invalidate(); let token = generation, cancellation = self.cancellation
        let p = NSEvent.mouseLocation, top = NSScreen.screens.first?.frame.maxY ?? 0
        let request = CaptureRequest(pid: app.processIdentifier, bundleID: bundle, appName: app.localizedName ?? bundle, point: CGPoint(x: p.x, y: top - p.y), capturedAt: Date(), sequence: token, startedAt: ProcessInfo.processInfo.systemUptime, trigger: "诊断按钮")
        queue.async { [weak self] in
            guard let self else { return }; let result = self.reader.read(request, cancellation: cancellation)
            var request = request; (request.sourceTitle, request.sourceURL) = self.reader.sourceContext(pid: request.pid)
            let ms = (ProcessInfo.processInfo.systemUptime - request.startedAt) * 1000
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.paused, self.generation == token else { return }
                self.onResult?(request, result, ms)
            }
        }
    }
    deinit { monitor.stop(); work?.cancel(); if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) } }
}
