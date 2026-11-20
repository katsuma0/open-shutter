import SwiftUI

/// SF Symbols has no tripod, so one is drawn here: a camera head on three legs, in the foreground style. The steady
/// sign draws it solid. The top bar asks for a line width and gets it in thin strokes, to sit among the outline
/// symbols there.
struct TripodGlyph: View {
    /// Draws the head as an outline and the legs at this width. Nil draws the steady sign's tripod: a solid head on
    /// legs about an eighth of the glyph's width.
    var lineWidth: CGFloat? = nil

    var body: some View {
        Canvas { context, size in
            if let lineWidth, lineWidth > 0 {
                Self.drawOutline(in: &context, size: size, lineWidth: lineWidth)
            } else {
                Self.drawSolid(in: &context, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    private static func drawSolid(in context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        let height = size.height
        let head = CGRect(x: width * 0.2, y: 0, width: width * 0.6, height: height * 0.3)
        context.fill(Path(roundedRect: head, cornerRadius: height * 0.07), with: .foreground)
        let top = CGPoint(x: width * 0.5, y: height * 0.34)
        var legs = Path()
        for share: CGFloat in [0.1, 0.5, 0.9] {
            legs.move(to: top)
            legs.addLine(to: CGPoint(x: width * share, y: height))
        }
        context.stroke(legs, with: .foreground, style: StrokeStyle(lineWidth: max(1, width * 0.13), lineCap: .round))
    }

    /// The same tripod as thin lines. Everything sits half a line in from the frame, so no stroke is cut at its edge,
    /// and the legs hang from the head's lower edge, so the glyph reads as one piece.
    private static func drawOutline(in context: inout GraphicsContext, size: CGSize, lineWidth: CGFloat) {
        let box = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        guard box.width > 0, box.height > 0 else { return }
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let head = CGRect(x: box.minX + box.width * 0.2, y: box.minY, width: box.width * 0.6, height: box.height * 0.3)
        context.stroke(Path(roundedRect: head, cornerRadius: box.height * 0.07), with: .foreground, style: style)
        let top = CGPoint(x: box.midX, y: head.maxY)
        var legs = Path()
        for share: CGFloat in [0.1, 0.5, 0.9] {
            legs.move(to: top)
            legs.addLine(to: CGPoint(x: box.minX + box.width * share, y: box.maxY))
        }
        context.stroke(legs, with: .foreground, style: style)
    }
}
