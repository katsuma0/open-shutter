import SwiftUI
import CameraCore

/// The Night page of the full list. Night mode holds the night shot and the long exposure scenes, so the settings of
/// both are here, and with them the battery saver, which only acts during those shots.
struct NightSettingsView: View {
    let model: CameraModel

    var body: some View {
        Form {
            NightShotSection(model: model)
            LongExposureSection(model: model)
            BatterySaverSection(model: model)
        }
        .navigationTitle("Night")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Night shot

private struct NightShotSection: View {
    let model: CameraModel

    private static let maxISOChoices: [Double] = [800, 1600, 3200, 6400, 12800]

    var body: some View {
        let night = model.settings.night
        let caps = model.capabilities

        Section {
            // Chosen only here. The top bar's button in NIGHT shows or hides the steady sign instead.
            SettingsPicker("Tripod or handheld", selection: model.settingBinding(\.night.stability),
                         options: NightStabilityChoice.allCases, label: \.title)
            // A tripod plan never lines frames up, so the switch only shows where it acts.
            if night.stability != .tripod {
                Toggle("Align frames", isOn: model.settingBinding(\.night.alignFrames))
            }
            SettingsPicker("Maximum ISO", selection: model.settingBinding(\.night.maxISO),
                         options: pickerNumbers(Self.maxISOChoices, current: night.maxISO), label: ISOScale.label)
        } header: {
            Text("Night shot")
        } footer: {
            SettingsFooter(Self.notes(night: night, caps: caps))
        }
    }

    private static func notes(night: NightSettings, caps: CameraCapabilities) -> [String?] {
        let deviceMax = caps.exposure.iso.upperBound
        return [
            // Tripod is where a night shot starts, and its long frames blur in a hand.
            night.stability == .tripod ? "Choose Handheld or Auto when you hold the phone." : nil,
            night.maxISO > deviceMax ? "This camera goes up to \(ISOScale.label(deviceMax))." : nil,
        ]
    }
}

// MARK: - Long exposure

private struct LongExposureSection: View {
    let model: CameraModel

    private static let bulbLimits: [Double] = [60, 120, 300, 600, 900, 1800]

    var body: some View {
        let long = model.settings.longExposure

        Section {
            SettingsDetailPicker("Blend", selection: Binding(get: { model.settings.longExposure.blend },
                                                             set: { model.setLongExposureBlend($0) }),
                                 options: StackBlend.allCases, label: \.title, detail: long.blend.detail)
            Toggle("Align frames", isOn: model.settingBinding(\.longExposure.align))
            SettingsPicker("Bulb limit", selection: model.settingBinding(\.longExposure.maxBulbSeconds),
                         options: pickerNumbers(Self.bulbLimits, current: long.maxBulbSeconds), label: Self.durationLabel)
        } header: {
            Text("Long exposure")
        } footer: {
            // A blend or alignment that isn't the scene's own makes the scene Custom (CameraModel.commit), from here
            // as from the camera, and the scene menu names Custom Manual night.
            if long.scene != .custom {
                Text("Changing Blend or Align frames turns \(NightText.title(long.scene)) into \(NightText.manualNightTitle).")
            }
        }
    }

    private static func durationLabel(_ seconds: Double) -> String {
        // A saved value comes back from disk as any Double, and Int(_:) traps on one out of range.
        guard seconds.isFinite, seconds > 0, seconds < 360_000 else { return "Custom" }
        let whole = Int(seconds.rounded())
        return whole >= 60 && whole % 60 == 0 ? "\(whole / 60) min" : Formatting.compactDuration(seconds)
    }
}

// MARK: - Battery saver

/// Battery saver: a section of its own in the short list, headed Night there, and the last section of the Night
/// page, whose title says the same.
struct BatterySaverSection: View {
    let model: CameraModel
    /// The short list names the subject; the Night page needs no header for it.
    var header: String? = nil

    var body: some View {
        Section {
            Toggle("Battery saver", isOn: model.settingBinding(\.display.dimDuringLongShots))
        } header: {
            if let header {
                Text(header)
            }
        } footer: {
            Text("Darkens the screen during shots of 10 seconds or more.")
        }
    }
}
