import SwiftUI
import UIKit
import Photos
import MapKit
import _MapKit_SwiftUI
import CameraCore

/// The info panel's look, measured from the owner's reference: white text at three strengths on dark glass made of
/// the photo itself, units in small capitals, thin lines between groups.
enum InfoPanelStyle {
    // Text: Dynamic Type styles, white at three strengths.
    /// Card values.
    static let primary = Color.white.opacity(0.88)
    /// Device, lens, night line, size, place, altitude.
    @MainActor static var secondary: Color {
        Color.white.opacity(AppearanceStore.shared.increaseContrast ? 0.75 : 0.55)
    }
    /// The date.
    @MainActor static var tertiary: Color {
        Color.white.opacity(AppearanceStore.shared.increaseContrast ? 0.6 : 0.42)
    }
    /// Every text row.
    static let body = Font.subheadline
    static let value = Font.subheadline.weight(.medium).monospacedDigit()
    /// "ISO", "SEC", "MP", "MB".
    static let unit = Font.subheadline.weight(.medium).uppercaseSmallCaps()
    /// "JPEG", "AWB", "P3", "HDR".
    static let badge = Font.caption2.weight(.semibold)

    // Shapes and fills.
    /// The panel floats this far in from the screen's sides.
    static let sideMargin: CGFloat = 8
    static let cornerRadius: CGFloat = 16
    /// Over the blurred photo.
    @MainActor static var scrim: Color {
        Color.black.opacity(AppearanceStore.shared.increaseContrast ? 0.75 : 0.62)
    }
    /// Reduce Transparency or Solid buttons.
    static let solidFill = Color(white: 0.11)
    static let cardFill = Color.white.opacity(0.07)
    static let cardRadius: CGFloat = 12
    @MainActor static var hairline: Color {
        Color.white.opacity(AppearanceStore.shared.increaseContrast ? 0.2 : 0.1)
    }
    static let grabber = Color.white.opacity(0.30)
    /// The file type's badge; its text is dark.
    static let filledBadgeFill = Color.white.opacity(0.48)
    static let filledBadgeText = Color.black.opacity(0.85)
    /// "AWB", "P3", "HDR", "Edited".
    @MainActor static var outlineBadgeStroke: Color {
        Color.white.opacity(AppearanceStore.shared.increaseContrast ? 0.5 : 0.3)
    }
    static let outlineBadgeText = Color.white.opacity(0.82)
    static let badgeRadius: CGFloat = 4
    static let mapHeight: CGFloat = 150
    static let histogramHeight: CGFloat = 96

    // Spacing.
    /// The date row, lines, card, histogram and map.
    static let contentInset: CGFloat = 14
    /// Text rows, so they line up with the card's text.
    static let textInset: CGFloat = contentInset + cardPadding
    static let cardPadding: CGFloat = 10
    static let cardRowHeight: CGFloat = 32
    static let grabberTop: CGFloat = 6
    static let headerHeight: CGFloat = 30
    /// After a line.
    static let groupTop: CGFloat = 18
    /// Device block, card, size row.
    static let blockGap: CGFloat = 10
    /// Before a line.
    static let groupBottom: CGFloat = 22
    /// Between the lines of one block.
    static let lineSpacing: CGFloat = 2
    /// The photo always keeps this much height above the panel.
    static let minimumPhotoRoom: CGFloat = 220

    /// Sampled from the reference. Normal blending, not the viewfinder's additive one, so the channels lie over one
    /// another as they do there.
    static let histogramRed = Color(red: 0.88, green: 0.06, blue: 0.03)
    static let histogramGreen = Color(red: 0.02, green: 0.80, blue: 0.02)
    static let histogramBlue = Color(red: 0.03, green: 0.66, blue: 0.85)
}

// MARK: - Layer

