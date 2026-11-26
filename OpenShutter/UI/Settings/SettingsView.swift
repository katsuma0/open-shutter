import SwiftUI
import CameraCore

/// The settings sheet. Every control reads `model.settings` and writes through `model.updateSettings`, which saves
/// the change and re-applies it to the camera.
///
/// The Advanced settings switch decides how much the sheet lists; the camera is the same either way. On is the full
/// list: every setting, as a menu of pages by subject. On those pages, rows the current camera can't use stay visible
/// but disabled, and their section footer says why, so nobody hunts for a switch that silently does nothing. Off is
/// the short list: the few settings most people change, all on the first page. The Camera section and the custom
/// setups lead both lists, and the look, the controls, the tools and About close both.
///
/// The search above the form finds any setting by name, with Advanced settings on or off, and opens its page, so
/// nobody has to know which page a switch lives on.
struct SettingsView: View {
    @Bindable var model: CameraModel

    @Environment(\.dismiss) private var dismiss
    /// Made on first appearance: a default value would build a new location manager on every parent update.
    @State private var locationAccess: LocationPermissionWatcher? = nil
    @State private var path: [SettingsPage] = []
    @State private var query = ""
    @State private var isSearching = false
    /// A first-page row a search result asked for, scrolled to once the form is back.
    @State private var pendingAnchor: SettingsAnchor?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                Group {
                    if query.isEmpty {
                        Form {
                            AdvancedSettingsSection(model: model)
                            CameraSection(model: model)
                            CustomSetupsSection(model: model)
                            SettingsListSections(model: model, locationAccess: locationAccess)
                            LookSection(model: model)
                            ControlsSection(model: model)
                            PhotoToolsSection(model: model)
                            AboutSection(model: model)
                        }
                        .formStyle(.grouped)
                        .onAppear {
                            // Back from a search that asked for a row of this page.
                            guard let anchor = pendingAnchor else { return }
                            pendingAnchor = nil
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    } else {
                        SettingsSearchResults(query: query, model: model, reveal: reveal)
                    }
                }
            }
            .searchable(text: $query, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .automatic),
                        prompt: "Search")
            .autocorrectionDisabled()
            .navigationDestination(for: SettingsPage.self) { page in
                SettingsDestination(page: page, model: model, locationAccess: locationAccess)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // On the stack rather than the form, so the pages pushed from it get them too: every number in mono digits,
        // and the switches in the accent the sheet tints with, as the camera marks what is on.
        .monospacedDigit()
        .sheetAppearance()
        .onAppear {
            if locationAccess == nil {
                locationAccess = LocationPermissionWatcher()
            }
        }
    }

    /// A result on the first page: the search closes and the form comes back where that row is.
    private func reveal(_ anchor: SettingsAnchor) {
        pendingAnchor = anchor
        query = ""
        isSearching = false
    }
}

// MARK: - Advanced settings

/// The switch for how much this page lists. It leads the form, because it decides what the rest of it shows. The
/// camera is the same either way.
private struct AdvancedSettingsSection: View {
    let model: CameraModel

    var body: some View {
        Section {
            Toggle("Advanced settings", isOn: Binding(
                get: { model.showsAdvancedSettings },
                // The short list and the menu trade places in one motion rather than a jump.
                set: { isOn in withAnimation(Theme.Motion.rows) { model.setAdvancedSettings(isOn) } }
            ))
        } footer: {
            Text("Shows every setting.")
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
            AdvancedMenuSection(model: model)
        } else {
            // What most people change. Each section has its page in the full list, where the rest of its subject is.
            BasicPhotosSection(model: model, locationAccess: locationAccess)
            BatterySaverSection(model: model, header: "Night")
            BasicVideoSection(model: model)
        }
    }
}

// MARK: - Full list

/// The full list as a menu of pages, one per subject. Where one choice sums a page up, it trails the row, so the
/// format, the night plan and the video size read without opening anything.
private struct AdvancedMenuSection: View {
    let model: CameraModel

    var body: some View {
        let settings = model.settings
        Section {
            NavigationLink(value: SettingsPage.photos) {
                SettingsRowLabel("Photos", symbol: "photo", value: Self.photoSummary(settings.capture))
            }
            NavigationLink(value: SettingsPage.exposure) {
                SettingsRowLabel("Exposure", symbol: "plusminus.circle")
            }
            NavigationLink(value: SettingsPage.focus) {
                SettingsRowLabel("Focus", symbol: "scope")
            }
            NavigationLink(value: SettingsPage.viewfinder) {
                SettingsRowLabel("Viewfinder", symbol: "viewfinder")
            }
            NavigationLink(value: SettingsPage.night) {
                SettingsRowLabel("Night", symbol: "moon.stars", value: settings.night.stability.title)
            }
            NavigationLink(value: SettingsPage.video) {
                SettingsRowLabel("Video", symbol: "video", value: VideoSettingsView.summary(settings.video))
            }
        } header: {
            Text("Advanced")
                .settingsHeader()
        }
    }

    /// "HEIF", or "HEIF + RAW" while a RAW file goes with it, since RAW changes what every shot costs.
    private static func photoSummary(_ capture: CaptureOptions) -> String {
        let choice = PhotoFormatChoice(capture)
        guard capture.rawFormat != .none, choice != .rawOnly else { return choice.title }
        return "\(choice.title) + RAW"
    }
}

// MARK: - About

private struct AboutSection: View {
    let model: CameraModel

    @State private var isConfirmingReset = false

    var body: some View {
        Section {
            LabeledContent("Version", value: Self.version)
                .id(SettingsAnchor.about)
            if model.isSimulated {
                LabeledContent("Camera", value: "Simulated")
            }
            // Every iPhone that runs the app takes the night shot and the long exposures; manual shutter speeds need
            // the iPhone 18 Pro (CameraModel.allowsManualShutter), which the footer names only where it matters.
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
                .settingsHeader()
        } footer: {
            if !model.allowsManualShutter {
                Text("Manual shutter needs an iPhone 18 Pro.")
            }
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
