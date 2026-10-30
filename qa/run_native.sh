#!/bin/bash
set -euo pipefail
OUT="${RUNNER_TEMP:-/tmp}/grainlight-qa"
mkdir -p "$OUT"
python3 -c "import base64,pathlib; p=pathlib.Path('qa/reference/target-srgb.b64'); pathlib.Path('qa/reference/target.jpg').write_bytes(base64.b64decode(p.read_text())) if p.exists() else None"
python3 qa/make_dng.py "$OUT"
xcrun swiftc Grainlight/Library/PhotoRecord.swift Grainlight/Imaging/FilmRenderer.swift qa/native/main.swift -o "$OUT/render-tests"
"$OUT/render-tests" "$OUT" | tee "$OUT/test.log"
