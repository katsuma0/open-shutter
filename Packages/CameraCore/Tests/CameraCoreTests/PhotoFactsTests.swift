import XCTest
@testable import CameraCore

final class PhotoFactsTests: XCTestCase {
    private typealias Measure = PhotoFacts.Measure

    /// The facts for an input built by `configure`, from an empty one.
    private func facts(_ configure: (inout PhotoFacts.Input) -> Void) -> PhotoFacts {
        var input = PhotoFacts.Input()
        configure(&input)
        return PhotoFacts(input)
    }

    /// The night line for a shot with these XMP fields.
    private func night(_ app: [ShotXMP.Field: String]) -> PhotoFacts.NightLine? {
        facts { $0.app = app }.night
    }

    // MARK: - The reference photo

    func testTheOwnersReferencePhotoReadsAsItsPanel() {
        let facts = facts {
            $0.format = .jpeg
            $0.make = "Apple"
            $0.model = "iPhone 15 Pro Max"
            $0.lensModel = "iPhone 15 Pro Max back triple camera 15.66mm f/2.8"
            $0.focalLength35 = 120
            $0.fNumber = 2.8
            $0.iso = 250
            $0.exposureSeconds = 1.0 / 83
            $0.exifWhiteBalance = 0
            $0.profileName = "Display P3"
            $0.pixelWidth = 4032
            $0.pixelHeight = 3024
            $0.fileBytes = 6_830_000
            $0.altitude = 5.56
            $0.altitudeRef = 0
        }
        XCTAssertEqual(facts.marks, [.format("JPEG")])
        XCTAssertEqual(facts.device, "iPhone 15 Pro Max")
        // Never Apple's long lens model: the camera by the name its picker uses.
        XCTAssertEqual(facts.lens, "Telephoto camera")
        XCTAssertNil(facts.night)
        XCTAssertEqual(facts.focal, Measure(value: "120", unit: "mm"))
        XCTAssertEqual(facts.aperture, "\u{0192}/2.8")
        XCTAssertEqual(facts.iso, Measure(value: "250", unit: "ISO", unitFirst: true))
        XCTAssertEqual(facts.shutter, Measure(value: "1/83", unit: "SEC"))
        XCTAssertEqual(facts.whiteBalance, "AWB")
        XCTAssertEqual(facts.colorSpace, .displayP3)
        XCTAssertEqual(facts.colorSpace?.title, "P3")
        XCTAssertEqual(facts.dimensions, "4,032 \u{00D7} 3,024")
        XCTAssertEqual(facts.megapixels, Measure(value: "12.2", unit: "MP"))
        XCTAssertEqual(facts.fileSize, Measure(value: "6.83", unit: "MB"))
        XCTAssertEqual(facts.altitude, PhotoFacts.Altitude(metres: Measure(value: "5.56", unit: "m"),
                                                           feet: Measure(value: "18.2", unit: "ft")))
        XCTAssertNil(facts.heading)
    }

    func testAnEmptyInputSaysNothing() {
        let facts = PhotoFacts(PhotoFacts.Input())
        XCTAssertEqual(facts.marks, [])
        XCTAssertNil(facts.device)
        XCTAssertNil(facts.lens)
        XCTAssertNil(facts.night)
        XCTAssertNil(facts.focal)
        XCTAssertNil(facts.aperture)
        XCTAssertNil(facts.iso)
        XCTAssertNil(facts.shutter)
        XCTAssertNil(facts.whiteBalance)
        XCTAssertNil(facts.colorSpace)
        XCTAssertNil(facts.dimensions)
        XCTAssertNil(facts.megapixels)
        XCTAssertNil(facts.fileSize)
        XCTAssertNil(facts.altitude)
        XCTAssertNil(facts.heading)
        XCTAssertEqual(PhotoFacts.Input().format, .other)
    }

    // MARK: - Device and lens

    func testTheDeviceIsTheModelUnlessTheMakeAddsSomething() {
        XCTAssertEqual(facts { $0.make = "Apple"; $0.model = "iPhone 17 Pro" }.device, "iPhone 17 Pro")
        XCTAssertEqual(facts { $0.make = "Canon"; $0.model = "Canon EOS R5" }.device, "Canon EOS R5")
        XCTAssertEqual(facts { $0.make = "Sony"; $0.model = "ILCE-7M4" }.device, "Sony ILCE-7M4")
        // A make that is a company's whole name only has to match by its first word.
        XCTAssertEqual(facts { $0.make = "NIKON CORPORATION"; $0.model = "NIKON D850" }.device, "NIKON D850")
        XCTAssertEqual(facts { $0.make = "FUJIFILM"; $0.model = "X-T5" }.device, "FUJIFILM X-T5")
        // Files pad their text with spaces and NUL characters.
        XCTAssertEqual(facts { $0.make = " Apple\0"; $0.model = "iPhone 16 Pro\0\0" }.device, "iPhone 16 Pro")
        // One of the two alone is what there is; blank is nothing.
        XCTAssertEqual(facts { $0.model = "iPhone 16" }.device, "iPhone 16")
        XCTAssertEqual(facts { $0.make = "Sony" }.device, "Sony")
        XCTAssertNil(facts { $0.make = ""; $0.model = "  " }.device)
        XCTAssertNil(facts { $0.make = "\0"; $0.model = "" }.device)
    }

