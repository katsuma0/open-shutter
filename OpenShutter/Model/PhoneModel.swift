import Foundation

/// Which iPhone the app runs on, as far as the camera's features go. Manual shutter speeds are offered on the
/// iPhone 18 Pro and later Pros only; every other iPhone still gets the night shot and the long exposure scenes,
/// whose lengths are set as a duration rather than a shutter speed.
enum PhoneModel {
    /// "iPhone19,1". The Simulator reports the Mac's architecture here, so it never matches.
    static let identifier: String = {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }()

    /// The iPhone 18 Pro and Pro Max by their model identifiers, and the Pros after them. Apple numbers a year's
    /// phones one major version up (the iPhone 17 Pro is iPhone18,1) and gives the Pro and Pro Max minor 1 and 2.
    /// The variable aperture, which only these phones have, says the same once the main camera is open
    /// (CameraModel.allowsManualShutter), so a guess wrong here is put right on the first launch.
    static var isProShutterPhone: Bool {
        let parts = identifier.dropFirst("iPhone".count).split(separator: ",")
        guard identifier.hasPrefix("iPhone"), parts.count == 2,
              let major = Int(parts[0]), let minor = Int(parts[1]) else { return false }
        return major >= 19 && (minor == 1 || minor == 2)
    }

    /// The camera has reported a variable aperture on this phone before. Kept, because the report only comes
    /// while the main camera is open, and the answer must hold from the first frame of the next launch.
    static var variableApertureSeen: Bool {
        get { UserDefaults.standard.bool(forKey: "device.variableApertureSeen") }
        set { UserDefaults.standard.set(newValue, forKey: "device.variableApertureSeen") }
    }
}
