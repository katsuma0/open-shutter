import SwiftUI
import CameraCore

/// The settings sheet. Every control reads `model.settings` and writes through `model.updateSettings`, which saves
/// the change and re-applies it to the camera.
///
/// The Advanced settings switch decides how much the sheet lists; the camera is the same either way. On is the full
/// list: every setting, as a menu of pages by subject. On those pages, rows the current camera can't use stay visible
/// but disabled, and their section footer says why, so nobody hunts for a switch that silently does nothing. Off is
/// the short list: the few settings most people change, all on the first page. The Camera section and the custom
/// setups lead both lists, and the look, the buttons, the tools and About close both.
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
                CustomSetupsSection(model: model)
                SettingsListSections(model: model, locationAccess: locationAccess)
                LookAndControlsSection(model: model)
                PhotoToolsSection(model: model)
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

    private static let explanation = "Shows every setting without changing the camera."

    var body: some View {
        Section {
            Toggle("Advanced settings", isOn: Binding(
                get: { model.showsAdvancedSettings },
                set: { model.setAdvancedSettings($0) }
            ))
        } footer: {
            Text(Self.explanation)
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
            BatterySaverSection(model: model, header: "Night")
            BasicVideoSection(model: model)
        }
    }
}

// MARK: - Full list

/// The full list as a menu of pages, one per subject. The page names say what each holds, so the rows carry no second
/// line. What the camera reports is not a page of settings, so it sits with the tools.
private struct AdvancedMenuSection: View {
    let model: CameraModel
    let locationAccess: LocationPermissionWatcher?

    var body: some View {
        Section {
            NavigationLink {
                PhotoSettingsView(model: model, locationAccess: locationAccess)
            } label: {
                MenuRowLabel("Photos", symbol: "photo")
            }
            NavigationLink {
                ExposureSettingsView(model: model)
            } label: {
                MenuRowLabel("Exposure", symbol: "plusminus.circle")
            }
            NavigationLink {
                FocusSettingsView(model: model)
            } label: {
                MenuRowLabel("Focus", symbol: "scope")
            }
            NavigationLink {
                ViewfinderSettingsView(model: model)
            } label: {
                MenuRowLabel("Viewfinder", symbol: "viewfinder")
            }
            NavigationLink {
                NightSettingsView(model: model)
            } label: {
                MenuRowLabel("Night", symbol: "moon.stars")
            }
            NavigationLink {
                VideoSettingsView(model: model)
            } label: {
                MenuRowLabel("Video", symbol: "video")
            }
        } header: {
            Text("Advanced")
        }
    }
}

/// A row of the menu: the page's name beside its symbol in the accent.
private struct MenuRowLabel: View {
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
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
            // Every iPhone that runs the app takes the night shot and the long exposures; manual shutter speeds need
            // the iPhone 18 Pro (CameraModel.allowsManualShutter).
            LabeledContent("Recommended", value: "iPhone 11 or later")
            LabeledContent("Best", value: "iPhone 18 Pro")
            LabeledContent("This iPhone", value: model.allowsManualShutter ? "Every feature" : "No manual shutter")
            Button("Reset all settings", role: .destructive) {
                isConfirmingReset = true
            }
            .confirmationDialog("Reset all settings?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive, action: resetAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Photos, custom setups and accessibility options are kept.")
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
            // The setups are the person's own work, kept to come back to: a reset of the camera leaves them.
            fresh.setups = settings.setups
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