    func testTheLensIsTheCameraByItsPickerName() {
        let names: [String: String] = [
            "ultraWide": "Ultra Wide camera", "wide": "Main camera", "telephoto": "Telephoto camera",
            "front": "Front camera", "external": "External camera",
        ]
        XCTAssertEqual(Set(names.keys), Set(LensKind.allCases.map(\.rawValue)))
        for (written, name) in names {
            // The app's XMP wins over anything the focal length would say.
            XCTAssertEqual(facts { $0.app = [.lens: written]; $0.focalLength35 = 120 }.lens, name, written)
        }
        // Without the XMP: Apple's lens model for the front camera, then the 35 mm focal length.
        XCTAssertEqual(facts { $0.lensModel = "iPhone 15 Pro front camera 2.69mm f/1.9"; $0.focalLength35 = 23 }.lens,
                       "Front camera")
        XCTAssertEqual(facts { $0.focalLength35 = 13 }.lens, "Ultra Wide camera")
        XCTAssertEqual(facts { $0.focalLength35 = 24 }.lens, "Main camera")
        XCTAssertEqual(facts { $0.focalLength35 = 77 }.lens, "Telephoto camera")
        XCTAssertEqual(facts { $0.focalLength35 = 19.9 }.lens, "Ultra Wide camera")
        XCTAssertEqual(facts { $0.focalLength35 = 20 }.lens, "Main camera")
        XCTAssertEqual(facts { $0.focalLength35 = 39.9 }.lens, "Main camera")
        XCTAssertEqual(facts { $0.focalLength35 = 40 }.lens, "Telephoto camera")
        XCTAssertEqual(facts { $0.make = "Apple"; $0.focalLength35 = 26 }.lens, "Main camera")
        // A lens name this version doesn't know goes by the focal length too.
        XCTAssertEqual(facts { $0.app = [.lens: "periscope"]; $0.focalLength35 = 120 }.lens, "Telephoto camera")
        // The names are the iPhone's, so another make's lens has none.
        XCTAssertNil(facts { $0.make = "Canon"; $0.focalLength35 = 50 }.lens)
        XCTAssertNil(facts { $0.lensModel = "iPhone 15 Pro Max back triple camera 15.66mm f/2.8" }.lens)
        XCTAssertNil(facts { $0.focalLength35 = 0 }.lens)
        XCTAssertNil(PhotoFacts(PhotoFacts.Input()).lens)
    }

    // MARK: - Night line

    func testANightShotSaysItsFramesAndTheirTime() {
        let line = night([.mode: "night", .frameCount: "30", .frameSeconds: "1"])
        XCTAssertEqual(line?.text, "Night \u{00B7} 30 frames \u{00D7} 1 s")
        // The night shot draws the moon, so it names no scene.
        XCTAssertNotNil(line)
        XCTAssertNil(line?.scene)
        XCTAssertEqual(night([.mode: "night", .frameCount: "12"]),
                       PhotoFacts.NightLine(text: "Night \u{00B7} 12 frames", scene: nil))
        XCTAssertEqual(night([.mode: "night", .frameCount: "8", .frameSeconds: "0.25"])?.text,
                       "Night \u{00B7} 8 frames \u{00D7} 1/4 s")
        // A bulb shot adds nothing: the count says how long it ran.
        XCTAssertEqual(night([.mode: "night", .frameCount: "30", .frameSeconds: "1", .bulb: "True"])?.text,
                       "Night \u{00B7} 30 frames \u{00D7} 1 s")
    }

    func testALongExposureSaysItsScene() {
        XCTAssertEqual(night([.mode: "long", .scene: "lightTrails", .frameCount: "120", .frameSeconds: "0.25"]),
                       PhotoFacts.NightLine(text: "Light trails \u{00B7} 120 frames \u{00D7} 1/4 s", scene: .lightTrails))
        for scene in LongExposureScene.allCases where scene != .custom {
            let line = night([.mode: "long", .scene: scene.rawValue, .frameCount: "40", .frameSeconds: "2.5"])
            XCTAssertEqual(line?.text, scene.title + " \u{00B7} 40 frames \u{00D7} 2.5 s", scene.rawValue)
            XCTAssertEqual(line?.scene, scene, scene.rawValue)
        }
        // The person's own setup, or a scene this version doesn't know, is a long exposure, with Custom's symbol.
        XCTAssertEqual(night([.mode: "long", .scene: "custom", .frameCount: "1", .frameSeconds: "8"]),
                       PhotoFacts.NightLine(text: "Long exposure", scene: .custom))
        XCTAssertEqual(night([.mode: "long", .scene: "custom", .frameCount: "60", .frameSeconds: "30"])?.text,
                       "Long exposure \u{00B7} 60 frames \u{00D7} 30 s")
        XCTAssertEqual(night([.mode: "long", .scene: "aurora", .frameCount: "6"]),
                       PhotoFacts.NightLine(text: "Long exposure \u{00B7} 6 frames", scene: .custom))
        XCTAssertEqual(night([.mode: "long"]), PhotoFacts.NightLine(text: "Long exposure", scene: .custom))
        // Star trails runs long enough for a count in the thousands.
        XCTAssertEqual(night([.mode: "long", .scene: "starTrails", .frameCount: "1800", .frameSeconds: "1"])?.text,
                       "Star trails \u{00B7} 1,800 frames \u{00D7} 1 s")
        XCTAssertEqual(night([.mode: "long", .scene: "stars", .frameCount: "3", .frameSeconds: "125"])?.text,
                       "Stars \u{00B7} 3 frames \u{00D7} 2m 5s")
    }

