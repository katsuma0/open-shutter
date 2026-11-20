import XCTest
@testable import CameraCore

final class StarTrailsTests: XCTestCase {
    /// The duration dial's ticks from a second to half an hour, third stops.
    private let dial = ShutterSpeed.scale(minSeconds: 1, maxSeconds: 1800).map(\.seconds)

    private func recipe(_ scene: LongExposureScene) throws -> LongExposureRecipe {
        try XCTUnwrap(scene.recipe, scene.rawValue)
    }

    func testTheRule() throws {
        XCTAssertEqual(StarTrails.rule, 400)
        XCTAssertEqual(try XCTUnwrap(StarTrails.sharpSeconds(equivalentFocalLength: 24)), 400.0 / 24, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(StarTrails.sharpSeconds(equivalentFocalLength: 13)), 400.0 / 13, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(StarTrails.sharpSeconds(equivalentFocalLength: 100)), 4, accuracy: 1e-12)
        // The main camera's 24 mm is about where the Stars recipe's fifteen seconds start to streak.
        XCTAssertEqual(try XCTUnwrap(StarTrails.sharpSeconds(equivalentFocalLength: 24)), 16.7, accuracy: 0.05)
        // A longer lens holds them for less time.
        XCTAssertLessThan(try XCTUnwrap(StarTrails.sharpSeconds(equivalentFocalLength: 48)),
                          try XCTUnwrap(StarTrails.sharpSeconds(equivalentFocalLength: 24)))
    }

    func testNoFocalLengthNoLimit() {
        for focalLength in [0, -24, .nan, .infinity, -.infinity] as [Double] {
            XCTAssertNil(StarTrails.sharpSeconds(equivalentFocalLength: focalLength), "\(focalLength)")
        }
    }

    func testTheLastSharpTick() throws {
        let fifteen = try XCTUnwrap(dial.firstIndex(of: 15))
        XCTAssertEqual(StarTrails.lastSharpIndex(in: dial, limit: 16.7), fifteen)
        XCTAssertEqual(StarTrails.lastSharpIndex(in: dial, limit: 4), dial.firstIndex(of: 4))
        XCTAssertNil(StarTrails.lastSharpIndex(in: dial, limit: 0.5))
        XCTAssertEqual(StarTrails.lastSharpIndex(in: dial, limit: 30.8), dial.firstIndex(of: 30))
        // 2% slack, as the shutter dials take a hardware limit: 15 s against 14.8 is the same tick.
        XCTAssertEqual(StarTrails.lastSharpIndex(in: dial, limit: 14.8), fifteen)
        XCTAssertEqual(StarTrails.lastSharpIndex(in: dial, limit: 14.6), dial.firstIndex(of: 13))
        // Every tick is inside a limit past the dial's end, none inside one that isn't a number.
        XCTAssertEqual(StarTrails.lastSharpIndex(in: dial, limit: .infinity), dial.count - 1)
        XCTAssertEqual(StarTrails.lastSharpIndex(in: dial, limit: 5000), dial.count - 1)
        XCTAssertNil(StarTrails.lastSharpIndex(in: dial, limit: .nan))
        XCTAssertNil(StarTrails.lastSharpIndex(in: [], limit: 16.7))
        // Exactly at the limit is inside.
        XCTAssertEqual(StarTrails.lastSharpIndex(in: [1, 2, 4], limit: 2), 1)
    }

    func testStarsStartsInsideTheLimit() throws {
        let stars = try recipe(.stars)
        XCTAssertEqual(stars.seconds, 15)
        // At 1x the scene's own time is inside.
        XCTAssertEqual(StarTrails.startingSeconds(recipe: stars, limit: 16.7, shortest: 0.25), 15)
        // The limit only shortens: at 0.5x the scene keeps its own.
        XCTAssertEqual(StarTrails.startingSeconds(recipe: stars, limit: 30.8, shortest: 0.25), 15)
        // The longest offered time inside it.
        XCTAssertEqual(StarTrails.startingSeconds(recipe: stars, limit: 12, shortest: 0.25), 10)
        // No offered time fits: the third stop at or under the limit.
        XCTAssertEqual(StarTrails.startingSeconds(recipe: stars, limit: 4, shortest: 0.25), 4)
        XCTAssertEqual(StarTrails.startingSeconds(recipe: stars, limit: 5.5, shortest: 0.25), 5)
        XCTAssertEqual(StarTrails.startingSeconds(recipe: stars, limit: 400.0 / 77, shortest: 0.25), 5)
        // Never under the shortest the camera takes.
        XCTAssertEqual(StarTrails.startingSeconds(recipe: stars, limit: 0.2, shortest: 1), 1)
        // With the same slack as the dial.
        XCTAssertEqual(StarTrails.startingSeconds(recipe: stars, limit: 14.8, shortest: 0.25), 15)
    }

    func testNoLimitChangesNothing() throws {
        let stars = try recipe(.stars)
        for limit in [nil, .nan, .infinity, 0, -3] as [Double?] {
            XCTAssertEqual(StarTrails.startingSeconds(recipe: stars, limit: limit, shortest: 1), 15, "\(String(describing: limit))")
        }
    }

    func testNorthernLights() throws {
        let aurora = try recipe(.northernLights)
        XCTAssertEqual(StarTrails.startingSeconds(recipe: aurora, limit: 4, shortest: 0.25), 4)
        XCTAssertEqual(StarTrails.startingSeconds(recipe: aurora, limit: 16.7, shortest: 0.25), aurora.seconds)
        XCTAssertEqual(StarTrails.startingSeconds(recipe: aurora, limit: 6, shortest: 0.25), 4)
    }

    func testTheStartIsNeverPastTheLimitOrTheScenesOwnTime() throws {
        for scene in LongExposureScene.allCases where scene.limitsStarTrails {
            let recipe = try recipe(scene)
            for focalLength in [13.0, 24, 35, 48, 77, 100, 120, 240] {
                let limit = try XCTUnwrap(StarTrails.sharpSeconds(equivalentFocalLength: focalLength))
                for shortest in [0.25, 1] {
                    let start = StarTrails.startingSeconds(recipe: recipe, limit: limit, shortest: shortest)
                    XCTAssertLessThanOrEqual(start, recipe.seconds, "\(scene.rawValue) \(focalLength)")
                    XCTAssertGreaterThanOrEqual(start, shortest, "\(scene.rawValue) \(focalLength)")
                    XCTAssertTrue(start <= limit * 1.02 || start == shortest, "\(scene.rawValue) \(focalLength)")
                    // The dial shows the start time as sharp.
                    if let index = dial.firstIndex(of: start), let last = StarTrails.lastSharpIndex(in: dial, limit: limit) {
                        XCTAssertLessThanOrEqual(index, last, "\(scene.rawValue) \(focalLength)")
                    }
                }
            }
        }
    }

    func testOnlyTheStarScenesKeepStarsAsPoints() {
        XCTAssertEqual(LongExposureScene.allCases.filter(\.limitsStarTrails), [.stars, .northernLights])
    }
}