/// The panel under the viewer's photo. It stays in place on photo pages, pushed below the screen while down, so
/// opening it moves it rather than inserting it. This is the one view besides InfoRoom that reads the finger.
struct InfoPanelLayer: View {
    let motion: InfoPanelMotion
    let asset: PHAsset
    /// The app's own record of the shot, if it took it: a stack reserves its night line while the file loads.
    let kind: CapturedAssetKind?
    let store: PhotoFactsStore
    let manager: PHImageManager
    let onAllDetails: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let progress = motion.progress
            InfoPanelSurface(motion: motion, asset: asset, kind: kind, store: store, manager: manager,
                             screenHeight: proxy.size.height, isShowing: progress > 0, onAllDetails: onAllDetails)
                .equatable()
                .frame(height: motion.openHeight)
                .offset(y: (1 - progress) * (motion.openHeight + 20) + (motion.isOpen ? min(motion.drag, 0) : 0))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(progress > 0)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photo info")
        .accessibilityHidden(!motion.isOpen)
        .accessibilityAction(.escape) {
            motion.close()
        }
    }
}

/// The panel's glass, its grip and its content. Equatable on what it shows, so the finger moving the layer above
/// doesn't redraw it.
private struct InfoPanelSurface: View, Equatable {
    let motion: InfoPanelMotion
    let asset: PHAsset
    let kind: CapturedAssetKind?
    let store: PhotoFactsStore
    let manager: PHImageManager
    let screenHeight: CGFloat
    /// Up or on its way: the panel builds and reads only then.
    let isShowing: Bool
    let onAllDetails: () -> Void

    @State private var hasShown = false
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var pull = PullTracker()
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    nonisolated static func == (lhs: InfoPanelSurface, rhs: InfoPanelSurface) -> Bool {
        lhs.asset.localIdentifier == rhs.asset.localIdentifier
            && lhs.asset.modificationDate == rhs.asset.modificationDate
            && lhs.kind == rhs.kind && lhs.screenHeight == rhs.screenHeight && lhs.isShowing == rhs.isShowing
    }

    private var version: AssetVersion { AssetVersion(asset) }

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: InfoPanelStyle.cornerRadius,
                                           topTrailingRadius: InfoPanelStyle.cornerRadius, style: .continuous)
        let entry = store.entries[version]
        VStack(spacing: 0) {
            header(entry)
            if hasShown {
                scroller(entry)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            backing(entry?.backdrop)
        }
        .clipShape(shape)
        .contentShape(shape)
        .padding(.horizontal, InfoPanelStyle.sideMargin)
        .onChange(of: isShowing, initial: true) { _, showing in
            if showing { hasShown = true }
        }
        .onChange(of: wantedHeight, initial: true) { _, height in
            if let height { motion.setOpenHeight(height) }
        }
        .task(id: LoadRequest(version: version, isShowing: isShowing)) {
            guard isShowing else { return }
            await store.load(asset, manager: manager)
        }
        .task(id: LoadRequest(version: version, isShowing: isShowing)) {
            // Apple limits how often an app asks for place names: only for the page the person stays on.
            guard isShowing, asset.location != nil else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await store.loadPlace(asset)
        }
    }

    /// The panel's height for its content, up to the room the photo leaves; nil until the content has measured.
    private var wantedHeight: CGFloat? {
        guard hasShown, headerHeight > 0, contentHeight > 0 else { return nil }
        let room = screenHeight - motion.safeTop - InfoPanelStyle.minimumPhotoRoom
        return max(min(headerHeight + contentHeight, room), headerHeight)
    }

    /// The grip and the date row: a drag here moves the panel, with a little give upward, as a sheet has.
    private func header(_ entry: PhotoFactsStore.Entry?) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(InfoPanelStyle.grabber)
                .frame(width: 36, height: 5)
                .padding(.top, InfoPanelStyle.grabberTop)
                .accessibilityHidden(true)
            InfoHeaderRow(date: asset.creationDate, marks: entry?.facts?.marks ?? [])
                .padding(.horizontal, InfoPanelStyle.contentInset)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { value in
                    let travel = value.translation.height
                    motion.drag = travel >= 0 ? travel : max(travel / 3, -24)
                }
                .onEnded { value in
                    motion.endDrag(translation: value.translation.height, velocity: value.velocity.height)
                }
        )
    }

    private func scroller(_ entry: PhotoFactsStore.Entry?) -> some View {
        ScrollView(.vertical) {
            InfoPanelContent(asset: asset, kind: kind, entry: entry, onAllDetails: onAllDetails)
                .padding(.bottom, motion.safeBottom + 12 + (voiceOver ? 49 : 0))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.always, axes: .vertical)
        // A pull down past the top closes the panel, as it would a sheet. Kept off SwiftUI state: the offset moves
        // every frame of a scroll.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            pull.offset = offset
        }
        .onScrollPhaseChange { old, new in
            if old == .interacting, new != .interacting, pull.offset < -60 {
                motion.close()
            }
        }
    }

    @ViewBuilder
    private func backing(_ backdrop: UIImage?) -> some View {
        if reduceTransparency || AppearanceStore.shared.reduceTransparency || AppearanceStore.shared.solidControls {
            InfoPanelStyle.solidFill
        } else {
            ZStack {
                InfoPanelStyle.solidFill
                if let backdrop {
                    Image(uiImage: backdrop)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
                InfoPanelStyle.scrim
            }
            .animation(.easeInOut(duration: 0.25), value: backdrop)
            .accessibilityHidden(true)
        }
    }
}

