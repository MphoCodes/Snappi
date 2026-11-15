# Snappi handoff

Repository: https://github.com/MphoCodes/Snappi
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
