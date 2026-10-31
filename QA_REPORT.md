# Grainlight QA audit — 30 October 2026

## Shutter crash investigation — 31 October 2026

A user reported immediate process termination when taking a photograph. Previous passing tests covered rendering and simulator startup; they did **not** validate a physical shutter capture. No iPhone crash report has yet been supplied, so attribution to this exact device crash remains provisional.

A concrete invalid request was found: the app preferred Bayer RAW but set `photoQualityPrioritization = .quality` for every capture. The installed Apple SDK's `AVCapturePhotoOutput.h` explicitly requires `.speed` for Bayer RAW. The new CI step checks this contract directly from the Apple SDK and retains the excerpt. Request construction now uses speed for Bayer RAW, quality for ProRAW/processed capture, and a fresh settings object per request.

The submission call is enclosed in an Objective-C exception boundary. A synchronous framework rejection is converted into an NSError and displayed, with the retained delegate and busy state released on the session queue. Swift `do/catch` alone cannot catch NSException. The boundary is tested by injecting a real Objective-C invalid-argument exception; this is not an induced sensor capture failure.

Supported capture dimensions now prefer the largest available size at or below 13 million pixels (normally 12MP); if no such size exists, the smallest advertised size is used. This is a conservative memory/compatibility choice, not proof that the reported crash was memory pressure. RAW capture remains enabled.

The simulator workflow now runs a Debug-only integration harness before the normal startup check. It constructs actual AVCapturePhotoSettings through the production factory, checks the Bayer rule, fresh request IDs, processed fallback and invalid capability handling, tests the exception boundary, injects five 4032×3024 JPEG payloads and a synthetic DNG through the production library, develops images on iOS Core Image, reloads edits, waits for a thumbnail, exports full-resolution JPEG, verifies original bytes, and deletes/reloads the generated records. This goes beyond a startup check, but does not exercise sensor acquisition, physical lens changes, Photos authorization/export, or real iPhone Bayer/ProRAW data.

