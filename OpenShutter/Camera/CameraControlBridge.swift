import Foundation
import AVFoundation
import CameraCore

/// Puts the person's own list of controls on the iPhone 16+ Camera Control (the hardware button's light-press
/// overlay): shutter, NIGHT's duration and scene, ISO, aperture, white balance, tint, focus, the timer, flash, the
/// histogram and the mode, next to Apple's system zoom and exposure sliders. The set is built once per lens and
/// stays through mode changes, as Apple's guidelines ask: a mode only changes the values and which controls can be
/// used, so the overlay never rebuilds under the finger.
final class CameraControlBridge: NSObject, AVCaptureSessionControlsDelegate, @unchecked Sendable {
    /// Called on the controls queue when the user moves one of our controls.
    var onChange: (@Sendable (CameraControlChange) -> Void)? {
        get { lock.withLock { changeHandler } }
        set { lock.withLock { changeHandler = newValue } }
    }

    /// Called on the controls queue when the overlay enters or leaves its fullscreen appearance.
    var onFullscreenChange: (@Sendable (Bool) -> Void)? {
        get { lock.withLock { fullscreenHandler } }
        set { lock.withLock { fullscreenHandler = newValue } }
    }

    /// Called on the controls queue when a light press brings up the overlay, before any fullscreen appearance.
    var onBecomeActive: (@Sendable () -> Void)? {
        get { lock.withLock { activeHandler } }
        set { lock.withLock { activeHandler = newValue } }
    }

