#!/bin/bash
# Execute the original shipping renderer unchanged apart from removing its UIKit preview adapter.
set -euo pipefail
OUT="$RUNNER_TEMP/grainlight-qa"
BASE="$OUT/baseline-source"
mkdir -p "$BASE"
git show c261056ff5063b828a2c015320a63119d191315b:Grainlight/Imaging/FilmRenderer.swift > "$BASE/FilmRenderer.swift"
python3 - "$BASE/FilmRenderer.swift" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text().replace('import UIKit','')
a=s.index('    func renderPreview(');b=s.index('    func export(',a)
s=s[:a]+s[b:];p.write_text(s)
PY
cat > "$BASE/main.swift" <<'SWIFT'
import Foundation
import CoreImage
let out=URL(fileURLWithPath:CommandLine.arguments[1])
var edits=PhotoEdits.neutral;edits.useLook=true
for name in ["ramp-input","color-input","halation-input"] {
    let url=try FilmRenderer.shared.export(url:out.appendingPathComponent(name+".png"),edits:edits,format:.jpeg)
    try FileManager.default.copyItem(at:url,to:out.appendingPathComponent(name+"-baseline.jpg"))
    try FileManager.default.removeItem(at:url)
}
let cs=CGColorSpace(name:CGColorSpace.sRGB)!
let ctx=CIContext(options:[.workingColorSpace:cs,.outputColorSpace:cs])
var measurements:[String:Any]=[:]
for name in ["ramp-input-baseline.jpg","ramp-signature-tone.png"] {
    let im=CIImage(contentsOf:out.appendingPathComponent(name))!
    var p=[Float](repeating:0,count:4)
    ctx.render(im,toBitmap:&p,rowBytes:16,bounds:CGRect(x:510,y:64,width:1,height:1),format:.RGBAf,colorSpace:cs)
    measurements[name]=["nearWhiteRGB":Array(p.prefix(3)),"neutralChannelSpread":p.prefix(3).max()!-p.prefix(3).min()!]
}
try JSONSerialization.data(withJSONObject:measurements,options:.prettyPrinted).write(to:out.appendingPathComponent("baseline-comparison.json"))
print(measurements)
SWIFT
xcrun swiftc Grainlight/Library/PhotoRecord.swift "$BASE/FilmRenderer.swift" "$BASE/main.swift" -o "$BASE/baseline-renderer"
"$BASE/baseline-renderer" "$OUT"
