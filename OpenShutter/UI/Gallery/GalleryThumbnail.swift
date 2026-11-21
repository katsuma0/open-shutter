import SwiftUI
import UIKit
import CameraCore

// The last capture's thumbnail beside the shutter, and the gallery it opens. In a file of its own so the gallery
// work and the camera screen's layout don't share one file. The gallery is presented here, so its zoom can grow
// out of the square; keep one ThumbnailButton on screen.

/// Where the gallery's zoom transition starts.
private enum GalleryZoom {
    static let thumbnail = "thumbnail"
}

struct ThumbnailButton: View {
    @Bindable var model: CameraModel
    @State private var press = PressTracker()
    @State private var landing = false
    @Namespace private var galleryZoom
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let library = model.library
        let activity = model.activity
        let isHidden = activity == .recording || activity == .stacking
        let canOpen = Self.canOpen(model)
        let picture = ThumbnailPicture(capture: model.lastCapture, library: library)
        Button {
            Self.showGallery(model)
        } label: {
            Upright(model: model) {
                ThumbnailImage(picture: picture)
            }
        }
        // With nothing to show a tap does nothing, so the square stays still under the finger.
        .buttonStyle(PressScaleButtonStyle(isPressed: press.isPressed && canOpen))
        .disabled(!canOpen)
        .accessibilityLabel("Photos")
        .accessibilityValue(picture.spokenValue)
        .accessibilityHint("Shows the photos and videos you took. Touch and hold to open Photos.")
        .accessibilityAction(named: "Open Photos") { Self.openPhotos(model) }
        // Laid over the disabled button as well: Photos can be opened before anything has been captured.
        .overlay {
            ThumbnailTouchLayer(model: model, press: press)
        }
        .matchedTransitionSource(id: GalleryZoom.thumbnail, in: galleryZoom)
        // A short swell as a new picture lands, so the eye catches where the shot went. Not with Reduce motion.
        .scaleEffect(landing ? 1.06 : 1)
        .opacity(isHidden ? 0 : 1)
        .allowsHitTesting(!isHidden)
        .animation(Theme.spring, value: picture.key)
        .animation(Theme.fade, value: isHidden)
        .fullScreenCover(isPresented: $model.isReviewPresented) {
            GalleryView(model: model)
                .galleryZoomTransition(sourceID: GalleryZoom.thumbnail, in: galleryZoom)
        }
        .onChange(of: picture.key) { old, new in
            // Only a picture that replaces one: the first fetch after launch is no new shot.
            guard old != nil, new != nil, !AppearanceStore.shared.reduceMotion else { return }
            withAnimation(Theme.snappy) {
                landing = true
            } completion: {
                withAnimation(Theme.spring) { landing = false }
            }
        }
        .onAppear {
            // The newest photo comes back after a relaunch, but only where access was already given: this never asks.
            library.loadLatestThumbnail(pixelSide: (ThumbnailImage.side * displayScale).rounded(.up))
        }
    }

    /// A capture this session, or any photo taken here before.
    fileprivate static func canOpen(_ model: CameraModel) -> Bool {
        !model.recentCaptures.isEmpty || model.library.hasRecordedAssets
    }

    fileprivate static func showGallery(_ model: CameraModel) {
        guard canOpen(model) else { return }
        Haptics.tap()
        model.isDrawerOpen = false
        model.isReviewPresented = true
    }

    /// The gallery's way into Photos, without the gallery.
    fileprivate static func openPhotos(_ model: CameraModel) {
        Haptics.tap()
        model.isDrawerOpen = false
        PhotosApp.open { opened in
            if !opened {
                model.showToast("Photos couldn't be opened.", symbol: "exclamationmark.triangle")
            }
        }
    }
}

/// What the square shows: this session's last capture while it still exists (as edited, once it is), else the
/// newest photo the library shows, which brings the last photo back after a relaunch and steps past one deleted in
/// the gallery.
private struct ThumbnailPicture {
    /// Changes when a different picture shows, for the swap animation.
    var key: String?
    var image: Image?
    var isVideo = false
    /// From this session: VoiceOver can name the kind and the exposure the camera reported.
    var capture: CaptureResult?
    /// From the library: the row the app stored for it.
    var entry: CapturedAsset?

