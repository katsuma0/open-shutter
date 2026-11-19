import SwiftUI
import CameraCore

/// NIGHT's row above the chips and the lens buttons: what the shot will take, on a dark pill that reads over any
/// picture, and for the long exposure scenes the bulb switch. NIGHT holds two kinds of shot. The night shot averages
/// its frames for a clean picture in low light. The long exposure scenes, and Custom, combine them the scene's way:
/// added like one long shutter, averaged into blur, or the brightest kept for trails.
///
/// The scene is chosen from the button left of the shutter (NightSceneMenuItems). How long a shot runs is the row of
/// durations above the pill, or for any other length the moon chip's, beside the lens buttons (LensRowShutterChip). Whether the shot needs a tripod, and whether the phone is
/// steady, is the status pill's over the picture (SteadyBanner).
struct NightModePanel: View {
    let model: CameraModel
    /// The row of durations. Folded away while a dial is open, which sets the same thing finer.
    var showsDurations = true

    var body: some View {
        let isLong = model.settings.mode == .long
        let long = model.settings.longExposure
        let locked = model.activity.isBusy
        VStack(spacing: 6) {
            // The lengths people reach for most, one tap each. Bulb's length is the hold, so it has none.
            if showsDurations, !(isLong && long.bulb) {
                DurationPresets(model: model, isLong: isLong)
                    .transition(.opacity)
            }
            HStack(spacing: 8) {
                // Centred in the room the bulb switch leaves. The switch is pinned to the edge, so it keeps its
                // place under the finger when a tap on it changes the pill's text.
                NightPlanPill(model: model, isLong: isLong)
                    .frame(maxWidth: .infinity)
                if isLong {
                    BulbButton(model: model, isOn: long.bulb)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(locked)
        .opacity(locked ? 0.45 : 1)
        .animation(Theme.snappy, value: isLong)
        .animation(Theme.snappy, value: locked)
    }
}

// MARK: - Scene

/// The rows of the scene menu, for the button left of the shutter: the night shot first, then Manual night (the
/// Custom scene, with every control by hand), then the long exposure scenes. Picking a long exposure scene loads its blend, time, bulb, frame and alignment; changing any
/// of those but the time by hand makes the scene Custom.
struct NightSceneMenuItems: View {
    let model: CameraModel
    /// nil is the night shot.
    let scene: LongExposureScene?

    var body: some View {
        Section {
            HoldMenuChoice(NightText.nightTitle, icon: Image(systemName: NightText.nightSymbol), isOn: scene == nil) {
                model.selectNightScene(nil)
            }
        }
        Section {
            HoldMenuChoice(NightText.manualNightTitle, icon: SceneSymbols.image(for: .custom), isOn: scene == .custom) {
                model.selectNightScene(.custom)
            }
        }
        Section {
            ForEach(LongExposureScene.presets) { preset in
                HoldMenuChoice(preset.title, icon: SceneSymbols.image(for: preset), isOn: preset == scene) {
                    model.selectNightScene(preset)
                }
            }
        }
    }
}

/// Each scene's symbol, found once. Finding it asks the system for every candidate name, which is too much for a
/// body that runs again with every settings change.
@MainActor
enum SceneSymbols {
    private static let images: [LongExposureScene: Image] = Dictionary(
        uniqueKeysWithValues: LongExposureScene.allCases.map { ($0, Image(firstAvailableSystemName: $0.symbolNames)) }
    )

    static func image(for scene: LongExposureScene) -> Image {
        images[scene] ?? Image(systemName: "circle")
    }
}

// MARK: - Bulb and the frame shutter

private struct BulbButton: View {
    let model: CameraModel
    let isOn: Bool

    var body: some View {
        Button {
            Haptics.tap()
            let turningOn = !isOn
            // The duration dial means nothing once the hold sets the length.
            if turningOn, model.activeDial == .shutter {
                withAnimation(Theme.spring) { model.activeDial = nil }
            }
            model.setBulb(turningOn)
        } label: {
            Text("BULB")
                .tracking(0.6)
        }
        .buttonStyle(NightChipStyle(isActive: isOn))
        .accessibilityLabel(Text("Bulb"))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
        .accessibilityHint(Text("Exposes for as long as you hold the shutter. Or tap once to start and again to stop."))
    }
}

/// The menu for the shutter of each Blur or Trails frame, around whatever shows it. Auto exposure stays under its
/// own limit and drifts with the light, so star trails need a fixed one: every frame equally bright, and up to the
/// longest shutter the sensor has.
private struct FrameMenu<Face: View>: View {
    let model: CameraModel
    let frameSeconds: Double?
    let range: ClosedRange<Double>
    // Built once in init: a stored closure never compares equal, and the pill that builds this follows the 10 Hz
    // readings, so the menu would be rebuilt with every one of them.
    @ViewBuilder let face: Face

    var body: some View {
        Menu {
            FrameMenuRows(model: model, frameSeconds: frameSeconds, range: range)
        } label: {
            face
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

/// The rows of the frame shutter menu. Their own view, so a change of the pill's text leaves them as they are.
private struct FrameMenuRows: View {
    let model: CameraModel
    let frameSeconds: Double?
    let range: ClosedRange<Double>

    var body: some View {
        let ascending = ShutterSpeed.scale(minSeconds: range.lowerBound, maxSeconds: range.upperBound, step: .full)
        // Longest first, right under Auto: the long end is what a fixed frame is for.
        let speeds = Array(ascending.reversed())
        // The model clamps to the lens's range, which can leave the value just off a stop; the nearest one is checked.
        let clamped = frameSeconds.map { min(max($0, range.lowerBound), range.upperBound) }
        let checked = clamped.map { ShutterSpeed(seconds: $0).nearest(in: speeds).seconds }
        // The checked stop can stand for a scene's frame that sits between stops. Picking it again keeps the
        // scene instead of turning it into Custom at that stop.
        Picker("Frame shutter", selection: Binding(get: { checked }, set: { if $0 != checked { select($0) } })) {
            Text("Auto").tag(Double?.none)
            ForEach(speeds, id: \.self) { speed in
                Text(speed.label).tag(Double?.some(speed.seconds))
            }
        }
        .pickerStyle(.inline)
    }

    private func select(_ seconds: Double?) {
        Haptics.tick()
        model.setLongExposureFrameSeconds(seconds)
    }
}

// MARK: - Plan

/// What the shot will take: "12 frames × 1/4s · ISO 640". In a Blur or Trails scene the pill is also the menu for the
/// shutter of each frame, the middle value on it, and wears a chevron to say so. The night shot and Real set their
/// frames themselves.
private struct NightPlanPill: View {
    let model: CameraModel
    let isLong: Bool

    var body: some View {
        let long = model.settings.longExposure
        let plan = isLong ? model.longPlan : model.nightPlan
        // Bulb has no length to plan, so the line gives the limit from Settings, where the exposure stops by itself.
        let bulbLimit = isLong && long.bulb ? long.maxBulbSeconds : nil
        let text = NightText.plan(plan, bulbLimit: bulbLimit)
        let spoken = NightText.plan(plan, bulbLimit: bulbLimit, spoken: true)
        // The frame shutter is a shutter speed, which only the phones with manual shutter speeds offer.
        if isLong, long.blend != .additive, model.allowsManualShutter {
            // The frame the shot will use, which for a scene that closes the iris is longer than its own.
            let frame = model.longFrameSeconds
            FrameMenu(model: model, frameSeconds: frame, range: model.capabilities.exposure.seconds) {
                PlanPillFace(text: text, opensMenu: true)
            }
            .accessibilityLabel(Text("Plan"))
            .accessibilityValue(Text(spoken + (frame == nil ? ", frame shutter auto" : ", frame shutter set")))
            .accessibilityHint(Text("Shows the shutter choices for each frame. Auto lets the camera pick it."))
        } else {
            PlanPillFace(text: text, opensMenu: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Plan"))
                .accessibilityValue(Text(spoken))
        }
    }
}

/// The pill itself. Its backing is its own and dark, not glass: glass takes its tone from the scene, and this is a
/// line of numbers to read over a lit street as well as a black sky.
private struct PlanPillFace: View {
    let text: String
    let opensMenu: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        // The steady pill's backing: white on 60 percent black over a white sky is about 5.7:1.
        let backing = contrast == .increased || reduceTransparency || AppearanceStore.shared.solidControls ? 0.85 : 0.6
        HStack(spacing: 6) {
            Text(text)
                // Rolls only inside an explicit animation: the plan follows the 10 Hz light readings.
                .contentTransition(.numericText())
            if opensMenu {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.6)
            }
        }
        .font(.system(size: 14 * Theme.labelScale, weight: .medium).monospacedDigit())
        .foregroundStyle(Theme.primaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background {
            Capsule()
                .fill(Color.black.opacity(backing))
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Looks and words

/// A glass capsule in a 44 pt touch area, yellow while its setting is in force.
private struct NightChipStyle: ButtonStyle {
    var isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.chipFont)
            .foregroundStyle(isActive ? Theme.accent : Theme.primaryText)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 30)
            .cameraGlass(in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

enum NightText {
    /// The night shot's name in the scene menu.
    static let nightTitle = "Night"
    /// The Custom scene's name in NIGHT: a long exposure with the chips of MANUAL and NIGHT's own controls.
    static let manualNightTitle = "Manual night"

    /// The scene's name in a word, under the button left of the shutter. nil is the night shot.
    static func shortName(_ scene: LongExposureScene?) -> String {
        guard let scene else { return nightTitle }
        switch scene {
        case .lightTrails: return "Trails"
        case .northernLights: return "Aurora"
        case .lightPainting: return "Painting"
        case .starTrails: return "Star trails"
        case .custom: return "Manual"
        default: return scene.title
        }
    }

    /// The scene's full name, with Custom as NIGHT calls it.
    static func title(_ scene: LongExposureScene?) -> String {
        guard let scene else { return nightTitle }
        return scene == .custom ? manualNightTitle : scene.title
    }
    /// The night shot's symbol, in the menu and on the button that opens it.
    static let nightSymbol = "moon.fill"
    /// What the night shot does, for VoiceOver.
    static let nightDetail = "Averages frames for a clean, bright picture."

    /// "12 frames × 1/4s · ISO 640", or with a bulb limit "Bulb: 1s frames · ISO 100 · max 30m". `spoken` writes the
    /// limit out for VoiceOver, which would read "30m" as thirty meters.
    static func plan(_ plan: StackPlan, bulbLimit: Double?, spoken: Bool = false) -> String {
        let speed = ShutterSpeed(seconds: plan.frameSeconds)
        let shutter = speed.isFraction ? speed.label + "s" : speed.label
        let iso = ISOScale.label(plan.iso)
        if let bulbLimit {
            let limit = spoken ? HoldMenuText.spokenTime(bulbLimit) : Formatting.compactDuration(bulbLimit)
            return "Bulb: \(shutter) frames \u{00B7} \(iso) \u{00B7} max \(limit)"
        }
        let frames = plan.frameCount == 1 ? "1 frame" : "\(plan.frameCount) frames"
        return "\(frames) \u{00D7} \(shutter) \u{00B7} \(iso)"
    }
}

// MARK: - Durations

/// One tap to the lengths people use most for a night or long exposure. The moon chip and its dial set any other.
private struct DurationPresets: View {
    let model: CameraModel
    let isLong: Bool

    private static let night: [Double] = [3, 10, 30, 60, 300, 1800]
    private static let long: [Double] = [2, 10, 30, 60, 300, 1800]

    var body: some View {
        let night = model.settings.night.seconds
        let long = model.settings.longExposure.seconds
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !isLong {
                    preset("Auto", spoken: "Automatic", isOn: night == nil) { model.setNightSeconds(nil) }
                }
                ForEach(isLong ? Self.long : Self.night, id: \.self) { seconds in
                    let isOn = isLong ? abs(long - seconds) < 0.01 : night.map { abs($0 - seconds) < 0.01 } ?? false
                    preset(Formatting.compactDuration(seconds), spoken: HoldMenuText.spokenTime(seconds), isOn: isOn) {
                        if isLong { model.setLongExposureSeconds(seconds) } else { model.setNightSeconds(seconds) }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Duration"))
    }

    private func preset(_ title: String, spoken: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard !isOn else { return }
            Haptics.tick()
            withAnimation(Theme.snappy) { action() }
        } label: {
            Text(title)
        }
        .buttonStyle(NightChipStyle(isActive: isOn))
        .accessibilityLabel(Text(spoken))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
