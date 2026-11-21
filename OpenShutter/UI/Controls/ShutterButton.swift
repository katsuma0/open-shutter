import SwiftUI

/// The shutter, drawn like the Camera app's: a white ring around a disc that morphs into the record and stop shapes.
/// A tap fires `action`. With `onHoldBegan` set, touching and holding opens the shutter until the finger lifts (bulb).
struct ShutterButton: View {
    enum Style: Equatable {
        case photo
        case video
        case recording
        case stacking(progress: Double)
        case night
        case long
        case countdown
        /// An intervalometer between shots, or a focus or white balance bracket: drawn like the countdown, and a
        /// press stops it.
        case sequence
    }

    var style: Style
    var isEnabled: Bool = true
    /// False while the camera would ignore a press, such as during a photo's exposure. A press then gets no scale,
    /// haptic or action, so the shutter is never felt to fire without firing. The look stays: that state is brief.
    var acceptsPress: Bool = true
    /// False while a press only brings the whole frame back from the focus magnifier. The model plays its own lighter
    /// tap for that, and a shutter click would be felt to fire without firing.
    var clicksOnPress: Bool = true
    /// The battery saver has the screen dark over the button. The bulb arc holds still and the progress ring steps
    /// without animating, so nothing keeps drawing under the black. The button stays in place: removing it would end
    /// a bulb hold.
    var isDimmed: Bool = false
    var action: () -> Void
    var onHoldBegan: (() -> Void)? = nil
    var onHoldEnded: (() -> Void)? = nil

    @GestureState private var isTouching = false
    /// The finger on the button, from touch down to lift.
    @State private var press: Press?

    private static let ringWidth: CGFloat = 4
    private static let ringGap: CGFloat = 3
    private static let discDiameter: CGFloat = Theme.shutterSize - 2 * (ringWidth + ringGap)
    /// Long enough that an ordinary tap never turns into a bulb exposure.
    private static let holdDelay: UInt64 = 350_000_000
    /// Sliding this far off the button cancels the tap, like UIButton.
    private static let touchSlop: CGFloat = 28

    private enum Kind: Equatable {
        case photo, video, recording, stacking, night, long, countdown
    }

