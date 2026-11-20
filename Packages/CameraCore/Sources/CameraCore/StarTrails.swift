import Foundation

/// How long stars stay points before the turning sky draws them into lines. Worked out on the 35 mm equivalent
/// focal length, the one AVFoundation gives: the stricter rules (NPF) need the real focal length and the pixel
/// pitch, which it doesn't. The limit holds for stars over the equator, the fastest; near the pole they move less.
public enum StarTrails {
    /// Seconds times millimetres of 35 mm equivalent focal length. The classic 500 rule, made stricter for a phone's
    /// fine pixels: 24 mm gives 16.7 s, about where stars start to streak on the main camera.
    public static let rule = 400.0

    /// A time this close over the limit still counts as inside it, the way the shutter dials take a hardware limit:
    /// 15 s against a limit of 14.8 is the same tick.
    static let slack = 0.02

    /// rule / focal length; nil for a focal length that isn't a positive number.
    public static func sharpSeconds(equivalentFocalLength: Double) -> Double? {
        guard equivalentFocalLength.isFinite, equivalentFocalLength > 0 else { return nil }
        return rule / equivalentFocalLength
    }

    /// The longest value of `scale` (ascending seconds) at or under `limit`, with 2% slack like the shutter dials;
    /// nil when even the first is longer, so every value is past the limit. A limit that isn't a number keeps
    /// nothing inside it either.
    public static func lastSharpIndex(in scale: [Double], limit: Double) -> Int? {
        scale.lastIndex { fits($0, limit) }
    }

    /// The time a scene starts at: its own when that is inside the limit, else the longest of its offered times
    /// that is, else the limit on third stops (ShutterSpeed.nominalThirdStops), never under `shortest`. The limit
    /// only ever shortens. A limit that isn't a positive number changes nothing.
    public static func startingSeconds(recipe: LongExposureRecipe, limit: Double?, shortest: Double) -> Double {
        let own = recipe.seconds
        guard let limit, limit.isFinite, limit > 0, !fits(own, limit) else { return own }
        let inside = recipe.durations.filter { fits($0, limit) }.max()
            ?? ShutterSpeed.nominalThirdStops.last { fits($0, limit) }
            ?? limit
        let floor = shortest.isFinite && shortest > 0 ? shortest : 0
        return Swift.max(inside, floor)
    }

    private static func fits(_ seconds: Double, _ limit: Double) -> Bool {
        seconds <= limit * (1 + slack)
    }
}

extension LongExposureScene {
    /// The scenes whose stars should stay points. Star trails wants the lines, and the rest have no stars to keep.
    public var limitsStarTrails: Bool { self == .stars || self == .northernLights }
}
