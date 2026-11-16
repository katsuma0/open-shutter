import SwiftUI
import UIKit
import CameraCore

// The top bar's buttons, all but the gear, and the steps they share with the quick settings drawer. The bar redraws
// with every settings write, 120 a second while a dial turns, so each button is its own small view that reads only
// what it shows.

// MARK: - Buttons

/// One of the top bar's fixed buttons: flash, shape, timer, format, histogram or Live Photo.
struct TopBarItemButton: View {
    let model: CameraModel
    let item: TopBarItem
    let mode: CaptureMode
    /// The Timer button ends its cycle, and its menu, in the timer sheet, which the camera screen presents.
    @Binding var timerSheetRequested: Bool

    var body: some View {
        switch item {
        case .flash:
            // In VIDEO the flash button works the flashlight, from the same place.
            if mode == .video {
                BarTorch(model: model)
            } else {
                BarFlash(model: model, mode: mode)
            }
        case .livePhoto:
            BarLivePhoto(model: model)
        case .timer:
            BarTimer(model: model, mode: mode, timerSheetRequested: $timerSheetRequested)
        case .aspect:
            BarAspect(model: model)
        case .format:
            BarFormat(model: model)
        case .histogram:
            BarHistogram(model: model)
        default:
            // The bar draws the six above and nothing else. CameraCore keeps the other cases for its stored layout.
            EmptyView()
        }
    }

    /// What CameraCore leaves to the app: whether `item` works on this camera with these settings. One that doesn't
    /// dims in its slot and takes no taps, so nothing on the bar ever moves.
    static func isAvailable(_ item: TopBarItem, model: CameraModel, mode: CaptureMode) -> Bool {
        let caps = model.capabilities
        switch item {
        case .flash:
            return mode == .video ? caps.hasTorch : caps.hasFlash
        case .livePhoto:
            return caps.livePhotoSupported
        case .timer:
            return QuickActions.timerApplies(model)
        case .format:
            return QuickActions.canChangeFormat(model)
        default:
            // The shape and the histogram work on every camera, and the other cases are never asked about.
            return true
        }
    }
}

// MARK: - Flash and flashlight

private struct BarFlash: View {
    let model: CameraModel
    let mode: CaptureMode
    @State private var press = PressTracker()

    var body: some View {
        let flash = model.settings.capture.flash
        // A MANUAL shutter past the hardware limit is shot as a stack, which never fires the flash. The button dims
        // in its slot for as long as the shutter dial is past the limit.
        let stacked = mode == .manual && model.shutterIsStacked
        Button {
            Self.step(model)
        } label: {
            Upright(model: model) {
                Image(systemName: flash.symbolName)
            }
        }
        .buttonStyle(BarCircleStyle(isActive: flash == .on && !stacked, isPressed: press.isPressed))
        .accessibilityLabel("Flash")
        .accessibilityValue(flash.title)
        .accessibilityHint(stacked ? "Stacked exposures don't use the flash." : HoldMenuText.hint)
        .overlay {
            ItemTouchLayer(model: model, control: .flash, press: press)
        }
        .disabled(stacked)
        .opacity(stacked ? 0.35 : 1)
    }

    static func step(_ model: CameraModel) {
        Haptics.tap()
        model.updateSettings { $0.capture.flash = $0.capture.flash.nextInCycle }
    }
}

/// Off, Auto, On: the order the tap steps through.
private struct FlashOptions: View {
    let model: CameraModel

    var body: some View {
        let flash = model.settings.capture.flash
        Picker("Flash", selection: Binding(get: { flash }, set: { choose($0) })) {
            ForEach(FlashSetting.allCases) { setting in
                Label(setting.title, systemImage: setting.symbolName).tag(setting)
            }
        }
        .pickerStyle(.inline)
    }

    private func choose(_ flash: FlashSetting) {
        Haptics.tick()
        model.updateSettings { $0.capture.flash = flash }
    }
}

/// The video light, where the flash button sits in the photo modes. The front camera has none, so it dims there.
private struct BarTorch: View {
    let model: CameraModel
    @State private var press = PressTracker()

