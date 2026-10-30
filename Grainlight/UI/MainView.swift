import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = CameraService()
    @State private var showGallery = false
    @State private var showPreferences = false
    @State private var showGrid = false
    @State private var showImport = false
    @State private var showSaved = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                cameraFrame
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(maxHeight: max(240, geo.size.height - 235))
                    .clipped()
                Spacer(minLength: 12)
                lensPicker
                cameraControls
                    .frame(height: 106)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .onAppear {
            camera.onCapture = { data, raw in
                do { try library.saveCapture(data, isRAW: raw) }
                catch { library.lastError = error.localizedDescription }
            }
            camera.requestAndStart()
        }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !showGallery && !showPreferences { camera.requestAndStart() }
            else if phase != .active { camera.stop() }
        }
        .onChange(of: showGallery) { _, open in
            if open { camera.stop() }
            else if scenePhase == .active { camera.requestAndStart() }
        }
        .onChange(of: showPreferences) { _, open in
            if open { camera.stop() }
            else if scenePhase == .active { camera.requestAndStart() }
        }
        .fullScreenCover(isPresented: $showGallery) { GalleryView() }
        .sheet(isPresented: $showPreferences) { PreferencesView() }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [
            .image, UTType(filenameExtension: "dng") ?? .data
        ]) { result in
            switch result {
            case .success(let url):
                do { try library.importFile(url) }
                catch { library.lastError = error.localizedDescription }
            case .failure(let error): library.lastError = error.localizedDescription
            }
        }
        .alert("Camera", isPresented: Binding(get: { camera.errorMessage != nil || library.lastError != nil },
                                               set: { if !$0 { camera.clearError(); library.lastError = nil } })) {
            Button("OK") { camera.clearError(); library.lastError = nil }
        } message: { Text(camera.errorMessage ?? library.lastError ?? "") }
    }

    private var header: some View {
        HStack {
            Button { showPreferences = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 21, weight: .light))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("G R A I N L I G H T")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                Text(camera.rawAvailable ? "RAW  ·  STILL CAMERA" : "STANDARD  ·  STILL CAMERA")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1.3)
            }
            Spacer()
            Button { showGrid.toggle() } label: {
                Image(systemName: showGrid ? "square.grid.3x3.fill" : "square.grid.3x3")
                    .font(.system(size: 21, weight: .light))
                    .frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 15)
        .frame(height: 60)
    }

    private var cameraFrame: some View {
        ZStack {
            CameraPreview(session: camera.session, onTap: camera.focus(at:))
            if showGrid {
                GeometryReader { geometry in
                    Path { path in
                        for multiplier in [1.0, 2.0] {
                            let x = geometry.size.width * multiplier / 3
                            let y = geometry.size.height * multiplier / 3
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                    }
                    .stroke(.white.opacity(0.3), lineWidth: 0.6)
                }
                .allowsHitTesting(false)
            }
            if camera.authorizationDenied {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.largeTitle)
                    Text("Camera access required").font(.headline)
                    Text("Enable camera access in Settings to take photos.")
                        .font(.subheadline).multilineTextAlignment(.center)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            }
        }
        .background(.black)
        .overlay(alignment: .topLeading) {
            Text("FRAME  ·  DEVELOP AFTER EXPOSURE")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1)
                .padding(10)
                .background(.black.opacity(0.35))
                .padding(9)
        }
    }

    private var lensPicker: some View {
        HStack(spacing: 8) {
            ForEach(camera.availableLenses) { lens in
                Button { camera.selectLens(lens) } label: {
                    Text(lens.rawValue)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(width: 50, height: 32)
                        .background(camera.activeLens == lens ? Color(red: 0.82, green: 0.71, blue: 0.55) : Color.white.opacity(0.1))
                        .foregroundStyle(camera.activeLens == lens ? .black : .white)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(height: 42)
    }

    private var cameraControls: some View {
        HStack {
            Button { showGallery = true } label: {
                Group {
                    if let record = library.latest,
                       let thumbnail = UIImage(contentsOfFile: library.thumbnailURL(for: record).path) {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 24, weight: .ultraLight))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 53, height: 53)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.2)))
            }
            Spacer()
            Button { camera.capture() } label: {
                ZStack {
                    Circle().stroke(.white.opacity(0.9), lineWidth: 3).frame(width: 76, height: 76)
                    Circle().fill(.white).frame(width: 63, height: 63)
                    if camera.isCapturing { ProgressView().tint(.black) }
                }
            }
            .disabled(camera.isCapturing || camera.authorizationDenied)
            .accessibilityLabel("Take a RAW photograph")
            Spacer()
            Button { showImport = true } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 23, weight: .light))
                    .frame(width: 53, height: 53)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 29)
    }
}
