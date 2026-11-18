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
        capture.onCapture = { [weak self] media in self?.process(media) }
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
    func exposure(_ value: Float) { capture.exposure(value) }
    func zoom(_ value: Double) { capture.zoom(value) }
    func torch(_ enabled: Bool) { capture.torch(enabled) }
    func shutter(video: Bool, flash: Bool, delay: Int) {
        if state.recording { capture.stopVideo(); return }
        guard state.ready, !state.busy, countdownTask == nil else { return }
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
            if video { self.capture.startVideo(to: self.repository.newURL(extension: "mov", original: true)) }
            else { self.capture.capturePhoto(flash: flash) }
        }
    }
    func importSelection(_ item: PhotosPickerItem) async {
        guard !state.busy, countdownTask == nil else { return }
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
    private func process(_ media: CapturedMedia) {
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
                switch media {
                case let .photo(data, options):
                    export = options.exportToPhotos
                    url = try await processor.processPhoto(data, settings: options.settings, preserveOriginal: options.preserveOriginal)
                case let .video(source, options):
                    export = options.exportToPhotos
                    url = try await processor.processVideo(source, settings: options.settings, preserveOriginal: options.preserveOriginal)
                }
                state.latest = url
                state.status = "Saved in Snappi"
                if export {
                    do { try await exporter.saveToPhotos(url); state.status = "Saved in Snappi + Photos" }
                    catch { state.error = error.localizedDescription }
                }
            } catch { fail(error) }
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
