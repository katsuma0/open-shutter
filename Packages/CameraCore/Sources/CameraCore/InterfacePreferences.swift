import Foundation

// How the app looks and handles, as opposed to how it takes pictures: the look of Settings, accessibility, the top
// bar's buttons, what the hardware buttons do, how haptics feel and what the camera opens on. None of it is in
// copyAdvancedFields, so bringing back a save from the earlier simple interface leaves all of it as it was.

// MARK: - Appearance

/// Light or dark for Settings and the lists it leads to. The camera stays dark either way.
public enum AppearanceScheme: String, Codable, Sendable, CaseIterable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return "Match iPhone"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// The color that marks what is on or set by hand. Red is left out because it means recording and warnings, white
/// and gray because they would read as automatic, and indigo because no shade of it stays readable on the camera's
/// dark glass.
public enum AccentChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    case yellow, orange, green, teal, blue, purple, pink

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .green: return "Green"
        case .teal: return "Teal"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        }
    }

    /// On black, on the camera's glass and in dark sheets. Each stays readable as small text on the lightest dark
    /// backing (#2C2C2E), and black text on it stays readable too, so text on an accent fill is black on the camera.
    /// Yellow is Apple Camera's, the color the app has always used. Blue, purple and pink are Apple's high contrast
    /// shades: the standard ones fall short on dark glass.
    public var camera: RGBA8 {
        switch self {
        case .yellow: return RGBA8(r: 0xFF, g: 0xD6, b: 0x0A)
        case .orange: return RGBA8(r: 0xFF, g: 0x9F, b: 0x0A)
        case .green: return RGBA8(r: 0x30, g: 0xD1, b: 0x58)
        case .teal: return RGBA8(r: 0x40, g: 0xC8, b: 0xE0)
        case .blue: return RGBA8(r: 0x40, g: 0x9C, b: 0xFF)
        case .purple: return RGBA8(r: 0xDA, g: 0x8F, b: 0xFF)
        case .pink: return RGBA8(r: 0xFF, g: 0x64, b: 0x82)
        }
    }

    /// In light sheets, where the camera shades wash out: readable on white cells and on the grouped gray
    /// background, with white text on its fills.
    public var lightSheet: RGBA8 {
        switch self {
        case .yellow: return RGBA8(r: 0x94, g: 0x6F, b: 0x00)
        case .orange: return RGBA8(r: 0xB3, g: 0x53, b: 0x00)
        case .green: return RGBA8(r: 0x1E, g: 0x7E, b: 0x34)
        case .teal: return RGBA8(r: 0x00, g: 0x7A, b: 0x8F)
        case .blue: return RGBA8(r: 0x00, g: 0x40, b: 0xDD)
        case .purple: return RGBA8(r: 0x89, g: 0x44, b: 0xAB)
        case .pink: return RGBA8(r: 0xD3, g: 0x0F, b: 0x45)
        }
    }
}

public struct AppearanceOptions: Codable, Hashable, Sendable {
    public var scheme: AppearanceScheme = .system
    public var accent: AccentChoice = .yellow

    public init() {}

    enum CodingKeys: String, CodingKey { case scheme, accent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppearanceOptions()
        scheme = c.value(.scheme, default: d.scheme)
        accent = c.value(.accent, default: d.accent)
    }
}

// MARK: - Accessibility

/// Small options that make the camera easier to see, reach and follow. The system's Bold Text, Reduce Transparency
/// and VoiceOver apply without any of them.
public struct AccessibilityOptions: Codable, Hashable, Sendable {
    /// Text on the camera screen about a fifth bigger. Camera labels have fixed sizes, so the system text size
    /// doesn't reach them.
    public var largerLabels: Bool = false
    /// Camera buttons on a dark backing instead of glass, so they stay readable over a bright scene.
    public var solidControls: Bool = false
    /// Icons switch instead of turning and panels fade instead of sliding. The system's Reduce Motion does the same
    /// whatever this says.
    public var reduceMotion: Bool = false
    /// The flip button on the left and the thumbnail on the right, the brightness control left of the lenses.
    public var leftHanded: Bool = false
    /// Says the countdown out loud, and when a long shot starts and ends.
    public var speakStatus: Bool = false

    public init() {}

    enum CodingKeys: String, CodingKey { case largerLabels, solidControls, reduceMotion, leftHanded, speakStatus }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AccessibilityOptions()
        largerLabels = c.value(.largerLabels, default: d.largerLabels)
        solidControls = c.value(.solidControls, default: d.solidControls)
        reduceMotion = c.value(.reduceMotion, default: d.reduceMotion)
        leftHanded = c.value(.leftHanded, default: d.leftHanded)
        speakStatus = c.value(.speakStatus, default: d.speakStatus)
    }
}

// MARK: - Buttons and haptics

