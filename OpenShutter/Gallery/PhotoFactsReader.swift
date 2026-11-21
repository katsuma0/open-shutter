import Foundation
import Photos
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import CoreLocation
import MapKit
import UIKit
import CameraCore

/// Reads what the gallery's info panel shows about one photo: the camera's original file through ImageIO, and a small
/// picture of the photo for its histogram. Everything here runs off the main actor;
/// CameraCore's `PhotoFacts` turns the values into text.
enum PhotoFactsReader {
    /// The side of the small picture the histogram is made from.
    static let picturePixels: CGFloat = 160

    /// What PhotoKit knows already, with no file read: enough for the header's marks while the file loads.
    static func quickInput(for asset: PHAsset) -> PhotoFacts.Input {
        var input = PhotoFacts.Input()
        let subtypes = asset.mediaSubtypes
        input.isLive = subtypes.contains(.photoLive)
        input.hasGainMap = subtypes.contains(.photoHDR)
        input.hasDepth = subtypes.contains(.photoDepthEffect)
        input.isEdited = asset.hasAdjustments
        return input
    }

    /// The facts from the asset's original file. `place` is where Photos puts the photo (it may have been moved
    /// there); the file's altitude and direction are kept only when the file was taken near it. nil when the file
    /// can't be read, offline with only an iCloud copy or unreadable; the reading stops with its task.
    static func read(_ asset: PHAsset, place: CLLocationCoordinate2D?,
                     progress: (@Sendable (Double) -> Void)? = nil) async -> PhotoFacts? {
        var input = quickInput(for: asset)
        let resources = PHAssetResource.assetResources(for: asset)
        guard let primary = resources.first(where: { $0.type == .photo })
                ?? resources.first(where: { $0.type == .alternatePhoto }) else { return nil }
        let type = typeIdentifier(of: primary)
        input.format = format(of: type)
        input.hasRAWCompanion = input.format != .raw && resources.contains {
            $0.type == .alternatePhoto && PhotoInfoFiles.isRAW(typeIdentifier: typeIdentifier(of: $0))
        }
        guard let data = await AssetRequests.data(of: primary, progress: progress), !Task.isCancelled else {
            return nil
        }
        input.fileBytes = knownSize(of: primary) ?? Int64(data.count)
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, options) as? [String: Any] ?? [:]
        fill(&input, from: properties, place: place)
        if !input.hasGainMap {
            input.hasGainMap = hasAux(source, index, kCGImageAuxiliaryDataTypeHDRGainMap)
                || hasAux(source, index, kCGImageAuxiliaryDataTypeISOGainMap)
        }
        if !input.hasDepth {
            input.hasDepth = hasAux(source, index, kCGImageAuxiliaryDataTypeDepth)
                || hasAux(source, index, kCGImageAuxiliaryDataTypeDisparity)
        }
        input.app = AssetRequests.appValues(in: source, at: index)
        return PhotoFacts(input)
    }

    // MARK: - The file

    private static func typeIdentifier(of resource: PHAssetResource) -> String {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            return resource.contentType.identifier
        }
        #endif
        return resource.uniformTypeIdentifier
    }

    /// The size PhotoKit knows without the bytes. The iOS 27 SDK tells it; earlier, the bytes read say it.
    private static func knownSize(of resource: PHAssetResource) -> Int64? {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return resource.dataSize.map(Int64.init)
        }
        #endif
        return nil
    }

    private static func format(of identifier: String) -> PhotoFacts.FileFormat {
        guard let type = UTType(identifier) else { return .other }
        // RAW first: a DNG is also a TIFF to UTType.
        if PhotoInfoFiles.isRAW(type) { return .raw }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return .heif }
        if type.conforms(to: .jpeg) { return .jpeg }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .tiff) { return .tiff }
        return .other
    }

    private static func fill(_ input: inout PhotoFacts.Input, from properties: [String: Any],
                             place: CLLocationCoordinate2D?) {
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        func number(_ group: [String: Any], _ key: CFString) -> Double? {
            group[key as String].flatMap(PhotoInfoNames.number)
        }
        func int(_ group: [String: Any], _ key: CFString) -> Int? {
            group[key as String].flatMap(PhotoInfoNames.int)
        }
        func text(_ group: [String: Any], _ key: CFString) -> String? {
            PhotoInfoNames.text(group[key as String])
        }

        input.make = text(tiff, kCGImagePropertyTIFFMake)
        input.model = text(tiff, kCGImagePropertyTIFFModel)
        if input.format == .raw, let photometric = int(tiff, kCGImagePropertyTIFFPhotometricInterpretation) {
            if photometric == 34892 { input.linearRAW = true }
            if photometric == 32803 { input.linearRAW = false }
        }
        input.lensModel = text(exif, kCGImagePropertyExifLensModel)
        input.focalLength = number(exif, kCGImagePropertyExifFocalLength)
        input.focalLength35 = number(exif, kCGImagePropertyExifFocalLenIn35mmFilm)
        input.fNumber = number(exif, kCGImagePropertyExifFNumber)
        input.iso = exif[kCGImagePropertyExifISOSpeedRatings as String].flatMap { PhotoInfoNames.numbers($0).first }
        input.exposureSeconds = number(exif, kCGImagePropertyExifExposureTime)
        input.exposureBias = number(exif, kCGImagePropertyExifExposureBiasValue)
        input.meteringMode = int(exif, kCGImagePropertyExifMeteringMode)
        input.flash = int(exif, kCGImagePropertyExifFlash)
        input.exifWhiteBalance = int(exif, kCGImagePropertyExifWhiteBalance)
        input.offsetTime = text(exif, kCGImagePropertyExifOffsetTimeOriginal)
            ?? text(exif, kCGImagePropertyExifOffsetTime)
        input.exifColorSpace = int(exif, kCGImagePropertyExifColorSpace)
        input.profileName = PhotoInfoNames.text(properties[kCGImagePropertyProfileName as String])
        input.pixelWidth = properties[kCGImagePropertyPixelWidth as String].flatMap(PhotoInfoNames.int)
        input.pixelHeight = properties[kCGImagePropertyPixelHeight as String].flatMap(PhotoInfoNames.int)
        input.orientation = properties[kCGImagePropertyOrientation as String].flatMap(PhotoInfoNames.int)

        // Photos' own place may have been moved, or the file's GPS may be from somewhere else: the height and the
        // direction belong to the file's point, so they show only when that point is where Photos puts the photo.
        guard let place,
              let latitude = number(gps, kCGImagePropertyGPSLatitude)
                .flatMap({ MetadataFormat.signedDegrees($0, ref: text(gps, kCGImagePropertyGPSLatitudeRef)) }),
              let longitude = number(gps, kCGImagePropertyGPSLongitude)
                .flatMap({ MetadataFormat.signedDegrees($0, ref: text(gps, kCGImagePropertyGPSLongitudeRef)) })
        else { return }
        let filePoint = CLLocation(latitude: latitude, longitude: longitude)
        let photosPoint = CLLocation(latitude: place.latitude, longitude: place.longitude)
        guard filePoint.distance(from: photosPoint) <= 200 else { return }
        input.altitude = number(gps, kCGImagePropertyGPSAltitude)
        input.altitudeRef = int(gps, kCGImagePropertyGPSAltitudeRef)
        input.heading = number(gps, kCGImagePropertyGPSImgDirection)
    }

    private static func hasAux(_ source: CGImageSource, _ index: Int, _ type: CFString) -> Bool {
        CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, index, type) != nil
    }

    // MARK: - The small picture

    /// The RGB histogram of the photo as it shows, edits included. Drawn in Display P3 so a saturated colour isn't
    /// clipped before it is counted.
    static func histogram(of image: CGImage) -> Histogram? {
        let side = Int(picturePixels)
        let wide = image.width >= image.height
        let longest = max(wide ? image.width : image.height, 1)
        let width = wide ? side : max(1, side * image.width / longest)
        let height = wide ? max(1, side * image.height / longest) : side
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.displayP3) else { return nil }
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: space, bitmapInfo: info) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return pixels.withUnsafeBytes { buffer -> Histogram? in
            guard let base = buffer.baseAddress else { return nil }
            let plane = PlaneView(base: base, width: width, height: height, bytesPerRow: bytesPerRow)
            return HistogramComputer.compute(bgra: plane, step: 1).0
        }
    }
}

