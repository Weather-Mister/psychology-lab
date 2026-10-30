# Grainlight — independent RAW cinematic camera for iPhone

An **Xcode iOS application project**, built as an independent functional counterpart to the Chromagraph workflow. The project is not affiliated with the original makers and does not contain their proprietary image-processing code, brand or assets.

## What's included

- Native SwiftUI still camera, using AVFoundation and a real `AVCaptureVideoPreviewLayer`.
- Physical lens selection (ultra-wide, wide, telephoto, if available on your iPhone).
- Tap to focus and meter, optional 3×3 compositional grid, capture at the active lens's maximum requested photo dimensions.
- Bayer RAW DNG capture on supported cameras; if Bayer RAW is unavailable, another supported RAW format (including Apple ProRAW where enabled); JPEG fallback if none.
- **Shoot first, develop afterward**: live preview remains the ungraded camera feed.
- An independent custom RAW-to-image pipeline in Core Image: minimize Apple RAW boost/local tonemapping, filmic tonality, highlight/shadow grading, cross-channel color rendering, warm highlight/cool shadow split, grain, halation and sharpening.
- Persistent private gallery, full-sized originals (DNG/JPEG), cached thumbnails, full-screen viewer and deletion.
- Non-destructive editable controls for tone, color, grain size/intensity, pixel-size grain, halation radius/strength, sharpness and crop ratios; `PhotoEdits` are stored alongside each original.
- Import DNG and common image formats from Files for developing existing pictures.
- Full-resolution JPEG and HEIC exports, iOS Share Sheet, and optional automatic export to Apple Photos.
- iOS 17+ target, no third-party packages and no accounts or network calls.

## How to run on your iPhone

1. On a Mac, install **Xcode 16 or newer** from Apple.
2. Unzip the project and double-click **`Grainlight.xcodeproj`**.
3. In Xcode, choose the `Grainlight` project → **Signing & Capabilities**. Choose your personal Apple Development team. Change the bundle ID from `com.example.grainlight` to a unique name if Xcode requests it.
4. Connect and unlock your iPhone, enable Developer Mode when prompted, select it as the run destination, then choose **Product → Run** (⌘R).
5. Grant camera access. Take a picture, tap the gallery thumbnail, and use **Tune** to adjust your photograph. Optional Photos permission is requested when you export there.

This is a **source project, not a signed IPA or App Store release**. Installing an iPhone app requires an Apple signing identity and Xcode (or an equivalent signed distribution pipeline). There is no Apple SDK or iOS simulator in the environment where these files were generated, so **device compilation and camera behavior have not been verified**.

## Main files

| Path | Responsibility |
| --- | --- |
| `Grainlight/Camera/CameraService.swift` | Permission, AVCapture session, RAW capture, physical lenses, focus |
| `Grainlight/Imaging/FilmRenderer.swift` | RAW development, 3D look LUT, tone, grain, halation, export |
| `Grainlight/Library/PhotoRecord.swift` | Metadata, editable parameters, crop types |
| `Grainlight/Library/PhotoLibrary.swift` | Save, load, thumbnails, import, persist, export to Photos |
| `Grainlight/UI/MainView.swift` | Camera layout and shutter |
| `Grainlight/UI/GalleryView.swift` | Grid, viewer, share and delete |
| `Grainlight/UI/EditorView.swift` | Interactive non-destructive editing |
| `Grainlight/UI/PreferencesView.swift` | Auto-export and app settings |
| `Grainlight/Info.plist` | Camera and photo library permission purpose strings |

## What isn't identical

The source code and quantitative parameters behind Chromagraph's bespoke pipeline are not public. Its image character can't be reverse-engineered exactly from marketing photographs. Grainlight's look is **an original approximation** with a film-like toe and shoulder, subdued saturation, gentle warmth, preserved shadow color, synthetic grain and red/orange halation.

Currently **not implemented**: Chromagraph's exact color science, its multi-exposure computational RAW merge, its Apple Watch companion, full calibrated color profiling per iPhone sensor, original photography and icon assets, and video shooting. JPEG fallback images have already passed through phone processing and therefore **do not** reproduce the RAW-first method. Apple ProRAW may also contain Apple's computational merging, even though the app applies its own tone/color rendering afterward.

