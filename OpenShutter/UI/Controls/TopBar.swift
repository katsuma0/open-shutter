import SwiftUI
import CameraCore

/// The row over the top of the picture: flash, shape, timer, format, histogram, Live Photo and the gear, always
/// those seven and always in the same seven slots, as plain glyphs with nothing behind them, like Apple's Camera. One
/// that has nothing to do in a mode dims in its place and never steps aside, so each stays where the thumb expects
/// it. A tap does a button's main thing; touch and hold lists its choices.
struct TopBar: View {
    @Bindable var model: CameraModel
    /// Set to ask the quick settings panel for its timer sheet.
    @Binding var timerSheetRequested: Bool

    /// Left to right. The gear takes the seventh slot.
    private static let items: [TopBarItem] = [.flash, .aspect, .timer, .format, .histogram, .livePhoto]

    var body: some View {
        let mode = model.settings.mode
        let activity = model.activity
        let isRecording = activity == .recording
        // A focus or white balance bracket is one long capture that reads the settings again for every frame.
        let isHeld = Self.holdsControls(activity) || model.bracketInProgress

        BarSlots {
            ForEach(Array(Self.items.enumerated()), id: \.element) { index, item in
                if mode == .video, item == .format {
                    // VIDEO's format is the size and the frame rate, which need the timer's slot as well.
                    VideoFormatChip(model: model)
                        .modifier(SlotPlacement(slots: BarSlots.format, isHidden: isRecording, isHeld: isHeld))
                } else if !(mode == .video && item == .timer) {
                    let applies = item.applies(in: mode) && TopBarItemButton.isAvailable(item, model: model, mode: mode)
                    // While filming only the light stays: it is wanted most once the recording runs.
                    let stays = item == .flash
                    TopBarItemButton(model: model, item: item, mode: mode, timerSheetRequested: $timerSheetRequested)
                        .disabled(!applies)
                        .opacity(applies ? 1 : 0.3)
                        .modifier(SlotPlacement(slots: index...index, isHidden: isRecording && !stays, isHeld: isHeld))
                }
            }
            if isRecording {
                RecordingCapsule(model: model)
                    .accessibilitySortPriority(Double(BarSlots.count - BarSlots.recording.lowerBound))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .layoutValue(key: BarSlot.self, value: BarSlots.recording)
            }
            SettingsButton(model: model)
                .modifier(SlotPlacement(slots: BarSlots.gear...BarSlots.gear, isHidden: isRecording, isHeld: isHeld))
        }
        .frame(maxWidth: .infinity)
        .frame(height: BarSlots.height)
        // No background: the bar sits over the top of the picture, as in Apple's Camera. The gaps between buttons
        // still take a stray tap, so a near miss doesn't move focus on the picture behind.
        .contentShape(Rectangle())
        // VoiceOver reads it left to right.
        .accessibilityElement(children: .contain)
        .animation(Theme.snappy, value: mode)
        .animation(Theme.snappy, value: isRecording)
        .animation(Theme.snappy, value: isHeld)
    }

    /// Countdown, stacks and saving keep the bar visible but inert, so nothing changes under a running shot.
    /// A single photo in flight is short enough that dimming would only flicker.
    private static func holdsControls(_ activity: CaptureActivity) -> Bool {
        switch activity {
        case .countdown, .stacking, .saving: return true
        case .idle, .capturing, .recording: return false
        }
    }
}

// MARK: - Slots

/// Seven equal slots across the bar on every iPhone: six buttons and the gear. The same seven places on every phone
/// keep each button where the thumb expects it, and the narrowest phone still gives each a 44 pt touch area with room
/// between, so neighbours never crowd or overlap.
private struct BarSlots: Layout {
    static let count = 7
    static let gear = 6
    /// While filming, the red capsule takes the middle three slots.
    static let recording = 2...4
    /// VIDEO's format chip, about 90 pt wide, takes the timer's slot and its own.
    static let format = 2...3
    static let height: CGFloat = 48
    /// From the screen edges, as the bar has always sat.
    static let inset: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Only an unbounded proposal lacks a width; the bar is always offered the screen's.
        let narrowest = CGFloat(Self.count) * 44 + Self.inset * 2
        let width = proposal.width.flatMap { $0.isFinite ? max($0, 0) : nil } ?? narrowest
        return CGSize(width: width, height: Self.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let pitch = max(bounds.width - Self.inset * 2, 0) / CGFloat(Self.count)
        for subview in subviews {
            let span = subview[BarSlot.self]
            let first = min(max(span.lowerBound, 0), Self.count - 1)
            let last = min(max(span.upperBound, first), Self.count - 1)
            let center = bounds.minX + Self.inset + pitch * CGFloat(first + last + 1) / 2
            subview.place(at: CGPoint(x: center, y: bounds.midY), anchor: .center,
                          proposal: ProposedViewSize(width: pitch * CGFloat(last - first + 1), height: bounds.height))
        }
    }
}

