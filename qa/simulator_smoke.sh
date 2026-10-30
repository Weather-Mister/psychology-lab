#!/bin/bash
set -euo pipefail
OUT="$RUNNER_TEMP/grainlight-qa"
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for a in d["devices"].values() for x in a if "iPhone" in x["name"]))')
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcodebuild build -project Grainlight.xcodeproj -scheme Grainlight -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath "$RUNNER_TEMP/SimulatorBuild" CODE_SIGNING_ALLOWED=NO | tee "$OUT/simulator-build.log"
xcrun simctl install "$DEVICE" "$RUNNER_TEMP/SimulatorBuild/Build/Products/Debug-iphonesimulator/Grainlight.app"
xcrun simctl launch "$DEVICE" com.example.grainlight | tee "$OUT/simulator-launch.log"
sleep 5
xcrun simctl spawn "$DEVICE" launchctl list | grep com.example.grainlight | tee "$OUT/simulator-process.log"
xcrun simctl io "$DEVICE" screenshot "$OUT/simulator-launch.png"
xcrun simctl terminate "$DEVICE" com.example.grainlight
xcrun simctl shutdown "$DEVICE"
