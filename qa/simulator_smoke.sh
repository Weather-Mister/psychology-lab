#!/bin/bash
set -euo pipefail
OUT="$RUNNER_TEMP/grainlight-qa"
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for a in d["devices"].values() for x in a if "iPhone" in x["name"]))')
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcodebuild build -project Grainlight.xcodeproj -scheme Grainlight -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath "$RUNNER_TEMP/SimulatorBuild" CODE_SIGNING_ALLOWED=NO | tee "$OUT/simulator-build.log"
xcrun simctl install "$DEVICE" "$RUNNER_TEMP/SimulatorBuild/Build/Products/Debug-iphonesimulator/Grainlight.app"
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" com.example.grainlight data)
mkdir -p "$CONTAINER/Documents"
cp "$OUT/synthetic-bayer-o1.dng" "$CONTAINER/Documents/"
xcrun simctl launch "$DEVICE" com.example.grainlight --capture-self-test | tee "$OUT/capture-integration-launch.log"
for ((i=0;i<120;i++)); do
  if test -f "$CONTAINER/Documents/capture-self-test.json"; then break; fi
  sleep 1
done
cp "$CONTAINER/Documents/capture-self-test.json" "$OUT/capture-self-test.json"
python3 - "$OUT/capture-self-test.json" <<'PYTEST'
import json,sys
r=json.load(open(sys.argv[1]))
for t in r['tests']: print(('PASS' if t['passed'] else 'FAIL')+' capture integration: '+t['test'])
assert r['passed'], 'iOS capture-path integration checks failed'
PYTEST
xcrun simctl terminate "$DEVICE" com.example.grainlight
xcrun simctl launch "$DEVICE" com.example.grainlight | tee "$OUT/simulator-launch.log"
sleep 5
xcrun simctl spawn "$DEVICE" launchctl list | grep com.example.grainlight | tee "$OUT/simulator-process.log"
xcrun simctl io "$DEVICE" screenshot "$OUT/simulator-launch.png"
xcrun simctl terminate "$DEVICE" com.example.grainlight
xcrun simctl shutdown "$DEVICE"
