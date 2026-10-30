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
    var onCapture: ((Data, Bool) -> Void)?

    func clearError() { errorMessage = nil }

    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationDenied = false
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { DispatchQueue.main.async { self?.authorizationDenied = false; self?.configureAndStart() } }
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
        if let best = choices.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
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
            self.inFlight = true
            let bayer = self.photoOutput.availableRawPhotoPixelFormatTypes.first {
                AVCapturePhotoOutput.isBayerRAWPixelFormat($0)
            }
            let rawFormat = bayer ?? self.photoOutput.availableRawPhotoPixelFormatTypes.first
            let settings: AVCapturePhotoSettings
            if let rawFormat {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
            } else {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            }
            settings.photoQualityPrioritization = .quality
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            // Never request an unsupported flash mode.
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
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func updateRawAvailability() {
        let supportsRAW = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        DispatchQueue.main.async { self.rawAvailable = supportsRAW }
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
