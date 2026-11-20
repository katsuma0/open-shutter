import XCTest
@testable import CameraCore

final class FocusMagnifierTests: XCTestCase {
    func testPowersAndTitles() {
        XCTAssertEqual(FocusMagnifier.allCases.map(\.rawValue), ["off", "x5", "x10"])
        XCTAssertEqual(FocusMagnifier.allCases.map(\.power), [1, 5, 10])
        XCTAssertEqual(FocusMagnifier.allCases.map(\.title), ["Off", "5\u{00D7}", "10\u{00D7}"])
        XCTAssertEqual(FocusMagnifier.allCases.map(\.id), FocusMagnifier.allCases.map(\.rawValue))
        // The badge's label for each power reads as the title does.
        for magnifier in FocusMagnifier.allCases where magnifier != .off {
            XCTAssertEqual(LensMath.zoomLabel(magnifier.power, selected: true), magnifier.title)
        }
    }

    private func focusOptions(saved json: String) -> FocusOptions {
        CameraSettings.decoded(from: Data(#"{"focusOptions":\#(json)}"#.utf8)).focusOptions
    }

    func testFiveTimesUnlessSaidOtherwise() throws {
        XCTAssertEqual(FocusOptions().magnifier, .x5)
        XCTAssertEqual(CameraSettings.default.focusOptions.magnifier, .x5)
        // Saved before the magnifier existed.
        let older = focusOptions(saved: #"{"range":"far","smooth":true}"#)
        XCTAssertEqual(older.magnifier, .x5)
        XCTAssertEqual(older.range, .far)
        XCTAssertTrue(older.smooth)
        // A choice from a later version, or of the wrong type, costs that one value.
        for value in [#""x20""#, "5", "null"] {
            let odd = focusOptions(saved: #"{"range":"near","magnifier":\#(value),"continuousTracking":true}"#)
            XCTAssertEqual(odd.magnifier, .x5, value)
            XCTAssertEqual(odd.range, .near, value)
            XCTAssertTrue(odd.continuousTracking, value)
        }
        for magnifier in FocusMagnifier.allCases {
            var settings = CameraSettings()
            settings.focusOptions.magnifier = magnifier
            XCTAssertEqual(CameraSettings.decoded(from: try settings.encoded()).focusOptions.magnifier, magnifier)
        }
    }

    func testDeviceZoom() {
        XCTAssertEqual(MagnifierMath.deviceZoom(base: 1, power: 5, range: 1...15), 5)
        XCTAssertEqual(MagnifierMath.deviceZoom(base: 2, power: 5, range: 1...15), 10)
        XCTAssertEqual(MagnifierMath.deviceZoom(base: 1, power: 10, range: 1...15), 10)
        // The lens's range runs out first.
        XCTAssertEqual(MagnifierMath.deviceZoom(base: 4, power: 5, range: 1...15), 15)
        XCTAssertEqual(MagnifierMath.deviceZoom(base: 2, power: 1, range: 1...15), 2)
        XCTAssertEqual(MagnifierMath.deviceZoom(base: 2, power: FocusMagnifier.off.power, range: 1...15), 2)
    }

    func testAPowerThatIsntOneOrMoreLeavesTheFrameAsItIs() {
        for power in [0.5, 0, -5, .nan, .infinity, -.infinity] as [Double] {
            XCTAssertEqual(MagnifierMath.deviceZoom(base: 2, power: power, range: 1...15), 2, "\(power)")
        }
    }

    func testABaseOutsideTheRangeIsClampedFirst() {
        XCTAssertEqual(MagnifierMath.deviceZoom(base: 20, power: 5, range: 1...15), 15)
        XCTAssertEqual(MagnifierMath.deviceZoom(base: 20, power: 1, range: 1...15), 15)
        XCTAssertEqual(MagnifierMath.deviceZoom(base: 0.5, power: 5, range: 1...15), 5)
        XCTAssertEqual(MagnifierMath.deviceZoom(base: .nan, power: 5, range: 1...15), 5)
        XCTAssertEqual(MagnifierMath.deviceZoom(base: .infinity, power: 5, range: 1...15), 15)
    }

    func testShownPower() {
        // A 5x asked of a 2x lens that stops at 15 shows what it got.
        XCTAssertEqual(MagnifierMath.shownPower(base: 2, deviceZoom: 15), 7.5)
        XCTAssertEqual(MagnifierMath.shownPower(base: 1, deviceZoom: 5), 5)
        XCTAssertEqual(MagnifierMath.shownPower(base: 1.5, deviceZoom: 15), 10)
        // Rounded to a tenth.
        XCTAssertEqual(MagnifierMath.shownPower(base: 3, deviceZoom: 14), 4.7)
        XCTAssertEqual(MagnifierMath.shownPower(base: 1, deviceZoom: 5.04), 5)
        XCTAssertEqual(LensMath.zoomLabel(MagnifierMath.shownPower(base: 2, deviceZoom: 15), selected: true), "7.5\u{00D7}")
        // Unusable input, and a device that hasn't zoomed in yet, show the frame as it is.
        for base in [0, -1, .nan, .infinity] as [Double] {
            XCTAssertEqual(MagnifierMath.shownPower(base: base, deviceZoom: 5), 1, "\(base)")
        }
        for zoom in [0, -3, .nan, .infinity] as [Double] {
            XCTAssertEqual(MagnifierMath.shownPower(base: 2, deviceZoom: zoom), 1, "\(zoom)")
        }
        XCTAssertEqual(MagnifierMath.shownPower(base: 2, deviceZoom: 2), 1)
        XCTAssertEqual(MagnifierMath.shownPower(base: 2, deviceZoom: 1), 1)
    }

    func testTheRoundTripOfBothFunctions() {
        // What the badge shows is the power asked for, where the range has room for it.
        for base in [0.5, 1, 2, 3] {
            for magnifier in FocusMagnifier.allCases {
                let zoom = MagnifierMath.deviceZoom(base: base, power: magnifier.power, range: 0.5...100)
                XCTAssertEqual(MagnifierMath.shownPower(base: base, deviceZoom: zoom), magnifier.power,
                               "\(base) \(magnifier.rawValue)")
            }
        }
    }
}
