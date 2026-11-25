import Foundation
import AVFoundation
import CoreImage

enum VideoRenderer {
    static func export(source: URL, destination: URL, settings: LookSettings, stamp: CIImage? = nil) async throws {
        let asset = AVURLAsset(url: source)
        let composition = AVVideoComposition(asset: asset) { request in
            var result = Effects.apply(request.sourceImage, settings: settings)
            if let stamp {
                let scale = result.extent.width / 1200
                let overlay = stamp.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .transformed(by: CGAffineTransform(translationX: 28 * scale, y: 28 * scale))
                result = overlay.composited(over: result)
            }
            request.finish(with: result.cropped(to: request.sourceImage.extent), context: nil)
        }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else {
            throw NSError(domain: "Snappi", code: 1, userInfo: [NSLocalizedDescriptionKey: "This video could not be prepared for export."])
        }
        exporter.videoComposition = composition
        // An interrupted export can leave a zero-byte MOV. Publish only completed movies to the roll.
        let files = FileManager.default
        let staging = try files.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                    appropriateFor: destination, create: true)
        defer { try? files.removeItem(at: staging) }
        let stagedMovie = staging.appendingPathComponent(destination.lastPathComponent)
        exporter.outputURL = stagedMovie
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = true
        await exporter.export()
        guard exporter.status == .completed else {
            throw exporter.error ?? NSError(domain: "Snappi", code: 2, userInfo: [NSLocalizedDescriptionKey: "Video processing was interrupted. The original is kept in your library."])
        }
        try files.moveItem(at: stagedMovie, to: destination)
    }
}
