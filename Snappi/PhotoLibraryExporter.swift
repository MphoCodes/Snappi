import Foundation
import Photos

protocol PhotoLibraryExporting: Sendable {
    func saveToPhotos(_ url: URL) async throws
}
struct PhotoLibraryExporter: PhotoLibraryExporting {
    func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SnappiFailure.make("Saved inside Snappi. Allow Photos access in Settings to export to your photo library.") }
        try await PHPhotoLibrary.shared().performChanges {
            if url.pathExtension == "mov" { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
            else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
        }
    }
}
enum SnappiFailure {
    static func make(_ text: String) -> NSError { NSError(domain: "Snappi", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
