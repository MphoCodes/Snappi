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

User subsequently confirmed “it works” in response to checking video sound and Save to Photos. Record audio playback and Photos export as user-reported passing; interruptions and broader device coverage remain unverified.

## 16 November 2026 — interaction polish

User rejected the initial UI as generic/dead, then specifically requested intuitive controls, visible animation and swiping between photos. Keep the approved Daylight logo. Implemented 1.1 (build 2): live 128px per-look thumbnails every two seconds from unfiltered frames; labelled Flash/Torch/Timer/Flip/Zoom; viewfinder swipes for looks; moving film selection; shutter keyframe feedback, haptics, recording ring/readout and a 950ms saved-photo print. Respect Reduce Motion.

Gallery now opens a full-screen TabView pager with count, previous/next buttons, thumbnail navigation, share/save for the selected URL, and native UIScrollView pinch/double-tap zoom. Decode only current/neighbour photos to max2400px; pause/release video players when inactive/backgrounded. Inner photo pan is disabled at 1x so the pager owns swipes, enabled when zoomed. Existing captures are never migrated/deleted.

Verification so far: device/simulator builds passed, existing image/video pipeline checks passed; review caught/fixed coalesced shutter blink (now keyframes) and found no confirmed remaining regression. Physical-phone Mirroring showed the updated labelled camera, full-screen viewer, next-photo navigation, and double-tap zoom/reset. Mirroring camera access is blocked by iOS; live thumbnails/capture animation need direct phone check. Horizontal drag could not be reliably reproduced through Mirroring; direct finger swipe/pinch and video page-away audio are not yet verified. Final gesture refinement built successfully and installed/launched on the physical phone on 16 November. User was asked to check swipe/pinch and capture feedback directly; response pending.

Settings are not all equivalent to Dazz Cam: missing manual ISO/shutter, optical lens selection, Live Photos, double exposure, accessory effects, video import and broader profile catalogue. Source: Dazz's official App Store listing, checked 15 Nov. No project knowledge-ingestion tool is installed; portable handoff and shared Agent Memory are the available context, no graph replaced.

## User verification — 16 November 2026

User replied “yes perfect” after being asked to check left/right photo swipes, double-tap zoom/reset and taking a photo to see the saved-photo animation. Those specific interactions are user-reported passing. Pinch gestures and video page-away audio were not separately confirmed. User now wants friends to try Snappi; TestFlight distribution discussed, no enrollment/payment/upload initiated.
