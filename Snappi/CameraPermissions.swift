import AVFoundation

protocol CameraPermissions: Sendable {
    var cameraStatus: AVAuthorizationStatus { get }
    func requestCamera() async -> Bool
    func requestMicrophone() async -> Bool
}
struct SystemCameraPermissions: CameraPermissions {
    var cameraStatus: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
    func requestCamera() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
    func requestMicrophone() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }
}
