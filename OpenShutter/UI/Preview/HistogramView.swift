import SwiftUI
import CameraCore

/// The live histogram, drawn straight on the picture with no panel: luma as a soft grey hill, RGB as three
/// translucent channels that add up to white where they overlap. It fades out on every side, the bottom and both
/// ends all the way to clear, so it sits on the scene with no edge to see where it stops.
struct HistogramView: View {
    static let height: CGFloat = 64
    /// About 260 pt, less where the open part of the frame is narrower: 65:24 leaves 246 to 289 pt.
    static func width(openWidth: CGFloat) -> CGFloat { min(260, max(openWidth - 24, 0)) }

    let histogram: Histogram
    let style: HistogramStyle
    /// The heights on screen. Each frame's are eased in, so the hill settles instead of flickering at the 12 frames a
    /// second it arrives in.
    @State private var curves = HistogramCurves()

    var body: some View {
        if style != .off {
            HistogramPlot(curves: curves, style: style)
                .equatable()
                .mask { HistogramFade() }
                .onChange(of: HistogramFrame(histogram: histogram, style: style), initial: true) { _, frame in
                    curves = curves.blended(toward: HistogramCurves(frame.histogram, channels: frame.style.channels),
                                            weight: 0.5)
                }
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(style == .rgb ? "RGB histogram" : "Histogram")
                .accessibilityValue(HistogramSummary.summary(of: histogram))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// What a new curve is made from.
private struct HistogramFrame: Equatable {
    var histogram: Histogram
    var style: HistogramStyle
}

private extension HistogramStyle {
    var channels: [HistogramChannel] {
        switch self {
        case .off: return []
        case .luma: return [.luma]
        case .rgb: return [.red, .green, .blue]
        }
    }
}

/// The fade over every side: a short one at the top, where a clipped end reaches, long ones at both ends, and the
/// bottom half going all the way to clear. Each eases in and out, so neither end of a fade shows as a line.
private struct HistogramFade: View {
    private static let across = gradient(HistogramCurves.fade(from: 0, to: HistogramCurves.sideFade, rising: true)
                                         + HistogramCurves.fade(from: 1 - HistogramCurves.sideFade, to: 1, rising: false))
    private static let down = gradient(HistogramCurves.fade(from: 0, to: HistogramCurves.topFade, rising: true)
                                       + HistogramCurves.fade(from: HistogramCurves.bottomFadeStart, to: 1, rising: false))

    private static func gradient(_ stops: [(location: Double, opacity: Double)]) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: .black.opacity($0.opacity), location: $0.location) })
    }

    var body: some View {
        LinearGradient(gradient: Self.across, startPoint: .leading, endPoint: .trailing)
            .mask {
                LinearGradient(gradient: Self.down, startPoint: .top, endPoint: .bottom)
            }
    }
}

/// Draws the curves. Equatable, so a redraw of the view around it with the same curves draws nothing new.
private struct HistogramPlot: View, Equatable {
    let curves: HistogramCurves
    let style: HistogramStyle

    nonisolated static func == (lhs: HistogramPlot, rhs: HistogramPlot) -> Bool {
        lhs.curves == rhs.curves && lhs.style == rhs.style
    }

