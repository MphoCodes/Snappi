import Foundation
import UIKit

struct CameraState {
    var preview: UIImage?
    var lookPreviews: [FilmLook: UIImage] = [:]
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
