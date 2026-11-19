import Foundation

/// How much the phone is moving right now, from 0 (still) to 1 (swinging), for the small meter on the steady pill.
/// Kept apart from MotionState so its several updates a second redraw only that meter: nothing else reads it, and a
/// phone at rest writes nothing.
@MainActor
@Observable
final class MotionPulse {
    private(set) var level: Double = 0
    /// The last levels, oldest first, for the trace on the steady sign: about two seconds at the rate they arrive.
    private(set) var history: [Double] = Array(repeating: 0, count: MotionPulse.historyCount)
    static let historyCount = 40

    /// Observation tells every reader of a write even when the value is the same.
    func set(_ value: Double) {
        guard level != value else { return }
        level = value
        history.append(value)
        if history.count > Self.historyCount { history.removeFirst(history.count - Self.historyCount) }
    }

    /// The turning speed the sensor reports, in radians a second, as a level. On a logarithmic scale, so the tremor
    /// of a steady hand (about 0.02 rad/s) already shows as a small pulse and a walk doesn't pin the meter: 0.004
    /// rad/s and under read 0, 0.4 and over read 1.
    nonisolated static func level(forSpeed speed: Double) -> Double {
        guard speed.isFinite, speed > 0 else { return 0 }
        let position = (log10(speed) - log10(0.004)) / 2
        return min(max(position, 0), 1)
    }

    /// The meter's colour for a level, from green through yellow and orange to red. Strict on purpose: a light
    /// touch on a tripod (about 0.01 rad/s) is already yellow, a steady hand orange, and moving the phone red, since
    /// any of those blurs a long exposure.
    nonisolated static func color(for level: Double) -> (red: Double, green: Double, blue: Double) {
        let stops: [(at: Double, rgb: (Double, Double, Double))] = [
            (0, (0.20, 0.84, 0.29)),      // green
            (0.12, (0.20, 0.84, 0.29)),   // still green: what a tripod reads
            (0.25, (1.00, 0.84, 0.04)),   // yellow
            (0.45, (1.00, 0.58, 0.00)),   // orange
            (0.70, (1.00, 0.23, 0.19)),   // red
        ]
        let value = level.isFinite ? min(max(level, 0), 1) : 0
        guard let upper = stops.firstIndex(where: { $0.at >= value }), upper > 0 else {
            let edge = value <= 0 ? stops[0].rgb : stops[stops.count - 1].rgb
            return (edge.0, edge.1, edge.2)
        }
        let a = stops[upper - 1], b = stops[upper]
        let t = (value - a.at) / (b.at - a.at)
        return (a.rgb.0 + (b.rgb.0 - a.rgb.0) * t, a.rgb.1 + (b.rgb.1 - a.rgb.1) * t, a.rgb.2 + (b.rgb.2 - a.rgb.2) * t)
    }
}