    var body: some View {
        let isOn = model.torchOn
        Button {
            Self.toggle(model)
        } label: {
            Upright(model: model) {
                Image(systemName: isOn ? "flashlight.on.fill" : "flashlight.off.fill")
            }
        }
        .buttonStyle(BarCircleStyle(isActive: isOn, isPressed: press.isPressed))
        .accessibilityLabel("Flashlight")
        .accessibilityValue(TorchBrightness.current(isOn: isOn, level: model.torchLevel).spokenValue)
        .accessibilityHint(HoldMenuText.hint)
        // The menu layer is hidden from VoiceOver, and the tap only turns the light on or off, so the brightness
        // steps would otherwise be out of reach.
        .accessibilityActions {
            ForEach(TorchBrightness.allCases) { choice in
                Button(choice.title) { Self.choose(choice, model: model) }
            }
        }
        .overlay {
            ItemTouchLayer(model: model, control: .torch, press: press)
        }
    }

    static func toggle(_ model: CameraModel) {
        // setTorch plays its own click.
        model.setTorch(!model.torchOn)
    }

    /// The model clicks for both.
    static func choose(_ brightness: TorchBrightness, model: CameraModel) {
        if let level = brightness.level {
            model.setTorchLevel(level)
        } else {
            model.setTorch(false)
        }
    }
}

private struct TorchOptions: View {
    let model: CameraModel

    var body: some View {
        let brightness = TorchBrightness.current(isOn: model.torchOn, level: model.torchLevel)
        Picker("Flashlight", selection: Binding(get: { brightness }, set: { BarTorch.choose($0, model: model) })) {
            ForEach(TorchBrightness.allCases) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .pickerStyle(.inline)
    }
}

/// The flashlight's touch and hold choices.
private enum TorchBrightness: CaseIterable, Identifiable {
    case off, low, medium, full

    var id: Self { self }

    var title: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .medium: return "Medium"
        case .full: return "Full"
        }
    }

    /// Torch level, 0...1; nil is off.
    var level: Double? {
        switch self {
        case .off: return nil
        case .low: return 0.25
        case .medium: return 0.6
        case .full: return 1
        }
    }

    var spokenValue: String {
        switch self {
        case .off: return "Off"
        case .low: return "On, low"
        case .medium: return "On, medium"
        case .full: return "On"
        }
    }

    /// The choice closest to what the light is doing.
    static func current(isOn: Bool, level: Double) -> TorchBrightness {
        guard isOn, level.isFinite else { return .off }
        let lit: [TorchBrightness] = [.low, .medium, .full]
        return lit.min(by: { abs(($0.level ?? 0) - level) < abs(($1.level ?? 0) - level) }) ?? .full
    }
}

private extension FlashSetting {
    /// Off, Auto, On, the Camera app's order.
    var nextInCycle: FlashSetting {
        switch self {
        case .off: return .auto
        case .auto: return .on
        case .on: return .off
        }
    }
}

// MARK: - Live Photo

private struct BarLivePhoto: View {
    let model: CameraModel

    var body: some View {
        let capture = model.settings.capture
        // The photo output can't record the movie part while it delivers RAW.
        let blockedByRaw = capture.rawFormat != RawFormat.none
        let isOn = capture.livePhoto && !blockedByRaw
        Button {
            Haptics.tap()
            model.updateSettings { $0.capture.livePhoto.toggle() }
        } label: {
            Upright(model: model) {
                Image(systemName: isOn ? "livephoto" : "livephoto.slash")
            }
        }
        .buttonStyle(BarCircleStyle(isActive: isOn))
        .disabled(blockedByRaw)
        .opacity(blockedByRaw ? 0.4 : 1)
        .accessibilityLabel("Live Photo")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(blockedByRaw ? "Turn off RAW to use Live Photos." : "")
    }
}

// MARK: - Timer

/// Steps the self timer, and in the advanced interface ends the cycle in the timer sheet, like the drawer's item. It
/// also shows an intervalometer or a bracket that is set, so the bar says what the next press starts.
private struct BarTimer: View {
    let model: CameraModel
    let mode: CaptureMode
    @Binding var timerSheetRequested: Bool
    @State private var press = PressTracker()
    @State private var cycle = TimerCycle()

