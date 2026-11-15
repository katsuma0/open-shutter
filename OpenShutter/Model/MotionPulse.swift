import Foundation

/// How much the phone is moving right now, from 0 (still) to 1 (swinging), for the small meter on the steady pill.
/// Kept apart from MotionState so its several updates a second redraw only that meter: nothing else reads it, and a
/// phone at rest writes nothing.
@MainActor
@Observable
final class MotionPulse {
    private(set) var level: Double = 0

    /// Observation tells every reader of a write even when the value is the same.
    func set(_ value: Double) {
        if level != value { level = value }
    }

    /// The turning speed the sensor reports, in radians a second, as a level. On a logarithmic scale, so the tremor
    /// of a steady hand (about 0.02 rad/s) already shows as a small pulse and a walk doesn't pin the meter: 0.004
    /// rad/s and under read 0, 0.4 and over read 1.
    nonisolated static func level(forSpeed speed: Double) -> Double {
        guard speed.isFinite, speed > 0 else { return 0 }
        let position = (log10(speed) - log10(0.004)) / 2
        return min(max(position, 0), 1)
    }
}
