import SwiftUI
import CameraCore

/// The Photos page of the full list: what a photo is saved as, how it is processed and what is written into it. Rows
/// the current camera can't use stay visible but disabled, and their section footer says why. The shape photos are
/// cropped to is not here but in the Camera section of the first page, which the short list has too.
struct PhotoSettingsView: View {
    let model: CameraModel
    let locationAccess: LocationPermissionWatcher?

    var body: some View {
        let capture = model.settings.capture
        let photo = PhotoSupport(model.capabilities, isVideoMode: model.settings.mode == .video)
        let choice = PhotoFormatChoice(capture)

        Form {
            // What a shot saves: the same choices as the Format button's menu on the camera.
            Section {
                SettingsPicker("Format", selection: formatBinding(model), options: photo.formatChoices(for: capture),
                               label: \.title)
                // Only where it acts: High saves at its own quality, and PNG and TIFF lose nothing to compression. RAW
                // only keeps it, because its night and long exposure photos save HEIF.
                if choice.takesQualitySlider {
                    SettingsSlider(title: "Quality", value: capture.quality, range: 0.5...1, step: 0.05,
                                   format: Formatting.percent) { quality in
                        model.updateSettings { $0.capture.quality = quality }
                    }
                }
                // The second line says what the chosen kind of RAW is.
                SettingsDetailPicker("RAW", selection: rawBinding(model),
                                     options: pickerOptions(Self.rawFormats(photo), current: capture.rawFormat),
                                     label: \.title, detail: capture.rawFormat.detail)
                    // Stays usable while RAW is set, so it can still be switched off on a camera without RAW.
                    .disabled(!photo.bayerRAW && !photo.proRAW && capture.rawFormat == .none)
                // A stored Largest or 24 MP reads as the row it takes (shownAs), so neither adds a row of its own.
                SettingsPicker("Resolution", selection: resolutionBinding(model), options: PhotoResolution.offered,
                               label: \.title)
            } footer: {
                SettingsFooter(Self.formatNotes(capture: capture, photo: photo, presets: model.lensPresets))
            }

            Section {
                SettingsDetailPicker("Processing", selection: model.settingBinding(\.capture.processing),
                                     options: pickerOptions(Self.processingLevels(photo), current: capture.processing),
                                     label: \.title, detail: capture.processing.detail)
                Toggle("Prioritize faster shooting", isOn: model.settingBinding(\.capture.prioritizeSpeed))
            } footer: {
                SettingsFooter([Self.processingLimitNote(capture.processing, photo: photo)])
            }

            Section {
                Toggle("Live Photo", isOn: model.settingBinding(\.capture.livePhoto))
                    .disabled(!photo.livePhoto || !capture.allowsLivePhoto)
                // ImageIO writes a depth map into HEIF and JPEG only, and the photo pipeline embeds none beside RAW.
                Toggle("Depth", isOn: model.settingBinding(\.capture.depth))
                    .disabled(!photo.depth || capture.processedFormat.isLossless || capture.rawFormat != .none)
                Toggle("Constant color", isOn: model.settingBinding(\.capture.constantColor))
                    .disabled(!photo.constantColor)
                Toggle("Lens correction", isOn: model.settingBinding(\.capture.lensCorrection))
                    .disabled(!photo.lensCorrection)
                Toggle("Mirror front camera", isOn: model.settingBinding(\.capture.mirrorFront))
                // The system refuses to mute the shutter where the law requires the sound, so the row only shows
                // where it works.
                if photo.silentShutter {
                    Toggle("Silent shutter", isOn: model.settingBinding(\.capture.silentShutter))
                }
            } footer: {
                SettingsFooter(Self.featureNotes(capture: capture, photo: photo))
            }

            Section {
                Toggle("Location tags", isOn: model.settingBinding(\.capture.saveLocation))
                if capture.saveLocation, locationAccess?.isDenied == true {
                    Button("Allow location access") { model.openAppSettings() }
                }
                SettingsTextRow(title: "Your name", value: capture.artist, prompt: "None") { name in
                    model.updateSettings { $0.capture.artist = name }
                }
                SettingsTextRow(title: "Copyright", value: capture.copyright, prompt: "None") { line in
                    model.updateSettings { $0.capture.copyright = line }
                }
            } header: {
                Text("Photo details")
                    .settingsHeader()
            } footer: {
                SettingsFooter([
                    locationNote(enabled: capture.saveLocation, access: locationAccess),
                    "Name and copyright go into every photo and video.",
                ])
            }
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func rawFormats(_ photo: PhotoSupport) -> [RawFormat] {
        var supported: [RawFormat] = [.none]
        if photo.bayerRAW { supported.append(.bayer) }
        if photo.proRAW { supported.append(.proRAW) }
        return supported
    }

    private static func processingLevels(_ photo: PhotoSupport) -> [ProcessingLevel] {
        let levels = ProcessingLevel.allCases
        let limit = levels.firstIndex(of: photo.maxProcessing) ?? levels.count - 1
        return Array(levels.prefix(limit + 1))
    }

    private static func processingLimitNote(_ level: ProcessingLevel, photo: PhotoSupport) -> String? {
        let levels = ProcessingLevel.allCases
        guard let wanted = levels.firstIndex(of: level), let limit = levels.firstIndex(of: photo.maxProcessing),
              wanted > limit else { return nil }
        return "This camera goes up to \(photo.maxProcessing.title)."
    }

    /// Only what a shot saves differently from what the rows say, and why a row is dimmed.
    private static func formatNotes(capture: CaptureOptions, photo: PhotoSupport, presets: [LensPreset]) -> [String?] {
        var notes: [String?] = [photo.heifNote(for: capture), photo.losslessNote(for: capture)]
        if capture.processedFormat == .none {
            notes.append("Quality applies to Night and stacked photos.")
        }
        notes += photo.rawNotes(for: capture, presets: presets)
        // Each row follows the person from lens to lens, so a lens without that size says what it gives instead.
        let shown = capture.resolution.shownAs
        if let delivered = photo.deliveredSize(capture.resolution), delivered.megapixelLabel != shown.title {
            notes.append("This camera has no \(shown.title), so photos are \(delivered.megapixelLabel).")
        }
        notes.append(stacksNote(capture: capture, photo: photo))
        var unavailable = UnavailableFeatures()
        unavailable.note("HEIF", supported: photo.heif)
        unavailable.note("RAW", supported: photo.bayerRAW || photo.proRAW)
        notes.append(unavailable.text)
        return notes
    }

    /// Stacks are made from video frames, so they are 12 MP on every sensor and never RAW.
    private static func stacksNote(capture: CaptureOptions, photo: PhotoSupport) -> String? {
        let raw = capture.rawFormat != .none
        let large = capture.resolution.shownAs == .mp48
            && (photo.deliveredSize(capture.resolution).map { $0.pixelCount > 20_000_000 } ?? true)
        switch (raw, large) {
        case (true, true): return "Night and stacked photos are 12 MP and never RAW."
        case (true, false): return "Night and stacked photos are never RAW."
        case (false, true): return "Night and stacked photos are 12 MP."
        case (false, false): return nil
        }
    }

    private static func featureNotes(capture: CaptureOptions, photo: PhotoSupport) -> [String?] {
        var notes: [String?] = []
        // The rows RAW, PNG and TIFF dim, named only where this camera has them.
        let dimmed = [photo.livePhoto ? "Live Photo" : nil, photo.depth ? "Depth" : nil].compactMap { $0 }
        if !dimmed.isEmpty {
            let names = ListFormatter.localizedString(byJoining: dimmed)
            if capture.rawFormat != .none {
                notes.append("\(names) \(dimmed.count > 1 ? "are" : "is") off while RAW is on.")
            } else if capture.processedFormat.isLossless {
                notes.append("\(names) \(dimmed.count > 1 ? "need" : "needs") HEIF or JPEG.")
            }
        }
        // Depth maps come at the sensor's own 4:3, and the photo pipeline embeds them only there.
        if capture.depth, photo.depth, capture.rawFormat == .none, !capture.processedFormat.isLossless,
           !capture.aspect.matches(.fourThree) {
            notes.append("Depth is saved only with 4:3 photos.")
        }
        // The photo pipeline skips it without a flash, with RAW, and with locked white balance (Apple's advice).
        if capture.constantColor, photo.constantColor {
            notes.append("Constant color needs the flash, auto white balance and RAW off.")
        }
        var unavailable = UnavailableFeatures()
        unavailable.note("Live Photo", supported: photo.livePhoto)
        unavailable.note("depth", supported: photo.depth)
        unavailable.note("constant color", supported: photo.constantColor)
        unavailable.note("lens correction", supported: photo.lensCorrection)
        notes.append(unavailable.text)
        return notes
    }
}

/// Photos in the short list: the photo settings most people change, under the names the Photos page gives them.
/// Unlike that page, a row the current camera can't use is left out: a dimmed switch and its reason are more than
/// the short list should carry.
struct BasicPhotosSection: View {
    let model: CameraModel
    let locationAccess: LocationPermissionWatcher?

    var body: some View {
        let capture = model.settings.capture
        let photo = PhotoSupport(model.capabilities, isVideoMode: model.settings.mode == .video)

        Section {
            SettingsPicker("Format", selection: formatBinding(model), options: photo.formatChoices(for: capture),
                           label: \.title)
            if photo.livePhoto {
                // RAW is set on the camera or on the Photos page, never in this list, so it can be on here. The
                // row is dimmed then, as on that page, and the footer says why. PNG and TIFF dim it the same way.
                Toggle("Live Photo", isOn: model.settingBinding(\.capture.livePhoto))
                    .disabled(!capture.allowsLivePhoto)
            }
            Toggle("Mirror front camera", isOn: model.settingBinding(\.capture.mirrorFront))
            Toggle("Location tags", isOn: model.settingBinding(\.capture.saveLocation))
            if capture.saveLocation, locationAccess?.isDenied == true {
                Button("Allow location access") { model.openAppSettings() }
            }
            if photo.silentShutter {
                Toggle("Silent shutter", isOn: model.settingBinding(\.capture.silentShutter))
            }
            Toggle("Prioritize faster shooting", isOn: model.settingBinding(\.capture.prioritizeSpeed))
        } header: {
            Text("Photos")
                .settingsHeader()
        } footer: {
            SettingsFooter(Self.notes(capture: capture, photo: photo, access: locationAccess))
        }
    }

    /// Only a state that differs from what the rows say, or why a row is dimmed.
    private static func notes(capture: CaptureOptions, photo: PhotoSupport,
                              access: LocationPermissionWatcher?) -> [String?] {
        [
            photo.heifNote(for: capture),
            photo.losslessNote(for: capture),
            photo.livePhotoNote(for: capture),
            locationNote(enabled: capture.saveLocation, access: access),
        ]
    }
}

// MARK: - Shared by both lists

/// The Format rows, one per PhotoFormatChoice, read from the two stored fields and written through the model, so
/// Settings, the camera's Format button and the quick settings panel set a format the same way.
@MainActor
private func formatBinding(_ model: CameraModel) -> Binding<PhotoFormatChoice> {
    Binding(get: { PhotoFormatChoice(model.settings.capture) }, set: { model.setPhotoFormat($0) })
}

@MainActor
private func rawBinding(_ model: CameraModel) -> Binding<RawFormat> {
    Binding(get: { model.settings.capture.rawFormat }, set: { model.setRawFormat($0) })
}

/// The two Resolution rows. Largest takes what 48 MP takes and 24 MP what 12 MP takes on every lens, so a stored one
/// reads as that row; a pick writes the row's own value.
@MainActor
private func resolutionBinding(_ model: CameraModel) -> Binding<PhotoResolution> {
    Binding(get: { model.settings.capture.resolution.shownAs }, set: { model.setPhotoResolution($0) })
}

/// Why photos carry only a rough place while location tags are on. A denied access needs no sentence: the Allow
/// location access row under the switch says it.
@MainActor
private func locationNote(enabled: Bool, access: LocationPermissionWatcher?) -> String? {
    guard enabled, let access, access.isAuthorized, !access.isPrecise else { return nil }
    return "Precise Location is off, so photos get an approximate place."
}

/// What the photo side of the current camera can do, as the photo rows need it. VIDEO takes the photo output
/// out of the session, so the capabilities there read as "no HEIF, no RAW, no Live Photo" and list the video
/// format's sizes. Rather than gray out every photo row, VIDEO leaves every choice open; the photo pipeline
/// checks each one against the output again when a photo is taken.
private struct PhotoSupport {
    /// iOS delivers 24 MP only through deferred photo delivery, which the photo pipeline keeps off, so asking
    /// for it would quietly save a 12 MP photo.
    private static let deferredOnlySize = PixelSize(width: 5712, height: 4284)

    /// False in VIDEO, where nothing below comes from the camera.
    let isReported: Bool
    let heif: Bool
    let bayerRAW: Bool
    let proRAW: Bool
    let livePhoto: Bool
    let depth: Bool
    let constantColor: Bool
    let lensCorrection: Bool
    /// Stays false in VIDEO: the row only shows where the system allows a silent shutter.
    let silentShutter: Bool
    let maxProcessing: ProcessingLevel
    /// Sizes a photo can come out at, ascending. nil in VIDEO, where no size is reported.
    let sizes: [PixelSize]?

    init(_ caps: CameraCapabilities, isVideoMode: Bool) {
        isReported = !isVideoMode
        silentShutter = !isVideoMode && caps.shutterSoundSuppressionSupported
        if isVideoMode {
            heif = true
            bayerRAW = true
            proRAW = true
            livePhoto = true
            depth = true
            constantColor = true
            lensCorrection = true
            maxProcessing = .maximum
            sizes = nil
        } else {
            heif = caps.heifSupported
            bayerRAW = caps.rawSupported
            proRAW = caps.proRAWSupported
            livePhoto = caps.livePhotoSupported
            depth = caps.depthSupported
            constantColor = caps.constantColorSupported
            lensCorrection = caps.geometricCorrectionSupported || caps.contentAwareCorrectionSupported
            maxProcessing = caps.maxProcessing
            sizes = caps.photoDimensions.filter { $0 != Self.deferredOnlySize }
        }
    }
}

// The choices and sentences the short list and the Photos page share, so a setting reads the same in both.
extension PhotoSupport {
    /// HEIF rows only where the camera saves HEIF, and "RAW only" only while RAW is on, because every shot needs at
    /// least one file. The saved choice stays listed even where the camera lacks it.
    func formatChoices(for capture: CaptureOptions) -> [PhotoFormatChoice] {
        pickerOptions(PhotoFormatChoice.choices(heif: heif, rawOn: capture.rawFormat != .none),
                      current: PhotoFormatChoice(capture))
    }

    /// The size a photo comes out at with `resolution` on the current camera, by the rule the photo output picks
    /// with; nil in VIDEO, where no size is reported, and for a camera that lists none.
    func deliveredSize(_ resolution: PhotoResolution) -> PixelSize? {
        guard let sizes else { return nil }
        return resolution.pick(amongPixelCounts: sizes.map(\.pixelCount)).map { sizes[$0] }
    }

    func heifNote(for capture: CaptureOptions) -> String? {
        guard capture.processedFormat == .heif, !heif else { return nil }
        // The photo pipeline falls back to JPEG at the same quality, High included.
        return capture.highQuality
            ? "This camera saves JPEG High in place of HEIF High."
            : "This camera saves JPEG in place of HEIF."
    }

    /// PNG and TIFF keep every pixel, at many times the size of a HEIF or JPEG.
    func losslessNote(for capture: CaptureOptions) -> String? {
        guard capture.processedFormat.isLossless else { return nil }
        return "\(capture.processedFormat.title) photos are many times larger than HEIF or JPEG."
    }

    /// What a shot really saves where it differs from the rows. The photo pipeline swaps ProRAW for Bayer RAW where
    /// ProRAW is missing, drops Bayer RAW at any zoom but a lens's own 1x, and saves a HEIF when RAW alone isn't
    /// possible.
    func rawNotes(for capture: CaptureOptions, presets: [LensPreset]) -> [String?] {
        let saved: RawFormat
        switch capture.rawFormat {
        case .none: return []
        case .proRAW: saved = proRAW ? .proRAW : (bayerRAW ? .bayer : .none)
        case .bayer: saved = bayerRAW ? .bayer : .none
        }
        let fallback = heif ? "HEIF" : "JPEG"
        // The file beside the RAW one: the chosen container, with JPEG where the camera can't save HEIF.
        let container = capture.processedFormat.saved
        let processed = container == .heif && !heif ? "JPEG" : container.title
        guard saved != .none else {
            return [capture.processedFormat == .none
                ? "This camera can't shoot RAW, so photos are \(fallback)."
                : "This camera can't shoot RAW, so only the \(processed) is saved."]
        }
        var notes: [String?] = []
        if saved != capture.rawFormat {
            notes.append("This camera saves \(saved.title) in place of \(capture.rawFormat.title).")
        }
        if saved == .bayer {
            // Older Pro phones have a real 2x lens, so the zoomed buttons are named from the presets, not assumed.
            let cropped = presets.filter { abs($0.zoomFactor - 1) > 0.01 }.map(\.selectedLabel)
            notes.append(cropped.first.map { "RAW is saved only at each lens's own zoom, not at \($0)." }
                ?? "RAW is saved only at each lens's own zoom.")
        }
        return notes
    }

    /// Why the Live Photo switch is dimmed; nil on a camera without Live Photo and while it can be used.
    func livePhotoNote(for capture: CaptureOptions) -> String? {
        guard livePhoto else { return nil }
        if capture.rawFormat != .none {
            return "Live Photo is off while RAW is on."
        }
        // PNG and TIFF are made from the camera's photo after the shot, so no movie goes with them.
        return capture.processedFormat.isLossless ? "Live Photo needs HEIF or JPEG." : nil
    }
}
