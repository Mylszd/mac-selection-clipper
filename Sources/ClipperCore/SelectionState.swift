import Foundation

public struct SelectionState {
    public private(set) var preview: ClipRecord?
    public private(set) var sequence: UInt64 = 0
    public private(set) var paused = false
    public private(set) var isSaved = false
    public init() {}
    @discardableResult public mutating func beginCapture() -> UInt64 { sequence &+= 1; return sequence }
    public mutating func invalidate() { sequence &+= 1 }
    public mutating func setPaused(_ value: Bool) { paused = value; invalidate() }
    public mutating func clear() { preview = nil; isSaved = false; invalidate() }
    public mutating func accept(_ clip: ClipRecord, sequence token: UInt64) {
        guard token == sequence, !paused, !clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if !isSaved, preview?.text == clip.text, preview?.sourceBundleID == clip.sourceBundleID { return }
        preview = clip; isSaved = false
    }
    public mutating func setManualPreview(_ clip: ClipRecord) {
        guard !clip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        invalidate(); preview = clip; isSaved = false
    }
    public mutating func markSaved(_ id: UUID) { if preview?.id == id { isSaved = true } }
}

public enum CapturePolicy {
    public static func allows(bundleID: String, ownBundleID: String, ignored: Set<String>, secure: Bool) -> Bool {
        !secure && !bundleID.isEmpty && bundleID != ownBundleID && !ignored.contains(bundleID)
    }
}
