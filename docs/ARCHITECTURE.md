# Architecture

Snappi uses main-actor screen view models with injected service protocols. `AppServices` is the composition root; it chooses the live implementations and constructs view models. Views do not instantiate capture hardware or perform media persistence/export workflows.

```mermaid
flowchart TD
    Root[AppServices] --> CameraVM[CameraViewModel · MainActor]
    Root --> GalleryVM[GalleryViewModel · MainActor]
    CameraUI[CameraScreen] --> CameraVM
    GalleryUI[LibraryScreen / MediaViewer] --> GalleryVM
    CameraVM --> Capture[CameraCapturing]
    Capture --> Hardware[CameraCaptureService · serial AVFoundation queue]
    Hardware --> Permissions[CameraPermissions]
    Hardware --> Events[CameraUpdate / CapturedMedia]
    Events --> CameraVM
    CameraVM --> Processor[MediaProcessing]
    Processor --> Actor[MediaProcessor · actor]
    Actor --> Repo[MediaRepository]
    CameraVM --> Photos[PhotoLibraryExporting]
    GalleryVM --> Repo
    GalleryVM --> Photos
    Thumbnails[ThumbnailViewModel · MainActor] --> Repo
```

## Ownership

- `CameraCaptureService` owns the session, device configuration, AVFoundation delegates, recording and throttled live previews. It emits immutable capture options and captured bytes/URLs. It has no file-store or Photos-export implementation.
- `CameraViewModel` owns observable camera state, countdown cancellation, photo import, processing/export coordination and the latest roll thumbnail. It reserves work synchronously before asynchronous permission/hardware operations.
- `MediaProcessor` is an actor that applies photo effects and coordinates `VideoRenderer`. It writes through `MediaRepository`, retaining originals until processed media has been saved successfully.
- `LocalMediaRepository` owns the existing `Documents/Captures` paths, atomic writes, removal, enumeration and thumbnail reads. A different directory or failing repository can be injected in tests.
- `PhotoLibraryExporter` owns Photos permission and export. Failure does not remove a successful local capture.
- `SystemCameraPermissions` owns camera/microphone permission access behind `CameraPermissions`.
- `GalleryViewModel` owns listing and export state; `ThumbnailViewModel` owns asynchronous thumbnail loading. AVPlayer and UIKit zoom remain presentation adapters with selection/background lifecycle hooks.
- SwiftUI retains transient presentation state (sheets, selection, animation) and AppStorage-backed user preferences. The view passes an effect-settings snapshot to its view model.

## Concurrency and cancellation

UI state is isolated to `@MainActor`; processing is actor-isolated. Complete Swift concurrency checking is enabled. `CameraCaptureService` is the one production `@unchecked Sendable` adapter because AVFoundation delegates and Dispatch queues are used for hardware access. It relies on explicit confinement: session/capture state on the capture queue, preview timing/context on the frame queue, effect options under a lock, and callbacks on the main actor. Do not access these values from arbitrary callers.

Device objects do not cross into UI update closures. Photo delegate bytes are extracted before queue handoff. Update closures are Sendable. Permission requests carry a generation ID, so a stale microphone response cannot start a recording after suspension. Countdown IDs prevent cancelled tasks from clearing a later countdown.

Captured-media deliveries are processed in order; a second delivery is not silently dropped. Only the last queued completion clears busy state and releases hardware. An in-flight durable save/export intentionally retains its view model until completion. Background video rendering is still not guaranteed by iOS.

## Persistence compatibility

No migration is required. `Documents/Captures`, `snappi-`/`original-` filenames and stored AppStorage keys remain unchanged. Updating the application in place preserves the library.

## Camera roll performance

Each directory scan reads capture dates and file attributes once per entry. Sorting and day grouping reuse those dates. The camera loads its roll preview off the main actor. Opening Your Roll scans live and deleted directories concurrently. Mutations still refresh the visible listing before the next action, and permanent deletion rechecks the current file at its path.

| Operation | Storage-cleanup baseline (`2d122da`) | Updated |
| --- | ---: | ---: |
| Camera roll count and first thumbnail | 94.5 ms | 17.0 ms |
| Initial gallery listing and deleted-storage total | 102.5 ms | 14.8 ms |

Measured on an iPhone 18 Pro simulator with iOS 27.2 and an optimized Swift build. Both builds used the same 1,500 live and 300 deleted synthetic 64×48 JPEGs with varied creation dates. Timings are median elapsed times across 16 warm samples per build, alternating process order and dropping the first sample from each process. Camera refresh included a thumbnail decode, and each gallery sample used a fresh view model. Host load varied. Cold app launch, grid rendering, video thumbnails and physical iPhone performance require separate measurements.

## Verification

- `./Tests/run.sh`: shared image effects and synthetic video rendering.
- With an iOS simulator booted, `./Tests/run-architecture.sh`: real temporary-file photo processing, countdown cancellation, synchronous workflow reservation, local save on export denial, unlock on processing failure, original retention after a failed final write, and queued failure followed by successful delivery. Set `SNAPPI_SIMULATOR_ID` to select a simulator explicitly.
- Xcode simulator and signed device builds check integration. Hardware permission dialogs, capture/audio and interruption behaviour still need direct physical-device verification after this refactor.
