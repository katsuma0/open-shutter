import SwiftUI
import CameraCore

/// PHOTO's line of live values: ISO, aperture, white balance and focus, and under it the white balance on a scale
/// from warm to cool, live. The shutter and the exposure compensation
/// are not in it: they are the chips beside the lens buttons. The other modes show these four on chips of their own
/// or plan them for the shot, so the line is PHOTO's alone, in the row where MANUAL has its chips.
struct ReadoutHUD: View {
    let model: CameraModel

    var body: some View {
        let items = readoutItems()
        let kelvin = items.first { $0.kind == .kelvin }?.value
        VStack(spacing: 3) {
            // Four values fit the narrowest phone with Larger labels on, so the line needs no shorter form.
            ReadoutLine(items: items)
            if let kelvin {
                WhiteBalanceMeter(kelvin: kelvin)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .cameraGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // Nothing to tap: a touch goes through to the picture.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exposure readout")
        .accessibilityValue(Self.spokenSummary(items))
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Values

    private func readoutItems() -> [ReadoutItem] {
        let capabilities = model.capabilities
        return [
            isoItem(capabilities),
            apertureItem(capabilities),
            kelvinItem(capabilities),
            focusItem(capabilities),
        ]
    }

    private func isoItem(_ capabilities: CameraCapabilities) -> ReadoutItem {
        // A camera without custom exposure runs auto whatever the settings say, so the readout shows the live value.
        let custom = capabilities.supportsCustomExposure
        let iso = custom ? model.displayISO : model.readings.iso
        let isAuto = model.isISOAuto || !custom
        // The widest label this slot can show, so the line doesn't shuffle as the ISO changes.
        let highest = ISOScale.label(capabilities.exposure.iso.upperBound)
        let template = highest.count > 8 ? highest : "ISO 6400"
        return ReadoutItem(kind: .iso, text: ISOScale.label(iso), template: template, value: iso,
                           isManual: !isAuto, marksAuto: isAuto, reservesMark: true,
                           spoken: "ISO \(ISOScale.compactLabel(iso))")
    }

    private func apertureItem(_ capabilities: CameraCapabilities) -> ReadoutItem {
        let aperture = model.displayAperture
        // A fixed iris is neither auto nor manual, so it gets neither the yellow nor the A.
        let variable = capabilities.supportsVariableAperture
        let isAuto = model.isApertureAuto
        return ReadoutItem(kind: .aperture, text: ApertureScale.label(aperture), template: "\u{0192}/8.88",
                           value: aperture, isManual: variable && !isAuto, marksAuto: variable && isAuto,
                           reservesMark: variable,
                           spoken: "Aperture f \(ApertureScale.compactLabel(aperture))")
    }

    private func kelvinItem(_ capabilities: CameraCapabilities) -> ReadoutItem {
        let custom = capabilities.supportsCustomWhiteBalance
        let kelvin = custom ? model.displayKelvin : model.readings.kelvin
        let isAuto = model.effectiveWhiteBalance.isAuto || !custom
        let label = Formatting.kelvin(kelvin)
        return ReadoutItem(kind: .kelvin, text: label, template: "10000K", value: kelvin,
                           isManual: !isAuto, marksAuto: isAuto, reservesMark: true,
                           spoken: "White balance \(label.dropLast()) kelvin")
    }

    private func focusItem(_ capabilities: CameraCapabilities) -> ReadoutItem {
        // The model falls back to autofocus on a lens that can't hold a lens position.
        guard model.effectiveFocus.lensPosition != nil, capabilities.supportsManualFocus else {
            return ReadoutItem(kind: .focus, text: "AF", template: "MF 100%", value: -1, isManual: false,
                               marksAuto: false, reservesMark: false, spoken: "Autofocus")
        }
        let position = model.displayLensPosition
        let label = Formatting.lensPosition(position)
        return ReadoutItem(kind: .focus, text: label, template: "MF 100%", value: position, isManual: true,
                           marksAuto: false, reservesMark: false,
                           spoken: "Manual focus \(label.dropFirst(3))")
    }

    private static func spokenSummary(_ items: [ReadoutItem]) -> String {
        items.map { $0.marksAuto ? $0.spoken + ", auto" : $0.spoken }.joined(separator: ". ")
    }
}

// MARK: - Line

private struct ReadoutItem: Identifiable {
    enum Kind: String {
        case iso, aperture, kelvin, focus
    }

    let kind: Kind
    let text: String
    /// The widest text the slot shows; the slot keeps that width so values don't push each other around.
    let template: String
    /// Drives the direction digits roll in.
    let value: Double
    /// Yellow: a value set by hand. A fixed iris is neither that nor auto, and stays white without the "A".
    let isManual: Bool
    /// Auto values carry a small "A", as in the Camera app.
    let marksAuto: Bool
    /// Room for the "A" is kept even while the value is manual, so switching doesn't shift the line.
    let reservesMark: Bool
    let spoken: String

    var id: String { kind.rawValue }
}

private struct ReadoutLine: View {
    let items: [ReadoutItem]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(items) { item in
                ReadoutSlot(item: item)
            }
        }
        .fixedSize()
    }
}

private struct ReadoutSlot: View {
    let item: ReadoutItem

