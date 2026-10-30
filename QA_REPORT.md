# Grainlight v0.2 — QA and reference comparison

## What was inspected

Three independent scripted reviews were performed against the current source:

- `qa/qa_camera.py`: permission state, serialized capture sessions, single capture guard, RAW settings, lens switch, focus coordinate conversion and JPEG fallback.
- `qa/qa_gallery.py`: original-preserving edits, persistence, image export, imports and rejection of stale asynchronous renders.
- `qa/qa_look.py`: RAW-first/Core Image pipeline presence and finite, monotonic, low-key tone math.

The scripts all pass. These are **static and numerical inspections**, not iPhone device playtests. Linux Swift syntax parsing passes; UIKit/AVFoundation compilation has **not** been verified locally. GitHub Actions is configured to do the first real macOS Xcode build after the project is pushed.

## Fixes from the review

1. Reduced excessive midtone lifting in the signature filmic look.
2. Made gallery image development discard stale results from slower earlier requests.
3. Prevented older thumbnail renders from overwriting newer ones, including after deletion.
4. Added a generation guard to the slider editor.
5. Added gallery import error presentation.
6. Paused the live camera session while the gallery/settings are shown or when the app is backgrounded.
7. Added a checked-in shared scheme for reproducible CI builds.
8. Added separate workflows for unsigned downloadable IPA and Apple ad hoc signed installable IPA.

## Chromagraph comparison from the supplied screenshots

In the example showing two photographs of the same city, the posted Chromagraph rendering is dramatically darker, warmer and lower-key. Measured from the screenshot crops (not from original camera files):

| Measure | Posted default-camera photograph | Posted Chromagraph photograph | LUT-only proxy on posted JPEG |
| --- | ---: | ---: | ---: |
| Mean screen luminance (0–1) | 0.473 | 0.312 | 0.412 |
| 10th-percentile luminance | 0.209 | 0.063 | 0.144 |
| 90th-percentile luminance | 0.747 | 0.848 | 0.706 |

The proxy was created by numerically reproducing the updated LUT calculation on the **already processed, resized screenshot**, and intentionally excludes RAW decoding, exposure setting, texture, and Core Image compositing. It is **not a screenshot of the actual iOS application** or a calibrated measure of its RAW output. Its results expose a remaining difference: the target looks deeper in the shadows and much warmer in sky highlights than the updated LUT-only result. The exact signature look is unverified on RAW source photographs.

The screenshot examples depict street daylight, low-light interiors, moody night, skin/objects, grain and bright halation. A comprehensive device test matrix should cover these scenes, plus:

- 12 MP and 48 MP resolution support by physical lens, including fallback behavior.
- Camera permission denied/changed during use; background/foreground; immediate gallery reopen.
- Rapid captures; repeated edits; close while rendering; deletion while thumbnail generation is running.
- RAW orientation, import from Files, original DNG checksum before/after edits.
- Full-resolution JPEG/HEIC metadata and fidelity; auto-export authorization.
- Low light highlights/shadows and memory/performance at 48 MP.

## Release state

- **Passed:** Swift syntax parse; project/asset structure; static QA tests; look curve numerical invariants; workflows parse as YAML.
- **Not yet verified:** Xcode linking on macOS, iOS simulator launch, real iPhone capture, RAW DNG decoding, HEIC export on hardware, signed distribution, or visual matching against an original RAW pair.
- **Signatures:** `Grainlight-unsigned.ipa` is a ZIP-shaped iOS application archive. It **cannot be installed as-is** on stock iOS; a side-loading tool must sign it, or the separate signed workflow must be run with valid Apple credentials and a provisioning profile covering the device.
