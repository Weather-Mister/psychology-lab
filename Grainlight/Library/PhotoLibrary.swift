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
    private var metadataLoadFailed = false
    private var thumbnailGeneration: [UUID: UUID] = [:]

    init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrainlightPhotos", isDirectory: true)
        indexURL = root.appendingPathComponent("library.json")
        do {
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            if files.fileExists(atPath: indexURL.path) {
                let data = try Data(contentsOf: indexURL)
                photos = try JSONDecoder().decode([PhotoRecord].self, from: data).sorted { $0.createdAt > $1.createdAt }
            }
        } catch {
            metadataLoadFailed = true
            lastError = "Could not open the photo library. Existing files are preserved: \(error.localizedDescription)"
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
        guard !metadataLoadFailed else { throw ImportError.libraryUnavailable }
        let id = UUID()
        let file = "\(id.uuidString).\(isRAW ? "dng" : "jpg")"
        try data.write(to: root.appendingPathComponent(file), options: .atomic)
        let newRecord = PhotoRecord(id: id, createdAt: Date(), filename: file,
                                    isRAW: isRAW, edits: .signature)
        photos.insert(newRecord, at: 0)
        do { try saveIndex() }
        catch {
            photos.removeAll { $0.id == id }
            try? files.removeItem(at: root.appendingPathComponent(file))
            throw error
        }
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
        guard !metadataLoadFailed else { throw ImportError.libraryUnavailable }
        let id = UUID()
        let file = "\(id.uuidString).\(ext)"
        try files.copyItem(at: chosenURL, to: root.appendingPathComponent(file))
        let newRecord = PhotoRecord(id: id, createdAt: Date(), filename: file,
                                    isRAW: ext == "dng", edits: .signature)
        photos.insert(newRecord, at: 0)
        do { try saveIndex() }
        catch {
            photos.removeAll { $0.id == id }
            try? files.removeItem(at: root.appendingPathComponent(file))
            throw error
        }
        generateThumbnail(for: newRecord)
        return newRecord
    }

    func update(_ id: UUID, edits: PhotoEdits) {
        guard let i = photos.firstIndex(where: { $0.id == id }) else { return }
        let previous = photos[i].edits
        photos[i].edits = edits
        do { try saveIndex() }
        catch { photos[i].edits = previous; lastError = error.localizedDescription; return }
        generateThumbnail(for: photos[i])
    }

    func delete(_ id: UUID) {
        guard let record = record(id) else { return }
        let previous = photos
        photos.removeAll { $0.id == id }
        do { try saveIndex() }
        catch { photos = previous; lastError = error.localizedDescription; return }
        thumbnailGeneration.removeValue(forKey: id)
        do {
            try files.removeItem(at: sourceURL(for: record))
            if files.fileExists(atPath: thumbnailURL(for: record).path) {
                try files.removeItem(at: thumbnailURL(for: record))
            }
        } catch { lastError = "Photo removed from gallery, but file cleanup failed: \(error.localizedDescription)" }
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
                        try? FileManager.default.removeItem(at: url)
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

    private func saveIndex() throws {
        guard !metadataLoadFailed else { throw ImportError.libraryUnavailable }
        let encoded = try JSONEncoder().encode(photos)
        try encoded.write(to: indexURL, options: .atomic)
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
        case unsupported, libraryUnavailable
        var errorDescription: String? {
            switch self {
            case .unsupported: return "Supported formats: DNG, JPEG, HEIC, PNG and TIFF."
            case .libraryUnavailable: return "Library metadata could not be opened. Existing originals were preserved."
            }
        }
    }
}
