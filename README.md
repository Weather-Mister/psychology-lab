# Grainlight — native iPhone RAW camera

Independent open-source cinematic RAW photography app. This is an original project, not the proprietary Chromagraph implementation.

**Build without a Mac:** Open [GitHub Actions](https://github.com/Weather-Mister/psychology-lab/actions/workflows/build-ipa.yml), run **Build Grainlight IPA**, and download the **Grainlight-unsigned-IPA** artifact when the build succeeds. Extract the downloaded ZIP to obtain `Grainlight-unsigned.ipa`.

**Install on iPhone:** The compiled artifact is *unsigned*, so it cannot be installed directly by opening it on iOS. Sign it using a compatible sideloading tool (such as AltStore/Sideloadly with a Windows computer) or run the optional [signed-IPA workflow](https://github.com/Weather-Mister/psychology-lab/actions/workflows/build-signed-ipa.yml) after securely configuring Apple Developer signing certificates, profile and bundle ID as repository secrets. Never commit private signing files. An Apple Developer membership is generally required for ad hoc distribution.

## Features
- Native AVFoundation RAW DNG capture when available, JPEG fallback, physical lens switching, tap-to-focus
- Core Image original cinematic processing (tone, color, film grain, halation)
- Non-destructive RAW gallery and editor; original source preserved
- Import existing DNG/JPEG/HEIC; JPEG and HEIC exports; optional Photos auto-export
- iOS 17+; SwiftUI

## Status
This app is compiled automatically on a GitHub-hosted macOS runner; physical-device RAW capture and exact Chromagraph image fidelity have not been validated. Refer to `QA_REPORT.md` for known test limitations.

## Repository safety
Your former psychology project is preserved in [backup-psychology-before-grainlight-2026-10-30](https://github.com/Weather-Mister/psychology-lab/tree/backup-psychology-before-grainlight-2026-10-30).
