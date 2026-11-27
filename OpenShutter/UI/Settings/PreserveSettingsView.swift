import SwiftUI
import CameraCore

/// What the camera keeps from last time when Open Shutter starts, as in iOS's Camera settings. Each switch off starts
/// its part where a fresh install does.
struct PreserveSettingsView: View {
    let model: CameraModel

    var body: some View {
        Form {
            Section {
                Toggle("Camera mode", isOn: model.settingBinding(\.startup.keepMode))
                Toggle("Lens and zoom", isOn: model.settingBinding(\.startup.keepLensAndZoom))
                Toggle("Exposure", isOn: model.settingBinding(\.startup.keepBrightness))
            } footer: {
                Text("Off opens in Photo at 1\u{00D7} with exposure at 0.")
            }
        }
        .navigationTitle("Preserve settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
