import SwiftUI
import CameraCore

/// NIGHT's panel, above the chips and the lens buttons. NIGHT holds two kinds of shot under one scene menu. The night
/// shot lines up and averages its frames for a clean picture in low light, and plans for a hand or a tripod. The long
/// exposure scenes, and Custom, choose how the frames combine instead (Real, Blur or Trails), with bulb and a frame
/// shutter. The row of four says which is on, and a tap there changes it without the menu.
///
/// How long a shot runs is the moon chip's, beside the lens buttons (LensRowShutterChip). Whether the shot needs a
/// tripod, and whether the phone is steady, is the status pill's over the picture (SteadyBanner).
struct NightModePanel: View {
    @Bindable var model: CameraModel

    var body: some View {
        let isLong = model.settings.mode == .long
        let long = model.settings.longExposure
        let locked = model.activity.isBusy
        VStack(alignment: .leading, spacing: 4) {
            // The scene leads, since it sets the rest. Its name and the row of four don't fit one line on a 375 pt
            // screen, so that row has the line below.
            HStack(spacing: 8) {
                NightSceneMenu(model: model, scene: isLong ? long.scene : nil)
                Spacer(minLength: 4)
                if isLong {
                    BulbButton(model: model, isOn: long.bulb)
                } else {
                    StabilityPicker(model: model)
                }
            }
            HStack(spacing: 8) {
                NightBlendPicker(model: model, selection: isLong ? long.blend : nil)
                // Blur and Trails pick a frame shutter. The night shot and Real set their frames themselves, so they
                // have the room for a line on what they do.
                if isLong, long.blend != .additive {
                    Spacer(minLength: 4)
                    // The frame the shot will use, which for a scene that closes the iris is longer than its own.
                    FrameMenu(model: model, frameSeconds: model.longFrameSeconds,
                              range: model.capabilities.exposure.seconds)
                        .transition(.opacity)
                } else {
                    Text(isLong ? long.blend.detail : NightText.nightDetail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .overPicture()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            NightPlanLine(model: model, isLong: isLong)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(locked)
        .opacity(locked ? 0.45 : 1)
        .animation(Theme.snappy, value: long.blend)
        .animation(Theme.snappy, value: isLong)
        .animation(Theme.snappy, value: locked)
    }
}

// MARK: - Scene

/// The scene as a menu chip: its symbol and name, yellow while a scene's own setup is in force. The night shot comes
/// first. Picking a long exposure scene loads its blend, time and frame into the controls beside it; changing one of
/// those by hand shows Custom here.
private struct NightSceneMenu: View {
    let model: CameraModel
    /// nil is the night shot.
    let scene: LongExposureScene?

    var body: some View {
        Menu {
            Section {
                HoldMenuChoice(NightText.nightTitle, icon: Image(systemName: "moon.fill"), isOn: scene == nil) {
                    model.selectNightScene(nil)
                }
            }
            Section {
                ForEach(LongExposureScene.presets) { preset in
                    HoldMenuChoice(preset.title, icon: SceneSymbols.image(for: preset), isOn: preset == scene) {
                        model.selectNightScene(preset)
                    }
                }
            }
            Section {
                HoldMenuChoice(LongExposureScene.custom.title, icon: SceneSymbols.image(for: .custom), isOn: scene == .custom) {
                    model.selectNightScene(.custom)
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let scene {
                    SceneSymbols.image(for: scene)
                } else {
                    Image(systemName: "moon.fill")
                }
                Text(scene?.title ?? NightText.nightTitle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
            .font(Theme.chipFont)
            .foregroundStyle(scene == .custom ? Theme.primaryText : Theme.accent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 30)
            .cameraGlass(in: Capsule())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        // In the picker's order whichever way the menu opens: the night shot first, Custom last.
        .menuOrder(.fixed)
        .animation(Theme.snappy, value: scene)
        .accessibilityLabel(Text("Scene"))
        .accessibilityValue(Text(scene?.title ?? NightText.nightTitle))
        .accessibilityHint(Text(scene?.tip ?? NightText.nightDetail))
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

// MARK: - How the frames combine

/// Night, Real, Blur, Trails: the night shot's own way of combining frames, then the three a long exposure chooses
/// from. Picking one of the three from the night shot starts a Custom long exposure with it.
private struct NightBlendPicker: View {
    let model: CameraModel
    /// nil is the night shot.
    let selection: StackBlend?
    @Namespace private var selectionSpace

    var body: some View {
        HStack(spacing: 0) {
            segment(NightText.nightTitle, detail: NightText.nightDetail, isSelected: selection == nil) {
                model.selectNightScene(nil)
            }
            ForEach(StackBlend.allCases) { blend in
                segment(blend.title, detail: blend.detail, isSelected: blend == selection) {
                    model.selectNightBlend(blend)
                }
            }
        }
        .padding(.horizontal, 3)
        .background {
            Capsule()
                .fill(Color.clear)
                .frame(height: 34)
                .cameraGlass(in: Capsule())
        }
    }

    private func segment(_ title: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard !isSelected else { return }
            Haptics.tick()
            withAnimation(Theme.snappy) { action() }
        } label: {
            Text(title)
                .font(Theme.chipFont)
                .foregroundStyle(isSelected ? Theme.accent : Theme.primaryText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.primaryText.opacity(0.16))
                            .matchedGeometryEffect(id: "selection", in: selectionSpace)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(detail))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

/// Shutter for each Blur or Trails frame. Auto exposure stays under its own limit and drifts with the light, so star
/// trails need a fixed one: every frame equally bright, and up to the longest shutter the sensor has.
private struct FrameMenu: View {
    let model: CameraModel
    let frameSeconds: Double?
    let range: ClosedRange<Double>

    var body: some View {
        let ascending = ShutterSpeed.scale(minSeconds: range.lowerBound, maxSeconds: range.upperBound, step: .full)
        // Longest first, right under Auto: the long end is what a fixed frame is for.
        let speeds = Array(ascending.reversed())
        // The model clamps to the lens's range, which can leave the value just off a stop; the nearest one is checked.
        // The request and the plan clamp the frame to this lens's range, so the label does too.
        let clamped = frameSeconds.map { min(max($0, range.lowerBound), range.upperBound) }
        let checked = clamped.map { ShutterSpeed(seconds: $0).nearest(in: speeds).seconds }
        let fixed = clamped.map { ShutterSpeed(seconds: $0) }
        let text = fixed?.label ?? "Auto"
        Menu {
            // The checked stop can stand for a scene's frame that sits between stops. Picking it again keeps the
            // scene instead of turning it into Custom at that stop.
            Picker("Frame shutter", selection: Binding(get: { checked }, set: { if $0 != checked { select($0) } })) {
                Text("Auto").tag(Double?.none)
                ForEach(speeds, id: \.self) { speed in
                    Text(speed.label).tag(Double?.some(speed.seconds))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text("Frame")
                    .opacity(0.8)
                Text(text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
            .font(Theme.chipFont)
            .foregroundStyle(fixed == nil ? Theme.primaryText : Theme.accent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 30)
            .cameraGlass(in: Capsule())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .animation(Theme.snappy, value: text)
        .accessibilityLabel(Text("Frame shutter"))
        .accessibilityValue(Text(fixed.map { $0.isFraction ? $0.label + " of a second" : $0.label } ?? "Auto"))
        .accessibilityHint(Text("The shutter for each frame. Auto lets the camera pick it."))
    }

    private func select(_ seconds: Double?) {
        Haptics.tick()
        model.setLongExposureFrameSeconds(seconds)
    }
}

// MARK: - Hand or tripod

/// What the night shot plans for: a hand, a tripod, or whichever the motion sensor sees.
private struct StabilityPicker: View {
    let model: CameraModel
    @Namespace private var selectionSpace

    var body: some View {
        let current = model.settings.night.stability
        HStack(spacing: 0) {
            ForEach(NightStabilityChoice.allCases) { choice in
                Button {
                    guard choice != current else { return }
                    Haptics.tick()
                    withAnimation(Theme.snappy) {
                        model.setNightStability(choice)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if choice == .automatic {
                            SteadyIndicator(model: model)
                        }
                        Text(choice.title)
                    }
                    .font(Theme.chipFont)
                    .foregroundStyle(choice == current ? Theme.accent : Theme.primaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background {
                        if choice == current {
                            Capsule()
                                .fill(Theme.primaryText.opacity(0.16))
                                .matchedGeometryEffect(id: "selection", in: selectionSpace)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choice == current ? .isSelected : [])
            }
        }
        .padding(.horizontal, 3)
        .background {
            Capsule()
                .fill(Color.clear)
                .frame(height: 34)
                .cameraGlass(in: Capsule())
        }
    }
}

/// What automatic stability sees right now: a tripod when the phone has been still, a hand otherwise. Without a
/// motion reading (the Simulator, or the first moment) Auto plans for a hand, and the label says only that.
private struct SteadyIndicator: View {
    let model: CameraModel

    var body: some View {
        let steady = model.motion.isSteady
        let label = steady ? "Phone is steady" : (model.motion.isAvailable ? "Phone is moving" : "Plans for a handheld phone")
        ZStack {
            if steady {
                TripodGlyph()
                    .frame(width: 10, height: 11)
                    .foregroundStyle(Theme.accent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 12, height: 12)
        .animation(Theme.snappy, value: steady)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Plan

/// What the shot will take. Whether it needs a tripod is the pill's over the picture, which follows the motion sensor.
private struct NightPlanLine: View {
    let model: CameraModel
    let isLong: Bool

    var body: some View {
        let text = isLong
            ? NightText.plan(model.longPlan, bulb: model.settings.longExposure.bulb)
            : NightText.plan(model.nightPlan, bulb: false)
        Text(text)
            .font(Theme.readoutFont)
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .overPicture()
            // Rolls only inside an explicit animation: the plan follows the 10 Hz light readings.
            .contentTransition(.numericText())
            .accessibilityLabel(Text("Plan: " + text))
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

private enum NightText {
    /// The night shot's name in the scene menu and the row of four.
    static let nightTitle = "Night"
    static let nightDetail = "Lines up and averages frames. Bright and clean in low light."

    /// "12 frames × 1/4s · ISO 640", or for bulb "Bulb: 1s frames · ISO 100".
    static func plan(_ plan: StackPlan, bulb: Bool) -> String {
        let speed = ShutterSpeed(seconds: plan.frameSeconds)
        let shutter = speed.isFraction ? speed.label + "s" : speed.label
        let iso = ISOScale.label(plan.iso)
        if bulb {
            return "Bulb: \(shutter) frames \u{00B7} \(iso)"
        }
        let frames = plan.frameCount == 1 ? "1 frame" : "\(plan.frameCount) frames"
        return "\(frames) \u{00D7} \(shutter) \u{00B7} \(iso)"
    }
}

private extension View {
    /// The panel sits on the picture with no scrim behind it, so plain text carries a shadow of its own, like the
    /// countdown's hint, to read over a bright scene.
    func overPicture() -> some View {
        shadow(color: .black.opacity(0.6), radius: 4)
    }
}
