import SwiftUI
import CameraCore

/// The tripod and hold-still status over the picture in NIGHT, LONG and a stacked MANUAL shutter. Those shots stand or
/// fall on a still phone, so the status is large, on a backing of its own that reads over a white sky or a black one,
/// and never takes a touch, so taps still focus.
///
/// Place it at the top of the open part of the frame, 12 pt down. It shows exactly while `model.steadyStatus` has a
/// message (the model drops it under the Camera Control's overlay and the battery saver's black screen). It is as
/// tall as its pill, and has no height while hidden, so toasts and badges can move below it by its measured height.
/// It takes the width it is offered and centers the pill with 16 pt to spare on each side. With the phone on its side
/// the pill moves to the edge that is then the person's top and reads upright there; the banner is then as tall as
/// the pill is long.
struct SteadyBanner: View {
    let model: CameraModel

    var body: some View {
        SteadyBannerSlot(model: model, message: model.steadyStatus)
            // The controls under the picture cap their text the same way, so the pill keeps to the top band.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// Reads the phone's turn on its own, so the motion updates redraw this slot and leave the pill alone.
private struct SteadyBannerSlot: View {
    let model: CameraModel
    let message: SteadyMessage?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let turns = model.motion.quarterTurns
        let degrees = model.motion.iconRotationDegrees
        let reduceMotion = systemReduceMotion || AppearanceStore.shared.reduceMotion
        ZStack {
            if let message {
                // One pill for as long as a status shows: a new state changes its words and colour in place. Two
                // pills crossing, one fading out under the other, read as a smear while a phone held by hand flips
                // between moving and steady.
                SteadyPill(message: message, pulse: model.motion.isAvailable ? model.motionPulse : nil)
                    // At once, too. A fade between two states draws the words of both over each other for as long
                    // as it runs, and that is the frame a screenshot catches. A control that changes the state
                    // inside an animation of its own must not reach the pill either.
                    .animation(nil, value: message)
                    .modifier(PersonsTop(degrees: degrees, sideways: turns % 2 != 0))
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(.horizontal, turns % 2 == 0 ? 16 : 12)
        .frame(maxWidth: .infinity, alignment: Self.alignment(turns))
        // Only the pill coming and going fades.
        .animation(.easeInOut(duration: 0.2), value: message != nil)
        .animation(.easeInOut(duration: 0.2), value: turns)
        .modifier(SteadyAnnouncements(message: message, isHidden: model.dimmer.isDimmed || model.controlsFullscreen))
        .allowsHitTesting(false)
    }

    /// The person's top edge: the right one with the top of the phone to the left, the left one the other way.
    private static func alignment(_ turns: Int) -> Alignment {
        switch turns {
        case 1: return .trailing
        case 3: return .leading
        default: return .center
        }
    }
}

/// Turns the pill upright for the person. On its side it is laid out turned, so it takes the room it covers and
/// can't reach over the top controls.
private struct PersonsTop: ViewModifier {
    let degrees: Double
    let sideways: Bool

    func body(content: Content) -> some View {
        if sideways {
            let layout = QuarterTurnLayout()
            layout {
                content.rotationEffect(.degrees(degrees))
            }
        } else {
            content.rotationEffect(.degrees(degrees))
        }
    }
}

/// Lays its one view out a quarter turn round: the view is offered the height as its width and the width as its
/// height, and the layout is as wide as the view is tall. The caller turns the view to match.
private struct QuarterTurnLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(ProposedViewSize(width: proposal.height, height: proposal.width))
        return CGSize(width: size.height, height: size.width)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        view.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                   proposal: ProposedViewSize(width: bounds.height, height: bounds.width))
    }
}

// MARK: - The sign

/// One state of the steady sign, drawn straight on the picture like the histogram: no box behind it, the words and
/// the icon carried by a soft shadow, and a live trace of the phone's movement beside them. A warning shows in its
/// colour (orange, the words and the icon) rather than on a filled block. A calm state fades to 70 percent after
/// 3 s, and every new state starts at full strength.
private struct SteadyPill: View {
    let message: SteadyMessage
    /// The live movement, where a sensor reports it.
    let pulse: MotionPulse?
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .headline) private var iconSize: CGFloat = 22
    @State private var isQuiet = false

    /// Orange, not the accent: the accent is yellow by default, and a yellow word over a lit street is lost.
    static let warningInk = Color(red: 1.0, green: 0.62, blue: 0.2)

    var body: some View {
        let warning = message.isWarning
        let ink = warning ? Self.warningInk : Theme.primaryText
        let iconInk = warning ? ink : (message.isIconAccented ? Theme.accent : Theme.primaryText)
        // With no backing, the shadow is what keeps white words apart from a white sky.
        let shade = contrast == .increased || AppearanceStore.shared.solidControls ? 0.95 : 0.75
        HStack(spacing: 10) {
            SteadyIconView(icon: message.icon, size: iconSize)
                .foregroundStyle(iconInk)
            VStack(alignment: .leading, spacing: 1) {
                Text(message.title)
                    .font(.headline)
                if let detail = message.detail {
                    Text(detail)
                        .font(.footnote.weight(.medium))
                        .opacity(0.9)
                }
            }
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if let pulse {
                MotionTrace(pulse: pulse)
            }
        }
        .shadow(color: .black.opacity(shade), radius: 3)
        .shadow(color: .black.opacity(shade * 0.5), radius: 10)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: 40)
        .opacity(isQuiet ? 0.7 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(message.spoken))
        // The sign stays while its state changes, so every state starts its own count at full strength.
        .task(id: message) {
            if isQuiet { isQuiet = false }
            guard Self.quietens(message) else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { isQuiet = true }
        }
    }

    /// States that only confirm all is well step back once they have been read.
    private static func quietens(_ message: SteadyMessage) -> Bool {
        message == .steady || message == .capturing
    }
}

