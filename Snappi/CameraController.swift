import Foundation
import AVFoundation
import UIKit
import CoreImage
import Combine

final class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    @Published var preview: UIImage?
    @Published var ready = false
    @Published var denied = false
    @Published var busy = false
    @Published var recording = false
    @Published var status = "Getting the camera ready…"
    @Published var error: String?
    @Published var latest: URL?
    @Published var audioEnabled = false
    @Published var isFront = false
    @Published var flashAvailable = false
    @Published var recordingStarted: Date?
    // Queue confinement: session/input/capture state on queue; frame timing on frames;
    // effect options under lock; all Published values are mutated on the main queue.
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "snappi.capture")
    private let frames = DispatchQueue(label: "snappi.preview", qos: .userInitiated)
    private let processing = DispatchQueue(label: "snappi.processing", qos: .userInitiated)
    private let photo = AVCapturePhotoOutput()
    private let movie = AVCaptureMovieFileOutput()
    private let video = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var active = true
    private var capturing = false
    private var options = LookSettings()
    private var shotOptions = LookSettings()
    private var keepOriginal = false
    private var shotKeepOriginal = false
    private var autoExport = true
    private var shotAutoExport = true
    private let lock = NSLock()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var lastFrame = CFAbsoluteTimeGetCurrent()
    private var front = false
    private var observers: [NSObjectProtocol] = []
    override init() {
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: nil) { [weak self] _ in
            self?.publish { $0.ready = false; $0.status = "Camera interrupted. Return to Snappi to continue." }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: nil) { [weak self] _ in self?.resume() })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] _ in
            self?.publish { $0.ready = false; $0.status = "Camera unavailable"; $0.error = "The camera stopped. Close and reopen Snappi to reconnect." }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    private func publish(_ change: @escaping (CameraController) -> Void) { DispatchQueue.main.async { [weak self] in if let self { change(self) } } }
    func update(settings: LookSettings, preserve: Bool, export: Bool) { lock.lock(); options = settings; keepOriginal = preserve; autoExport = export; lock.unlock() }
    private func snapshot() { lock.lock(); shotOptions = options; shotKeepOriginal = keepOriginal; shotAutoExport = autoExport; lock.unlock() }
    func start() {
        Task {
            let access = await AVCaptureDevice.requestAccess(for: .video)
            guard access else { publish { $0.denied = true; $0.status = "Camera access is off" }; return }
            queue.async { self.active = true; self.configure() }
        }
    }
    private func configure() {
        publish { $0.denied = false }
        guard !configured else { resumeOnQueue(); return }
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        do {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw MediaLibrary.failure("No camera is available on this device.") }
            let deviceInput = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(deviceInput) else { throw MediaLibrary.failure("Could not connect the camera.") }
            session.addInput(deviceInput); input = deviceInput
            video.alwaysDiscardsLateVideoFrames = true
            video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            video.setSampleBufferDelegate(self, queue: frames)
            for output in [photo, movie, video] as [AVCaptureOutput] {
                guard session.canAddOutput(output) else { throw MediaLibrary.failure("This device cannot run the required camera outputs.") }
                session.addOutput(output)
            }
            movie.maxRecordedDuration = CMTime(seconds: 60, preferredTimescale: 600)
            orientConnections()
            session.commitConfiguration(); configured = true
            if active { session.startRunning() }
            let running = active && session.isRunning
            publish { $0.ready = running; $0.status = "Ready to capture"; $0.flashAvailable = camera.hasFlash }
        } catch {
            session.inputs.forEach(session.removeInput); session.outputs.forEach(session.removeOutput)
            session.commitConfiguration(); publish { $0.error = error.localizedDescription; $0.status = "Camera unavailable" }
        }
    }
    private func orientConnections() {
        for output in [photo, movie, video] as [AVCaptureOutput] {
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = front }
            }
        }
    }
    func resume() { queue.async {
        self.active = true
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { self.configure() }
        else if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
            self.publish { $0.denied = true; $0.ready = false; $0.status = "Camera access is off" }
        }
    } }
    private func resumeOnQueue() {
        if active && !session.isRunning { session.startRunning() }
        let running = session.isRunning, idle = !capturing
        publish { $0.ready = running; if idle { $0.status = "Ready to capture" } }
    }
    func suspend() { queue.async {
        self.active = false
        if self.movie.isRecording { self.movie.stopRecording() }
        self.torchOnQueue(false)
        if self.session.isRunning { self.session.stopRunning() }
        self.publish { $0.ready = false }
    } }
    func switchCamera() { queue.async {
        guard !self.capturing, let old = self.input else { return }
        let position: AVCaptureDevice.Position = self.front ? .back : .front
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { return }
        do {
            let next = try AVCaptureDeviceInput(device: device)
            self.session.beginConfiguration(); self.session.removeInput(old)
            if self.session.canAddInput(next) {
                self.session.addInput(next); self.input = next; self.front.toggle(); self.orientConnections()
            } else { self.session.addInput(old) }
            self.session.commitConfiguration()
            let front = self.front, hasFlash = self.input?.device.hasFlash ?? false
            self.publish { $0.isFront = front; $0.flashAvailable = hasFlash }
        } catch { self.publish { $0.error = error.localizedDescription } }
    } }
    func exposure(_ value: Float) { queue.async {
        guard let device = self.input?.device else { return }
        do { try device.lockForConfiguration(); device.setExposureTargetBias(min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias)); device.unlockForConfiguration() }
        catch { self.publish { $0.error = error.localizedDescription } }
    } }
    func zoom(_ value: Double) { queue.async {
        guard let device = self.input?.device else { return }
        do { try device.lockForConfiguration(); device.videoZoomFactor = min(max(CGFloat(value), 1), min(device.maxAvailableVideoZoomFactor, 3)); device.unlockForConfiguration() }
        catch { self.publish { $0.error = error.localizedDescription } }
    } }
    func torch(_ enabled: Bool) { queue.async { self.torchOnQueue(enabled) } }
    private func torchOnQueue(_ enabled: Bool) {
        guard let device = input?.device, device.hasTorch else { return }
        do { try device.lockForConfiguration(); device.torchMode = enabled ? .on : .off; device.unlockForConfiguration() }
        catch { publish { $0.error = error.localizedDescription } }
    }
    func capturePhoto(flash: Bool) { queue.async {
        guard self.configured, self.session.isRunning, !self.capturing else { return }
        self.capturing = true; self.snapshot()
        self.publish { $0.busy = true; $0.status = "Developing your photo…" }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        if self.photo.supportedFlashModes.contains(flash ? .on : .off) { settings.flashMode = flash ? .on : .off }
        self.photo.capturePhoto(with: settings, delegate: self)
    } }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        queue.async {
            let settings = self.shotOptions, preserve = self.shotKeepOriginal, export = self.shotAutoExport
            if let error { self.finishFailure(error); return }
            guard let data = photo.fileDataRepresentation() else { self.finishFailure(MediaLibrary.failure("No photo data was returned.")); return }
            self.processing.async {
                do { let url = try MediaLibrary.processPhoto(data, settings: settings, preserveOriginal: preserve); self.complete(url, export: export) }
                catch { self.finishFailure(error) }
            }
        }
    }
    func startVideo() {
        Task {
            let mic = await AVCaptureDevice.requestAccess(for: .audio)
            queue.async {
                guard self.configured, self.session.isRunning, !self.capturing else { return }
                self.capturing = true; self.snapshot()
                if mic && !self.session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }), let device = AVCaptureDevice.default(for: .audio), let audio = try? AVCaptureDeviceInput(device: device) {
                    self.session.beginConfiguration()
                    if self.session.canAddInput(audio) { self.session.addInput(audio) }
                    self.session.commitConfiguration()
                }
                let hasAudio = self.session.inputs.contains { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }
                self.publish { $0.audioEnabled = hasAudio; $0.busy = true; $0.status = hasAudio ? "Starting recording…" : "Starting silent recording…" }
                self.movie.startRecording(to: MediaLibrary.newURL(extension: "mov", original: true), recordingDelegate: self)
            }
        }
    }
    func stopVideo() { queue.async { if self.movie.isRecording { self.movie.stopRecording() } } }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        publish { $0.recording = true; $0.recordingStarted = Date(); $0.status = $0.audioEnabled ? "Recording · 60s maximum" : "Recording without audio · 60s maximum" }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo source: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            self.torchOnQueue(false)
            self.publish { $0.recording = false; $0.recordingStarted = nil; $0.status = "Developing your film… Keep Snappi open." }
            if let error = error as NSError?, error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
                self.finishFailure(error); return
            }
            let settings = self.shotOptions, preserve = self.shotKeepOriginal, export = self.shotAutoExport
            let stamp = settings.dateStamp ? MediaLibrary.stamp(date: Date()) : nil
            Task {
                let destination = MediaLibrary.newURL(extension: "mov")
                do {
                    try await VideoRenderer.export(source: source, destination: destination, settings: settings, stamp: stamp)
                    if !preserve { try? FileManager.default.removeItem(at: source) }
                    self.complete(destination, export: export)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    self.finishFailure(MediaLibrary.failure("Video processing failed. The original remains in Snappi’s library. \(error.localizedDescription)"))
                }
            }
        }
    }
    func importPhoto(_ data: Data) {
        queue.async {
            guard !self.capturing else { return }; self.capturing = true; self.snapshot()
            let settings = self.shotOptions, preserve = self.shotKeepOriginal, export = self.shotAutoExport
            self.publish { $0.busy = true; $0.status = "Developing imported photo…" }
            self.processing.async {
                do { self.complete(try MediaLibrary.processPhoto(data, settings: settings, preserveOriginal: preserve), export: export) }
                catch { self.finishFailure(error) }
            }
        }
    }
    private func complete(_ url: URL, export: Bool) {
        publish { $0.latest = url; $0.status = "Saved in Snappi" }
        Task {
            var message: String?
            if export { do { try await MediaLibrary.saveToPhotos(url) } catch { message = error.localizedDescription } }
            let result = message
            queue.async { self.capturing = false }
            publish { $0.busy = false; $0.status = result == nil && export ? "Saved in Snappi + Photos" : "Saved in Snappi"; if let result { $0.error = result } }
        }
    }
    private func finishFailure(_ error: Error) {
        queue.async { self.capturing = false }
        publish { $0.busy = false; $0.recording = false; $0.recordingStarted = nil; $0.error = error.localizedDescription; $0.status = "Capture needs attention" }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrame > 1.0 / 15.0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        lock.lock(); let settings = options; lock.unlock()
        var frame = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, 720 / frame.extent.width)
        frame = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rendered = Effects.apply(frame, settings: settings)
        guard let image = context.createCGImage(rendered, from: rendered.extent) else { return }
        publish { $0.preview = UIImage(cgImage: image) }
    }
}
