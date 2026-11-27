import SwiftUI
import CameraCore

/// The pages Settings can push, as values, so a search result and a menu row open a page the same way.
enum SettingsPage: Hashable {
    case photos, exposure, focus, viewfinder, night, video
    case accessibility, buttons, cameraControl, preserve
    case photoInfo, thisCamera

    var title: String {
        switch self {
        case .photos: return "Photos"
        case .exposure: return "Exposure"
        case .focus: return "Focus"
        case .viewfinder: return "Viewfinder"
        case .night: return "Night"
        case .video: return "Video"
        case .accessibility: return "Accessibility"
        case .buttons: return "Buttons and haptics"
        case .cameraControl: return "Camera Control"
        case .preserve: return "Preserve settings"
        case .photoInfo: return "Photo info"
        case .thisCamera: return "This camera"
        }
    }
}

/// Rows of the first page a search can scroll to. The search never pushes for these: they are already there.
enum SettingsAnchor: Hashable {
    case camera, setups, look, controls, about
}

/// The page for a value pushed onto the Settings stack.
struct SettingsDestination: View {
    let page: SettingsPage
    let model: CameraModel
    let locationAccess: LocationPermissionWatcher?

    var body: some View {
        switch page {
        case .photos: PhotoSettingsView(model: model, locationAccess: locationAccess)
        case .exposure: ExposureSettingsView(model: model)
        case .focus: FocusSettingsView(model: model)
        case .viewfinder: ViewfinderSettingsView(model: model)
        case .night: NightSettingsView(model: model)
        case .video: VideoSettingsView(model: model)
        case .accessibility: AccessibilitySettingsView(model: model)
        case .buttons: ButtonsAndHapticsView(model: model)
        case .cameraControl: CameraControlItemsView(model: model)
        case .preserve: PreserveSettingsView(model: model)
        case .photoInfo: PhotoInfoToolView()
        case .thisCamera: CapabilitiesView(capabilities: model.capabilities)
        }
    }
}

/// One searchable setting: its name as the row shows it, other words people might type for it, and where it lives.
/// A static list rather than a walk of the views, so it costs nothing until someone types.
struct SettingsSearchEntry: Identifiable {
    enum Target: Hashable {
        case page(SettingsPage)
        case anchor(SettingsAnchor)
    }

    /// Rows that only exist on some iPhones or behind another setting, so the search never leads to a page
    /// without them.
    enum Requirement {
        case silentShutter, cameraControl, quality, zebraLevel, peakingOptions, customRatio
    }

    let title: String
    let keywords: [String]
    let target: Target
    var requirement: Requirement? = nil

    var id: String { "\(title)|\(place)" }

    /// The page name shown beside the result.
    var place: String {
        switch target {
        case .page(let page): return page.title
        case .anchor: return "Settings"
        }
    }

    func matches(_ query: String) -> Bool {
        title.localizedStandardContains(query) || keywords.contains { $0.localizedStandardContains(query) }
    }

    @MainActor
    func isAvailable(on model: CameraModel) -> Bool {
        switch requirement {
        case nil: return true
        // Each mirrors the condition its page shows the row under.
        case .silentShutter:
            // PhotoSupport leaves the row out in VIDEO, where no photo capabilities are reported.
            return model.settings.mode != .video && model.capabilities.shutterSoundSuppressionSupported
        case .cameraControl: return model.capabilities.supportsCameraControls
        case .quality: return PhotoFormatChoice(model.settings.capture).takesQualitySlider
        case .zebraLevel: return model.settings.display.zebras
        case .peakingOptions: return model.settings.display.peaking != .off
        case .customRatio:
            let aspect = model.settings.capture.aspect
            return model.showsAdvancedSettings || !AspectRatio.presets.contains(where: { $0.matches(aspect) })
        }
    }
}

extension SettingsSearchEntry {
    private static func on(_ page: SettingsPage, _ title: String, _ keywords: [String] = [],
                           requirement: Requirement? = nil) -> SettingsSearchEntry {
        SettingsSearchEntry(title: title, keywords: keywords, target: .page(page), requirement: requirement)
    }

    private static func at(_ anchor: SettingsAnchor, _ title: String, _ keywords: [String] = [],
                           requirement: Requirement? = nil) -> SettingsSearchEntry {
        SettingsSearchEntry(title: title, keywords: keywords, target: .anchor(anchor), requirement: requirement)
    }

