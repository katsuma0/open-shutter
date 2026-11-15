import SwiftUI
import CameraCore

/// The Focus page of the full list: where autofocus searches, how gently it moves and what it follows.
struct FocusSettingsView: View {
    let model: CameraModel

    var body: some View {
        let caps = model.capabilities

        Form {
            Section {
                SettingsPicker("Focus range", selection: model.settingBinding(\.focusOptions.range),
                             options: FocusRange.allCases, label: \.title)
                    .disabled(!caps.focusRangeRestrictionSupported)
                Toggle("Smooth autofocus", isOn: model.settingBinding(\.focusOptions.smooth))
                    .disabled(!caps.smoothFocusSupported)
                SettingsPicker("Face-driven focus", selection: model.settingBinding(\.focusOptions.faceDriven),
                             options: TriState.allCases, label: \.title)
                    .disabled(!caps.faceDrivenAutoFocusSupported)
                Toggle("Subject tracking", isOn: model.settingBinding(\.focusOptions.continuousTracking))
                    .disabled(!caps.continuousAFTrackingSupported)
            } footer: {
                SettingsFooter(Self.notes(caps: caps))
            }
        }
        .navigationTitle("Focus")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func notes(caps: CameraCapabilities) -> [String?] {
        var unavailable = UnavailableFeatures()
        unavailable.note("focus range", supported: caps.focusRangeRestrictionSupported)
        unavailable.note("smooth autofocus", supported: caps.smoothFocusSupported)
        unavailable.note("face-driven focus", supported: caps.faceDrivenAutoFocusSupported)
        unavailable.noteFromIOS27("subject tracking", supported: caps.continuousAFTrackingSupported)
        return [
            "Near and Far keep autofocus from searching the whole range. Smooth autofocus makes gentler focus changes for video.",
            "Subject tracking keeps focus on a moving subject.",
            unavailable.text,
        ]
    }
}
