import Foundation
import UIKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

struct RetainedPhotoError: LocalizedError {
    let original: URL
    let cause: Error
    var errorDescription: String? { "Original saved in Your Roll. \(cause.localizedDescription)" }
}

protocol MediaProcessing: Sendable {
    func beginPair(_ data: Data, options: CaptureOptions) async throws -> HalfFrame
    func finishPair(_ first: HalfFrame, second data: Data, options: CaptureOptions) async throws -> FinishedPair
    func processPhoto(_ data: Data, settings: LookSettings, preserveOriginal: Bool) async throws -> URL
    func processVideo(_ source: URL, settings: LookSettings, preserveOriginal: Bool) async throws -> URL
}
actor MediaProcessor: MediaProcessing {
    let repository: any MediaRepository
    lazy var renderContext = CIContext(options: [.cacheIntermediates: false])
    init(repository: any MediaRepository) { self.repository = repository }
    func processPhoto(_ data: Data, settings: LookSettings, preserveOriginal: Bool) throws -> URL {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String), let ext = type.preferredFilenameExtension,
              let input = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw SnappiFailure.make("The photo could not be read.")
        }
        let original = repository.newURL(extension: type == .jpeg ? "jpg" : ext, original: true)
        // Keep the camera bytes until processing and the atomic write both succeed.
        try repository.write(data, to: original)
        let output = developedPhoto(input, settings: settings, date: Date())
        do {
            guard let jpeg = renderContext.jpegRepresentation(of: output, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.94]) else {
                throw SnappiFailure.make("The effect could not be rendered.")
            }
            let destination = repository.newURL(extension: "jpg")
            try repository.write(jpeg, to: destination)
            if !preserveOriginal { try? repository.remove(original) }
            return destination
        } catch {
            throw RetainedPhotoError(original: original, cause: error)
        }
    }
    func developedPhoto(_ input: CIImage, settings: LookSettings, date: Date) -> CIImage {
        var output = Effects.apply(input, settings: settings)
        if settings.dateStamp, let stamp = DateStampRenderer.stamp(date: date) {
            let scale = output.extent.width / 1200
            output = stamp.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: 28 * scale, y: 28 * scale)).composited(over: output).cropped(to: output.extent)
        }
        return output
    }
    func processVideo(_ source: URL, settings: LookSettings, preserveOriginal: Bool) async throws -> URL {
        let destination = repository.newURL(extension: "mov")
        do {
            try await VideoRenderer.export(source: source, destination: destination, settings: settings,
                stamp: settings.dateStamp ? DateStampRenderer.stamp(date: Date()) : nil)
            if !preserveOriginal { try? repository.remove(source) }
            return destination
        } catch {
            throw SnappiFailure.make("Video processing failed. The original remains in Snappi’s library. \(error.localizedDescription)")
        }
    }
}
enum DateStampRenderer {
    static func stamp(date: Date) -> CIImage? {
        let formatter = DateFormatter(); formatter.dateFormat = "yy MM dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 60), format: format).image { _ in
            let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(0.7); shadow.shadowBlurRadius = 3
            (formatter.string(from: date) as NSString).draw(at: CGPoint(x: 4, y: 5), withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 35, weight: .medium), .foregroundColor: UIColor(red: 1, green: 0.72, blue: 0.4, alpha: 1), .shadow: shadow])
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }
}