/// What the panel's loads are for: the photo, and whether the panel is up for it.
private struct LoadRequest: Hashable {
    let version: AssetVersion
    let isShowing: Bool
}

/// How far the panel's list is pulled past its top. A box, so a scroll doesn't redraw the panel.
private final class PullTracker {
    var offset: CGFloat = 0
}

// MARK: - Content

/// Everything under the date, top to bottom.
private struct InfoPanelContent: View {
    let asset: PHAsset
    let kind: CapturedAssetKind?
    let entry: PhotoFactsStore.Entry?
    let onAllDetails: () -> Void

    var body: some View {
        let facts = entry?.facts
        let isRead = entry?.factsRead ?? false
        let coordinate = asset.location?.coordinate
        VStack(alignment: .leading, spacing: 0) {
            InfoHairline()
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: InfoPanelStyle.blockGap) {
                InfoDeviceBlock(facts: facts, isRead: isRead, isStack: kind == .stack)
                InfoCard(facts: facts, isRead: isRead)
                InfoSizeRow(facts: facts, isRead: isRead)
            }
            .padding(.top, InfoPanelStyle.groupTop)
            .padding(.bottom, InfoPanelStyle.groupBottom)
            .id(AssetVersion(asset))
            .transition(.opacity)
            if !(entry?.pictureRead ?? false) || entry?.curves != nil {
                InfoHairline()
                InfoHistogram(curves: entry?.curves ?? HistogramCurves())
                    .equatable()
                    .frame(height: InfoPanelStyle.histogramHeight)
                    .padding(.horizontal, InfoPanelStyle.contentInset)
                    .padding(.vertical, InfoPanelStyle.groupTop)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("RGB histogram")
                    .accessibilityValue(entry?.histogramSummary ?? "")
            }
            InfoHairline()
            if let coordinate {
                InfoMap(spot: MapSpot(latitude: coordinate.latitude, longitude: coordinate.longitude),
                        heading: facts?.heading)
                    .padding(.horizontal, InfoPanelStyle.contentInset)
                    .padding(.top, InfoPanelStyle.groupTop)
                InfoPlaceRow(lines: entry?.place, coordinate: coordinate, altitude: facts?.altitude)
                    .padding(.horizontal, InfoPanelStyle.textInset)
                    .padding(.top, InfoPanelStyle.blockGap)
            }
            Button {
                onAllDetails()
            } label: {
                Text("All details")
                    .font(InfoPanelStyle.body)
                    .foregroundStyle(InfoPanelStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, InfoPanelStyle.textInset)
            .padding(.top, coordinate == nil ? 4 : InfoPanelStyle.blockGap)
            .accessibilityHint("Shows everything saved in the photo.")
        }
        .animation(.easeInOut(duration: 0.2), value: AssetVersion(asset))
        .animation(.easeInOut(duration: 0.2), value: isRead)
    }
}