    private struct Press {
        var isInside = true
        var holdActive = false
        var holdTask: Task<Void, Never>?
        /// The hold-end handler from when the hold began, in case the parent drops it while the exposure runs.
        var holdEnded: (() -> Void)?
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(showsStopBackdrop ? 0.14 : 0))
                .frame(width: Self.discDiameter, height: Self.discDiameter)
            ZStack {
                centerShape
                glyph
            }
            .scaleEffect(isPressed ? 0.9 : 1)
            .animation(Theme.snappy, value: isPressed)
            ring
        }
        .frame(width: Theme.shutterSize, height: Theme.shutterSize)
        .animation(Theme.spring, value: kind)
        .animation(Theme.spring, value: showsBulbGlyph)
        .opacity(isEnabled || press != nil ? 1 : Theme.Dim.off)
        .animation(Theme.snappy, value: isEnabled)
        .contentShape(Circle())
        .gesture(pressGesture)
        // A press already under way keeps going, so a bulb exposure can always be released.
        .disabled(!isEnabled && press == nil)
        .onChange(of: isTouching) { _, touching in
            guard !touching else { return }
            // A press the system cancels never reaches onEnded; look again once this gesture update is over.
            Task { @MainActor in releaseCancelledPress() }
        }
        .onDisappear { releaseCancelledPress(force: true) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityValue(Text(accessibilityProgress))
        .accessibilityHint(Text(showsBulbGlyph ? "Touch and hold to keep the shutter open until you let go." : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activateFromAccessibility() }
    }

    // MARK: - Appearance

    private var kind: Kind {
        switch style {
        case .photo: return .photo
        case .video: return .video
        case .recording: return .recording
        case .stacking: return .stacking
        case .night: return .night
        case .long: return .long
        case .countdown, .sequence: return .countdown
        }
    }

    private var progress: Double {
        guard case .stacking(let value) = style, value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// While recording, stacking or counting down the button stops what is running instead of starting a shot.
    private var isStopStyle: Bool {
        kind == .recording || kind == .stacking || kind == .countdown
    }

    private var showsStopBackdrop: Bool {
        kind == .stacking || kind == .countdown
    }

    private var showsBulbGlyph: Bool {
        kind == .long && onHoldBegan != nil
    }

    private var isPressed: Bool {
        guard let press else { return false }
        return press.isInside || press.holdActive
    }

    /// One shape morphs between disc, record square and stop square, the way the Camera app's shutter does.
    private var centerShape: some View {
        let disc = Self.discDiameter
        let size: CGFloat
        let corner: CGFloat
        let color: Color
        switch kind {
        case .photo, .night, .long:
            (size, corner, color) = (disc, disc / 2, .white)
        case .video:
            (size, corner, color) = (disc - 4, (disc - 4) / 2, Theme.recording)
        case .recording:
            (size, corner, color) = (28, 7, Theme.recording)
        case .stacking, .countdown:
            (size, corner, color) = (26, 6, .white)
        }
        return RoundedRectangle(cornerRadius: corner, style: .circular)
            .fill(color)
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var glyph: some View {
        // NIGHT's shutter is the plain white disc: the mode is already named in the carousel and on the scene button.
        if showsBulbGlyph {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.55))
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
        }
    }

    /// A hairline rim carrying fine ticks, like a lens barrel's, in the band the solid ring used to fill, so the disc
    /// and the hit area keep their size. While a stack runs the ticks dim and the accent sweeps along them.
    private var ring: some View {
        ZStack {
            ShutterDial(color: .white)
                .opacity(kind == .stacking ? 0.28 : 1)
            if kind == .stacking {
                if progress > 0 {
                    ShutterDial(color: Theme.accent)
                        .mask {
                            Circle()
                                .inset(by: Self.ringWidth / 2)
                                .trim(from: 0, to: progress)
                                .stroke(style: StrokeStyle(lineWidth: Self.ringWidth + 2))
                                .rotationEffect(.degrees(-90))
                                .animation(isDimmed ? nil : .linear(duration: 0.3), value: progress)
                        }
                } else {
                    ShutterDial(color: Theme.accent)
                        .mask { PendingArc(lineWidth: Self.ringWidth + 2, isPaused: isDimmed) }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Touch handling

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, touching, _ in
                touching = true
            }
            .onChanged { value in
                pressChanged(value)
            }
            .onEnded { value in
                pressEnded(value)
            }
    }

    private static func isInside(_ location: CGPoint) -> Bool {
        CGRect(x: 0, y: 0, width: Theme.shutterSize, height: Theme.shutterSize)
            .insetBy(dx: -touchSlop, dy: -touchSlop)
            .contains(location)
    }

    private func pressChanged(_ value: DragGesture.Value) {
        guard var current = press else {
            guard isEnabled, acceptsPress else { return }
            var next = Press()
            if onHoldBegan != nil, !isStopStyle {
                next.holdTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Self.holdDelay)
                    guard !Task.isCancelled else { return }
                    holdTimerFired()
                }
            }
            press = next
            return
        }
        // Once the shutter is held open it stays open until the finger lifts, wherever it slides.
        guard !current.holdActive else { return }
        let inside = Self.isInside(value.location)
        guard inside != current.isInside else { return }
        current.isInside = inside
        if !inside {
            current.holdTask?.cancel()
            current.holdTask = nil
        }
        press = current
    }

    private func holdTimerFired() {
        guard var current = press, current.isInside, !current.holdActive, !isStopStyle, acceptsPress,
              let began = onHoldBegan else { return }
        current.holdActive = true
        current.holdTask = nil
        current.holdEnded = onHoldEnded
        press = current
        if clicksOnPress { Haptics.shutter() }
        began()
    }

    private func pressEnded(_ value: DragGesture.Value) {
        guard let current = press else { return }
        current.holdTask?.cancel()
        press = nil
        if current.holdActive {
            (onHoldEnded ?? current.holdEnded)?()
        } else if current.isInside, Self.isInside(value.location), isEnabled, acceptsPress {
            // Checked again at the lift: the camera may have started a shot from another button meanwhile.
            if clicksOnPress { Haptics.shutter() }
            action()
        }
    }

    /// Ends a press that never got its onEnded (system cancel, view removed). A running bulb exposure must always end.
    private func releaseCancelledPress(force: Bool = false) {
        guard let current = press, force || !isTouching else { return }
        current.holdTask?.cancel()
        press = nil
        if current.holdActive {
            (onHoldEnded ?? current.holdEnded)?()
        }
    }

    private func activateFromAccessibility() {
        guard isEnabled, acceptsPress else { return }
        if clicksOnPress { Haptics.shutter() }
        action()
    }

    // MARK: - Accessibility

    private var accessibilityTitle: String {
        if style == .sequence { return "Stop" }
        switch kind {
        case .photo: return "Take photo"
        case .video: return "Start recording"
        case .recording: return "Stop recording"
        case .stacking: return "Stop exposure"
        case .night: return "Take night photo"
        case .long: return "Take long exposure"
        // A scene's wait for the phone to settle counts down here too, with no timer set.
        case .countdown: return "Cancel"
        }
    }

    private var accessibilityProgress: String {
        guard kind == .stacking, progress > 0 else { return "" }
        return "\(Int((progress * 100).rounded())) percent"
    }
}

/// The shutter's rim: a fine circle at the outer edge and 60 ticks inside it, every fifth one longer. It takes only
/// a colour, which never changes while it shows, so SwiftUI draws it once and keeps it through presses and redraws.
private struct ShutterDial: View, Equatable {
    let color: Color

    var body: some View {
        ZStack {
            DialTicks(major: false)
                .stroke(color.opacity(0.6), lineWidth: 0.75)
            DialTicks(major: true)
                .stroke(color, lineWidth: 1)
            Circle()
                .strokeBorder(color, lineWidth: DialTicks.rim)
        }
    }
}

private struct DialTicks: Shape {
    static let count = 60
    static let rim: CGFloat = 1.25
    /// The long ticks or the short ones, so each kind gets its own weight.
    let major: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - Self.rim
        for i in 0..<Self.count where (i % 5 == 0) == major {
            let inner = outer - (major ? 3.5 : 2)
            let angle = Double(i) / Double(Self.count) * 2 * .pi
            let (dx, dy) = (CGFloat(cos(angle)), CGFloat(sin(angle)))
            path.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
            path.addLine(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
        }
        return path
    }
}

/// Bulb exposures have no known length, so the ring shows a slow sweep instead of progress. With Reduce Motion, the
/// system's or the app's own, the arc holds still at the top; the stop square already says the shutter is open. It
/// holds still while the battery saver keeps the screen dark too.
private struct PendingArc: View {
    let lineWidth: CGFloat
    var isPaused = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var spinning = false

    var body: some View {
        let holdsStill = systemReduceMotion || AppearanceStore.shared.reduceMotion || isPaused
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: 0.2)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(spinning ? 270 : -90))
            .animation(spinning ? .linear(duration: 1.4).repeatForever(autoreverses: false) : nil, value: spinning)
            .onAppear { spinning = !holdsStill }
            // A repeating animation keeps running after its value changes back, so a change starts a fresh arc,
            // whose onAppear picks the new state.
            .id(holdsStill)
    }
}
