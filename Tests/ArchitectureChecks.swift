import Foundation
import UIKit

// This fake is driven only by the main-actor test harness.
final class FakeCamera: CameraCapturing, @unchecked Sendable {
    @MainActor var onUpdate: ((CameraUpdate) -> Void)?
    @MainActor var onCapture: ((CapturedMedia) -> Void)?
    var captures = 0
    var releases = 0
    var videoStarts = 0
    func update(settings: LookSettings, preserve: Bool, export: Bool) {}
    var starts = 0
    var suspensions = 0
    func start() { starts += 1 }
    func suspend() { suspensions += 1 }
    func switchCamera() {}
    var lastFocus: (point: CGPoint, size: CGSize, front: Bool, lock: Bool)?
    var lastExposure: Float?
    func focus(at point: CGPoint, bufferSize: CGSize, front: Bool, lock: Bool) { lastFocus = (point, bufferSize, front, lock) }
    func exposure(_ value: Float) { lastExposure = value }
    func zoom(_ value: Double) {}
    func torch(_ enabled: Bool) {}
    func capturePhoto(flash: Bool) { captures += 1 }
    func startVideo(to destination: URL) { videoStarts += 1 }
    func stopVideo() {}
    func finishCapture() { releases += 1 }
}
struct DeniedExporter: PhotoLibraryExporting {
    func saveToPhotos(_ url: URL) async throws { throw SnappiFailure.make("Photos denied") }
}
struct UnusedExporter: PhotoLibraryExporting {
    func saveToPhotos(_ url: URL) async throws { fatalError("Export must be skipped") }
}
struct FailingProcessedWrite: MediaRepository {
    var directory: URL { base.directory }
    let base: LocalMediaRepository
    var blockedRemoval: URL?
    func items() -> [CaptureItem] { base.items() }
    func newURL(extension ext: String, original: Bool) -> URL { base.newURL(extension: ext, original: original) }
    func write(_ data: Data, to url: URL) throws {
        if url.lastPathComponent.hasPrefix("snappi-") { throw SnappiFailure.make("Disk full") }
        try base.write(data, to: url)
    }
    func remove(_ url: URL) throws {
        if url.path == blockedRemoval?.path { throw SnappiFailure.make("File is busy") }
        try base.remove(url)
    }
    func thumbnail(_ item: CaptureItem, maxPixelSize: Int) async -> UIImage? { await base.thumbnail(item, maxPixelSize: maxPixelSize) }
}
@main struct ArchitectureChecks {
    @MainActor static func checkStorageCleanup(in folder: URL) throws {
        let base = LocalMediaRepository(directory: folder)
        let live = CaptureItem(url: folder.appendingPathComponent("live.jpg"))
        let movie = CaptureItem(url: folder.appendingPathComponent("movie.mov"))
        let blocked = CaptureItem(url: folder.appendingPathComponent("busy.jpg"))
        let unselected = CaptureItem(url: folder.appendingPathComponent("unselected.jpg"))
        for item in [live, movie, blocked, unselected] {
            try base.write(Data(repeating: 0x7b, count: 32_768), to: item.url)
        }
        let exportedCopy = folder.appendingPathComponent("separate-export")
        try FileManager.default.copyItem(at: movie.url, to: exportedCopy)
        let blockedURL = base.deletedDirectory.appendingPathComponent(blocked.id)
        let gallery = GalleryViewModel(repository: FailingProcessedWrite(base: base, blockedRemoval: blockedURL), exporter: UnusedExporter())
        gallery.reload()
        precondition(gallery.deletedBytes == 0)
        gallery.toggleFavorites([live.id, movie.id, blocked.id, unselected.id])
        gallery.relocate([movie, blocked, unselected], restoring: false)
        let unrelated = base.deletedDirectory.appendingPathComponent("notes.txt")
        try Data([0]).write(to: unrelated)
        let folderNamedLikeCapture = base.deletedDirectory.appendingPathComponent("folder.jpg", isDirectory: true)
        try FileManager.default.createDirectory(at: folderNamedLikeCapture, withIntermediateDirectories: false)
        let linkedCapture = base.deletedDirectory.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: linkedCapture, withDestinationURL: live.url)
        gallery.reload()
        let initialBytes = gallery.deletedBytes!
        let movieBytes = gallery.deleted.first { $0.id == movie.id }!.allocatedBytes!
        precondition(initialBytes > 0 && movieBytes > 0 && gallery.deleted.count == 3)
        gallery.permanentlyDelete([blocked.id, movie.id])
        precondition(gallery.message?.contains("Deleted 1 of 2") == true)
        precondition(gallery.deletedBytes == initialBytes - movieBytes)
        precondition(Set(gallery.deleted.map(\.id)) == [blocked.id, unselected.id])
        let expectedFavorites: Set<String> = [live.id, blocked.id, unselected.id]
        precondition(gallery.favorites == expectedFavorites)
        let reopened = GalleryViewModel(repository: base, exporter: UnusedExporter())
        reopened.reload()
        precondition(reopened.favorites == expectedFavorites)
        for url in [live.url, unrelated, folderNamedLikeCapture, linkedCapture] {
            do {
                try base.permanentlyDelete(CaptureItem(url: url))
                fatalError("Unexpected permanent deletion of \(url.lastPathComponent)")
            } catch { precondition(FileManager.default.fileExists(atPath: url.path)) }
        }
        // A replacement directory or symlink must never turn a confirmed file deletion into a recursive one.
        let redirected = LocalMediaRepository(directory: folder.appendingPathComponent("redirected"))
        try FileManager.default.createDirectory(at: redirected.directory, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: redirected.deletedDirectory, withDestinationURL: folder)
        do {
            try redirected.permanentlyDelete(CaptureItem(url: redirected.deletedDirectory.appendingPathComponent(live.id)))
            fatalError("Deleted through a redirected trash folder")
        } catch { precondition(FileManager.default.fileExists(atPath: live.url.path)) }
        reopened.relocate(reopened.deleted.filter { $0.id == unselected.id }, restoring: true)
        reopened.permanentlyDelete([blocked.id])
        precondition(reopened.deleted.isEmpty && reopened.deletedBytes == 0)
        precondition(reopened.favorites == [live.id, unselected.id])
        let preservedExport = try Data(contentsOf: exportedCopy)
        precondition(preservedExport == Data(repeating: 0x7b, count: 32_768))
        print("Recently Deleted storage, selected deletion, partial failure and favorite persistence checks passed")
    }
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await checkHalfFrames(in: folder)
        let repository = LocalMediaRepository(directory: folder)
        let processor = MediaProcessor(repository: repository)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 48), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
        }.jpegData(compressionQuality: 0.9)!
        let camera = FakeCamera()
        let vm = CameraViewModel(capture: camera, processor: processor, repository: repository, exporter: DeniedExporter())
        vm.updateActivity(scene: .inactive, galleryPresented: false)
        precondition(camera.starts == 0)
        vm.updateActivity(scene: .active, galleryPresented: false)
        vm.updateActivity(scene: .inactive, galleryPresented: false) // System permission sheet
        vm.updateActivity(scene: .active, galleryPresented: false)
        precondition(camera.starts == 1 && camera.suspensions == 0)
        vm.updateActivity(scene: .active, galleryPresented: true)
        camera.onUpdate? { $0.ready = true } // A queued update from before the gallery opened
        precondition(!vm.ready)
        vm.updateActivity(scene: .background, galleryPresented: true)
        vm.updateActivity(scene: .active, galleryPresented: true)
        precondition(camera.starts == 1 && camera.suspensions == 1)
        vm.updateActivity(scene: .background, galleryPresented: false)
        vm.updateActivity(scene: .inactive, galleryPresented: false)
        precondition(camera.starts == 1, "Dismissing the gallery offscreen must not start the camera")
        vm.updateActivity(scene: .active, galleryPresented: false)
        vm.updateActivity(scene: .active, galleryPresented: true)
        vm.updateActivity(scene: .active, galleryPresented: false)
        precondition(camera.starts == 3 && camera.suspensions == 2)
        camera.onUpdate? { $0.ready = true }
        func lockLabel(focus: MeteringLock, exposure: MeteringLock) -> String? {
            FocusSelection(id: UUID(), point: .zero, focus: focus, exposure: exposure).lockLabel
        }
        precondition(lockLabel(focus: .adjusting, exposure: .locked) == "Metering…")
        precondition(lockLabel(focus: .locked, exposure: .adjusting) == "Metering…")
        precondition(lockLabel(focus: .locked, exposure: .locked) == "AE/AF Lock")
        precondition(lockLabel(focus: .unrequested, exposure: .locked) == "Exposure Lock")
        precondition(lockLabel(focus: .locked, exposure: .unrequested) == "Focus Lock")
        precondition(lockLabel(focus: .unrequested, exposure: .unrequested) == nil)
        print("Gallery, permission-sheet, foreground transitions and metering label checks passed")
        let geometry = PreviewGeometry(image: CGSize(width: 1080, height: 1920), view: CGSize(width: 400, height: 400))
        precondition(geometry.unitPoint(CGPoint(x: 30, y: 200)) == nil)
        let point = geometry.unitPoint(CGPoint(x: 143.75, y: 300))!
        precondition(point == CGPoint(x: 0.25, y: 0.75))
        precondition(ViewfinderDrag.direction(CGPoint(x: 50, y: 10)) == .look)
        precondition(ViewfinderDrag.direction(CGPoint(x: 5, y: -50)) == .exposure)
        precondition(ViewfinderDrag.direction(CGPoint(x: 26, y: 25)) == nil)
        camera.onUpdate? { $0.previewBufferSize = CGSize(width: 1080, height: 1920); $0.isFront = true }
        vm.focus(at: point, lock: true)
        precondition(camera.lastFocus == nil, "Reject stale back-camera frames after a flip")
        camera.onUpdate? { $0.previewIsFront = true; $0.exposureRange = -1...1 }
        vm.focus(at: point, lock: true)
        precondition(camera.lastFocus?.point == point && camera.lastFocus?.front == true && camera.lastFocus?.lock == true)
        precondition(camera.lastFocus?.size == CGSize(width: 1080, height: 1920))
        vm.focus(at: point, lock: false)
        precondition(camera.lastFocus?.lock == false)
        vm.exposure(3)
        precondition(camera.lastExposure == 1 && vm.exposureBias == 1)
        print("Viewfinder letterbox, gesture direction, camera flip, lock request and exposure range checks passed")
        vm.shutter(video: true, flash: false, delay: 0)
        precondition(vm.busy, "Reserve workflow before microphone authorization/hardware callback")
        vm.shutter(video: false, flash: false, delay: 0)
        await Task.yield()
        precondition(camera.captures == 0 && camera.videoStarts == 1, "Pending video must block another capture")
        camera.onUpdate? { $0.busy = false }
        vm.shutter(video: false, flash: false, delay: 3)
        precondition(vm.countdown == 3 && vm.busy && !vm.showsProcessingOverlay)
        vm.updateActivity(scene: .background, galleryPresented: false)
        try await Task.sleep(for: .milliseconds(30))
        precondition(camera.captures == 0 && vm.countdown == 0, "Backgrounding must cancel countdown")
        vm.updateActivity(scene: .active, galleryPresented: false)
        camera.onUpdate? { $0.ready = true }
        vm.shutter(video: false, flash: false, delay: 0)
        await Task.yield()
        precondition(camera.captures == 1 && vm.showsProcessingOverlay)
        vm.updateActivity(scene: .background, galleryPresented: false)
        precondition(vm.busy && !vm.ready, "Keep the capture reservation until its delegate delivers")
        camera.onCapture?(.photo(data, CaptureOptions(settings: LookSettings(), preserveOriginal: true, exportToPhotos: true)))
        await vm.waitForProcessing()
        precondition(vm.latest != nil && !vm.busy && vm.error == "Photos denied", "Denied export must leave the local capture available")
        precondition(repository.items().count == 2, "Original and rendered photo must remain")
        precondition(camera.releases == 1, "Capture must unlock even if Photos rejects export")
        let originalCount = repository.items().count
        camera.onUpdate? { $0.busy = true }
        camera.onCapture?(.photo(Data([0, 1, 2]), CaptureOptions()))
        await vm.waitForProcessing()
        precondition(!vm.busy && vm.error != nil && camera.releases == 2, "Processing failure must unlock and surface an error")
        precondition(repository.items().count == originalCount, "Failure must not remove existing media")
        let url = try await processor.processPhoto(data, settings: LookSettings(), preserveOriginal: false)
        precondition(FileManager.default.fileExists(atPath: url.path), "Processed file must exist")
        precondition(repository.items().count == originalCount + 1, "Discard only the successful capture's original")
        let failureStore = LocalMediaRepository(directory: folder.appendingPathComponent("failure"))
        let failureProcessor = MediaProcessor(repository: FailingProcessedWrite(base: failureStore))
        do {
            _ = try await failureProcessor.processPhoto(data, settings: LookSettings(), preserveOriginal: false)
            fatalError("Expected processed write to fail")
        } catch {
            precondition(failureStore.items().count == 1 && failureStore.items()[0].isOriginal,
                         "A failed final write must retain the original even when keep-originals is off")
            let preserved = try Data(contentsOf: failureStore.items()[0].url)
            precondition(preserved == data)
        }
        let beforeQueue = repository.items().count, beforeReleases = camera.releases
        let recoveryCamera = FakeCamera()
        let recoveryModel = CameraViewModel(capture: recoveryCamera, processor: failureProcessor,
                                            repository: failureStore, exporter: UnusedExporter())
        let inputPNG = UIImage(data: data)!.pngData()!
        recoveryCamera.onCapture?(.photo(inputPNG, CaptureOptions(settings: LookSettings(), preserveOriginal: false, exportToPhotos: false)))
        await recoveryModel.waitForProcessing()
        guard let recovered = recoveryModel.latest else { fatalError("Publish the retained original to refresh the camera roll") }
        precondition(recovered.pathExtension == "png" && recoveryModel.error?.contains("Your Roll") == true)
        let recoveredData = try Data(contentsOf: recovered)
        precondition(recoveredData == inputPNG)
        await recoveryModel.refreshRoll()
        precondition(recoveryModel.rollCount == 2 && recoveryModel.latestThumbnail != nil)
        camera.onCapture?(.photo(Data([0]), CaptureOptions()))
        camera.onCapture?(.photo(data, CaptureOptions(settings: LookSettings(), preserveOriginal: false, exportToPhotos: false)))
        await vm.waitForProcessing()
        precondition(repository.items().count == beforeQueue + 1 && !vm.busy,
                     "A failed delivery must not discard the following valid capture")
        precondition(camera.releases == beforeReleases + 1, "Release hardware only after the queued work drains")
        let gallery = GalleryViewModel(repository: repository, exporter: DeniedExporter())
        gallery.reload()
        let pair = Array(gallery.items.prefix(2))
        precondition(pair.count == 2)
        let ids = Set(pair.map(\.id))
        gallery.toggleFavorites(ids)
        gallery.relocate(pair, restoring: false)
        let reopened = GalleryViewModel(repository: repository, exporter: DeniedExporter())
        reopened.reload()
        precondition(Set(reopened.deleted.map(\.id)) == ids && reopened.captures(.favorites).isEmpty)
        reopened.relocate(reopened.deleted, restoring: true)
        precondition(reopened.deleted.isEmpty && Set(reopened.captures(.favorites).map(\.id)) == ids)
        reopened.toggleFavorites(ids)
        precondition(reopened.favorites.isEmpty)
        try checkStorageCleanup(in: folder.appendingPathComponent("cleanup"))
        print("Gallery favorite, batch delete, reopen and restore checks passed")
        print("Architecture checks passed: countdown cancellation, local save on export denial, capture unlock, file preservation")
    }
}
