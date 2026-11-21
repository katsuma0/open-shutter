import Foundation

/// How much the phone is moving right now, from 0 (still) to 1 (moving it around), for the line on the steady sign.
/// Kept apart from MotionState so its several updates a second redraw only that line: nothing else reads it, and a
/// phone at rest writes nothing.
@MainActor
@Observable
final class MotionPulse {
    private(set) var level: Double = 0

    /// Observation tells every reader of a write even when the value is the same.
    func set(_ value: Double) {
        guard level != value else { return }
        level = value
    }

    /// What a phone lying still reads, and under: level 0.
    nonisolated static let quietSpeed = 0.004
    /// Moving the phone on purpose, and over: level 1.
    nonisolated static let fullSpeed = 0.15
    /// The top of the green: a tripod with nobody touching it reads under this. The line lies flat up to here.
    nonisolated static let stillSpeed = 0.007
    /// The top of the green as a level, about 0.15. MotionMonitor sends every level up to it as 0.
    nonisolated static let stillLevel = level(forSpeed: stillSpeed)

    /// The turning speed the sensor reports, in radians a second, as a level. On a logarithmic scale, so a light touch
    /// on a tripod already shows and a steady hand's tremor (about 0.02 rad/s) reads about half way, while moving the
    /// phone on purpose (0.15 rad/s) reads 1. 0.004 rad/s and under read 0.
    nonisolated static func level(forSpeed speed: Double) -> Double {
        guard speed.isFinite, speed > 0 else { return 0 }
        let position = (log10(speed) - log10(quietSpeed)) / (log10(fullSpeed) - log10(quietSpeed))
        return min(max(position, 0), 1)
    }

    /// The line's colour for a level, from green through yellow and orange to red. Strict on purpose: a light touch on
    /// a tripod (about 0.0125 rad/s) is already yellow, a hand's tremor (0.032) orange, and moving the phone (0.1)
    /// red, since any of those blurs a long exposure. The stops are set as speeds, so each colour marks the same
    /// movement whatever the scale above.
    nonisolated static func color(for level: Double) -> (red: Double, green: Double, blue: Double) {
        let value = level.isFinite ? min(max(level, 0), 1) : 0
        guard let upper = colorStops.firstIndex(where: { $0.level >= value }), upper > 0 else {
            let edge = value <= 0 ? colorStops[0].rgb : colorStops[colorStops.count - 1].rgb
            return (edge.0, edge.1, edge.2)
        }
        let a = colorStops[upper - 1], b = colorStops[upper]
        let t = b.level > a.level ? (value - a.level) / (b.level - a.level) : 1
        return (a.rgb.0 + (b.rgb.0 - a.rgb.0) * t, a.rgb.1 + (b.rgb.1 - a.rgb.1) * t, a.rgb.2 + (b.rgb.2 - a.rgb.2) * t)
    }

    nonisolated private static let colorStops: [(level: Double, rgb: (Double, Double, Double))] = [
        (0, (0.20, 0.84, 0.29)),                            // green
        (stillLevel, (0.20, 0.84, 0.29)),                   // still green: a tripod nobody touches
        (level(forSpeed: 0.0125), (1.00, 0.84, 0.04)),      // yellow: a light touch
        (level(forSpeed: 0.032), (1.00, 0.58, 0.00)),       // orange: a hand's tremor
        (level(forSpeed: 0.1), (1.00, 0.23, 0.19)),         // red: the phone is being moved
    ]
}

/// The steady sign's line as a sound wave. It lies flat while the phone is still. Above the green it flows to the
/// right like a voice's waveform, taller and a little quicker the more the phone moves. The level it shows eases
/// toward the movement, quickly up and slowly down, like a sound meter: the wave grows and calms without a bounce,
/// and lies flat soon after the phone stops. Each step is exact for the time a frame covers, so the wave looks the
/// same at 60 and 120 frames a second.
struct MotionWave: Equatable, Sendable {
    /// Seconds for the shown level to go most of the way (63 percent) up to a larger movement.
    static let riseTime = 0.12
    /// The same down to a smaller one, so the wave calms more slowly than it grows.
    static let fallTime = 0.45
    /// The longest step taken at once, so a late frame can't throw the wave.
    static let longestStep = 0.1
    /// The flow's pace in cycles a second, at the first ripple and at the most movement.
    static let slowestFlow = 0.6
    static let fastestFlow = 1.5
    /// The flow repeats every 2 cycles: the main wave every 1, the second one every 2/3.
    static let flowPeriod = 2.0
    /// The largest height the two waves reach together under the window, over the whole line and every phase
    /// (1.2200 to four places), so a drawn wave never leaves its room.
    static let peak = 1.22

    /// The level the line shows now, 0 to 1. It follows MotionPulse.level.
    private(set) var level = 0.0
    /// How far the wave has flowed, in cycles, from 0 up to `flowPeriod`.
    private(set) var phase = 0.0

    /// How tall the wave is for a level, from 0 to 1 of its room: 0 up to the top of the green, then in proportion.
    static func amplitude(forLevel level: Double) -> Double {
        guard level.isFinite, level > MotionPulse.stillLevel else { return 0 }
        return min((level - MotionPulse.stillLevel) / (1 - MotionPulse.stillLevel), 1)
    }

    var amplitude: Double { Self.amplitude(forLevel: level) }

    /// A flat green line.
    var isFlat: Bool { amplitude == 0 }

    /// Seconds until the wave lies flat once the phone is still, as long as frames come in.
    var secondsToFlat: Double {
        guard level > MotionPulse.stillLevel else { return 0 }
        return Self.fallTime * log(level / MotionPulse.stillLevel)
    }

    /// Flat at once. The phase stays, so the next wave carries on from where this one was.
    mutating func settle() {
        level = 0
    }

    /// Moves the wave on by `seconds` with the phone moving at `target` (MotionPulse.level). With `flowing` false
    /// (Reduce Motion) the shape stays where it is and only its height follows the movement.
    mutating func advance(by seconds: Double, toward target: Double, flowing: Bool = true) {
        guard seconds.isFinite, seconds > 0 else { return }
        let dt = min(seconds, Self.longestStep)
        let goal = target.isFinite ? min(max(target, 0), 1) : 0
        let time = goal > level ? Self.riseTime : Self.fallTime
        level = goal + (level - goal) * exp(-dt / time)
        if flowing {
            let rate = Self.slowestFlow + (Self.fastestFlow - Self.slowestFlow) * amplitude
            phase = (phase + rate * dt).truncatingRemainder(dividingBy: Self.flowPeriod)
        }
        if !(level.isFinite && phase.isFinite) {
            level = 0
            phase = 0
        }
    }

    /// The wave's height at `position` along the line (0 at the left end, 1 at the right) at flow `phase`, from -1
    /// to 1 of its room: a main wave and a smaller, quicker one travelling right, under a window that is 0 at both
    /// ends, so the ends stay on the middle line.
    static func shape(at position: Double, phase: Double) -> Double {
        let u = position.isFinite ? min(max(position, 0), 1) : 0
        let window = sin(Double.pi * u) * sin(Double.pi * u)
        let main = sin(2 * Double.pi * (2.2 * u - phase))
        let second = 0.22 * sin(2 * Double.pi * (3.7 * u - 1.5 * phase) + 1.1)
        return window * (main + second) / peak
    }
}