    var body: some View {
        let preview = SchedulePreview(model: model, mode: mode)
        Button {
            Self.step(model, cycle: cycle, timerSheetRequested: $timerSheetRequested)
        } label: {
            Upright(model: model) {
                if preview.isEmpty {
                    Image(systemName: "timer")
                } else {
                    ScheduleFace(preview: preview)
                }
            }
        }
        .buttonStyle(BarCircleStyle(isActive: !preview.isEmpty, isPressed: press.isPressed))
        .accessibilityLabel(TopBarItem.timer.title(advanced: model.isAdvanced))
        .accessibilityValue(preview.spokenValue)
        .accessibilityHint(HoldMenuText.hint)
        .overlay {
            TimerItemTouchLayer(model: model, press: press, cycle: cycle, timerSheetRequested: $timerSheetRequested)
        }
        // Any other change of the schedule starts the cycle over, as in the drawer.
        .onChange(of: model.settings.capture.schedule) { _, _ in
            cycle.sheetOffered = false
        }
    }

    static func step(_ model: CameraModel, cycle: TimerCycle, timerSheetRequested: Binding<Bool>) {
        let advanced = model.isAdvanced
        switch QuickActions.timerStep(after: model.settings.capture.schedule,
                                      delays: QuickActions.delays(advanced: advanced),
                                      endsInSheet: advanced, sheetOffered: cycle.sheetOffered) {
        case .schedule(let schedule):
            cycle.sheetOffered = false
            QuickActions.setSchedule(schedule, model)
        case .sheet:
            cycle.sheetOffered = true
            Haptics.tap()
            // The camera screen presents the sheet; the quick settings panel stays as it is.
            timerSheetRequested.wrappedValue = true
        }
    }
}

/// Whether the Timer button's last tap offered the timer sheet, so the next one turns the timer off. A reference, so
/// the button and its touch and hold layer share it, and changing it redraws nothing.
@MainActor
private final class TimerCycle {
    var sheetOffered = false
}

private struct TimerItemTouchLayer: View {
    let model: CameraModel
    let press: PressTracker
    let cycle: TimerCycle
    @Binding var timerSheetRequested: Bool

    var body: some View {
        MenuOnHoldLayer(press: press) {
            BarTimer.step(model, cycle: cycle, timerSheetRequested: $timerSheetRequested)
        } options: {
            TimerOptions(model: model, timerSheetRequested: $timerSheetRequested)
        }
    }
}

/// The self timer's delays. The simple interface offers the ones its drawer steps through; the advanced one adds the
/// rest and the way into the timer sheet.
private struct TimerOptions: View {
    let model: CameraModel
    @Binding var timerSheetRequested: Bool

