import CoreImage
import UIKit

struct HalfFrame: Sendable {
    let original: URL
    let options: CaptureOptions
    let date: Date
    let preview: UIImage
}

struct FinishedPair: Sendable {
    let image: URL
    let disposableOriginals: [URL]
}

extension MediaProcessor {
    func beginPair(_ data: Data, options: CaptureOptions) throws -> HalfFrame {
        let original = try storePairOriginal(data)
        let image = try pairInput(original)
        let unit = min(160, panelUnit(image))
        let date = Date()
        let panel = renderPanel(image, unit: unit, settings: options.settings, date: date)
        guard let preview = CIContext().createCGImage(panel, from: panel.extent) else {
            throw SnappiFailure.make("Could not preview the first frame. Its original is in your roll.")
        }
        return HalfFrame(original: original, options: options, date: date, preview: UIImage(cgImage: preview))
    }

    func finishPair(_ first: HalfFrame, second data: Data, options: CaptureOptions) throws -> FinishedPair {
        let second = try storePairOriginal(data)
        let left = try pairInput(first.original)
        let right = try pairInput(second)
        let unit = min(panelUnit(left), panelUnit(right))
        let firstPanel = renderPanel(left, unit: unit, settings: first.options.settings, date: first.date)
        let secondPanel = renderPanel(right, unit: unit, settings: options.settings, date: Date())
            .transformed(by: CGAffineTransform(translationX: firstPanel.extent.width, y: 0))
        let pair = firstPanel.composited(over: secondPanel)
        guard let jpeg = CIContext().jpegRepresentation(of: pair, colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.94]) else {
            throw SnappiFailure.make("Could not develop the pair. Both originals are in your roll.")
        }
        let destination = repository.newURL(extension: "jpg")
        try repository.write(jpeg, to: destination)
        var disposableOriginals: [URL] = []
        if !first.options.preserveOriginal { disposableOriginals.append(first.original) }
        if !options.preserveOriginal { disposableOriginals.append(second) }
        return FinishedPair(image: destination, disposableOriginals: disposableOriginals)
    }

    private func storePairOriginal(_ data: Data) throws -> URL {
        let url = repository.newURL(extension: "jpg", original: true)
        try repository.write(data, to: url)
        return url
    }

    private func pairInput(_ url: URL) throws -> CIImage {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              image.extent.width >= 3, image.extent.height >= 4 else {
            throw SnappiFailure.make("Could not read a half-frame photo. Its original is in your roll.")
        }
        return image
    }

    // Each panel is a centred 3:4 crop. Use an integral size both cameras can supply.
    private func panelUnit(_ image: CIImage) -> CGFloat {
        floor(min(image.extent.width / 3, image.extent.height / 4))
    }

    private func renderPanel(_ image: CIImage, unit: CGFloat, settings: LookSettings, date: Date) -> CIImage {
        let bounds = CGRect(x: 0, y: 0, width: 3 * unit, height: 4 * unit)
        let scale = max(bounds.width / image.extent.width, bounds.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let panel = scaled.transformed(by: CGAffineTransform(translationX: bounds.midX - scaled.extent.midX,
                                                               y: bounds.midY - scaled.extent.midY)).cropped(to: bounds)
        return developedPhoto(panel, settings: settings, date: date)
    }
}
