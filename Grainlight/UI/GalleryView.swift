import SwiftUI
import UniformTypeIdentifiers

struct GalleryView: View {
    @EnvironmentObject private var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selected: PhotoRecord?
    @State private var importOpen = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                if library.photos.isEmpty {
                    ContentUnavailableView("No developed photos yet",
                                           systemImage: "camera.aperture",
                                           description: Text("Photographs will appear here after capture. Import DNG files to develop existing RAW photos."))
                    .padding(.top, 90)
                } else {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(library.photos) { photo in
                            Button { selected = photo } label: {
                                ThumbnailView(photo: photo)
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipped()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importOpen = true } label: { Image(systemName: "square.and.arrow.down") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("\(library.photos.count) ORIGINALS")
                    Spacer()
                    Text("RAW FILES NEVER OVERWRITTEN")
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 18)
                .frame(height: 34)
                .background(.black)
            }
        }
        .fullScreenCover(item: $selected) { record in
            PhotoViewer(id: record.id)
        }
        .fileImporter(isPresented: $importOpen,
                      allowedContentTypes: [.image, UTType(filenameExtension: "dng") ?? .data]) { result in
            do { try library.importFile(result.get()) }
            catch { library.lastError = error.localizedDescription }
        }
        .alert("Import failed", isPresented: Binding(get: { library.lastError != nil },
                                                      set: { if !$0 { library.lastError = nil } })) {
            Button("OK") { library.lastError = nil }
        } message: { Text(library.lastError ?? "") }
    }
}

struct ThumbnailView: View {
    @EnvironmentObject private var library: PhotoLibrary
    var photo: PhotoRecord

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = UIImage(contentsOfFile: library.thumbnailURL(for: photo).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color(white: 0.12))
                    .overlay(ProgressView().tint(.white.opacity(0.6)))
            }
            if photo.isRAW {
                Text("DNG")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(.black.opacity(0.6))
                    .padding(5)
            }
        }
    }
}

struct PhotoViewer: View {
    @EnvironmentObject private var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var image: UIImage?
    @State private var showEditor = false
    @State private var showDelete = false
    @State private var share: ShareFile?
    @State private var exporting = false
    @State private var selectedFormat: ExportFormat = .jpeg
    @State private var exportError: String?
    @State private var developmentID = UUID()

    var body: some View {
        Group {
            if let record = library.record(id) {
                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        Spacer()
                        VStack(spacing: 3) {
                            Text(record.createdAt, style: .date).font(.system(size: 12, weight: .semibold))
                            Text(record.isRAW ? "DNG · ORIGINAL KEPT" : "IMAGE · ORIGINAL KEPT")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Button { showDelete = true } label: { Image(systemName: "trash") }
                    }
                    .font(.system(size: 19))
                    .padding(.horizontal, 23)
                    .frame(height: 66)

                    Spacer(minLength: 8)
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else {
                            ProgressView("Developing image…").tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Spacer(minLength: 8)
                    HStack(spacing: 13) {
                        Button { showEditor = true } label: {
                            Label("Tune", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(FilledActionStyle())
                        Menu {
                            Picker("Format", selection: $selectedFormat) {
                                ForEach(ExportFormat.allCases) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }
                            Button("Share \(selectedFormat.rawValue)") { export(record) }
                            Button("Save to Photos") { library.exportToPhotos(record) }
                        } label: {
                            Label(exporting ? "Exporting…" : "Export", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(FilledActionStyle())
                        .disabled(exporting)
                    }
                    .padding(20)
                }
                .background(.black)
                .task(id: record.edits) { develop(record) }
                .fullScreenCover(isPresented: $showEditor, onDismiss: {
                    if let updated = library.record(id) { develop(updated) }
                }) { EditorView(id: id) }
                .sheet(item: $share) { item in ShareSheet(items: [item.url]) }
                .confirmationDialog("Delete this photograph and its RAW original?",
                                    isPresented: $showDelete, titleVisibility: .visible) {
                    Button("Delete permanently", role: .destructive) {
                        library.delete(id)
                        dismiss()
                    }
                }
                .alert("Export failed", isPresented: Binding(get: { exportError != nil },
                                                             set: { if !$0 { exportError = nil } })) {
                    Button("OK") { exportError = nil }
                } message: { Text(exportError ?? "") }
            } else {
                Color.black.ignoresSafeArea().onAppear { dismiss() }
            }
        }
    }

    private func develop(_ record: PhotoRecord) {
        // An older RAW development must never replace a newer edit preview.
        let requestID = UUID()
        developmentID = requestID
        let source = library.sourceURL(for: record)
        let edits = record.edits
        DispatchQueue.global(qos: .userInitiated).async {
            let preview = FilmRenderer.shared.renderPreview(url: source, edits: edits)
            DispatchQueue.main.async {
                guard developmentID == requestID else { return }
                image = preview
            }
        }
    }

    private func export(_ record: PhotoRecord) {
        exporting = true
        library.export(record, format: selectedFormat) { result in
            exporting = false
            switch result {
            case .success(let url): share = ShareFile(url: url)
            case .failure(let error): exportError = error.localizedDescription
            }
        }
    }
}

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct FilledActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(.white)
            .background(Color(white: configuration.isPressed ? 0.30 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
