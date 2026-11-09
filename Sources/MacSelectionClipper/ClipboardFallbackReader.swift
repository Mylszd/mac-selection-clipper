import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipperClipboard

/// Allowlisted Copy compatibility for apps whose selection AX cannot read. It never
/// changes focus, never runs for secure input, and polls only within one transaction.
final class ClipboardFallbackReader {
    private(set) var isBusy = false
    private(set) var recovery: PasteboardArchive?
    var onRecoveryChanged: ((Bool) -> Void)?
    private var lastCopyAt: TimeInterval = 0

    /// One copy transaction: back up clipboard -> press the target's Copy menu item
    /// (or post ⌘C) -> wait for a fresh, stable clipboard write -> read text -> restore.
    /// If the target never writes (nothing selected), the clipboard was untouched and
    /// nothing needs restoring.
    func capture(_ request: CaptureRequest, copyItem: AXUIElement?, allowKey: Bool, cancellation: CaptureCancellation, completion: @escaping (AXReadResult) -> Void) {
        precondition(Thread.isMainThread)
        guard !isBusy, recovery == nil else { completion(.clipboardIssue("剪贴板有待恢复备份，已跳过复制取词（点浮窗里的恢复按钮处理）。")); return }
        guard !cancellation.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == request.pid,
              AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { completion(.changedApp); return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCopyAt > 0.3 else { completion(.clipboardIssue("复制取词请求过密，已跳过。")); return }
        let pasteboard = NSPasteboard.general
        let archive: PasteboardArchive
        do { archive = try PasteboardArchive.capture(pasteboard) }
        catch { completion(.clipboardIssue(error.localizedDescription)); return }
        isBusy = true; lastCopyAt = now
        var pressed = false
        if let copyItem {
            AXUIElementSetMessagingTimeout(copyItem, 0.2)
            pressed = AXUIElementPerformAction(copyItem, kAXPressAction as CFString) == .success
        }
        if !pressed && !allowKey { isBusy = false; completion(.empty); return }
        if !pressed {
            let held = CGEventSource.flagsState(.combinedSessionState)
            guard held.intersection([.maskControl, .maskAlternate, .maskShift]).isEmpty else {
                isBusy = false; completion(.clipboardIssue("请松开修饰键后重新划选。")); return
            }
            let source = CGEventSource(stateID: .privateState)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
                isBusy = false; completion(.clipboardIssue("无法创建复制事件。")); return
            }
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.6
        var observed: Int?, changedAt: TimeInterval = 0
        func finish(_ result: AXReadResult) {
            // Restore only if nobody wrote after the copy we observed.
            if let observed, !archive.restore(pasteboard, expectedChangeCount: observed) {
                recovery = archive; onRecoveryChanged?(true)
                isBusy = false
                completion(.clipboardIssue("复制取词期间剪贴板被其他程序改写，未覆盖新内容；原剪贴板备份在内存中，可手动恢复。")); return
            }
            isBusy = false; completion(result)
        }
        func poll() {
            let current = pasteboard.changeCount, time = ProcessInfo.processInfo.systemUptime
            if current != archive.changeCount {
                if observed != current { observed = current; changedAt = time }
                if time - changedAt >= 0.05 || time >= deadline {
                    let text = pasteboard.string(forType: .string)
                    if cancellation.isCancelled || IsSecureEventInputEnabled() { finish(.changedApp) }
                    else if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { finish(text.count > 100_000 ? .tooLong : .copied(text)) }
                    else { finish(.empty) } // copied files/images/shapes, not text: restore quietly
                    return
                }
            } else if time >= deadline {
                isBusy = false; completion(.empty); return // target copied nothing: clipboard untouched
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(15), execute: poll)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(15), execute: poll)
    }
    func restoreByUser() -> Bool {
        guard let recovery, !isBusy else { return false }
        if recovery.restore(.general, expectedChangeCount: NSPasteboard.general.changeCount) {
            self.recovery = nil; onRecoveryChanged?(false); return true
        }
        return false
    }
    func discardRecoveryByUser() { recovery = nil; onRecoveryChanged?(false) }
}
