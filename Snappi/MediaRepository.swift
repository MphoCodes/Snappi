import Foundation
import UIKit
import AVFoundation
import ImageIO

struct CaptureItem: Identifiable {
    var url: URL
    var id: String { url.lastPathComponent }
    var isVideo: Bool { url.pathExtension == "mov" }
    var date: Date { (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
    var isOriginal: Bool { url.lastPathComponent.hasPrefix("original-") }
}
protocol MediaRepository: Sendable {
    func items() -> [CaptureItem]
    func newURL(extension ext: String, original: Bool) -> URL
    func write(_ data: Data, to url: URL) throws
    func remove(_ url: URL) throws
    func thumbnail(_ item: CaptureItem, maxPixelSize: Int) async -> UIImage?
}
extension MediaRepository {
    func newURL(extension ext: String) -> URL { newURL(extension: ext, original: false) }
    func thumbnail(_ item: CaptureItem) async -> UIImage? { await thumbnail(item, maxPixelSize: 800) }
}
struct LocalMediaRepository: MediaRepository {
    let directory: URL
    init(directory: URL = URL.documentsDirectory.appendingPathComponent("Captures", isDirectory: true)) {
        self.directory = directory
    }
    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
    func items() -> [CaptureItem] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { ["jpg", "mov"].contains($0.pathExtension) }.map { CaptureItem(url: $0) }.sorted { $0.date > $1.date }
    }
    func newURL(extension ext: String, original: Bool = false) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(original ? "original-" : "snappi-")\(UUID().uuidString).\(ext)")
    }
    func thumbnail(_ item: CaptureItem, maxPixelSize: Int = 800) async -> UIImage? {
        if item.isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: item.url)); generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)
            return (try? await generator.image(at: .zero)).map { UIImage(cgImage: $0.image) }
        }
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixelSize, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