    func testOnlyStackedShotsHaveANightLine() {
        for mode in ["photo", "manual", "video", "selfie", ""] {
            XCTAssertNil(night([.mode: mode, .frameCount: "30", .frameSeconds: "1"]), mode)
        }
        XCTAssertNil(night([.frameCount: "30", .frameSeconds: "1"]))
    }

    func testANightLineWithoutAReadableCountIsItsTitle() {
        for count in ["1", "0", "-4", "many", "12.5", ""] {
            XCTAssertEqual(night([.mode: "night", .frameCount: count, .frameSeconds: "1"])?.text, "Night", count)
        }
        XCTAssertEqual(night([.mode: "night"])?.text, "Night")
        // A frame time that is no time leaves the count alone.
        for frame in ["0", "-1", "nan", "inf", "fast"] {
            XCTAssertEqual(night([.mode: "night", .frameCount: "9", .frameSeconds: frame])?.text,
                           "Night \u{00B7} 9 frames", frame)
        }
    }

    // MARK: - Card

    func testTheShutterReadsAsCamerasWriteIt() {
        func shutter(_ seconds: Double) -> Measure? {
            facts { $0.exposureSeconds = seconds }.shutter
        }
        XCTAssertEqual(shutter(1.0 / 8000), Measure(value: "1/8000", unit: "SEC"))
        XCTAssertEqual(shutter(1.0 / 83), Measure(value: "1/83", unit: "SEC"))
        XCTAssertEqual(shutter(0.399), Measure(value: "1/3", unit: "SEC"))
        XCTAssertEqual(shutter(0.4), Measure(value: "0.4", unit: "SEC"))
        XCTAssertEqual(shutter(1), Measure(value: "1", unit: "SEC"))
        XCTAssertEqual(shutter(2.5), Measure(value: "2.5", unit: "SEC"))
        // One decimal below 10 s, however many the file holds.
        XCTAssertEqual(shutter(3.14), Measure(value: "3.1", unit: "SEC"))
        XCTAssertEqual(shutter(30), Measure(value: "30", unit: "SEC"))
        // Whole seconds below 99.5 s; past that minutes and seconds, which name their own units.
        XCTAssertEqual(shutter(10.4), Measure(value: "10", unit: "SEC"))
        XCTAssertEqual(shutter(99.4), Measure(value: "99", unit: "SEC"))
        XCTAssertEqual(shutter(99.6), Measure(value: "1m 40s", unit: ""))
        XCTAssertEqual(shutter(125), Measure(value: "2m 5s", unit: ""))
        for bad in [0.0, .nan, -0.5, .infinity] {
            XCTAssertNil(shutter(bad), "\(bad)")
        }
    }

    func testFocalApertureAndISO() {
        let card = facts { $0.focalLength35 = 26; $0.fNumber = 1.78; $0.iso = 12800 }
        XCTAssertEqual(card.focal, Measure(value: "26", unit: "mm"))
        XCTAssertEqual(card.aperture, "\u{0192}/1.78")
        // The ISO is written as cameras write it, ungrouped and unit first.
        XCTAssertEqual(card.iso, Measure(value: "12800", unit: "ISO", unitFirst: true))
        XCTAssertEqual(facts { $0.iso = 64.4 }.iso?.value, "64")
        // EXIF stores 0 for what it doesn't know, so 0 drops the cell.
        let unknown = facts { $0.focalLength35 = 0; $0.fNumber = 0; $0.iso = 0 }
        XCTAssertNil(unknown.focal)
        XCTAssertNil(unknown.aperture)
        XCTAssertNil(unknown.iso)
        XCTAssertNil(facts { $0.fNumber = .nan; $0.iso = -3; $0.focalLength35 = .infinity }.aperture)
    }

