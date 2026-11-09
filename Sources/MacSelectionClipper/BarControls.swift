import AppKit

/// The bar's primary action ("保存" / "已存" / "授权"), drawn by hand.
/// A stock bezel button with `bezelColor` renders gray whenever its window is not key, and
/// the bar panel never becomes key, so the accent colour would never show. Fixed width so the
/// buttons to its right never shift when the label changes.
final class PillButton: NSView {
    weak var target: AnyObject?
    var action: Selector?
    var label = "" { didSet { needsDisplay = true } }
    var symbol = "plus" { didSet { needsDisplay = true } }
    var fill: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    var ink: NSColor = .white { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }

    static let size = NSSize(width: 70, height: 28)
    override var intrinsicContentSize: NSSize { Self.size }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { if isEnabled { pressed = true } }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) {
        defer { pressed = false }
        guard isEnabled, pressed, let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = isEnabled ? 1 : 0.4
        var bg = fill
        if pressed { bg = bg.blended(withFraction: 0.18, of: .black) ?? bg }
        else if hovering && isEnabled { bg = bg.blended(withFraction: 0.12, of: .white) ?? bg }
        bg.withAlphaComponent(bg.alphaComponent * alpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        let color = ink.withAlphaComponent(ink.alphaComponent * alpha)
        let text = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .semibold), .foregroundColor: color])
        let config = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .bold).applying(.init(paletteColors: [color]))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        let textSize = text.size(), imageSize = image?.size ?? .zero, gap: CGFloat = image == nil ? 0 : 4
        var x = (bounds.width - imageSize.width - gap - textSize.width) / 2
        if let image {
            image.draw(in: NSRect(x: x, y: (bounds.height - imageSize.height) / 2, width: imageSize.width, height: imageSize.height))
            x += imageSize.width + gap
        }
        text.draw(at: NSPoint(x: x, y: (bounds.height - textSize.height) / 2))
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { label }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, let action else { return false }
        return NSApp.sendAction(action, to: target, from: self)
    }
}

/// Bar background: re-resolves the hairline border colour when light/dark mode changes
/// (a layer's CGColor does not follow the appearance on its own).
final class BarBackground: NSVisualEffectView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { self.layer?.borderColor = NSColor.separatorColor.cgColor }
    }
}
