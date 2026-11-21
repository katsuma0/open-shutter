import SwiftUI
import UIKit
import Photos
import CameraCore

/// Where the viewer's info panel is: up, down, or under a finger. Only small leaf views read `drag` and `progress`
/// (InfoRoom and the panel's layer), so a finger at 120 Hz redraws those two and never the viewer, its bars or the
/// pager.
@MainActor
@Observable
final class InfoPanelMotion {
    /// The last height an open panel measured in this run, so the next viewer starts there and rarely corrects.
    static var lastOpenHeight: CGFloat = 420

    /// Where the panel rests. Changed only with an animation.
    private(set) var isOpen = false
    /// How far a finger has moved the panel from where it rests, in points; positive is down. 0 at rest.
    var drag: CGFloat = 0
    /// The open panel's height, set by the panel from its content.
    var openHeight: CGFloat = InfoPanelMotion.lastOpenHeight
    /// The phone's own top inset (the sensor housing), so the photo stays clear of it. Not the view's: inside the
    /// navigation stack that grows with the bar, which hides just as the panel opens, and the photo would jump.
    var safeTop: CGFloat = 59
    /// The phone's own bottom inset, so the panel's last row clears the home indicator.
    var safeBottom: CGFloat = 34

    /// 0 down, 1 up, with the finger applied.
    var progress: CGFloat {
        guard openHeight > 1 else { return isOpen ? 1 : 0 }
        let shown = (isOpen ? openHeight : 0) - drag
        return min(max(shown / openHeight, 0), 1)
    }

    static var animation: Animation {
        AppearanceStore.shared.reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.36, dampingFraction: 0.88)
    }

    func open() {
        settle(open: true)
    }

    func close() {
        guard isOpen || drag != 0 else { return }
        settle(open: false)
    }

    func toggle() {
        settle(open: !isOpen)
    }

    /// A drag on the photo, from its page's swipe recognizer. Closed, it only lifts; open, it only lowers.
    func track(_ phase: InfoDragPhase) {
        switch phase {
        case .changed(let translation):
            drag = isOpen ? max(0, translation) : min(0, translation)
        case .ended(let translation, let velocity):
            endDrag(translation: translation, velocity: velocity)
        case .cancelled:
            endDrag(translation: 0, velocity: 0)
        }
    }

    /// A quarter of the way, or a flick, opens or closes it; anything less springs back.
    func endDrag(translation: CGFloat, velocity: CGFloat) {
        var opens = isOpen
        if !isOpen, translation < -openHeight * 0.25 || velocity < -600 { opens = true }
        if isOpen, translation > openHeight * 0.25 || velocity > 600 { opens = false }
        settle(open: opens)
    }

    /// A new height from the panel's content. The photo above glides with it.
    func setOpenHeight(_ height: CGFloat) {
        guard height.isFinite, height > 1, abs(height - openHeight) > 1 else { return }
        Self.lastOpenHeight = height
        withAnimation(Self.animation) {
            openHeight = height
        }
    }

    func setSafeArea(top: CGFloat, bottom: CGFloat) {
        if top > 0, abs(top - safeTop) > 0.5 { safeTop = top }
        if abs(bottom - safeBottom) > 0.5 { safeBottom = bottom }
    }

    private func settle(open: Bool) {
        withAnimation(Self.animation) {
            isOpen = open
            drag = 0
        }
    }
}

/// Moves and shrinks a page's picture into the room above the info panel as the panel rises. The page is built once
/// in init, so the finger only redraws this wrapper. A transform only: the page keeps its frame, so its picture
/// request doesn't start again and its zoom doesn't refit.
struct InfoRoom<Content: View>: View {
    let motion: InfoPanelMotion
    /// Width over height; nil for a video or a photo of no known size, which stays put.
    let aspect: Double?
    let content: Content

    init(motion: InfoPanelMotion, aspect: Double?, @ViewBuilder content: () -> Content) {
        self.motion = motion
        self.aspect = aspect
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let place = InfoPanelLayout.photoPlacement(
                pageWidth: Double(proxy.size.width), pageHeight: Double(proxy.size.height), aspect: aspect,
                safeTop: Double(motion.safeTop), panelHeight: Double(motion.openHeight),
                progress: Double(motion.progress))
            content
                .scaleEffect(CGFloat(place.scale), anchor: .center)
                .offset(y: CGFloat(place.offsetY))
        }
    }
}

/// Reads the window's own safe area, which the bars don't change, for InfoPanelMotion.
struct WindowInsetProbe: UIViewRepresentable {
    let onChange: (_ top: CGFloat, _ bottom: CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((CGFloat, CGFloat) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            report()
        }

        /// After the view update that moved it: SwiftUI state mustn't change in the middle of one.
        private func report() {
            guard let insets = window?.safeAreaInsets else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(insets.top, insets.bottom)
            }
        }
    }
}

