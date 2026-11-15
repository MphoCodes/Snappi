import Foundation
import AVFoundation
import CoreImage

@main struct VideoChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mov"), destination = directory.appendingPathComponent("noir.mov")
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 96, AVVideoHeightKey: 160])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 96, kCVPixelBufferHeightKey as String: 160])
        writer.add(input); guard writer.startWriting() else { throw writer.error! }; writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        for n in 0..<12 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let colour = CIImage(color: CIColor(red: 0.2, green: 0.65, blue: 0.85)).cropped(to: CGRect(x: 0, y: 0, width: 96, height: 160))
            context.render(colour, to: buffer!)
            guard adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(n), timescale: 12)) else { throw writer.error! }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error! }
        try await VideoRenderer.export(source: source, destination: destination, settings: LookSettings(look: .noir, strength: 1, grain: 0))
        let asset = AVURLAsset(url: destination)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0.8 && duration < 1.2 else { fatalError("Export changed duration: \(duration)") }
        let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
        let (image, _) = try await generator.image(at: .zero)
        guard image.height > image.width else { fatalError("Portrait orientation lost") }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(CIImage(cgImage: image), toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 20, y: 20, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        guard abs(Int(pixel[0]) - Int(pixel[1])) < 6 && abs(Int(pixel[1]) - Int(pixel[2])) < 6 else { fatalError("Export did not apply Noir: \(pixel)") }
        guard FileManager.default.fileExists(atPath: source.path) else { fatalError("Export deleted source") }
        do {
            try await VideoRenderer.export(source: directory.appendingPathComponent("missing.mov"), destination: directory.appendingPathComponent("bad.mov"), settings: LookSettings())
            fatalError("Missing input accepted")
        } catch { }
        print("Video checks passed: effect, portrait orientation, duration, source preservation, invalid-input error")
    }
}
