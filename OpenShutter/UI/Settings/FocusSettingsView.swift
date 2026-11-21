import SwiftUI
import CameraCore

/// The Focus page of the full list: where autofocus searches, how gently it moves and what it follows, and the
/// magnifier for focusing by hand.
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

            Section {
                SettingsPicker("Focus magnifier", selection: model.settingBinding(\.focusOptions.magnifier),
                             options: FocusMagnifier.allCases, label: \.title)
                    // It enlarges the frame while the lens is focused by hand, which this camera can't do.
                    .disabled(!caps.supportsManualFocus)
            } footer: {
                SettingsFooter(Self.magnifierNotes(caps: caps, depth: model.settings.capture.depth))
            }
        }
        .navigationTitle("Focus")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func magnifierNotes(caps: CameraCapabilities, depth: Bool) -> [String?] {
        var unavailable = UnavailableFeatures()
        unavailable.note("focus magnifier", supported: caps.supportsManualFocus)
        return [
            "Enlarges the frame while you focus by hand.",
            // Depth delivery rebuilds the capture pipeline at every zoom change, so the model doesn't offer it then.
            depth && caps.depthSupported ? "The magnifier is off while Depth is on." : nil,
            unavailable.text,
        ]
    }

    private static func notes(caps: CameraCapabilities) -> [String?] {
        var unavailable = UnavailableFeatures()
        unavailable.note("focus range", supported: caps.focusRangeRestrictionSupported)
        unavailable.note("smooth autofocus", supported: caps.smoothFocusSupported)
        unavailable.note("face-driven focus", supported: caps.faceDrivenAutoFocusSupported)
        unavailable.noteFromIOS27("subject tracking", supported: caps.continuousAFTrackingSupported)
        return [unavailable.text]
    }
}
