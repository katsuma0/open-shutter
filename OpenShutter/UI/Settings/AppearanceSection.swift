import SwiftUI
import CameraCore

/// How the app looks and handles, whether Advanced settings is on or off: light or dark for Settings, the accent
/// color, and the pages for the buttons and haptics, Camera Control, accessibility and what the camera keeps between
/// launches.
struct LookAndControlsSection: View {
    let model: CameraModel

    var body: some View {
        let accent = model.settings.appearance.accent

        Section {
            SettingsPicker("Appearance", selection: model.settingBinding(\.appearance.scheme),
                           options: AppearanceScheme.allCases, label: \.title)
            AccentColorRow(selection: accent) { choice in
                Haptics.tick()
                model.updateSettings { $0.appearance.accent = choice }
            }
            NavigationLink("Accessibility") {
                AccessibilitySettingsView(model: model)
            }
            // Its own view: it reads the list and the camera, which this section has no need to redraw for. It shows
            // only on an iPhone with Camera Control.
            CameraControlRow(model: model)
            NavigationLink("Buttons and haptics") {
                ButtonsAndHapticsView(model: model)
            }
            if model.showsAdvancedSettings {
                Toggle("Switch lenses while zooming", isOn: model.settingBinding(\.controls.autoLensSwitching))
            }
            NavigationLink("Preserve settings") {
                PreserveSettingsView(model: model)
            }
        } header: {
            Text("Look and controls")
                .settingsHeader()
        } footer: {
            Text("Appearance changes Settings, not the camera.")
        }
    }
}

/// Swatches instead of a menu, because menus draw their icons in one color and the point here is the color. Each
/// swatch is the accent as it would draw here, so in a light sheet it shows the deeper shade Settings would use.
private struct AccentColorRow: View {
    let selection: AccentChoice
    let onSelect: (AccentChoice) -> Void

    var body: some View {
        // Seven swatches beside the label don't fit a 375 pt wide phone, so the label sits above them and the
        // swatches share the row's width.
        VStack(alignment: .leading, spacing: 4) {
            Text("Accent color")
            HStack(spacing: 0) {
                ForEach(AccentChoice.allCases) { choice in
                    swatch(choice)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func swatch(_ choice: AccentChoice) -> some View {
        let isSelected = choice == selection
        return Button {
            guard !isSelected else { return }
            onSelect(choice)
        } label: {
            Circle()
                .fill(AppearanceStore.color(for: choice))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                .overlay {
                    // A mark as well as the ring, so the choice doesn't rest on telling colors apart.
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                    }
                }
                .frame(width: 28, height: 28)
                .padding(3)
                .overlay(Circle().strokeBorder(Color.primary, lineWidth: 2).opacity(isSelected ? 1 : 0))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        // Borderless, or a tap anywhere on the row would fire every swatch at once.
        .buttonStyle(.borderless)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