    func testWhiteBalanceSaysAutoAPresetOrTheKelvin() {
        XCTAssertEqual(facts { $0.app = [.whiteBalance: "auto"] }.whiteBalance, "AWB")
        XCTAssertEqual(facts { $0.app = [.whiteBalance: "kelvin", .kelvin: "5600"] }.whiteBalance, "5600K")
        XCTAssertEqual(facts { $0.app = [.whiteBalance: "daylight"] }.whiteBalance, "Daylight")
        for preset in WhiteBalancePreset.allCases where preset != .auto {
            XCTAssertEqual(facts { $0.app = [.whiteBalance: preset.rawValue] }.whiteBalance, preset.title)
        }
        XCTAssertEqual(facts { $0.exifWhiteBalance = 0 }.whiteBalance, "AWB")
        XCTAssertEqual(facts { $0.exifWhiteBalance = 1 }.whiteBalance, "Manual")
        XCTAssertNil(PhotoFacts(PhotoFacts.Input()).whiteBalance)
        XCTAssertNil(facts { $0.exifWhiteBalance = 7 }.whiteBalance)
        // The XMP knows more than EXIF's manual, so it wins; what it can't say falls back to EXIF.
        XCTAssertEqual(facts { $0.app = [.whiteBalance: "tungsten"]; $0.exifWhiteBalance = 1 }.whiteBalance, "Tungsten")
        XCTAssertEqual(facts { $0.app = [.whiteBalance: "kelvin"]; $0.exifWhiteBalance = 1 }.whiteBalance, "Manual")
        XCTAssertEqual(facts { $0.app = [.whiteBalance: "kelvin", .kelvin: "warm"]; $0.exifWhiteBalance = 1 }
            .whiteBalance, "Manual")
        XCTAssertEqual(facts { $0.app = [.whiteBalance: "sodium"]; $0.exifWhiteBalance = 0 }.whiteBalance, "AWB")
    }

    func testTheColorBadgeNamesTheSpace() {
        func space(_ name: String?, exif: Int? = nil) -> PhotoFacts.ColorSpace? {
            facts { $0.profileName = name; $0.exifColorSpace = exif }.colorSpace
        }
        XCTAssertEqual(space("Display P3"), .displayP3)
        XCTAssertEqual(space("sRGB IEC61966-2.1"), .sRGB)
        XCTAssertEqual(space(nil, exif: 1), .sRGB)
        XCTAssertEqual(space("ITU-R BT.2020"), .named("Rec. 2020"))
        XCTAssertEqual(space("ITU-R BT.2100 PQ"), .named("Rec. 2020"))
        XCTAssertEqual(space("Adobe RGB (1998)"), .named("Adobe RGB"))
        XCTAssertEqual(space(nil, exif: 2), .named("Adobe RGB"))
        XCTAssertNil(space("Generic Gray Gamma 2.2 Profile"))
        // What a Display P3 photo's EXIF says: uncalibrated, which names no space.
        XCTAssertNil(space(nil, exif: 65535))
        XCTAssertNil(space(nil))
        // The profile's name says more than EXIF.
        XCTAssertEqual(space("Display P3", exif: 1), .displayP3)
        XCTAssertEqual([PhotoFacts.ColorSpace.displayP3, .sRGB, .named("Rec. 2020"), .named("Adobe RGB")].map(\.title),
                       ["P3", "sRGB", "Rec. 2020", "Adobe RGB"])
    }

    // MARK: - Marks

    func testTheFormatBadgesNameTheFiles() {
        func marks(_ format: PhotoFacts.FileFormat, linear: Bool? = nil, companion: Bool = false) -> [PhotoFacts.Mark] {
            facts { $0.format = format; $0.linearRAW = linear; $0.hasRAWCompanion = companion }.marks
        }
        XCTAssertEqual(marks(.heif, companion: true), [.format("HEIF"), .format("RAW")])
        XCTAssertEqual(marks(.jpeg, companion: true), [.format("JPEG"), .format("RAW")])
        XCTAssertEqual(marks(.heif), [.format("HEIF")])
        XCTAssertEqual(marks(.png), [.format("PNG")])
        XCTAssertEqual(marks(.tiff), [.format("TIFF")])
        // A DNG alone says which kind it is.
        XCTAssertEqual(marks(.raw, linear: true), [.format("ProRAW")])
        XCTAssertEqual(marks(.raw, linear: false), [.format("RAW")])
        XCTAssertEqual(marks(.raw), [.format("RAW")])
        XCTAssertEqual(marks(.raw, linear: true, companion: true), [.format("ProRAW")])
        XCTAssertEqual(marks(.other), [])
        XCTAssertEqual(marks(.other, companion: true), [.format("RAW")])
    }

    func testTheMarksReadDepthLiveHDREditedThenTheFiles() {
        let all = facts {
            $0.format = .heif
            $0.hasRAWCompanion = true
            $0.isEdited = true
            $0.hasGainMap = true
            $0.isLive = true
            $0.hasDepth = true
        }
        XCTAssertEqual(all.marks, [.depth, .live, .hdr, .edited, .format("HEIF"), .format("RAW")])
        XCTAssertEqual(facts { $0.format = .jpeg; $0.isLive = true; $0.isEdited = true }.marks,
                       [.live, .edited, .format("JPEG")])
        XCTAssertEqual(facts { $0.hasGainMap = true }.marks, [.hdr])
    }