    private static let channelColors: [Color] = [
        Color(red: 1, green: 0.23, blue: 0.2),
        Color(red: 0.2, green: 0.95, blue: 0.32),
        Color(red: 0.26, green: 0.5, blue: 1),
    ]

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 1, size.height > 1, !curves.channels.isEmpty else { return }
        let paths = curves.channels.map { Self.paths($0, size: size) }
        // A dark line under each curve keeps a white curve readable over a white sky. It is drawn inside, so it
        // fades with the rest, where a shadow around the view would outline it.
        for path in paths {
            context.stroke(path.curve, with: .color(.black.opacity(0.22)), lineWidth: 3)
        }
        if paths.count == 1 {
            // Grey rather than white: a white hill was the brightest thing on a night scene.
            context.fill(paths[0].area, with: .color(.white.opacity(0.32)))
            context.stroke(paths[0].curve, with: .color(.white.opacity(0.7)), lineWidth: 1)
            return
        }
        // Additive blending turns overlapping channels white, so a neutral scene reads as a white curve.
        context.blendMode = .plusLighter
        for (path, color) in zip(paths, Self.channelColors) {
            context.fill(path.area, with: .color(color.opacity(0.45)))
            context.stroke(path.curve, with: .color(color.opacity(0.9)), lineWidth: 1)
        }
    }

    /// The top edge, flat from each end of the view to the end bucket, and the area under it.
    private static func paths(_ heights: [Double], size: CGSize) -> (curve: Path, area: Path) {
        var curve = Path()
        let segments = HistogramCurves.segments(heights)
        guard let first = segments.first, let last = segments.last else { return (curve, curve) }
        func point(_ p: PlotPoint) -> CGPoint {
            CGPoint(x: CGFloat(p.x) * size.width, y: (1 - CGFloat(p.y)) * size.height)
        }
        curve.move(to: CGPoint(x: 0, y: point(first.start).y))
        curve.addLine(to: point(first.start))
        for segment in segments {
            curve.addCurve(to: point(segment.end), control1: point(segment.control1), control2: point(segment.control2))
        }
        curve.addLine(to: CGPoint(x: size.width, y: point(last.end).y))
        var area = curve
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()
        return (curve, area)
    }
}

/// A point in the histogram's unit square: x from 0 (left) to 1 (right), y from 0 (bottom) to 1 (top).
struct PlotPoint: Hashable, Sendable {
    var x: Double
    var y: Double
}

/// One cubic Bézier piece of a curve.
struct CurveSegment: Hashable, Sendable {
    var start: PlotPoint
    var control1: PlotPoint
    var control2: PlotPoint
    var end: PlotPoint
}

/// The histogram as the viewfinder draws it: for each channel, bucket heights from 0 to 1, smoothed across the
/// buckets and eased from frame to frame, and the smooth curve over them.
struct HistogramCurves: Equatable, Sendable {
    static let bucketCount = 64
    /// The tallest inner bucket reaches this height, so no peak sits flat against the top.
    static let headroom = 0.88
    /// The first and last buckets sit this far in from each end, where the side fades are half way, so a clipped end
    /// still shows. The curve runs on flat to the ends from there and fades out.
    static let inset = 0.09

    /// One list of `bucketCount` heights per channel, in the order asked for. Empty when the frame had no signal.
    var channels: [[Double]]

    init(channels: [[Double]] = []) {
        self.channels = channels
    }

    /// From a frame's bins. Square roots keep dark tails visible beside a tall peak. The inner buckets set the scale,
    /// so a pile of clipped whites or crushed blacks can't flatten the rest; those end buckets stay as they are, and
    /// reach the top. One scale for all the channels asked for, so their heights compare.
    init(_ histogram: Histogram, channels wanted: [HistogramChannel]) {
        func compressed(_ channels: [HistogramChannel]) -> [[Double]] {
            channels.map { channel in
                histogram.bucketed(channel, count: Self.bucketCount).map { Double($0).squareRoot() }
            }
        }
        var heights = compressed(wanted)
        // A luma-only analysis (the simulated camera measures luma alone) leaves the colour bins empty: the luma
        // hill stands in.
        if wanted.count > 1, heights.allSatisfy({ $0.allSatisfy { $0 == 0 } }) {
            heights = compressed([.luma])
        }
        let smoothed = heights.map(Self.smoothed)
        var peak = 0.0
        for values in smoothed {
            for value in values.dropFirst().dropLast() where value > peak { peak = value }
        }
        if peak <= 0 {
            for values in smoothed {
                for value in values where value > peak { peak = value }
            }
        }
        guard peak > 0 else {
            self.channels = []
            return
        }
        let scale = Self.headroom / peak
        self.channels = smoothed.map { values in values.map { min($0 * scale, 1) } }
    }

    /// `weight` of the way from these heights to `next`, so the curve settles instead of flickering. A change of
    /// channels, or no curve yet, starts over at `next`.
    func blended(toward next: HistogramCurves, weight: Double) -> HistogramCurves {
        guard !channels.isEmpty, channels.count == next.channels.count,
              zip(channels, next.channels).allSatisfy({ $0.count == $1.count }) else { return next }
        let w = weight.isFinite ? min(max(weight, 0), 1) : 1
        return HistogramCurves(channels: zip(channels, next.channels).map { old, new in
            zip(old, new).map { $0 + ($1 - $0) * w }
        })
    }