    let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
    }

    // MARK: - Installing (session queue)

    /// Whether `state` needs new controls on `session`: another camera or session, another list, or new titles or
    /// stops on a control that is installed. Anything else is a value or an enabled flag, which
    /// `update(on:device:state:)` sets without configuring the session.
    func needsRebuild(on session: AVCaptureSession, device: AVCaptureDevice, state: CameraControlState) -> Bool {
        let wanted = Self.layout(for: state, device: device, session: session)
        let installed = lock.withLock { layout == wanted ? entries : nil }
        guard let installed else { return true }
        return !Self.isInstalled(installed, on: session)
    }

    /// The person moved one of the controls since the latest state arrived. A pick the model refused leaves its
    /// state as it was, and the same state sent again is what takes the control back.
    var touchedSinceLatestState: Bool {
        lock.withLock { lastTouch.values.contains { $0 > stateArrival } }
    }

    /// Inside begin/commitConfiguration. Replaces all controls on `session` with ones for `state`. Does nothing when
    /// the session doesn't support controls.
    func install(on session: AVCaptureSession, device: AVCaptureDevice, state: CameraControlState) {
        guard session.supportsControls else {
            lock.withLock {
                layout = nil
                entries = []
                pendingEcho = [:]
                currentDevice = nil
            }
            return
        }
        let now = DispatchTime.now().uptimeNanoseconds
        let wanted = Self.layout(for: state, device: device, session: session)
        lock.withLock {
            latestState = state
            stateArrival = now
            currentDevice = device
        }
        for control in session.controls {
            session.removeControl(control)
        }
        var added: [Entry] = []
        let limit = session.maxControlsCount
        for item in wanted.items where added.count < limit {
            let entry = makeEntry(for: item, layout: wanted, device: device)
            // Before it joins the session, so a control with nothing to do in this mode never shows as usable.
            entry.control.isEnabled = !state.disabledItems.contains(item)
            guard session.canAddControl(entry.control) else { continue }
            session.addControl(entry.control)
            added.append(entry)
        }
        lock.withLock {
            layout = wanted
            entries = added
            lastTouch = [:]
            pendingEcho = [:]
        }
        scheduleValues(from: state, for: added, device: device, sparingRecentTouches: false)
        attachDelegate(to: session)
    }

    /// Outside any configuration: the installed controls take `state`'s values and enabled flags. A new state can
    /// arrive while a finger is still on the button (a closing dial, a pick that changed the mode); a control
    /// touched within the grace keeps the finger's value for now and gets the latest state once the grace is over.
    func update(on session: AVCaptureSession, device: AVCaptureDevice, state: CameraControlState) {
        let now = DispatchTime.now().uptimeNanoseconds
        let installed = lock.withLock { () -> [Entry] in
            latestState = state
            stateArrival = now
            currentDevice = device
            return entries
        }
        scheduleValues(from: state, for: installed, device: device, sparingRecentTouches: true)
        attachDelegate(to: session)
    }

    // MARK: - Delegate (controls queue)

    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        let snapshot = lock.withLock { (state: latestState, entries: entries, device: currentDevice, active: activeHandler) }
        // The system zoom slider reads the device's zoom from now on, which the focus magnifier has enlarged past the
        // photo's, so the model ends it before the first swipe.
        snapshot.active?()
        guard let state = snapshot.state else { return }
        // The model sends its state after every pick, a refused or clamped one included, so the latest state is
        // right for every control. One touched within the grace is brought up to date once the grace is over.
        applyEnabled(Self.enabledFlags(from: state, for: snapshot.entries))
        applyValues(Self.targets(from: state, for: snapshot.entries, device: snapshot.device), sparingRecentTouches: true)
    }

    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        setFullscreen(true)
    }

    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        setFullscreen(false)
    }

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        // Exit normally arrives first; this covers the overlay going away without it.
        setFullscreen(false)
    }

    // MARK: - State

    /// One control we added and the values behind it.
    private struct Entry {
        let item: CameraControlItem
        let control: AVCaptureControl
        /// Values behind picker indexes 1...n; index 0 is Auto. Empty for sliders, system controls and pickers
        /// without an Auto.
        let stops: [Double]
    }

    /// What the installed controls were built from. Anything else needs new controls. A control's stops and titles
    /// are kept only while it is in the list, since a control that isn't installed can't need rebuilding.
    private struct Layout: Equatable {
        var session: ObjectIdentifier
        var deviceID: String
        var items: [CameraControlItem]
        var shutterStops: [Double]
        var isoStops: [Double]
        var apertureStops: [Double]
        var lensTitles: [String]
        var durationStops: [Double]
        var sceneTitles: [String]
    }

    private enum Target {
        case index(Int)
        case value(Float)

        func matches(_ other: Target) -> Bool {
            switch (self, other) {
            case let (.index(a), .index(b)): return a == b
            case let (.value(a), .value(b)): return abs(a - b) <= CameraControlBridge.valueTolerance
            default: return false
            }
        }
    }

    /// What `applyValues` did with one control's new value.
    private enum Claim {
        case applied
        /// The finger moved the control at this uptime, within the grace.
        case spared(UInt64)
        /// A rebuild replaced the control since the value was worked out.
        case gone
    }

    private let lock = NSLock()
    private var changeHandler: (@Sendable (CameraControlChange) -> Void)?
    private var fullscreenHandler: (@Sendable (Bool) -> Void)?
    private var activeHandler: (@Sendable () -> Void)?
    private var layout: Layout?
    private var entries: [Entry] = []
    private var latestState: CameraControlState?
    /// Uptime in nanoseconds when `latestState` arrived.
    private var stateArrival: UInt64 = 0
    /// The camera the controls belong to. Only read, for the focus and white balance it chose on its own.
    private weak var currentDevice: AVCaptureDevice?
    /// Uptime in nanoseconds of the user's last move on each control.
    private var lastTouch: [CameraControlItem: UInt64] = [:]
    /// The value this bridge last set on each control, until the control reports anything. Apple doesn't say
    /// whether a value set in code comes back through the action; if it does, it is the model's own value
    /// snapped to a stop or step, and sending it back would quietly move the model.
    private var pendingEcho: [CameraControlItem: Target] = [:]
    private var isFullscreen = false

    /// How long after the user's last move a control ignores values coming back from the model, which lag
    /// behind the finger and would otherwise pull the control backwards.
    private static let touchGrace: UInt64 = 700_000_000
    /// Slider values closer than this count as the same.
    private static let valueTolerance: Float = 0.0001
    private static let kelvinRange: ClosedRange<Float> = 2000...10000
    private static let kelvinStep: Float = 100
    private static let tintRange = Float(WhiteBalanceMath.tintRange.lowerBound)...Float(WhiteBalanceMath.tintRange.upperBound)
    private static let tintStep: Float = 1
    /// Daylight, shown for automatic white balance when the camera's own temperature can't be read.
    private static let neutralKelvin = 5500.0
    /// The middle of the lens travel, shown for autofocus when the lens position can't be read.
    private static let neutralFocus = 0.5

    /// The Timer picker's delays, Off first, and Custom after them for a burst, an intervalometer or another delay
    /// from the timer sheet. The model reads a pick's index into the same CameraCore list, and Custom's index is the
    /// list's count.
    private static var timerDelays: [Double] { CaptureSchedule.delayPresets }
    private static let flashChoices = FlashSetting.allCases
    private static let histogramChoices = HistogramStyle.allCases

    // MARK: - Building controls

    private static func layout(for state: CameraControlState, device: AVCaptureDevice, session: AVCaptureSession) -> Layout {
        let shutterStops = usableStops(state.shutterStops)
        let isoStops = usableStops(state.isoStops)
        let apertureStops = usableStops(state.apertureStops)
        let durationStops = usableStops(state.durationStops)
        let customExposure = device.isExposureModeSupported(.custom)
        let customGains = device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        var seen = Set<CameraControlItem>()
        let items = state.items.filter { item in
            guard seen.insert(item).inserted else { return false }
            switch item {
            // The system sliders raise an exception for a device that can't zoom or take an exposure bias.
            case .zoom: return device.activeFormat.videoMaxZoomFactor > 1
            // A picker with one title has nothing to pick. The selfie camera has no spot among the back lenses, and a
            // new picker starts on the first one, which would show as current there and couldn't be picked.
            case .lens: return state.lensTitles.count > 1 && device.position != .front
            case .exposureBias: return device.maxExposureTargetBias > device.minExposureTargetBias
            case .shutter: return customExposure && !shutterStops.isEmpty
            case .nightDuration: return !durationStops.isEmpty
            case .nightScene: return state.sceneTitles.count > 1
            case .iso: return customExposure && !isoStops.isEmpty
            case .aperture: return !apertureStops.isEmpty
            case .whiteBalance, .tint: return customGains
            case .focus: return device.isLockingFocusWithCustomLensPositionSupported
            // Settings pickers with no device call behind them, so they raise nowhere. Flash goes by the photo output,
            // which also offers the front camera's Retina Flash where the device itself reports none; the model dims
            // it where the output has no flash.
            case .flash, .timer, .histogram, .mode: return true
            }
        }
        let installed = Set(items)
        return Layout(
            session: ObjectIdentifier(session),
            deviceID: device.uniqueID,
            items: items,
            shutterStops: installed.contains(.shutter) ? shutterStops : [],
            isoStops: installed.contains(.iso) ? isoStops : [],
            apertureStops: installed.contains(.aperture) ? apertureStops : [],
            lensTitles: installed.contains(.lens) ? state.lensTitles : [],
            durationStops: installed.contains(.nightDuration) ? durationStops : [],
            sceneTitles: installed.contains(.nightScene) ? state.sceneTitles : []
        )
    }

    /// Stops that can be labelled and compared on a log scale.
    private static func usableStops(_ stops: [Double]) -> [Double] {
        stops.filter { $0.isFinite && $0 > 0 }
    }

    private func makeEntry(for item: CameraControlItem, layout: Layout, device: AVCaptureDevice) -> Entry {
        let control: AVCaptureControl
        var stops: [Double] = []
        switch item {
        case .zoom:
            control = AVCaptureSystemZoomSlider(device: device)
        case .lens:
            control = makeIndexPicker(item, title: "Lens", titles: layout.lensTitles)
        case .exposureBias:
            control = AVCaptureSystemExposureBiasSlider(device: device)
        case .shutter:
            stops = layout.shutterStops
            control = makePicker(item, title: "Shutter", stops: stops) { ShutterSpeed(seconds: $0).label }
        case .nightDuration:
            // The same labels as the shutter's ("1/4", "1m30s"), so a time reads alike on both.
            stops = layout.durationStops
            control = makePicker(item, title: "Duration", stops: stops) { ShutterSpeed(seconds: $0).label }
        case .nightScene:
            control = makeIndexPicker(item, title: "Scene", titles: layout.sceneTitles)
        case .iso:
            stops = layout.isoStops
            control = makePicker(item, title: "ISO", stops: stops) { ISOScale.compactLabel($0) }
        case .aperture:
            stops = layout.apertureStops
            control = makePicker(item, title: "Aperture", stops: stops) { ApertureScale.label($0) }
        case .whiteBalance:
            let slider = makeSlider(item, title: "Kelvin", range: Self.kelvinRange, step: Self.kelvinStep)
            slider.localizedValueFormat = "%@K"
            slider.prominentValues = Self.presetKelvins()
            control = slider
        case .tint:
            let slider = makeSlider(item, title: "Tint", range: Self.tintRange, step: Self.tintStep)
            // Neutral, where most settings want to be, lands most easily.
            slider.prominentValues = [0]
            control = slider
        case .focus:
            let slider = AVCaptureSlider("Focus", symbolName: item.symbolName, in: 0...1)
            slider.accessibilityIdentifier = "cameraControl.\(item.rawValue)"
            slider.setActionQueue(queue) { [weak self] value in
                self?.sliderMoved(item, value: value)
            }
            control = slider
        case .timer:
            // Custom gives a schedule set in the timer sheet a spot of its own. Without one, the picker would show
            // Off or an old delay while the next press starts a sequence.
            let titles = Self.timerDelays.map { $0 > 0 ? Formatting.compactDuration($0) : "Off" } + ["Custom"]
            control = makeIndexPicker(item, title: "Timer", titles: titles)
        case .flash:
            control = makeIndexPicker(item, title: "Flash", titles: Self.flashChoices.map(\.title))
        case .histogram:
            control = makeIndexPicker(item, title: "Histogram", titles: Self.histogramChoices.map(\.title))
        case .mode:
            // The uppercase titles are the carousel's styling; the system overlay sets its own type, where
            // title case matches the other pickers.
            let titles = CaptureMode.carouselOrder.map { $0.title.capitalized }
            control = makeIndexPicker(item, title: "Mode", titles: titles)
        }
        return Entry(item: item, control: control, stops: stops)
    }

    /// "Auto" first, then one title per stop. Controls need their action before the session accepts them.
    private func makePicker(_ item: CameraControlItem, title: String, stops: [Double], label: (Double) -> String) -> AVCaptureIndexPicker {
        let titles = ["Auto"] + stops.map(label)
        let picker = AVCaptureIndexPicker(title, symbolName: item.symbolName, localizedIndexTitles: titles)
        picker.accessibilityIdentifier = "cameraControl.\(item.rawValue)"
        picker.setActionQueue(queue) { [weak self] index in
            self?.pickerMoved(item, index: index, stops: stops, count: titles.count)
        }
        return picker
    }

    /// A picker of plain choices, with no Auto. `titles` holds at least two (layout(for:) sees to that where it
    /// can vary): an empty list raises.
    private func makeIndexPicker(_ item: CameraControlItem, title: String, titles: [String]) -> AVCaptureIndexPicker {
        let picker = AVCaptureIndexPicker(title, symbolName: item.symbolName, localizedIndexTitles: titles)
        picker.accessibilityIdentifier = "cameraControl.\(item.rawValue)"
        picker.setActionQueue(queue) { [weak self] index in
            self?.pickerMoved(item, index: index, stops: [], count: titles.count)
        }
        return picker
    }

    private func makeSlider(_ item: CameraControlItem, title: String, range: ClosedRange<Float>, step: Float) -> AVCaptureSlider {
        let slider = AVCaptureSlider(title, symbolName: item.symbolName, in: range, step: step)
        slider.accessibilityIdentifier = "cameraControl.\(item.rawValue)"
        slider.setActionQueue(queue) { [weak self] value in
            self?.sliderMoved(item, value: value)
        }
        return slider
    }

    /// Preset temperatures inside the slider's range, one per spot on the scale (flash sits on daylight).
    private static func presetKelvins() -> [Float] {
        var values: [Float] = []
        for preset in WhiteBalancePreset.allCases {
            guard let kelvin = preset.kelvin, kelvin.isFinite else { continue }
            let value = Float(kelvin)
            guard kelvinRange.contains(value), !values.contains(where: { abs($0 - value) < 150 }) else { continue }
            values.append(value)
        }
        return values.sorted()
    }

    private func attachDelegate(to session: AVCaptureSession) {
        if (session.controlsDelegate as AnyObject?) !== self {
            session.setControlsDelegate(self, queue: queue)
        }
    }

    private static func isInstalled(_ entries: [Entry], on session: AVCaptureSession) -> Bool {
        let current = Set(session.controls.map { ObjectIdentifier($0) })
        let ours = Set(entries.map { ObjectIdentifier($0.control) })
        return current == ours
    }

    // MARK: - User input (controls queue)

    /// `count` is the picker's number of titles.
    private func pickerMoved(_ item: CameraControlItem, index: Int, stops: [Double], count: Int) {
        guard acceptMove(item, reported: .index(index)) else { return }
        // Anything past the titles is ignored rather than read as the first choice.
        guard index >= 0, index < count else { return }
        let change: CameraControlChange
        switch item {
        case .mode:
            guard CaptureMode.carouselOrder.indices.contains(index) else { return }
            change = .mode(CaptureMode.carouselOrder[index])
        case .lens:
            change = .lens(index)
        case .nightScene:
            change = .scene(index)
        case .timer:
            // Custom included: it sets nothing, and the state the model sends back takes the picker to what is set.
            change = .timer(index)
        case .flash:
            guard Self.flashChoices.indices.contains(index) else { return }
            change = .flash(Self.flashChoices[index])
        case .histogram:
            guard Self.histogramChoices.indices.contains(index) else { return }
            change = .histogram(Self.histogramChoices[index])
        case .shutter, .nightDuration, .iso, .aperture:
            // Index 0 is Auto.
            guard index <= stops.count else { return }
            let value: Double? = index == 0 ? nil : stops[index - 1]
            switch item {
            case .shutter: change = .shutter(value)
            case .nightDuration: change = .duration(value)
            case .iso: change = .iso(value)
            default: change = .aperture(value)
            }
        case .zoom, .exposureBias, .whiteBalance, .tint, .focus:
            return
        }
        onChange?(change)
    }

    private func sliderMoved(_ item: CameraControlItem, value: Float) {
        guard acceptMove(item, reported: .value(value)) else { return }
        guard value.isFinite else { return }
        switch item {
        case .whiteBalance:
            let range = Self.kelvinRange
            onChange?(.kelvin(Double(min(max(value, range.lowerBound), range.upperBound))))
        case .tint:
            let range = Self.tintRange
            onChange?(.tint(Double(min(max(value, range.lowerBound), range.upperBound))))
        case .focus:
            onChange?(.focus(Double(min(max(value, 0), 1))))
        case .zoom, .lens, .exposureBias, .shutter, .nightDuration, .nightScene, .iso, .aperture, .timer, .flash,
             .histogram, .mode:
            break
        }
    }

    /// Notes the user's move, or returns false for the echo of a value this bridge set. Any report clears the
    /// pending echo, so the next real move always goes through.
    private func acceptMove(_ item: CameraControlItem, reported: Target) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        return lock.withLock { () -> Bool in
            if let expected = pendingEcho.removeValue(forKey: item), expected.matches(reported) {
                return false
            }
            lastTouch[item] = now
            return true
        }
    }

    private func setFullscreen(_ fullscreen: Bool) {
        let handler = lock.withLock { () -> (@Sendable (Bool) -> Void)? in
            guard isFullscreen != fullscreen else { return nil }
            isFullscreen = fullscreen
            return fullscreenHandler
        }
        handler?(fullscreen)
    }

    // MARK: - Values from the model

    /// Picker indexes, slider values and enabled flags change on the action queue, so they are set from there.
    private func scheduleValues(from state: CameraControlState, for entries: [Entry], device: AVCaptureDevice,
                                sparingRecentTouches: Bool) {
        guard !entries.isEmpty else { return }
        let targets = Self.targets(from: state, for: entries, device: device)
        let flags = Self.enabledFlags(from: state, for: entries)
        queue.async { [weak self] in
            self?.applyEnabled(flags)
            self?.applyValues(targets, sparingRecentTouches: sparingRecentTouches)
        }
    }

    /// Whether each control can be used in the state's mode.
    private static func enabledFlags(from state: CameraControlState, for entries: [Entry]) -> [(Entry, Bool)] {
        entries.map { ($0, !state.disabledItems.contains($0.item)) }
    }

    /// Controls queue. Not spared under a finger: a control that has nothing to do now, because a shot started or
    /// the mode changed, stops at once.
    private func applyEnabled(_ flags: [(Entry, Bool)]) {
        for (entry, enabled) in flags where entry.control.isEnabled != enabled {
            // A rebuild may have replaced the control since the flags were worked out.
            guard lock.withLock({ entries.contains { $0.control === entry.control } }) else { continue }
            entry.control.isEnabled = enabled
        }
    }

    /// Controls queue.
    private func applyValues(_ targets: [(Entry, Target)], sparingRecentTouches: Bool) {
        let now = DispatchTime.now().uptimeNanoseconds
        var spared: [(entry: Entry, touched: UInt64)] = []
        for (entry, target) in targets where Self.needsChange(entry.control, to: target) {
            // Checked together under the lock: values queued just before a rebuild belong to controls it removed,
            // and their pending echo would swallow the first move on the new control of the same kind.
            let claim = lock.withLock { () -> Claim in
                guard entries.contains(where: { $0.control === entry.control }) else { return .gone }
                if sparingRecentTouches, let touched = lastTouch[entry.item], now < touched + Self.touchGrace {
                    return .spared(touched)
                }
                pendingEcho[entry.item] = target
                return .applied
            }
            switch claim {
            case .gone:
                continue
            case .spared(let touched):
                spared.append((entry, touched))
                continue
            case .applied:
                break
            }
            switch target {
            case .index(let index):
                (entry.control as? AVCaptureIndexPicker)?.selectedIndex = index
            case .value(let value):
                (entry.control as? AVCaptureSlider)?.value = value
            }
        }
        retryAfterGrace(spared)
    }

    /// Controls queue. Controls spared for a touch get the latest state once their grace is over, so a pick the
    /// model refused or clamped doesn't stay on show. One the finger moved again by then is left to the state that
    /// move brings, which spares it in turn.
    private func retryAfterGrace(_ spared: [(entry: Entry, touched: UInt64)]) {
        guard let last = spared.map(\.touched).max() else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let end = last + Self.touchGrace
        let wait = end > now ? end - now : 0
        // A little past the end, so the retry itself never lands inside the grace.
        let deadline = DispatchTime.now() + .nanoseconds(Int(clamping: wait)) + .milliseconds(20)
        queue.asyncAfter(deadline: deadline) { [weak self] in
            self?.retry(spared)
        }
    }

    private func retry(_ spared: [(entry: Entry, touched: UInt64)]) {
        let snapshot = lock.withLock { (state: latestState, entries: entries, touches: lastTouch, device: currentDevice) }
        guard let state = snapshot.state else { return }
        let due = spared.filter { spare in
            snapshot.entries.contains { $0.control === spare.entry.control }
                && (snapshot.touches[spare.entry.item] ?? 0) <= spare.touched
        }.map(\.entry)
        guard !due.isEmpty else { return }
        applyValues(Self.targets(from: state, for: due, device: snapshot.device), sparingRecentTouches: true)
    }

    /// The control can take `target` and doesn't show it yet. An index out of range raises an exception.
    private static func needsChange(_ control: AVCaptureControl, to target: Target) -> Bool {
        switch target {
        case .index(let index):
            guard let picker = control as? AVCaptureIndexPicker else { return false }
            return index >= 0 && index < picker.numberOfIndexes && picker.selectedIndex != index
        case .value(let value):
            guard let slider = control as? AVCaptureSlider else { return false }
            return abs(slider.value - value) > valueTolerance
        }
    }

    /// What each control should show for `state`. Values are clamped (and snapped to the slider's step)
    /// before they get here, because an out-of-range value raises an exception.
    private static func targets(from state: CameraControlState, for entries: [Entry], device: AVCaptureDevice?) -> [(Entry, Target)] {
        // Automatic white balance and focus have no spot on their sliders, so the sliders show what the camera
        // picked on its own; the first touch then continues from the preview instead of jumping to the middle.
        let wantsLiveColor = (state.kelvin == nil && entries.contains { $0.item == .whiteBalance })
            || (state.tint == nil && entries.contains { $0.item == .tint })
        let liveColor = wantsLiveColor ? device.map(currentTemperatureAndTint(of:)) : nil
        let liveFocus = state.lensPosition == nil && entries.contains { $0.item == .focus }
            ? device.flatMap(currentLensPosition(of:)) : nil
        return entries.compactMap { entry -> (Entry, Target)? in
            switch entry.item {
            case .shutter:
                return pickerIndex(for: state.shutter, stops: entry.stops).map { (entry, .index($0)) }
            case .nightDuration:
                return pickerIndex(for: state.duration, stops: entry.stops).map { (entry, .index($0)) }
            case .iso:
                return pickerIndex(for: state.iso, stops: entry.stops).map { (entry, .index($0)) }
            case .aperture:
                return pickerIndex(for: state.aperture, stops: entry.stops).map { (entry, .index($0)) }
            case .mode:
                return CaptureMode.carouselOrder.firstIndex(of: state.mode.carouselMode).map { (entry, .index($0)) }
            case .lens:
                // An index past the picker's titles raises; the selfie camera has no spot on it.
                guard let index = state.lensIndex, state.lensTitles.indices.contains(index) else { return nil }
                return (entry, .index(index))
            case .nightScene:
                // nil leaves the picker where it is, for a choice the menu has and the picker doesn't.
                return state.sceneIndex.map { (entry, .index($0)) }
            case .timer:
                // Custom, past the delays, for a burst, an intervalometer or a delay off the list.
                return state.timerIndex.map { (entry, .index($0)) }
            case .flash:
                return flashChoices.firstIndex(of: state.flash).map { (entry, .index($0)) }
            case .histogram:
                return histogramChoices.firstIndex(of: state.histogram).map { (entry, .index($0)) }
            case .whiteBalance:
                let kelvin = state.kelvin.flatMap { $0.isFinite ? $0 : nil } ?? liveColor?.kelvin ?? neutralKelvin
                let snapped = (Float(kelvin) / kelvinStep).rounded() * kelvinStep
                return (entry, .value(min(max(snapped, kelvinRange.lowerBound), kelvinRange.upperBound)))
            case .tint:
                let tint = state.tint.flatMap { $0.isFinite ? $0 : nil } ?? liveColor?.tint ?? 0
                let snapped = (Float(tint) / tintStep).rounded() * tintStep
                return (entry, .value(min(max(snapped, tintRange.lowerBound), tintRange.upperBound)))
            case .focus:
                let position = state.lensPosition.flatMap { $0.isFinite ? $0 : nil } ?? liveFocus ?? neutralFocus
                return (entry, .value(Float(min(max(position, 0), 1))))
            case .zoom, .exposureBias:
                // Apple's system sliders follow the device themselves.
                return nil
            }
        }
    }

    /// The temperature and tint automatic white balance is using; either is nil when the device reports nothing
    /// usable for it.
    private static func currentTemperatureAndTint(of device: AVCaptureDevice) -> (kelvin: Double?, tint: Double?) {
        let maxGain = max(1, device.maxWhiteBalanceGain)
        func legal(_ gain: Float) -> Float {
            gain.isFinite ? min(max(gain, 1), maxGain) : 1
        }
        let gains = device.deviceWhiteBalanceGains
        // Gains outside 1...maxWhiteBalanceGain make the conversion raise an exception.
        let legalGains = AVCaptureDevice.WhiteBalanceGains(redGain: legal(gains.redGain), greenGain: legal(gains.greenGain),
                                                           blueGain: legal(gains.blueGain))
        let values = device.temperatureAndTintValues(for: legalGains)
        let kelvin = Double(values.temperature)
        let tint = Double(values.tint)
        return (kelvin.isFinite && kelvin > 0 ? kelvin : nil, tint.isFinite ? tint : nil)
    }

    private static func currentLensPosition(of device: AVCaptureDevice) -> Double? {
        let position = Double(device.lensPosition)
        return position.isFinite ? position : nil
    }

    /// 0 for Auto (nil), else 1 + the stop closest on a log scale. nil leaves the control as it is.
    private static func pickerIndex(for value: Double?, stops: [Double]) -> Int? {
        guard let value else { return 0 }
        guard value.isFinite, value > 0, !stops.isEmpty else { return nil }
        var best = 0
        var bestDistance = Double.infinity
        for (index, stop) in stops.enumerated() {
            let distance = abs(log2(stop / value))
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best + 1
    }
}