/// The date on the left, the marks on the right: depth, Live, HDR, Edited, then the file type.
private struct InfoHeaderRow: View {
    let date: Date?
    let marks: [PhotoFacts.Mark]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(date.map { $0.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()) } ?? "")
                .font(InfoPanelStyle.body)
                .foregroundStyle(InfoPanelStyle.tertiary)
                .lineLimit(2)
            Spacer(minLength: 8)
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                markView(mark)
            }
        }
        .frame(minHeight: InfoPanelStyle.headerHeight)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func markView(_ mark: PhotoFacts.Mark) -> some View {
        switch mark {
        case .depth:
            Image(systemName: "cube")
                .font(.footnote)
                .foregroundStyle(InfoPanelStyle.secondary)
                .accessibilityLabel("Depth")
        case .live:
            Image(systemName: "livephoto")
                .font(.footnote)
                .foregroundStyle(InfoPanelStyle.secondary)
                .accessibilityLabel("Live Photo")
        case .hdr:
            InfoBadge(text: "HDR")
        case .edited:
            InfoBadge(text: "Edited")
        case .format(let name):
            InfoBadge(text: name, isFilled: true)
        }
    }
}

/// Device, lens, and how a stacked shot was made. Each line is left out when unknown; while the file loads, lines
/// of the same height hold the place.
private struct InfoDeviceBlock: View {
    let facts: PhotoFacts?
    let isRead: Bool
    let isStack: Bool

    var body: some View {
        let device = isRead ? facts?.device : "iPhone 17 Pro"
        let lens = isRead ? facts?.lens : "Main camera"
        let night = isRead ? facts?.night.map(nightText) : (isStack ? Text("Night · 30 frames × 1 s") : nil)
        if device != nil || lens != nil || night != nil {
            VStack(alignment: .leading, spacing: InfoPanelStyle.lineSpacing) {
                if let device { Text(device) }
                if let lens { Text(lens) }
                if let night { night }
            }
            .font(InfoPanelStyle.body)
            .foregroundStyle(InfoPanelStyle.secondary)
            .redacted(reason: isRead ? [] : .placeholder)
            .padding(.horizontal, InfoPanelStyle.textInset)
            .accessibilityElement(children: .combine)
        }
    }

    private func nightText(_ line: PhotoFacts.NightLine) -> Text {
        let symbol = line.scene.map { Image(firstAvailableSystemName: $0.symbolNames) }
            ?? Image(systemName: "moon.stars.fill")
        return Text("\(symbol) \(line.text)")
    }
}

/// The exposure in one rounded card: focal length, aperture, ISO and shutter, then white balance and colour space.
private struct InfoCard: View {
    let facts: PhotoFacts?
    let isRead: Bool

    var body: some View {
        if !isRead {
            card(cells: Self.sampleCells, whiteBalance: "AWB", colorSpace: .displayP3)
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        } else if let facts {
            let cells = Self.cells(facts)
            if !cells.isEmpty || facts.whiteBalance != nil || facts.colorSpace != nil {
                card(cells: cells, whiteBalance: facts.whiteBalance, colorSpace: facts.colorSpace)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(InfoSpoken.card(facts))
            }
        }
    }

    private struct Cell: Identifiable {
        let id: Int
        let text: Text
    }

    private static let sampleCells = [
        Cell(id: 0, text: InfoMeasure.text(PhotoFacts.Measure(value: "120", unit: "mm"))),
        Cell(id: 1, text: Text("ƒ/2.8")),
        Cell(id: 2, text: InfoMeasure.text(PhotoFacts.Measure(value: "250", unit: "ISO", unitFirst: true))),
        Cell(id: 3, text: InfoMeasure.text(PhotoFacts.Measure(value: "1/83", unit: "SEC"))),
    ]

