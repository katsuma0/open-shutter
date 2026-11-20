import Foundation

// Where each Camera Control control works. The session carries one set of controls for every mode, as Apple's
// guidelines ask: a rebuild on every mode change would pull the overlay out from under the finger. So the set
// stays, and a control with nothing to do in the current mode stays in it, disabled, the way the screen's own
// control for the same thing dims in place.

/// What the camera is doing, as far as the Camera Control's controls care.
public struct CameraControlContext: Hashable, Sendable {
    public var mode: CaptureMode
    /// The long exposure's scene; read in .long only, where Custom is Manual night.
    public var scene: LongExposureScene
    /// The long exposure runs until it is stopped. Read in .long only: a night shot always runs for a time.
    public var bulb: Bool
    /// The white balance the camera runs is automatic, so there is no tint to set. A scene's fixed temperature
    /// counts as set.
    public var whiteBalanceIsAuto: Bool
    /// A MANUAL shutter past the sensor's longest frame, shot as a stack.
    public var stackedShutter: Bool
    /// A photo, a stack or a save is under way: the dials on screen are locked too, as a change would end up in
    /// the picture. Recording a video isn't one.
    public var shotRunning: Bool
    /// The mode can't change now: busy, recording included, or an intervalometer runs.
    public var modeLocked: Bool
    /// The phone takes manual shutter speeds.
    public var manualShutterAllowed: Bool

    /// Every value is the caller's to give: a default here would quietly decide a control for the model.
    public init(mode: CaptureMode, scene: LongExposureScene, bulb: Bool, whiteBalanceIsAuto: Bool,
                stackedShutter: Bool, shotRunning: Bool, modeLocked: Bool, manualShutterAllowed: Bool) {
        self.mode = mode
        self.scene = scene
        self.bulb = bulb
        self.whiteBalanceIsAuto = whiteBalanceIsAuto
        self.stackedShutter = stackedShutter
        self.shotRunning = shotRunning
        self.modeLocked = modeLocked
        self.manualShutterAllowed = manualShutterAllowed
    }

    /// Manual night: the one place in NIGHT with MANUAL's chips, so the one place there its values are set by hand.
    var isManualNight: Bool { mode == .long && scene == .custom }

    /// A long exposure on bulb has no time to set and no timer to wait for: the hold is the time.
    var runsOnBulb: Bool { mode == .long && bulb }
}

extension CameraControlItem {
    /// The control does something now. The ones that don't stay in the overlay, disabled.
    public func isActive(in context: CameraControlContext) -> Bool {
        let mode = context.mode
        switch self {
        case .zoom, .exposureBias, .lens:
            // Lens keeps working while a video records: it zooms there.
            return !context.shotRunning
        case .shutter:
            // In NIGHT the time is Night duration's, on every phone. A PHOTO pick leads to MANUAL, as the dial does.
            return context.manualShutterAllowed && !context.shotRunning
                && (mode == .photo || mode == .manual || mode == .video)
        case .nightDuration:
            return mode.usesStacking && !context.runsOnBulb && !context.shotRunning
        case .nightScene:
            // A scene pick can switch between the night shot and the scenes, so it waits as a mode change does.
            return mode.usesStacking && !context.modeLocked
        case .iso, .aperture, .whiteBalance, .focus:
            return Self.setsValuesByHand(context)
        case .tint:
            return Self.setsValuesByHand(context) && !context.whiteBalanceIsAuto
        case .mode:
            return !context.modeLocked
        case .timer:
            // Timer and Flash wait out a countdown, a shot, a sequence or a save, as the top bar's own do: a new
            // timer would replace the intervalometer under way, and every bracket frame and intervalometer shot reads
            // the flash again.
            return mode != .video && !context.runsOnBulb && !context.modeLocked
        case .flash:
            // Stacks never fire it, a stacked MANUAL shutter included.
            return (mode == .photo || (mode == .manual && !context.stackedShutter)) && !context.modeLocked
        case .histogram:
            return mode.hasHistogram
        }
    }

    /// Where ISO, aperture, white balance, tint and focus are set by hand: MANUAL, VIDEO, Manual night, and PHOTO,
    /// where a pick leads to MANUAL as the chips' do. The night shot and the scenes keep them to themselves.
    private static func setsValuesByHand(_ context: CameraControlContext) -> Bool {
        guard !context.shotRunning else { return false }
        switch context.mode {
        case .photo, .manual, .video: return true
        case .long: return context.isManualNight
        case .night: return false
        }
    }
}

/// The times the Camera Control's Night duration picker offers. One list for the night shot and every scene, so a
/// scene pick changes the picker's value and never its titles, which only a rebuild of the controls could change.
public enum NightControlStops {
    /// A second to half an hour, every time a scene starts at or offers among them. With manual shutter speeds a
    /// quarter and half a second come first, the shortest a long exposure runs there; the night shot's eighth of a
    /// second stays the dial's.
    public static func durations(manualShutter: Bool) -> [Double] {
        manualShutter ? [0.25, 0.5] + fromOneSecond : fromOneSecond
    }

    private static let fromOneSecond: [Double] = [
        1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600, 900, 1200, 1800,
    ]
}

extension LongExposureScene {
    /// NIGHT's choices in the order of its scene menu: the night shot (nil), Manual night (Custom), then the scenes.
    /// The menu and the Camera Control's Night scene picker both list them from here, so an index means the same
    /// choice in both.
    public static let nightMenuChoices: [LongExposureScene?] = [nil, .custom] + presets
}
