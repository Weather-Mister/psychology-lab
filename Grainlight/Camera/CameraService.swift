import AVFoundation
import SwiftUI

/// AVCapture session work stays on its own serial queue; callbacks are delivered on main.
final class CameraService: NSObject, ObservableObject {
    @Published private(set) var authorizationDenied = false
    @Published private(set) var isCapturing = false
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var activeLens: Lens = .wide
    @Published private(set) var rawAvailable = false
    @Published private(set) var captureFormatLabel = "CHECKING CAMERA"
    @Published private(set) var availableLenses: [Lens] = [.wide]

    enum Lens: String, CaseIterable, Identifiable {
        case ultraWide = "0.5×"
        case wide = "1×"
        case telephoto = "Tele"
        var id: String { rawValue }
        var deviceType: AVCaptureDevice.DeviceType {
            switch self {
            case .ultraWide: return .builtInUltraWideCamera
            case .wide: return .builtInWideAngleCamera
            case .telephoto: return .builtInTelephotoCamera
            }
        }
    }

    private static func camera(for lens: Lens) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [lens.deviceType], mediaType: .video, position: .back
        ).devices.first
    }

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.grainlight.camera.session", qos: .userInitiated)
    private var activeInput: AVCaptureDeviceInput?
    private var configured = false
    private var inFlight = false
    private var photoDelegate: PhotoCaptureDelegate?
    private var wantsRunning = false // main-thread lifecycle intent
    var onCapture: ((Data, Bool) -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterrupted), name: AVCaptureSession.wasInterruptedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(interruptionEnded), name: AVCaptureSession.interruptionEndedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(runtimeError(_:)), name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func sessionInterrupted() {
        DispatchQueue.main.async { self.isReady = false }
    }

    @objc private func interruptionEnded() {
        DispatchQueue.main.async { if self.wantsRunning { self.configureAndStart() } }
    }

    @objc private func runtimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        DispatchQueue.main.async {
            self.isReady = false
            if error?.code == .mediaServicesWereReset && self.wantsRunning {
                self.configureAndStart()
            } else {
                self.errorMessage = error?.localizedDescription ?? "Camera session stopped. Reopen the camera to retry."
            }
        }
    }

    func clearError() { errorMessage = nil }

    func requestAndStart() {
        wantsRunning = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationDenied = false
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { DispatchQueue.main.async { self?.authorizationDenied = false; if self?.wantsRunning == true { self?.configureAndStart() } } }
                else { DispatchQueue.main.async { self?.authorizationDenied = true } }
            }
        default: DispatchQueue.main.async { self.authorizationDenied = true }
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                let discovered = Lens.allCases.filter {
                    Self.camera(for: $0) != nil
                }
                DispatchQueue.main.async { self.availableLenses = discovered }
                guard let device = Self.camera(for: .wide),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input), self.session.canAddOutput(self.photoOutput) else {
                    self.session.commitConfiguration()
                    self.report("The rear camera is unavailable.")
                    return
                }
                self.session.addInput(input)
                self.activeInput = input
                self.session.addOutput(self.photoOutput)
                // Prefer minimally processed Bayer RAW. Some devices instead support ProRAW.
                if self.photoOutput.isAppleProRAWSupported {
                    self.photoOutput.isAppleProRAWEnabled = true
                }
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                self.configureBestResolution(for: device)
                self.configured = true
                self.session.commitConfiguration()
                self.updateRawAvailability()
            }
            if !self.session.isRunning { self.session.startRunning() }
            let running = self.session.isRunning
            DispatchQueue.main.async { self.isReady = running }
        }
    }

    func stop() {
        wantsRunning = false
        isReady = false
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isReady = false }
        }
    }

    func selectLens(_ lens: Lens) {
        sessionQueue.async { [weak self] in
            guard let self, self.configured, !self.inFlight, let camera = Self.camera(for: lens),
                  let newInput = try? AVCaptureDeviceInput(device: camera) else { return }
            self.session.beginConfiguration()
            if let old = self.activeInput { self.session.removeInput(old) }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.activeInput = newInput
                DispatchQueue.main.async { self.activeLens = lens }
            } else if let old = self.activeInput {
                self.session.addInput(old)
            }
            if let actual = self.activeInput?.device { self.configureBestResolution(for: actual) }
            if self.photoOutput.isAppleProRAWSupported { self.photoOutput.isAppleProRAWEnabled = true }
            self.session.commitConfiguration()
            self.updateRawAvailability()
        }
    }

    private func configureBestResolution(for device: AVCaptureDevice) {
        let choices = device.activeFormat.supportedMaxPhotoDimensions
        if let best = Self.preferredDimensions(choices) {
            photoOutput.maxPhotoDimensions = best
        }
    }

    func focus(at point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.activeInput?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
            } catch { self?.report(error.localizedDescription) }
        }
    }

    func capture() {
        sessionQueue.async { [weak self] in
            guard let self, self.configured, self.session.isRunning, !self.session.isInterrupted, !self.inFlight,
                  let connection = self.photoOutput.connection(with: .video), connection.isActive else { return }
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            let settings: AVCapturePhotoSettings
            do {
                settings = try Self.makePhotoSettings(
                    rawFormats: self.photoOutput.availableRawPhotoPixelFormatTypes,
                    dimensions: self.photoOutput.maxPhotoDimensions,
                    jpegAvailable: self.photoOutput.availablePhotoCodecTypes.contains(.jpeg))
            } catch { self.report(error.localizedDescription); return }
            self.inFlight = true
            if self.photoOutput.supportedFlashModes.contains(.off) { settings.flashMode = .off }
            DispatchQueue.main.async { self.isCapturing = true }
            let delegate = PhotoCaptureDelegate { [weak self] data, raw, error in
                guard let self else { return }
                self.sessionQueue.async {
                    self.inFlight = false
                    self.photoDelegate = nil
                    DispatchQueue.main.async {
                        self.isCapturing = false
                        if let error { self.errorMessage = error.localizedDescription }
                        else if let data { self.onCapture?(data, raw) }
                        else { self.errorMessage = "The camera returned no image. Please try again." }
                    }
                }
            }
            self.photoDelegate = delegate
            var submissionError: NSError?
            let submitted = GLPerformSafely({
                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }, &submissionError)
            if !submitted {
                self.inFlight = false
                self.photoDelegate = nil
                DispatchQueue.main.async { self.isCapturing = false }
                self.report(submissionError?.localizedDescription ?? "Camera rejected the capture. Reopen the camera and retry.")
            }
        }
    }

    // These functions are exercised using real AVCapturePhotoSettings on iOS Simulator.
    static func preferredDimensions(_ choices: [CMVideoDimensions]) -> CMVideoDimensions? {
        let valid = choices.filter { $0.width > 0 && $0.height > 0 }
        let modest = valid.filter { Int64($0.width) * Int64($0.height) <= 13_000_000 }
        if let best = modest.max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }) { return best }
        return valid.min(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) })
    }

    static func makePhotoSettings(rawFormats: [OSType], dimensions: CMVideoDimensions,
                                  jpegAvailable: Bool) throws -> AVCapturePhotoSettings {
        guard dimensions.width > 0 && dimensions.height > 0 else {
            throw NSError(domain: "Grainlight.Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera resolution is unavailable."])
        }
        let bayer = rawFormats.first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
        let rawFormat = bayer ?? rawFormats.first
        let settings: AVCapturePhotoSettings
        if let rawFormat {
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
            // SDK capturePhoto rules: Bayer RAW requires speed. ProRAW can use quality.
            settings.photoQualityPrioritization = bayer != nil ? .speed : .quality
        } else {
            guard jpegAvailable else {
                throw NSError(domain: "Grainlight.Camera", code: 2, userInfo: [NSLocalizedDescriptionKey: "No supported photo format is available."])
            }
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality
        }
        settings.maxPhotoDimensions = dimensions
        return settings
    }

    private func updateRawAvailability() {
        let formats = photoOutput.availableRawPhotoPixelFormatTypes
        let hasBayer = formats.contains { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
        let label = hasBayer ? "BAYER RAW" : (formats.isEmpty ? "JPEG" : "RAW")
        // Remaining available RAW formats on supported iPhones are Apple ProRAW.
        let hasProRAW = formats.contains { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
        DispatchQueue.main.async {
            self.rawAvailable = !formats.isEmpty
            self.captureFormatLabel = hasBayer ? label : (hasProRAW ? "APPLE PRORAW" : label)
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { self.errorMessage = message }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Data?, Bool, Error?) -> Void
    private var captureData: Data?
    private var isRAW = false
    private var captureError: Error?

    init(completion: @escaping (Data?, Bool, Error?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error { captureError = error; return }
        if let data = photo.fileDataRepresentation() {
            if photo.isRawPhoto || captureData == nil {
                captureData = data
                isRAW = photo.isRawPhoto
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        completion(captureData, isRAW, error ?? captureError)
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }
    func updateUIView(_ view: CameraPreviewUIView, context: Context) {
        view.previewLayer.session = session
        context.coordinator.onTap = onTap
    }
    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject {
        weak var view: CameraPreviewUIView?
        var onTap: (CGPoint) -> Void
        init(onTap: @escaping (CGPoint) -> Void) { self.onTap = onTap }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let location = gesture.location(in: view)
            onTap(view.previewLayer.captureDevicePointConverted(fromLayerPoint: location))
        }
    }
}