    private static func cells(_ facts: PhotoFacts) -> [Cell] {
        var texts: [Text] = []
        if let focal = facts.focal { texts.append(InfoMeasure.text(focal)) }
        if let aperture = facts.aperture { texts.append(Text(aperture)) }
        if let iso = facts.iso { texts.append(InfoMeasure.text(iso)) }
        if let shutter = facts.shutter { texts.append(InfoMeasure.text(shutter)) }
        return texts.enumerated().map { Cell(id: $0.offset, text: $0.element) }
    }

    private func card(cells: [Cell], whiteBalance: String?, colorSpace: PhotoFacts.ColorSpace?) -> some View {
        VStack(spacing: 0) {
            if !cells.isEmpty {
                ViewThatFits(in: .horizontal) {
                    spread(cells)
                    stacked(cells)
                }
                .font(InfoPanelStyle.value)
                .foregroundStyle(InfoPanelStyle.primary)
                .frame(minHeight: InfoPanelStyle.cardRowHeight)
            }
            if !cells.isEmpty, whiteBalance != nil || colorSpace != nil {
                InfoHairline(inset: 0)
            }
            if whiteBalance != nil || colorSpace != nil {
                HStack {
                    if let whiteBalance { InfoBadge(text: whiteBalance) }
                    Spacer(minLength: 8)
                    if let colorSpace { InfoBadge(text: colorSpace.title, showsWheel: colorSpace == .displayP3) }
                }
                .frame(minHeight: InfoPanelStyle.cardRowHeight)
            }
        }
        .padding(.horizontal, InfoPanelStyle.cardPadding)
        .background(InfoPanelStyle.cardFill,
                    in: RoundedRectangle(cornerRadius: InfoPanelStyle.cardRadius, style: .continuous))
        .padding(.horizontal, InfoPanelStyle.contentInset)
    }

    /// Spread across the width, as in the reference.
    private func spread(_ cells: [Cell]) -> some View {
        HStack(spacing: 0) {
            ForEach(cells) { cell in
                if cell.id > 0 { Spacer(minLength: 12) }
                cell.text.lineLimit(1).fixedSize()
            }
        }
    }

    /// Two by two, at text sizes too large for one row.
    private func stacked(_ cells: [Cell]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { start in
                GridRow {
                    cells[start].text
                    if start + 1 < cells.count { cells[start + 1].text }
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pixel size and megapixels on the left, file size on the right.
private struct InfoSizeRow: View {
    let facts: PhotoFacts?
    let isRead: Bool

    var body: some View {
        if !isRead {
            row(dimensions: "4,032 × 3,024", megapixels: PhotoFacts.Measure(value: "12.2", unit: "MP"),
                fileSize: PhotoFacts.Measure(value: "6.83", unit: "MB"))
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
        } else if let facts, facts.dimensions != nil || facts.fileSize != nil {
            row(dimensions: facts.dimensions, megapixels: facts.megapixels, fileSize: facts.fileSize)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(InfoSpoken.size(facts))
        }
    }

    private func row(dimensions: String?, megapixels: PhotoFacts.Measure?,
                     fileSize: PhotoFacts.Measure?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let dimensions {
                if let megapixels {
                    Text("\(Text(dimensions)) · \(InfoMeasure.text(megapixels))")
                } else {
                    Text(dimensions)
                }
            }
            Spacer(minLength: 8)
            if let fileSize { InfoMeasure.text(fileSize) }
        }
        .font(InfoPanelStyle.body.monospacedDigit())
        .foregroundStyle(InfoPanelStyle.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, InfoPanelStyle.textInset)
    }
}

/// The place's name on the left, up to three lines, and its height on the right.
private struct InfoPlaceRow: View {
    /// nil while the name is asked for; empty when there was none, and the coordinates stand in.
    let lines: [String]?
    let coordinate: CLLocationCoordinate2D
    let altitude: PhotoFacts.Altitude?

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: InfoPanelStyle.lineSpacing) {
                if let lines {
                    if lines.isEmpty {
                        Text(MetadataFormat.coordinates(latitude: coordinate.latitude, latitudeRef: nil,
                                                        longitude: coordinate.longitude, longitudeRef: nil) ?? "")
                    } else {
                        ForEach(Array(lines.prefix(3).enumerated()), id: \.offset) { _, line in
                            Text(line)
                        }
                    }
                } else {
                    // Held in place while the name is asked for.
                    Text("Grant Park")
                    Text("South Loop, Chicago")
                }
            }
            .redacted(reason: lines == nil ? .placeholder : [])
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if let altitude {
                VStack(alignment: .trailing, spacing: InfoPanelStyle.lineSpacing) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.caption2)
                    InfoMeasure.text(altitude.metres)
                    InfoMeasure.text(altitude.feet)
                }
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Altitude")
                .accessibilityValue(InfoSpoken.measure(altitude.metres))
            }
        }
        .font(InfoPanelStyle.body)
        .foregroundStyle(InfoPanelStyle.secondary)
    }
}

