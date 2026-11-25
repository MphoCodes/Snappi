import Foundation
import UIKit

struct FocusSelection: Equatable, Sendable {
    let point: CGPoint
    let focusLocked: Bool
    let exposureLocked: Bool
    let id = UUID()

    var lockLabel: String? {
        switch (focusLocked, exposureLocked) {
        case (true, true): return "AE/AF Lock"
        case (true, false): return "Focus Lock"
        case (false, true): return "Exposure Lock"
        default: return nil
        }
    }
}

struct CameraState {
    var preview: UIImage?
    var lookPreviews: [FilmLook: UIImage] = [:]
    var previewBufferSize = CGSize.zero
    var previewIsFront = false
    var focusSelection: FocusSelection?
    var exposureBias = 0.0
    var exposureRange = -2.0...2.0
    var photoCaptured = 0
    var ready = false
    var denied = false
    var busy = false
    var recording = false
    var status = "Getting the camera ready…"
    var error: String?
    var latest: URL?
    var audioEnabled = false
    var isFront = false
    var flashAvailable = false
    var recordingStarted: Date?
}

struct CaptureOptions: Sendable {
    var settings = LookSettings()
    var preserveOriginal = false
    var exportToPhotos = true
}
enum CapturedMedia: Sendable {
    case photo(Data, CaptureOptions)
    case video(URL, CaptureOptions)
}

typealias CameraUpdate = @Sendable (inout CameraState) -> Void
