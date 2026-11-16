# Snappi project context

Public repository: https://github.com/MphoCodes/Snappi
Canonical shared-memory project ID: `MphoCodes/Snappi`.

## Product and identity

Snappi is an open-source iPhone camera for film-inspired photos and videos. Public wording should describe its own capabilities without naming competing apps. The owner explicitly requested public publication on 16 November 2026. The chosen license is MIT.

Preserve the approved Daylight identity: turquoise optical lens, deep navy, cream reflection and lowercase wordmark. The logo must read as photography, with colour but without a cartoon style. Generated raster masters and earlier explorations are in `branding/`.

The UI should feel tactile and purposeful. Priorities are intuitive labelled controls, visible interaction feedback and fluid photo browsing. Respect Reduce Motion; do not add decorative motion that obstructs capture.

## Implementation and verification

Native SwiftUI, AVFoundation and Core Image; iOS 17+, Swift 5. Preview/photo/video share the effect pipeline. Captures live locally; Photos export is optional. Keep originals until successful processing and atomic writes. Videos are portrait, up to 1080p and 60 seconds; rendering happens after recording.

Version 1.1 (build 2) includes live per-look thumbnails, labelled controls, swipeable looks, recording/shutter/saved-photo feedback, full-screen media paging and native photo zoom. Decode only the current and neighbouring full-screen images. Pause/release video players when inactive or backgrounded. At 1×, the inner photo pan recognizer is disabled so the parent pager can handle swipes.

Image pipeline and synthetic video checks passed. Device/simulator builds passed. Physical-device capture, audio, Photos export, photo swipes, double-tap zoom/reset and saved-photo animation are user-reported passing. Pinch and video page-away audio were not separately confirmed. Broader interruption/device testing remains open.

See README for build steps, exact feature boundaries and installation requirements. Configure signing locally; never commit credentials, signing profiles, certificates or personal capture files. No knowledge-graph ingestion tool was available at publication; the portable files and shared Agent Memory carry current context, and no existing graph was replaced.

Publication verified on 16 November 2026 using an unauthenticated GitHub API request: public visibility, MIT license, approved description and camera/iOS/Swift topics. The simulator build passed after removing the hard-coded signing team. Reachable Git history was scanned for credential-like content and signing file types; none were found.

## Architecture separation — 16 November 2026

Version 1.1 build 3 separates CameraCaptureService from main-actor CameraViewModel; AppServices injects MediaRepository, actor MediaProcessor, PhotoLibraryExporter and CameraPermissions. Gallery/thumbnail view models own listing, loads and export. Countdown/import/save workflows moved out of views. See docs/ARCHITECTURE.md. Captures directory, filenames and preference keys remain unchanged. Complete concurrency checks enabled; the AVFoundation adapter remains the documented unchecked Sendable boundary.

Review exposed a permission-pending reservation race; a regression test reproduced it and the implementation now reserves synchronously, cancels stale video permission responses by request ID and queues captured media instead of dropping deliveries. Architecture tests cover denied export, failed processing, final-write original preservation and countdown cancellation. Existing device verification predates this refactor; repeat capture/audio and interruption checks on a connected phone.

Refactor verification: architecture checks, image/video pipeline checks, complete-concurrency simulator build and signed generic iOS build passed. The only app-build warning was the informational AppIntents metadata skip. Independent review confirmed the reservation fix and found no further concrete blocker. Build 3 was not installed because the development phone was unavailable.

Code style: prefer clear names and small functions; keep comments only for non-obvious constraints such as concurrency, gesture ownership and media preservation. Redundant narration was removed on 16 November 2026 without changing executable code.
