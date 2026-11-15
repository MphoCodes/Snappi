<p align="center"><img src="branding/snappi-logo-horizontal.png" alt="Snappi" width="720"></p>

# Snappi for iPhone

A personal photo and vintage-video camera, with six included looks and no accounts, ads, purchases or cloud processing.

## First build

- Photo and video capture using the front/rear wide camera.
- Live effect preview: Original, Daylight, Golden, Faded, Noir and Tape.
- Adjustable effect strength, grain and warmth; camera exposure from −2 to +2 EV (clamped to device capabilities).
- 1×/2×/3× digital zoom, photo flash/video torch where available, 3/10-second timer and composition grid.
- Date stamps, remembering settings, optional original preservation.
- Local gallery, photo import, video playback, sharing and optional Photos export.
- Portrait video, up to 1080p, capped at 60 seconds per clip. Effects render after recording; keep Snappi open during processing.

Camera permission is required for capture. Microphone access is requested for video; denied microphone access produces silent video. Photos add-only permission is optional: captures remain in Snappi even if export is denied. Deleting the app deletes its local library. Export anything you want to keep first.

The Original preset bypasses the preset colour treatment; grain/warmth/date-stamp controls remain independent. Set grain and warmth to zero and disable the date stamp for an untouched colour treatment. Preview is throttled to 15 fps and downscaled for responsiveness; full captured media is processed separately. This is a first development version, not a reproduction of Dazz Cam's proprietary rendering.

## Current boundaries

Portrait-only camera, front/rear wide lenses, digital zoom. No manual ISO/shutter, optical lens selector, RAW/Live Photos, double exposure or video import yet. No delete control in the local gallery yet; use Photos exports for external organization. No background export guarantee: original movie files are kept if processing does not complete.

## Build

Xcode 27.2 on the development Mac; iOS 17+. The project uses that Xcode installation's `project.xcproj` format. Automatic signing uses the owner's configured development team; change DEVELOPMENT_TEAM and bundle ID for another account.

```sh
xcodebuild -project Snappi.xcodeproj -scheme Snappi -configuration Debug \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
./Tests/run.sh
```

## Verification

- Core Image pixel tests: preset output, Original identity with independent effects off, zero-strength behaviour, Noir colour removal, finite extents.
- Real synthetic video export: Noir applied to rendered pixels, duration retained, portrait orientation retained, original source preserved, missing input errors.
- Signed physical-device build passed; installed and launched on the connected iPhone 17 Pro Max.
- Independent code review found no confirmed high-priority defects. Permission resume recovery was strengthened.
- Real photo/video capture, audio, Photos export and UI presentation on the phone remain user verification items. Mirroring was unavailable because the phone was in use.
- Mac video-test compilation reports deprecated AVFoundation API warnings; these compatibility APIs support the iOS 17 deployment floor. Device build has only the informational AppIntents metadata warning.

## Installation lifetime

The current development profile expires **22 November 2026 at 23:39 SAST**. It requires renewal before expiry. This is not App Store/TestFlight distribution. Do not uninstall to renew: updating in place preserves the local library.

## Implementation

- `Effects.swift`: shared Core Image processing.
- `VideoRenderer.swift`: filtered movie export.
- `CameraController.swift`: queue-confined AVFoundation capture and preview.
- `MediaLibrary.swift`: durable files, image processing, Photos export.
- `SnappiApp.swift`: SwiftUI camera, controls and gallery.

Selected brand: Daylight (turquoise lens, navy, cream reflection). Master artwork lives in `branding/`; earlier rejected concepts are retained for history. Name/trademark availability has not been checked.