    // MARK: - Size

    func testTheSizeIsAsThePhotoShows() {
        let turned = facts { $0.pixelWidth = 4032; $0.pixelHeight = 3024; $0.orientation = 6 }
        XCTAssertEqual(turned.dimensions, "3,024 \u{00D7} 4,032")
        XCTAssertEqual(turned.megapixels, Measure(value: "12.2", unit: "MP"))
        for orientation in 5...8 {
            XCTAssertEqual(facts { $0.pixelWidth = 4; $0.pixelHeight = 3; $0.orientation = orientation }.dimensions,
                           "3 \u{00D7} 4", "\(orientation)")
        }
        for orientation in [1, 2, 3, 4, 0, 9] {
            XCTAssertEqual(facts { $0.pixelWidth = 4; $0.pixelHeight = 3; $0.orientation = orientation }.dimensions,
                           "4 \u{00D7} 3", "\(orientation)")
        }
        let large = facts { $0.pixelWidth = 8064; $0.pixelHeight = 6048 }
        XCTAssertEqual(large.dimensions, "8,064 \u{00D7} 6,048")
        // One decimal, where the camera's menus say 48 MP.
        XCTAssertEqual(large.megapixels, Measure(value: "48.8", unit: "MP"))
        XCTAssertEqual(facts { $0.pixelWidth = 4000; $0.pixelHeight = 3000 }.megapixels?.value, "12.0")
        XCTAssertEqual(facts { $0.pixelWidth = 640; $0.pixelHeight = 480 }.megapixels?.value, "0.3")
        XCTAssertEqual(facts { $0.pixelWidth = 100; $0.pixelHeight = 100 }.megapixels?.value, "0.01")
        // A side of 0, or one missing, is no size.
        for (width, height) in [(0, 3024), (4032, 0), (-4032, 3024)] {
            let none = facts { $0.pixelWidth = width; $0.pixelHeight = height }
            XCTAssertNil(none.dimensions, "\(width) x \(height)")
            XCTAssertNil(none.megapixels, "\(width) x \(height)")
        }
        XCTAssertNil(facts { $0.pixelWidth = 4032 }.dimensions)
        XCTAssertNil(facts { $0.pixelHeight = 3024; $0.orientation = 6 }.megapixels)
    }

    func testTheFileSizeHasThreeFiguresInDecimalUnits() {
        func size(_ bytes: Int64) -> Measure? {
            facts { $0.fileBytes = bytes }.fileSize
        }
        XCTAssertEqual(size(6_830_000), Measure(value: "6.83", unit: "MB"))
        XCTAssertEqual(size(12_345_678), Measure(value: "12.3", unit: "MB"))
        XCTAssertEqual(size(845_000), Measure(value: "845", unit: "KB"))
        XCTAssertEqual(size(1_234_567_890), Measure(value: "1.23", unit: "GB"))
        XCTAssertEqual(size(6_800_000), Measure(value: "6.8", unit: "MB"))
        // A size that would round to 1000 of a unit is one of the next.
        XCTAssertEqual(size(999_700), Measure(value: "1", unit: "MB"))
        XCTAssertEqual(size(999_499), Measure(value: "999", unit: "KB"))
        XCTAssertEqual(size(999_500), Measure(value: "1", unit: "MB"))
        XCTAssertEqual(size(999_600_000), Measure(value: "1", unit: "GB"))
        XCTAssertEqual(size(1_000), Measure(value: "1", unit: "KB"))
        XCTAssertEqual(size(999), Measure(value: "999", unit: "B"))
        XCTAssertEqual(size(1), Measure(value: "1", unit: "B"))
        // Rounding up into the next decade keeps three figures' worth, without the zeros.
        XCTAssertEqual(size(9_995_000), Measure(value: "10", unit: "MB"))
        XCTAssertEqual(size(9_994_999), Measure(value: "9.99", unit: "MB"))
        XCTAssertEqual(size(99_950_000), Measure(value: "100", unit: "MB"))
        XCTAssertEqual(size(25_100_000), Measure(value: "25.1", unit: "MB"))
        // GB is the largest unit, and no file size traps.
        XCTAssertEqual(size(1_500_000_000_000), Measure(value: "1,500", unit: "GB"))
        XCTAssertEqual(size(.max)?.unit, "GB")
        XCTAssertNil(size(0))
        XCTAssertNil(size(-5))
    }

    // MARK: - Place

