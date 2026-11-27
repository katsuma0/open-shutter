import SwiftUI
import CameraCore

/// The custom setups C1 to C3, right after Camera on the first page whether Advanced settings is on or off: a whole
/// shooting setup saved once and taken back with one tap, the way a camera's mode dial keeps C1 to C3.
struct CustomSetupsSection: View {
    let model: CameraModel

    var body: some View {
        Section {
            ForEach(0..<CameraSetups.count, id: \.self) { slot in
                CustomSetupRow(model: model, slot: slot)
                    // The first slot is where a search for the setups lands.
                    .id(slot == 0 ? AnyHashable(SettingsAnchor.setups) : AnyHashable(slot))
            }
        } header: {
            Text("Custom setups")
                .settingsHeader()
        }
    }
}

/// One slot: a tap takes the setup and goes back to the camera, or, on an empty slot, saves the current setup and
/// asks for its name. The More button beside it holds the rest, as a tap menu rather than touch and hold.
private struct CustomSetupRow: View {
    let model: CameraModel
    let slot: Int

    @State private var naming = SetupNaming()

    /// Room for a name that still leaves "C1 · " and the name readable in a menu row.
    private static let maxNameLength = 30

    var body: some View {
        let setup = model.settings.setups[slot]
        let code = "C\(slot + 1)"
        let title = setup.map { $0.name.isEmpty ? code : "\(code) \u{00B7} \($0.name)" } ?? code

        HStack(spacing: 8) {
            Button {
                if setup != nil {
                    recall()
                } else {
                    SetupActions.save(model: model, slot: slot, keeping: nil, naming: naming)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(setup?.summary ?? "Tap to save")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            // Borderless, or a tap anywhere on the row would also open the menu beside it.
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .accessibilityHint(setup != nil ? "Uses this setup and goes back to the camera." : "Saves the current setup here.")
            // The More button's choices, for VoiceOver's actions rotor too.
            .accessibilityActions {
                Button("Save current setup here") {
                    SetupActions.save(model: model, slot: slot, keeping: setup?.name, naming: naming)
                }
                if let setup {
                    Button("Rename") { naming.begin(name: setup.name, justSaved: false) }
                    Button("Clear") { SetupActions.clear(model: model, slot: slot) }
                }
            }

            SetupMenu(model: model, slot: slot, name: setup?.name, naming: naming)
        }
        .alert("Name for \(code)", isPresented: Bindable(naming).isPresented) {
            TextField("Name", text: Binding(get: { naming.draft },
                                            set: { naming.draft = String($0.prefix(Self.maxNameLength)) }))
            Button("Save") {
                model.renameSetup(slot: slot, to: naming.draft.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            Button(naming.justSaved ? "Not now" : "Cancel", role: .cancel) {}
        } message: {
            Text(naming.justSaved
                 ? "Saved to \(code). Name it, or leave it as \(code)."
                 : "Leave it empty to call it \(code).")
        }
    }

    private func recall() {
        model.recallSetup(slot: slot)
        // Back to the camera either way: its toast names the setup, or says why it has to wait.
        model.isSettingsPresented = false
    }
}

/// The More button of a slot. Its own view whose inputs compare equal between redraws (the model, the slot, the
/// name, the naming reference), so a redraw of the row never rebuilds the system's menu button.
private struct SetupMenu: View {
    let model: CameraModel
    let slot: Int
    /// nil for an empty slot.
    let name: String?
    let naming: SetupNaming

    var body: some View {
        Menu {
            Button {
                SetupActions.save(model: model, slot: slot, keeping: name, naming: naming)
            } label: {
                Label("Save current setup here", systemImage: "square.and.arrow.down")
            }
            if let name {
                Button {
                    naming.begin(name: name, justSaved: false)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    SetupActions.clear(model: model, slot: slot)
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .imageScale(.large)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        // Saving first wherever the menu opens, above the row or below it.
        .menuOrder(.fixed)
        .accessibilityLabel("C\(slot + 1) options")
        .accessibilityHint(name == nil ? "Saves the current setup here." : "Saves the current setup here, renames it or clears it.")
    }
}

/// What the row and its menu do, in one place so the tap, the menu and VoiceOver's actions behave the same.
@MainActor
private enum SetupActions {
    /// A slot that has a name keeps it, so saving over Milky Way updates Milky Way. A slot that was empty asks for
    /// one, as a fresh setup has none.
    static func save(model: CameraModel, slot: Int, keeping name: String?, naming: SetupNaming) {
        model.saveSetup(slot: slot, name: name)
        Haptics.tap()
        if name == nil {
            naming.begin(name: "", justSaved: true)
        }
    }

    static func clear(model: CameraModel, slot: Int) {
        model.clearSetup(slot: slot)
        Haptics.tap()
    }
}

/// The name being typed for one slot. A reference, so the slot's menu can open the alert without a closure among its
/// inputs, the way PressTracker carries a press.
@MainActor
@Observable
private final class SetupNaming {
    var isPresented = false
    var draft = ""
    /// The slot was empty and has just been saved, so the alert says so and its dismissal keeps the setup.
    var justSaved = false

    func begin(name: String, justSaved: Bool) {
        draft = name
        self.justSaved = justSaved
        isPresented = true
    }
}
