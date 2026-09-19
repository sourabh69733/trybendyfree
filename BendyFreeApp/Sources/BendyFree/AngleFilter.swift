import Foundation

/// Smooths raw hinge readings and picks how often to poll.
struct AngleFilter {
    /// Weight of the newest reading; lower is smoother but laggier.
    static let smoothing = 0.5
    /// Above this angle the effect is far away, so polling can be slow.
    static let idleAngle = FoldSession.startAngle + 20
    static let idleInterval: TimeInterval = 0.2

    private var value: Double?

    mutating func filter(_ raw: Double) -> Double {
        guard let previous = value else {
            value = raw
            return raw
        }
        let next = previous + (raw - previous) * Self.smoothing
        value = next
        return next
    }

    mutating func reset() { value = nil }

    /// Poll quickly near the fold range and slowly while the lid is comfortably open.
    static func pollInterval(for angle: Double, active: TimeInterval) -> TimeInterval {
        angle >= idleAngle ? max(active, idleInterval) : active
    }
}
