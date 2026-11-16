# Architecture separation

Goal: preserve the existing camera and gallery while separating hardware, workflows and persistence.

- CaptureService owns AVFoundation and emits state changes/captured media; main-actor CameraViewModel owns workflows and countdown/import coordination.
- Inject MediaRepository, MediaProcessor, PhotoLibraryExporter and CameraPermissions behind protocols. Keep the Captures directory and filename conventions unchanged.
- Gallery view models own listing, thumbnails and exports. UIKit playback/zoom remain presentation adapters.
- Verify storage preservation and failure behaviour, countdown cancellation, immutable capture settings, denied export handling, builds and existing pipeline tests.
- Review before push; document remaining queue-confined AVFoundation unsafe-sendability boundary.

Completed: service/view-model separation, workflow/storage regression checks, original effect/video checks, strict-concurrency simulator and signed device builds, independent review and architecture documentation. Physical-device revalidation remains pending connection.
