import Foundation

/// A shooting setup the person saved, the way a camera's C1 to C3 keep one: what the camera takes pictures with,
/// not how the app looks or handles. Moments stay out of it (macro, AE lock, the focus magnifier, an open dial),
/// and so does what belongs to the person rather than the shot (their name, the copyright line, location tags,
/// front camera mirroring).
public struct CameraSetup: Codable, Hashable, Sendable {
    /// The person's name for it; empty until they give one.
    public var name: String
    public var mode: CaptureMode
    /// Where the lens was when the setup was saved. The model moves the lens itself on a recall, so `applied(to:)`
    /// leaves the settings' own lens and zoom alone.
    public var lensID: String?
    public var zoom: Double
    public var manual: ManualExposureSetting
    public var whiteBalance: WhiteBalanceSetting
    public var focus: FocusSetting
    public var capture: CaptureOptions
    public var exposure: ExposureOptions
    public var focusOptions: FocusOptions
    public var display: DisplaySettings
    public var night: NightSettings
    public var longExposure: LongExposureSettings
    public var video: VideoSettings

    public init(name: String, from settings: CameraSettings) {
        self.name = name
        mode = settings.mode
        lensID = settings.lensID
        zoom = settings.zoom
        manual = settings.manual
        whiteBalance = settings.whiteBalance
        focus = settings.focus
        capture = settings.capture
        exposure = settings.exposure
        focusOptions = settings.focusOptions
        display = settings.display
        night = settings.night
        longExposure = settings.longExposure
        video = settings.video
    }

    /// `base` with this setup's shooting fields. Lens and zoom stay as `base` has them: the model moves the lens
    /// itself. The person's name, copyright line, location tags and front camera mirroring stay as they are, and so
    /// does everything outside shooting (controls, interface, look, accessibility, top bar, startup, setups).
    public func applied(to base: CameraSettings) -> CameraSettings {
        var settings = base
        settings.mode = mode
        settings.manual = manual
        settings.whiteBalance = whiteBalance
        settings.focus = focus
        settings.capture = capture
        settings.capture.artist = base.capture.artist
        settings.capture.copyright = base.capture.copyright
        settings.capture.saveLocation = base.capture.saveLocation
        settings.capture.mirrorFront = base.capture.mirrorFront
        settings.exposure = exposure
        settings.focusOptions = focusOptions
        settings.display = display
        settings.night = night
        settings.longExposure = longExposure
        settings.video = video
        return settings
    }

