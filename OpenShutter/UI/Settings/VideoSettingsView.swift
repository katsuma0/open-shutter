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
                Toggle("Low light noise reduction", isOn: model.settingBinding(\.video.lowLightNoiseReduction))
                    .disabled(!caps.lowLightVideoNoiseReductionSupported)
                Toggle("Show shutter angle", isOn: model.settingBinding(\.video.showShutterAngle))
            } footer: {
                SettingsFooter(Self.notes(video: video, caps: caps, isVideoMode: model.settings.mode == .video))
            }

            Section {
                Toggle("Record sound", isOn: model.settingBinding(\.video.audio))
                // Without sound the camera leaves the audio session alone, so other apps keep playing anyway.
                Toggle("Allow audio playback", isOn: model.settingBinding(\.video.allowAudioPlayback))
                    .disabled(!video.audio)
                Toggle("Wind noise reduction", isOn: model.settingBinding(\.video.windNoiseReduction))
                    .disabled(!video.audio)
            } header: {
                Text("Sound")
            } footer: {
                Text(audioPlaybackNote)
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
        var notes: [String?] = []
        var recordable = VideoFormatChoices.isRecordable(video, formats: caps.formats) && caps.colorModes.contains(video.colorMode)
        if isVideoMode {
            recordable = recordable && caps.videoCodecs.contains(video.codec)
                && caps.stabilizationModes.contains(video.stabilization)
        } else {
            notes.append("Some choices show only while the camera is in Video.")
        }
        if !recordable {
            notes.append("This camera can't record this exactly, so video uses the closest it has.")
        }
        var unavailable = UnavailableFeatures()
        unavailable.noteFromIOS27("low light noise reduction", supported: caps.lowLightVideoNoiseReductionSupported)
        notes.append(unavailable.text)
        return notes
    }
}

/// Video in the short list: sound, the video settings most people change in Settings rather than on the camera.
struct BasicVideoSection: View {
    let model: CameraModel

    var body: some View {
        Section {
            Toggle("Record sound", isOn: model.settingBinding(\.video.audio))
            // Without sound the camera leaves the audio session alone, so other apps keep playing anyway.
            Toggle("Allow audio playback", isOn: model.settingBinding(\.video.allowAudioPlayback))
                .disabled(!model.settings.video.audio)
        } header: {
            Text("Video")
        } footer: {
            Text(audioPlaybackNote)
        }
    }
}

/// What allowing audio playback means for the recording, in the short list and on the Video page.
private let audioPlaybackNote = "Allow audio playback keeps music playing while you film, and the microphone may record it."