    func testTheAltitudeHasMetresAndFeet() {
        func height(_ metres: Double, ref: Int? = 0) -> PhotoFacts.Altitude? {
            facts { $0.altitude = metres; $0.altitudeRef = ref }.altitude
        }
        func pair(_ metres: String, _ feet: String) -> PhotoFacts.Altitude {
            PhotoFacts.Altitude(metres: Measure(value: metres, unit: "m"), feet: Measure(value: feet, unit: "ft"))
        }
        XCTAssertEqual(height(5.56), pair("5.56", "18.2"))
        XCTAssertEqual(height(563.4), pair("563", "1,848"))
        XCTAssertEqual(height(1234.5), pair("1,235", "4,050"))
        XCTAssertEqual(height(-12.34), pair("-12.3", "-40.5"))
        XCTAssertEqual(height(0), pair("0", "0"))
        // Reference 1 is below sea level, whatever sign the value carries.
        XCTAssertEqual(height(12.34, ref: 1), pair("-12.3", "-40.5"))
        XCTAssertEqual(height(5.56, ref: nil), pair("5.56", "18.2"))
        // A GPS height isn't good to the millimetre.
        XCTAssertEqual(height(0.004), pair("0", "0.01"))
        // No phone was 20 km up: that is a file's error.
        XCTAssertNil(height(20_000))
        XCTAssertNil(height(-20_000))
        XCTAssertNotNil(height(19_999))
        XCTAssertNil(height(.nan))
        XCTAssertNil(height(.infinity))
        XCTAssertNil(facts { $0.altitudeRef = 1 }.altitude)
    }

    func testTheHeadingTurnsIntoACircle() {
        func heading(_ degrees: Double?) -> Double? {
            facts { $0.heading = degrees }.heading
        }
        XCTAssertEqual(heading(190), 190)
        XCTAssertEqual(heading(0), 0)
        XCTAssertEqual(heading(360), 0)
        XCTAssertEqual(heading(370), 10)
        XCTAssertEqual(heading(-90), 270)
        XCTAssertEqual(heading(-720), 0)
        XCTAssertNil(heading(nil))
        XCTAssertNil(heading(.nan))
        XCTAssertNil(heading(.infinity))
        let tiny = heading(-1e-15)
        XCTAssertNotNil(tiny)
        XCTAssertTrue(tiny.map { $0 >= 0 && $0 < 360 } ?? false)
    }

    func testPlaceLinesBeforeIOS26() {
        XCTAssertEqual(PhotoFacts.placeLines(name: "Grant Park", subLocality: "South Loop", locality: "Chicago",
                                             administrativeArea: "IL", country: "United States"),
                       ["Grant Park", "South Loop, Chicago, IL", "United States"])
        // Missing and blank parts leave no gap.
        XCTAssertEqual(PhotoFacts.placeLines(name: nil, subLocality: " ", locality: "Toronto", administrativeArea: "ON",
                                             country: "Canada"),
                       ["Toronto, ON", "Canada"])
        XCTAssertEqual(PhotoFacts.placeLines(name: "CN Tower", subLocality: nil, locality: nil, administrativeArea: nil,
                                             country: nil),
                       ["CN Tower"])
        XCTAssertEqual(PhotoFacts.placeLines(name: nil, subLocality: nil, locality: nil, administrativeArea: "",
                                             country: nil),
                       [])
        // A part said twice is said once.
        XCTAssertEqual(PhotoFacts.placeLines(name: "Old Port", subLocality: "Montreal", locality: "Montreal",
                                             administrativeArea: "QC", country: "Canada"),
                       ["Old Port", "Montreal, QC", "Canada"])
        // A name that is only the city, or a line equal to the one above it, goes.
        XCTAssertEqual(PhotoFacts.placeLines(name: "Chicago", subLocality: "South Loop", locality: "Chicago",
                                             administrativeArea: "IL", country: "United States"),
                       ["South Loop, Chicago, IL", "United States"])
        XCTAssertEqual(PhotoFacts.placeLines(name: "Singapore", subLocality: nil, locality: nil,
                                             administrativeArea: nil, country: "Singapore"),
                       ["Singapore"])
        XCTAssertEqual(PhotoFacts.placeLines(name: "Monaco", subLocality: nil, locality: "Monaco",
                                             administrativeArea: nil, country: "Monaco"),
                       ["Monaco"])
    }

    func testPlaceLinesFromIOS26() {
        XCTAssertEqual(PhotoFacts.placeLines(name: "Grant Park", city: "Chicago, IL", region: "United States"),
                       ["Grant Park", "Chicago, IL", "United States"])
        // A name that is only the city goes, by the city line or by its first part.
        XCTAssertEqual(PhotoFacts.placeLines(name: "Chicago", city: "Chicago, IL", region: "United States"),
                       ["Chicago, IL", "United States"])
        XCTAssertEqual(PhotoFacts.placeLines(name: "Chicago, IL", city: "Chicago, IL", region: "United States"),
                       ["Chicago, IL", "United States"])
        // Capitals don't make it another place.
        XCTAssertEqual(PhotoFacts.placeLines(name: "CHICAGO", city: "Chicago, IL", region: "United States"),
                       ["Chicago, IL", "United States"])
        // A region the city line already ends with goes.
        XCTAssertEqual(PhotoFacts.placeLines(name: "Louvre Museum", city: "Paris, France", region: "France"),
                       ["Louvre Museum", "Paris, France"])
        XCTAssertEqual(PhotoFacts.placeLines(name: "  ", city: nil, region: "Canada"), ["Canada"])
        XCTAssertEqual(PhotoFacts.placeLines(name: "Lake Louise", city: "", region: nil), ["Lake Louise"])
        XCTAssertEqual(PhotoFacts.placeLines(name: nil, city: nil, region: nil), [])
        XCTAssertEqual(PhotoFacts.placeLines(name: "Canada", city: nil, region: "Canada"), ["Canada"])
    }