/// The last two seconds of the phone's movement as a small hill, drawn like the histogram: a smooth translucent
/// area with no box, its old end and its bottom fading out. It is coloured by how much the phone moves now, green
/// when still, then yellow, orange and red, so a glance says whether it is ready.
private struct MotionTrace: View {
    let pulse: MotionPulse

    private static let size = CGSize(width: 64, height: 24)

    var body: some View {
        let history = pulse.history
        let rgb = MotionPulse.color(for: pulse.level)
        let color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        Canvas { context, size in
            let curve = Self.curve(history, size: size)
            var area = curve
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(color.opacity(0.45)))
            context.stroke(curve, with: .color(color), lineWidth: 1.5)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .mask {
            // Old movement fades out to the left, and the hill fades into the picture at its foot.
            LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing)
                .mask {
                    LinearGradient(colors: [.black, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                }
        }
        .accessibilityHidden(true)
    }

    /// A still phone draws a flat line just above the foot; any movement lifts it. Joined through midpoints, so it
    /// reads as one smooth trace.
    private static func curve(_ values: [Double], size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = size.width / CGFloat(values.count - 1)
        let floor = size.height - 2
        let points = values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: floor - CGFloat(min(max(value, 0), 1)) * (floor - 2))
        }
        path.move(to: points[0])
        for index in 1..<points.count {
            let previous = points[index - 1]
            let mid = CGPoint(x: (previous.x + points[index].x) / 2, y: (previous.y + points[index].y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}

private struct SteadyIconView: View {
    let icon: SteadyIcon
    let size: CGFloat

    var body: some View {
        switch icon {
        case .tripod:
            TripodGlyph()
                .frame(width: size * 10 / 11, height: size)
        case .hand:
            Image(systemName: "hand.raised.fill")
                .font(.system(size: size * 0.82, weight: .semibold))
                .frame(width: size, height: size)
        }
    }
}

// MARK: - VoiceOver

/// VoiceOver hears the pill change between moving and steady before the shot, a bump or a drift during it, and "Keep
/// the phone still" once as it starts. At most once every 3 s: a change inside that wait is said when the wait is
/// over, and only if it still holds and differs from what was said last. A pill that comes back after the dark
/// screen or the Camera Control's overlay hid it belongs to the same shot, so its start isn't said again.
private struct SteadyAnnouncements: ViewModifier {
    let message: SteadyMessage?
    /// The model takes the pill away under the battery saver's dark screen and the Camera Control's overlay.
    let isHidden: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var latest: SteadyMessage?
    @State private var lastSaid: String?
    @State private var lastSaidAt = Date.distantPast
    /// Counts changes that came too soon after the last announcement; the newest state is said when the wait ends.
    @State private var deferred = 0
    /// The pill was hidden while frames came in. The shot goes on under the dark screen and the overlay, so the
    /// pill that comes back is still that shot's.
    @State private var hiddenInShot = false

    private static let interval: TimeInterval = 3

    func body(content: Content) -> some View {
        content
            .onChange(of: message) { old, new in
                guard voiceOver else { return }
                latest = new
                // Only a pill hidden mid-shot comes back to the same shot. No pill can also come before a new one:
                // the overlay was up at the press, or an intervalometer starts the next shot as soon as the last
                // one's frames are all in, with no steady reading shown in between.
                let returning = old == nil && hiddenInShot
                hiddenInShot = new == nil && isHidden && old?.isDuringShot == true
                guard let new else { return }
                if new.isDuringShot, old?.isDuringShot != true, !returning {
                    // Speak status says "Keep the phone still" itself when a long shot starts.
                    if !AppearanceStore.shared.speakStatus { say(new.spoken) }
                    return
                }
                guard Self.isNews(from: old, to: new) else { return }
                if Date().timeIntervalSince(lastSaidAt) >= Self.interval {
                    say(new.spoken)
                } else {
                    deferred &+= 1
                }
            }
            .onChange(of: isHidden) { _, hidden in
                // Shown again with no pill: that shot has all its frames or was stopped, so the next pill is a new
                // shot's.
                if !hidden, message == nil { hiddenInShot = false }
            }
            .task(id: deferred) {
                guard deferred > 0 else { return }
                let wait = Self.interval - Date().timeIntervalSince(lastSaidAt)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, let latest, Self.isWorthSaying(latest), latest.spoken != lastSaid else { return }
                say(latest.spoken)
            }
    }

    private func say(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
        lastSaid = text
        lastSaidAt = Date()
    }

    /// Moving to steady or back before the shot, and a bump or a drift during it. What the shot needs changing while
    /// the phone moves is the person's own doing, and the pill coming back on target isn't news.
    private static func isNews(from old: SteadyMessage?, to new: SteadyMessage) -> Bool {
        switch new {
        case .bumped, .drifted:
            return true
        case .steady, .useTripod, .holdStill:
            guard let old, old.isFramingReading else { return false }
            return (old == .steady) != (new == .steady)
        default:
            return false
        }
    }

    private static func isWorthSaying(_ message: SteadyMessage) -> Bool {
        message.isFramingReading || message == .bumped || message == .drifted
    }
}

private extension SteadyMessage {
    /// Frames are coming in.
    var isDuringShot: Bool {
        switch self {
        case .capturing, .drifted, .bumped: return true
        default: return false
        }
    }

    /// Before the shot, with a sensor that tells moving from steady.
    var isFramingReading: Bool {
        self == .steady || self == .useTripod || self == .holdStill
    }
}
