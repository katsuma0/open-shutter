import SwiftUI

extension Theme {
    /// Corner radii shared by the sheets, cards and cells, so a card in the gallery and one in Settings round the
    /// same way and a new screen has no number to invent.
    enum Radius {
        /// Small wells and previews: the editor's thumbnails, a histogram well, a tag's backing.
        static let small: CGFloat = 8
        /// Cards that sit on a sheet: the info panel's wells, the share progress card, a banner.
        static let card: CGFloat = 14
        /// A sheet's own top corners and panels that float over a photo.
        static let sheet: CGFloat = 22
        /// A grid cell: just enough to soften the edge without eating the picture.
        static let cell: CGFloat = 3
    }
}

/// The small A beside a value the camera picks, drawn as the camera's chips draw it (AutoMarkGlyph in
/// ManualControlStrip). It lives here so screens outside the camera can share it; the camera's own copy can point
/// at this one later, and then there is a single A.
struct SmallAutoMark: View {
    /// The A's point size. Its top sits level with the top of digits about 12/7 its size.
    let size: CGFloat

    /// The gap the camera keeps between a value and its A.
    static func spacing(for size: CGFloat) -> CGFloat { size / 7 }

    var body: some View {
        Text("A")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Theme.secondaryText)
            .baselineOffset(size * 4 / 7)
            // Keeps its size while the value beside it shrinks to fit.
            .minimumScaleFactor(1)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

extension Theme {
    /// Motion for the screens around the camera: Settings, the gallery, the editor. Every curve here settles without
    /// overshoot, and each one is nil under Reduce Motion, in the app or in iOS, so a caller that hands it to
    /// withAnimation or Binding.animation gets an instant change with no branch of its own.
    @MainActor
    enum Motion {
        /// Rows that come and go under a switch or a menu, and sections that swap.
        static var rows: Animation? { still ? nil : .easeInOut(duration: 0.22) }
        /// A number or a symbol rolling to its next value.
        static var roll: Animation? { still ? nil : .snappy(duration: 0.24, extraBounce: 0) }
        /// The viewer's bars, a cell leaving the grid, a page fading in.
        static var fade: Animation? { still ? nil : .easeInOut(duration: 0.25) }
        /// The grid's first screen, a beat apart per row, so it settles in from the newest photo up.
        static func reveal(delay: Double) -> Animation? {
            still ? nil : .easeOut(duration: 0.28).delay(delay)
        }

        static var still: Bool { AppearanceStore.shared.reduceMotion }
    }
}

/// A row that leads somewhere or switches something in Settings: a thin symbol in the accent, the title, and the
/// current value trailing in gray, so every row of a menu reads the same way.
struct SettingsRowLabel: View {
    let title: String
    let symbol: String
    var value: String? = nil

    init(_ title: String, symbol: String, value: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.value = value
    }

    var body: some View {
        LabeledContent {
            if let value {
                Text(value)
                    .contentTransition(.numericText())
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .fontWeight(.light)
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}