/// How firm the taps feel. Haptics off stays the `haptics` switch, so a save from before means the same.
public enum HapticStrength: String, Codable, Sendable, CaseIterable, Identifiable {
    case light, normal, strong

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .light: return "Light"
        case .normal: return "Normal"
        case .strong: return "Strong"
        }
    }
}

/// Where turning the zoom ticks under the finger.
public enum ZoomTickStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case everyStep, lensValues

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .everyStep: return "Every step"
        case .lensValues: return "Lens values only"
        }
    }
}

/// What a volume button does in the camera. During a timer, a long exposure, an intervalometer or a bracket, any
/// button stops the shot whatever it is set to, so a shot can always be ended without touching the phone.
public enum HardwareButtonAction: String, Codable, Sendable, CaseIterable, Identifiable {
    case shutter, zoomIn, zoomOut, brighter, darker, nextLens

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .shutter: return "Shutter"
        case .zoomIn: return "Zoom in"
        case .zoomOut: return "Zoom out"
        case .brighter: return "Brighter"
        case .darker: return "Darker"
        case .nextLens: return "Next lens"
        }
    }
}

// MARK: - Top bar

/// A button the top bar can carry. The app's bar is fixed now: flash, shape, timer, format, histogram (in NIGHT the
/// night shot's stability), AE lock and Live Photo, with the gear. It still names its buttons by these cases and asks
/// each where it applies; the rest are the ones the bar could carry while people arranged it themselves. Saves hold
/// these names, so a new case goes at the end.
public enum TopBarItem: String, Codable, Sendable, CaseIterable, Identifiable {
    case flash, livePhoto, timer, aspect, grid, level, location, quietShutter, batterySaver, nightDuration
    case raw, exposureLock, format, resolution, processing, histogram, zebras, peaking, falseColor
    case whiteBalance, stabilization, sound
    /// NIGHT's button in the histogram's slot: whether the night shot plans for a hand, a tripod, or follows the
    /// motion sensor.
    case nightStability

    public var id: String { rawValue }

    /// The modes where it has something to do. What depends on the camera or on other settings at the moment
    /// (a flash on this lens, Live Photo support, a bulb shot) is for the app's `isAvailable` to say.
    public func applies(in mode: CaptureMode) -> Bool {
        switch self {
        case .flash:
            // In VIDEO it works the flashlight.
            return mode == .photo || mode == .manual || mode == .video
        case .livePhoto:
            return mode == .photo
        case .quietShutter, .raw, .resolution, .processing:
            return mode == .photo || mode == .manual
        case .timer, .aspect, .format:
            return mode != .video
        case .batterySaver:
            return mode == .night || mode == .long
        case .nightDuration:
            return mode == .night
        case .nightStability:
            // Only the night shot plans for a hand or a tripod; the long exposure scenes have their own recipes.
            return mode == .night
        case .histogram:
            return mode.hasHistogram
        case .stabilization, .sound:
            return mode == .video
        case .grid, .level, .location, .exposureLock, .zebras, .peaking, .falseColor, .whiteBalance:
            return true
        }
    }

    /// Its name, which the bar's buttons give VoiceOver.
    public var title: String {
        switch self {
        case .flash: return "Flash"
        case .livePhoto: return "Live Photo"
        case .timer: return "Timer"
        case .aspect: return "Aspect ratio"
        case .grid: return "Grid"
        case .level: return "Level"
        case .location: return "Location tags"
        case .quietShutter: return "Silent shutter"
        case .batterySaver: return "Battery saver"
        case .nightDuration: return "Night duration"
        case .raw: return "RAW"
        case .exposureLock: return "AE lock"
        case .format: return "Format"
        case .resolution: return "Resolution"
        case .processing: return "Processing"
        case .histogram: return "Histogram"
        case .zebras: return "Zebras"
        case .peaking: return "Focus peaking"
        case .falseColor: return "False color"
        case .whiteBalance: return "White balance"
        case .stabilization: return "Stabilization"
        case .sound: return "Sound"
        // Settings > Night names it so too.
        case .nightStability: return "Stability"
        }
    }