    @MainActor
    init(capture: CaptureResult?, library: CaptureLibrary) {
        // A capture that never reached Photos has no identifier and still shows: it is the newest there is.
        if let capture, !(capture.assetIdentifier.map(library.isGone) ?? false) {
            if let id = capture.assetIdentifier, let image = library.latestThumbnail, library.latestThumbnailID == id,
               library.assets?.asset(id: id)?.hasAdjustments ?? false {
                // Edited in the gallery or in Photos, so the library's picture shows the edit. An unedited capture
                // keeps its own picture: the fetch after each shot would otherwise swap the square for the same one.
                key = id
                self.image = Image(uiImage: image)
            } else {
                key = capture.id.uuidString
                image = capture.thumbnail.map { Image(decorative: $0, scale: 1) }
            }
            isVideo = capture.kind == .video
            self.capture = capture
        } else if let image = library.latestThumbnail, let id = library.latestThumbnailID {
            let entry = library.entry(for: id)
            key = id
            self.image = Image(uiImage: image)
            isVideo = entry?.kind == .video
            self.entry = entry
        }
    }

    /// The thumbnail's VoiceOver value: the exposure the camera reported, or for a photo from the library its stored
    /// summary where there is one.
    var spokenValue: String {
        if let capture { return capture.summary }
        if let entry {
            if !entry.summary.isEmpty { return entry.summary }
            return entry.kind == .video ? "Video" : "Photo"
        }
        return "None yet"
    }
}

/// The thumbnail's tap and its touch and hold menu, laid over it. Its own view with inputs that never change, so a
/// new capture or a turn of the phone redraws the picture and leaves the system's menu button alone.
private struct ThumbnailTouchLayer: View {
    let model: CameraModel
    let press: PressTracker

    var body: some View {
        MenuOnHoldLayer(press: press) {
            ThumbnailButton.showGallery(model)
        } options: {
            ThumbnailOptions(model: model)
        }
    }
}

private struct ThumbnailOptions: View {
    let model: CameraModel

    var body: some View {
        // A tap already opens the gallery, so the menu only adds the way out to Photos.
        Button {
            ThumbnailButton.openPhotos(model)
        } label: {
            Label("Open Photos", systemImage: "photo.on.rectangle")
        }
    }
}

private struct ThumbnailImage: View {
    static let side: CGFloat = 48

    let picture: ThumbnailPicture

    var body: some View {
        let side = Self.side
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.trackFill)
            if let image = picture.image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .id(picture.key)
                    .transition(AppearanceStore.shared.reduceMotion
                        ? AnyTransition.opacity : .scale(scale: 0.6).combined(with: .opacity))
            }
            if picture.isVideo {
                Image(systemName: "video.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.primaryText)
                    .legibleShadow()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(4)
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                // A fine rim like the chips': a hairline round an empty well, a brighter thin line round a picture,
                // which needs more to stand apart from a dark photo.
                .strokeBorder(picture.image == nil ? Theme.hairline : Color.white.opacity(0.85),
                              lineWidth: picture.image == nil ? Theme.hairlineWidth : 1)
        }
        .frame(width: side, height: side)
    }
}

/// Rotates its content with the phone. Reading motion here instead of in the parent keeps the 30 Hz attitude
/// updates from redrawing whole control rows.
private struct Upright<Content: View>: View {
    let model: CameraModel
    // Built once in init: a stored closure never compares equal, so SwiftUI could never skip this view.
    let content: Content

    init(model: CameraModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    var body: some View {
        content.uprightRotation(model.motion.iconRotationDegrees)
    }
}

/// PressScaleStyle's look, which also takes a press that lands on a layer above the button, such as its touch and
/// hold menu.
private struct PressScaleButtonStyle: ButtonStyle {
    var isPressed = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isPressed
        configuration.label
            .scaleEffect(pressed ? PressScaleStyle().scale : 1)
            .animation(Theme.snappy, value: pressed)
            .contentShape(Rectangle())
    }
}