    var body: some View {
        let advanced = model.isAdvanced
        let schedule = model.settings.capture.schedule
        ForEach(QuickActions.delays(advanced: advanced), id: \.self) { delay in
            // A burst or an intervalometer is none of the plain delays, so no row is marked for it.
            let isCurrent = schedule.shots == 1 && abs(schedule.delay - delay) < 0.01
            Toggle(isOn: Binding(get: { isCurrent }, set: { _ in choose(delay) })) {
                // Worded like the other touch and hold menus; the bar itself keeps the compact "3s".
                Text(QuickActions.delayTitle(delay))
            }
        }
        if advanced {
            Section {
                Button(action: showSheet) {
                    Label("More\u{2026}", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    private func choose(_ delay: Double) {
        QuickActions.setSchedule(CaptureSchedule(delay: delay), model)
    }

    /// The camera screen presents the sheet; the quick settings panel stays as it is.
    private func showSheet() {
        timerSheetRequested = true
    }
}

/// What the next press adds to the photo: a timer or an intervalometer, and a bracket. Video and bulb start on the
/// press itself and stacks ignore brackets, so each shows only where it applies. A bracket the photo output can't
/// shoot comes out as a single photo, so it shows nothing either.
private struct SchedulePreview {
    var schedule: CaptureSchedule?
    var bracket: BracketPlan?
    /// The frames the bracket really takes, while it shows.
    var bracketFrames = 0

    @MainActor
    init(model: CameraModel, mode: CaptureMode) {
        let capture = model.settings.capture
        let isBulb = mode == .long && model.settings.longExposure.bulb
        if !capture.schedule.isOff, mode != .video, !isBulb {
            schedule = capture.schedule
        }
        let singlePhoto = mode == .photo || (mode == .manual && !model.shutterIsStacked)
        guard !capture.bracket.isOff, singlePhoto else { return }
        // A focus bracket is centered on the manual focus distance. Under autofocus it is wherever the lens is at the
        // press, which would move this count while framing and through the bracket, so it counts around the middle.
        let frames = Self.frameCount(capture.bracket, maxBurst: model.capabilities.maxBracketCount,
                                     focusCenter: model.effectiveFocus.lensPosition ?? 0.5)
        if frames > 1 {
            bracket = capture.bracket
            bracketFrames = frames
        }
    }

    var isEmpty: Bool { schedule == nil && bracket == nil }

    var spokenValue: String {
        var parts: [String] = []
        if let schedule { parts.append(schedule.summary) }
        if let bracket { parts.append(bracket.summary) }
        return parts.isEmpty ? "Off" : parts.joined(separator: ", ")
    }

    /// "3s" for a timer, "×20" for a burst or an intervalometer. The menus and the timer sheet show the rest.
    static func label(_ schedule: CaptureSchedule) -> String {
        if schedule.shots > 1 {
            return "\u{00D7}\(schedule.shots)"
        }
        return Formatting.compactDuration(schedule.delay)
    }

    /// The frames the bracket really takes. The photo output caps an exposure bracket at its burst limit and keeps
    /// the count odd so the metered frame stays in the middle; under two frames it takes a single photo. A focus
    /// spread wider than the lens travel piles frames on its ends, so that count depends on the center.
    private static func frameCount(_ bracket: BracketPlan, maxBurst: Int, focusCenter: Double) -> Int {
        switch bracket.kind {
        case .off:
            return 1
        case .exposure:
            let planned = bracket.exposureOffsets().count
            var count = min(planned, max(maxBurst, 1))
            if count < planned && count % 2 == 0 { count -= 1 }
            return max(count, 1)
        case .focus:
            return bracket.focusPositions(center: focusCenter).count
        case .whiteBalance:
            return bracket.kelvinValues(center: 5500).count
        }
    }
}

/// The Timer button's face: "3s" under a timer glyph or the bracket's frame count under a stack glyph, or both on
/// two small rows. The button has no room for more; VoiceOver and the timer sheet say the rest.
private struct ScheduleFace: View {
    let preview: SchedulePreview

    var body: some View {
        let scale = Theme.labelScale
        let timer = preview.schedule.map { SchedulePreview.label($0) }
        let frames = preview.bracket == nil ? nil : "\(preview.bracketFrames)"
        Group {
            if let timer, let frames {
                VStack(spacing: 1) {
                    Self.row(symbol: "timer", text: timer, scale: scale)
                    Self.row(symbol: "square.stack.3d.up", text: frames, scale: scale)
                }
            } else if let text = timer ?? frames {
                VStack(spacing: 0) {
                    Image(systemName: timer == nil ? "square.stack.3d.up" : "timer")
                        .font(.system(size: 11, weight: .regular))
                    Text(text)
                        .font(.system(size: 10 * scale, weight: .medium).monospacedDigit())
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 3)
    }

    private static func row(symbol: String, text: String, scale: CGFloat) -> some View {
        HStack(spacing: 1.5) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .medium))
            Text(text)
                .font(.system(size: 9.5 * scale, weight: .medium).monospacedDigit())
        }
    }
}

// MARK: - Photo shape

private struct BarAspect: View {
    let model: CameraModel
    @State private var press = PressTracker()

    var body: some View {
        let aspect = model.settings.capture.aspect
        Button {
            QuickActions.stepAspect(model)
        } label: {
            Upright(model: model) {
                ItemText(aspect.label, size: 13)
            }
        }
        .buttonStyle(BarCircleStyle(isActive: QuickActions.aspectIsActive(aspect), isPressed: press.isPressed))
        .accessibilityLabel(TopBarItem.aspect.title(advanced: model.isAdvanced))
        .accessibilityValue(aspect.label)
        .accessibilityHint(HoldMenuText.hint)
        .overlay {
            ItemTouchLayer(model: model, control: .aspect, press: press)
        }
    }
}

/// Every shape, a ratio entered in Settings as a row of its own, and the way to enter one: Custom ratio, in the
/// Camera section at the top of Settings.
private struct AspectOptions: View {
    let model: CameraModel

    var body: some View {
        let advanced = model.isAdvanced
        let presets = QuickActions.aspects(advanced: advanced)
        let aspect = model.settings.capture.aspect
        let isPreset = presets.contains(where: { $0.matches(aspect) })
        Picker("Aspect ratio", selection: Binding(get: { QuickActions.aspectSelection(aspect, among: presets) },
                                                  set: { QuickActions.setAspect($0, model) })) {
            ForEach(presets) { preset in
                Text(preset.label).tag(preset)
            }
            if !isPreset {
                Text(aspect.label).tag(aspect)
            }
        }
        .pickerStyle(.inline)
        if advanced {
            Button {
                // Settings holds the side fields; the bar shows the new ratio once it closes.
                model.isSettingsPresented = true
            } label: {
                Label("Custom\u{2026}", systemImage: "slider.horizontal.3")
            }
        }
    }
}

// MARK: - Format and histogram

private struct BarFormat: View {
    let model: CameraModel

    var body: some View {
        let format = model.settings.capture.processedFormat
        let value = QuickActions.formatValue(format)
        Button {
            QuickActions.stepFormat(model)
        } label: {
            Upright(model: model) {
                ItemText(value, size: 12)
            }
        }
        .buttonStyle(BarCircleStyle(isActive: format != .heif))
        .accessibilityLabel(TopBarItem.format.title(advanced: true))
        .accessibilityValue(value)
    }
}

private struct BarHistogram: View {
    let model: CameraModel
    @State private var press = PressTracker()

    var body: some View {
        let style = model.settings.display.histogram
        Button {
            QuickActions.stepHistogram(model)
        } label: {
            Upright(model: model) {
                ItemSymbol.image(.histogram)
                    .marksOn(style != .off)
            }
        }
        .buttonStyle(BarCircleStyle(isActive: style != .off, isPressed: press.isPressed))
        .accessibilityLabel(TopBarItem.histogram.title(advanced: true))
        .accessibilityValue(style.title)
        .accessibilityHint(HoldMenuText.hint)
        .overlay {
            ItemTouchLayer(model: model, control: .histogram, press: press)
        }
    }
}

private struct HistogramOptions: View {
    let model: CameraModel

    var body: some View {
        let style = model.settings.display.histogram
        Picker("Histogram", selection: Binding(get: { style },
                                               set: { QuickActions.set(\.display.histogram, to: $0, model) })) {
            ForEach(HistogramStyle.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.inline)
    }
}

// MARK: - Touch and hold

/// A button's tap and its touch and hold menu, laid over the button. Its own view with inputs that never change, so
/// the button's redraws with every settings change leave the system's menu button alone.
private struct ItemTouchLayer: View {
    enum Control {
        case flash, torch, aspect, histogram
    }

    let model: CameraModel
    let control: Control
    let press: PressTracker

    var body: some View {
        MenuOnHoldLayer(press: press) {
            switch control {
            case .flash: BarFlash.step(model)
            case .torch: BarTorch.toggle(model)
            case .aspect: QuickActions.stepAspect(model)
            case .histogram: QuickActions.stepHistogram(model)
            }
        } options: {
            switch control {
            case .flash: FlashOptions(model: model)
            case .torch: TorchOptions(model: model)
            case .aspect: AspectOptions(model: model)
            case .histogram: HistogramOptions(model: model)
            }
        }
    }
}

// MARK: - Faces

/// A short value as a button's face, such as "16:9" or "HEIF", kept narrow enough for the dark circle Solid buttons
/// puts behind it.
private struct ItemText: View {
    let text: String
    let size: CGFloat

    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size * Theme.labelScale, weight: .medium).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 4)
    }
}

/// The first of a button's symbol names this iOS has, looked up once per kind of button instead of on every redraw.
@MainActor
private enum ItemSymbol {
    private static var names: [TopBarItem: String] = [:]

    static func name(_ item: TopBarItem) -> String {
        if let name = names[item] { return name }
        let candidates = item.symbolNames
        let name = candidates.first(where: { UIImage(systemName: $0) != nil }) ?? candidates.last ?? "circle"
        names[item] = name
        return name
    }

    static func image(_ item: TopBarItem) -> Image {
        Image(systemName: name(item))
    }
}

/// A dot under a glyph that looks the same on and off, for people who turned on Differentiate Without Color: the
/// accent alone would be the only sign the setting is on.
private struct OnDot: ViewModifier {
    let isOn: Bool
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isOn && differentiateWithoutColor {
                    Circle()
                        .frame(width: 4, height: 4)
                        .offset(y: 7)
                        .accessibilityHidden(true)
                }
            }
    }
}

