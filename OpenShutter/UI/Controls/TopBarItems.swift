import SwiftUI
import CameraCore

// The top bar's buttons, all but the gear, their menus, and what the quick settings panel shares with them. The
// bar redraws with every settings write, 120 a second while a dial turns, so each button is its own small view that
// reads only what it shows, and each menu sits in a layer of its own whose inputs compare equal between redraws.

// MARK: - Buttons

/// One of the top bar's fixed buttons: flash (the flashlight in VIDEO), shape, timer, format, histogram (in NIGHT the
/// steady sign's switch), AE lock or Live Photo.
struct TopBarItemButton: View {
    let model: CameraModel
    let item: TopBarItem
    let mode: CaptureMode
    /// The Timer menu's last rows open the timer sheet, which the camera screen presents.
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
        case .steadySign:
            BarSteadySign(model: model)
        case .exposureLock:
            BarExposureLock(model: model)
        default:
            // The bar draws the eight above and nothing else. CameraCore keeps the other cases for its stored layout.
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
        case .exposureLock:
            // With every value set by hand there is no auto exposure to hold, but a lock that is on can be undone.
            return (QuickActions.aeLockApplies(model) || model.aeLocked) && !QuickActions.exposureIsBusy(model.activity)
        default:
            // The shape, the histogram and the steady sign's switch work on every camera, and so does the format:
            // the app writes PNG and TIFF itself. The other cases are never asked about.
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
        Upright(model: model) {
            Image(systemName: flash.symbolName)
                // The pick animates, so the glyph changes over as iOS's own toggles do.
                .contentTransition(.symbolEffect(.replace))
        }
        .modifier(BarGlyphLook(isActive: flash == .on && !stacked, isPressed: press.isPressed))
        // The menu over the glyph is what VoiceOver reads and opens.
        .accessibilityHidden(true)
        .overlay {
            ItemMenuLayer(model: model, control: .flash, press: press, label: "Flash", value: flash.title,
                          hint: stacked ? "Stacked exposures don't use the flash." : HoldMenuText.choicesHint)
        }
        .disabled(stacked)
        .opacity(stacked ? Theme.Dim.off : 1)
    }
}

/// Off, Auto, On, the Camera app's order.
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
        withAnimation(Theme.snappy) {
            model.updateSettings { $0.capture.flash = flash }
        }
    }
}

/// The video light, where the flash button sits in the photo modes. A light is on or off, so a tap switches it, and
/// touch and hold lists its brightness: the one hold left on the bar. The front camera has none, so it dims there.
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
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(BarCircleStyle(isActive: isOn, isPressed: press.isPressed))
        .accessibilityLabel("Flashlight")
        .accessibilityValue(TorchBrightness.current(isOn: isOn, level: model.torchLevel).spokenValue)
        .accessibilityHint(HoldMenuText.hint)
        // The hold layer is hidden from VoiceOver, and the tap only turns the light on or off, so the brightness
        // steps would otherwise be out of reach.
        .accessibilityActions {
            ForEach(TorchBrightness.allCases) { choice in
                Button(choice.title) { Self.choose(choice, model: model) }
            }
        }
        .overlay {
            TorchTouchLayer(model: model, press: press)
        }
    }

    static func toggle(_ model: CameraModel) {
        // setTorch plays its own click. Animated, so the glyph changes over rather than cuts.
        withAnimation(Theme.snappy) {
            model.setTorch(!model.torchOn)
        }
    }

    /// The model clicks for both.
    static func choose(_ brightness: TorchBrightness, model: CameraModel) {
        withAnimation(Theme.snappy) {
            if let level = brightness.level {
                model.setTorchLevel(level)
            } else {
                model.setTorch(false)
            }
        }
    }
}

/// The flashlight's tap and its touch and hold menu, laid over the button. Its own view with inputs that never
/// change, so the button's redraws leave the system's menu button alone.
private struct TorchTouchLayer: View {
    let model: CameraModel
    let press: PressTracker

