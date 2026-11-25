import Foundation

protocol CameraCapturing: AnyObject, Sendable {
    @MainActor var onUpdate: ((CameraUpdate) -> Void)? { get set }
    @MainActor var onCapture: ((CapturedMedia) -> Void)? { get set }
    func update(settings: LookSettings, preserve: Bool, export: Bool)
    func start()
    func suspend()
    func switchCamera()
    func focus(at point: CGPoint, bufferSize: CGSize, front: Bool, lock: Bool)
    func exposure(_ value: Float)
    func zoom(_ value: Double)
    func torch(_ enabled: Bool)
    func capturePhoto(flash: Bool)
    func startVideo(to destination: URL)
    func stopVideo()
    func finishCapture()
}

struct CameraSessionActivity {
    var requested = false
    var awaitingCapture = false

    func shouldStop(running: Bool, interrupted: Bool) -> Bool {
        // AVFoundation can restart an interrupted session even when it currently reports stopped.
        !requested && !awaitingCapture && (running || interrupted)
    }
}
