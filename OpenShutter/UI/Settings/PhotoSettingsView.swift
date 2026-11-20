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
            // Format, RAW and Resolution, the same three groups as the Format button's menu on the camera.
            Section {
                SettingsPicker("Format", selection: formatBinding(model), options: photo.formatChoices(for: capture),
                               label: \.title)
                // Dimmed where it does nothing: High saves at its own quality, and PNG and TIFF lose nothing to
                // compression. RAW only keeps it, because its night and long exposure photos save HEIF.
                SettingsSlider(title: "Quality", value: capture.quality, range: 0.5...1, step: 0.05,
                               format: Formatting.percent) { quality in
                    model.updateSettings { $0.capture.quality = quality }
                }
                .disabled(!choice.takesQualitySlider)
            } header: {
                Text("Format")
            } footer: {
                SettingsFooter(Self.formatNotes(capture: capture, photo: photo))
            }

            Section {
                Picker(selection: rawBinding(model)) {
                    ForEach(pickerOptions(Self.rawFormats(photo), current: capture.rawFormat)) { raw in
                        Text(raw.title).tag(raw)
                    }
                } label: {
                    // The second text is the row's subtitle: what the chosen kind of RAW is.
                    if let detail = capture.rawFormat.detail {
                        Text("RAW")
                        Text(detail)
                    } else {
                        Text("RAW")
                    }
                }
                // Stays usable while RAW is set, so it can still be switched off on a camera without RAW.
                .disabled(!photo.bayerRAW && !photo.proRAW && capture.rawFormat == .none)
            } header: {
                Text("RAW")
            } footer: {
                SettingsFooter(Self.rawNotes(capture: capture, photo: photo, presets: model.lensPresets))
            }

            Section {
                // A stored Largest or 24 MP reads as the row it takes (shownAs), so neither adds a row of its own.
                SettingsPicker("Resolution", selection: resolutionBinding(model), options: PhotoResolution.offered,
                               label: \.title)
            } header: {
                Text("Resolution")
            } footer: {
                SettingsFooter(Self.resolutionNotes(capture: capture, photo: photo))
            }

            Section {
                SettingsPicker("Processing", selection: model.settingBinding(\.capture.processing),
                             options: pickerOptions(Self.processingLevels(photo), current: capture.processing), label: \.title)
                Toggle("Prioritize faster shooting", isOn: model.settingBinding(\.capture.prioritizeSpeed))
            } footer: {
                SettingsFooter([
                    capture.processing.detail,
                    Self.processingLimitNote(capture.processing, photo: photo),
                    "Manual exposure always uses Minimal, so the shutter and ISO you set are kept.",
                    fasterShootingNote,
                ])
            }

            Section {
                Toggle("Live Photo", isOn: model.settingBinding(\.capture.livePhoto))
                    .disabled(!photo.livePhoto || !capture.allowsLivePhoto)
                // PNG and TIFF can't carry a depth map: ImageIO writes auxiliary data into HEIF and JPEG only.
                Toggle("Depth", isOn: model.settingBinding(\.capture.depth))
                    .disabled(!photo.depth || capture.processedFormat.isLossless)
                Toggle("Constant color", isOn: model.settingBinding(\.capture.constantColor))
                    .disabled(!photo.constantColor)
                Toggle("Lens correction", isOn: model.settingBinding(\.capture.lensCorrection))
                    .disabled(!photo.lensCorrection)
                Toggle("Mirror front camera", isOn: model.settingBinding(\.capture.mirrorFront))
            } footer: {
                SettingsFooter(Self.featureNotes(capture: capture, photo: photo))
            }

            // The system refuses to mute the shutter where the law requires the sound, so the row only shows where it
            // works.
            if photo.silentShutter {
                Section {
                    Toggle("Silent shutter", isOn: model.settingBinding(\.capture.silentShutter))
                } footer: {
                    Text("Not available in every region.")
                }
            }

            Section {
                Toggle("Location tags", isOn: model.settingBinding(\.capture.saveLocation))
                if capture.saveLocation, locationAccess?.isDenied == true {
                    Button("Open Settings") { model.openAppSettings() }
                }
                SettingsTextRow(title: "Your name", value: capture.artist, prompt: "None") { name in
                    model.updateSettings { $0.capture.artist = name }
                }
                SettingsTextRow(title: "Copyright", value: capture.copyright, prompt: "None") { line in
                    model.updateSettings { $0.capture.copyright = line }
                }
            } header: {
                Text("Photo details")
            } footer: {
                SettingsFooter([
                    locationNote(enabled: capture.saveLocation, access: locationAccess),
                    "Your name and the copyright line go into every photo and video, for apps that show who took it. Leave them empty to save neither.",
                    "Every photo also records how it was taken: lens, focal length, shutter, ISO, aperture, white balance, exposure compensation and mode.",
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
        return "The current camera tops out at \(photo.maxProcessing.title)."
    }

    private static func formatNotes(capture: CaptureOptions, photo: PhotoSupport) -> [String?] {
        var notes: [String?] = []
        if !photo.isReported {
            notes.append("In video mode the camera doesn't report its photo features, so the photo choices here aren't checked against it. Switch to a photo mode to see which ones the current camera supports.")
        }
        notes.append(photo.heifNote(for: capture))
        notes.append("HEIF and JPEG use the Quality slider. HEIF High and JPEG High always save at \(Formatting.percent(PhotoFormatChoice.highQuality)).")
        if capture.processedFormat == .none {
            notes.append("Quality still applies to night and long exposure photos, which are never RAW.")
        }
        notes.append("PNG and TIFF keep every pixel, with no compression loss. A 12 MP TIFF is about 37 MB and a 48 MP one about 146 MB. PNG files are smaller, with the same pixels.")
        if capture.processedFormat.isLossless {
            notes.append("PNG and TIFF photos are standard range. Live Photo and depth need HEIF or JPEG.")
            notes.append("Night photos and other stacks saved as PNG or TIFF keep 16 bits per color.")
        }
        var unavailable = UnavailableFeatures()
        unavailable.note("HEIF", supported: photo.heif)
        notes.append(unavailable.text)
        return notes
    }

    private static func rawNotes(capture: CaptureOptions, photo: PhotoSupport, presets: [LensPreset]) -> [String?] {
        var notes: [String?] = []
        // The unprocessed RAW and Apple's processed one read alike by name, so each says what it is, where this camera
        // has it.
        if photo.bayerRAW {
            notes.append("RAW saves the sensor's data with no processing. It needs a lens at its own zoom, such as 1\u{00D7}.")
        }
        if photo.proRAW {
            notes.append("ProRAW saves Apple's processed picture as a RAW file and works at any zoom.")
        }
        notes += photo.rawNotes(for: capture, presets: presets)
        if capture.rawFormat != .none {
            notes.append("Night photos and other stacks have no RAW.")
        }
        var unavailable = UnavailableFeatures()
        unavailable.note("RAW", supported: photo.bayerRAW || photo.proRAW)
        notes.append(unavailable.text)
        return notes
    }

    private static func resolutionNotes(capture: CaptureOptions, photo: PhotoSupport) -> [String?] {
        var notes: [String?] = []
        if let sizes = photo.sizes {
            let shown = capture.resolution.shownAs
            // Each row follows the person from lens to lens, so a lens without that size says what it gives instead.
            if let delivered = photo.deliveredSize(capture.resolution), delivered.megapixelLabel != shown.title {
                notes.append("The current camera has no \(shown.title) size, so photos are \(delivered.megapixelLabel).")
            }
            if let largest = sizes.last {
                notes.append("Largest photo with the current camera: \(largest.width)\u{00D7}\(largest.height) (\(largest.megapixelLabel)).")
            }
        }
        notes.append("48 MP photos take about four times the space of 12 MP photos.")
        notes.append("Night photos and other stacks are made from video frames at 12 MP.")
        return notes
    }

    private static func featureNotes(capture: CaptureOptions, photo: PhotoSupport) -> [String?] {
        var notes: [String?] = [photo.livePhotoNote(for: capture)]
        if capture.depth, photo.depth {
            if capture.processedFormat.isLossless {
                notes.append("Depth needs HEIF or JPEG, so \(capture.processedFormat.title) photos have none.")
            } else {
                // Depth maps come at the sensor's own 4:3, and the photo pipeline embeds them only there.
                notes.append(capture.aspect.matches(.fourThree)
                    ? "Depth is saved only with 4:3 HEIF and JPEG photos that have no RAW file."
                    : "Depth is saved only with 4:3 HEIF and JPEG photos that have no RAW file, so photos at \(capture.aspect.label) have none.")
            }
        }
        if photo.constantColor {
            // The photo pipeline skips it without a flash, with RAW, and with locked white balance (Apple's advice).
            notes.append("Constant color uses the flash to remove the color cast of room light. It needs the flash on or set to auto, auto white balance, and RAW off.")
        }
        if photo.lensCorrection {
            notes.append("Lens correction straightens stretched edges, mostly on the ultra wide.")
        }
        notes.append("Mirror front camera saves selfies the way the preview shows them.")
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
                Button("Open Settings") { model.openAppSettings() }
            }
            if photo.silentShutter {
                Toggle("Silent shutter", isOn: model.settingBinding(\.capture.silentShutter))
            }
            Toggle("Prioritize faster shooting", isOn: model.settingBinding(\.capture.prioritizeSpeed))
        } header: {
            Text("Photos")
        } footer: {
            SettingsFooter(Self.notes(capture: capture, photo: photo, presets: model.lensPresets,
                                      access: locationAccess))
        }
    }

    private static func notes(capture: CaptureOptions, photo: PhotoSupport, presets: [LensPreset],
                              access: LocationPermissionWatcher?) -> [String?] {
        var notes: [String?] = [
            "HEIF photos take less space. JPEG photos open in any app. HEIF High and JPEG High save at full quality. PNG and TIFF keep every pixel, in much larger files.",
            photo.heifNote(for: capture),
            // Neither has a row in this list, so the footer says where they are.
            "RAW and the resolution are on the Format button at the top of the camera.",
        ]
        // RAW has no row in this list, so while it is on the footer is where a shot's files are named.
        notes += photo.rawNotes(for: capture, presets: presets)
        notes.append(photo.livePhotoNote(for: capture))
        notes.append(locationNote(enabled: capture.saveLocation, access: access))
        notes.append("Every photo also records how it was taken, such as the lens and the camera's settings.")
        notes.append(fasterShootingNote)
        return notes
    }
}

