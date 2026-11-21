import SwiftUI
import CameraCore

/// The Camera section of Settings: the shape photos are cropped to, the grid and the level. It comes right after the
/// Advanced settings switch whether that is on or off, so what frames the picture stays one tap from the camera's
/// gear.
struct CameraSection: View {
    let model: CameraModel

    var body: some View {
        let aspect = model.settings.capture.aspect

        Section {
            Picker("Aspect ratio", selection: aspectBinding) {
                ForEach(Self.aspectOptions(current: aspect)) { ratio in
                    Text(ratio.label).tag(ratio)
                }
            }
            // Any other shape is for the full list, unless one is saved: then it stays where it can be changed.
            if model.showsAdvancedSettings || !AspectRatio.presets.contains(where: { $0.matches(aspect) }) {
                CustomAspectRow(aspect: aspect) { ratio in
                    model.updateSettings { $0.capture.aspect = ratio }
                }
            }
            SettingsPicker("Grid", selection: model.settingBinding(\.display.grid),
                         options: GridStyle.allCases, label: \.title)
            Toggle("Level", isOn: model.settingBinding(\.display.showLevel))
        } header: {
            Text("Camera")
        }
    }

    /// A saved ratio within half a percent of a preset reads as that preset, so the menu marks the preset.
    private var aspectBinding: Binding<AspectRatio> {
        Binding(
            get: {
                let aspect = model.settings.capture.aspect
                return AspectRatio.presets.first(where: { $0.matches(aspect) }) ?? aspect
            },
            set: { ratio in model.updateSettings { $0.capture.aspect = ratio } }
        )
    }

    /// A custom ratio gets its own row, or the menu would show no selection.
    private static func aspectOptions(current: AspectRatio) -> [AspectRatio] {
        let presets = AspectRatio.presets
        return presets.contains(where: { $0.matches(current) }) ? presets : presets + [current]
    }
}

/// Any shape the presets miss, from its two sides: 1.85 and 1 for cinema, 7 and 6 for a squarer frame. Typed
/// sides are saved when editing ends, so a half-typed number never reaches the crop. A lone side that crosses the
/// saved other side waits for that side too: 1.85 typed as the long side of 4:3 is half of 1.85:1, not 3:1.85.
private struct CustomAspectRow: View {
    let aspect: AspectRatio
    let onCommit: (AspectRatio) -> Void

    private enum Side: Hashable {
        case long, short
    }

    /// Text typed but not saved yet; nil shows the saved side.
    @State private var longText: String?
    @State private var shortText: String?
    @FocusState private var editing: Side?

    private static let range = 1.0...100.0

    var body: some View {
        HStack(spacing: 6) {
            Text("Custom ratio")
            Spacer(minLength: 8)
            field("Long side", draft: $longText, saved: aspect.long, side: .long)
            Text(":")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            field("Short side", draft: $shortText, saved: aspect.short, side: .short)
        }
        // Moving from one field to the other keeps the draft; leaving both saves it.
        .onChange(of: editing) { _, side in
            if side == nil { commit() }
        }
        // A preset picked while a side is half typed wins, instead of being overwritten by the draft on Done.
        .onChange(of: aspect) {
            longText = nil
            shortText = nil
        }
        // Closing Settings or opening one of its pages with the keyboard still up keeps what was typed, even a side
        // still waiting for the other.
        .onDisappear { commit(force: true) }
        .toolbar {
            // The decimal pad has no return key.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editing = nil }
            }
        }
    }

    // Plain text rather than a formatted value field, which may hand over its value only after the focus change
    // that saves it.
    private func field(_ title: String, draft: Binding<String?>, saved: Double, side: Side) -> some View {
        TextField(title, text: Binding(get: { draft.wrappedValue ?? Self.text(saved) }, set: { draft.wrappedValue = $0 }))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($editing, equals: side)
            .frame(width: 64)
    }

    private func commit(force: Bool = false) {
        guard longText != nil || shortText != nil else { return }
        let long = Self.side(longText)
        let short = Self.side(shortText)
        // Saved now, the sides would swap and the side typed next would pair with the wrong one: 1.85 and then 1
        // over 4:3 would save 3:1.
        if !force, (long == nil) != (short == nil),
           (long.map { $0 < aspect.short } ?? false) || (short.map { $0 > aspect.long } ?? false) {
            return
        }
        let typed = AspectRatio(long ?? aspect.long, short ?? aspect.short)
        longText = nil
        shortText = nil
        // 16 and 9, or 1.78 and 1, is a preset, so it takes the preset's name and checkmark.
        let ratio = AspectRatio.presets.first(where: { $0.matches(typed) }) ?? typed
        if ratio != aspect {
            onCommit(ratio)
        }
    }

    private static func text(_ side: Double) -> String {
        side.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// The typed number in the user's locale (a decimal comma too), to two decimals within 1 to 100. nil when
    /// nothing usable was typed, which keeps the saved side.
    private static func side(_ text: String?) -> Double? {
        guard let text, let value = try? Double(text, format: .number), value.isFinite else { return nil }
        return min(max((value * 100).rounded() / 100, range.lowerBound), range.upperBound)
    }
}