**Final hosted result: PASS** — [run 41172439569](https://github.com/Weather-Mister/psychology-lab/actions/runs/41172439569), source `8f7f37ef6349622fc3c784b69732da87d692a67e`, macOS 15 / Xcode 16.4. **25/25 iOS capture-path integration checks**, **37/37 native renderer checks**, SDK rule extraction, static checks, baseline comparison, Release device build, Debug simulator build/integration/normal startup all passed. Logs inspected. Real AVFoundation disconnected submission was rejected into NSError and the app continued; stopped-session shutter was safely ignored. This is failure-path reproduction in Simulator, not reproduction of the user's sensor crash. Normal app startup was observed separately after the harness.

Machine-readable [capture-path results](docs/qa/shutter-crash-2026-10-31/capture-self-test.json) and [renderer results](docs/qa/shutter-crash-2026-10-31/renderer-results.json) are committed. [IPA artifact](https://github.com/Weather-Mister/psychology-lab/actions/runs/41172439569/artifacts/13032250980) and [full test/SDK evidence](https://github.com/Weather-Mister/psychology-lab/actions/runs/41172439569/artifacts/13031946706).

Package inspected: valid ZIP CRC, ARM64 Mach-O, version 0.1.1/build 5. The `--capture-self-test` entry string is absent from the Release executable; test mode is Debug-only. IPA size 341,664 bytes; SHA-256 `432cf192c5dd2e01821ba351b81a3b810586c529ca6dbbebd56ffd0ca25c75bc`. Unsigned, requiring sideload signing. The psychology backup branch is preserved. The confirmed request defect is fixed, but the user's exact crash and physical-device capture still require an iPhone test/crash report. This patch is version 0.1.1 (build 5); the old art-direction evidence is retained below.

## Shadow-density refinement and RAW format visibility

Application source `70602ea6d0172b8d8bfe482ad7d381fbc1e14596` adds a luminance-dependent density stage after LUT interpolation. It deepens shadows/lower midtones while retaining bright cream highlights, and strengthens cool shadow separation. Neutral mode bypasses it. Applying density inside the LUT initially caused a monotonic-ramp regression; the unchanged native test caught it, and density now operates after interpolation.

The [focused hosted test run](https://github.com/Weather-Mister/psychology-lab/actions/runs/41077960702) passes **37/37 native assertions**, including three new checks for shadow density, dark-blue preservation and near-black detail. Minimum red-channel ramp step is positive (`0.00013725483`); the signature's 18% gray red channel is `0.04735294`. These are creative-transform checks, not sensor accuracy measurements. Actual previous/current renders of the same screenshot were visually compared with the target. Updated shadows are denser; the target still has darker lower midtones and different framing. For corresponding low-tone pixels in this screenshot probe, median encoded-sRGB luma fell from 0.1381 to 0.0765; this measures the intended density change, not colorimetric accuracy or target equivalence. No exact match claim.

The camera header now states Bayer RAW, Apple ProRAW, or JPEG according to available formats, with a checking state before configuration. Capture still prefers Bayer RAW, then another available RAW format (Apple ProRAW on supported iPhones), and JPEG when RAW is unavailable. DNG is developed with CIRAWFilter before the look; a JPEG import is not RAW. Synthetic Bayer decode is tested; physical-device capture and ProRAW validation remain outstanding. ProRAW includes Apple computational processing and is not equivalent to single-frame Bayer RAW.

Full build [41077960743](https://github.com/Weather-Mister/psychology-lab/actions/runs/41077960743) passed: 37 native tests, static checks, iOS device and simulator builds, install/startup smoke test and IPA packaging. Logs inspected: both builds succeeded; simulator PID 8493 observed alive. No physical camera test was performed. Package ZIP CRC and ARM64 Mach-O inspected. Size 337,267 bytes; SHA-256 `b39d3d5c8cab5c7a8165b3b598ada5dfc54c84074ca74fed83bd6bc1abe87070`. The IPA is unsigned and requires signing. [IPA artifact](https://github.com/Weather-Mister/psychology-lab/actions/runs/41077960743/artifacts/12987379015), [evidence artifact](https://github.com/Weather-Mister/psychology-lab/actions/runs/41077960743/artifacts/12989041003). Earlier sections retain historical measurements for their explicitly named source revisions.

## Reference-style update (latest)

The user supplied three screenshots after the first audit and requested closer photographic style. The signature was retuned toward their visible characteristics: deeper cool shadows, creamy bright neutrals, and reduced bright-blue saturation, with luminance gating to preserve blue architecture. Neutral mode still bypasses the creative transform. The earlier audit's low highlight-color-spread measurement below describes its tested revision, not the new artistic target; creamy signature highlights are deliberately warm.

The native harness now develops the cropped city “before” screenshot and places the unmodified target crop beside the result. Crops exclude the social interface. These are already processed JPEG screenshots, differently framed and potentially differently exposed—not a common sensor RAW pair. The sunset, airport, Chicago and night examples have no before frames. No photographic-equivalence or whole-scene pixel-error claim is made.

The new signature has passed all 34 native runtime assertions. The screenshot probe has different exposure/framing and baked processing; a style adjustment cannot establish RAW equivalence. The new warmth is intentionally confined to signature mode; neutral-mode color preservation remains tested.

The latest refinement also reduces default grain from 0.55 to 0.18 for new photographs/reset edits and lifts luminous blue skies toward cream, leaving dark blues outside that adjustment. Existing saved edit values remain preserved. A near-neutral exclusion prevents the sky transform from introducing tone reversals through LUT interpolation. The unchanged monotonic-ramp test caught that regression before release, and the repaired renderer passes all 34 native checks.

A repository tree construction error in intermediate commits temporarily omitted unrelated project files. It was detected by CI and repaired from the full preceding tree in commit `fabb00b`; the final project retains all original application, project, QA and workflow files. The psychology backup branch was never modified.

Final color-managed style check: [run 41075842071](https://github.com/Weather-Mister/psychology-lab/actions/runs/41075842071), source `87b933f3ed44c16cac892ac3b781e72f403ffeae`, 34/34 native runtime assertions passed. Actual output was visually inspected beside the screenshot source and target. The sky is creamier and grain is subtler; shadows remain lighter than the target, so this is a closer style approximation, not a match. The target crop uses tagged sRGB reconstructed from `target-srgb.b64`; it is not processed through Grainlight.

These reference results supersede the initial audit's creative-look measurements. That audit's neutral-mode tests and engineering findings remain relevant. Final IPA build: [run 41075842053](https://github.com/Weather-Mister/psychology-lab/actions/runs/41075842053), source `87b933f3ed44c16cac892ac3b781e72f403ffeae`. All 34 native assertions, static checks, baseline comparison, iOS device compilation and simulator install/launch smoke check passed. Final job logs inspected; both builds succeeded and simulator PID 16306 was observed alive. IPA ZIP CRC and ARM64 Mach-O packaging inspected. Size 335,759 bytes; SHA-256 `9b187066483a58986d1512c7da0593f62e582a20feb7dfca2b6d5925f5e3639f`. Unsigned; physical capture remains unverified. Download artifacts [IPA](https://github.com/Weather-Mister/psychology-lab/actions/runs/41075842053/artifacts/12986788622) and [evidence](https://github.com/Weather-Mister/psychology-lab/actions/runs/41075842053/artifacts/12986628802).

## Scope and release meaning

Reviewed every application Swift file and the Xcode project, permissions, build workflows, and existing QA scripts. Starting revision: `c261056ff5063b828a2c015320a63119d191315b`. Its Actions run [41063611894](https://github.com/Weather-Mister/psychology-lab/actions/runs/41063611894) succeeded using Xcode 16.4, but only performed static Python checks and a device-target compile; it did not run renderer tests or launch a simulator.

This audit adds executable tests of the **shipping Swift/Core Image renderer**, a reproducible synthetic Bayer DNG generator, baseline-image comparison, and an iOS simulator build/install/launch smoke check. This is engineering validation, not a physical-camera certification or a claim of photographic equivalence.

The original psychology backup branch must remain at `4b2fedeb3106816f0cfc29f2c343b8a95def8f0b`: `backup-psychology-before-grainlight-2026-10-30`. No writes target that branch.

## Confirmed findings and repairs

| Finding | Impact | Repair / evidence |
|---|---|---|
| Capture delegate stored on session queue but cleared on main | Data race and possible interference with a subsequent capture | Retain/release delegate and reset capture gate on the same serial session queue |
| Lens input could change during capture | Capture configuration could change beneath the request | Both UI and session-queue guard block lens switches during capture |
| Failed lens replacement still applied requested device dimensions | Output dimensions could disagree with actual input | Configure dimensions from the successfully attached input |
| Autofocus/autoexposure setters checked point support only | Unsupported mode can raise an Objective-C exception | Check the requested mode as well as point support |
| Capture permitted while stopped/interrupted | Invalid or unusable capture requests | Require running, uninterrupted session and an active video connection |
| Camera-denied state never cleared after Settings grant | UI could remain blocked after permission recovery | Reset denial on grant; preserve lifecycle intent across asynchronous authorization |
| No interruption/reset handling | Camera could remain unavailable after media-services events | Disable shutter during interruption; restart on interruption end/media-services reset when wanted |
| Fixed “3×” telephoto label | Incorrect on phones with other physical telephoto magnification | Label physical camera “Tele” |
| RAW output explicitly rotated again using EXIF | Risk of double rotation | Let CIRAWFilter apply orientation; test synthetic Bayer DNG orientations 1 and 6 |
| DNG decode could fall through to generic image decoding | Potential embedded-preview substitution | DNG must decode through CIRAWFilter or return failure |
| Unconditional optional RAW controls | Some decoders do not support all adjustments | Check each CIRAWFilter support flag before configuring it |
| Strong LUT highlight tint and bounded LUT clipping | Yellow bright neutrals; over-range highlight detail loss | Taper split tone, reduce warm bias, compress highlights before the LUT |
| Grain regenerated with each rendering | Texture moved when editing/exporting | Deterministic coordinate-based monochrome grain, weighted toward midtones |
| Halation radius identical at preview and export resolutions | Different apparent bloom in preview versus export | Scale radius with render size; use highlight mask and valid premultiplied glow |
| Fractional crop bounds | Core Image expanded 4:5 and 16:9 crops in native tests | Pixel-align crop bounds and normalize the output origin; tolerance is one output pixel |
| Unbounded simultaneous full-resolution render work | Memory pressure from preview/thumbnail/export overlap | Serialize public render/export calls with a lock; disable intermediate caching |
| Metadata write failure silently left in-memory changes | Gallery could display unsaved edits/captures; delete could lose original before metadata saved | Roll back failed mutations; persist delete before unlinking; block writes on corrupt index |
| Photos-denial/share temporary files not removed | Accumulating exports | Cleanup on denied Photos authorization and share completion |
| Portrait-only iPad app did not require full screen | Xcode orientation warning / unsupported multitasking contract | Declare full-screen requirement |
| Editor claimed all originals were RAW | False for JPEG/HEIC imports | Say “original file preserved” |

These are source-confirmed defects or robustness issues. No physical-device crash was reproduced, and none is described as reproduced.

## Every Swift file reviewed

| File | Review focus and remaining limits |
|---|---|
| `App/GrainlightApp.swift` | Single library ownership, preferences, scene creation; no functional change needed |
| `Camera/CameraService.swift` | Permissions, session sequencing, lens rollback, RAW selection, focus, delegate lifetime, interruptions, portrait orientation; all physical-camera behavior still requires hardware |
| `Imaging/FilmRenderer.swift` | Decode, color space, effects ordering, premultiplication, orientation, crop, export, memory; now exercised natively |
| `Library/PhotoRecord.swift` | Codable edit model, default values, crop ratios, export mapping; round-trip test |
| `Library/PhotoLibrary.swift` | Original preservation, index transactions, generation-safe thumbnails, export authorization and cleanup; filesystem failure paths reviewed, not fault-injected on iOS |
| `UI/MainView.swift` | Scene transitions, modal lifecycle, shutter/lens readiness, permissions and format labels |
| `UI/GalleryView.swift` | Selection by ID, stale render suppression, export/share lifecycle, decode failures; no full automated touch-navigation test |
| `UI/EditorView.swift` | Debouncing, stale render suppression, cancel/save, controls and source label; in-flight detached work can complete after cancellation but cannot replace a newer result |
| `UI/PreferencesView.swift` | Preference persistence and truthful capture/export descriptions; no functional change needed |

## Reproducible controlled-image tests

Run `bash qa/run_native.sh` on macOS with Xcode. It compiles the production renderer and edit model alongside `qa/native/main.swift`; UIKit preview adaptation alone is excluded on macOS. The exact Core Image processing methods used by the app are executed.

Fixtures are generated locally with known values: grayscale/shadow ramps, values above 1.0, RGB swatches, a midgray texture field, a white rectangle on black, an EXIF-rotated JPEG, invalid DNG data, and synthetic Bayer DNGs. The Bayer fixtures are deliberately synthetic—not photographs and not iPhone sensor calibration data. Their original 128×96 form was rejected by Apple's decoder; the 640×480 fixtures include explicit crop/active-area metadata and decode successfully.

Checks cover neutral RGB preservation, monotonic tone, black preservation, bright-neutral balance, over-range highlight separation, finite pixels, grain repeatability/mean/monochrome variation, halation isolation/spread, all crop ratios, preview bounds, rejection of invalid RAW, JPEG and HEIC encoding/decoding, source-byte preservation, shadow/exposure response, JPEG/DNG orientation and edit persistence. Results and actual rendered images are uploaded in `Grainlight-QA-evidence`.

`qa/run_baseline.sh` compiles the starting revision's renderer with only its UIKit preview adapter removed. It renders the same chart files and records near-white RGB/channel spread in `baseline-comparison.json`. This is a reproducible comparison against Grainlight's original build, not against competitor apps. Baseline JPEG versus revised PNG measurements include small encoding/quantization differences; they support identifying a large color cast, not high-precision colorimetric calibration.

The Python camera/gallery/look checks remain explicitly **static checks**. They are not substitutes for runtime tests.

## RAW pipeline comparison with established applications

Documentation checked 30 October 2026. No competitor app was installed or executed during this audit; no matched camera captures or common-RAW competitor exports were supplied.

| Application | Documented behavior | Grainlight comparison and limits |
|---|---|---|
| [Chromagraph](https://www.chromaticapplications.com/chromagraph/chromagraph) | Custom rendering beginning with RAW, developed appearance after capture, original-preserving gallery and JPEG/HEIC export | Similar workflow, independently designed math. No access to its transform, grain, halation, calibration or test images. No equivalence claim |
| [Halide Process Zero](https://www.lux.camera/process-zero-manual/) | Single capture with minimal processing, separate RAW data and developed image; documented resolution/night-mode limitations | Grainlight prefers Bayer RAW but deliberately adds a creative LUT, denoising, sharpening and texture. ProRAW fallback is a different capture pipeline, not Process Zero |
| [Lightroom mobile](https://helpx.adobe.com/ro/lightroom/mobile/add-and-capture-photos/capture-photos/capture-photos-in-auto-mode.html) | DNG/JPEG capture and RAW editing; broader profile/editing workflow | Grainlight uses Apple's RAW decoder and a small custom effect stack, not Adobe Camera Raw profiles or processing |
| [Apple Camera / ProRAW](https://support.apple.com/en-ie/119916) | ProRAW combines RAW flexibility with computational image processing | ProRAW fallback cannot be described as unprocessed sensor capture. Grainlight does not recreate Smart HDR, Deep Fusion or Night mode |

Apple references: [RAW/ProRAW capture](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats), [CIRAWFilter](https://developer.apple.com/documentation/coreimage/cirawfilter), [RAW orientation](https://developer.apple.com/documentation/coreimage/cirawfilter/orientation), [capture settings validity](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings), [photo quality prioritization](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/photoqualityprioritization).

## Image-quality interpretation

- **Color:** neutral digital swatches test the software transform, not real-world sensor accuracy. Signature intentionally alters color. No ColorChecker capture, illuminant measurement, spectrally characterized reference, Delta E claim or calibrated-display assessment.
- **Highlights:** the new shoulder preserves distinctions above the LUT range; it cannot recover data already saturated at the sensor. It is an SDR creative curve, not an HDR output pipeline.
- **Shadows:** tests verify control response and zero-black behavior. Real low-light noise, banding, black-level calibration and denoising tradeoffs remain unmeasured.
- **Grain:** repeatable monochrome procedural texture with midtone weighting; no claim of physically accurate silver-halide grain. Preview downsampling cannot reproduce every full-resolution grain particle.
- **Halation:** selective warm bloom with resolution-scaled radius; not a calibrated emulsion/optics simulation. Synthetic edges test isolation and spread, not photographic authenticity.
- **RAW:** synthetic Bayer decode/orientation is useful integration coverage, not verification of any iPhone Bayer/ProRAW variant or 48 MP memory behavior.

## Remaining release gates

1. Install a signed build on a supported iPhone and exercise every physical lens, Bayer/ProRAW/JPEG fallback, flash availability, focus, repeated captures, gallery entry during capture and background/foreground transitions.
2. Test camera permission deny → Settings grant, Photos deny → grant, incoming call/interruption, media-services reset, thermal pressure and low storage.
3. Test actual iPhone DNG and ProRAW files in portrait/landscape, large images and repeated slider scrubbing; measure latency and peak memory. Serial rendering limits overlap but does not prove memory safety on all phones.
4. Photograph the same controlled scene and color target with fixed lighting/exposure/white balance, then compare matched RAW developments in Grainlight, Lightroom, Halide and Chromagraph where their workflows permit it. Record app versions and settings. Until then aesthetic equivalence is unverified.
5. Exercise library recovery and disk-full failure paths on iOS. Startup corruption is now surfaced and writes blocked; automatic repair is not implemented. Capture/import file I/O still occurs on the main actor and may pause UI for very large originals.
6. Verify accessibility, Dynamic Type, iPad layout and touch interactions. Simulator process survival is only a launch smoke test.

Core Image source-language kernels compile and execute on the tested runner but use Apple's deprecated `CIColorKernel(source:)` API. A compiled Metal-kernel migration remains technical debt; the warning is not hidden. GPS/EXIF export preservation is not comprehensively tested. Unsigned IPA output still needs signing/provisioning before stock-iOS installation.

Machine-readable results are retained in [results.json](docs/qa/2026-10-30/results.json) and [baseline-comparison.json](docs/qa/2026-10-30/baseline-comparison.json).

## Final hosted results

- **PASS:** [Actions run 41066773710](https://github.com/Weather-Mister/psychology-lab/actions/runs/41066773710), source revision `e360c35782a19c90f698d9043341aab05908c756`, hosted macOS 15 / Xcode 16.4. Device and simulator SDK: iOS 18.5; deployment minimum iOS 17.
- **34/34 native runtime assertions passed**, plus 20 static checks (9 camera, 10 gallery, 1 aggregate look check).
- **PASS:** Release iOS device build; Debug iOS simulator build, install, launch and process-alive check. Simulator PID 6634 remained registered at the check; this is only a brief startup test. Simulator screenshot was inspected and shows the initial camera-permission prompt. The prompt was not dismissed and no post-permission navigation was automated; this is not a capture or interaction test.
- **PASS:** JPEG and HEIC export/decoding on hosted macOS; Bayer DNG decode at 640×480 and orientation-6 output at 480×640; unchanged RAW input bytes.
- **Measured:** neutral ramp and digital swatch max channel error 0.0 in the tested neutral pipeline. Grain midgray mean 0.49989834. Near-white signature channel spread reduced from 0.24233 in the original renderer to 0.00392 in the revised output (different export encodings as noted above). This is not Delta E or sensor accuracy.
- **Visual inspection:** generated color patches, grayscale ramp, grain field, halation edge, baseline ramp and synthetic rotated RAW development reviewed. No real photographic scene or competitor output was verified.
- **Artifact:** [unsigned IPA ZIP](https://github.com/Weather-Mister/psychology-lab/actions/runs/41066773710/artifacts/12982534958), [QA evidence ZIP](https://github.com/Weather-Mister/psychology-lab/actions/runs/41066773710/artifacts/12983775620). Actions retention expires 29 November 2026.
- **Package inspection:** ZIP CRC valid; `Payload/Grainlight.app/Grainlight` is a 64-bit ARM64 Mach-O, not a simulator binary. Info.plist has camera and Photos-add usage strings, minimum iOS 17, bundle `com.example.grainlight`, version 0.1.0. No provisioning profile. Unsigned output requires signing; installation was not attempted on a phone.
- **IPA size:** 335,390 bytes. SHA-256: `bdb26dd2748c4a70a0af7cba59b9d13bdd555e8719c4258d718a3f706d5e9c43`.
- **Warnings reviewed:** deprecated Core Image source kernels; harmless App Intents metadata extraction warning. Prior renderer Sendable and iPad orientation warnings no longer appeared. No compiler errors in final run.
- **Backup verified unchanged after commits:** `4b2fedeb3106816f0cfc29f2c343b8a95def8f0b`.

Intermediate failures were retained in Actions: run 41066134038 exposed fractional crop bounds; run 41066575565 rejected the first synthetic DNG fixture. Neither is represented as a successful release. Documentation-only commits after the tested source revision do not change the IPA.
