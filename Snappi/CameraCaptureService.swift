import Foundation
import AVFoundation
import UIKit
import CoreImage
import Combine

final class CameraCaptureService: NSObject, CameraCapturing, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    @MainActor var onUpdate: ((CameraUpdate) -> Void)?
    @MainActor var onCapture: ((CapturedMedia) -> Void)?
    private let permissions: any CameraPermissions
    // Queue confinement: session/input/capture state on queue; frame timing on frames;
    // effect options under lock; callbacks are delivered only on the main actor.
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "snappi.capture")
    private let frames = DispatchQueue(label: "snappi.preview", qos: .userInitiated)
    private let photo = AVCapturePhotoOutput()
    private let movie = AVCaptureMovieFileOutput()
    private let video = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var activity = CameraSessionActivity()
    private var requestingCameraAccess = false
    private var meteringRequest: UUID?
    private var meteringObservers: [NSKeyValueObservation] = []
    private var capturing = false
    private var stopVideoOnStart = false
    private var pendingVideoStart: UUID?
    private var options = LookSettings()
    private var shotOptions = LookSettings()
    private var keepOriginal = false
    private var shotKeepOriginal = false
    private var autoExport = true
    private var shotAutoExport = true
    private let lock = NSLock()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var lastFrame = CFAbsoluteTimeGetCurrent()
    private var lastLookPreview: CFAbsoluteTime = 0
    private var front = false
    private var observers: [NSObjectProtocol] = []
    init(permissions: any CameraPermissions) {
        self.permissions = permissions
        super.init()
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: nil) { [weak self] _ in
            self?.publish { $0.ready = false; $0.status = "Camera interrupted. Return to Snappi to continue." }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionDidStartRunning, object: session, queue: nil) { [weak self] _ in
            self?.reconcileSessionStart()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: nil) { [weak self] _ in
            self?.recoverAfterInterruption()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] _ in
            self?.publish { $0.ready = false; $0.status = "Camera unavailable"; $0.error = "The camera stopped. Close and reopen Snappi to reconnect." }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    private func publish(_ change: @escaping CameraUpdate) {
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(change) }
    }
    private func deliver(_ media: CapturedMedia) {
        DispatchQueue.main.async { [weak self] in self?.onCapture?(media) }
    }
    func finishCapture() { queue.async { self.capturing = false } }
    func update(settings: LookSettings, preserve: Bool, export: Bool) { lock.lock(); options = settings; keepOriginal = preserve; autoExport = export; lock.unlock() }
    private func snapshot() { lock.lock(); shotOptions = options; shotKeepOriginal = keepOriginal; shotAutoExport = autoExport; lock.unlock() }
    func start() { queue.async {
        self.activity.requested = true
        switch self.permissions.cameraStatus {
        case .authorized: self.configure()
        case .notDetermined:
            guard !self.requestingCameraAccess else { return }
            self.requestingCameraAccess = true
            Task {
                let granted = await self.permissions.requestCamera()
                self.queue.async {
                    self.requestingCameraAccess = false
                    guard self.activity.requested else { return }
                    if granted { self.configure() } else { self.showCameraAccessDenied() }
                }
            }
        default: self.showCameraAccessDenied()
        }
    } }
    private func showCameraAccessDenied() {
        publish { $0.denied = true; $0.ready = false; $0.status = "Camera access is off" }
    }
    private func configure() {
        publish { $0.denied = false }
        guard !configured else { resumeOnQueue(); return }
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        do {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw SnappiFailure.make("No camera is available on this device.") }
            let deviceInput = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(deviceInput) else { throw SnappiFailure.make("Could not connect the camera.") }
            session.addInput(deviceInput); input = deviceInput
            video.alwaysDiscardsLateVideoFrames = true
            video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            video.setSampleBufferDelegate(self, queue: frames)
            for output in [photo, movie, video] as [AVCaptureOutput] {
                guard session.canAddOutput(output) else { throw SnappiFailure.make("This device cannot run the required camera outputs.") }
                session.addOutput(output)
            }
            movie.maxRecordedDuration = CMTime(seconds: 60, preferredTimescale: 600)
            orientConnections()
            publishMeteringState(camera)
            session.commitConfiguration(); configured = true
            if activity.requested { session.startRunning() }
            let running = activity.requested && session.isRunning && !session.isInterrupted, hasFlash = camera.hasFlash
            publish { $0.ready = running; $0.status = "Ready to capture"; $0.flashAvailable = hasFlash }
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
    private func reconcileSessionStart() { queue.async { self.stopSessionIfIdle() } }
    private func recoverAfterInterruption() { queue.async {
        guard self.activity.requested else { self.stopSessionIfIdle(); return }
        guard self.configured, self.permissions.cameraStatus == .authorized else { return }
        self.resumeOnQueue()
    } }
    private func resumeOnQueue() {
        video.connection(with: .video)?.isEnabled = true
        if !session.isRunning && !session.isInterrupted { session.startRunning() }
        let running = session.isRunning && !session.isInterrupted, idle = !capturing
        publish { $0.ready = running; if idle && !$0.busy { $0.status = "Ready to capture" } }
    }
    func suspend() { queue.async {
        self.activity.requested = false
        if self.pendingVideoStart != nil {
            self.pendingVideoStart = nil; self.capturing = false
            self.publish { $0.busy = false; $0.status = "Recording cancelled" }
        }
        self.video.connection(with: .video)?.isEnabled = false
        self.stopVideoOnStart = true
        if self.movie.isRecording { self.movie.stopRecording() }
        self.torchOnQueue(false)
        self.stopSessionIfIdle()
        self.publish { $0.ready = false }
    } }
    private func stopSessionIfIdle() {
        // Shutting down the session mid-capture can interrupt delivery of the original.
        if activity.shouldStop(running: session.isRunning, interrupted: session.isInterrupted) {
            session.stopRunning()
        }
    }
    func switchCamera() { queue.async {
        guard !self.capturing, let old = self.input else { return }
        let position: AVCaptureDevice.Position = self.front ? .back : .front
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { return }
        do {
            let next = try AVCaptureDeviceInput(device: device)
            self.session.beginConfiguration(); self.session.removeInput(old)
            if self.session.canAddInput(next) {
                self.clearMeteringObservation()
                self.resetMetering(old.device)
                self.session.addInput(next); self.input = next; self.front.toggle(); self.orientConnections()
                self.publishMeteringState(device)
            } else { self.session.addInput(old) }
            self.session.commitConfiguration()
            let front = self.front, hasFlash = self.input?.device.hasFlash ?? false
            self.publish { $0.isFront = front; $0.flashAvailable = hasFlash }
        } catch { self.publish { $0.error = error.localizedDescription } }
    } }
    private func publishMeteringState(_ device: AVCaptureDevice) {
        let range = max(-2, Double(device.minExposureTargetBias))...min(2, Double(device.maxExposureTargetBias))
        let bias = Double(device.exposureTargetBias)
        publish { $0.exposureRange = range; $0.exposureBias = bias; $0.focusSelection = nil }
    }
    private func resetMetering(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let center = CGPoint(x: 0.5, y: 0.5)
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = center }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = center }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.setExposureTargetBias(0)
        } catch { publish { $0.error = error.localizedDescription } }
    }
    func focus(at point: CGPoint, bufferSize: CGSize, front: Bool, lock: Bool) { queue.async {
        guard self.activity.requested, self.session.isRunning, !self.capturing, self.front == front,
              let device = self.input?.device else { return }
        // This conversion uses the data output's actual rotation, mirroring and scaling.
        let pixel = CGRect(x: point.x * (bufferSize.width - 1), y: point.y * (bufferSize.height - 1), width: 1, height: 1)
        let rect = self.video.metadataOutputRectConverted(fromOutputRect: pixel)
        guard !rect.isEmpty, rect.midX.isFinite, rect.midY.isFinite else { return }
        let target = CGPoint(x: min(max(rect.midX, 0), 1), y: min(max(rect.midY, 0), 1))
        let focusMode: AVCaptureDevice.FocusMode = lock ? .autoFocus : .continuousAutoFocus
        let exposureMode: AVCaptureDevice.ExposureMode = lock ? .autoExpose : .continuousAutoExposure
        let focus = device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode)
        let exposure = device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode)
        guard focus || exposure else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if focus { device.focusPointOfInterest = target; device.focusMode = focusMode }
            if exposure { device.exposurePointOfInterest = target; device.exposureMode = exposureMode }
            self.observeMetering(at: point, device: device, focus: lock && focus, exposure: lock && exposure)
        } catch { self.publish { $0.error = error.localizedDescription } }
    } }
    private func clearMeteringObservation() {
        meteringRequest = nil
        meteringObservers.removeAll()
    }
    private func observeMetering(at point: CGPoint, device: AVCaptureDevice, focus: Bool, exposure: Bool) {
        clearMeteringObservation()
        let request = UUID()
        meteringRequest = request
        let update: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard self.meteringRequest == request, let device = self.input?.device else { return }
                let selection = FocusSelection(id: request, point: point,
                    focus: .init(requested: focus, adjusting: device.focusMode == .autoFocus, locked: device.focusMode == .locked),
                    exposure: .init(requested: exposure, adjusting: device.exposureMode == .autoExpose, locked: device.exposureMode == .locked))
                self.publish { $0.focusSelection = selection }
            }
        }
        if focus { meteringObservers.append(device.observe(\.focusMode, options: [.new]) { _, _ in update() }) }
        if exposure { meteringObservers.append(device.observe(\.exposureMode, options: [.new]) { _, _ in update() }) }
        update()
    }
    func exposure(_ value: Float) { queue.async {
        guard let device = self.input?.device else { return }
        do { try device.lockForConfiguration(); device.setExposureTargetBias(min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias)); device.unlockForConfiguration() }
        catch {
            let actual = Double(device.exposureTargetBias)
            self.publish { $0.exposureBias = actual; $0.error = error.localizedDescription }
        }
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
        guard self.activity.requested, self.configured, self.session.isRunning, !self.session.isInterrupted, !self.capturing else {
            if !self.capturing { self.publish { $0.busy = false; $0.status = "Camera unavailable" } }
            return
        }
        self.capturing = true; self.snapshot()
        self.publish { $0.busy = true; $0.status = "Developing your photo…" }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        if self.photo.supportedFlashModes.contains(flash ? .on : .off) { settings.flashMode = flash ? .on : .off }
        self.activity.awaitingCapture = true
        self.photo.capturePhoto(with: settings, delegate: self)
    } }
    func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        publish { $0.photoCaptured += 1 }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let capturedData = photo.fileDataRepresentation()
        queue.async {
            self.activity.awaitingCapture = false
            self.stopSessionIfIdle()
            let settings = self.shotOptions, preserve = self.shotKeepOriginal, export = self.shotAutoExport
            if let error { self.finishFailure(error); return }
            guard let data = capturedData else { self.finishFailure(SnappiFailure.make("No photo data was returned.")); return }
            self.deliver(.photo(data, CaptureOptions(settings: settings, preserveOriginal: preserve, exportToPhotos: export)))
        }
    }
    func startVideo(to destination: URL) {
        queue.async {
            guard self.activity.requested, self.configured, self.session.isRunning, !self.session.isInterrupted, !self.capturing else {
                if !self.capturing { self.publish { $0.busy = false; $0.status = "Camera unavailable" } }
                return
            }
            self.capturing = true; self.snapshot()
            let request = UUID()
            self.pendingVideoStart = request
            self.publish { $0.busy = true; $0.status = "Preparing recording…" }
            Task {
                let mic = await self.permissions.requestMicrophone()
                self.queue.async {
                    guard self.pendingVideoStart == request else { return }
                    self.pendingVideoStart = nil
                    guard self.activity.requested, self.session.isRunning, !self.session.isInterrupted else {
                        self.capturing = false
                        self.publish { $0.busy = false; $0.status = "Recording cancelled" }
                        return
                    }
                    if mic && !self.session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }), let device = AVCaptureDevice.default(for: .audio), let audio = try? AVCaptureDeviceInput(device: device) {
                        self.session.beginConfiguration()
                        if self.session.canAddInput(audio) { self.session.addInput(audio) }
                        self.session.commitConfiguration()
                    }
                    let hasAudio = self.session.inputs.contains { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }
                    self.publish { $0.audioEnabled = hasAudio; $0.status = hasAudio ? "Starting recording…" : "Starting silent recording…" }
                    self.activity.awaitingCapture = true
                    self.stopVideoOnStart = false
                    self.movie.startRecording(to: destination, recordingDelegate: self)
                }
            }
        }
    }
    func stopVideo() { queue.async { if self.movie.isRecording { self.movie.stopRecording() } } }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async {
            guard !self.stopVideoOnStart else {
                if self.movie.isRecording { self.movie.stopRecording() }
                return
            }
            self.publish { $0.recording = true; $0.recordingStarted = Date(); $0.status = $0.audioEnabled ? "Recording · 60s maximum" : "Recording without audio · 60s maximum" }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo source: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            self.activity.awaitingCapture = false
            self.stopSessionIfIdle()
            self.torchOnQueue(false)
            self.publish { $0.recording = false; $0.recordingStarted = nil; $0.status = "Developing your film… Keep Snappi open." }
            if let error = error as NSError?, error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
                self.finishFailure(error); return
            }
            let settings = self.shotOptions, preserve = self.shotKeepOriginal, export = self.shotAutoExport
            self.deliver(.video(source, CaptureOptions(settings: settings, preserveOriginal: preserve, exportToPhotos: export)))
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
        let bufferSize = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let front = connection.inputPorts.first?.sourceDevicePosition == .front
        publish {
            $0.preview = UIImage(cgImage: image)
            $0.previewBufferSize = bufferSize
            $0.previewIsFront = front
        }
        // Use the unfiltered frame so previews do not apply the active look twice.
        if now - lastLookPreview > 2 {
            lastLookPreview = now
            let size = 128 / frame.extent.width
            let sample = frame.transformed(by: CGAffineTransform(scaleX: size, y: size))
            var previews: [FilmLook: UIImage] = [:]
            for look in FilmLook.allCases {
                var option = settings; option.look = look
                let result = Effects.apply(sample, settings: option)
                if let cg = context.createCGImage(result, from: result.extent) { previews[look] = UIImage(cgImage: cg) }
            }
            let completed = previews
            publish { $0.lookPreviews = completed }
        }
    }
}
