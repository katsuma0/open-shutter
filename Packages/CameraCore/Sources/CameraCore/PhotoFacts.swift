import Foundation

/// What the gallery's info panel says about one photo, as finished text. The app reads PhotoKit and ImageIO into an
/// `Input` of plain values; every rule for how a value reads lives here, where it is tested.
///
/// The panel describes the file the camera saved: its type, exposure, size and bytes. Numbers are written the app's
/// way whatever the phone's region, "." before decimals and "," between thousands, as `Formatting` writes them.
public struct PhotoFacts: Equatable, Sendable {
    /// A number and its unit, drawn apart so the unit can be set in small capitals.
    public struct Measure: Equatable, Sendable {
        /// "1/83", "250", "6.83".
        public var value: String
        /// "SEC", "ISO", "MB", "mm", "m", "ft". Empty for a time that names its own units ("2m 5s").
        public var unit: String
        /// The unit goes before the number, as cameras write "ISO 250".
        public var unitFirst = false

        public init(value: String, unit: String, unitFirst: Bool = false) {
            self.value = value
            self.unit = unit
            self.unitFirst = unitFirst
        }
    }

    /// The type of the file the camera saved.
    public enum FileFormat: String, Sendable {
        case heif, jpeg, png, tiff, raw, other
    }

    /// The header's marks, left to right.
    public enum Mark: Equatable, Sendable {
        case depth, live, hdr, edited
        /// A file type's badge: "HEIF", "JPEG", "PNG", "TIFF", "RAW", "ProRAW".
        case format(String)
    }

    /// The colour space a photo was saved in, as its badge names it.
    public enum ColorSpace: Equatable, Sendable {
        case displayP3, sRGB
        /// One the badge spells out: "Rec. 2020", "Adobe RGB".
        case named(String)

        /// "P3", "sRGB", "Rec. 2020", "Adobe RGB".
        public var title: String {
            switch self {
            case .displayP3: return "P3"
            case .sRGB: return "sRGB"
            case .named(let name): return name
            }
        }
    }

    /// How a stacked shot was made, under the device: NIGHT's frames or a long exposure's scene.
    public struct NightLine: Equatable, Sendable {
        /// "Night · 30 frames × 1 s", "Light trails · 120 frames × 1/4 s", "Long exposure".
        public var text: String
        /// The scene, for its symbol: Custom for a long exposure without one of the presets, and nil only for the
        /// night shot, which draws the moon.
        public var scene: LongExposureScene?

        public init(text: String, scene: LongExposureScene? = nil) {
            self.text = text
            self.scene = scene
        }
    }

    /// The height of the place, in metres with feet beside, as the panel shows both.
    public struct Altitude: Equatable, Sendable {
        public var metres: Measure
        public var feet: Measure

        public init(metres: Measure, feet: Measure) {
            self.metres = metres
            self.feet = feet
        }
    }

    /// What the app read from the photo, as plain values. Everything starts unknown, so a reader fills in only what
    /// the file has and the rest stays out of the panel.
    public struct Input: Equatable, Sendable {
        /// The primary original's type.
        public var format: FileFormat = .other
        /// A DNG's TIFF PhotometricInterpretation: 34892 (linear, ProRAW) is true, 32803 (the sensor's pattern) false.
        public var linearRAW: Bool? = nil
        /// A RAW file saved beside the HEIF or JPEG, as one picture.
        public var hasRAWCompanion = false
        public var isLive = false
        /// A gain map in the file, or a photo Photos marks HDR.
        public var hasGainMap = false
        public var hasDepth = false
        /// Edited in Photos since. The numbers stay the camera's.
        public var isEdited = false
        /// TIFF Make and Model.
        public var make: String? = nil
        public var model: String? = nil
        /// EXIF LensModel, "iPhone 15 Pro Max back triple camera 15.66mm f/2.8".
        public var lensModel: String? = nil
        /// EXIF FocalLenIn35mmFilm.
        public var focalLength35: Double? = nil
        /// EXIF FNumber.
        public var fNumber: Double? = nil
        /// EXIF ISOSpeedRatings, the first.
        public var iso: Double? = nil
        /// EXIF ExposureTime, the light time: one frame's for NIGHT, Blur and Trails, every frame's together for Real.
        /// The night line gives the frames.
        public var exposureSeconds: Double? = nil
        /// EXIF WhiteBalance: 0 auto, 1 manual.
        public var exifWhiteBalance: Int? = nil
        /// The embedded colour profile's name, "Display P3".
        public var profileName: String? = nil
        /// EXIF ColorSpace: 1 sRGB, 65535 uncalibrated (what a Display P3 photo says).
        public var exifColorSpace: Int? = nil
        /// The stored pixels, before the orientation turns them.
        public var pixelWidth: Int? = nil
        public var pixelHeight: Int? = nil
        /// The EXIF orientation, 1 to 8.
        public var orientation: Int? = nil
        /// The original file's size in bytes.
        public var fileBytes: Int64? = nil
        /// EXIF GPS Altitude and AltitudeRef (1 is below sea level).
        public var altitude: Double? = nil
        public var altitudeRef: Int? = nil
        /// EXIF GPS ImgDirection: where the camera faced, in degrees.
        public var heading: Double? = nil
        /// The app's own XMP fields, as written.
        public var app: [ShotXMP.Field: String] = [:]