    // MARK: - Library

    func testTheLibraryCountIsShort() {
        XCTAssertEqual(PhotoFacts.libraryCount(photos: 0, videos: 0), "")
        XCTAssertEqual(PhotoFacts.libraryCount(photos: 1, videos: 0), "1 photo")
        XCTAssertEqual(PhotoFacts.libraryCount(photos: 0, videos: 1), "1 video")
        XCTAssertEqual(PhotoFacts.libraryCount(photos: 0, videos: 3), "3 videos")
        XCTAssertEqual(PhotoFacts.libraryCount(photos: 214, videos: 6), "214 photos, 6 videos")
        XCTAssertEqual(PhotoFacts.libraryCount(photos: 1234, videos: 5), "1,234 photos, 5 videos")
        XCTAssertEqual(PhotoFacts.libraryCount(photos: 1, videos: 1), "1 photo, 1 video")
        XCTAssertEqual(PhotoFacts.libraryCount(photos: -2, videos: -1), "")
    }

    // MARK: - Numbers

    func testNumbersAreWrittenTheAppsWay() {
        XCTAssertEqual(FactNumbers.grouped(0), "0")
        XCTAssertEqual(FactNumbers.grouped(999), "999")
        XCTAssertEqual(FactNumbers.grouped(1000), "1,000")
        XCTAssertEqual(FactNumbers.grouped(1_234_567), "1,234,567")
        XCTAssertEqual(FactNumbers.grouped(-4032), "-4,032")
        XCTAssertEqual(FactNumbers.fixed(12.193, places: 1), "12.2")
        XCTAssertEqual(FactNumbers.fixed(12, places: 1), "12.0")
        XCTAssertEqual(FactNumbers.fixed(0.05, places: 2), "0.05")
        XCTAssertEqual(FactNumbers.fixed(1.5, places: 2, trimsZeros: true), "1.5")
        XCTAssertEqual(FactNumbers.fixed(1234.5, places: 0), "1,235")
        XCTAssertEqual(FactNumbers.fixed(1234.5, places: 0, groups: false), "1235")
        XCTAssertEqual(FactNumbers.fixed(-0.004, places: 2), "0.00")
        XCTAssertEqual(FactNumbers.fixed(.nan, places: 2), "0")
        XCTAssertEqual(FactNumbers.significant(6.83, digits: 3), "6.83")
        XCTAssertEqual(FactNumbers.significant(12.345678, digits: 3), "12.3")
        XCTAssertEqual(FactNumbers.significant(845, digits: 3), "845")
        XCTAssertEqual(FactNumbers.significant(9.996, digits: 3), "10")
        XCTAssertEqual(FactNumbers.significant(0.012, digits: 1), "0.01")
        XCTAssertEqual(FactNumbers.significant(-40.49, digits: 3), "-40.5")
        XCTAssertEqual(FactNumbers.significant(0, digits: 3), "0")
        XCTAssertEqual(FactNumbers.whole(83.0000001), "83")
        // Garbage in a file can't trap a conversion.
        XCTAssertFalse(FactNumbers.fixed(1e300, places: 2).isEmpty)
        XCTAssertFalse(FactNumbers.whole(-1e300).isEmpty)
    }

    // MARK: - Info panel layout

    private let page = (width: 402.0, height: 874.0)

    private func place(aspect: Double?, safeTop: Double = 62, panel: Double = 520, progress: Double = 1)
        -> InfoPanelLayout.Placement {
        InfoPanelLayout.photoPlacement(pageWidth: page.width, pageHeight: page.height, aspect: aspect, safeTop: safeTop,
                                       panelHeight: panel, progress: progress)
    }

    /// The photo's top and bottom on the page once placed, for a photo fitted at `fittedHeight`.
    private func edges(_ placement: InfoPanelLayout.Placement, fittedHeight: Double) -> (top: Double, bottom: Double) {
        let middle = page.height / 2 + placement.offsetY
        let half = fittedHeight * placement.scale / 2
        return (middle - half, middle + half)
    }

    func testThePhotoStaysPutWhileThePanelIsDown() {
        for aspect in [4.0 / 3, 3.0 / 4, 1, 0.3] {
            XCTAssertEqual(place(aspect: aspect, progress: 0), InfoPanelLayout.Placement(scale: 1, offsetY: 0))
            XCTAssertEqual(place(aspect: aspect, progress: -0.5), InfoPanelLayout.Placement(scale: 1, offsetY: 0))
        }
    }