/// The slots a view takes, the first to the last.
private struct BarSlot: LayoutValueKey {
    static let defaultValue: ClosedRange<Int> = 0...0
}

/// Puts a view in its slots, hides it while filming, dims it while a shot runs and orders it for VoiceOver.
private struct SlotPlacement: ViewModifier {
    let slots: ClosedRange<Int>
    /// Hidden while filming: only the light and the recording capsule stay.
    let isHidden: Bool
    /// Countdown, stacks and saving keep the bar visible but inert.
    let isHeld: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isHidden ? 0 : (isHeld ? 0.35 : 1))
            .allowsHitTesting(!isHidden && !isHeld)
            .accessibilityHidden(isHidden)
            .accessibilitySortPriority(Double(BarSlots.count - slots.lowerBound))
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
            .layoutValue(key: BarSlot.self, value: slots)
    }
}

// MARK: - Touch and hold

/// A control's tap and its touch and hold menu, laid over the control. Its own view with inputs that never change,
/// so the control's redraws with every settings change leave the system's menu button alone.
private struct BarTouchLayer: View {
    enum Control {
        case resolution, frameRate, settings
    }

    let model: CameraModel
    let control: Control
    let press: PressTracker

    var body: some View {
        MenuOnHoldLayer(press: press) {
            switch control {
            case .resolution: VideoFormatChip.stepResolution(model)
            case .frameRate: VideoFormatChip.stepFrameRate(model)
            case .settings: SettingsButton.open(model)
            }
        } options: {
            switch control {
            case .resolution, .frameRate: VideoFormatOptions(model: model)
            case .settings: SettingsButtonOptions(model: model)
            }
        }
    }
}

// MARK: - Furniture

/// "4K · 30" like the Camera app: tap the resolution or the frame rate to step through what this lens can record.
/// Touch and hold either one lists every size and rate together.
private struct VideoFormatChip: View {
    let model: CameraModel
    @State private var resolutionPress = PressTracker()
    @State private var frameRatePress = PressTracker()

