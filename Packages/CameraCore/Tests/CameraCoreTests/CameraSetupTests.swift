import XCTest
@testable import CameraCore

final class CameraSetupTests: XCTestCase {
    // MARK: - Fixtures

    /// A night on a tripod: Manual night for twenty seconds, ISO 3200, 4000 K, focus near the far end.
    private func milkyWay() -> CameraSettings {
        var s = CameraSettings()
        s.mode = .long
        s.lensID = "com.apple.avfoundation.avcapturedevice.built-in_video:0"
        s.zoom = 1
        s.longExposure.scene = .custom
        s.longExposure.blend = .additive
        s.longExposure.seconds = 20
        s.manual = ManualExposureSetting(shutter: nil, iso: 3200, aperture: nil, bias: -0.3)
        s.whiteBalance = .kelvin(4000, tint: 6)
        s.focus = .manual(lensPosition: 0.97)
        s.capture.processedFormat = .tiff
        s.night.stability = .tripod
        return s
    }

    /// Every shooting field off its default, and every field around them too.
    private func everythingSet() -> CameraSettings {
        var s = CameraSettings()
        s.mode = .manual
        s.lensID = "back.telephoto"
        s.zoom = 4
        s.manual = ManualExposureSetting(shutter: 1.0 / 125, iso: 100, aperture: 2.8, bias: 0.7)
        s.whiteBalance = .preset(.cloudy)
        s.focus = .manual(lensPosition: 0.3)
        s.capture.processedFormat = .jpeg
        s.capture.rawFormat = .proRAW
        s.capture.quality = 0.7
        s.capture.highQuality = true
        s.capture.resolution = .mp12
        s.capture.processing = .minimal
        s.capture.flash = .on
        s.capture.aspect = .square
        s.capture.livePhoto = true
        s.capture.silentShutter = true
        s.capture.depth = true
        s.capture.constantColor = true
        s.capture.lensCorrection = false
        s.capture.mirrorFront = false
        s.capture.saveLocation = true
        s.capture.schedule = CaptureSchedule(delay: 3, shots: 10, interval: 5)
        s.capture.bracket = BracketPlan(kind: .exposure, count: 5, step: 1)
        s.capture.prioritizeSpeed = true
        s.capture.artist = "Sam Rivera"
        s.capture.copyright = "Copyright 2026 Sam Rivera"
        s.exposure.aeMaxShutter = 1.0 / 30
        s.exposure.meteringArea = .spot
        s.focusOptions.range = .far
        s.focusOptions.magnifier = .x10
        s.display.grid = .crosshair
        s.display.histogram = .rgb
        s.display.zebras = true
        s.display.peaking = .always
        s.night.seconds = 8
        s.night.stability = .handheld
        s.night.biasEV = -1
        s.longExposure.apply(.fireworks)
        s.longExposure.seconds = 10
        s.longExposure.maxBulbSeconds = 600
        s.video.resolution = .hd1080
        s.video.frameRate = 60
        s.video.codec = .proRes422
        s.video.colorMode = .appleLog
        s.controls.volumeShutter = false
        s.controls.cameraControlItems = [.zoom, .tint]
        s.interface.advancedSettings = true
        s.appearance.accent = .green
        s.accessibility.leftHanded = true
        s.topBar = TopBarOptions(leading: [.grid], trailing: [])
        s.startup.keepMode = false
        return s
    }

    /// The fields of `settings` by name, each written out.
    private func fields(of settings: CameraSettings) -> [String: String] {
        Dictionary(uniqueKeysWithValues: Mirror(reflecting: settings).children.compactMap { child in
            child.label.map { ($0, String(reflecting: child.value)) }
        })
    }

    // MARK: - Slots

