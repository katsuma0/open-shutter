import SwiftUI
import CameraCore

/// The Camera Control row of the first page, in the short list and the full one alike, and of the Controls page. It
/// reads the list and the camera itself, so a settings change redraws this row and not the section around it.
struct CameraControlRow: View {
    let model: CameraModel

    var body: some View {
        NavigationLink {
            CameraControlItemsView(model: model)
        } label: {
            LabeledContent("Camera Control", value: CameraControlItemsView.summary(model))
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
                // Text only: the explanations sit above the list, where they are read before it is changed.
                VStack(alignment: .leading, spacing: 12) {
                    Text(Self.intro(hasCameraControl: caps.supportsCameraControls, manualShutter: manualShutter))
                        .textCase(nil)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Included")
                }
            } footer: {
                SettingsFooter(Self.includedNotes(count: chosen.count, limit: limit,
                                                  hasCameraControl: caps.supportsCameraControls))
            }

            if !others.isEmpty {
                Section {
                    ForEach(others) { item in
                        let note = Self.note(for: item, caps: caps, manualShutter: manualShutter)
                        Button {
                            add(item, limit: limit)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .green)
                                    .font(.title3)
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
                } footer: {
                    if chosen.count >= limit {
                        Text("Camera Control holds \(limit) controls. Remove one to add another.")
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
        model.updateSettings { settings in
            guard !settings.controls.cameraControlItems.contains(item),
                  settings.controls.cameraControlItems.count < limit else { return }
            settings.controls.cameraControlItems.append(item)
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

    /// How the overlay is used, and why a control can be in the list and still not move: one set serves every mode.
    private static func intro(hasCameraControl: Bool, manualShutter: Bool) -> String {
        var sentences: [String] = []
        if !hasCameraControl {
            sentences.append("This iPhone has no Camera Control. The list is kept for an iPhone that has one.")
        }
        sentences.append("Press Camera Control lightly to show a control over the picture, then slide along it to change the value. Press lightly twice to see every control on this list, and slide to choose one.")
        // Shutter isn't put on Camera Control without manual shutter speeds, so it has no modes to name there.
        sentences.append(manualShutter
            ? "Some controls only work in some modes. Night duration and Night scene work in Night. Shutter works in Photo, Manual and Video. Elsewhere they stay in the list but can't be used."
            : "Some controls only work in some modes. Night duration and Night scene work in Night. Elsewhere they stay in the list but can't be used.")
        return sentences.joined(separator: "\n\n")
    }

    private static func includedNotes(count: Int, limit: Int, hasCameraControl: Bool) -> [String?] {
        guard count > 0 else { return ["Camera Control shows no app controls. Add some below."] }
        return [
            "Drag to change the order. Up to \(limit) controls. Camera Control lists them in this order and opens on the last one you used.",
            count > limit
                ? "Camera Control on this iPhone takes \(limit) controls, so the ones after the first \(limit) don't show."
                : nil,
            // The click is iOS's button event, set with the volume buttons.
            hasCameraControl ? ButtonsAndHapticsView.cameraControlNote + " You can change that in Buttons and haptics." : nil,
        ]
    }

    /// Where the control works, or why it won't show. The camera checks match what the Camera Control bridge leaves
    /// out, and the modes match CameraControlItem.isActive(in:), which sets what the overlay lets through.
    private static func note(for item: CameraControlItem, caps: CameraCapabilities, manualShutter: Bool) -> String? {
        let missing = "Not on the current camera."
        // MANUAL's values: a pick in PHOTO leads to MANUAL, as the chips do, and NIGHT keeps them to Manual night.
        let setByHand = "A pick in Photo switches to Manual. In Night, Manual night only."
        switch item {
        case .zoom:
            return caps.zoomRange.upperBound > caps.zoomRange.lowerBound ? "Zooms within the current lens." : missing
        // The bridge leaves the picker out on the selfie camera and on a phone with one back lens.
        case .lens:
            return caps.lens.isFront ? missing : "Picks a lens button."
        case .exposureBias:
            return caps.biasRange.upperBound > caps.biasRange.lowerBound ? "Exposure compensation." : missing
        case .shutter:
            // The model leaves Shutter off Camera Control on any other phone.
            guard manualShutter else { return "Needs an iPhone 18 Pro." }
            return caps.supportsCustomExposure ? "Photo, Manual and Video. A pick in Photo switches to Manual." : missing
        case .nightDuration:
            return "Night. How long the shot runs."
        case .nightScene:
            return "Night. The night shot, Manual night or a scene."
        case .iso:
            return caps.supportsCustomExposure ? setByHand : missing
        case .aperture:
            return caps.supportsVariableAperture ? setByHand : "Only on lenses with a variable aperture."
        case .whiteBalance:
            return caps.supportsCustomWhiteBalance ? setByHand : missing
        case .tint:
            return caps.supportsCustomWhiteBalance ? "Works once white balance is set." : missing
        case .focus:
            return caps.supportsManualFocus ? setByHand : missing
        case .timer:
            return "Not in Video."
        case .flash:
            // Stacks never fire it, so Night and a stacked Manual shutter leave it off.
            return caps.hasFlash ? "Photo and Manual." : missing
        case .histogram:
            return "Not in Night."
        case .mode:
            return "Night, Photo, Manual and Video."
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
                .foregroundStyle(Theme.accent)
        }
    }
}