    /// In the order the pages come, so a word that hits several rows lists them as Settings does.
    static let all: [SettingsSearchEntry] = [
        at(.camera, "Aspect ratio", ["crop", "shape", "4:3", "16:9", "square", "1:1"]),
        at(.camera, "Custom ratio", ["aspect", "cinema"], requirement: .customRatio),
        at(.camera, "Grid", ["thirds", "lines"]),
        at(.camera, "Level", ["horizon", "tilt"]),
        at(.setups, "Custom setups", ["C1", "C2", "C3", "preset", "save", "recall"]),

        on(.photos, "Format", ["HEIF", "HEIC", "JPEG", "PNG", "TIFF", "file"]),
        on(.photos, "Quality", ["compression"], requirement: .quality),
        on(.photos, "RAW", ["ProRAW", "DNG"]),
        on(.photos, "Resolution", ["megapixels", "MP", "48", "12", "size"]),
        on(.photos, "Processing", ["noise", "sharpening", "Deep Fusion"]),
        on(.photos, "Prioritize faster shooting", ["speed", "burst"]),
        on(.photos, "Live Photo", ["motion"]),
        on(.photos, "Depth", ["portrait"]),
        on(.photos, "Constant color", ["flash"]),
        on(.photos, "Lens correction", ["distortion"]),
        on(.photos, "Mirror front camera", ["selfie", "flip"]),
        on(.photos, "Silent shutter", ["sound", "mute", "quiet"], requirement: .silentShutter),
        on(.photos, "Location tags", ["GPS", "place", "where"]),
        on(.photos, "Your name", ["artist", "author", "metadata"]),
        on(.photos, "Copyright", ["metadata"]),

        on(.exposure, "Slowest auto shutter", ["shutter limit", "blur"]),
        on(.exposure, "Metering area", ["meter"]),
        on(.exposure, "Face-driven exposure", ["faces"]),
        on(.exposure, "Aperture speed", ["iris"]),
        on(.exposure, "Low light boost", ["dark"]),
        on(.exposure, "Global tone mapping", ["tone"]),
        on(.exposure, "Video HDR", ["dynamic range"]),

        on(.focus, "Focus range", ["near", "far", "macro"]),
        on(.focus, "Smooth autofocus", ["AF"]),
        on(.focus, "Face-driven focus", ["faces", "AF"]),
        on(.focus, "Subject tracking", ["AF", "follow"]),
        on(.focus, "Focus magnifier", ["punch in", "zoom", "manual focus"]),

        on(.viewfinder, "Histogram", ["luma", "RGB"]),
        on(.viewfinder, "Exposure readout", ["readout", "ISO"]),
        on(.viewfinder, TopBarItem.steadySign.title, ["tripod", "shake", "still"]),
        on(.viewfinder, "Zebras", ["clipping", "highlights"]),
        on(.viewfinder, "Zebra level", ["clipping"], requirement: .zebraLevel),
        on(.viewfinder, "Focus peaking", ["edges", "manual focus"]),
        on(.viewfinder, "Peaking color", ["edges"], requirement: .peakingOptions),
        on(.viewfinder, "False color", ["exposure", "brightness"]),

        on(.night, "Tripod or handheld", ["stability", "night shot"]),
        on(.night, "Align frames", ["stack", "handheld"]),
        on(.night, "Maximum ISO", ["noise", "night shot"]),
        on(.night, "Blend", ["long exposure", "trails", "real"]),
        on(.night, "Bulb limit", ["long exposure", "bulb"]),
        on(.night, "Battery saver", ["dim", "screen"]),

        on(.video, "Resolution", ["video", "4K", "1080p", "HD"]),
        on(.video, "Frame rate", ["fps", "slow motion", "24", "30", "60"]),
        on(.video, "Codec", ["HEVC", "H.264", "ProRes"]),
        on(.video, "Color", ["HDR", "Log", "Dolby Vision"]),
        on(.video, "Stabilization", ["steady", "shake"]),
        on(.video, "Low light noise reduction", ["noise"]),
        on(.video, "Show shutter angle", ["180", "degrees"]),
        on(.video, "Record sound", ["audio", "microphone", "mic"]),
        on(.video, "Allow audio playback", ["music"]),
        on(.video, "Wind noise reduction", ["audio", "wind"]),

        at(.look, "Appearance", ["dark", "light", "theme"]),
        at(.look, "Accent color", ["color", "tint", "yellow"]),

        on(.buttons, "Use hardware buttons", ["volume", "shutter"]),
        on(.buttons, "Volume up", ["button"]),
        on(.buttons, "Volume down", ["button"]),
        on(.buttons, "Haptics", ["vibration", "feedback"]),
        on(.buttons, "Selection ticks", ["haptics"]),
        on(.buttons, "Zoom ticks", ["haptics"]),
        on(.cameraControl, "Camera Control", ["button", "slide"], requirement: .cameraControl),
        at(.controls, "Switch lenses while zooming", ["zoom", "lens"]),

        on(.accessibility, "Larger camera text", ["font", "size", "bigger"]),
        on(.accessibility, "Solid buttons", ["contrast", "background"]),
        on(.accessibility, "Reduce motion", ["animation"]),
        on(.accessibility, "Left-handed", ["hand", "layout"]),
        on(.accessibility, "Speak status", ["voice", "spoken", "countdown"]),

        on(.preserve, "Preserve settings", ["keep", "startup", "launch"]),
        on(.preserve, "Camera mode", ["keep", "startup"]),
        on(.preserve, "Lens and zoom", ["keep", "startup"]),

        on(.photoInfo, "Photo info", ["metadata", "EXIF", "remove location"]),
        on(.thisCamera, "This camera", ["capabilities", "formats", "lens"]),

        at(.about, "Version", ["about", "build"]),
        at(.about, "Reset all settings", ["defaults", "restore"]),
    ]
}

/// What a search shows in place of the form: every matching setting, each beside the page it is on. A tap opens the
/// page, or for a row of the first page, ends the search and scrolls to it.
struct SettingsSearchResults: View {
    let query: String
    let model: CameraModel
    let reveal: (SettingsAnchor) -> Void

    var body: some View {
        let hits = SettingsSearchEntry.all.filter { $0.matches(query) && $0.isAvailable(on: model) }
        List {
            ForEach(hits) { entry in
                switch entry.target {
                case .page(let page):
                    NavigationLink(value: page) {
                        LabeledContent(entry.title, value: entry.place)
                    }
                case .anchor(let anchor):
                    Button {
                        reveal(anchor)
                    } label: {
                        LabeledContent(entry.title, value: entry.place)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .overlay {
            if hits.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}
