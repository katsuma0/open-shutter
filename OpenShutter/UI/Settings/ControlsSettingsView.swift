import SwiftUI
import CameraCore

/// The Controls page of the full list: what Camera Control carries and whether zooming changes lenses. The volume
/// buttons and haptics have their own page, linked from Look and controls whether Advanced settings is on or off.
struct ControlsSettingsView: View {
    let model: CameraModel

    var body: some View {
        let controls = model.settings.controls

        Form {
            Section {
                NavigationLink {
                    CameraControlItemsView(model: model)
                } label: {
                    LabeledContent("Camera Control", value: model.capabilities.supportsCameraControls
                        ? "\(controls.cameraControlItems.count) of \(CameraControlItemsView.limit)"
                        : "Not on this iPhone")
                }
                Toggle("Switch lenses while zooming", isOn: model.settingBinding(\.controls.autoLensSwitching))
            } footer: {
                Text("Switching lenses while zooming moves to the next lens as you pinch or drag the zoom wheel past it, like the Camera app.")
            }
        }
        .navigationTitle("Controls")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Chooses and orders the controls Camera Control offers. The system shows them in this order.
private struct CameraControlItemsView: View {
    static let limit = 6

    let model: CameraModel
    /// Always editing, so the reorder handles show without an Edit button.
    @State private var editMode: EditMode = .active

    var body: some View {
        let chosen = model.settings.controls.cameraControlItems
        let others = CameraControlItem.allCases.filter { !chosen.contains($0) }
        let caps = model.capabilities

        List {
            Section {
                ForEach(chosen) { item in
                    ControlItemLabel(item: item, note: Self.note(for: item, caps: caps))
                }
                .onMove { source, destination in
                    model.updateSettings { $0.controls.cameraControlItems.move(fromOffsets: source, toOffset: destination) }
                }
                .onDelete { offsets in
                    model.updateSettings { $0.controls.cameraControlItems.remove(atOffsets: offsets) }
                }
            } header: {
                Text("Included")
            } footer: {
                Text(chosen.isEmpty
                    ? "Camera Control shows no app controls. Add some below."
                    : "Drag to change the order. Up to \(Self.limit) controls, on iPhone models with Camera Control.")
            }

            if !others.isEmpty {
                Section {
                    ForEach(others) { item in
                        let note = Self.note(for: item, caps: caps)
                        Button {
                            add(item)
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
                        .disabled(chosen.count >= Self.limit)
                        .accessibilityLabel("Add \(item.title)")
                        // The label above replaces the visible text, so the camera note is read as a hint instead.
                        .accessibilityHint(note ?? "")
                    }
                } header: {
                    Text("More controls")
                } footer: {
                    if chosen.count >= Self.limit {
                        Text("Camera Control holds \(Self.limit) controls. Remove one to add another.")
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Camera Control")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: removeDuplicates)
    }

    private func add(_ item: CameraControlItem) {
        model.updateSettings { settings in
            guard !settings.controls.cameraControlItems.contains(item),
                  settings.controls.cameraControlItems.count < Self.limit else { return }
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

    /// Matches what the Camera Control bridge skips, so a control that won't appear says so here.
    private static func note(for item: CameraControlItem, caps: CameraCapabilities) -> String? {
        let available: Bool
        switch item {
        case .zoom: available = caps.zoomRange.upperBound > caps.zoomRange.lowerBound
        // The bridge leaves the picker out on the selfie camera and on a phone with one back lens.
        case .lens: available = !caps.lens.isFront
        case .exposureBias: available = caps.biasRange.upperBound > caps.biasRange.lowerBound
        case .shutter, .iso: available = caps.supportsCustomExposure
        case .aperture:
            return caps.supportsVariableAperture ? nil : "Only on lenses with a variable aperture"
        case .whiteBalance: available = caps.supportsCustomWhiteBalance
        case .focus: available = caps.supportsManualFocus
        case .mode: available = true
        }
        return available ? nil : "Not on the current camera"
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