private extension View {
    func marksOn(_ isOn: Bool) -> some View {
        modifier(OnDot(isOn: isOn))
    }
}

/// Diagonal stripes in a rounded square, the usual zebra symbol; SF Symbols has none. The drawer's Zebras item
/// draws it.
struct ZebraGlyph: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let outline = Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 3.5)
            var stripes = Path()
            var x = -size.height
            while x < size.width {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 4.5
            }
            context.stroke(outline, with: .foreground, lineWidth: 1.5)
            context.clip(to: outline)
            context.stroke(stripes, with: .foreground, lineWidth: 1.5)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
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

// MARK: - Quick actions

/// What a tap on a quick setting does, for the drawer and the top bar alike, so a button on the bar and its item in
/// the drawer always step the same way through the same values.
@MainActor
enum QuickActions {
    // MARK: Photo shape

    /// The shapes a tap steps through and a menu lists: the simple interface's three, or every preset.
    static func aspects(advanced: Bool) -> [AspectRatio] {
        advanced ? AspectRatio.presets : CameraSettings.simpleAspects
    }

    /// Lit whenever the shape isn't the one a fresh install starts with, so a new phone's bar starts unlit.
    static func aspectIsActive(_ aspect: AspectRatio) -> Bool {
        !aspect.matches(CameraSettings.default.capture.aspect)
    }