/// The name of the place a photo was taken, from Apple's servers, as Photos shows it. They limit how often an app
/// may ask, so a lookup waits its turn, and every answer, a failure too, is kept for the app's run: a burst of shots
/// in one place costs one request, and a dead network isn't asked again and again.
actor PlaceLookup {
    static let shared = PlaceLookup()

    /// About 11 m: shots that close together share a name.
    private struct Key: Hashable {
        let latitude: Int
        let longitude: Int

        init(_ coordinate: CLLocationCoordinate2D) {
            latitude = Int((coordinate.latitude * 10_000).rounded())
            longitude = Int((coordinate.longitude * 10_000).rounded())
        }
    }

    private var names: [Key: [String]] = [:]
    private var isAsking = false

    /// Up to three lines, place first; empty when there is no name to give (offline, or nothing there). nil when
    /// the task was cancelled before an answer.
    func lines(for coordinate: CLLocationCoordinate2D) async -> [String]? {
        let key = Key(coordinate)
        if let known = names[key] { return known }
        while isAsking {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return nil }
            if let known = names[key] { return known }
        }
        isAsking = true
        defer { isAsking = false }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let found = await Self.ask(location)
        if Task.isCancelled && found == nil { return nil }
        let lines = found ?? []
        names[key] = lines
        return lines
    }

    private static func ask(_ location: CLLocation) async -> [String]? {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            request.preferredLocale = Locale.current
            guard let item = try? await request.mapItems.first else { return nil }
            let address = item.addressRepresentations
            return PhotoFacts.placeLines(name: item.name, city: address?.cityWithContext(.short),
                                         region: address?.regionName)
        }
        #endif
        return await askBefore26(location)
    }

    /// CLGeocoder, which iOS 26 deprecates for MKReverseGeocodingRequest. Kept in a function of its own, outside
    /// any iOS 26 check, where the deprecation doesn't apply to the iOS 18 target.
    private static func askBefore26(_ location: CLLocation) async -> [String]? {
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: .current).first
        else { return nil }
        return PhotoFacts.placeLines(name: mark.areasOfInterest?.first ?? mark.name, subLocality: mark.subLocality,
                                     locality: mark.locality, administrativeArea: mark.administrativeArea,
                                     country: mark.country)
    }
}
