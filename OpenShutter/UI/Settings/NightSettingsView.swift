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
    /// Night shots rarely want more than a few stops either way; the dial on the camera screen covers the rest.
    private static let biasLimit = 3.0

    var body: some View {
        let night = model.settings.night
        let caps = model.capabilities
        let biasRange = Self.biasRange(caps.biasRange, current: night.biasEV)

        Section {
            SettingsPicker("Stability", selection: model.settingBinding(\.night.stability),
                         options: NightStabilityChoice.allCases, label: \.title)
            Toggle("Align frames", isOn: model.settingBinding(\.night.alignFrames))
                // A tripod plan never lines frames up, so the switch has nothing to act on there.
                .disabled(night.stability == .tripod)
            SettingsPicker("Maximum ISO", selection: model.settingBinding(\.night.maxISO),
                         options: pickerNumbers(Self.maxISOChoices, current: night.maxISO), label: ISOScale.label)
            Stepper(value: biasBinding(range: biasRange), in: biasRange, step: 1.0 / 3.0) {
                HStack {
                    Text("Exposure")
                    Spacer()
                    Text(EVFormat.label(night.biasEV) + " EV")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(biasRange.upperBound - biasRange.lowerBound < 1.0 / 3.0)
        } header: {
            Text("Night shot")
        } footer: {
            SettingsFooter(Self.notes(night: night, caps: caps))
        }
    }

    /// Snapped to thirds so repeated steps can't drift into values like 0.9999.
    private func biasBinding(range: ClosedRange<Double>) -> Binding<Double> {
        Binding(
            get: { model.settings.night.biasEV },
            set: { newValue in
                let snapped = min(max(EVFormat.snap(newValue, step: .third), range.lowerBound), range.upperBound)
                model.updateSettings { $0.night.biasEV = snapped }
            }
        )
    }

    /// The device's bias range, capped at three stops, widened to keep a value set from the camera screen reachable.
    private static func biasRange(_ device: ClosedRange<Double>, current: Double) -> ClosedRange<Double> {
        let reach = min(biasLimit, max(0, -device.lowerBound), max(0, device.upperBound))
        let thirds = (reach * 3).rounded(.down) / 3
        let safeCurrent = current.isFinite ? current : 0
        return min(-thirds, safeCurrent)...max(thirds, safeCurrent)
    }

    private static func notes(night: NightSettings, caps: CameraCapabilities) -> [String?] {
        var notes: [String?] = [
            "Stability starts at Tripod, which uses the longest frames the camera allows. Handheld keeps the frames short and lines them up. Auto follows the motion sensor.",
            // Night has no histogram, and its top bar button sits in that slot.
            "In Night, the top bar has Stability too, in the histogram's place.",
            night.stability == .tripod
                ? "On Tripod the frames are not lined up, so Align frames has nothing to do. A night shot keeps each frame at or below the maximum ISO."
                : "Align frames lines up the frames to undo small hand movements. A night shot keeps each frame at or below the maximum ISO.",
        ]
        let deviceMax = caps.exposure.iso.upperBound
        if night.maxISO > deviceMax {
            notes.append("The current camera tops out at \(ISOScale.label(deviceMax)).")
        }
        return notes
    }
}

// MARK: - Long exposure

private struct LongExposureSection: View {
    let model: CameraModel

    private static let bulbLimits: [Double] = [60, 120, 300, 600, 900, 1800]

    var body: some View {
        let long = model.settings.longExposure

        Section {
            SettingsPicker("Blend", selection: Binding(get: { model.settings.longExposure.blend },
                                                       set: { model.setLongExposureBlend($0) }),
                         options: StackBlend.allCases, label: \.title)
            Toggle("Align frames", isOn: model.settingBinding(\.longExposure.align))
            SettingsPicker("Bulb limit", selection: model.settingBinding(\.longExposure.maxBulbSeconds),
                         options: pickerNumbers(Self.bulbLimits, current: long.maxBulbSeconds), label: Self.durationLabel)
        } header: {
            Text("Long exposure")
        } footer: {
            SettingsFooter([
                "\(long.blend.title): \(long.blend.detail)",
                "Align frames corrects small camera movement between frames. A bulb exposure stops on its own at the bulb limit.",
            ])
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

/// Battery saver, a section of its own in the short list and the last one of the Night page in the full list. The
/// steady status on the camera tells when it applies.
struct BatterySaverSection: View {
    let model: CameraModel

    var body: some View {
        Section {
            Toggle("Battery saver", isOn: model.settingBinding(\.display.dimDuringLongShots))
        } footer: {
            Text("Darkens the screen during night and long exposure shots of 10 seconds or more, once the phone is steady. Touch the screen to see the shot. It lights up again when the shot ends.")
        }
    }
}