    /// The row a menu marks. A saved ratio within half a percent of a preset reads as that preset.
    static func aspectSelection(_ aspect: AspectRatio, among presets: [AspectRatio]) -> AspectRatio {
        presets.first(where: { $0.matches(aspect) }) ?? aspect
    }

    /// Steps through the interface's shapes. A ratio entered in Settings sits after the last one, so the next tap goes
    /// to the first.
    static func stepAspect(_ model: CameraModel) {
        let presets = aspects(advanced: model.isAdvanced)
        guard !presets.isEmpty else { return }
        let current = model.settings.capture.aspect
        let index = presets.firstIndex(where: { $0.matches(current) })
        setAspect(index.map { presets[($0 + 1) % presets.count] } ?? presets[0], model)
    }

    static func setAspect(_ aspect: AspectRatio, _ model: CameraModel) {
        Haptics.tick()
        model.updateSettings { $0.capture.aspect = aspect }
    }

    // MARK: RAW

    /// Off, then what this camera can save.
    static func rawChoices(_ capabilities: CameraCapabilities) -> [RawFormat] {
        var choices: [RawFormat] = [RawFormat.none]
        if capabilities.rawSupported { choices.append(.bayer) }
        if capabilities.proRAWSupported { choices.append(.proRAW) }
        return choices
    }