        public init() {}
    }

    /// The header's marks: depth, Live, HDR, Edited, then the file type and a RAW saved beside it.
    public var marks: [Mark]
    /// "iPhone 15 Pro Max", "Canon EOS R5".
    public var device: String?
    /// "Telephoto camera": which of the phone's cameras, never Apple's long lens model.
    public var lens: String?
    public var night: NightLine?
    /// The 35 mm equivalent: "120" "mm".
    public var focal: Measure?
    /// "ƒ/2.8".
    public var aperture: String?
    /// "ISO" "250", unit first.
    public var iso: Measure?
    /// "1/83" "SEC", "2.5" "SEC", "2m 5s" with no unit.
    public var shutter: Measure?
    /// "AWB", "5600K", "Daylight", "Manual".
    public var whiteBalance: String?
    public var colorSpace: ColorSpace?
    /// "4,032 × 3,024", turned as the photo shows.
    public var dimensions: String?
    /// "12.2" "MP".
    public var megapixels: Measure?
    /// "6.83" "MB".
    public var fileSize: Measure?
    public var altitude: Altitude?
    /// Where the camera faced, 0..<360 degrees; nil when unknown.
    public var heading: Double?

    public init(_ input: Input) {
        marks = Self.marks(input)
        device = Self.device(make: input.make, model: input.model)
        lens = Self.lens(input)
        night = Self.nightLine(input.app)
        focal = Self.positive(input.focalLength35).map { Measure(value: FactNumbers.whole($0), unit: "mm") }
        aperture = Self.positive(input.fNumber).map(ApertureScale.label)
        iso = Self.positive(input.iso).map { Measure(value: FactNumbers.whole($0), unit: "ISO", unitFirst: true) }
        shutter = Self.positive(input.exposureSeconds).map { seconds in
            let written = Self.time(seconds)
            return Measure(value: written.value, unit: written.namesItsUnits ? "" : "SEC")
        }
        whiteBalance = Self.whiteBalance(input)
        colorSpace = Self.colorSpace(profileName: input.profileName, exif: input.exifColorSpace)
        let size = Self.shownSize(input)
        dimensions = size.map { FactNumbers.grouped($0.width) + " \u{00D7} " + FactNumbers.grouped($0.height) }
        megapixels = size.map { Self.megapixels(width: $0.width, height: $0.height) }
        fileSize = input.fileBytes.flatMap(Self.fileSize)
        altitude = Self.altitude(input.altitude, ref: input.altitudeRef)
        heading = Self.heading(input.heading)
    }

    // MARK: - Library and place

    /// "214 photos, 6 videos", "1 photo", "3 videos"; "" for none.
    public static func libraryCount(photos: Int, videos: Int) -> String {
        var parts: [String] = []
        if photos > 0 {
            parts.append(FactNumbers.grouped(photos) + (photos == 1 ? " photo" : " photos"))
        }
        if videos > 0 {
            parts.append(FactNumbers.grouped(videos) + (videos == 1 ? " video" : " videos"))
        }
        return parts.joined(separator: ", ")
    }

    /// Before iOS 26 (CLPlacemark parts): ["Grant Park", "South Loop, Chicago, IL", "United States"], empty parts
    /// and repeats left out. `name` is the place itself (an area of interest, else the placemark's name); a name that
    /// only says the city is left out, as the line under it says it already.
    public static func placeLines(name: String?, subLocality: String?, locality: String?,
                                  administrativeArea: String?, country: String?) -> [String] {
        var area: [String] = []
        for part in [subLocality, locality, administrativeArea].compactMap(cleaned)
        where !area.contains(where: { same($0, part) }) {
            area.append(part)
        }
        return placeLines(name: name, unlessCalled: [locality], over: [area.joined(separator: ", "), country])
    }

