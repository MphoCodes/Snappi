import Foundation

/// The composition root is the only place that chooses concrete service implementations.
@MainActor
struct AppServices {
    let repository: any MediaRepository
    let processor: any MediaProcessing
    let exporter: any PhotoLibraryExporting
    let permissions: any CameraPermissions
    static func live() -> AppServices {
        let repository = LocalMediaRepository()
        return AppServices(repository: repository, processor: MediaProcessor(repository: repository),
                           exporter: PhotoLibraryExporter(), permissions: SystemCameraPermissions())
    }
    func cameraViewModel() -> CameraViewModel {
        CameraViewModel(capture: CameraCaptureService(permissions: permissions), processor: processor,
                        repository: repository, exporter: exporter)
    }
    func galleryViewModel() -> GalleryViewModel {
        GalleryViewModel(repository: repository, exporter: exporter)
    }
}
