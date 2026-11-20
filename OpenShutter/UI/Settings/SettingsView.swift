import SwiftUI
import CameraCore

/// The settings sheet. Every control reads `model.settings` and writes through `model.updateSettings`, which saves
/// the change and re-applies it to the camera.
///
/// The Advanced settings switch decides how much the sheet lists; the camera is the same either way. On is the full
/// list: every setting, as a menu of pages by subject. On those pages, rows the current camera can't use stay visible
/// but disabled, and their section footer says why, so nobody hunts for a switch that silently does nothing. Off is
/// the short list: the few settings most people change, all on the first page. The Camera section leads both lists,
/// and the look, the buttons, the tools and About close both.
struct SettingsView: View {
    @Bindable var model: CameraModel

    @Environment(\.dismiss) private var dismiss
    /// Made on first appearance: a default value would build a new location manager on every parent update.
    @State private var locationAccess: LocationPermissionWatcher? = nil

    var body: some View {
        NavigationStack {
            Form {
                AdvancedSettingsSection(model: model)
                CameraSection(model: model)
                SettingsListSections(model: model, locationAccess: locationAccess)
                LookAndControlsSection(model: model)
                PhotoToolsSection()
                PhoneSection(model: model)
                AboutSection(model: model)
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // On the stack rather than the form, so the pages pushed from it get green switches too.
        .toggleStyle(SettingsSwitchStyle())
        .sheetAppearance()
        .onAppear {
            if locationAccess == nil {
                locationAccess = LocationPermissionWatcher()
            }
        }
    }
}

// MARK: - Advanced settings

/// The switch for how much this page lists. It leads the form, because it decides what the rest of it shows. The
/// camera is the same either way.
private struct AdvancedSettingsSection: View {
    let model: CameraModel

    private static let explanation = "Lists every setting, in groups. Off keeps this page to the ones most people change. The camera itself stays the same."

    var body: some View {
        Section {
            Toggle("Advanced settings", isOn: Binding(
                get: { model.showsAdvancedSettings },
                set: { model.setAdvancedSettings($0) }
            ))
        } footer: {
            SettingsFooter([Self.explanation])
        }
    }
}

/// The short list, or the menu that leads to the full one. Reading the switch here keeps it out of the form's own
/// body, which would otherwise re-run with every setting.
private struct SettingsListSections: View {
    let model: CameraModel
    let locationAccess: LocationPermissionWatcher?

    var body: some View {
        if model.showsAdvancedSettings {
            AdvancedMenuSection(model: model, locationAccess: locationAccess)
        } else {
            // What most people change. Each section has its page in the full list, where the rest of its subject is.
            BasicPhotosSection(model: model, locationAccess: locationAccess)
            BatterySaverSection(model: model)
            BasicVideoSection(model: model)
        }
    }
}

// MARK: - Full list

/// The full list as a menu. On one page it ran to some sixty rows, so each subject has a page of its own and a row
/// here that opens it. Each row says what its page holds, so a setting can be found without opening every page.
private struct AdvancedMenuSection: View {
    let model: CameraModel
    let locationAccess: LocationPermissionWatcher?

    var body: some View {
        Section {
            NavigationLink {
                PhotoSettingsView(model: model, locationAccess: locationAccess)
            } label: {
                MenuRowLabel("Photos", detail: "Format, RAW, resolution and processing", symbol: "photo")
            }
            NavigationLink {
                ExposureSettingsView(model: model)
            } label: {
                MenuRowLabel("Exposure", detail: "Auto exposure limit, metering and HDR", symbol: "plusminus.circle")
            }
            NavigationLink {
                FocusSettingsView(model: model)
            } label: {
                MenuRowLabel("Focus", detail: "Autofocus range, faces, tracking and the magnifier", symbol: "scope")
            }
            NavigationLink {
                ViewfinderSettingsView(model: model)
            } label: {
                MenuRowLabel("Viewfinder", detail: "Histogram, zebras and focus peaking", symbol: "viewfinder")
            }
            NavigationLink {
                NightSettingsView(model: model)
            } label: {
                MenuRowLabel("Night", detail: "Long exposures and battery saver", symbol: "moon.stars")
            }
            NavigationLink {
                VideoSettingsView(model: model)
            } label: {
                MenuRowLabel("Video", detail: "Resolution, frame rate and sound", symbol: "video")
            }
            NavigationLink {
                ControlsSettingsView(model: model)
            } label: {
                MenuRowLabel("Controls", detail: "Camera Control and lens switching", symbol: "slider.horizontal.3")
            }
            ThisCameraLink(model: model)
        } header: {
            Text("Advanced")
        }
    }
}

/// The last row of the menu, to everything the current camera reports to apps. It reads the capabilities itself, so
/// a change of lens redraws this row and not the whole menu.
private struct ThisCameraLink: View {
    let model: CameraModel

    var body: some View {
        let capabilities = model.capabilities

        NavigationLink {
            CapabilitiesView(capabilities: capabilities)
        } label: {
            MenuRowLabel("This camera", detail: Self.summary(capabilities), symbol: "info.circle")
        }
    }

    /// The lens by name, focal length and aperture. The active format is on the page itself.
    private static func summary(_ capabilities: CameraCapabilities) -> String {
        let lens = capabilities.lens
        let range = capabilities.exposure.aperture
        let aperture = capabilities.supportsVariableAperture
            ? ApertureScale.label(range.lowerBound) + "\u{2013}" + ApertureScale.compactLabel(range.upperBound)
            : ApertureScale.label(lens.aperture)
        return [lens.name, LensMath.focalLengthLabel(lens.equivalentFocalLength), aperture]
            .joined(separator: " \u{00B7} ")
    }
}

/// A row of the menu: the subject's name over a line that says what its page holds.
private struct MenuRowLabel: View {
    let title: String
    let detail: String
    let symbol: String

    init(_ title: String, detail: String, symbol: String) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
        }
    }
}

