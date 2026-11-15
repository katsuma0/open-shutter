import Foundation
import CameraCore

/// Keeps CameraSettings in UserDefaults as JSON. CameraSettings decodes missing keys with defaults,
/// so new settings in a later version never wipe what the user already set up.
final class SettingsStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "camera.settings.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> CameraSettings {
        guard let data = defaults.data(forKey: key) else { return .default }
        return CameraSettings.decoded(from: data)
    }

    func save(_ settings: CameraSettings) {
        guard let data = try? settings.encoded() else { return }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: snapshotKey)
    }

    // MARK: - Advanced snapshot

    /// What the earlier simple interface put aside when it was turned on. The camera always shows every control
    /// now, so this is only read once, to bring those settings back, and then cleared.
    private var snapshotKey: String { key + ".advanced" }

    func loadAdvancedSnapshot() -> CameraSettings? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return CameraSettings.decoded(from: data)
    }

    func clearAdvancedSnapshot() {
        defaults.removeObject(forKey: snapshotKey)
    }
}