    func testALandscapePhotoOnlyMovesUpWhenItFits() {
        // 402 pt wide, a 4:3 photo is 301.5 pt tall; with the panel at 520 that fits on a phone with no top inset.
        let up = place(aspect: 4.0 / 3, safeTop: 0, panel: 520)
        XCTAssertEqual(up.scale, 1)
        XCTAssertLessThan(up.offsetY, 0)
        // Centred in the room: from 8 pt below the top to 12 pt above the panel.
        XCTAssertEqual(up.offsetY, (8 + 342) / 2 - 437, accuracy: 1e-9)
        // Under a sensor housing the room is shorter, so with a lower panel it still only moves.
        let housed = place(aspect: 4.0 / 3, safeTop: 62, panel: 420)
        XCTAssertEqual(housed.scale, 1)
        XCTAssertEqual(housed.offsetY, (70 + 442) / 2 - 437, accuracy: 1e-9)
        let photo = edges(housed, fittedHeight: 301.5)
        XCTAssertGreaterThanOrEqual(photo.top, 70)
        XCTAssertLessThanOrEqual(photo.bottom, 874 - 420 - 12)
    }

    func testAPortraitPhotoShrinksIntoTheRoomAboveThePanel() {
        // 3:4 on a 402 pt page is 536 pt tall, more than the 272 pt between the housing and the panel.
        let placed = place(aspect: 3.0 / 4)
        XCTAssertLessThan(placed.scale, 1)
        XCTAssertEqual(placed.scale, 272.0 / 536, accuracy: 1e-9)
        let photo = edges(placed, fittedHeight: 536)
        // Its bottom ends 12 pt above the panel and its top 8 pt below the phone's top.
        XCTAssertEqual(photo.bottom, 874 - 520 - 12, accuracy: 1e-9)
        XCTAssertEqual(photo.top, 62 + 8, accuracy: 1e-9)
        // A landscape photo taller than a short room shrinks the same way.
        let wide = place(aspect: 4.0 / 3)
        XCTAssertEqual(wide.scale, 272 / 301.5, accuracy: 1e-9)
        XCTAssertEqual(edges(wide, fittedHeight: 301.5).bottom, 874 - 520 - 12, accuracy: 1e-9)
        // A photo taller than the page is fitted to its height first.
        let tall = place(aspect: 0.3)
        XCTAssertEqual(tall.scale, 272.0 / 874, accuracy: 1e-9)
        XCTAssertEqual(edges(tall, fittedHeight: 874).bottom, 874 - 520 - 12, accuracy: 1e-9)
    }

    func testThePlacementFollowsThePanelAsItRises() {
        let full = place(aspect: 3.0 / 4)
        let half = place(aspect: 3.0 / 4, progress: 0.5)
        XCTAssertEqual(half.scale, 1 + (full.scale - 1) / 2, accuracy: 1e-12)
        XCTAssertEqual(half.offsetY, full.offsetY / 2, accuracy: 1e-12)
        // Past the top it stays where the panel is up.
        XCTAssertEqual(place(aspect: 3.0 / 4, progress: 1.4), full)
    }

    func testAPhotoOfNoKnownShapeStaysPut() {
        let still = InfoPanelLayout.Placement(scale: 1, offsetY: 0)
        for aspect in [nil, 0, -1, .nan, .infinity] as [Double?] {
            XCTAssertEqual(place(aspect: aspect), still, "\(String(describing: aspect))")
        }
        XCTAssertEqual(InfoPanelLayout.photoPlacement(pageWidth: 0, pageHeight: 874, aspect: 1, safeTop: 62,
                                                      panelHeight: 520, progress: 1), still)
        XCTAssertEqual(InfoPanelLayout.photoPlacement(pageWidth: 402, pageHeight: .nan, aspect: 1, safeTop: 62,
                                                      panelHeight: 520, progress: 1), still)
        XCTAssertEqual(place(aspect: 1, safeTop: .nan), still)
        XCTAssertEqual(place(aspect: 1, panel: .infinity), still)
        XCTAssertEqual(place(aspect: 1, progress: .nan), still)
    }

    func testAnInsetOrPanelUnderZeroCountsAsNone() {
        // Neither is below zero on a phone; one that reads so is taken as none, not as room the page doesn't have.
        XCTAssertEqual(place(aspect: 3.0 / 4, safeTop: -20), place(aspect: 3.0 / 4, safeTop: 0))
        XCTAssertEqual(place(aspect: 3.0 / 4, panel: -100), place(aspect: 3.0 / 4, panel: 0))
    }

    func testARoomUnderAPointNeverFlipsOrLosesThePhoto() {
        for panel in [862.0 - 70, 900, 5000] {
            for aspect in [4.0 / 3, 3.0 / 4] {
                let placed = place(aspect: aspect, panel: panel)
                XCTAssertTrue(placed.scale.isFinite && placed.scale > 0, "\(panel) \(aspect): \(placed)")
                XCTAssertTrue(placed.offsetY.isFinite, "\(panel) \(aspect): \(placed)")
                XCTAssertLessThan(placed.scale, 0.01, "\(panel) \(aspect): \(placed)")
            }
        }
    }
}
