import Foundation
import UIKit
import Combine
import PhotosUI
import SwiftUI

@MainActor
@dynamicMemberLookup
final class CameraViewModel: ObservableObject {
    @Published private(set) var state = CameraState()
    @Published private(set) var countdown = 0
    @Published private(set) var rollCount = 0
    @Published private(set) var latestThumbnail: UIImage?
    @Published private(set) var firstHalfFrame: HalfFrame?
    private var capturingHalfFrame = false
    private let capture: any CameraCapturing
    private let processor: any MediaProcessing
    private let repository: any MediaRepository
    private let exporter: any PhotoLibraryExporting
    private var options = CaptureOptions()
    private var countdownTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var processingID: UUID?
    private var countdownID: UUID?

    init(capture: any CameraCapturing, processor: any MediaProcessing,
         repository: any MediaRepository, exporter: any PhotoLibraryExporting) {
        self.capture = capture; self.processor = processor
        self.repository = repository; self.exporter = exporter
        capture.onUpdate = { [weak self] update in
            guard let self else { return }
            update(&self.state)
        }
        capture.onCapture = { [weak self] media in
            guard let self else { return }
            let pair = self.capturingHalfFrame
            self.capturingHalfFrame = false
            self.process(media, pair: pair)
        }
    }
    subscript<Value>(dynamicMember keyPath: WritableKeyPath<CameraState, Value>) -> Value {
        get { state[keyPath: keyPath] }
        set { state[keyPath: keyPath] = newValue }
    }
    func update(settings: LookSettings, preserve: Bool, export: Bool) {
        options = CaptureOptions(settings: settings, preserveOriginal: preserve, exportToPhotos: export)
        capture.update(settings: settings, preserve: preserve, export: export)
    }
    func start() { capture.start() }
    func resume() { capture.resume() }
    func suspend() {
        if countdownTask != nil { state.busy = false }
        countdownTask?.cancel(); countdownTask = nil; countdownID = nil; countdown = 0
        capture.suspend()
    }
    func switchCamera() { capture.switchCamera() }
    func focus(at point: CGPoint, lock: Bool) {
        guard state.ready, !state.busy, state.previewIsFront == state.isFront,
              state.previewBufferSize.width > 0, state.previewBufferSize.height > 0 else { return }
        capture.focus(at: point, bufferSize: state.previewBufferSize, front: state.isFront, lock: lock)
    }
    func exposure(_ value: Double) {
        guard state.ready, !state.busy else { return }
        let range = state.exposureRange
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        guard clamped != state.exposureBias else { return }
        state.exposureBias = clamped
        capture.exposure(Float(clamped))
    }
    func zoom(_ value: Double) { capture.zoom(value) }
    func torch(_ enabled: Bool) { capture.torch(enabled) }
    func shutter(video: Bool, flash: Bool, delay: Int, pair: Bool = false) {
        if state.recording { capture.stopVideo(); return }
        guard state.ready, !state.busy, countdownTask == nil, firstHalfFrame == nil || pair else { return }
        state.busy = true
        let request = UUID()
        countdownID = request
        countdownTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.countdownID == request { self.countdownTask = nil; self.countdownID = nil; self.countdown = 0 }
            }
            if delay > 0 {
                for value in stride(from: delay, through: 1, by: -1) {
                    guard !Task.isCancelled else { return }
                    self.countdown = value
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            guard !Task.isCancelled else { return }
            self.capturingHalfFrame = pair && !video
            if video { self.capture.startVideo(to: self.repository.newURL(extension: "mov", original: true)) }
            else { self.capture.capturePhoto(flash: flash) }
        }
    }
    func cancelPair() async {
        guard !state.busy, let frame = firstHalfFrame else { return }
        do {
            if !frame.options.preserveOriginal { try repository.remove(frame.original) }
            firstHalfFrame = nil
            state.status = "Pair cancelled"
            await refreshRoll()
        } catch { fail(error) }
    }
    func importSelection(_ item: PhotosPickerItem) async {
        guard !state.busy, countdownTask == nil, firstHalfFrame == nil else { return }
        let selectedOptions = options
        state.busy = true
        state.status = "Developing imported photo…"
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw SnappiFailure.make("The selected photo could not be imported.")
            }
            process(.photo(data, selectedOptions))
        } catch { state.busy = false; fail(error) }
    }
    private func process(_ media: CapturedMedia, pair: Bool = false) {
        let preceding = processingTask
        let request = UUID()
        processingID = request
        processingTask = Task {
            await preceding?.value
            state.busy = true
            defer {
                if processingID == request {
                    capture.finishCapture(); state.busy = false; processingTask = nil; processingID = nil
                }
            }
            do {
                let url: URL, export: Bool
                var disposableOriginals: [URL] = []
                switch media {
                case let .photo(data, options) where pair:
                    guard let first = firstHalfFrame else {
                        firstHalfFrame = try await processor.beginPair(data, options: options)
                        state.status = "First frame ready. Take the second photo."
                        return
                    }
                    let result = try await processor.finishPair(first, second: data, options: options)
                    firstHalfFrame = nil
                    url = result.image
                    disposableOriginals = result.disposableOriginals
                    export = options.exportToPhotos
                case let .photo(data, options):
                    export = options.exportToPhotos
                    url = try await processor.processPhoto(data, settings: options.settings, preserveOriginal: options.preserveOriginal)
                case let .video(source, options):
                    export = options.exportToPhotos
                    url = try await processor.processVideo(source, settings: options.settings, preserveOriginal: options.preserveOriginal)
                }
                // For pairs, publish the new roll item after its temporary originals are settled.
                if disposableOriginals.isEmpty { state.latest = url }
                defer { if !disposableOriginals.isEmpty { state.latest = url } }
                state.status = "Saved in Snappi"
                if export {
                    do { try await exporter.saveToPhotos(url); state.status = "Saved in Snappi + Photos" }
                    catch { state.error = error.localizedDescription; return }
                }
                for original in disposableOriginals { try? repository.remove(original) }
            } catch let error as RetainedPhotoError {
                state.latest = error.original
                fail(error)
            } catch {
                fail(error)
                if pair { await refreshRoll() }
            }
        }
    }
    private func fail(_ error: Error) {
        state.recording = false; state.recordingStarted = nil
        state.error = error.localizedDescription; state.status = "Capture needs attention"
    }
    func refreshRoll() async {
        let items = repository.items()
        rollCount = items.count
        guard let item = items.first(where: { $0.url == state.latest }) ?? items.first else {
            latestThumbnail = nil
            return
        }
        let image = await repository.thumbnail(item)
        guard !Task.isCancelled else { return }
        latestThumbnail = image
    }
    func waitForProcessing() async { await processingTask?.value }
}
