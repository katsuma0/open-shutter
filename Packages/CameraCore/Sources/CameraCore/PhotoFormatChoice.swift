import Foundation

/// One row of the photo format list, as the top bar's menu, the quick settings panel and Settings show it. Two
/// stored fields lie behind the rows, the container (`processedFormat`) and `highQuality`, so High is no format
/// of its own: every switch over containers stays one case per file type, and the Quality slider keeps its place
/// while High is on. "High", not Apple Camera's "Max", which there names the 48 MP size.
public enum PhotoFormatChoice: String, CaseIterable, Identifiable, Sendable {
    case heif, heifHigh, jpeg, jpegHigh, png, tiff, rawOnly

    /// The quality HEIF High and JPEG High save at. Lossless for HEIF; kept in one place so it can come down a
    /// little if those files turn out too large on a phone.
    public static let highQuality = 1.0

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heif: return "HEIF"
        case .heifHigh: return "HEIF High"
        case .jpeg: return "JPEG"
        case .jpegHigh: return "JPEG High"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .rawOnly: return "RAW only"
        }
    }

    /// The container this row saves. RAW only saves none beside the RAW file.
    public var format: ProcessedFormat {
        switch self {
        case .heif, .heifHigh: return .heif
        case .jpeg, .jpegHigh: return .jpeg
        case .png: return .png
        case .tiff: return .tiff
        case .rawOnly: return .none
        }
    }

    public var isHigh: Bool { self == .heifHigh || self == .jpegHigh }

    /// The Quality slider sets plain HEIF and JPEG. It sets RAW only too, whose stacks save HEIF. High saves at
    /// `highQuality` whatever the slider says, and PNG and TIFF lose nothing to compression.
    public var takesQualitySlider: Bool {
        switch self {
        case .heif, .jpeg, .rawOnly: return true
        case .heifHigh, .jpegHigh, .png, .tiff: return false
        }
    }

    /// The row the stored fields show as. High only means something for HEIF and JPEG, so PNG and TIFF read the
    /// same with it on or off.
    public init(_ capture: CaptureOptions) {
        switch capture.processedFormat {
        case .heif: self = capture.highQuality ? .heifHigh : .heif
        case .jpeg: self = capture.highQuality ? .jpegHigh : .jpeg
        case .png: self = .png
        case .tiff: self = .tiff
        case .none: self = .rawOnly
        }
    }

    /// Picks this row: the container and High. The Quality slider's value stays for the next plain HEIF or JPEG,
    /// and RAW is the RAW row's to change. High goes off with every other row, RAW only's included, so a stack
    /// saved as HEIF beside RAW follows the slider again.
    public func apply(to capture: inout CaptureOptions) {
        capture.processedFormat = format
        capture.highQuality = isHigh
    }

    /// The rows to offer, in order. Without HEIF on this phone there are no HEIF rows, and RAW only is offered only
    /// while a RAW file is on, as it saves nothing else.
    public static func choices(heif: Bool, rawOn: Bool) -> [PhotoFormatChoice] {
        allCases.filter { choice in
            switch choice.format {
            case .heif: return heif
            case .none: return rawOn
            case .jpeg, .png, .tiff: return true
            }
        }
    }
}
