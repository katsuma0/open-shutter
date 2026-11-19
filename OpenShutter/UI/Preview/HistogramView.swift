import SwiftUI
import CameraCore

/// The live histogram, drawn straight on the picture with no panel: luma as a soft grey hill, RGB as three
/// translucent channels that add up to white where they overlap. Its bottom and both ends fade into the picture, so
/// it sits on the scene instead of covering a box of it.
struct HistogramView: View {
    static let size = CGSize(width: 190, height: 64)

    let histogram: Histogram
    let style: HistogramStyle

    var body: some View {
        if style != .off {
            Canvas { context, size in
                HistogramPlot(histogram: histogram, style: style).draw(in: &context, size: size)
            }
            .frame(width: Self.size.width, height: Self.size.height)
            // Ends and bottom fade out; the top keeps its full strength, where the peaks are read.
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                       .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .mask {
                        LinearGradient(colors: [.black, .black, .black.opacity(0.15)], startPoint: .top,
                                       endPoint: .bottom)
                    }
            }
            // A soft shade under the curves, so a white curve still reads over a white sky.
            .shadow(color: .black.opacity(0.35), radius: 3)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(style == .rgb ? "RGB histogram" : "Histogram")
            .accessibilityValue(HistogramPlot.summary(of: histogram))
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

private struct HistogramPlot {
    let histogram: Histogram
    let style: HistogramStyle

    /// 64 bars across about 106 points: fine enough to read, coarse enough that sampling noise doesn't fizz.
    private static let bucketCount = 64

    private static let channels: [(HistogramChannel, Color)] = [
        (.red, Color(red: 1, green: 0.23, blue: 0.2)),
        (.green, Color(red: 0.2, green: 0.95, blue: 0.32)),
        (.blue, Color(red: 0.26, green: 0.5, blue: 1)),
    ]

    func draw(in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        switch style {
        case .off:
            return
        case .luma:
            drawLuma(in: &context, size: size)
        case .rgb:
            let heights = Self.heights(Self.channels.map { histogram.bucketed($0.0, count: Self.bucketCount) })
            // A luma-only analysis (the simulated camera measures luma alone) leaves the colour bins empty.
            guard !heights.isEmpty else {
                drawLuma(in: &context, size: size)
                return
            }
            // Additive blending turns overlapping channels white, so a neutral scene reads as a white curve.
            context.blendMode = .plusLighter
            for (values, channel) in zip(heights, Self.channels) {
                let area = Self.area(values, size: size)
                context.fill(area, with: .color(channel.1.opacity(0.45)))
                context.stroke(Self.curve(values, size: size), with: .color(channel.1.opacity(0.9)), lineWidth: 1)
            }
        }
    }

    private func drawLuma(in context: inout GraphicsContext, size: CGSize) {
        let heights = Self.heights([histogram.bucketed(.luma, count: Self.bucketCount)])
        guard let luma = heights.first else { return }
        // Grey rather than white: a white hill was the brightest thing on a night scene.
        context.fill(Self.area(luma, size: size), with: .color(.white.opacity(0.32)))
        context.stroke(Self.curve(luma, size: size), with: .color(.white.opacity(0.7)), lineWidth: 1)
    }

    /// Square roots keep dark tails visible next to a tall peak. Scaling to the tallest inner bucket stops
    /// a pile of clipped whites or crushed blacks from flattening the rest; those end spikes simply hit the top.
    private static func heights(_ channels: [[UInt32]]) -> [[CGFloat]] {
        let compressed = channels.map { values in values.map { Double($0).squareRoot() } }
        var peak = 0.0
        for values in compressed where values.count > 2 {
            for value in values[1..<(values.count - 1)] where value > peak {
                peak = value
            }
        }
        if peak <= 0 {
            for values in compressed {
                for value in values where value > peak {
                    peak = value
                }
            }
        }
        guard peak > 0 else { return [] }
        return compressed.map { values in smoothed(values.map { CGFloat(min($0 / peak, 1)) }) }
    }

    /// A light blur across neighbouring buckets, so sampling noise reads as a curve rather than a comb.
    private static func smoothed(_ values: [CGFloat]) -> [CGFloat] {
        guard values.count > 2 else { return values }
        return values.indices.map { index in
            let left = values[max(index - 1, 0)]
            let right = values[min(index + 1, values.count - 1)]
            return (left + 2 * values[index] + right) / 4
        }
    }

    /// The top edge as a smooth curve: each bucket joined to the next through their midpoint.
    private static func curve(_ heights: [CGFloat], size: CGSize) -> Path {
        var path = Path()
        guard heights.count > 1 else { return path }
        let step = size.width / CGFloat(heights.count - 1)
        let points = heights.enumerated().map { CGPoint(x: CGFloat($0.offset) * step, y: size.height * (1 - $0.element)) }
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1]
            let mid = CGPoint(x: (previous.x + points[index].x) / 2, y: (previous.y + points[index].y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    private static func area(_ heights: [CGFloat], size: CGSize) -> Path {
        var path = curve(heights, size: size)
        guard !path.isEmpty else { return path }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }

    /// A spoken summary for VoiceOver: where most of the tones sit, and whether highlights clip.
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