    static func stepRaw(_ model: CameraModel) {
        let choices = rawChoices(model.capabilities)
        let index = choices.firstIndex(of: model.settings.capture.rawFormat)
        // Spelled out: a bare .none next to an optional reads as nil.
        let next: RawFormat = index.map { choices[($0 + 1) % choices.count] } ?? RawFormat.none
        Haptics.tap()
        model.updateSettings { $0.capture.rawFormat = next }
    }

    // MARK: Timer

    /// The self timer's delays: the simple interface's, or every preset.
    static func delays(advanced: Bool) -> [Double] {
        advanced ? CaptureSchedule.delayPresets : CameraSettings.simpleDelays
    }

    /// Video and bulb start on the press itself, so a timer would never run there.
    static func timerApplies(_ model: CameraModel) -> Bool {
        let mode = model.settings.mode
        return mode != .video && !(mode == .long && model.settings.longExposure.bulb)
    }

    /// Where a tap on a timer goes next.
    enum TimerStep {
        case schedule(CaptureSchedule)
        /// The timer sheet, for an intervalometer or a delay the presets don't have.
        case sheet
    }

    /// Off, then each delay, then the timer sheet where the cycle ends there, and Off again. A burst, an
    /// intervalometer or a delay off the list steps back to Off, and so does the tap after the sheet was offered.
    static func timerStep(after schedule: CaptureSchedule, delays: [Double], endsInSheet: Bool,
                          sheetOffered: Bool) -> TimerStep {
        guard schedule.shots == 1,
              let index = delays.firstIndex(where: { abs($0 - schedule.delay) < 0.01 }) else {
            return .schedule(.off)
        }
        if index + 1 < delays.count {
            return .schedule(CaptureSchedule(delay: delays[index + 1]))
        }
        return endsInSheet && !sheetOffered ? .sheet : .schedule(.off)
    }

    static func setSchedule(_ schedule: CaptureSchedule, _ model: CameraModel) {
        Haptics.tick()
        model.updateSettings { $0.capture.schedule = schedule }
    }

    /// A menu row, worded like the other touch and hold menus ("3 s"); the drawer's value and the bar keep "3s".
    static func delayTitle(_ delay: Double) -> String {
        delay > 0 ? HoldMenuText.time(delay) : "Off"
    }

    // MARK: Lists and switches

    /// Steps a setting to the value after the current one, wrapping around. A value off the list goes to the first.
    static func cycle<Value: Equatable>(_ keyPath: WritableKeyPath<CameraSettings, Value>, through values: [Value],
                                        _ model: CameraModel) {
        guard !values.isEmpty else { return }
        let index = values.firstIndex(of: model.settings[keyPath: keyPath])
        let next = index.map { values[($0 + 1) % values.count] } ?? values[0]
        Haptics.tick()
        model.updateSettings { $0[keyPath: keyPath] = next }
    }

    /// A menu's pick.
    static func set<Value>(_ keyPath: WritableKeyPath<CameraSettings, Value>, to value: Value, _ model: CameraModel) {
        Haptics.tick()
        model.updateSettings { $0[keyPath: keyPath] = value }
    }

    static func toggle(_ keyPath: WritableKeyPath<CameraSettings, Bool>, _ model: CameraModel) {
        Haptics.tap()
        model.updateSettings { $0[keyPath: keyPath].toggle() }
    }

    static func stepHistogram(_ model: CameraModel) {
        cycle(\.display.histogram, through: HistogramStyle.allCases, model)
    }

    static func stepPeaking(_ model: CameraModel) {
        cycle(\.display.peaking, through: PeakingMode.allCases, model)
    }

    /// "Off", "MF", "On": short enough for the drawer's value line.
    static func peakingValue(_ mode: PeakingMode) -> String {
        switch mode {
        case .off: return "Off"
        case .manualFocus: return "MF"
        case .always: return "On"
        }
    }

    // MARK: Format

    static func formatChoices(_ capabilities: CameraCapabilities) -> [ProcessedFormat] {
        capabilities.heifSupported ? [.heif, .jpeg] : [.jpeg]
    }

