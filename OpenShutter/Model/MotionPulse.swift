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

    /// The turning speed the sensor reports, in radians a second, as a level. On a logarithmic scale, so a light touch
    /// on a tripod already shows and a steady hand's tremor (about 0.02 rad/s) swings the line about half way, while
    /// moving the phone on purpose (0.15 rad/s) reads 1. 0.004 rad/s and under read 0.
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
        (level(forSpeed: stillSpeed), (0.20, 0.84, 0.29)),  // still green: a tripod nobody touches
        (level(forSpeed: 0.0125), (1.00, 0.84, 0.04)),      // yellow: a light touch
        (level(forSpeed: 0.032), (1.00, 0.58, 0.00)),       // orange: a hand's tremor
        (level(forSpeed: 0.1), (1.00, 0.23, 0.19)),         // red: the phone is being moved
    ]
}

/// The steady sign's line as a plucked string. It lies flat while the phone is still and swings while it moves; when
/// the phone stops it bounces back and forth, each swing smaller than the last, and lies flat again about a second
/// and a half later. The movement level sets how far it swings: a smaller swing grows to that where it is in its
/// swing, so the line never jumps, and a larger one rings down by itself, an exact damped oscillation. The reach and
/// the turn of the swing are stepped apart and each exactly for the time a frame covers, so the line swings at the
/// same pace and looks the same at 60 and 120 frames a second.
struct MotionBounce: Equatable, Sendable {
    /// Swings a second.
    static let frequency = 3.0
    /// Under 1, so the line overshoots and bounces before it settles: about four bounces that can be seen.
    static let damping = 0.16
    /// How fast a swing grows to what the movement asks for, per second: nine tenths of the way by the top of the
    /// first swing.
    static let attack = 30.0
    /// Levels up to the top of the green read as still, so a tripod's own sensor noise leaves the line flat.
    static let stillLevel = MotionPulse.level(forSpeed: MotionPulse.stillSpeed)
    /// Under 1, so a small movement swings a little more than in proportion.
    static let response = 0.75
    /// A swing this small reads as flat.
    static let restAmplitude = 0.01
    /// The longest step taken at once, so a late frame can't throw the line.
    static let longestStep = 1.0 / 20
    /// Reduce Motion's glide to the level, in cycles a second: there in about half a second, with no overshoot.
    static let glideFrequency = 1.5

    /// How far the swing reaches, from 0 to 1 of the room the line has.
    private var reach = 0.0
    /// Where the line is in its swing, in radians: 0 in the middle on its way up, a quarter turn at the top.
    private var phase = 0.0
    /// Reduce Motion's bow, which follows the movement without swinging, and its speed.
    private var bow = 0.0
    private var bowSpeed = 0.0
    /// Reduce Motion: the line bows with the movement and eases back, with no swing and no bounce. A change takes
    /// over from where the line is, so it doesn't jump.
    var isCalm: Bool {
        didSet {
            guard isCalm != oldValue else { return }
            if isCalm {
                bow = reach * sin(phase)
                bowSpeed = 0
                reach = 0
                phase = 0
            } else {
                reach = abs(bow)
                phase = bow < 0 ? 1.5 * Double.pi : 0.5 * Double.pi
                bow = 0
                bowSpeed = 0
            }
        }
    }

    init(isCalm: Bool = false) {
        self.isCalm = isCalm
    }

    /// How far the line swings for a movement level: 0 up to `stillLevel`, then rising to 1 at level 1.
    static func swing(forLevel level: Double) -> Double {
        guard level.isFinite, level > stillLevel else { return 0 }
        let share = min((level - stillLevel) / (1 - stillLevel), 1)
        return pow(share, response)
    }

    private static var angularFrequency: Double { 2 * Double.pi * frequency }

    /// The middle of the line, from -1 to 1 of the room it has. Positive is up.
    var displacement: Double {
        isCalm ? bow : reach * sin(phase)
    }

    /// How far it swings now.
    var amplitude: Double {
        guard isCalm else { return reach }
        let speed = bowSpeed / Self.angularFrequency
        return (bow * bow + speed * speed).squareRoot()
    }

    /// Nothing moves and nothing is asked of it: the view can stop drawing frames.
    func isAtRest(level: Double) -> Bool {
        Self.swing(forLevel: level) == 0 && amplitude < Self.restAmplitude
    }

    /// Flat and still, the next swing setting off upward from the middle.
    mutating func reset() {
        reach = 0
        phase = 0
        bow = 0
        bowSpeed = 0
    }

    /// Moves the line on by `seconds` with the phone moving at `level`.
    mutating func advance(by seconds: Double, level: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        let dt = min(seconds, Self.longestStep)
        let target = Self.swing(forLevel: level)
        if isCalm {
            glide(toward: target, dt: dt)
        } else {
            ring(toward: target, dt: dt)
        }
        if !(reach.isFinite && phase.isFinite && bow.isFinite && bowSpeed.isFinite) { reset() }
    }

    /// A swing smaller than the target grows toward it, a larger one rings down freely until it meets it. The swing
    /// turns at the damped oscillation's own pace either way, so growing never pulls it out of time.
    private mutating func ring(toward target: Double, dt: Double) {
        let omega = Self.angularFrequency
        let zeta = Self.damping
        if target > reach {
            reach = target + (reach - target) * exp(-Self.attack * dt)
        } else {
            reach = max(reach * exp(-zeta * omega * dt), target)
        }
        let damped = omega * (1 - zeta * zeta).squareRoot()
        phase = (phase + damped * dt).truncatingRemainder(dividingBy: 2 * Double.pi)
    }

    /// Reduce Motion: critically damped, so it eases to the target without overshooting.
    private mutating func glide(toward target: Double, dt: Double) {
        let omega = 2 * Double.pi * Self.glideFrequency
        let offset = bow - target
        let b = bowSpeed + omega * offset
        let decay = exp(-omega * dt)
        bow = target + (offset + b * dt) * decay
        bowSpeed = (bowSpeed - omega * b * dt) * decay
    }
}
