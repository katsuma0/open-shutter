import XCTest
@testable import CameraCore

final class PhotoFormatsTests: XCTestCase {
    private func capture(saved json: String) -> CaptureOptions {
        CameraSettings.decoded(from: Data(#"{"capture":\#(json)}"#.utf8)).capture
    }

    // MARK: - Containers

    func testContainersKeepTheirStoredNames() {
        // Saves hold these names; PNG and TIFF go between JPEG and RAW only.
        XCTAssertEqual(ProcessedFormat.allCases.map(\.rawValue), ["heif", "jpeg", "png", "tiff", "none"])
        XCTAssertEqual(ProcessedFormat.allCases.map(\.title), ["HEIF", "JPEG", "PNG", "TIFF", "None"])
        XCTAssertEqual(ProcessedFormat.allCases.map(\.id), ProcessedFormat.allCases.map(\.rawValue))
    }

    func testOnlyPNGAndTIFFAreLossless() {
        XCTAssertEqual(ProcessedFormat.allCases.filter(\.isLossless), [.png, .tiff])
    }

    func testRawOnlySavesHEIFWhereItSavesNoRAW() {
        XCTAssertEqual(ProcessedFormat.none.saved, .heif)
        for format in ProcessedFormat.allCases where format != .none {
            XCTAssertEqual(format.saved, format, format.rawValue)
        }
        XCTAssertFalse(ProcessedFormat.allCases.contains { $0.saved == .none })
    }

    func testPNGAndTIFFDecodeAndStayValid() throws {
        for format in [ProcessedFormat.png, .tiff] {
            let alone = capture(saved: #"{"processedFormat":"\#(format.rawValue)","rawFormat":"none"}"#)
            XCTAssertEqual(alone.processedFormat, format)
            XCTAssertTrue(alone.isValid)
            let withRaw = capture(saved: #"{"processedFormat":"\#(format.rawValue)","rawFormat":"proRAW"}"#)
            XCTAssertEqual(withRaw.processedFormat, format)
            XCTAssertEqual(withRaw.rawFormat, .proRAW)

            var settings = CameraSettings()
            settings.capture.processedFormat = format
            XCTAssertEqual(CameraSettings.decoded(from: try settings.encoded()), settings, format.rawValue)
        }
    }

    func testAnUnknownFormatDecodesAsHEIFAndKeepsTheRest() {
        // From a later version, or of the wrong type.
        for value in [#""webp""#, "3", "null", #"{"png":true}"#] {
            let decoded = capture(saved: #"{"processedFormat":\#(value),"quality":0.7,"rawFormat":"bayer","highQuality":true,"flash":"on"}"#)
            XCTAssertEqual(decoded.processedFormat, .heif, value)
            XCTAssertEqual(decoded.quality, 0.7, accuracy: 1e-9, value)
            XCTAssertEqual(decoded.rawFormat, .bayer, value)
            XCTAssertTrue(decoded.highQuality, value)
            XCTAssertEqual(decoded.flash, .on, value)
        }
        // RAW only is still RAW only, and with no RAW it gets HEIF, as it always did.
        XCTAssertEqual(capture(saved: #"{"processedFormat":"none","rawFormat":"bayer"}"#).processedFormat, .none)
        XCTAssertEqual(capture(saved: #"{"processedFormat":"none","rawFormat":"none"}"#).processedFormat, .heif)
    }

    // MARK: - High quality

    func testHighQualityStartsOffAndRoundTrips() throws {
        XCTAssertFalse(CaptureOptions().highQuality)
        XCTAssertFalse(CameraSettings.default.capture.highQuality)
        XCTAssertFalse(capture(saved: #"{"quality":0.8}"#).highQuality)
        XCTAssertFalse(capture(saved: #"{"highQuality":"yes"}"#).highQuality)
        XCTAssertTrue(capture(saved: #"{"highQuality":true}"#).highQuality)
        var settings = CameraSettings()
        settings.capture.highQuality = true
        let json = String(decoding: try settings.encoded(), as: UTF8.self)
        XCTAssertTrue(json.contains(#""highQuality":true"#), json)
        XCTAssertTrue(CameraSettings.decoded(from: try settings.encoded()).capture.highQuality)
    }

    func testHighSavesAtTheTopAndKeepsTheSlider() {
        XCTAssertEqual(PhotoFormatChoice.highQuality, 1)
        var options = CaptureOptions()
        options.quality = 0.65
        XCTAssertEqual(options.effectiveQuality, 0.65, accuracy: 1e-12)
        options.highQuality = true
        XCTAssertEqual(options.effectiveQuality, PhotoFormatChoice.highQuality, accuracy: 1e-12)
        // The slider's own value waits for plain HEIF.
        XCTAssertEqual(options.quality, 0.65, accuracy: 1e-12)
        options.highQuality = false
        XCTAssertEqual(options.effectiveQuality, 0.65, accuracy: 1e-12)
    }

    // MARK: - Live Photo

    func testLivePhotoNeedsHEIFOrJPEGWithoutRAW() {
        for raw in RawFormat.allCases {
            for format in ProcessedFormat.allCases where format != .none || raw != .none {
                var options = CaptureOptions()
                options.processedFormat = format
                options.rawFormat = raw
                let expected = raw == .none && (format == .heif || format == .jpeg)
                XCTAssertEqual(options.allowsLivePhoto, expected, "\(format.rawValue) + \(raw.rawValue)")
            }
        }
        // A capture with nothing to save is saved as HEIF, which may carry the movie.
        var empty = CaptureOptions()
        empty.processedFormat = .none
        XCTAssertTrue(empty.allowsLivePhoto)
        // High changes the quality, not the container.
        var high = CaptureOptions()
        high.highQuality = true
        XCTAssertTrue(high.allowsLivePhoto)
    }

    // MARK: - The rows

    func testRowsAndTheirTitles() {
        XCTAssertEqual(PhotoFormatChoice.allCases, [.heif, .heifHigh, .jpeg, .jpegHigh, .png, .tiff, .rawOnly])
        XCTAssertEqual(PhotoFormatChoice.allCases.map(\.title),
                       ["HEIF", "HEIF High", "JPEG", "JPEG High", "PNG", "TIFF", "RAW only"])
        XCTAssertEqual(PhotoFormatChoice.allCases.map(\.format), [.heif, .heif, .jpeg, .jpeg, .png, .tiff, .none])
        XCTAssertEqual(PhotoFormatChoice.allCases.filter(\.isHigh), [.heifHigh, .jpegHigh])
        XCTAssertEqual(PhotoFormatChoice.allCases.filter(\.takesQualitySlider), [.heif, .jpeg, .rawOnly])
        XCTAssertEqual(PhotoFormatChoice.allCases.map(\.id), PhotoFormatChoice.allCases.map(\.rawValue))
        // Every container has a row, RAW only's "none" included.
        XCTAssertEqual(Set(PhotoFormatChoice.allCases.map(\.format)), Set(ProcessedFormat.allCases))
    }

    func testTheStoredFieldsShowAsOneRow() {
        func row(_ format: ProcessedFormat, high: Bool) -> PhotoFormatChoice {
            var options = CaptureOptions()
            options.processedFormat = format
            options.rawFormat = .bayer
            options.highQuality = high
            return PhotoFormatChoice(options)
        }
        XCTAssertEqual(row(.heif, high: false), .heif)
        XCTAssertEqual(row(.heif, high: true), .heifHigh)
        XCTAssertEqual(row(.jpeg, high: false), .jpeg)
        XCTAssertEqual(row(.jpeg, high: true), .jpegHigh)
        // High means nothing to a lossless file, so it doesn't show.
        XCTAssertEqual(row(.png, high: true), .png)
        XCTAssertEqual(row(.tiff, high: true), .tiff)
        XCTAssertEqual(row(.none, high: false), .rawOnly)
        XCTAssertEqual(row(.none, high: true), .rawOnly)
        // A fresh install is plain HEIF.
        XCTAssertEqual(PhotoFormatChoice(CaptureOptions()), .heif)
    }

    func testEveryRowComesBackAsPicked() {
        var high = CaptureOptions()
        high.highQuality = true
        high.quality = 0.55
        var png = CaptureOptions()
        png.processedFormat = .png
        png.rawFormat = .proRAW
        var rawOnly = CaptureOptions()
        rawOnly.processedFormat = .none
        rawOnly.rawFormat = .bayer
        rawOnly.quality = 0.75
        for start in [CaptureOptions(), high, png, rawOnly] {
            for choice in PhotoFormatChoice.allCases {
                var options = start
                choice.apply(to: &options)
                XCTAssertEqual(PhotoFormatChoice(options), choice, choice.rawValue)
                XCTAssertEqual(options.processedFormat, choice.format, choice.rawValue)
                XCTAssertEqual(options.highQuality, choice.isHigh, choice.rawValue)
                // The slider and the RAW row are left alone.
                XCTAssertEqual(options.quality, start.quality, choice.rawValue)
                XCTAssertEqual(options.rawFormat, start.rawFormat, choice.rawValue)
                // Nothing else moves either.
                var others = options
                others.processedFormat = start.processedFormat
                others.highQuality = start.highQuality
                XCTAssertEqual(others, start, choice.rawValue)
            }
        }
    }

    func testPickingPNGLeavesTheQualityAlone() {
        var options = CaptureOptions()
        options.quality = 0.65
        PhotoFormatChoice.heifHigh.apply(to: &options)
        XCTAssertEqual(options.effectiveQuality, 1, accuracy: 1e-12)
        PhotoFormatChoice.png.apply(to: &options)
        XCTAssertEqual(options.processedFormat, .png)
        XCTAssertEqual(options.quality, 0.65, accuracy: 1e-12)
        // Back to plain HEIF, the slider as it was.
        PhotoFormatChoice.heif.apply(to: &options)
        XCTAssertEqual(options.effectiveQuality, 0.65, accuracy: 1e-12)
    }

    func testRawOnlyStacksFollowTheSliderAgain() {
        // RAW only's stacks save HEIF at the slider's quality, and the slider is live for it: High can't linger.
        var options = CaptureOptions()
        options.rawFormat = .bayer
        options.quality = 0.7
        PhotoFormatChoice.heifHigh.apply(to: &options)
        PhotoFormatChoice.rawOnly.apply(to: &options)
        XCTAssertTrue(PhotoFormatChoice(options).takesQualitySlider)
        XCTAssertFalse(options.highQuality)
        XCTAssertEqual(options.effectiveQuality, 0.7, accuracy: 1e-12)
        XCTAssertEqual(options.processedFormat.saved, .heif)
    }

    func testWhichRowsAreOffered() {
        let all = PhotoFormatChoice.allCases
        XCTAssertEqual(PhotoFormatChoice.choices(heif: true, rawOn: true), all)
        XCTAssertEqual(PhotoFormatChoice.choices(heif: true, rawOn: false), all.filter { $0 != .rawOnly })
        XCTAssertEqual(PhotoFormatChoice.choices(heif: false, rawOn: true), [.jpeg, .jpegHigh, .png, .tiff, .rawOnly])
        XCTAssertEqual(PhotoFormatChoice.choices(heif: false, rawOn: false), [.jpeg, .jpegHigh, .png, .tiff])
        // PNG and TIFF come from ImageIO, so every phone offers them.
        for heif in [false, true] {
            for rawOn in [false, true] {
                let rows = PhotoFormatChoice.choices(heif: heif, rawOn: rawOn)
                XCTAssertTrue(rows.contains(.png) && rows.contains(.tiff))
                XCTAssertEqual(rows.contains(.heifHigh), heif)
                XCTAssertEqual(rows.contains(.rawOnly), rawOn)
            }
        }
    }

    // MARK: - RAW

    func testRawDetailsTellTheTwoKindsApart() {
        XCTAssertNil(RawFormat.none.detail)
        XCTAssertEqual(RawFormat.bayer.detail, "No processing. The sensor's data.")
        XCTAssertEqual(RawFormat.proRAW.detail, "Apple's processing. Any zoom.")
        XCTAssertEqual(RawFormat.allCases.map(\.title), ["Off", "RAW", "ProRAW"])
    }

    // MARK: - Resolution

    private let twelve = 4032 * 3024
    private let twentyFour = 5712 * 4284
    private let fortyEight = 8064 * 6048
    private let frontSquare = 4224 * 4224

    func testTwoSizesAreOffered() {
        XCTAssertEqual(PhotoResolution.offered, [.mp12, .mp48])
        XCTAssertEqual(PhotoResolution.mp12.shownAs, .mp12)
        XCTAssertEqual(PhotoResolution.mp24.shownAs, .mp12)
        XCTAssertEqual(PhotoResolution.automatic.shownAs, .mp48)
        XCTAssertEqual(PhotoResolution.mp48.shownAs, .mp48)
        for resolution in PhotoResolution.allCases {
            XCTAssertTrue(PhotoResolution.offered.contains(resolution.shownAs), resolution.rawValue)
        }
        for resolution in PhotoResolution.offered {
            XCTAssertEqual(resolution.shownAs, resolution, resolution.rawValue)
        }
        // A fresh install keeps Largest, which shows as 48 MP.
        XCTAssertEqual(CaptureOptions().resolution, .automatic)
        // The cases stay, so saves that hold them decode.
        XCTAssertEqual(PhotoResolution.allCases.map(\.rawValue), ["automatic", "mp12", "mp24", "mp48"])
    }

    func testEachRowShowsAsTheSizeItGets() {
        // On a 12 MP lens, a 48 MP one and an 18 MP square front camera, Largest gets what 48 MP gets, and 24 MP
        // what 12 MP gets wherever no 24 MP size is delivered: so the row a stored value shows as is the size the
        // photo gets.
        for counts in [[twelve, fortyEight], [twelve], [frontSquare], [twelve, twentyFour, fortyEight]] {
            for resolution in PhotoResolution.allCases where resolution != .mp24 || !counts.contains(twentyFour) {
                XCTAssertEqual(resolution.pick(amongPixelCounts: counts),
                               resolution.shownAs.pick(amongPixelCounts: counts), "\(resolution.rawValue) \(counts)")
            }
        }
    }

    func testThePickRule() {
        // A "48 MP" sensor delivers 48.8 and counts as 48.
        XCTAssertEqual(PhotoResolution.mp48.pick(amongPixelCounts: [twelve, fortyEight]), 1)
        XCTAssertEqual(PhotoResolution.mp12.pick(amongPixelCounts: [twelve, fortyEight]), 0)
        // A lens without the size gives the largest it has under it, or else its smallest.
        XCTAssertEqual(PhotoResolution.mp48.pick(amongPixelCounts: [twelve]), 0)
        XCTAssertEqual(PhotoResolution.mp12.pick(amongPixelCounts: [frontSquare]), 0)
        XCTAssertEqual(PhotoResolution.mp12.pick(amongPixelCounts: [fortyEight, frontSquare]), 1)
        XCTAssertEqual(PhotoResolution.mp24.pick(amongPixelCounts: [twelve, fortyEight]), 0)
        XCTAssertEqual(PhotoResolution.mp24.pick(amongPixelCounts: [twelve, twentyFour, fortyEight]), 1)
        // Largest is the largest.
        XCTAssertEqual(PhotoResolution.automatic.pick(amongPixelCounts: [twelve, fortyEight, frontSquare]), 1)
        XCTAssertEqual(PhotoResolution.automatic.pick(amongPixelCounts: [twelve]), 0)
        // The index is into the list as given, in any order.
        XCTAssertEqual(PhotoResolution.automatic.pick(amongPixelCounts: [fortyEight, twelve]), 0)
        XCTAssertEqual(PhotoResolution.mp12.pick(amongPixelCounts: [fortyEight, twelve]), 1)
        // A size "not clearly above" means up to a tenth over.
        XCTAssertEqual(PhotoResolution.mp12.pick(amongPixelCounts: [12_000_000, 13_200_000]), 1)
        XCTAssertEqual(PhotoResolution.mp12.pick(amongPixelCounts: [12_000_000, 13_200_001]), 0)
    }

    func testNoUsableSizeGivesNone() {
        for resolution in PhotoResolution.allCases {
            XCTAssertNil(resolution.pick(amongPixelCounts: []), resolution.rawValue)
            XCTAssertNil(resolution.pick(amongPixelCounts: [0, -12_192_768]), resolution.rawValue)
            // A size without width or height is passed over.
            XCTAssertEqual(resolution.pick(amongPixelCounts: [0, twelve, -1]), 1, resolution.rawValue)
        }
    }

    func testEqualSizesGoWhereTheSortedListLeftThem() {
        // The largest of equals is the later one, the smallest the earlier.
        XCTAssertEqual(PhotoResolution.automatic.pick(amongPixelCounts: [twelve, twelve]), 1)
        XCTAssertEqual(PhotoResolution.mp48.pick(amongPixelCounts: [fortyEight, twelve, fortyEight]), 2)
        XCTAssertEqual(PhotoResolution.mp12.pick(amongPixelCounts: [frontSquare, fortyEight, frontSquare]), 0)
    }

    func testThePickRuleIsTheCoordinatorsRule() {
        // PhotoCaptureCoordinator.pickDimensions as it was before the rule moved here, on sizes.
        func coordinator(_ resolution: PhotoResolution, _ sizes: [(width: Int, height: Int)]) -> Int? {
            let sorted = sizes.indices
                .filter { sizes[$0].width > 0 && sizes[$0].height > 0 }
                .sorted { sizes[$0].width * sizes[$0].height < sizes[$1].width * sizes[$1].height }
            guard let target = resolution.targetMegapixels else { return sorted.last }
            let limit = Double(target) * 1.1 * 1_000_000
            return sorted.last { Double(sizes[$0].width * sizes[$0].height) <= limit } ?? sorted.first
        }
        let choices: [(width: Int, height: Int)] = [
            (4032, 3024), (5712, 4284), (8064, 6048), (4224, 4224), (3024, 4032), (1920, 1080), (0, 1080),
            (2016, 1512), (7008, 7008),
        ]
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        for _ in 0..<2000 {
            let sizes = (0..<next(6)).map { _ in choices[next(choices.count)] }
            let counts = sizes.map { $0.width > 0 && $0.height > 0 ? $0.width * $0.height : 0 }
            for resolution in PhotoResolution.allCases {
                XCTAssertEqual(resolution.pick(amongPixelCounts: counts), coordinator(resolution, sizes),
                               "\(resolution.rawValue) \(sizes)")
            }
        }
    }
}