    var body: some View {
        // What this lens records: a lens without the saved 4K 120 shows 4K 60 here, and a tap steps from that.
        let video = model.recordedVideo
        let formats = model.capabilities.formats
        let resolutions = FormatSelector.availableResolutions(colorMode: video.colorMode, among: formats)
        let rates = FormatSelector.availableFrameRates(resolution: video.resolution, colorMode: video.colorMode,
                                                       among: formats)
        // Stays level when the phone turns, like the strip's text chips: turned upright, the chip would hang out of
        // the bar and its two buttons would sit over the picture.
        HStack(spacing: 0) {
            Button {
                Self.stepResolution(model)
            } label: {
                Text(video.resolution.title)
                    .padding(.leading, 12)
                    .padding(.trailing, 5)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Video resolution")
            .accessibilityValue(video.resolution.title)
            .accessibilityHint(HoldMenuText.hint)
            // The touch lands on the menu layer, so the plain style's dimming is done by hand.
            .opacity(resolutionPress.isPressed ? 0.5 : 1)
            .overlay {
                BarTouchLayer(model: model, control: .resolution, press: resolutionPress)
            }
            .disabled(!Self.canStep(resolutions, from: video.resolution, matches: ==))

            Text("\u{00B7}")
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)

            Button {
                Self.stepFrameRate(model)
            } label: {
                Text(Self.rateLabel(video.frameRate))
                    .padding(.leading, 5)
                    .padding(.trailing, 12)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Frame rate")
            .accessibilityValue(Formatting.frameRate(video.frameRate))
            .accessibilityHint(HoldMenuText.hint)
            .opacity(frameRatePress.isPressed ? 0.5 : 1)
            .overlay {
                BarTouchLayer(model: model, control: .frameRate, press: frameRatePress)
            }
            .disabled(!Self.canStep(rates, from: video.frameRate, matches: Self.sameRate))
        }
        .buttonStyle(.plain)
        .font(Theme.chipFont)
        // Its two slots hold "1080p · 29.97" on the narrowest phone; with Larger labels the text shrinks to fit them
        // rather than reach its neighbours.
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(Theme.primaryText)
        // Bare like the glyphs beside it, with their shadow to read over a bright picture.
        .shadow(color: .black.opacity(0.5), radius: 3)
        .contentTransition(.numericText())
        // One unit for the bar's reading order, so both its buttons come before the gear.
        .accessibilityElement(children: .contain)
    }

    fileprivate static func stepResolution(_ model: CameraModel) {
        let video = model.recordedVideo
        let formats = model.capabilities.formats
        let resolutions = FormatSelector.availableResolutions(colorMode: video.colorMode, among: formats)
        guard !resolutions.isEmpty else { return }
        let index = resolutions.firstIndex(of: video.resolution)
        // A size this lens can't record steps to the first one it can.
        let next = index.map { resolutions[($0 + 1) % resolutions.count] } ?? resolutions[0]
        guard next != video.resolution else { return }
        // Not every size records at every rate, so the rate moves to the closest one the new size supports. Closest to
        // the saved rate rather than the one shown, so a size that has the saved rate gets it back.
        let rates = FormatSelector.availableFrameRates(resolution: next, colorMode: video.colorMode, among: formats)
        let saved = model.settings.video.frameRate
        let rate = nearest(to: saved, in: rates) ?? saved
        Haptics.tick()
        withAnimation(Theme.snappy) {
            model.updateSettings {
                $0.video.resolution = next
                $0.video.frameRate = rate
            }
        }
    }

    fileprivate static func stepFrameRate(_ model: CameraModel) {
        let video = model.recordedVideo
        let rates = FormatSelector.availableFrameRates(resolution: video.resolution, colorMode: video.colorMode,
                                                       among: model.capabilities.formats)
        guard !rates.isEmpty else { return }
        let index = rates.firstIndex(where: { sameRate($0, video.frameRate) })
        let next = index.map { rates[($0 + 1) % rates.count] } ?? rates[0]
        guard !sameRate(next, video.frameRate) else { return }
        Haptics.tick()
        withAnimation(Theme.snappy) {
            model.updateSettings { $0.video.frameRate = next }
        }
    }

    private static func nearest(to rate: Double, in rates: [Double]) -> Double? {
        rates.min(by: { abs($0 - rate) < abs($1 - rate) })
    }

    /// A tap changes something: there are two or more choices, or the value shown isn't one of them, which the first
    /// choice replaces.
    private static func canStep<Value>(_ choices: [Value], from current: Value, matches: (Value, Value) -> Bool) -> Bool {
        guard let first = choices.first else { return false }
        return choices.count > 1 || !matches(first, current)
    }

    fileprivate static func sameRate(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.01
    }

    /// "30", "29.97": the chip has no room for "fps".
    fileprivate static func rateLabel(_ fps: Double) -> String {
        guard fps.isFinite, fps > 0, fps < 10_000 else { return "-" }
        if abs(fps - fps.rounded()) < 0.01 {
            return "\(Int(fps.rounded()))"
        }
        return String(format: "%.2f", fps)
    }
}

/// Every size this lens records, largest first, with each of its frame rates, such as "4K at 30".
private struct VideoFormatOptions: View {
    let model: CameraModel

