import Foundation
import UIKit
import Combine

enum GalleryFilter: String, CaseIterable {
    case all = "All", photos = "Photos", videos = "Videos", favorites = "Favorites", deleted = "Recently Deleted"
}

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
    @Published private(set) var deleted: [CaptureItem] = []
    @Published private(set) var favorites: Set<String> = []
    func reload() {
        items = repository.items()
        deleted = repository.captures(in: repository.deletedDirectory)
        do { favorites = try readFavorites() }
        catch { message = error.localizedDescription }
    }
    private func readFavorites() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: repository.favoritesURL.path) else { return [] }
        return try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: repository.favoritesURL))
    }
    func captures(_ filter: GalleryFilter) -> [CaptureItem] {
        switch filter {
        case .all: return items
        case .photos: return items.filter { !$0.isVideo }
        case .videos: return items.filter { $0.isVideo }
        case .favorites: return items.filter { favorites.contains($0.id) }
        case .deleted: return deleted
        }
    }
    func toggleFavorites(_ ids: Set<String>) {
        do {
            var updated = try readFavorites()
            if ids.isSubset(of: updated) { updated.subtract(ids) }
            else { updated.formUnion(ids) }
            try repository.write(JSONEncoder().encode(updated), to: repository.favoritesURL)
            favorites = updated
        } catch { message = error.localizedDescription }
    }
    func relocate(_ captures: [CaptureItem], restoring: Bool) {
        defer { reload() }
        do {
            for item in captures { try repository.relocate(item, restoring: restoring) }
        } catch { message = error.localizedDescription }
    }
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
