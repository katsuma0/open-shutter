import SwiftUI
import CameraCore

/// The Tools section of Settings: pages that read rather than set. Photo info shows a file's own data under its
/// standard names, in both lists. What the camera reports to apps joins it with Advanced settings on.
struct PhotoToolsSection: View {
    let model: CameraModel

    var body: some View {
        Section {
            NavigationLink(value: SettingsPage.photoInfo) {
                SettingsRowLabel("Photo info", symbol: "doc.text.magnifyingglass")
            }
            if model.showsAdvancedSettings {
                ThisCameraLink(model: model)
            }
        } header: {
            Text("Tools")
                .settingsHeader()
        }
    }
}

/// The row to everything the current camera reports to apps. It reads the capabilities itself, so a change of lens
/// redraws this row and not the whole section.
private struct ThisCameraLink: View {
    let model: CameraModel

    var body: some View {
        let capabilities = model.capabilities

        NavigationLink(value: SettingsPage.thisCamera) {
            SettingsRowLabel("This camera", symbol: "camera.aperture", value: Self.summary(capabilities))
        }
    }

    /// The lens by focal length and aperture, "24 mm · f/1.78". Its name and the active format are on the page.
    private static func summary(_ capabilities: CameraCapabilities) -> String {
        let lens = capabilities.lens
        let range = capabilities.exposure.aperture
        let aperture = capabilities.supportsVariableAperture
            ? ApertureScale.label(range.lowerBound) + "\u{2013}" + ApertureScale.compactLabel(range.upperBound)
            : ApertureScale.label(lens.aperture)
        return [LensMath.focalLengthLabel(lens.equivalentFocalLength), aperture].joined(separator: " \u{00B7} ")
    }
}