    var body: some View {
        // What the lens records, as on the chip, so the marked row is the one in use.
        let video = model.recordedVideo
        let formats = model.capabilities.formats
        let resolutions = FormatSelector.availableResolutions(colorMode: video.colorMode, among: formats)
        ForEach(Array(resolutions.reversed())) { resolution in
            let rates = FormatSelector.availableFrameRates(resolution: resolution, colorMode: video.colorMode,
                                                           among: formats)
            Section {
                ForEach(rates, id: \.self) { rate in
                    let isCurrent = resolution == video.resolution && VideoFormatChip.sameRate(rate, video.frameRate)
                    Toggle(isOn: Binding(get: { isCurrent }, set: { _ in choose(resolution, rate) })) {
                        Text("\(resolution.title) at \(VideoFormatChip.rateLabel(rate))")
                    }
                }
            }
        }
    }

    private func choose(_ resolution: VideoResolution, _ rate: Double) {
        Haptics.tick()
        withAnimation(Theme.snappy) {
            model.updateSettings {
                $0.video.resolution = resolution
                $0.video.frameRate = rate
            }
        }
    }
}

private struct SettingsButton: View {
    let model: CameraModel
    @State private var press = PressTracker()

    var body: some View {
        Button {
            Self.open(model)
        } label: {
            Upright(model: model) {
                Image(systemName: "gearshape")
            }
        }
        .buttonStyle(BarCircleStyle(isPressed: press.isPressed))
        .accessibilityLabel("Settings")
        .accessibilityHint(HoldMenuText.hint)
        .overlay {
            BarTouchLayer(model: model, control: .settings, press: press)
        }
    }

    fileprivate static func open(_ model: CameraModel) {
        Haptics.tap()
        model.isDrawerOpen = false
        model.isSettingsPresented = true
    }
}

/// The gear's touch and hold menu.
private struct SettingsButtonOptions: View {
    let model: CameraModel

    var body: some View {
        Button {
            SettingsButton.open(model)
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
    }
}

/// Reads the duration on its own, so the four ticks a second while filming redraw only this capsule.
private struct RecordingCapsule: View {
    let model: CameraModel

    var body: some View {
        let seconds = Self.wholeSeconds(model.recordingDuration)
        // Stays level when the phone turns: turned upright, the capsule would hang over the picture being filmed.
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.primaryText)
                .frame(width: 7, height: 7)
            Text(Self.timecode(seconds))
                .font(Theme.valueFont)
                .contentTransition(.numericText(value: Double(seconds)))
        }
        .foregroundStyle(Theme.primaryText)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Theme.recording, in: Capsule())
        .animation(Theme.snappy, value: seconds)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording")
        .accessibilityValue(Self.timecode(seconds))
    }

    /// Clamped before the conversion, because Int(_:) traps on NaN or out of range values.
    private static func wholeSeconds(_ duration: TimeInterval) -> Int {
        guard duration.isFinite, duration > 0 else { return 0 }
        return Int(min(duration, 359_999).rounded(.down))
    }

    /// "00:01:05", the Camera app's recording clock.
    private static func timecode(_ total: Int) -> String {
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        // %ld: Swift's Int is 64 bits wide, which %d (a C int) doesn't promise to read.
        return String(format: "%02ld:%02ld:%02ld", hours, minutes, seconds)
    }
}

// MARK: - Styles and helpers

/// A bar button's look: the glyph alone in a 44 pt touch area, white, or the accent while its setting is on. No
/// circle behind it, as in Apple's Camera, so it carries a shadow to read over a bright picture. The name is from
/// when each sat in a glass circle.
struct BarCircleStyle: ButtonStyle {
    var isActive = false
    /// A press on the button's touch and hold layer.
    var isPressed = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isPressed
        configuration.label
            .font(.system(size: 18 * Theme.labelScale, weight: .semibold))
            .foregroundStyle(isActive ? Theme.accent : Theme.primaryText)
            .shadow(color: .black.opacity(0.5), radius: 3)
            .frame(width: 44, height: 44)
            .scaleEffect(pressed ? 0.86 : 1)
            .opacity(pressed ? 0.7 : 1)
            .animation(Theme.snappy, value: pressed)
            .contentShape(Rectangle())
    }
}

/// Rotates its content with the phone. Motion is read here so attitude updates redraw single icons, not the bar.
private struct Upright<Content: View>: View {
    let model: CameraModel
    // Built once in init: a stored closure never compares equal, so SwiftUI could never skip this view.
    let content: Content

    init(model: CameraModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    var body: some View {
        content.uprightRotation(model.motion.iconRotationDegrees)
    }
}