    /// A 1-4-6-4-1 blur over the inner buckets, which reach only each other: the end buckets stay as measured, and
    /// a spike in one doesn't spread inward.
    static func smoothed(_ values: [Double]) -> [Double] {
        guard values.count > 4 else { return values }
        let first = 1
        let last = values.count - 2
        var result = values
        for index in first...last {
            func at(_ offset: Int) -> Double { values[min(max(index + offset, first), last)] }
            result[index] = (at(-2) + 4 * at(-1) + 6 * at(0) + 4 * at(1) + at(2)) / 16
        }
        return result
    }

    /// The curve over `heights` as cubic Bézier pieces: a uniform cubic B-spline, which is smooth through its second
    /// derivative and stays inside the heights it is drawn from, so it never dips under the floor or rises over a
    /// peak. The ends are tripled so the curve starts and ends on the first and last bucket. x runs from `inset` to
    /// 1 - `inset`.
    static func segments(_ heights: [Double], inset: Double = inset) -> [CurveSegment] {
        guard heights.count > 1 else { return [] }
        let span = 1 - 2 * inset
        let step = span / Double(heights.count - 1)
        let points = heights.enumerated().map { PlotPoint(x: inset + Double($0.offset) * step, y: $0.element) }
        let padded = [points[0], points[0]] + points + [points[points.count - 1], points[points.count - 1]]
        func mix(_ a: PlotPoint, _ wa: Double, _ b: PlotPoint, _ wb: Double, _ c: PlotPoint, _ wc: Double) -> PlotPoint {
            PlotPoint(x: a.x * wa + b.x * wb + c.x * wc, y: a.y * wa + b.y * wb + c.y * wc)
        }
        var segments: [CurveSegment] = []
        segments.reserveCapacity(padded.count - 3)
        for index in 0..<(padded.count - 3) {
            let p0 = padded[index], p1 = padded[index + 1], p2 = padded[index + 2], p3 = padded[index + 3]
            let start = mix(p0, 1.0 / 6, p1, 4.0 / 6, p2, 1.0 / 6)
            let control1 = mix(p1, 2.0 / 3, p2, 1.0 / 3, p2, 0)
            let control2 = mix(p1, 1.0 / 3, p2, 2.0 / 3, p2, 0)
            let end = mix(p1, 1.0 / 6, p2, 4.0 / 6, p3, 1.0 / 6)
            segments.append(CurveSegment(start: start, control1: control1, control2: control2, end: end))
        }
        return segments
    }

    /// The fades, as fractions of the width and the height: both ends over 18 percent, so the end buckets sit half
    /// way into them; the top over 8 percent, where only a clipped end reaches; the bottom from 55 percent down.
    static let sideFade = 0.18
    static let topFade = 0.08
    static let bottomFadeStart = 0.55

    /// Stops for a fade across `start...end` of a gradient, from clear to full when `rising`, eased at both ends
    /// (smoothstep), so neither the start nor the end of the fade shows as a line the way a straight ramp's do.
    static func fade(from start: Double, to end: Double, rising: Bool,
                     count: Int = 7) -> [(location: Double, opacity: Double)] {
        let steps = max(count, 2)
        return (0..<steps).map { index in
            let t = Double(index) / Double(steps - 1)
            let eased = t * t * (3 - 2 * t)
            return (start + (end - start) * t, rising ? eased : 1 - eased)
        }
    }
}

/// A spoken summary for VoiceOver: where most of the tones sit, and whether highlights clip.
private enum HistogramSummary {
    static func summary(of histogram: Histogram) -> String {
        var total = 0.0
        var weighted = 0.0
        var clipped = 0.0
        for (bin, count) in histogram.luma.enumerated() {
            let samples = Double(count)
            total += samples
            weighted += samples * Double(bin)
            if bin >= 250 {
                clipped += samples
            }
        }
        guard total > 0 else { return "No signal" }
        let mean = weighted / total / 255
        let tones: String
        if mean < 0.3 {
            tones = "Mostly shadows"
        } else if mean > 0.7 {
            tones = "Mostly highlights"
        } else {
            tones = "Mostly midtones"
        }
        return clipped / total > 0.02 ? tones + ", highlights clipping" : tones
    }
}
