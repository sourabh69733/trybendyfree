import Foundation

/// Angle-to-effect lifecycle, independent of windows and hardware.
struct FoldSession {
    private(set) var startedAt: TimeInterval?
    private var lastReadingAt: TimeInterval?
    private(set) var isSuppressed = false

    mutating func progress(angle: Double, now: TimeInterval) -> Double? {
        guard angle.isFinite, (0...180).contains(angle) else {
            dismiss()
            return nil
        }
        guard angle < 90 else {
            startedAt = nil
            lastReadingAt = nil
            isSuppressed = false
            return nil
        }
        guard !isSuppressed else { return nil }
        if startedAt == nil { startedAt = now }
        lastReadingAt = now
        let t = (90 - max(20, angle)) / 70
        return t * t * (3 - 2 * t)
    }

    mutating func dismiss() {
        startedAt = nil
        lastReadingAt = nil
        isSuppressed = true
    }

    func hasExpired(now: TimeInterval) -> Bool {
        guard let lastReadingAt else { return false }
        return now - lastReadingAt >= 1
    }
}
