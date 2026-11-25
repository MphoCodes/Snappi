import Foundation
import UIKit

enum MeteringLock: Sendable {
    case unrequested, adjusting, locked
    init(requested: Bool, adjusting: Bool, locked: Bool) {
        if requested && locked { self = .locked }
        else if requested && adjusting { self = .adjusting }
        else { self = .unrequested }
    }
}

struct FocusSelection: Equatable, Sendable {
    let id: UUID
    let point: CGPoint
    let focus: MeteringLock
    let exposure: MeteringLock

    var isAdjusting: Bool { focus == .adjusting || exposure == .adjusting }
    var lockLabel: String? {
        if isAdjusting { return "Metering…" }
        switch (focus, exposure) {
        case (.locked, .locked): return "AE/AF Lock"
        case (.locked, _): return "Focus Lock"
        case (_, .locked): return "Exposure Lock"
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