This version is a strong independent foundation rather than a tested pixel-perfect commercial-app replica. 

## Testing on device

1. Photograph a bright sky and shadowed building; verify DNG is saved when the current lens supports RAW, and ensure the sky rolls off rather than clipping too harshly.
2. Open the gallery; select the new shot and edit exposure, grain and halation. Close and reopen; verify edits persist and the original file is unchanged.
3. Switch each available lens and verify the viewfinder and capture remain functional.
4. Import a DNG from Files; verify decoding, orientation, preview generation and crop.
5. Export JPEG and HEIC and inspect both at full resolution.
6. Enable auto-export and test Apple Photos authorization and saved photo.
7. Test on a device without RAW support to verify JPEG fallback.
8. Test low light, rapid repeated taps, device locking/unlocking, and app relaunch.

## References used to design the behavior

- Official app description: https://www.chromaticapplications.com/chromagraph/chromagraph
- Apple App Store listing: https://apps.apple.com/us/app/chromagraph-camera/id6803329435
- Apple RAW capture: https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats
- Apple's high-resolution capture guidance: https://developer.apple.com/videos/play/wwdc2026/304/
- Apple RAW development: https://developer.apple.com/documentation/coreimage/cirawfilter

Copyright (c) 2026. Independent sample project. No Chromagraph source or assets used.

## GitHub Actions: download an IPA

The project now includes `.github/workflows/build-ipa.yml` and a **shared Xcode scheme**. To get a build in GitHub Actions:

1. On a Mac with the GitHub CLI installed, unzip this project and run `bash publish-to-github.sh` inside the `Grainlight` folder. The script creates a **separate private** `grainlight-ios` repository in your GitHub account and pushes the project, including `.github` workflows. Alternatively, create a new repo manually and push all files (including hidden `.github`).
2. Open **Actions → Build Grainlight IPA → Run workflow**. The workflow also runs automatically on a push to `main` or `grainlight-ios`.
3. After a **successful** run, open the workflow run and download the artifact named **`Grainlight-unsigned-IPA`**. Unzip the artifact ZIP to obtain `Grainlight-unsigned.ipa`.
4. This is a real compiled iOS app package but **unsigned**. To install it, sign it using an appropriate sideloading tool, or set up the optional signed workflow below. Renaming an IPA does not make it installable.

The GitHub Actions service uses a macOS runner with Xcode; this environment cannot run `xcodebuild`. If it reports a compile error, check its `build-log` artifact and fix the Swift source.

### Signed IPA for registered iPhones

The separate `.github/workflows/build-signed-ipa.yml` creates a release-testing (ad hoc) IPA using these GitHub Actions repository **secrets**:

| Secret | Meaning |
| --- | --- |
| `IOS_TEAM_ID` | Apple Developer Team ID |
| `IOS_BUNDLE_ID` | Unique iOS bundle ID covered by the provisioning profile |
| `IOS_CERTIFICATE_P12_BASE64` | Base64-encoded Apple Distribution `.p12` certificate **including its private key** |
| `IOS_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64-encoded ad hoc `.mobileprovision` whose registered devices include the target iPhone |

Run **Actions → Build signed iPhone IPA → Run workflow**, then download `Grainlight-signed-IPA` after success. Keep signing keys and profiles in GitHub encrypted repository secrets; never commit them. Signing requires membership in Apple's Developer Program with the appropriate certificates/profiles. A free Apple ID does not supply the full ad hoc distribution prerequisites. A registered device and suitable installation method are still required. Apple's TestFlight route is an alternative for beta distribution.

**Important:** Creating a new repository is not exposed by the connected GitHub actions available in this chat, so the downloadable source ZIP is prepared and workflow-ready, but it has not automatically been pushed to a new GitHub repository. Do not use an unrelated existing repo as a replacement for the new standalone repository without considering its organization.

See `QA_REPORT.md` for test results and visual comparison limitations.
