import Foundation
import UIKit
import Combine

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published private(set) var items: [CaptureItem] = []
    @Published private(set) var exporting = false
    @Published var message: String?
    let repository: any MediaRepository
    private let exporter: any PhotoLibraryExporting
    init(repository: any MediaRepository, exporter: any PhotoLibraryExporting) {
        self.repository = repository; self.exporter = exporter
    }
    func reload() { items = repository.items() }
    func export(_ item: CaptureItem, number: Int) {
        guard !exporting else { return }
        exporting = true
        let url = item.url
        Task {
            defer { exporting = false }
            do { try await exporter.saveToPhotos(url); message = "Capture \(number) saved to Photos" }
            catch { message = error.localizedDescription }
        }
    }
}
@MainActor
final class ThumbnailViewModel: ObservableObject {
    @Published private(set) var image: UIImage?
    private let repository: any MediaRepository
    private let item: CaptureItem
    init(item: CaptureItem, repository: any MediaRepository) { self.item = item; self.repository = repository }
    func load(maxPixelSize: Int = 800) async {
        guard image == nil else { return }
        let result = await repository.thumbnail(item, maxPixelSize: maxPixelSize)
        guard !Task.isCancelled else { return }
        image = result
    }
}