    func testAFreshInstallHasThreeEmptySlots() {
        XCTAssertEqual(CameraSetups.count, 3)
        XCTAssertEqual(CameraSetups().slots, [nil, nil, nil])
        XCTAssertEqual(CameraSettings.default.setups, CameraSetups())
        // An empty save, and one from before the setups.
        XCTAssertEqual(CameraSettings.decoded(from: Data("{}".utf8)).setups, CameraSetups())
        XCTAssertEqual(CameraSettings.decoded(from: Data(#"{"mode":"night","zoom":2}"#.utf8)).setups, CameraSetups())
        XCTAssertEqual(try JSONDecoder().decode(CameraSetups.self, from: Data("{}".utf8)), CameraSetups())
    }

    func testTwoSavedSlotsRoundTrip() throws {
        var settings = CameraSettings()
        settings.setups[0] = CameraSetup(name: "Milky Way", from: milkyWay())
        settings.setups[2] = CameraSetup(name: "", from: everythingSet())
        let decoded = CameraSettings.decoded(from: try settings.encoded())
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.setups[0]?.name, "Milky Way")
        XCTAssertNil(decoded.setups[1])
        XCTAssertEqual(decoded.setups[2]?.capture.rawFormat, .proRAW)
    }

    /// `slots` as JSON, each entry as given.
    private func setups(saved entries: [String]) throws -> CameraSetups {
        try JSONDecoder().decode(CameraSetups.self, from: Data(#"{"slots":[\#(entries.joined(separator: ","))]}"#.utf8))
    }

    private func json(_ setup: CameraSetup) throws -> String {
        String(decoding: try JSONEncoder().encode(setup), as: UTF8.self)
    }

    func testADamagedSlotIsEmptyOnItsOwn() throws {
        let first = CameraSetup(name: "C1", from: milkyWay())
        let third = CameraSetup(name: "C3", from: everythingSet())
        for damage in ["42", #""milky""#, "[1,2]", "true", "null"] {
            let decoded = try setups(saved: [try json(first), damage, try json(third)])
            XCTAssertEqual(decoded.slots, [first, nil, third], damage)
        }
        // A slots list that can't be read at all, or none, leaves all three empty.
        for value in ["7", #""slots""#, "null", #"{"0":{}}"#] {
            let decoded = try JSONDecoder().decode(CameraSetups.self, from: Data(#"{"slots":\#(value)}"#.utf8))
            XCTAssertEqual(decoded, CameraSetups(), value)
        }
        // In a whole save, unreadable setups cost only the setups.
        let settings = CameraSettings.decoded(from: Data(#"{"setups":"C1","mode":"manual"}"#.utf8))
        XCTAssertEqual(settings.setups, CameraSetups())
        XCTAssertEqual(settings.mode, .manual)
    }

    func testAlwaysThreeSlots() throws {
        let setup = CameraSetup(name: "Stars", from: milkyWay())
        let entry = try json(setup)
        let four = try setups(saved: [entry, entry, "null", entry])
        XCTAssertEqual(four.slots, [setup, setup, nil])
        let one = try setups(saved: [entry])
        XCTAssertEqual(one.slots, [setup, nil, nil])
        XCTAssertEqual(try setups(saved: []).slots, [nil, nil, nil])
    }

    func testOutsideTheThreeReadsEmptyAndTakesNothing() {
        var slots = CameraSetups()
        let setup = CameraSetup(name: "C9", from: milkyWay())
        for slot in [-1, 3, 4, Int.max, Int.min] {
            slots[slot] = setup
            XCTAssertNil(slots[slot], "\(slot)")
        }
        XCTAssertEqual(slots, CameraSetups())
        slots[1] = setup
        XCTAssertEqual(slots.slots, [nil, setup, nil])
        slots[1] = nil
        XCTAssertEqual(slots, CameraSetups())
    }

    // MARK: - Decoding one setup

    func testASetupDecodesLeniently() throws {
        let empty = try JSONDecoder().decode(CameraSetup.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, CameraSetup(name: "", from: .default))
        // A wrong value costs that value alone.
        let odd = try JSONDecoder().decode(CameraSetup.self, from: Data(
            #"{"name":"Street","mode":"selfie","zoom":"wide","manual":{"iso":800},"display":{"grid":"thirds"}}"#.utf8))
        XCTAssertEqual(odd.name, "Street")
        XCTAssertEqual(odd.mode, CameraSettings.default.mode)
        XCTAssertEqual(odd.zoom, CameraSettings.default.zoom)
        XCTAssertEqual(odd.manual.iso, 800)
        XCTAssertEqual(odd.display.grid, .thirds)
    }

    func testASavedSceneComesBackWithThisVersionsRecipe() throws {
        // A Stars setup as a version with another blend for Stars saved it: the scene and its time are the
        // setup's, the rest is the recipe as it is now, so the scene doesn't read as changed by hand.
        let saved = #"{"name":"Stars","mode":"long","longExposure":{"scene":"stars","seconds":20,"blend":"lighten","bulb":true,"align":true}}"#
        let setup = try JSONDecoder().decode(CameraSetup.self, from: Data(saved.utf8))
        var wanted = LongExposureSettings()
        wanted.apply(.stars)
        wanted.seconds = 20
        XCTAssertEqual(setup.longExposure, wanted)
        XCTAssertEqual(setup.longExposure.blend, .additive)
    }

    func testASetupWithNothingToSaveGetsHEIF() throws {
        let saved = #"{"name":"Odd","capture":{"processedFormat":"none","rawFormat":"none","quality":0.6}}"#
        let setup = try JSONDecoder().decode(CameraSetup.self, from: Data(saved.utf8))
        XCTAssertEqual(setup.capture.processedFormat, .heif)
        XCTAssertTrue(setup.capture.isValid)
        XCTAssertEqual(setup.capture.quality, 0.6, accuracy: 1e-9)
    }

    // MARK: - Recall

    func testRecallBringsBackEveryShootingField() {
        let saved = everythingSet()
        let recalled = CameraSetup(name: "Sport", from: saved).applied(to: .default)
        XCTAssertEqual(recalled.mode, saved.mode)
        XCTAssertEqual(recalled.manual, saved.manual)
        XCTAssertEqual(recalled.whiteBalance, saved.whiteBalance)
        XCTAssertEqual(recalled.focus, saved.focus)
        XCTAssertEqual(recalled.exposure, saved.exposure)
        XCTAssertEqual(recalled.focusOptions, saved.focusOptions)
        XCTAssertEqual(recalled.display, saved.display)
        XCTAssertEqual(recalled.night, saved.night)
        XCTAssertEqual(recalled.longExposure, saved.longExposure)
        XCTAssertEqual(recalled.video, saved.video)
        // The capture, but for what is the person's.
        var capture = saved.capture
        capture.artist = ""
        capture.copyright = ""
        capture.saveLocation = false
        capture.mirrorFront = true
        XCTAssertEqual(recalled.capture, capture)
    }

    func testRecallKeepsWhatIsntTheShots() {
        let base = everythingSet()
        let recalled = CameraSetup(name: "Night", from: milkyWay()).applied(to: base)
        XCTAssertEqual(recalled.capture.artist, base.capture.artist)
        XCTAssertEqual(recalled.capture.copyright, base.capture.copyright)
        XCTAssertEqual(recalled.capture.saveLocation, base.capture.saveLocation)
        XCTAssertEqual(recalled.capture.mirrorFront, base.capture.mirrorFront)
        // The model moves the lens itself.
        XCTAssertEqual(recalled.lensID, base.lensID)
        XCTAssertEqual(recalled.zoom, base.zoom)
        XCTAssertEqual(recalled.controls, base.controls)
        XCTAssertEqual(recalled.interface, base.interface)
        XCTAssertEqual(recalled.appearance, base.appearance)
        XCTAssertEqual(recalled.accessibility, base.accessibility)
        XCTAssertEqual(recalled.topBar, base.topBar)
        XCTAssertEqual(recalled.startup, base.startup)
        XCTAssertEqual(recalled.setups, base.setups)
        // And the setup's own shooting fields arrive.
        XCTAssertEqual(recalled.mode, .long)
        XCTAssertEqual(recalled.capture.processedFormat, .tiff)
        XCTAssertEqual(recalled.longExposure.seconds, 20)
    }

    func testEverySettingIsTheSetupsOrStays() {
        // Every field of the settings, by name, either comes from the setup or stays as the base has it, so a
        // setting added later has to be sorted into one or the other here.
        let stays: Set<String> = ["lensID", "zoom", "controls", "interface", "appearance", "accessibility", "topBar",
                                  "startup", "setups"]
        var base = CameraSettings()
        base.setups[0] = CameraSetup(name: "Kept", from: milkyWay())
        let saved = everythingSet()
        let recalled = fields(of: CameraSetup(name: "", from: saved).applied(to: base))
        let fromBase = fields(of: base)
        let fromSaved = fields(of: saved)
        XCTAssertEqual(Set(recalled.keys), Set(fromBase.keys))
        XCTAssertTrue(stays.isSubset(of: Set(recalled.keys)))
        for (name, value) in recalled where name != "capture" {
            if stays.contains(name) {
                XCTAssertEqual(value, fromBase[name], name)
            } else {
                XCTAssertEqual(value, fromSaved[name], name)
                // A field the fixture leaves at its default couldn't show it was copied.
                XCTAssertNotEqual(fromSaved[name], fromBase[name], "everythingSet() leaves \(name) as the base has it")
            }
        }
        // The setup holds the settings' shooting fields under the same names, with its name beside them.
        let setupFields = Set(Mirror(reflecting: CameraSetup(name: "", from: saved)).children.compactMap(\.label))
        XCTAssertEqual(setupFields, Set(recalled.keys).subtracting(stays).union(["name", "lensID", "zoom"]))
    }

    func testASetupSavedAndRecalledIsTheSettingsItWasSavedFrom() {
        for settings in [milkyWay(), everythingSet(), CameraSettings.default] {
            let setup = CameraSetup(name: "C1", from: settings)
            XCTAssertEqual(setup.applied(to: settings), settings)
            XCTAssertEqual(setup.lensID, settings.lensID)
            XCTAssertEqual(setup.zoom, settings.zoom)
        }
    }

    // MARK: - Summary

    func testSummaries() {
        XCTAssertEqual(CameraSetup(name: "", from: milkyWay()).summary,
                       "Manual night \u{00B7} 20s \u{00B7} ISO 3200 \u{00B7} 4000K \u{00B7} MF 97%")

        var stars = CameraSettings()
        stars.mode = .long
        stars.longExposure.apply(.stars)
        XCTAssertEqual(CameraSetup(name: "", from: stars).summary, "Stars \u{00B7} 15s")

        var night = CameraSettings()
        night.mode = .night
        night.night.seconds = 10
        night.night.stability = .tripod
        XCTAssertEqual(CameraSetup(name: "", from: night).summary, "Night shot \u{00B7} 10s \u{00B7} Tripod")

        var manual = CameraSettings()
        manual.mode = .manual
        manual.manual = ManualExposureSetting(shutter: 1.0 / 125, iso: 100)
        XCTAssertEqual(CameraSetup(name: "", from: manual).summary, "Manual \u{00B7} 1/125 \u{00B7} ISO 100")

        var photo = CameraSettings()
        photo.capture.rawFormat = .bayer
        XCTAssertEqual(CameraSetup(name: "", from: photo).summary, "Photo \u{00B7} HEIF \u{00B7} RAW")

        var video = CameraSettings()
        video.mode = .video
        XCTAssertEqual(CameraSetup(name: "", from: video).summary, "Video \u{00B7} 4K \u{00B7} 30 \u{00B7} HEVC")
    }

    func testSummariesLeaveOutWhatTheCameraChooses() {
        var night = CameraSettings()
        night.mode = .night
        night.night.seconds = nil
        night.night.stability = .automatic
        XCTAssertEqual(CameraSetup(name: "", from: night).summary, "Night shot")
        night.night.stability = .handheld
        XCTAssertEqual(CameraSetup(name: "", from: night).summary, "Night shot \u{00B7} Handheld")

        var manual = CameraSettings()
        manual.mode = .manual
        XCTAssertEqual(CameraSetup(name: "", from: manual).summary, "Manual")
        manual.manual = ManualExposureSetting(shutter: 30, iso: nil, aperture: 2.8)
        manual.whiteBalance = .preset(.tungsten)
        manual.focus = .manual(lensPosition: 0.5)
        XCTAssertEqual(CameraSetup(name: "", from: manual).summary,
                       "Manual \u{00B7} 30s \u{00B7} \u{0192}/2.8 \u{00B7} 3200K \u{00B7} MF 50%")
        // The auto preset is auto white balance.
        manual.whiteBalance = .preset(.auto)
        manual.focus = .auto
        XCTAssertEqual(CameraSetup(name: "", from: manual).summary, "Manual \u{00B7} 30s \u{00B7} \u{0192}/2.8")
    }

    func testSummariesForTheOtherShapesOfASetup() {
        var bulb = CameraSettings()
        bulb.mode = .long
        bulb.longExposure.apply(.lightPainting)
        XCTAssertEqual(CameraSetup(name: "", from: bulb).summary, "Light painting \u{00B7} Bulb")
        var trails = CameraSettings()
        trails.mode = .long
        trails.longExposure.apply(.starTrails)
        XCTAssertEqual(CameraSetup(name: "", from: trails).summary, "Star trails \u{00B7} 30m")

        var photo = CameraSettings()
        PhotoFormatChoice.jpegHigh.apply(to: &photo.capture)
        photo.capture.rawFormat = .proRAW
        XCTAssertEqual(CameraSetup(name: "", from: photo).summary, "Photo \u{00B7} JPEG High \u{00B7} ProRAW")
        photo.capture.processedFormat = .none
        XCTAssertEqual(CameraSetup(name: "", from: photo).summary, "Photo \u{00B7} ProRAW only")
        photo.capture.rawFormat = .bayer
        XCTAssertEqual(CameraSetup(name: "", from: photo).summary, "Photo \u{00B7} RAW only")
        photo.capture.processedFormat = .tiff
        photo.capture.rawFormat = .none
        XCTAssertEqual(CameraSetup(name: "", from: photo).summary, "Photo \u{00B7} TIFF")

        var video = CameraSettings()
        video.mode = .video
        video.video.resolution = .hd1080
        video.video.frameRate = 29.97
        video.video.codec = .proRes422HQ
        video.video.colorMode = .appleLog
        XCTAssertEqual(CameraSetup(name: "", from: video).summary,
                       "Video \u{00B7} 1080p \u{00B7} 29.97 \u{00B7} ProRes 422 HQ \u{00B7} Apple Log")
    }

    func testNightTimesReadAsTheirChipDoes() {
        // The 18 Pro's night shot goes down to 1/8 s and Manual night to 1/4 s. The moon chip and the duration
        // dial write those as shutter speeds, and so does the line: rounded to a tenth, 1/8 would read "0.1s".
        var night = CameraSettings()
        night.mode = .night
        night.night.seconds = 0.125
        night.night.stability = .automatic
        XCTAssertEqual(CameraSetup(name: "", from: night).summary, "Night shot \u{00B7} 1/8")
        var manualNight = CameraSettings()
        manualNight.mode = .long
        manualNight.longExposure.scene = .custom
        manualNight.longExposure.seconds = 0.25
        XCTAssertEqual(CameraSetup(name: "", from: manualNight).summary, "Manual night \u{00B7} 1/4")
        manualNight.longExposure.seconds = 0.5
        XCTAssertEqual(CameraSetup(name: "", from: manualNight).summary, "Manual night \u{00B7} 0.5s")
        // From a second up, the chip's own words.
        manualNight.longExposure.seconds = 1
        XCTAssertEqual(CameraSetup(name: "", from: manualNight).summary, "Manual night \u{00B7} 1s")
        manualNight.longExposure.seconds = 90
        XCTAssertEqual(CameraSetup(name: "", from: manualNight).summary, "Manual night \u{00B7} 1m 30s")
    }

    func testSummariesArePlain() {
        let shapes = [milkyWay(), everythingSet(), CameraSettings.default]
        for settings in shapes {
            for mode in CaptureMode.allCases {
                var s = settings
                s.mode = mode
                let summary = CameraSetup(name: "", from: s).summary
                XCTAssertFalse(summary.isEmpty, mode.rawValue)
                XCTAssertFalse(summary.contains("\u{2014}"), summary)
                XCTAssertFalse(summary.contains("nan"), summary)
                XCTAssertFalse(summary.hasSuffix(" "), summary)
            }
        }
    }
}
