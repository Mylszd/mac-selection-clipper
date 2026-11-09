import AppKit
import ApplicationServices

/// Mouse-only passive tap. An NSEvent monitor is retained as a fallback when
/// macOS declines a session tap. Neither route reads keys or alters events.
final class SelectionEventMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var global: Any?
    private(set) var strategy = "未安装"
    var onMouse: ((NSEvent.EventType, CGPoint, Int, Bool) -> Void)?
    func start() {
        guard tap == nil, global == nil else { return }
        let mask: CGEventMask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged].reduce(0) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<SelectionEventMonitor>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let kind: NSEvent.EventType
            switch type { case .leftMouseDown: kind = .leftMouseDown; case .leftMouseUp: kind = .leftMouseUp; case .leftMouseDragged: kind = .leftMouseDragged; default: return Unmanaged.passUnretained(event) }
            let location = event.location, clicks = Int(event.getIntegerValueField(.mouseEventClickState)), shift = event.flags.contains(.maskShift)
            monitor.onMouse?(kind, location, clicks, shift)
            return Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap, let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
            source = runSource; CFRunLoopAddSource(CFRunLoopGetMain(), runSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true); strategy = "CGEvent 被动鼠标监听"
        } else {
            global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                let p = event.cgEvent?.location ?? CGPoint(x: NSEvent.mouseLocation.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - NSEvent.mouseLocation.y)
                self?.onMouse?(event.type, p, event.clickCount, event.modifierFlags.contains(.shift))
            }
            strategy = global == nil ? "监听安装失败" : "NSEvent 全局鼠标监听"
        }
    }
    func stop() {
        if let global { NSEvent.removeMonitor(global) }; global = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }; tap = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; source = nil
        strategy = "未安装"
    }
    deinit { stop() }
}
