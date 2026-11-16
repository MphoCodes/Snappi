# Snappi handoff

Public repository: https://github.com/MphoCodes/Snappi
Branch: `main`. Shared-memory project ID: `MphoCodes/Snappi`.

## Current state

Version 1.1 (build 2) is installed on the development iPhone. The owner confirmed photo swipes, double-tap zoom/reset and saved-photo feedback work after the interaction polish pass. Earlier checks confirmed capture, video audio and Photos export. Existing captures were preserved in place.

The owner requested public open-source publication on 16 November 2026. Public description: **An open-source iPhone camera for film-inspired photos and videos.** MIT license added; public-facing wording does not name competing apps. The signing team is no longer hard-coded in the project. Supply a team and unique bundle identifier locally, as documented in README.

## Next development work

- Directly verify pinch/pan transitions, video page-away audio and interruption recovery across devices.
- Preserve original media on every processing failure and export denial.
- Keep camera controls labelled and touch-friendly; maintain the Daylight identity and Reduce Motion support.
- Consult README before expanding scope: manual ISO/shutter, physical lens selection, RAW/Live Photos, double exposure, video import and gallery deletion remain unimplemented.

The source is available for developers to build. Public source is not a signed iPhone distribution: no App Store release, TestFlight link, enrollment purchase or public binary release has been created. Sharing with friends was deferred by the owner.

## Checks and context

Use `./Tests/run.sh` for image and synthetic movie checks, and Xcode for device/simulator builds. The project uses Xcode 27.2's `project.xcproj` format. macOS AVFoundation test warnings reflect compatibility APIs for iOS 17.

See `MEMORY.md` for product decisions and architecture. No project knowledge-ingestion tool was available; no graph refresh or replacement was performed. Do not store credentials or private captures in this repository.

Publication verified on 16 November 2026 using an unauthenticated GitHub API request: public visibility, MIT license, approved description and camera/iOS/Swift topics. The simulator build passed after removing the hard-coded signing team. Reachable Git history was scanned for credential-like content and signing file types; none were found.

## Architecture separation — 16 November 2026

Version 1.1 build 3 separates CameraCaptureService from main-actor CameraViewModel; AppServices injects MediaRepository, actor MediaProcessor, PhotoLibraryExporter and CameraPermissions. Gallery/thumbnail view models own listing, loads and export. Countdown/import/save workflows moved out of views. See docs/ARCHITECTURE.md. Captures directory, filenames and preference keys remain unchanged. Complete concurrency checks enabled; the AVFoundation adapter remains the documented unchecked Sendable boundary.

Review exposed a permission-pending reservation race; a regression test reproduced it and the implementation now reserves synchronously, cancels stale video permission responses by request ID and queues captured media instead of dropping deliveries. Architecture tests cover denied export, failed processing, final-write original preservation and countdown cancellation. Existing device verification predates this refactor; repeat capture/audio and interruption checks on a connected phone.

Refactor verification: architecture checks, image/video pipeline checks, complete-concurrency simulator build and signed generic iOS build passed. The only app-build warning was the informational AppIntents metadata skip. Independent review confirmed the reservation fix and found no further concrete blocker. Build 3 was not installed because the development phone was unavailable.
