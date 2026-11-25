import CoreImage
import UIKit

private actor PairExporter: PhotoLibraryExporting {
    private(set) var urls: [URL] = []
    func saveToPhotos(_ url: URL) async throws { urls.append(url) }
}

@MainActor
func checkHalfFrames(in folder: URL) async throws {
    let repository = LocalMediaRepository(directory: folder.appendingPathComponent("pairs"))
    let processor = MediaProcessor(repository: repository)
    let camera = FakeCamera()
    let exporter = PairExporter()
    let model = CameraViewModel(capture: camera, processor: processor, repository: repository, exporter: exporter)
    camera.onUpdate? { $0.ready = true }

    func photo(_ color: UIColor, landscape: Bool = false) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = landscape ? CGSize(width: 64, height: 48) : CGSize(width: 36, height: 64)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 1)!
    }
    let red = photo(.red), blue = photo(.blue, landscape: true)
    let options = CaptureOptions(settings: LookSettings(look: .original, grain: 0), preserveOriginal: false, exportToPhotos: true)
    func shoot(_ data: Data, options: CaptureOptions) async {
        let previous = camera.captures
        model.shutter(video: false, flash: false, delay: 0, pair: true)
        await Task.yield()
        precondition(camera.captures == previous + 1)
        camera.onCapture?(.photo(data, options))
        await model.waitForProcessing()
    }
    await shoot(red, options: options)
    precondition(model.firstHalfFrame?.preview.size == CGSize(width: 36, height: 48))
    precondition(model.latest == nil && !model.busy)
    await model.cancelPair()
    precondition(repository.items().isEmpty && model.firstHalfFrame == nil)

    await shoot(red, options: options)
    model.shutter(video: false, flash: false, delay: 3, pair: true)
    model.suspend()
    precondition(model.firstHalfFrame != nil && !model.busy)
    let firstURL = model.firstHalfFrame?.original
    await shoot(Data([0]), options: options)
    precondition(model.firstHalfFrame?.original == firstURL, "A failed second shot must leave the first panel ready for retry")
    // The invalid test delivery may retain a recovery file alongside the finished pair.
    let recoveryFiles = Set(repository.items().map(\.url)).subtracting([firstURL!])
    await shoot(blue, options: options)
    let saved = model.latest!
    precondition(Set(repository.items().map(\.url)) == recoveryFiles.union([saved]))
    for url in recoveryFiles { try repository.remove(url) }
    let exported = await exporter.urls
    precondition(exported == [saved] && model.firstHalfFrame == nil)
    let image = CIImage(contentsOf: saved)!
    precondition(image.extent == CGRect(x: 0, y: 0, width: 72, height: 48))
    func sample(at x: CGFloat) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: 4)
        CIContext().render(image, toBitmap: &rgba, rowBytes: 4,
                           bounds: CGRect(x: x, y: 24, width: 1, height: 1), format: .RGBA8,
                           colorSpace: CGColorSpaceCreateDeviceRGB())
        return rgba
    }
    let left = sample(at: 18), right = sample(at: 54)
    precondition(left[0] > 220 && left[2] < 30 && right[2] > 220 && right[0] < 30)

    var keep = options
    keep.preserveOriginal = true
    await shoot(red, options: keep)
    await model.cancelPair()
    precondition(repository.items().filter(\.isOriginal).count == 1)
    let failureStore = LocalMediaRepository(directory: folder.appendingPathComponent("pair-failure"))
    let failing = MediaProcessor(repository: FailingProcessedWrite(base: failureStore))
    let frame = try await failing.beginPair(red, options: options)
    do {
        _ = try await failing.finishPair(frame, second: blue, options: options)
        fatalError("Expected final pair write to fail")
    } catch {
        let originals = try failureStore.items().map { try Data(contentsOf: $0.url) }
        precondition(originals.count == 2 && originals.contains(red) && originals.contains(blue))
    }
    let deniedCamera = FakeCamera()
    let denied = CameraViewModel(capture: deniedCamera, processor: processor, repository: repository, exporter: DeniedExporter())
    deniedCamera.onUpdate? { $0.ready = true }
    for data in [red, blue] {
        denied.shutter(video: false, flash: false, delay: 0, pair: true)
        await Task.yield()
        deniedCamera.onCapture?(.photo(data, options))
        await denied.waitForProcessing()
    }
    precondition(denied.latest != nil && denied.error == "Photos denied")
    precondition(repository.items().filter(\.isOriginal).count == 3)
    print("Half-frame checks passed: shutter sequence, preview, cancellation, interrupted timer, JPEG dimensions and side order, single export, original preservation")
}
