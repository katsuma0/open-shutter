import XCTest
@testable import CameraCore

final class CameraControlRulesTests: XCTestCase {
    // MARK: - Items

    func testItemsKeepTheirStoredNamesInOrder() {
        // Saves hold these names, and Settings lists the ones not picked in this order.
        XCTAssertEqual(CameraControlItem.allCases.map(\.rawValue),
                       ["zoom", "lens", "exposureBias", "shutter", "nightDuration", "nightScene", "iso", "aperture",
                        "whiteBalance", "tint", "focus", "timer", "flash", "histogram", "mode"])
        XCTAssertEqual(CameraControlItem.allCases.map(\.id), CameraControlItem.allCases.map(\.rawValue))
    }

    func testEveryItemHasATitleAndASymbol() {
        XCTAssertEqual(CameraControlItem.allCases.map(\.title),
                       ["Zoom", "Lens", "Exposure", "Shutter", "Night duration", "Night scene", "ISO", "Aperture",
                        "White balance", "Tint", "Focus", "Timer", "Flash", "Histogram", "Mode"])
        XCTAssertEqual(CameraControlItem.allCases.map(\.symbolName),
                       ["plus.magnifyingglass", "camera", "plusminus.circle", "camera.aperture", "hourglass",
                        "moon.stars", "camera.metering.matrix", "camera.aperture", "thermometer.sun", "drop.halffull",
                        "scope", "timer", "bolt", "chart.bar", "camera.on.rectangle"])
        let titles = CameraControlItem.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        for item in CameraControlItem.allCases {
            XCTAssertFalse(item.title.isEmpty, item.rawValue)
            XCTAssertLessThanOrEqual(item.title.count, 20, item.rawValue)
            XCTAssertFalse(item.symbolName.isEmpty, item.rawValue)
            XCTAssertFalse(item.symbolName.contains(" "), item.rawValue)
        }
    }

    func testTheDefaultListAndTheOneBeforeIt() {
        XCTAssertEqual(CameraControlItem.defaultSelection, [.zoom, .lens, .exposureBias, .shutter, .nightDuration, .iso])
        XCTAssertEqual(CameraControlItem.previousDefaultSelection,
                       [.zoom, .lens, .exposureBias, .shutter, .iso, .whiteBalance])
        XCTAssertEqual(ControlOptions().cameraControlItems, CameraControlItem.defaultSelection)
        for list in [CameraControlItem.defaultSelection, CameraControlItem.previousDefaultSelection] {
            XCTAssertLessThanOrEqual(list.count, 6)
            XCTAssertEqual(Set(list).count, list.count)
        }
        // The one-time move only has something to do if the two differ.
        XCTAssertNotEqual(CameraControlItem.defaultSelection, CameraControlItem.previousDefaultSelection)
        // NIGHT's time is on the Camera Control of every phone out of the box.
        XCTAssertTrue(CameraControlItem.defaultSelection.contains(.nightDuration))
    }

