import Foundation

/// How far the focus magnifier enlarges the middle of the frame while focus is set by hand. It enlarges with the
/// lens's own zoom, a crop of the sensor, so stars show as real pixels and peaking is worked out on the enlarged
/// frames. Off leaves the focus dial without it.
public enum FocusMagnifier: String, Codable, Sendable, CaseIterable, Identifiable {
    case off, x5, x10

    public var id: String { rawValue }

    /// Times the frame is enlarged; 1 for Off.
    public var power: Double {
        switch self {
        case .off: return 1
        case .x5: return 5
        case .x10: return 10
        }
    }

    public var title: String {
        switch self {
        case .off: return "Off"
        case .x5: return "5\u{00D7}"
        case .x10: return "10\u{00D7}"
        }
    }
}

/// The zoom behind the focus magnifier. The photo's own zoom is left alone: the magnifier lives on the device's
/// zoom only, and every shot starts after it has let go.
public enum MagnifierMath {
    /// The device zoom that enlarges the frame at `base` by `power`, inside `range`. A power under 1, or one that
    /// isn't a finite number, counts as 1, so the frame is never made smaller or sent to the end of the range. A
    /// base outside the range is clamped first, and one that isn't a number is the range's start.
    public static func deviceZoom(base: Double, power: Double, range: ClosedRange<Double>) -> Double {
        let start = ExposureMath.clamp(base, to: range)
        let times = power.isFinite && power >= 1 ? power : 1
        return ExposureMath.clamp(start * times, to: range)
    }

    /// How many times the frame shows enlarged, for the badge: `deviceZoom / base`, rounded to a tenth. A range that
    /// ran out shows here, 7.5 for a 5× asked of a 2× lens that stops at 15. 1 where either zoom isn't a positive
    /// number, or the device hasn't zoomed in past the base yet: a magnifier never shows the frame smaller.
    public static func shownPower(base: Double, deviceZoom: Double) -> Double {
        guard base.isFinite, base > 0, deviceZoom.isFinite, deviceZoom > 0 else { return 1 }
        let ratio = (deviceZoom / base * 10).rounded() / 10
        return ratio.isFinite ? Swift.max(ratio, 1) : 1
    }
}
