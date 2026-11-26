import SwiftUI
import UIKit
import CameraCore

/// The Camera Control row of the first page, in the short list and the full one alike. It reads the list and the
/// camera itself, so a settings change redraws this row and not the section around it.
struct CameraControlRow: View {
    let model: CameraModel

    /// The button's own symbol where the system has it. Looked up once: a missing name draws nothing.
    private static let symbol = ["camera.shutter.button", "camera"].first { UIImage(systemName: $0) != nil } ?? "camera"

    var body: some View {
        // An iPhone without Camera Control has nothing to set here. The saved list stays for one that has it.
        if model.capabilities.supportsCameraControls {
            NavigationLink(value: SettingsPage.cameraControl) {
                SettingsRowLabel("Camera Control", symbol: Self.symbol, value: CameraControlItemsView.summary(model))
            }
        }
    }
}

/// Chooses and orders the controls Camera Control offers. The system shows them in this order. The same set stays in
/// every mode, as Apple asks: a control with nothing to do in the current mode stays in the overlay but can't be
/// used, so each row says where its control works.
struct CameraControlItemsView: View {
    let model: CameraModel
    /// Always editing, so the reorder handles show without an Edit button. A NavigationLink row in an editing list
    /// doesn't navigate, so this page keeps links off it.
    @State private var editMode: EditMode = .active

    /// How many controls the session takes. A camera that has started says so; before that, 6, what current iPhones
    /// are thought to take.
    static func limit(_ capabilities: CameraCapabilities) -> Int {
        capabilities.maxCameraControls > 0 ? capabilities.maxCameraControls : 6
    }

    /// "4 of 6", the controls Camera Control shows out of what it takes, or why there are none.
    static func summary(_ model: CameraModel) -> String {
        let capabilities = model.capabilities
        guard capabilities.supportsCameraControls else { return "Not on this iPhone" }
        let limit = Self.limit(capabilities)
        // A list saved on an iPhone that took more keeps its extra rows, but only the first ones show.
        return "\(min(model.settings.controls.cameraControlItems.count, limit)) of \(limit)"
    }

    var body: some View {
        let chosen = model.settings.controls.cameraControlItems
        let others = CameraControlItem.allCases.filter { !chosen.contains($0) }
        let caps = model.capabilities
        let limit = Self.limit(caps)
        let manualShutter = model.allowsManualShutter

        List {
            Section {
                ForEach(chosen) { item in
                    ControlItemLabel(item: item, note: Self.note(for: item, caps: caps, manualShutter: manualShutter))
                }
                .onMove { source, destination in
                    model.updateSettings { $0.controls.cameraControlItems.move(fromOffsets: source, toOffset: destination) }
                }
                .onDelete { offsets in
                    model.updateSettings { $0.controls.cameraControlItems.remove(atOffsets: offsets) }
                }
            } header: {
                Text("Included")
                    .settingsHeader()
            } footer: {
                SettingsFooter([Self.includedNote(count: chosen.count, limit: limit)])
            }

            if !others.isEmpty {
                Section {
                    ForEach(others) { item in
                        let note = Self.note(for: item, caps: caps, manualShutter: manualShutter)
                        Button {
                            add(item, limit: limit)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle")
                                    .font(.title3.weight(.light))
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityHidden(true)
                                ControlItemLabel(item: item, note: note)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        // Borderless keeps the button tappable while the list is in edit mode.
                        .buttonStyle(.borderless)
                        .foregroundStyle(.primary)
                        .disabled(chosen.count >= limit)
                        .accessibilityLabel("Add \(item.title)")
                        // The label above replaces the visible text, so the note is read as a hint instead.
                        .accessibilityHint(note ?? "")
                    }
                } header: {
                    Text("More controls")
                        .settingsHeader()
                } footer: {
                    if chosen.count >= limit {
                        Text("Remove a control above to add another.")
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Camera Control")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: removeDuplicates)
    }

    private func add(_ item: CameraControlItem, limit: Int) {
        // The row moves up into Included rather than vanishing from one list and appearing in the other.
        withAnimation(Theme.Motion.rows) {
            model.updateSettings { settings in
                guard !settings.controls.cameraControlItems.contains(item),
                      settings.controls.cameraControlItems.count < limit else { return }
                settings.controls.cameraControlItems.append(item)
            }
        }
    }

    /// Rows are identified by item, so a damaged saved list with repeats would confuse the list's editing.
    private func removeDuplicates() {
        let items = model.settings.controls.cameraControlItems
        var seen = Set<CameraControlItem>()
        let unique = items.filter { seen.insert($0).inserted }
        guard unique.count != items.count else { return }
        model.updateSettings { $0.controls.cameraControlItems = unique }
    }

    /// Only what would otherwise surprise: an empty list, or more controls than this iPhone shows.
    private static func includedNote(count: Int, limit: Int) -> String? {
        if count == 0 { return "Add controls from the list below." }
        return count > limit ? "Only the first \(limit) show on this iPhone." : nil
    }

    /// Where the control works, or why it won't show. The camera checks match what the Camera Control bridge leaves
    /// out, and the modes match CameraControlItem.isActive(in:), which sets what the overlay lets through.
    private static func note(for item: CameraControlItem, caps: CameraCapabilities, manualShutter: Bool) -> String? {
        let missing = "Not on this camera"
        // MANUAL's values: a pick in PHOTO leads to MANUAL, as the chips do, and NIGHT keeps them to Manual night.
        let setByHand = "Photo, Manual, Video and Manual night"
        switch item {
        case .zoom:
            return caps.zoomRange.upperBound > caps.zoomRange.lowerBound ? "Within the current lens" : missing
        // The bridge leaves the picker out on the selfie camera and on a phone with one back lens.
        case .lens:
            return caps.lens.isFront ? missing : nil
        case .exposureBias:
            return caps.biasRange.upperBound > caps.biasRange.lowerBound ? nil : missing
        case .shutter:
            // The model leaves Shutter off Camera Control on any other phone.
            guard manualShutter else { return "Needs an iPhone 18 Pro" }
            return caps.supportsCustomExposure ? "Photo, Manual and Video" : missing
        case .nightDuration, .nightScene:
            return "Night only"
        case .iso:
            return caps.supportsCustomExposure ? setByHand : missing
        case .aperture:
            return caps.supportsVariableAperture ? setByHand : "Needs a variable aperture"
        case .whiteBalance:
            return caps.supportsCustomWhiteBalance ? setByHand : missing
        case .tint:
            return caps.supportsCustomWhiteBalance ? "With white balance set by hand" : missing
        case .focus:
            return caps.supportsManualFocus ? setByHand : missing
        case .timer:
            return "Not in Video"
        case .flash:
            // Stacks never fire it, so Night and a stacked Manual shutter leave it off.
            return caps.hasFlash ? "Photo and Manual" : missing
        case .histogram:
            return "Not in Night"
        case .mode:
            return nil
        }
    }
}

private struct ControlItemLabel: View {
    let item: CameraControlItem
    let note: String?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: item.symbolName)
                .fontWeight(.light)
                .foregroundStyle(Theme.accent)
        }
    }
}
