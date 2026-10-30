#!/bin/bash
set -euo pipefail
OUT="${RUNNER_TEMP:-/tmp}/grainlight-qa"
mkdir -p "$OUT"
python3 qa/make_dng.py "$OUT"
xcrun swiftc Grainlight/Library/PhotoRecord.swift Grainlight/Imaging/FilmRenderer.swift qa/native/main.swift -o "$OUT/render-tests"
"$OUT/render-tests" "$OUT" | tee "$OUT/test.log"
