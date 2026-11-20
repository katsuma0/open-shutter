import SwiftUI
import CameraCore

/// The Controls page of the full list: what Camera Control carries and whether zooming changes lenses. The volume
/// buttons and haptics have their own page, linked from Look and controls whether Advanced settings is on or off, and
/// so does the Camera Control row, which this page repeats for the people who look for it here.
struct ControlsSettingsView: View {
    let model: CameraModel

    var body: some View {
        Form {
            Section {
                CameraControlRow(model: model)
                Toggle("Switch lenses while zooming", isOn: model.settingBinding(\.controls.autoLensSwitching))
            } footer: {
                Text("Switching lenses while zooming moves to the next lens as you pinch or drag the zoom wheel past it, like the Camera app.")
            }
        }
        .navigationTitle("Controls")
        .navigationBarTitleDisplayMode(.inline)
    }
}
