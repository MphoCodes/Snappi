import Foundation
import UIKit
import Photos
import CoreImage
import AVFoundation

struct CaptureItem: Identifiable {
    var url: URL
    var id: String { url.lastPathComponent }
    var isVideo: Bool { url.pathExtension == "mov" }
    var date: Date { (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
    var isOriginal: Bool { url.lastPathComponent.hasPrefix("original-") }
}
enum MediaLibrary {
    static var directory: URL {
        let url = URL.documentsDirectory.appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func items() -> [CaptureItem] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { ["jpg", "mov"].contains($0.pathExtension) }.map { CaptureItem(url: $0) }.sorted { $0.date > $1.date }
    }
    static func newURL(extension ext: String, original: Bool = false) -> URL {
        directory.appendingPathComponent("\(original ? "original-" : "snappi-")\(UUID().uuidString).\(ext)")
    }
    static func stamp(date: Date) -> CIImage? {
        let formatter = DateFormatter(); formatter.dateFormat = "yy MM dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 60), format: format).image { _ in
            let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.7); shadow.shadowBlurRadius = 3
            (formatter.string(from: date) as NSString).draw(at: CGPoint(x: 4, y: 5), withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 35, weight: .medium), .foregroundColor: UIColor(red: 1, green: 0.72, blue: 0.4, alpha: 1), .shadow: shadow])
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }
    static func processPhoto(_ data: Data, settings: LookSettings, preserveOriginal: Bool) throws -> URL {
        guard let input = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw failure("The photo could not be read.") }
        let original = newURL(extension: "jpg", original: true)
        // Keep the camera bytes until processing and the atomic write both succeed.
        try data.write(to: original, options: .atomic)
        var output = Effects.apply(input, settings: settings)
        if settings.dateStamp, let stamp = stamp(date: Date()) {
            let scale = output.extent.width / 1200
            output = stamp.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: 28 * scale, y: 28 * scale)).composited(over: output).cropped(to: output.extent)
        }
        let context = CIContext()
        guard let jpeg = context.jpegRepresentation(of: output, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.94]) else { throw failure("The effect could not be saved. Your original is kept in the library.") }
        let destination = newURL(extension: "jpg")
        try jpeg.write(to: destination, options: .atomic)
        if !preserveOriginal { try? FileManager.default.removeItem(at: original) }
        return destination
    }
    static func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw failure("Saved inside Snappi. Allow Photos access in Settings to export to your photo library.") }
        try await PHPhotoLibrary.shared().performChanges {
            if url.pathExtension == "mov" { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
            else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
        }
    }
    static func thumbnail(_ item: CaptureItem) async -> UIImage? {
        if item.isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: item.url)); generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            return (try? await generator.image(at: .zero)).map { UIImage(cgImage: $0.image) }
        }
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 800, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    static func failure(_ text: String) -> NSError { NSError(domain: "Snappi", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