    /// iOS 26 (MKMapItem): name, cityWithContext(.short), regionName, with the same clean-up. A name that only says
    /// the city, or a region the city line ends with ("Paris, France" over "France"), is left out.
    public static func placeLines(name: String?, city: String?, region: String?) -> [String] {
        // "Chicago, IL" names Chicago, so a place called Chicago is already there.
        let cityName = city?.split(separator: ",").first.map(String.init)
        return placeLines(name: name, unlessCalled: [city, cityName], over: [city, region])
    }

    /// The place's own name, unless it is only one of `cities`, then the lines under it: without blanks, without a
    /// line that repeats the one above it, and without one the line above already ends with.
    private static func placeLines(name: String?, unlessCalled cities: [String?], over lines: [String?]) -> [String] {
        let place = cleaned(name).flatMap { place in cities.compactMap(cleaned).contains { same($0, place) } ? nil : place }
        var kept: [String] = []
        for line in ([place] + lines).compactMap(cleaned) {
            if let last = kept.last, same(last, line) || last.lowercased().hasSuffix(", " + line.lowercased()) {
                continue
            }
            kept.append(line)
        }
        return kept
    }

    // MARK: - Rules

    /// Depth, Live, HDR and Edited first, as the icons and badges read left to right, then the file type and a RAW
    /// file saved beside it.
    private static func marks(_ input: Input) -> [Mark] {
        var marks: [Mark] = []
        if input.hasDepth { marks.append(.depth) }
        if input.isLive { marks.append(.live) }
        if input.hasGainMap { marks.append(.hdr) }
        if input.isEdited { marks.append(.edited) }
        switch input.format {
        case .heif: marks.append(.format("HEIF"))
        case .jpeg: marks.append(.format("JPEG"))
        case .png: marks.append(.format("PNG"))
        case .tiff: marks.append(.format("TIFF"))
        // A DNG says which kind it is: ProRAW is Apple's processed picture, RAW the sensor's own data. One that
        // doesn't say is the plain kind.
        case .raw: marks.append(.format(input.linearRAW == true ? "ProRAW" : "RAW"))
        case .other: break
        }
        // The companion's file isn't opened, so a ProRAW beside a HEIF reads RAW too.
        if input.hasRAWCompanion, input.format != .raw {
            marks.append(.format("RAW"))
        }
        return marks
    }

    /// The model alone when it names the phone or carries the make already ("iPhone 17 Pro", "Canon EOS R5"), else
    /// make and model ("Sony ILCE-7M4"). Some makes are a company's whole name, so the model only has to start with
    /// its first word ("NIKON D850" from "NIKON CORPORATION").
    private static func device(make: String?, model: String?) -> String? {
        let make = cleaned(make)
        guard let model = cleaned(model) else { return make }
        guard let make else { return model }
        let lowerMake = make.lowercased()
        let lowerModel = model.lowercased()
        let firstWord = lowerMake.split(separator: " ").first.map(String.init) ?? lowerMake
        if firstWord == "apple" || lowerModel.hasPrefix(lowerMake) || lowerModel == firstWord
            || lowerModel.hasPrefix(firstWord + " ") {
            return model
        }
        return make + " " + model
    }

    /// Which of the phone's cameras, by the name its picker uses. The app's XMP says it; a photo without it goes by
    /// Apple's lens model for the front camera and by the 35 mm focal length for the back ones. Those names are the
    /// iPhone's, so another make's lens gets none.
    private static func lens(_ input: Input) -> String? {
        if let written = input.app[.lens].flatMap(cleaned), let kind = LensKind(rawValue: written) {
            return lensName(kind)
        }
        if let model = input.lensModel, model.lowercased().contains("front") {
            return lensName(.front)
        }
        if let make = cleaned(input.make), !make.lowercased().hasPrefix("apple") {
            return nil
        }
        guard let focal = positive(input.focalLength35) else { return nil }
        if focal < 20 { return lensName(.ultraWide) }
        return lensName(focal < 40 ? .wide : .telephoto)
    }

