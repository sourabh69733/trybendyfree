import Foundation

/// Angle-to-effect lifecycle, independent of windows and hardware.
struct FoldSession {
    /// The effect begins below `startAngle` and reaches full strength at `endAngle`.
    /// macOS dims the display as the lid nears closed, so start early.
    static let startAngle = 110.0
    static let endAngle = 30.0
    static let watchdogTimeout: TimeInterval = 2

    private(set) var startedAt: TimeInterval?
    private var lastReadingAt: TimeInterval?
    private(set) var isSuppressed = false

    mutating func progress(angle: Double, now: TimeInterval) -> Double? {
        guard angle.isFinite, (0...180).contains(angle) else {
            dismiss()
            return nil
        }
        guard angle < Self.startAngle else {
            startedAt = nil
            lastReadingAt = nil
            isSuppressed = false
            return nil
        }
        guard !isSuppressed else { return nil }
        if startedAt == nil { startedAt = now }
        lastReadingAt = now
        let t = (Self.startAngle - max(Self.endAngle, angle)) / (Self.startAngle - Self.endAngle)
        return t * t * (3 - 2 * t)
    }

    mutating func dismiss() {
        startedAt = nil
        lastReadingAt = nil
        isSuppressed = true
    }

    func hasExpired(now: TimeInterval) -> Bool {
        guard let lastReadingAt else { return false }
        return now - lastReadingAt >= Self.watchdogTimeout
    }
}
