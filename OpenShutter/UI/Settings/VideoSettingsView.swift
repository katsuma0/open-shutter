import SwiftUI
import CameraCore

/// The Video page of the full list: what a recording is made of, from its size and frame rate to its sound.
struct VideoSettingsView: View {
    let model: CameraModel

    var body: some View {
        let video = model.settings.video
        let caps = model.capabilities
        let formats = caps.formats

        Form {
            Section {
                SettingsPicker("Resolution", selection: fittedBinding(\.resolution, formats: formats),
                             options: pickerOptions(VideoFormatChoices.resolutions(colorMode: video.colorMode, formats: formats),
                                              current: video.resolution),
                             label: \.title)
                SettingsPicker("Frame rate", selection: fittedBinding(\.frameRate, formats: formats),
                             options: pickerNumbers(VideoFormatChoices.frameRates(resolution: video.resolution,
                                                                             colorMode: video.colorMode, formats: formats),
                                                     current: video.frameRate),
                             label: Self.frameRateLabel)
                SettingsPicker("Codec", selection: model.settingBinding(\.video.codec),
                             options: pickerOptions(caps.videoCodecs, current: video.codec), label: \.title)
                SettingsPicker("Color", selection: fittedBinding(\.colorMode, formats: formats),
                             options: pickerOptions(caps.colorModes, current: video.colorMode), label: \.title)
                SettingsPicker("Stabilization", selection: model.settingBinding(\.video.stabilization),
                             options: pickerOptions(caps.stabilizationModes, current: video.stabilization), label: \.title)
                Toggle("Record sound", isOn: model.settingBinding(\.video.audio))
                // Without sound the camera leaves the audio session alone, so other apps keep playing anyway.
                Toggle("Allow audio playback", isOn: model.settingBinding(\.video.allowAudioPlayback))
                    .disabled(!video.audio)
                Toggle("Wind noise reduction", isOn: model.settingBinding(\.video.windNoiseReduction))
                    .disabled(!video.audio)
                Toggle("Low light noise reduction", isOn: model.settingBinding(\.video.lowLightNoiseReduction))
                    .disabled(!caps.lowLightVideoNoiseReductionSupported)
                Toggle("Shutter angle", isOn: model.settingBinding(\.video.showShutterAngle))
            } footer: {
                SettingsFooter(Self.notes(video: video, caps: caps, isVideoMode: model.settings.mode == .video))
            }
        }
        .navigationTitle("Video")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Writes one field, then moves resolution and frame rate to the nearest combination a format can record,
    /// so a pick in one menu never leaves the others asking for something the camera doesn't have.
    private func fittedBinding<Value>(_ keyPath: WritableKeyPath<VideoSettings, Value>,
                                      formats: [FormatDescriptor]) -> Binding<Value> {
        Binding(
            get: { model.settings.video[keyPath: keyPath] },
            set: { newValue in
                model.updateSettings { settings in
                    settings.video[keyPath: keyPath] = newValue
                    settings.video = VideoFormatChoices.fitted(settings.video, formats: formats)
                }
            }
        )
    }

    /// The saved rate is shown even when the camera lacks it, and Formatting.frameRate converts to Int, which
    /// traps on a value out of range.
    private static func frameRateLabel(_ fps: Double) -> String {
        guard fps.isFinite, fps > 0, fps < 10_000 else { return "Custom" }
        return Formatting.frameRate(fps)
    }

    /// Codecs, stabilization and noise reduction describe the active format and movie output, which only exist in
    /// VIDEO; resolution, frame rate and color come from every format of the lens and hold in any mode.
    private static func notes(video: VideoSettings, caps: CameraCapabilities, isVideoMode: Bool) -> [String?] {
        var notes: [String?] = ["Choices follow what the current camera can record."]
        var recordable = VideoFormatChoices.isRecordable(video, formats: caps.formats) && caps.colorModes.contains(video.colorMode)
        if isVideoMode {
            recordable = recordable && caps.videoCodecs.contains(video.codec)
                && caps.stabilizationModes.contains(video.stabilization)
        } else {
            notes.append("Codec, stabilization and noise reduction choices are complete while video is the active mode.")
        }
        if !recordable {
            notes.append("The current camera can't record these settings exactly, so video uses the closest it has.")
        }
        notes.append(audioPlaybackNote)
        notes.append("Wind noise reduction takes the rumble of wind out of the sound, on iPhones that support it.")
        notes.append("Shutter angle shows the shutter in degrees while filming; 180\u{00B0} gives the classic film look.")
        var unavailable = UnavailableFeatures()
        unavailable.noteFromIOS27("low light noise reduction", supported: caps.lowLightVideoNoiseReductionSupported)
        notes.append(unavailable.text)
        return notes
    }
}

/// Video in the short list: the one video setting most people change in Settings rather than on the camera.
struct BasicVideoSection: View {
    let model: CameraModel

    var body: some View {
        let recordsSound = model.settings.video.audio

        Section {
            // Without sound the camera leaves the audio session alone, so other apps keep playing anyway.
            Toggle("Allow audio playback", isOn: model.settingBinding(\.video.allowAudioPlayback))
                .disabled(!recordsSound)
        } header: {
            Text("Video")
        } footer: {
            SettingsFooter([
                audioPlaybackNote,
                // The switch that dims this row is not in the short list, so the footer has to name the reason.
                recordsSound ? nil : "Video is set to record without sound, so other apps keep playing either way.",
            ])
        }
    }
}

/// What allowing audio playback means for the recording, in the short list and on the Video page.
private let audioPlaybackNote = "Music and other apps keep playing while you film. The microphone can pick them up."