// MARK: - Phone

/// Which iPhones the app is made for, and what this one gets. Every iPhone that runs it takes the night shot and the
/// long exposures; manual shutter speeds need the iPhone 18 Pro (CameraModel.allowsManualShutter).
private struct PhoneSection: View {
    let model: CameraModel

    var body: some View {
        Section {
            LabeledContent("Recommended", value: "iPhone 11 or later")
            LabeledContent("Best", value: "iPhone 18 Pro")
            LabeledContent("This iPhone", value: model.allowsManualShutter ? "Every control" : "Night and long exposures")
        } header: {
            Text("Phone")
        } footer: {
            Text(model.allowsManualShutter
                 ? "Night mode, the long exposure scenes and manual shutter speeds all work on this phone."
                 : "Night mode and the long exposure scenes work on any iPhone 11 or later, with durations up to 30 minutes. Manual shutter speeds need an iPhone 18 Pro.")
        }
    }
}

// MARK: - About

private struct AboutSection: View {
    let model: CameraModel

    @State private var isConfirmingReset = false

    var body: some View {
        Section {
            LabeledContent("Version", value: Self.version)
            if model.isSimulated {
                LabeledContent("Camera", value: "Simulated")
            }
            Button("Reset all settings", role: .destructive) {
                isConfirmingReset = true
            }
            .confirmationDialog("Reset all settings?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive, action: resetAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every setting goes back to its default, including the look and the buttons. The Advanced settings switch and the accessibility options stay as they are. Photos and videos you took stay in your library.")
            }
        } header: {
            Text("About")
        }
    }

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return short }
        return "\(short) (\(build))"
    }()

    private func resetAll() {
        let formats = model.capabilities.formats
        model.updateSettings { settings in
            // The look and the button mapping start over with the rest. The Advanced settings switch stays where it
            // is, because updateSettings keeps the interface options: a reset that turned it off would swap the
            // page under the dialog for the short list.
            var fresh = CameraSettings.default
            // Accessibility options are what someone needs to use the app at all, so a reset never takes them away.
            fresh.accessibility = settings.accessibility
            // Mode, lens and zoom say where the camera is, not how it is set up; resetting them would make the
            // preview jump to another lens behind the sheet.
            fresh.mode = settings.mode
            fresh.lensID = settings.lensID
            fresh.zoom = settings.zoom
            // The default 4K 30 isn't on every lens, and the saved values should say what VIDEO really records.
            fresh.video = VideoFormatChoices.fitted(fresh.video, formats: formats)
            settings = fresh
        }
        // An open dial would keep editing a value that just went back to auto, or a tint that no longer applies.
        model.activeDial = nil
        Haptics.success()
    }
}