// MARK: - Pieces

/// A number with its unit: capitals set small ("1/83 SEC", "ISO 250"), lowercase units as they are ("120 mm").
private enum InfoMeasure {
    static func text(_ measure: PhotoFacts.Measure) -> Text {
        guard !measure.unit.isEmpty else { return Text(measure.value) }
        let isCapitals = measure.unit == measure.unit.uppercased()
        let unit = isCapitals ? Text(measure.unit).font(InfoPanelStyle.unit) : Text(measure.unit)
        // A thin space, as the reference sets it. Interpolation, not Text + Text, which iOS 26 deprecates.
        return measure.unitFirst
            ? Text("\(unit)\u{2009}\(Text(measure.value))")
            : Text("\(Text(measure.value))\u{2009}\(unit)")
    }
}

/// The words VoiceOver reads for the panel's numbers.
private enum InfoSpoken {
    static func card(_ facts: PhotoFacts) -> String {
        var parts: [String] = []
        if let focal = facts.focal { parts.append(measure(focal)) }
        if let aperture = facts.aperture { parts.append(aperture.replacingOccurrences(of: "ƒ/", with: "f ")) }
        if let iso = facts.iso { parts.append("ISO " + iso.value) }
        if let shutter = facts.shutter { parts.append(measure(shutter)) }
        if let whiteBalance = facts.whiteBalance {
            parts.append(whiteBalance == "AWB" ? "auto white balance" : whiteBalance + " white balance")
        }
        if let colorSpace = facts.colorSpace {
            parts.append(colorSpace == .displayP3 ? "Display P3" : colorSpace.title)
        }
        return parts.joined(separator: ", ")
    }

    static func size(_ facts: PhotoFacts) -> String {
        var parts: [String] = []
        if let dimensions = facts.dimensions { parts.append(dimensions.replacingOccurrences(of: "×", with: "by")) }
        if let megapixels = facts.megapixels { parts.append(measure(megapixels)) }
        if let fileSize = facts.fileSize { parts.append(measure(fileSize)) }
        return parts.joined(separator: ", ")
    }

    static func measure(_ measure: PhotoFacts.Measure) -> String {
        let one = measure.value == "1"
        switch measure.unit {
        case "SEC":
            if measure.value.contains("/") { return measure.value + " of a second" }
            return measure.value + (one ? " second" : " seconds")
        case "mm": return measure.value + (one ? " millimetre" : " millimetres")
        case "m": return measure.value + (one ? " metre" : " metres")
        case "ft": return measure.value + (one ? " foot" : " feet")
        case "MP": return measure.value + (one ? " megapixel" : " megapixels")
        case "KB": return measure.value + (one ? " kilobyte" : " kilobytes")
        case "MB": return measure.value + (one ? " megabyte" : " megabytes")
        case "GB": return measure.value + (one ? " gigabyte" : " gigabytes")
        case "": return measure.value
        default: return measure.unitFirst ? measure.unit + " " + measure.value : measure.value + " " + measure.unit
        }
    }
}