    var body: some View {
        MenuOnHoldLayer(press: press) {
            BarTorch.toggle(model)
        } options: {
            TorchOptions(model: model)
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

// MARK: - Live Photo

private struct BarLivePhoto: View {
    let model: CameraModel

    var body: some View {
        let capture = model.settings.capture
        // The movie goes with a HEIF or JPEG photo taken without RAW: the photo output can't record it while it
        // delivers RAW, and PNG and TIFF are made from the photo after the shot.
        let blocked = !capture.allowsLivePhoto
        let isOn = capture.livePhoto && !blocked
        Button {
            Haptics.tap()
            withAnimation(Theme.snappy) {
                model.updateSettings { $0.capture.livePhoto.toggle() }
            }
        } label: {
            Upright(model: model) {
                Image(systemName: isOn ? "livephoto" : "livephoto.slash")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(BarCircleStyle(isActive: isOn))
        .disabled(blocked)
        .opacity(blocked ? Theme.Dim.off : 1)
        .accessibilityLabel("Live Photo")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(blocked ? "Live Photos need HEIF or JPEG, and RAW off." : "")
    }
}

// MARK: - Timer

/// The self timer: a tap lists the delays and the way into the timer sheet, where the intervalometer and brackets
/// are. It also shows an intervalometer or a bracket that is set, so the bar says what the next press starts.
private struct BarTimer: View {
    let model: CameraModel
    let mode: CaptureMode
    @Binding var timerSheetRequested: Bool
    @State private var press = PressTracker()

    var body: some View {
        let preview = SchedulePreview(model: model, mode: mode)
        Upright(model: model) {
            if preview.isEmpty {
                Image(systemName: "timer")
            } else {
                ScheduleFace(preview: preview)
            }
        }
        .modifier(BarGlyphLook(isActive: !preview.isEmpty, isPressed: press.isPressed))
        .accessibilityHidden(true)
        .overlay {
            TimerMenuLayer(model: model, mode: mode, press: press, value: preview.spokenValue,
                           timerSheetRequested: $timerSheetRequested)
        }
    }
}

/// The Timer button's menu, laid over the button, and over the quick settings panel's Timer item, so the two list the
/// same rows. Its own view with inputs that compare equal between redraws, so the redraws of the control under it
/// leave the system's menu button alone. It hands the sheet's binding on to the menu's rows.
struct TimerMenuLayer: View {
    let model: CameraModel
    let mode: CaptureMode
    let press: PressTracker
    let value: String
    @Binding var timerSheetRequested: Bool

    var body: some View {
        MenuOnTapLayer(press: press, label: TopBarItem.timer.title, value: value) {
            TimerOptions(model: model, mode: mode, timerSheetRequested: $timerSheetRequested)
        }
    }
}

/// The self timer's delays, then what the timer sheet set that none of them is, checked, and the way into the sheet.
/// A checked row opens the sheet too, as that is where its values are changed.
private struct TimerOptions: View {
    let model: CameraModel
    let mode: CaptureMode
    @Binding var timerSheetRequested: Bool

    var body: some View {
        let schedule = model.settings.capture.schedule
        let delays = CaptureSchedule.delayPresets
        // A burst, an intervalometer or a delay set in the sheet is none of the plain delays.
        let preset = schedule.shots == 1 ? delays.first(where: { abs($0 - schedule.delay) < 0.01 }) : nil
        let bracket = SchedulePreview(model: model, mode: mode).bracket
        Section {
            ForEach(delays, id: \.self) { delay in
                // Worded like the other menus ("3 s"); the bar itself keeps the compact "3s". The row ticks.
                HoldMenuChoice(QuickActions.delayTitle(delay), isOn: preset == delay) {
                    model.updateSettings { $0.capture.schedule = CaptureSchedule(delay: delay) }
                }
            }
        }
        Section {
            if preset == nil {
                // "7 s" like the rows above, or "10s · 5 shots" for a burst or an intervalometer.
                HoldMenuChoice(schedule.shots == 1 ? QuickActions.delayTitle(schedule.delay) : schedule.summary,
                               isOn: true, action: showSheet)
            }
            if let bracket {
                HoldMenuChoice("Bracket", detail: bracket.summary, isOn: true, action: showSheet)
            }
            Button(action: showSheet) {
                Label("Custom\u{2026}", systemImage: "slider.horizontal.3")
            }
        }
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
        Upright(model: model) {
            ItemText(aspect.label)
        }
        .modifier(BarGlyphLook(isActive: QuickActions.aspectIsActive(aspect), isPressed: press.isPressed))
        .accessibilityHidden(true)
        .overlay {
            ItemMenuLayer(model: model, control: .aspect, press: press,
                          label: TopBarItem.aspect.title, value: aspect.label)
        }
    }
}

/// Every shape, a ratio entered in Settings as a row of its own, and the way to enter one: Custom ratio, in the
/// Camera section at the top of Settings.
private struct AspectOptions: View {
    let model: CameraModel

    var body: some View {
        let presets = AspectRatio.presets
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
        Button {
            // Settings holds the side fields; the bar shows the new ratio once it closes.
            model.isSettingsPresented = true
        } label: {
            Label("Custom\u{2026}", systemImage: "slider.horizontal.3")
        }
    }
}

// MARK: - Format

/// The photo file in one menu: the format, the RAW file beside it and the size. The face names the file type, with
/// HIGH under HEIF High and JPEG High, or the RAW file that goes with it here.
private struct BarFormat: View {
    let model: CameraModel
    @State private var press = PressTracker()

    var body: some View {
        let shown = FormatShown(model: model)
        Upright(model: model) {
            FormatFace(type: QuickActions.formatCode(shown.format), detail: shown.faceDetail)
        }
        .modifier(BarGlyphLook(isActive: shown.isActive, isPressed: press.isPressed))
        .accessibilityHidden(true)
        .overlay {
            ItemMenuLayer(model: model, control: .format, press: press,
                          label: TopBarItem.format.title, value: shown.spokenValue)
        }
    }
}

/// What the next photo saves here, as the Format button shows it.
private struct FormatShown {
    /// The format, RAW only included. HEIF stands in wherever RAW only saves no RAW file, as the photo then saves a
    /// HEIF alone: in a stack, at a zoom that leaves Bayer RAW out, and on a lens without RAW.
    let format: PhotoFormatChoice
    /// The RAW file it saves, beside the picture or alone.
    let raw: RawFormat?
    /// "48 MP", or what a lens without the set size takes in its place. nil in a stack, which is made at the video
    /// frames' size.
    let size: String?

    @MainActor
    init(model: CameraModel) {
        let raw = QuickActions.savedRaw(model)
        let shown = QuickActions.shownFormat(model)
        self.raw = raw
        // savedRaw is nil in each of those places, so one test covers them all.
        format = shown == .rawOnly && raw == nil ? .heif : shown
        let resolution = model.settings.capture.resolution
        let sizes = model.capabilities.photoDimensions
        size = QuickActions.isStacked(model)
            ? nil : QuickActions.sizeInstead(resolution, sizes: sizes) ?? resolution.shownAs.title
    }

    /// Lit when the format isn't plain HEIF, or a RAW file goes with it.
    var isActive: Bool { format != .heif || raw != nil }

    /// The face's second line: HIGH, or the RAW file, "PRO" for ProRAW. One line is all the button has room for,
    /// so HIGH wins; VoiceOver says both.
    var faceDetail: String? {
        if format.isHigh { return "HIGH" }
        if format == .rawOnly { return raw == .proRAW ? "PRO" : nil }
        switch raw {
        case .proRAW?: return "+PRO"
        case .bayer?: return "+RAW"
        default: return nil
        }
    }

    /// "HEIF High, ProRAW, 48 MP", "ProRAW only, 12 MP".
    var spokenValue: String {
        var parts: [String] = []
        if format == .rawOnly {
            parts.append(raw == .proRAW ? "ProRAW only" : format.title)
        } else {
            parts.append(format.title)
            if let raw { parts.append(raw.title) }
        }
        if let size { parts.append(size) }
        return parts.joined(separator: ", ")
    }
}

/// The Format button's face: the file type, and a small second line for HIGH or the RAW file that goes with it.
private struct FormatFace: View {
    let type: String
    let detail: String?

    var body: some View {
        let scale = Theme.labelScale
        // Both lines medium, like the rest of the bar's text: a heavier HIGH or +RAW stood out beside the thin glyphs.
        VStack(spacing: 0) {
            Text(type)
                .font(Theme.chipFont.weight(.medium))
            if let detail {
                Text(detail)
                    .font(.system(size: 8 * scale, weight: .medium))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 4)
    }
}

/// The Format button's menu: the file, the RAW file beside it, and the size. A stack is made from video frames, so
/// in NIGHT and with a stacked MANUAL shutter the RAW and size rows dim and say why.
private struct FormatOptions: View {
    let model: CameraModel

    var body: some View {
        Section("Format") {
            PhotoFormatRows(model: model)
        }
        Section("RAW") {
            RawFormatRows(model: model)
        }
        Section("Resolution") {
            PhotoResolutionRows(model: model)
        }
    }
}

/// The format rows, for the Format menu and the quick settings panel's Format item: HEIF, HEIF High, JPEG, JPEG High,
/// PNG, TIFF, and RAW only while a RAW file is on. A stack saves HEIF in place of RAW only, so there RAW only is
/// listed only while it is set, dimmed, saying so.
struct PhotoFormatRows: View {
    let model: CameraModel

    var body: some View {
        let current = PhotoFormatChoice(model.settings.capture)
        let choices = QuickActions.formatChoices(model)
        // The setting stays listed where this mode or this camera doesn't offer it, so the menu shows what is set.
        let rows = PhotoFormatChoice.allCases.filter { choices.contains($0) || $0 == current }
        ForEach(rows) { choice in
            let offered = choices.contains(choice)
            // The row ticks.
            HoldMenuChoice(choice.title, detail: offered ? nil : Self.reason(choice, model: model),
                           isOn: choice == current) {
                model.setPhotoFormat(choice)
            }
            .disabled(!offered)
        }
    }

    /// Why a format that is set isn't offered here.
    private static func reason(_ choice: PhotoFormatChoice, model: CameraModel) -> String? {
        guard choice == .rawOnly, QuickActions.isStacked(model) else { return nil }
        return QuickActions.stackedPhotos(model.settings.mode) + " are saved as HEIF."
    }
}

/// Off, RAW and ProRAW, for the Format menu and the quick settings panel's RAW item. A kind this camera lacks dims,
/// and in a stack the whole list does, as a stack saves no RAW.
struct RawFormatRows: View {
    let model: CameraModel

    var body: some View {
        let raw = model.settings.capture.rawFormat
        let stacked = QuickActions.isStacked(model)
        ForEach(RawFormat.allCases) { choice in
            HoldMenuChoice(choice.title, detail: Self.detail(choice, stacked: stacked, model: model),
                           isOn: choice == raw) {
                model.setRawFormat(choice)
            }
            .disabled(stacked || !Self.isSupported(choice, model.capabilities))
        }
    }

    private static func isSupported(_ raw: RawFormat, _ capabilities: CameraCapabilities) -> Bool {
        switch raw {
        case RawFormat.none: return true
        case .bayer: return capabilities.rawSupported
        case .proRAW: return capabilities.proRAWSupported
        }
    }

    private static func detail(_ raw: RawFormat, stacked: Bool, model: CameraModel) -> String? {
        guard raw != RawFormat.none else { return nil }
        if stacked {
            // Said once, under the first of the two.
            return raw == .bayer ? QuickActions.stackedPhotos(model.settings.mode) + " have no RAW." : nil
        }
        if !isSupported(raw, model.capabilities) { return "Not on this camera" }
        // Tested on the zoom itself: rawBlockedByZoom reads the stored setting, so it only holds once RAW is on, and
        // the row has to warn before it is picked. The backends leave RAW out past a thousandth off 1.
        if raw == .bayer, abs(model.settings.zoom - 1) > 0.001 {
            // Macro keeps the 1x button lit, so "this zoom" would point at a lens that isn't the one running.
            return model.isMacro ? "Not in macro" : "Not at this zoom"
        }
        // The names say enough; a detail is there only to say why a row is dimmed.
        return nil
    }
}

/// 12 MP and 48 MP. 48 MP is the biggest size the lens gives, up to 48 MP, so a row whose size this lens doesn't have
/// says what it takes. A stack is made from video frames at 12 MP, so the rows dim there.
private struct PhotoResolutionRows: View {
    let model: CameraModel

    var body: some View {
        let shown = model.settings.capture.resolution.shownAs
        let stacked = QuickActions.isStacked(model)
        let mode = model.settings.mode
        let sizes = model.capabilities.photoDimensions
        ForEach(PhotoResolution.offered) { resolution in
            let detail = stacked
                ? Self.stackDetail(resolution, mode: mode) : QuickActions.sizeDetail(resolution, sizes: sizes)
            HoldMenuChoice(resolution.title, detail: detail, isOn: resolution == shown) {
                model.setPhotoResolution(resolution)
            }
            .disabled(stacked)
        }
    }

    private static func stackDetail(_ resolution: PhotoResolution, mode: CaptureMode) -> String? {
        resolution == .mp48 ? QuickActions.stackedPhotos(mode) + " are 12 MP." : nil
    }
}

// MARK: - Histogram

private struct BarHistogram: View {
    let model: CameraModel
    @State private var press = PressTracker()

    var body: some View {
        let style = model.settings.display.histogram
        Upright(model: model) {
            // Outlined bars at a light weight: the filled chart was the heaviest glyph on the bar.
            Image(systemName: "chart.bar")
                .fontWeight(.light)
                .marksOn(style != .off)
        }
        .modifier(BarGlyphLook(isActive: style != .off, isPressed: press.isPressed))
        .accessibilityHidden(true)
        .overlay {
            ItemMenuLayer(model: model, control: .histogram, press: press,
                          label: TopBarItem.histogram.title, value: style.title)
        }
    }
}

/// The histogram's styles, for the Histogram menu and the quick settings panel's Histogram item.
struct HistogramOptions: View {
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

// MARK: - NIGHT's steady sign

/// NIGHT's button in the histogram's place: shows or hides the steady sign, the words over the picture that say
/// whether the phone is still enough and the line beside them. A tap switches it, as Live Photo's does. The switch
/// covers the sign of a stacked MANUAL shutter too, and Settings > Viewfinder has it as well.
private struct BarSteadySign: View {
    let model: CameraModel

    var body: some View {
        let isOn = model.settings.display.showSteadySign
        Button {
            // No toast: the sign coming or going over the picture says it.
            QuickActions.toggle(\.display.showSteadySign, model)
        } label: {
            Upright(model: model) {
                // A drawing takes no font, so it is sized here: about a symbol's height, a little narrower. The same
                // tripod on and off, lit while the sign shows, with the histogram's dot for Differentiate Without
                // Color.
                TripodGlyph(lineWidth: 1.2)
                    .frame(width: 17 * Theme.labelScale, height: 19 * Theme.labelScale)
                    .marksOn(isOn)
            }
        }
        .buttonStyle(BarCircleStyle(isActive: isOn))
        .accessibilityLabel(TopBarItem.steadySign.title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint("Shows whether the phone is still.")
    }
}

// MARK: - AE lock

/// AE lock: holds the auto exposure where it is. It was the last chip on MANUAL's strip; here it is in reach in every
/// mode that has auto exposure, and dims where every value is set by hand.
private struct BarExposureLock: View {
    let model: CameraModel

    var body: some View {
        let locked = model.aeLocked && QuickActions.aeLockApplies(model)
        Button {
            Haptics.tap()
            withAnimation(Theme.snappy) {
                model.toggleAELock()
            }
        } label: {
            Upright(model: model) {
                Image(systemName: locked ? "lock.fill" : "lock.open")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(BarCircleStyle(isActive: locked))
        .accessibilityLabel("Auto exposure lock")
        .accessibilityValue(locked ? "On" : "Off")
        .accessibilityHint("Holds the current auto exposure.")
    }
}

// MARK: - Menus

/// A button's menu, laid over the button. Its own view with inputs that compare equal between redraws, so the
/// button's redraws with every settings change leave the system's menu button alone.
private struct ItemMenuLayer: View {
    enum Control {
        case flash, aspect, format, histogram
    }

    let model: CameraModel
    let control: Control
    let press: PressTracker
    let label: String
    let value: String
    var hint: String = HoldMenuText.choicesHint

    var body: some View {
        MenuOnTapLayer(press: press, label: label, value: value, hint: hint) {
            switch control {
            case .flash: FlashOptions(model: model)
            case .aspect: AspectOptions(model: model)
            case .format: FormatOptions(model: model)
            case .histogram: HistogramOptions(model: model)
            }
        }
    }
}

// MARK: - Faces

/// A short value as a button's face, such as "16:9", kept narrow enough for the dark circle Solid buttons puts behind
/// it. The size of the bar's other text, HEIF and VIDEO's "4K · 30", so the neighbours match.
private struct ItemText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            // Medium, like the rest of the bar's text: the bare glyphs beside it are drawn in thin lines.
            .font(Theme.chipFont.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 4)
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

/// What a quick setting does, for the drawer and the top bar alike, so a button on the bar and its item in the
/// drawer always offer the same values in the same order.
@MainActor
enum QuickActions {
    // MARK: Photo shape

    /// Lit whenever the shape isn't the one a fresh install starts with, so a new phone's bar starts unlit.
    static func aspectIsActive(_ aspect: AspectRatio) -> Bool {
        !aspect.matches(CameraSettings.default.capture.aspect)
    }

    /// The row a menu marks. A saved ratio within half a percent of a preset reads as that preset.
    static func aspectSelection(_ aspect: AspectRatio, among presets: [AspectRatio]) -> AspectRatio {
        presets.first(where: { $0.matches(aspect) }) ?? aspect
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

    /// The RAW file a single photo saves, beside its picture or alone: ProRAW on a lens without it saves RAW, a lens
    /// without either saves none, and RAW, unlike ProRAW, is left out of zoomed photos. None in a stack.
    static func savedRaw(_ model: CameraModel) -> RawFormat? {
        guard !isStacked(model) else { return nil }
        let caps = model.capabilities
        let raw: RawFormat?
        switch model.settings.capture.rawFormat {
        case RawFormat.none: raw = nil
        case .bayer: raw = caps.rawSupported ? .bayer : nil
        case .proRAW: raw = caps.proRAWSupported ? .proRAW : (caps.rawSupported ? .bayer : nil)
        }
        if raw == .bayer, model.rawBlockedByZoom { return nil }
        return raw
    }

    // MARK: Timer

    /// Video and bulb start on the press itself, so a timer would never run there.
    static func timerApplies(_ model: CameraModel) -> Bool {
        let mode = model.settings.mode
        return mode != .video && !(mode == .long && model.settings.longExposure.bulb)
    }

    /// A menu row, worded like the other menus ("3 s"); the drawer's value and the bar keep "3s".
    static func delayTitle(_ delay: Double) -> String {
        delay > 0 ? HoldMenuText.time(delay) : "Off"
    }

    // MARK: Lists and switches

    /// A menu's pick.
    static func set<Value>(_ keyPath: WritableKeyPath<CameraSettings, Value>, to value: Value, _ model: CameraModel) {
        Haptics.tick()
        model.updateSettings { $0[keyPath: keyPath] = value }
    }

    /// Animated, so a glyph that shows the switch changes over as iOS's own toggles do.
    static func toggle(_ keyPath: WritableKeyPath<CameraSettings, Bool>, _ model: CameraModel) {
        Haptics.tap()
        withAnimation(Theme.snappy) {
            model.updateSettings { $0[keyPath: keyPath].toggle() }
        }
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

    /// A stack is made from video frames: NIGHT's shots, and a MANUAL shutter past the hardware limit. It saves no
    /// RAW and takes no size, and saves HEIF in place of RAW only.
    static func isStacked(_ model: CameraModel) -> Bool {
        let mode = model.settings.mode
        return mode.usesStacking || (mode == .manual && model.shutterIsStacked)
    }

    /// What the menus call a stack's photos where they say why a row is dimmed.
    static func stackedPhotos(_ mode: CaptureMode) -> String {
        mode.usesStacking ? "Night photos" : "Stacked photos"
    }

    /// The format rows on offer, in order: no HEIF rows on a camera without HEIF, and RAW only only while a RAW file
    /// is on and the photo isn't a stack.
    static func formatChoices(_ model: CameraModel) -> [PhotoFormatChoice] {
        let rawOn = model.settings.capture.rawFormat != RawFormat.none
        return PhotoFormatChoice.choices(heif: model.capabilities.heifSupported, rawOn: rawOn && !isStacked(model))
    }

    /// The format set, or HEIF in place of RAW only in a stack. The drawer shows this, and its RAW item beside it says
    /// where else no RAW file is taken. The bar's face has no such neighbour, so it puts HEIF in place of RAW only there
    /// too.
    static func shownFormat(_ model: CameraModel) -> PhotoFormatChoice {
        let choice = PhotoFormatChoice(model.settings.capture)
        return choice == .rawOnly && isStacked(model) ? .heif : choice
    }

    /// The file type as a button's face has room for it: "HEIF", "JPEG", "PNG", "TIFF", or "RAW" for RAW only.
    static func formatCode(_ choice: PhotoFormatChoice) -> String {
        choice == .rawOnly ? "RAW" : choice.format.title
    }

    // MARK: Resolution

    /// Single photos only: stacks are merged from video frames, so a MANUAL shutter past the hardware limit ignores
    /// the size too.
    static func resolutionApplies(_ model: CameraModel) -> Bool {
        let mode = model.settings.mode
        return mode == .photo || (mode == .manual && !model.shutterIsStacked)
    }

    /// The size a photo comes out at with `resolution` among a lens's `sizes`, where that isn't the size the setting
    /// shows as: "12 MP" for 48 MP on the selfie camera. nil where the lens has that size, or lists none. The photo
    /// output picks by the same rule, and the Format menu, the drawer and VoiceOver all take the size from here.
    static func sizeInstead(_ resolution: PhotoResolution, sizes: [PixelSize]) -> String? {
        guard let index = resolution.pick(amongPixelCounts: sizes.map(\.pixelCount)), sizes.indices.contains(index)
        else { return nil }
        let label = sizes[index].megapixelLabel
        return label == resolution.shownAs.title ? nil : label
    }

    /// "This camera takes 12 MP"; "up to" where 48 MP meets a lens with more than one size.
    static func sizeDetail(_ resolution: PhotoResolution, sizes: [PixelSize]) -> String? {
        guard let label = sizeInstead(resolution, sizes: sizes) else { return nil }
        let several = Set(sizes.map(\.megapixelLabel)).count > 1
        return (resolution.shownAs == .mp48 && several ? "This camera takes up to " : "This camera takes ") + label
    }

    /// The drawer's tap: 12 MP and 48 MP in turn, from the size the setting shows as.
    static func stepResolution(_ model: CameraModel) {
        let offered = PhotoResolution.offered
        guard !offered.isEmpty else { return }
        let index = offered.firstIndex(of: model.settings.capture.resolution.shownAs)
        let next = index.map { offered[($0 + 1) % offered.count] } ?? offered[0]
        Haptics.tick()
        model.setPhotoResolution(next)
    }

    // MARK: Processing

    /// Levels up to what the camera reports; asking for more would only be clamped by the model.
    static func processingChoices(maximum: ProcessingLevel) -> [ProcessingLevel] {
        let order: [ProcessingLevel] = [.minimal, .balanced, .maximum]
        guard let limit = order.firstIndex(of: maximum) else { return order }
        return Array(order[...limit])
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