    /// One line under the setup's name: "Manual night · 20s · ISO 3200 · 4000K · MF 97%", "Stars · 15s",
    /// "Night shot · 10s · Tripod", "Manual · 1/125 · ISO 100", "Photo · HEIF · RAW", "Video · 4K · 30 · HEVC".
    /// Values left to the camera are left out, so the line names what the setup sets.
    public var summary: String {
        var parts: [String]
        switch mode {
        case .night:
            parts = ["Night shot"]
            if let seconds = night.seconds {
                parts.append(Self.duration(seconds))
            }
            // Auto follows the motion sensor, the camera's own choice.
            if night.stability != .automatic {
                parts.append(night.stability.title)
            }
        case .long:
            let time = longExposure.bulb ? "Bulb" : Self.duration(longExposure.seconds)
            if longExposure.scene == .custom {
                parts = ["Manual night", time] + valuesSetByHand
            } else {
                // A scene sets the rest itself.
                parts = [longExposure.scene.title, time]
            }
        case .photo:
            parts = ["Photo"] + formatParts
        case .manual:
            parts = ["Manual"]
            if let shutter = manual.shutter {
                parts.append(ShutterSpeed(seconds: shutter).label)
            }
            parts += valuesSetByHand
        case .video:
            parts = ["Video", video.resolution.title]
            if video.frameRate.isFinite, video.frameRate > 0 {
                parts.append(Formatting.trimmed(video.frameRate, decimals: 2))
            }
            parts.append(video.codec.title)
            if video.colorMode != .sdr {
                parts.append(video.colorMode.title)
            }
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// A NIGHT time as its chip and dial write it: "1/8" below a second, where the time is a shutter speed, and
    /// "20s" or "30m" above. A tenth of a second would read 1/8 s as "0.1s".
    private static func duration(_ seconds: Double) -> String {
        seconds < 1 ? ShutterSpeed(seconds: seconds).label : Formatting.compactDuration(seconds)
    }

    /// MANUAL's values beside the shutter, which Manual night shares: the ones set by hand.
    private var valuesSetByHand: [String] {
        var parts: [String] = []
        if let iso = manual.iso {
            parts.append(ISOScale.label(iso))
        }
        if let aperture = manual.aperture {
            parts.append(ApertureScale.label(aperture))
        }
        if !whiteBalance.isAuto, let kelvin = whiteBalance.kelvinValue {
            parts.append(Formatting.kelvin(kelvin))
        }
        if let position = focus.lensPosition {
            parts.append(Formatting.lensPosition(position))
        }
        return parts
    }

    /// "HEIF High", "JPEG · ProRAW", "RAW only", "ProRAW only".
    private var formatParts: [String] {
        let choice = PhotoFormatChoice(capture)
        guard choice != .rawOnly else {
            return [capture.rawFormat == .proRAW ? "ProRAW only" : choice.title]
        }
        return capture.rawFormat == .none ? [choice.title] : [choice.title, capture.rawFormat.title]
    }

    enum CodingKeys: String, CodingKey {
        case name, mode, lensID, zoom, manual, whiteBalance, focus, capture, exposure, focusOptions, display, night
        case longExposure, video
    }

    /// Lenient like the settings, each part through the decoder the settings use: a Stars setup comes back with
    /// this version's recipe, and a capture with no format to save gets HEIF. A missing or unreadable value is the
    /// fresh install's.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CameraSetup(name: "", from: .default)
        name = c.value(.name, default: d.name)
        mode = c.value(.mode, default: d.mode)
        lensID = c.value(.lensID, default: d.lensID)
        zoom = c.value(.zoom, default: d.zoom)
        manual = c.value(.manual, default: d.manual)
        whiteBalance = c.value(.whiteBalance, default: d.whiteBalance)
        focus = c.value(.focus, default: d.focus)
        capture = c.value(.capture, default: d.capture)
        exposure = c.value(.exposure, default: d.exposure)
        focusOptions = c.value(.focusOptions, default: d.focusOptions)
        display = c.value(.display, default: d.display)
        night = c.value(.night, default: d.night)
        longExposure = c.value(.longExposure, default: d.longExposure)
        video = c.value(.video, default: d.video)
    }
}

/// The three custom setup slots. Always exactly three after decoding: a longer saved list is cut, a shorter one
/// padded, and a slot that can't be read is empty on its own.
public struct CameraSetups: Codable, Hashable, Sendable {
    public static let count = 3

    /// Slot 0 is C1. nil is an empty slot.
    public private(set) var slots: [CameraSetup?]

    public init() {
        slots = Array(repeating: nil, count: Self.count)
    }

    /// A slot outside the three reads as empty and takes no setup.
    public subscript(slot: Int) -> CameraSetup? {
        get { slots.indices.contains(slot) ? slots[slot] : nil }
        set {
            guard slots.indices.contains(slot) else { return }
            slots[slot] = newValue
        }
    }

    enum CodingKeys: String, CodingKey { case slots }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let saved = (try? c.decodeIfPresent([SavedSlot].self, forKey: .slots)) ?? []
        var slots = saved.prefix(Self.count).map(\.setup)
        slots += Array(repeating: nil, count: Self.count - slots.count)
        self.slots = slots
    }
}

/// One entry of the saved slots: the setup, or nil for an empty slot and for anything this version can't read.
private struct SavedSlot: Decodable {
    let setup: CameraSetup?

    init(from decoder: Decoder) throws {
        setup = try? CameraSetup(from: decoder)
    }
}