    /// SF Symbols for the button where it is listed, newest first: a name newer than the phone's iOS draws nothing,
    /// so the next one stands in. On the bar, a button that shows its state draws that instead (bolt.slash, "16:9",
    /// the zebra stripes SF Symbols doesn't have).
    public var symbolNames: [String] {
        switch self {
        case .flash: return ["bolt"]
        case .livePhoto: return ["livephoto"]
        case .timer: return ["timer"]
        case .aspect: return ["aspectratio", "rectangle"]
        case .grid: return ["square.grid.3x3", "grid"]
        case .level: return ["level"]
        case .location: return ["location"]
        case .quietShutter: return ["speaker.slash"]
        case .batterySaver: return ["moon.zzz", "battery.100percent", "battery.100"]
        case .nightDuration: return ["moon.fill"]
        case .raw: return ["r.square"]
        case .exposureLock: return ["lock"]
        case .format: return ["photo"]
        case .resolution: return ["arrow.up.left.and.arrow.down.right"]
        case .processing: return ["wand.and.stars"]
        case .histogram: return ["chart.bar.fill"]
        case .zebras: return ["line.diagonal"]
        case .peaking: return ["scope"]
        case .falseColor: return ["paintpalette"]
        case .whiteBalance: return ["thermometer.sun", "sun.max"]
        case .stabilization: return ["figure.walk"]
        case .sound: return ["mic"]
        // SF Symbols has no tripod, so the bar draws one for Tripod; the hand stands for the button where a symbol
        // has to.
        case .nightStability: return ["hand.raised"]
        }
    }
}

/// The arrangement the top bar had while people picked its buttons: seven equal slots, three for the left side, a
/// chevron, two for the right side and the gear. The app's bar is fixed now and no longer reads this. It stays in the
/// settings so saves from that time still decode.
public struct TopBarOptions: Codable, Hashable, Sendable {
    /// The most a side keeps, so a damaged save can't grow without end.
    public static let storedLimit = 8

    /// Left of the chevron, the first nearest the edge.
    public var leading: [TopBarItem] = [.flash]
    /// Between the chevron and the gear. With Flash on the left, the bar as it was before it could be changed.
    public var trailing: [TopBarItem] = [.raw, .livePhoto]

    public init() {}

    /// The sides as given, cleaned as a save is: each button once, on the side where it comes first (the left
    /// counts first), at most `storedLimit` a side.
    public init(leading: [TopBarItem], trailing: [TopBarItem]) {
        (self.leading, self.trailing) = Self.cleaned(leading, trailing)
    }

    enum CodingKeys: String, CodingKey { case leading, trailing }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TopBarOptions()
        (leading, trailing) = Self.cleaned(Self.items(c, .leading) ?? d.leading, Self.items(c, .trailing) ?? d.trailing)
    }

    /// One saved side, read by name: a button from a later version, or renamed since, drops out alone instead of
    /// costing the whole side. nil when the side is missing or isn't a list, which leaves it at its default.
    private static func items(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [TopBarItem]? {
        guard let names = try? c.decodeIfPresent([StoredName].self, forKey: key) else { return nil }
        return names.compactMap(\.item)
    }

    private static func cleaned(_ leading: [TopBarItem], _ trailing: [TopBarItem]) -> ([TopBarItem], [TopBarItem]) {
        var placed = Set<TopBarItem>()
        var sides: [[TopBarItem]] = []
        for items in [leading, trailing] {
            var kept: [TopBarItem] = []
            for item in items where kept.count < storedLimit && placed.insert(item).inserted {
                kept.append(item)
            }
            sides.append(kept)
        }
        return (sides[0], sides[1])
    }
}

/// One entry of a saved list of buttons: the button, or nil for anything this version can't read.
private struct StoredName: Decodable {
    let item: TopBarItem?

    init(from decoder: Decoder) throws {
        item = (try? decoder.singleValueContainer().decode(String.self)).flatMap(TopBarItem.init(rawValue:))
    }
}

// MARK: - Startup

/// What the camera keeps from last time when it opens. All on is how it has always worked; each one off starts its
/// part where a fresh install does: PHOTO, the main lens at 1x, brightness at zero.
public struct StartupOptions: Codable, Hashable, Sendable {
    /// Opens in the mode it was left in.
    public var keepMode: Bool = true
    /// Opens on the lens and zoom it was left on.
    public var keepLensAndZoom: Bool = true
    /// Keeps the brightness it was left at, NIGHT's included.
    public var keepBrightness: Bool = true

    public init() {}

    enum CodingKeys: String, CodingKey { case keepMode, keepLensAndZoom, keepBrightness }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StartupOptions()
        keepMode = c.value(.keepMode, default: d.keepMode)
        keepLensAndZoom = c.value(.keepLensAndZoom, default: d.keepLensAndZoom)
        keepBrightness = c.value(.keepBrightness, default: d.keepBrightness)
    }
}

extension CameraSettings {
    /// These settings as the camera opens with them: what the startup options don't keep goes back to where a fresh
    /// install starts.
    public func applyingStartupOptions() -> CameraSettings {
        var settings = self
        let fresh = CameraSettings.default
        if !startup.keepMode {
            settings.mode = fresh.mode
        }
        if !startup.keepLensAndZoom {
            settings.lensID = fresh.lensID
            settings.zoom = fresh.zoom
        }
        if !startup.keepBrightness {
            settings.manual.bias = fresh.manual.bias
            settings.night.biasEV = fresh.night.biasEV
        }
        return settings
    }
}