// MARK: - Shared by both lists

/// What prioritize faster shooting gives up, in the short list and on the Photos page.
private let fasterShootingNote = "Prioritize faster shooting lets the camera lower the quality of photos taken in quick succession so it keeps up, on iPhones that support it."

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

/// The location row's line in a footer: why photos carry no place, or only a rough one, while location tags are on,
/// and otherwise what the tags do.
@MainActor
private func locationNote(enabled: Bool, access: LocationPermissionWatcher?) -> String {
    if enabled, let access {
        if access.isDenied {
            return "Location access is off for Open Shutter, so photos won't include where they were taken."
        }
        if access.isAuthorized, !access.isPrecise {
            return "Precise Location is off for Open Shutter, so photos get an approximate place."
        }
    }
    return "Location tags add where each photo and video was taken. Location is only read while they are on."
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
        return "The current camera can't save HEIF, so photos are saved as \(capture.highQuality ? "JPEG High" : "JPEG")."
    }

    /// Says what a shot really saves. The photo pipeline swaps ProRAW for Bayer RAW where ProRAW is missing,
    /// drops Bayer RAW at any zoom but a lens's own 1x, and saves a HEIF when RAW alone isn't possible.
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
                ? "The current camera can't shoot RAW, so photos are saved as \(fallback)."
                : "The current camera can't shoot RAW, so only the \(processed) is saved."]
        }
        var notes: [String?] = []
        if saved != capture.rawFormat {
            notes.append("The current camera can't shoot \(capture.rawFormat.title), so it saves \(saved.title) instead.")
        }
        notes.append(capture.processedFormat == .none
            ? "Each shot saves only the \(saved.title) file."
            : "Each shot saves \(saved.title) and \(processed) together.")
        if saved == .bayer {
            // With RAW only a zoomed shot still saves something, because the pipeline falls back to HEIF or JPEG.
            let outcome = capture.processedFormat == .none ? "save a \(fallback) instead" : "skip it"
            // Older Pro phones have a real 2x lens, so the zoomed buttons are named from the presets, not assumed.
            let cropped = presets.filter { abs($0.zoomFactor - 1) > 0.01 }.map(\.selectedLabel)
            notes.append(cropped.first.map { "RAW is saved only at each lens's own zoom; zoomed views such as \($0) \(outcome)." }
                ?? "RAW is saved only at each lens's own zoom; zoomed photos \(outcome).")
        }
        return notes
    }

    /// Why the Live Photo switch is dimmed, or else when it does nothing; nil on a camera without Live Photo.
    func livePhotoNote(for capture: CaptureOptions) -> String? {
        guard livePhoto else { return nil }
        if capture.rawFormat != .none {
            return "Live Photo is off while RAW is on."
        }
        // PNG and TIFF are made from the camera's photo after the shot, so no movie goes with them.
        if capture.processedFormat.isLossless {
            return "Live Photo is off with \(capture.processedFormat.title). Live Photos need HEIF or JPEG."
        }
        // The model records the Live movie in PHOTO only; unsaid, the switch would seem dead in the other modes.
        return "Only photo mode takes Live Photos."
    }
}