    var body: some View {
        ZStack {
            ReadoutValue(text: item.template, marked: item.reservesMark)
                .hidden()
            ReadoutValue(text: item.text, marked: item.marksAuto)
                .foregroundStyle(item.isManual ? Theme.accent : Theme.primaryText)
                .contentTransition(.numericText(value: item.value))
        }
        // Only the switch between auto and manual rolls the digits. Auto values change with most 10 Hz readings,
        // and rolling each one would keep an animation, and with it the 120 Hz display, running the whole time.
        // The dial header and the strip chips work the same way.
        .animation(Theme.snappy, value: item.isManual)
    }
}

private struct ReadoutValue: View {
    let text: String
    let marked: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(text)
                .font(Theme.readoutFont)
            if marked {
                Text("A")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .baselineOffset(4)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - White balance meter

/// The light's colour temperature on a strip from amber (2000 K, candles and sodium lamps) through white (daylight)
/// to blue (10000 K, shade and blue hour), with a needle at the value the camera is using: the live reading under
/// auto white balance, the set value otherwise. On a log scale, so daylight sits right of the middle and the warm
/// end, where indoor light differs most, has room.
private struct WhiteBalanceMeter: View {
    let kelvin: Double

    private static let range: ClosedRange<Double> = 2000...10000
    private static let width: CGFloat = 150
    private static let height: CGFloat = 5
    private static let colors: [Color] = [
        Color(red: 1.0, green: 0.55, blue: 0.15),
        Color(red: 1.0, green: 0.76, blue: 0.47),
        Color(red: 1.0, green: 1.0, blue: 1.0),
        Color(red: 0.76, green: 0.86, blue: 1.0),
        Color(red: 0.55, green: 0.70, blue: 1.0),
    ]

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: Self.colors, startPoint: .leading, endPoint: .trailing))
            .opacity(0.85)
            .frame(width: Self.width, height: Self.height)
            .overlay(alignment: .leading) {
                // Not animated: under auto white balance the reading moves ten times a second.
                Capsule()
                    .fill(Theme.primaryText)
                    .frame(width: 2, height: Self.height + 6)
                    .shadow(color: .black.opacity(0.7), radius: 1.5)
                    .offset(x: Self.position(kelvin) * Self.width - 1)
            }
            .frame(height: Self.height + 6)
            .accessibilityHidden(true)
    }

    private static func position(_ kelvin: Double) -> CGFloat {
        guard kelvin.isFinite, kelvin > 0 else { return 0.5 }
        let clamped = min(max(kelvin, range.lowerBound), range.upperBound)
        return CGFloat(log(clamped / range.lowerBound) / log(range.upperBound / range.lowerBound))
    }
}
