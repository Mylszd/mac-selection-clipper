import Foundation

public struct MouseSelectionGesture {
    private var start: (Double, Double)?
    private var dragged = false
    public init() {}
    public mutating func down(x: Double, y: Double) { start = (x, y); dragged = false }
    public mutating func move() { dragged = true }
    public mutating func clear() { start = nil; dragged = false }
    public mutating func finish(x: Double, y: Double, clicks: Int, shift: Bool) -> Bool {
        defer { clear() }
        guard let start else { return false }
        return (dragged && hypot(x - start.0, y - start.1) >= 3) || clicks >= 2 || shift
    }
}
