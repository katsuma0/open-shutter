import SwiftUI
import CameraCore

/// PHOTO's line of live values: ISO, aperture, white balance and focus, and under it the light meter: how far the
/// picture is from what the meter wants, -3 to +3 EV, live. The shutter and the exposure compensation
/// are not in it: they are the chips beside the lens buttons. The other modes show these four on chips of their own
/// or plan them for the shot, so the line is PHOTO's alone, in the row where MANUAL has its chips.
struct ReadoutHUD: View {
    let model: CameraModel

    var body: some View {
        let items = readoutItems()
        let meter = model.meterOffset
        VStack(spacing: 3) {
            // Four values fit the narrowest phone with Larger labels on, so the line needs no shorter form.
            ReadoutLine(items: items)
            LightMeter(offset: meter)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .cameraGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // Nothing to tap: a touch goes through to the picture.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exposure readout")
        .accessibilityValue(Self.spokenSummary(items) + ". Meter " + EVFormat.label(meter))
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

// MARK: - Meter

/// A camera's exposure scale: -3 to +3 EV in thirds, filled from zero to the reading, with a needle.
private struct LightMeter: View {
    let offset: Double

    private static let range = 3.0
    private static let width: CGFloat = 160
    private static let height: CGFloat = 14
    /// Room at each end for the minus and plus marks.
    private static let inset: CGFloat = 11

    var body: some View {
        let value = offset.isFinite ? min(max(offset, -Self.range), Self.range) : 0
        // Read here rather than in the renderer, which runs outside the body: a new accent, or Increase Contrast,
        // then redraws the scale.
        let accent = Theme.accent
        let marks = Theme.secondaryText
        HStack(spacing: 6) {
            Canvas { context, size in
                Self.drawScale(in: &context, size: size, value: value, accent: accent, marks: marks)
            }
            .frame(width: Self.width, height: Self.height)
            .overlay(alignment: .leading) {
                // Not animated: the reading moves ten times a second, so a glide would never come to rest.
                Capsule()
                    .fill(Self.needleColor(value))
                    .frame(width: 2, height: Self.height)
                    .offset(x: Self.position(of: value, width: Self.width) - 1)
            }
            ZStack {
                Text("+0.0").hidden()
                Text(EVFormat.label(value))
                    .foregroundStyle(abs(value) < 1.0 / 6.0 ? Theme.primaryText : Theme.accent)
            }
            .font(Theme.readoutFont)
            .lineLimit(1)
            .fixedSize()
        }
    }

    private static func position(of value: Double, width: CGFloat) -> CGFloat {
        inset + CGFloat((value + range) / (2 * range)) * (width - 2 * inset)
    }

    /// White near zero, yellow off the mark, red when the reading runs past the end of the scale.
    private static func needleColor(_ value: Double) -> Color {
        if abs(value) >= range - 0.01 { return Theme.recording }
        return abs(value) < 1.0 / 6.0 ? Theme.primaryText : Theme.accent
    }

    private static func drawScale(in context: inout GraphicsContext, size: CGSize, value: Double, accent: Color,
                                  marks: Color) {
        let steps = 18
        var plain = Path()
        var lit = Path()
        for index in 0...steps {
            let ev = -range + Double(index) / 3
            let x = position(of: ev, width: size.width)
            let tick: CGFloat
            if index == steps / 2 {
                tick = size.height
            } else if index % 3 == 0 {
                tick = size.height * 0.6
            } else {
                tick = size.height * 0.3
            }
            let top = (size.height - tick) / 2
            // Ticks between zero and the reading light up, so the size of the error reads at a glance.
            let isLit = value >= 0 ? (ev > 0.01 && ev <= value + 0.01) : (ev < -0.01 && ev >= value - 0.01)
            var line = Path()
            line.move(to: CGPoint(x: x, y: top))
            line.addLine(to: CGPoint(x: x, y: top + tick))
            if isLit {
                lit.addPath(line)
            } else {
                plain.addPath(line)
            }
        }
        context.stroke(plain, with: .color(.white.opacity(0.55)), lineWidth: 1)
        context.stroke(lit, with: .color(accent), lineWidth: 1.5)
        let minus = context.resolve(Text("-").font(.system(size: 9, weight: .semibold)).foregroundStyle(marks))
        let plus = context.resolve(Text("+").font(.system(size: 9, weight: .semibold)).foregroundStyle(marks))
        context.draw(minus, at: CGPoint(x: 0, y: size.height / 2), anchor: .leading)
        context.draw(plus, at: CGPoint(x: size.width, y: size.height / 2), anchor: .trailing)
    }
}