/// A small badge: outlined for "AWB", "P3", "HDR"; filled for the file type.
private struct InfoBadge: View {
    let text: String
    var isFilled = false
    /// The colour wheel beside "P3".
    var showsWheel = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: InfoPanelStyle.badgeRadius, style: .continuous)
        HStack(spacing: 3) {
            if showsWheel {
                Circle()
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                          center: .center))
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(InfoPanelStyle.badge)
        .foregroundStyle(isFilled ? InfoPanelStyle.filledBadgeText : InfoPanelStyle.outlineBadgeText)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background {
            if isFilled {
                shape.fill(InfoPanelStyle.filledBadgeFill)
            } else {
                shape.strokeBorder(InfoPanelStyle.outlineBadgeStroke, lineWidth: 1)
            }
        }
    }
}

/// A one-pixel line between groups.
private struct InfoHairline: View {
    var inset: CGFloat = InfoPanelStyle.contentInset
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        InfoPanelStyle.hairline
            .frame(height: 1 / max(displayScale, 1))
            .padding(.horizontal, inset)
            .accessibilityHidden(true)
    }
}

/// The photo's RGB histogram, edge to edge with no frame: soft fills with the green on top, as in the reference.
private struct InfoHistogram: View, Equatable {
    let curves: HistogramCurves

    var body: some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1, curves.channels.count == 3 else { return }
            // Red, green, blue as made; drawn blue, red, green.
            let drawn = [(2, InfoPanelStyle.histogramBlue), (0, InfoPanelStyle.histogramRed),
                         (1, InfoPanelStyle.histogramGreen)]
            for (index, color) in drawn {
                let paths = HistogramPlot.paths(curves.channels[index], size: size)
                context.fill(paths.area, with: .color(color.opacity(0.5)))
                context.stroke(paths.curve, with: .color(color), lineWidth: 1.25)
            }
        }
    }
}

/// Where a photo was taken, as the map compares it.
private struct MapSpot: Equatable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200)
    }
}

/// A still map of the spot, with the dot and the way the camera faced. A tap opens Apple Maps there. One map for
/// the panel: a new photo pans it rather than building another.
private struct InfoMap: View {
    let spot: MapSpot
    /// Degrees clockwise from north; nil when the file doesn't say.
    let heading: Double?
    @State private var camera: MapCameraPosition
    @Environment(\.openURL) private var openURL

    init(spot: MapSpot, heading: Double?) {
        self.spot = spot
        self.heading = heading
        _camera = State(initialValue: .region(spot.region))
    }

    var body: some View {
        // No interaction, so the panel's list scrolls over it.
        Map(position: $camera, interactionModes: []) {
            Annotation("", coordinate: spot.coordinate, anchor: .center) {
                LocationDot(heading: heading)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .all))
        .mapControlVisibility(.hidden)
        .frame(height: InfoPanelStyle.mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: InfoPanelStyle.cardRadius, style: .continuous))
        .overlay {
            Button {
                openMaps()
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onChange(of: spot) { _, spot in
            withAnimation {
                camera = .region(spot.region)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open in Maps") {
            openMaps()
        }
    }

    private func openMaps() {
        let place = PhotoInfoLocation(latitude: spot.latitude, longitude: spot.longitude, text: "")
        if let url = place.mapsURL { openURL(url) }
    }
}

/// Maps' blue dot, with a cone the way the camera faced when that is known.
private struct LocationDot: View {
    let heading: Double?

    var body: some View {
        ZStack {
            if let heading {
                ViewCone()
                    .fill(RadialGradient(colors: [Color.blue.opacity(0.55), Color.blue.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: 44))
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(heading))
            }
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
            Circle()
                .fill(Color.blue)
                .frame(width: 11, height: 11)
        }
        .accessibilityHidden(true)
    }
}

/// A 60 degree wedge pointing up from the centre.
private struct ViewCone: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: rect.width / 2, startAngle: .degrees(-120), endAngle: .degrees(-60),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}
