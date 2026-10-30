"""Camera/session code review checks; not a replacement for device testing."""
from pathlib import Path
s=(Path(__file__).resolve().parents[1]/'Grainlight/Camera/CameraService.swift').read_text()
checks={
    'permission gate': 'AVCaptureDevice.authorizationStatus' in s,
    'capture queue serialization': 'sessionQueue.async' in s,
    'single capture guard': '!self.inFlight' in s,
    'RAW requested on supported devices': 'AVCapturePhotoSettings(rawPixelFormatType: rawFormat)' in s,
    'JPEG fallback': 'AVVideoCodecType.jpeg' in s,
    'RAW identification': 'photo.isRawPhoto' in s,
    'real lens switching': 'self.session.removeInput(old)' in s,
    'focus coordinate conversion': 'captureDevicePointConverted(fromLayerPoint:' in s,
    'capture callback': 'didFinishCaptureFor resolvedSettings:' in s,
}
for k,v in checks.items(): print(('PASS' if v else 'FAIL')+' camera: '+k)
assert all(checks.values())
