# Snappi

User chose the name Snappi for a free native iPhone photo and vintage-video camera app inspired by Dazz Cam. Both photo and video are required. First implementation is now installed; see the implementation section below.

## Approved brand direction
15 November 2026: user selected concept 03 Daylight from branding/snappi-colour-directions-v4.png. Turquoise optical lens, deep navy background, cream reflection, clean lowercase wordmark. Prior orange cartoon camera, monochrome abstract S and monochrome gallery-icon concepts were rejected. Colour is wanted, with clear photographic recognition and a polished character.

Assets: branding/snappi-app-icon-master.png (square opaque raster master; needs platform-size export when implementing), branding/snappi-logo-horizontal.png (repo header). Generated raster artwork, not editable vector masters. Earlier concepts retained as exploration only.

Repository: https://github.com/MphoCodes/Snappi (private), main branch. Canonical memory project ID: MphoCodes/Snappi. Name/trademark availability not checked. Dazz settings were inspected via iPhone Mirroring; live camera quality was not verified. See chat for broader feature requirements. Signing/distribution constraints from Keep also apply to a free development install.

## First implementation — 15 November 2026

User authorized build-out. Native SwiftUI/AVFoundation/Core Image app implemented in Snappi/, with shared live/photo/video effects, local gallery, photo import and Photos export. See README for exact scope and limitations. Main implementation plan in docs/superpowers/plans/. Image tests and synthetic video tests pass. Signed device build installed and launched; real capture/audio/export and UI verification remain pending user feedback. Mirroring could not view the phone because it was in use. Independent review found no confirmed high-priority issue; camera permission recovery on foreground was strengthened.

Development profile expires 22 November 2026 23:39 SAST. Maintain local captures across updates. Originals survive processing failure. Videos capped at 60 seconds and render after recording. API compatibility warnings remain on macOS video-test compilation; iOS build clean except AppIntents metadata skip. No knowledge-graph ingestion tool identified; no graph replaced.

## User device verification
User confirmed that a captured photo and short video both appear in Your roll on the iPhone. This verifies real-device capture through local gallery for those samples. Audio playback, Photos export, interruptions and broader device behaviour remain unverified.
