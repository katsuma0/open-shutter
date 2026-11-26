import SwiftUI
import CameraCore

/// What the volume buttons do in the camera, and how the controls feel. Linked from Controls, whether
/// Advanced settings is on or off.
struct ButtonsAndHapticsView: View {
    let model: CameraModel

    /// Which press raises which of iOS's two button events is for a phone to confirm. If a Camera Control click
    /// turns out to follow Volume up, this sentence is the one to change.
    static let cameraControlNote = "A Camera Control click does what Volume down does."

    var body: some View {
        let controls = model.settings.controls
        let hasCameraControl = model.capabilities.supportsCameraControls

        Form {
            Section {
                // One system interaction carries the volume buttons and the Camera Control click, with one switch
                // for all of them, so a single switch here covers both. The rows under it say what each press does.
                Toggle("Use hardware buttons", isOn: model.settingBinding(\.controls.volumeShutter).animation(Theme.Motion.rows))
            }

            Section {
                SettingsPicker("Volume up", selection: model.settingBinding(\.controls.volumeUpAction),
                               options: HardwareButtonAction.allCases, label: \.title)
                SettingsPicker("Volume down", selection: model.settingBinding(\.controls.volumeDownAction),
                               options: HardwareButtonAction.allCases, label: \.title)
            } header: {
                Text("Volume buttons")
                    .settingsHeader()
            } footer: {
                SettingsFooter([hasCameraControl ? Self.cameraControlNote : nil])
            }
            .disabled(!controls.volumeShutter)

            Section {
                SettingsPicker("Haptics", selection: hapticsBinding, options: HapticsChoice.allCases, label: \.title)
                Toggle("Selection ticks", isOn: model.settingBinding(\.controls.dialTicks))
                    .disabled(!controls.haptics)
                SettingsPicker("Zoom ticks", selection: model.settingBinding(\.controls.zoomTicks),
                               options: ZoomTickStyle.allCases, label: \.title)
                    .disabled(!controls.haptics)
            } header: {
                Text("Haptics")
                    .settingsHeader()
            }
        }
        .navigationTitle("Buttons and haptics")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Off is the old haptics switch and the strength is kept beside it, so a save from before means the same, and
    /// turning haptics back on brings the strength back.
    private var hapticsBinding: Binding<HapticsChoice> {
        Binding(
            get: {
                let controls = model.settings.controls
                return controls.haptics ? HapticsChoice(controls.hapticStrength) : .off
            },
            set: { choice in
                model.updateSettings { settings in
                    if let strength = choice.strength {
                        settings.controls.haptics = true
                        settings.controls.hapticStrength = strength
                    } else {
                        settings.controls.haptics = false
                    }
                }
                // The new strength, felt at once.
                Haptics.tap()
            }
        )
    }
}

/// The Haptics menu: off, or on at a strength.
private enum HapticsChoice: Hashable, CaseIterable {
    case off, light, normal, strong

    init(_ strength: HapticStrength) {
        switch strength {
        case .light: self = .light
        case .normal: self = .normal
        case .strong: self = .strong
        }
    }

    var strength: HapticStrength? {
        switch self {
        case .off: return nil
        case .light: return .light
        case .normal: return .normal
        case .strong: return .strong
        }
    }

    var title: String {
        strength?.title ?? "Off"
    }
}
