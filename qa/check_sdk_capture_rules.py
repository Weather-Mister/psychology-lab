"""Assert the installed Apple SDK's Bayer RAW submission contract, preserving source evidence."""
from pathlib import Path
import sys
sdk=Path(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
headers=list(sdk.glob('System/Library/Frameworks/AVFoundation.framework/Headers/AVCapturePhotoOutput.h'))
assert headers, 'Apple SDK header missing'
s=headers[0].read_text();start=s.index('Bayer RAW rules');snippet=s[start:start+1800]
assert 'AVCapturePhotoQualityPrioritizationSpeed' in snippet
(out/'apple-sdk-bayer-rules.txt').write_text(str(headers[0])+'\n'+snippet)
print(snippet)