    private static func lensName(_ kind: LensKind) -> String {
        switch kind {
        case .ultraWide: return "Ultra Wide camera"
        case .wide: return "Main camera"
        case .telephoto: return "Telephoto camera"
        case .front: return "Front camera"
        case .external: return "External camera"
        }
    }

    /// NIGHT's and the long exposure's shots: what they were and how many frames of what time made them. EXIF's
    /// time is one frame's for NIGHT, Blur and Trails, so this is where the length shows. One frame, or a count that
    /// can't be read, leaves the title alone. A bulb shot adds nothing: its frame count says how long it ran.
    private static func nightLine(_ app: [ShotXMP.Field: String]) -> NightLine? {
        guard let mode = app[.mode].flatMap(cleaned).flatMap(CaptureMode.init(rawValue:)), mode.usesStacking else {
            return nil
        }
        let title: String
        let scene: LongExposureScene?
        if mode == .night {
            title = "Night"
            scene = nil
        } else {
            // A scene this version can't read, or none, was the person's own setup.
            let picked = app[.scene].flatMap(cleaned).flatMap(LongExposureScene.init(rawValue:)) ?? .custom
            title = picked == .custom ? "Long exposure" : picked.title
            scene = picked
        }
        guard let count = app[.frameCount].flatMap(cleaned).flatMap({ Int($0) }), count > 1 else {
            return NightLine(text: title, scene: scene)
        }
        var text = title + " \u{00B7} " + FactNumbers.grouped(count) + " frames"
        if let frame = app[.frameSeconds].flatMap(cleaned).flatMap({ Double($0) }), let seconds = positive(frame) {
            let frameTime = Self.time(seconds)
            text += " \u{00D7} " + frameTime.value + (frameTime.namesItsUnits ? "" : " s")
        }
        return NightLine(text: text, scene: scene)
    }

    /// An exposure time as cameras write it: "1/83" below 0.4 s, one decimal below 10 s ("2.5"), whole seconds below
    /// 99.5 s ("30"), and past that minutes and seconds ("2m 5s"), which name their own units.
    private static func time(_ seconds: Double) -> (value: String, namesItsUnits: Bool) {
        if seconds < 0.4 {
            return ("1/" + FactNumbers.whole(1 / seconds), false)
        }
        if seconds < 10 {
            return (FactNumbers.fixed(seconds, places: 1, trimsZeros: true), false)
        }
        if seconds < 99.5 {
            return (FactNumbers.whole(seconds), false)
        }
        return (Formatting.compactDuration(seconds), true)
    }

    /// The app's XMP first, which knows a preset from a Kelvin value; EXIF only tells auto from manual.
    private static func whiteBalance(_ input: Input) -> String? {
        if let written = input.app[.whiteBalance].flatMap(cleaned) {
            if written == "auto" { return "AWB" }
            if written == "kelvin",
               let kelvin = input.app[.kelvin].flatMap(cleaned).flatMap({ Double($0) }).flatMap(positive) {
                return Formatting.kelvin(kelvin)
            }
            if let preset = WhiteBalancePreset(rawValue: written) {
                return preset == .auto ? "AWB" : preset.title
            }
        }
        switch input.exifWhiteBalance {
        case 0: return "AWB"
        case 1: return "Manual"
        default: return nil
        }
    }

    /// The embedded profile's name says the most; EXIF ColorSpace only knows sRGB (and Adobe RGB, as some cameras
    /// write it). A space with no short name, or none known, leaves the badge out.
    private static func colorSpace(profileName: String?, exif: Int?) -> ColorSpace? {
        if let name = cleaned(profileName)?.lowercased() {
            if name.contains("p3") { return .displayP3 }
            if name.contains("srgb") { return .sRGB }
            if name.contains("2020") || name.contains("2100") { return .named("Rec. 2020") }
            if name.replacingOccurrences(of: " ", with: "").contains("adobergb") { return .named("Adobe RGB") }
        }
        switch exif {
        case 1: return .sRGB
        case 2: return .named("Adobe RGB")
        default: return nil
        }
    }

    /// Width and height as the photo shows: orientations 5 to 8 turn it a quarter, so the two swap.
    private static func shownSize(_ input: Input) -> (width: Int, height: Int)? {
        guard let width = input.pixelWidth, let height = input.pixelHeight, width > 0, height > 0 else { return nil }
        if let orientation = input.orientation, (5...8).contains(orientation) {
            return (height, width)
        }
        return (width, height)
    }

