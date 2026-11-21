import SwiftUI
import UIKit
import Photos
import CameraCore

/// The app's photos and videos, three to a row as in Photos: the oldest at the top and the newest at the bottom,
/// where it opens, under the thumb. It follows the appearance setting; the viewer it opens stays black.
struct GalleryGrid: View {
    let library: CaptureLibrary
    let zoomSpace: Namespace.ID
    /// The asset to keep in view, so the zoom back from the viewer lands on its cell.
    @Binding var scrollID: String?
    /// While on, a tap ticks a cell instead of opening it.
    let isSelecting: Bool
    @Binding var selection: Set<String>
    let onOpen: (String) -> Void
    let onChangeShared: () -> Void

    @State private var width: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    private static let spacing: CGFloat = 2
    private static let columnCount = 3

    var body: some View {
        let assets = library.assets
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: Self.columnCount)
        let cellPoints = max(0, (width - Self.spacing * CGFloat(Self.columnCount - 1)) / CGFloat(Self.columnCount))
        let pixelSide = (cellPoints * displayScale).rounded(.up)
        ScrollView {
            VStack(spacing: 0) {
                if library.access == .limited {
                    LimitedAccessBanner(missingCount: library.missingCount, onChange: onChangeShared)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                if let assets {
                    LazyVGrid(columns: columns, spacing: Self.spacing) {
                        ForEach(assets.identifiers, id: \.self) { id in
                            GridCell(library: library, asset: assets.asset(id: id), id: id, pixelSide: pixelSide,
                                     zoomSpace: zoomSpace, isSelecting: isSelecting,
                                     isSelected: isSelecting && selection.contains(id)) {
                                onOpen(id)
                            } onToggle: {
                                toggle(id)
                            }
                        }
                    }
                    .scrollTargetLayout()
                    let count = PhotoFacts.libraryCount(photos: assets.photoCount, videos: assets.videoCount)
                    if !count.isEmpty {
                        Text(count)
                            .font(.caption.weight(.medium).monospacedDigit())
                            .tracking(GridStyle.tracking)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                    }
                }
            }
        }
        // Opened at the bottom, and kept there as the grid grows or turns. Not the one-argument form: it would also
        // pin a short grid of a few photos to the bottom of the screen.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollPosition(id: $scrollID, anchor: .center)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .overlay {
            if let assets {
                if assets.isEmpty, library.access == .limited, library.missingCount > 0 {
                    // Under the banner that says some aren't shared, "No photos yet" would say none were taken.
                    GridEmptyState(symbol: "photo.badge.plus", text: "Tap Change to share the photos you took here.")
                } else if assets.isEmpty {
                    GridEmptyState(symbol: "camera.aperture", text: "Photos you take with Open Shutter show up here.")
                }
            } else {
                ProgressView()
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func toggle(_ id: String) {
        withAnimation(Theme.snappy) {
            if selection.contains(id) {
                selection.remove(id)
            } else {
                selection.insert(id)
            }
        }
    }
}

/// One square of the grid: the picture, filled and cropped, with what Photos marks on it.
private struct GridCell: View {
    let library: CaptureLibrary
    let asset: PHAsset?
    let id: String
    /// 0 until the grid knows its width; nothing is asked for before then.
    let pixelSide: CGFloat
    let zoomSpace: Namespace.ID
    let isSelecting: Bool
    let isSelected: Bool
    let onOpen: () -> Void
    let onToggle: () -> Void

    @State private var image: UIImage?

    var body: some View {
        let entry = library.entry(for: id)
        // In Select mode a tap only ticks: no viewer, no zoom.
        Button(action: isSelecting ? onToggle : onOpen) {
            let shape = RoundedRectangle(cornerRadius: GridStyle.cornerRadius, style: .continuous)
            Color(uiColor: .secondarySystemFill)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    }
                }
                .clipShape(shape)
                .overlay {
                    // The picked ones keep full brightness and take the ring; the rest step back a little.
                    if isSelecting, !isSelected {
                        shape.fill(Color.black.opacity(0.22))
                    }
                }
                .overlay {
                    if isSelected {
                        shape.strokeBorder(Theme.accent, lineWidth: 2.5)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // The tick takes the duration's corner while selecting.
                    if isSelecting {
                        SelectionMark(isSelected: isSelected)
                            .padding(6)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else if let asset, asset.mediaType == .video {
                        Text(Formatting.clock(asset.duration))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.white)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                            .padding(5)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if asset?.isFavorite ?? false {
                        Image(systemName: "heart.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                            .padding(5)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let tag = CellTag(kind: entry?.kind, asset: asset) {
                        tag.padding(4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(GridCellButtonStyle())
        .matchedTransitionSource(id: id, in: zoomSpace)
        .accessibilityLabel(asset.map {
            GalleryText.spokenDescription(of: $0, detail: GalleryText.detailTitle(entry?.kind))
        } ?? "Photo")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: CellRequest(asset: asset, pixelSide: pixelSide)) {
            await load()
        }
    }

    private func load() async {
        guard let asset, pixelSide > 0 else { return }
        for await update in AssetRequests.thumbnail(for: asset, pixelSide: pixelSide, manager: library.imageManager) {
            if case .value(let picture, _) = update {
                image = picture
            }
        }
    }
}

/// The grid's own measures, kept here so the camera's tokens stay the camera's.
private enum GridStyle {
    static let cornerRadius: CGFloat = 3
    /// The dial header's spaced capitals.
    static let tracking: CGFloat = 1.2
}

/// The small mark at a cell's top corner: how the app took it, from the row it stored, or Live from the asset
/// PhotoKit already fetched. One mark a cell, the rarest first, so a corner never fills up.
private struct CellTag: View {
    private enum Mark {
        case symbol(String)
        case text(String)
    }

    private let mark: Mark

    init?(kind: CapturedAssetKind?, asset: PHAsset?) {
        switch kind {
        case .stack: mark = .symbol("moon")
        case .raw: mark = .text("RAW")
        case .bracket: mark = .symbol("square.stack.3d.up")
        case .photo, .edit, .video, nil:
            guard asset?.playbackStyle == .livePhoto else { return nil }
            mark = .text("LIVE")
        }
    }

    var body: some View {
        Group {
            switch mark {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 9, weight: .semibold))
            case .text(let text):
                Text(text)
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.6)
            }
        }
        .foregroundStyle(Color.white)
        .frame(minWidth: 10, minHeight: 10)
        .padding(.horizontal, 4)
        .padding(.vertical, 2.5)
        // A dark backing, so the mark reads over a bright sky.
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// What the grid shows with nothing in it: a thin glyph and one plain sentence.
private struct GridEmptyState: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The round tick at a cell's corner in Select mode: an empty ring, or filled with a check once picked.
private struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                Circle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.18))
                Circle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
        .shadow(color: .black.opacity(0.35), radius: 2)
        .accessibilityHidden(true)
    }
}

/// A cell asks again when its asset changes (an edit in Photos) or the grid's width does.
private struct CellRequest: Hashable {
    let version: AssetVersion?
    let pixelSide: Int

    init(asset: PHAsset?, pixelSide: CGFloat) {
        version = asset.map(AssetVersion.init)
        self.pixelSide = pixelSide.isFinite ? Int(min(max(pixelSide, 0), 4_096)) : 0
    }
}

private struct GridCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