    func testListsWithTheNewItemsRoundTrip() throws {
        let decoded = CameraSettings.decoded(from: Data(
            #"{"controls":{"cameraControlItems":["tint","nightScene","timer","flash","histogram","nightDuration"]}}"#.utf8))
        XCTAssertEqual(decoded.controls.cameraControlItems, [.tint, .nightScene, .timer, .flash, .histogram, .nightDuration])
        var settings = CameraSettings()
        settings.controls.cameraControlItems = CameraControlItem.allCases
        XCTAssertEqual(CameraSettings.decoded(from: try settings.encoded()).controls.cameraControlItems,
                       CameraControlItem.allCases)
    }

    // MARK: - Where each one works

    /// The columns of the table: NIGHT has three.
    private enum Column: CaseIterable {
        case photo, manual, nightShot, manualNight, scene, video
    }

    private func column(_ mode: CaptureMode, _ scene: LongExposureScene) -> Column {
        switch mode {
        case .photo: return .photo
        case .manual: return .manual
        case .night: return .nightShot
        case .long: return scene == .custom ? .manualNight : .scene
        case .video: return .video
        }
    }

    /// Where each item is on with nothing running, a white balance set, a single MANUAL shutter and manual shutter
    /// speeds on the phone.
    private let on: [CameraControlItem: Set<Column>] = {
        let every = Set(Column.allCases)
        let byHand: Set<Column> = [.photo, .manual, .manualNight, .video]
        let night: Set<Column> = [.nightShot, .manualNight, .scene]
        return [
            .zoom: every, .lens: every, .exposureBias: every, .mode: every,
            .shutter: [.photo, .manual, .video],
            .nightDuration: night, .nightScene: night,
            .iso: byHand, .aperture: byHand, .whiteBalance: byHand, .tint: byHand, .focus: byHand,
            .timer: every.subtracting([.video]),
            .flash: [.photo, .manual],
            .histogram: [.photo, .manual, .video],
        ]
    }()

    /// What each condition turns off, and in which columns it counts.
    private struct Condition {
        var turnsOff: Set<CameraControlItem>
        var counts: Set<Column>
    }

    private let shotRunning = Condition(
        turnsOff: [.zoom, .lens, .exposureBias, .shutter, .nightDuration, .iso, .aperture, .whiteBalance, .tint, .focus],
        counts: Set(Column.allCases))
    // Timer and Flash too, as the top bar holds them: a sequence reads the flash again for each shot, and a new
    // timer would replace it.
    private let modeLocked = Condition(turnsOff: [.nightScene, .mode, .timer, .flash], counts: Set(Column.allCases))
    // Bulb is a long exposure's: the night shot always runs for a time.
    private let bulb = Condition(turnsOff: [.nightDuration, .timer], counts: [.manualNight, .scene])
    private let autoWhiteBalance = Condition(turnsOff: [.tint], counts: Set(Column.allCases))
    // A stacked shutter is MANUAL's, and stacks never fire the flash.
    private let stackedShutter = Condition(turnsOff: [.flash], counts: [.manual])
    private let noManualShutter = Condition(turnsOff: [.shutter], counts: Set(Column.allCases))

    func testTheTableHasEveryItem() {
        XCTAssertEqual(Set(on.keys), Set(CameraControlItem.allCases))
    }

    func testEveryItemInEveryModeAndState() {
        // Every mode with every scene, so the night shot and the other modes are seen to ignore the stored scene,
        // and every combination of the conditions.
        for mode in CaptureMode.allCases {
            for scene in LongExposureScene.allCases {
                let place = column(mode, scene)
                for flags in 0..<64 {
                    let context = CameraControlContext(
                        mode: mode, scene: scene, bulb: flags & 1 != 0, whiteBalanceIsAuto: flags & 2 != 0,
                        stackedShutter: flags & 4 != 0, shotRunning: flags & 8 != 0, modeLocked: flags & 16 != 0,
                        manualShutterAllowed: flags & 32 == 0)
                    let active: [(Condition, Bool)] = [
                        (bulb, context.bulb), (autoWhiteBalance, context.whiteBalanceIsAuto),
                        (stackedShutter, context.stackedShutter), (shotRunning, context.shotRunning),
                        (modeLocked, context.modeLocked), (noManualShutter, !context.manualShutterAllowed),
                    ]
                    for item in CameraControlItem.allCases {
                        let offByCondition = active.contains { condition, isSet in
                            isSet && condition.counts.contains(place) && condition.turnsOff.contains(item)
                        }
                        let expected = (on[item]?.contains(place) ?? false) && !offByCondition
                        XCTAssertEqual(item.isActive(in: context), expected,
                                       "\(item.rawValue) in \(mode.rawValue)/\(scene.rawValue), flags \(flags)")
                    }
                }
            }
        }
    }

    func testNightLeadsNowhereElse() {
        // In the night shot and the scenes no pick leaves NIGHT but Mode's: Shutter is off, and the values MANUAL
        // shares are set by hand in Manual night only.
        for scene in LongExposureScene.allCases where scene != .custom {
            for mode in [CaptureMode.night, .long] {
                let context = CameraControlContext(mode: mode, scene: scene, bulb: false, whiteBalanceIsAuto: false,
                                                   stackedShutter: false, shotRunning: false, modeLocked: false,
                                                   manualShutterAllowed: true)
                for item in [CameraControlItem.shutter, .iso, .aperture, .whiteBalance, .tint, .focus] {
                    XCTAssertFalse(item.isActive(in: context), "\(item.rawValue) in \(mode.rawValue)/\(scene.rawValue)")
                }
                XCTAssertTrue(CameraControlItem.nightDuration.isActive(in: context))
                XCTAssertTrue(CameraControlItem.nightScene.isActive(in: context))
            }
        }
        let manualNight = CameraControlContext(mode: .long, scene: .custom, bulb: false, whiteBalanceIsAuto: false,
                                               stackedShutter: false, shotRunning: false, modeLocked: false,
                                               manualShutterAllowed: true)
        XCTAssertFalse(CameraControlItem.shutter.isActive(in: manualNight))
        for item in [CameraControlItem.iso, .aperture, .whiteBalance, .tint, .focus] {
            XCTAssertTrue(item.isActive(in: manualNight), item.rawValue)
        }
    }

    // MARK: - Night duration's stops

    func testDurationStops() {
        let standard: [Double] = [1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600, 900, 1200, 1800]
        XCTAssertEqual(NightControlStops.durations(manualShutter: false), standard)
        XCTAssertEqual(NightControlStops.durations(manualShutter: true), [0.25, 0.5] + standard)
        for manualShutter in [false, true] {
            let stops = NightControlStops.durations(manualShutter: manualShutter)
            XCTAssertEqual(stops, stops.sorted())
            XCTAssertEqual(Set(stops).count, stops.count)
            for stop in stops {
                XCTAssertTrue((0.25...1800).contains(stop), "\(stop)")
            }
            // Half an hour, the night shot's longest and the bulb limit's.
            XCTAssertEqual(stops.last, NightModePlanner.secondsRange.upperBound)
            XCTAssertEqual(stops.last, LongExposureSettings().maxBulbSeconds)
            // The picker's titles tell every stop apart.
            let titles = stops.map { ShutterSpeed(seconds: $0).label }
            XCTAssertEqual(Set(titles).count, titles.count, "\(titles)")
        }
        // Without manual shutter speeds nothing shorter than the night shot's own second.
        XCTAssertEqual(NightControlStops.durations(manualShutter: false).first, NightModePlanner.secondsRange.lowerBound)
        XCTAssertEqual(NightControlStops.durations(manualShutter: true).first, 0.25)
    }

    func testEverySceneTimeIsAStop() {
        // A scene pick moves the picker to the scene's time, and its offered times are a detent each. Star trails
        // too: a saved choice still opens.
        for scene in LongExposureScene.allCases {
            guard let recipe = scene.recipe else { continue }
            for manualShutter in [false, true] {
                let stops = NightControlStops.durations(manualShutter: manualShutter)
                for seconds in recipe.durations + [recipe.seconds] {
                    XCTAssertTrue(stops.contains(seconds), "\(scene.rawValue) \(seconds)")
                }
            }
        }
    }

    // MARK: - Night scene's order

    func testTheSceneChoicesAreTheMenusOrder() {
        XCTAssertEqual(LongExposureScene.nightMenuChoices,
                       [nil, .custom, .water, .lightTrails, .stars, .northernLights, .fireworks, .lightPainting])
        XCTAssertEqual(LongExposureScene.nightMenuChoices, [nil, .custom] + LongExposureScene.presets.map { $0 })
        // Each choice once; Star trails is no longer offered.
        XCTAssertEqual(Set(LongExposureScene.nightMenuChoices).count, LongExposureScene.nightMenuChoices.count)
        XCTAssertFalse(LongExposureScene.nightMenuChoices.contains(.starTrails))
        // The night shot first, so index 0 is NIGHT's own shot.
        XCTAssertEqual(LongExposureScene.nightMenuChoices.first, .some(nil))
    }
}