    /// One decimal: "12.2", "48.8". Not `Formatting.megapixels`, which rounds 12.19 down to "12 MP" on purpose for
    /// the camera's menus; here the photo's own size is the point.
    private static func megapixels(width: Int, height: Int) -> Measure {
        let value = Double(width) * Double(height) / 1_000_000
        // A picture too small for one decimal still gets a number that isn't zero.
        let text = value < 0.05 ? FactNumbers.significant(value, digits: 1) : FactNumbers.fixed(value, places: 1)
        return Measure(value: text, unit: "MP")
    }

    /// Three significant figures in decimal units, as Files and Photos count: "6.83" MB, "845" KB, "1.23" GB. A
    /// size that would round up to 1000 of a unit takes the next unit, so 999,700 bytes reads "1" MB. Worked out in
    /// whole bytes, so a size right on a boundary rounds the same way every time.
    private static func fileSize(_ bytes: Int64) -> Measure? {
        guard bytes > 0 else { return nil }
        let count = UInt64(bytes)
        let names = ["KB", "MB", "GB"]
        var unit: UInt64 = 1
        var index = -1
        while index < names.count - 1, (count + unit / 2) / unit >= 1000 {
            unit *= 1000
            index += 1
        }
        guard index >= 0 else { return Measure(value: String(count), unit: "B") }
        // Two decimals below 10 of the unit, one below 100, none above: the first that rounds under 1000 steps.
        for places in [2, 1] {
            let step = unit / FactNumbers.power(places)
            let steps = (count + step / 2) / step
            if steps < 1000 {
                return Measure(value: FactNumbers.decimal(steps, places: places, trimsZeros: true), unit: names[index])
            }
        }
        return Measure(value: FactNumbers.decimal((count + unit / 2) / unit, places: 0), unit: names[index])
    }

    /// Metres with feet beside, three significant figures below 1000 ("5.56", "563") and whole above ("1,235").
    /// Nothing for a height no phone was at, which is a file's error.
    private static func altitude(_ value: Double?, ref: Int?) -> Altitude? {
        guard let value, let metres = MetadataFormat.signedAltitude(value, ref: ref), abs(metres) < 20_000 else {
            return nil
        }
        func text(_ height: Double) -> String {
            // GPS heights aren't good to a centimetre, so two decimals at most.
            abs(height) >= 1000 ? FactNumbers.fixed(height, places: 0)
                : FactNumbers.significant(height, digits: 3, maxPlaces: 2)
        }
        return Altitude(metres: Measure(value: text(metres), unit: "m"),
                        feet: Measure(value: text(metres / 0.3048), unit: "ft"))
    }

    /// Degrees from north, turned into 0..<360.
    private static func heading(_ degrees: Double?) -> Double? {
        guard let degrees, degrees.isFinite else { return nil }
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        // A tiny negative remainder plus 360 rounds to 360, which is north again, as is -720's remainder of -0.
        return value >= 360 || value == 0 ? 0 : value
    }

    // MARK: - Helpers

    /// A value that measures something: finite and above zero. EXIF stores 0 for what it doesn't know.
    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    /// Text as files hold it, without the spaces and NUL characters around it; nil when nothing is left.
    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.lowercased() == b.lowercased()
    }
}

// MARK: - Numbers

/// Numbers as the rest of the app writes them, whatever the phone's region: "." before decimals and "," between
/// thousands. Written out from whole numbers by hand: Foundation's NumberFormatter ignored the fraction digits it was
/// given on Linux and printed "12.193" for one decimal.
enum FactNumbers {
    /// Past this a value is clamped, so a damaged file's number can't trap the conversion to a whole number.
    private static let limit = 9e15
    private static let powersOfTen: [UInt64] = [1, 10, 100, 1_000, 10_000, 100_000, 1_000_000]

