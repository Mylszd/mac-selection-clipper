import Foundation

/// Main-thread value state. A failed frozen snapshot remains retryable even
/// after the user has moved on to a different live selection.
public struct SaveLedger {
    public private(set) var pending = [UUID: ClipRecord]()
    public private(set) var failed = [UUID: ClipRecord]()
    public init() {}
    @discardableResult public mutating func begin(_ clip: ClipRecord) -> Bool {
        guard pending[clip.id] == nil else { return false }
        pending[clip.id] = clip; return true
    }
    public mutating func finish(_ id: UUID, succeeded: Bool) {
        guard let clip = pending.removeValue(forKey: id) else { return }
        if succeeded { failed.removeValue(forKey: id) } else { failed[id] = clip }
    }
}