    /// A camera without HEIF has nothing to step through, unless the setting is one it can't write.
    static func canChangeFormat(_ model: CameraModel) -> Bool {
        let choices = formatChoices(model.capabilities)
        return choices.count > 1 || !choices.contains(model.settings.capture.processedFormat)
    }

    static func stepFormat(_ model: CameraModel) {
        let choices = formatChoices(model.capabilities)
        guard !choices.isEmpty else { return }
        let index = choices.firstIndex(of: model.settings.capture.processedFormat)
        let next = index.map { choices[($0 + 1) % choices.count] } ?? choices[0]
        Haptics.tick()
        model.updateSettings { $0.capture.processedFormat = next }
    }

    /// RAW alone has no processed format, so the value names what is saved.
    static func formatValue(_ format: ProcessedFormat) -> String {
        format == ProcessedFormat.none ? "RAW" : format.title
    }

    // MARK: Resolution

    /// Sizes this camera can shoot. A size counts when one of the lens's photo dimensions is within 20% of it,
    /// because sensors sold as 48 MP deliver 48.8 MP and 12 MP ones 12.2 MP.
    static func resolutionChoices(_ capabilities: CameraCapabilities) -> [PhotoResolution] {
        var choices: [PhotoResolution] = [.automatic]
        for option in [PhotoResolution.mp12, .mp24, .mp48] {
            guard let target = option.targetMegapixels, target > 0 else { continue }
            let wanted = Double(target)
            let available = capabilities.photoDimensions.contains { size in
                let megapixels = Double(size.width) * Double(size.height) / 1_000_000
                return abs(megapixels - wanted) / wanted < 0.2
            }
            if available { choices.append(option) }
        }
        return choices
    }

    /// Single photos only: stacks are merged from video frames, so a MANUAL shutter past the hardware limit ignores
    /// the size too.
    static func resolutionApplies(_ model: CameraModel) -> Bool {
        let mode = model.settings.mode
        return mode == .photo || (mode == .manual && !model.shutterIsStacked)
    }

    static func stepResolution(_ model: CameraModel) {
        let choices = resolutionChoices(model.capabilities)
        let index = choices.firstIndex(of: model.settings.capture.resolution)
        let next = index.map { choices[($0 + 1) % choices.count] } ?? .automatic
        Haptics.tick()
        model.updateSettings { $0.capture.resolution = next }
    }

    // MARK: Processing

    /// Levels up to what the camera reports; asking for more would only be clamped by the model.
    static func processingChoices(maximum: ProcessingLevel) -> [ProcessingLevel] {
        let order: [ProcessingLevel] = [.minimal, .balanced, .maximum]
        guard let limit = order.firstIndex(of: maximum) else { return order }
        return Array(order[...limit])
    }

    static func stepProcessing(_ model: CameraModel) {
        let choices = processingChoices(maximum: model.capabilities.maxProcessing)
        let index = choices.firstIndex(of: model.settings.capture.processing)
        let next = index.map { choices[($0 + 1) % choices.count] } ?? .balanced
        Haptics.tick()
        model.updateSettings { $0.capture.processing = next }
    }

    // MARK: Exposure lock

    /// When the model honours AE lock: only while auto exposure owns every value. LONG's Blur and Trails meter
    /// each frame, so the lock holds there too as long as ISO and aperture are auto.
    static func aeLockApplies(_ model: CameraModel) -> Bool {
        switch model.settings.mode {
        case .photo, .night:
            return true
        case .manual, .video:
            return !model.isManualExposure
        case .long:
            // A fixed Blur or Trails frame shutter leaves no auto exposure to freeze, as in the strip's AE-L chip.
            return model.settings.longExposure.blend != .additive && model.settings.longExposure.frameSeconds == nil
                && model.isISOAuto && model.isApertureAuto
        }
    }

    /// A change of exposure in the middle of a shot or a stack would end up in the picture.
    static func exposureIsBusy(_ activity: CaptureActivity) -> Bool {
        switch activity {
        case .capturing, .stacking, .saving: return true
        case .idle, .countdown, .recording: return false
        }
    }
}
