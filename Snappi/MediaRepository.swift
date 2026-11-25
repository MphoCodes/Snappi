import Foundation
import UIKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct CaptureItem: Identifiable, Sendable {
    let url: URL
    let id: String
    let date: Date
    let allocatedBytes: Int64?
    var isVideo: Bool { url.pathExtension == "mov" }
    var isOriginal: Bool { id.hasPrefix("original-") }

    init(url: URL, values: URLResourceValues? = nil) {
        self.url = url
        id = url.lastPathComponent
        let metadata = values ?? (try? url.resourceValues(forKeys: [.creationDateKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]))
        date = metadata?.creationDate ?? .distantPast
        allocatedBytes = (metadata?.totalFileAllocatedSize ?? metadata?.fileAllocatedSize).map(Int64.init)
    }
}
protocol MediaRepository: Sendable {
    var directory: URL { get }
    func items() -> [CaptureItem]
    func newURL(extension ext: String, original: Bool) -> URL
    func write(_ data: Data, to url: URL) throws
    func remove(_ url: URL) throws
    func thumbnail(_ item: CaptureItem, maxPixelSize: Int) async -> UIImage?
}
extension MediaRepository {
    var deletedDirectory: URL { directory.appendingPathComponent("Recently Deleted", isDirectory: true) }
    var favoritesURL: URL { directory.appendingPathComponent("favorites.json") }
    func captures(in folder: URL) -> [CaptureItem] {
        var keys: Set<URLResourceKey> = [.creationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        if folder == deletedDirectory { keys.formUnion([.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) }
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []
        return urls.compactMap { url -> CaptureItem? in
            guard let values = captureMetadata(at: url, keys: keys) else { return nil }
            return CaptureItem(url: url, values: values)
        }.sorted { $0.date > $1.date }
    }
    private func captureMetadata(at url: URL, keys: Set<URLResourceKey>) -> URLResourceValues? {
        let ext = url.pathExtension.lowercased()
        guard ext == "jpg" || ext == "mov" ||
                (url.lastPathComponent.hasPrefix("original-") && UTType(filenameExtension: ext)?.conforms(to: .image) == true),
              let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true, values.isSymbolicLink == false else { return nil }
        return values
    }
    func rollPreview(preferred: URL?) async -> (count: Int, thumbnail: UIImage?) {
        let captures = items()
        guard !Task.isCancelled, let item = preferred.flatMap({ url in captures.first { $0.url == url } }) ?? captures.first else {
            return (captures.count, nil)
        }
        return (captures.count, await thumbnail(item))
    }
    func permanentlyDelete(_ item: CaptureItem) throws {
        // Resolve the repository root first so a redirected trash directory cannot target live files.
        let trash = directory.resolvingSymlinksInPath().appendingPathComponent(deletedDirectory.lastPathComponent)
        let url = URL(fileURLWithPath: item.url.path)
        guard url.resolvingSymlinksInPath().deletingLastPathComponent().path == trash.path,
              captureMetadata(at: url, keys: [.isRegularFileKey, .isSymbolicLinkKey]) != nil else {
            throw SnappiFailure.make("Only files in Recently Deleted can be permanently deleted.")
        }
        try remove(url)
    }

    func relocate(_ item: CaptureItem, restoring: Bool) throws {
        let destination = restoring ? directory : deletedDirectory
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: item.url, to: destination.appendingPathComponent(item.id))
    }

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
    func items() -> [CaptureItem] { captures(in: directory) }
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
