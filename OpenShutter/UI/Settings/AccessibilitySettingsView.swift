import SwiftUI
import CameraCore

/// Small options that make the camera easier to see, reach and follow. iOS's own Bold Text, Reduce Transparency,
/// Increase Contrast and VoiceOver apply without them.
struct AccessibilitySettingsView: View {
    let model: CameraModel

    var body: some View {
        let systemReducesMotion = AppearanceStore.shared.systemReducesMotion

        Form {
            Section {
                Toggle("Larger camera text", isOn: model.settingBinding(\.accessibility.largerLabels))
                Toggle("Solid buttons", isOn: model.settingBinding(\.accessibility.solidControls))
                Toggle("Reduce motion", isOn: model.settingBinding(\.accessibility.reduceMotion))
                Toggle("Left-handed", isOn: model.settingBinding(\.accessibility.leftHanded))
                Toggle("Speak status", isOn: model.settingBinding(\.accessibility.speakStatus))
            } footer: {
                SettingsFooter([
                    "Speak status says the countdown, and when a long shot starts and ends.",
                    // The in-app switch adds nothing while iOS already keeps the camera still.
                    systemReducesMotion ? "Reduce Motion is already on in iOS." : nil,
                ])
            }
        }
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}