    /// "4,032", "-12".
    static func grouped(_ value: Int) -> String {
        let digits = Array(String(value.magnitude))
        var text = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { text.append(",") }
            text.append(digit)
        }
        return value < 0 ? "-" + text : text
    }

    /// Rounded to a whole number, without grouping, as cameras write an ISO or a shutter's fraction: "250", "8000".
    static func whole(_ value: Double) -> String {
        fixed(value, places: 0, groups: false)
    }

    /// `places` decimals, half away from zero: "12.2", "1,235". Trimmed, trailing zeros go ("1.50" reads "1.5"). A
    /// value that rounds to zero has no sign.
    static func fixed(_ value: Double, places: Int, trimsZeros: Bool = false, groups: Bool = true) -> String {
        guard value.isFinite else { return "0" }
        let places = min(max(places, 0), powersOfTen.count - 1)
        let steps = UInt64(min((abs(value) * Double(power(places))).rounded(), limit))
        let sign = value < 0 && steps > 0 ? "-" : ""
        return sign + decimal(steps, places: places, trimsZeros: trimsZeros, groups: groups)
    }

    /// A count of hundredths (or tenths, or ones) written out: 683 with two places is "6.83".
    static func decimal(_ steps: UInt64, places: Int, trimsZeros: Bool = false, groups: Bool = true) -> String {
        let places = min(max(places, 0), powersOfTen.count - 1)
        let base = power(places)
        let whole = min(steps / base, UInt64(limit))
        var fraction = ""
        if places > 0 {
            let digits = String(steps % base)
            fraction = String(repeating: "0", count: places - digits.count) + digits
        }
        if trimsZeros {
            while fraction.hasSuffix("0") { fraction.removeLast() }
        }
        let wholeText = groups ? grouped(Int(whole)) : String(whole)
        return wholeText + (fraction.isEmpty ? "" : "." + fraction)
    }

    /// 10 to the `places`, for the decimals this file writes (up to six).
    static func power(_ places: Int) -> UInt64 {
        powersOfTen[min(max(places, 0), powersOfTen.count - 1)]
    }

    /// Rounded to `digits` significant figures, trailing zeros dropped: 6.83, 12.3, 845, 0.01. `maxPlaces` caps the
    /// decimals for a value whose small digits mean nothing.
    static func significant(_ value: Double, digits: Int, maxPlaces: Int = 6) -> String {
        guard value.isFinite, value != 0 else { return "0" }
        let magnitude = Int(floor(log10(abs(value)))) + 1
        let places = min(max(0, digits - magnitude), maxPlaces)
        return fixed(value, places: places, trimsZeros: true)
    }
}

// MARK: - Info panel layout

/// Where a page's photo sits while the info panel is up: shrunk and moved into the room above the panel. The page's
/// frame never changes, so the photo's request and its zoom keep going; the viewer only scales and moves what it
/// draws.
public enum InfoPanelLayout {
    /// How the page's photo is drawn: a scale about its centre, then a move up or down in points.
    public struct Placement: Equatable, Sendable {
        public var scale: Double
        public var offsetY: Double

        public init(scale: Double, offsetY: Double) {
            self.scale = scale
            self.offsetY = offsetY
        }
    }

    /// Space kept between the phone's top (the sensor housing) and the photo, and between the photo and the panel.
    static let gapBelowTop = 8.0
    static let gapAbovePanel = 12.0

    /// The photo, fitted to the page and centred as the pager draws it, moved to the middle of the room between the
    /// phone's top and the panel, and shrunk where it is taller than that room: a landscape photo only moves up, a
    /// portrait one also shrinks. `aspect` is width over height; `safeTop` is the device's own top inset, which doesn't
    /// change while the bars hide. `progress` runs from 0 (panel down) to 1 (up), and both the scale and the move go
    /// with it. A photo of no known shape, or a page of no size, stays where it is.
    public static func photoPlacement(pageWidth: Double, pageHeight: Double, aspect: Double?, safeTop: Double,
                                      panelHeight: Double, progress: Double) -> Placement {
        let still = Placement(scale: 1, offsetY: 0)
        guard let aspect, aspect.isFinite, aspect > 0, pageWidth.isFinite, pageWidth > 0,
              pageHeight.isFinite, pageHeight > 0, safeTop.isFinite, panelHeight.isFinite, progress.isFinite else {
            return still
        }
        let shown = min(max(progress, 0), 1)
        guard shown > 0 else { return still }
        let fittedHeight = min(pageWidth / aspect, pageHeight)
        let top = max(safeTop, 0) + gapBelowTop
        let bottom = pageHeight - max(panelHeight, 0) - gapAbovePanel
        // A panel that leaves no room still leaves a point of it, so the scale stays above zero.
        let room = max(bottom - top, 1)
        let scale = min(1, room / fittedHeight)
        let offset = top + room / 2 - pageHeight / 2
        return Placement(scale: 1 + (scale - 1) * shown, offsetY: offset * shown)
    }
}