/// What the info panel has read about the photos it showed, kept for the 40 most recent, so swiping back is
/// instant and a long session stays small. Keyed by version, so a photo edited in Photos reads again.
@MainActor
@Observable
final class PhotoFactsStore {
    struct Entry {
        /// What PhotoKit knew at once (the marks), then the file's facts. nil when the file couldn't be read.
        var facts: PhotoFacts?
        var factsRead = false
        var curves: HistogramCurves?
        var histogramSummary = ""
        /// Which ends of the histogram pile up, for the marks under it.
        var clipping = HistogramClipping()
        var pictureRead = false
        /// The place name's lines; nil until asked, empty when there was no answer.
        var place: [String]?
    }

    private static let kept = 40

    private(set) var entries: [AssetVersion: Entry] = [:]
    @ObservationIgnored private var order: [AssetVersion] = []

    func entry(for asset: PHAsset) -> Entry? {
        entries[AssetVersion(asset)]
    }

    /// Reads the file and the small picture together. Each part is read once per version; a cancelled read starts
    /// again the next time.
    func load(_ asset: PHAsset, manager: PHImageManager) async {
        let version = AssetVersion(asset)
        if entries[version] == nil {
            remember(version, Entry(facts: PhotoFacts(PhotoFactsReader.quickInput(for: asset))))
        }
        async let facts: Void = loadFacts(asset, version: version)
        async let picture: Void = loadPicture(asset, version: version, manager: manager)
        _ = await (facts, picture)
    }

    /// The place's name, for a photo with a location.
    func loadPlace(_ asset: PHAsset) async {
        let version = AssetVersion(asset)
        guard entries[version]?.place == nil, let coordinate = asset.location?.coordinate else { return }
        guard let lines = await PlaceLookup.shared.lines(for: coordinate) else { return }
        entries[version]?.place = lines
    }

    private func loadFacts(_ asset: PHAsset, version: AssetVersion) async {
        guard entries[version]?.factsRead == false else { return }
        let place = asset.location?.coordinate
        let facts = await Self.offMain { await PhotoFactsReader.read(asset, place: place) }
        guard !Task.isCancelled else { return }
        // A file that can't be read keeps what PhotoKit told: the marks stay, the rows that need the file go.
        if let facts { entries[version]?.facts = facts }
        entries[version]?.factsRead = true
    }

    private func loadPicture(_ asset: PHAsset, version: AssetVersion, manager: PHImageManager) async {
        guard entries[version]?.pictureRead == false else { return }
        let side = PhotoFactsReader.picturePixels
        var picture: CGImage?
        for await update in AssetRequests.fullImage(for: asset, pixelSize: CGSize(width: side, height: side),
                                                     manager: manager) {
            if case .value(let image, let isFinal) = update, isFinal { picture = image.cgImage }
        }
        guard !Task.isCancelled else { return }
        guard let picture else {
            entries[version]?.pictureRead = true
            return
        }
        let histogram = await Self.offMain { PhotoFactsReader.histogram(of: picture) }
        guard !Task.isCancelled else { return }
        if let histogram {
            let curves = HistogramCurves(histogram, channels: [.red, .green, .blue])
            entries[version]?.curves = curves.channels.isEmpty ? nil : curves
            entries[version]?.histogramSummary = HistogramSummary.summary(of: histogram)
            entries[version]?.clipping = HistogramClipping(histogram)
        }
        entries[version]?.pictureRead = true
    }

    private func remember(_ version: AssetVersion, _ entry: Entry) {
        entries[version] = entry
        order.append(version)
        if order.count > Self.kept {
            let dropped = order.removeFirst()
            entries[dropped] = nil
        }
    }

    /// Work off the main actor that stops with the task waiting for it.
    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T {
        let task = Task.detached(priority: .userInitiated, operation: work)
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

/// Whether a photo's tones pile up against black or white, as a camera's clipping warning says it.
struct HistogramClipping: Equatable, Sendable {
    var shadows = false
    var highlights = false

    /// Half a percent of the picture at the very end: less is a speck of black or a small light, more is detail
    /// lost there.
    private static let share = 0.005

    init() {}

    init(_ histogram: Histogram) {
        let total = Double(histogram.luma.reduce(0) { $0 + UInt64($1) })
        guard total > 0 else { return }
        func atEnd(_ bins: [UInt32], dark: Bool) -> Bool {
            guard let bin = dark ? bins.first : bins.last else { return false }
            return Double(bin) / total > Self.share
        }
        shadows = atEnd(histogram.luma, dark: true)
        // A channel alone at white is a colour clipped, which the luma would hide.
        highlights = [histogram.red, histogram.green, histogram.blue].contains { atEnd($0, dark: false) }
    }
}
