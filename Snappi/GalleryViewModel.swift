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
    @Published private(set) var deletedBytes: Int64? = 0
    @Published private(set) var favorites: Set<String> = []
    func reload() {
        items = repository.items()
        deleted = repository.captures(in: repository.deletedDirectory)
        let sizes = deleted.compactMap(\.allocatedBytes)
        deletedBytes = sizes.count == deleted.count ? sizes.reduce(0, +) : nil
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
    func permanentlyDelete(_ ids: Set<String>) {
        var removed: Set<String> = []
        var errors: [String] = []
        for item in deleted where ids.contains(item.id) {
            do {
                try repository.permanentlyDelete(item)
                removed.insert(item.id)
            } catch { errors.append(error.localizedDescription) }
        }
        do {
            let stored = try readFavorites()
            // A live capture can share a legacy filename with an item in the trash.
            let obsolete = removed.filter { !FileManager.default.fileExists(atPath: repository.directory.appendingPathComponent($0).path) }
            let updated = stored.subtracting(obsolete)
            if updated != stored {
                try repository.write(JSONEncoder().encode(updated), to: repository.favoritesURL)
            }
        } catch { errors.append("Favorites could not be updated. \(error.localizedDescription)") }
        reload()
        if !errors.isEmpty {
            message = "Deleted \(removed.count) of \(ids.count). " + Array(Set(errors)).sorted().joined(separator: " ")
        }
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
