import Foundation
import Photos
import UIKit
import Combine

@MainActor
final class PhotoLibrary: ObservableObject {
    @Published private(set) var photos: [PhotoRecord] = []
    @Published var lastError: String?

    private let root: URL
    private let indexURL: URL
    private let files: FileManager = .default
    private let renderer = FilmRenderer.shared
    private var thumbnailGeneration: [UUID: UUID] = [:]

    init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrainlightPhotos", isDirectory: true)
        indexURL = root.appendingPathComponent("library.json")
        try? files.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([PhotoRecord].self, from: data) {
            photos = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var latest: PhotoRecord? { photos.first }
    func record(_ id: UUID) -> PhotoRecord? { photos.first { $0.id == id } }
    func sourceURL(for record: PhotoRecord) -> URL { root.appendingPathComponent(record.filename) }
    func thumbnailURL(for record: PhotoRecord) -> URL {
        root.appendingPathComponent("\(record.id.uuidString)-thumb.jpg")
    }

    @discardableResult
    func saveCapture(_ data: Data, isRAW: Bool) throws -> PhotoRecord {
        let id = UUID()
        let file = "\(id.uuidString).\(isRAW ? "dng" : "jpg")"
        try data.write(to: root.appendingPathComponent(file), options: .atomic)
        let newRecord = PhotoRecord(id: id, createdAt: Date(), filename: file,
                                    isRAW: isRAW, edits: .signature)
        photos.insert(newRecord, at: 0)
        saveIndex()
        generateThumbnail(for: newRecord)
        if UserDefaults.standard.bool(forKey: "autoExport") {
            exportToPhotos(newRecord)
        }
        return newRecord
    }

    @discardableResult
    func importFile(_ chosenURL: URL) throws -> PhotoRecord {
        let scoped = chosenURL.startAccessingSecurityScopedResource()
        defer { if scoped { chosenURL.stopAccessingSecurityScopedResource() } }
        let ext = chosenURL.pathExtension.lowercased()
        guard ["dng", "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff"].contains(ext) else {
            throw ImportError.unsupported
        }
        let id = UUID()
        let file = "\(id.uuidString).\(ext)"
        try files.copyItem(at: chosenURL, to: root.appendingPathComponent(file))
        let newRecord = PhotoRecord(id: id, createdAt: Date(), filename: file,
                                    isRAW: ext == "dng", edits: .signature)
        photos.insert(newRecord, at: 0)
        saveIndex()
        generateThumbnail(for: newRecord)
        return newRecord
    }

    func update(_ id: UUID, edits: PhotoEdits) {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[i].edits = edits
        saveIndex()
        generateThumbnail(for: photos[i])
    }

    func delete(_ id: UUID) {
        guard let record = record(id) else { return }
        try? files.removeItem(at: sourceURL(for: record))
        try? files.removeItem(at: thumbnailURL(for: record))
        photos.removeAll { $0.id == id }
        thumbnailGeneration.removeValue(forKey: id)
        saveIndex()
    }

    func export(_ record: PhotoRecord, format: ExportFormat, completion: @escaping (Result<URL, Error>) -> Void) {
        let url = sourceURL(for: record)
        let edits = record.edits
        DispatchQueue.global(qos: .userInitiated).async { [renderer] in
            let result = Result { try renderer.export(url: url, edits: edits, format: format) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func exportToPhotos(_ record: PhotoRecord) {
        let format: ExportFormat = UserDefaults.standard.string(forKey: "exportFormat") == "HEIC" ? .heic : .jpeg
        export(record, format: format) { [weak self] result in
            switch result {
            case .failure(let error): self?.lastError = error.localizedDescription
            case .success(let url):
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    guard status == .authorized || status == .limited else {
                        DispatchQueue.main.async { self?.lastError = "Photo Library access was denied." }
                        return
                    }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                    }, completionHandler: { success, error in
                        if !success {
                            DispatchQueue.main.async { self?.lastError = error?.localizedDescription ?? "Failed to save to Photos." }
                        }
                        try? FileManager.default.removeItem(at: url)
                    })
                }
            }
        }
    }

    private func saveIndex() {
        guard let encoded = try? JSONEncoder().encode(photos) else { return }
        do { try encoded.write(to: indexURL, options: .atomic) }
        catch { lastError = "Couldn't save photo metadata: \(error.localizedDescription)" }
    }

    private func generateThumbnail(for record: PhotoRecord) {
        let generation = UUID()
        thumbnailGeneration[record.id] = generation
        let source = sourceURL(for: record)
        let destination = thumbnailURL(for: record)
        let edits = record.edits
        DispatchQueue.global(qos: .utility).async { [renderer] in
            guard let image = renderer.renderPreview(url: source, edits: edits, maxDimension: 650),
                  let data = image.jpegData(compressionQuality: 0.82) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.thumbnailGeneration[record.id] == generation else { return }
                // Writing on main is small (650px JPEG); it prevents stale
                // asynchronous renders from replacing the current thumbnail.
                do { try data.write(to: destination, options: .atomic) }
                catch { self.lastError = error.localizedDescription }
                self.objectWillChange.send()
            }
        }
    }

    enum ImportError: LocalizedError {
        case unsupported
        var errorDescription: String? { "Supported formats: DNG, JPEG, HEIC, PNG and TIFF." }
    }
}
