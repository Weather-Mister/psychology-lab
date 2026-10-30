import Foundation
import CoreGraphics

enum CropAspect: String, Codable, CaseIterable, Identifiable {
    case original = "Original"
    case square = "1:1"
    case portrait = "4:5"
    case classic = "3:2"
    case wide = "16:9"
    var id: String { rawValue }
    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .square: return 1
        case .portrait: return 4.0 / 5.0
        case .classic: return 3.0 / 2.0
        case .wide: return 16.0 / 9.0
        }
    }
}

struct PhotoEdits: Codable, Equatable {
    var exposure: Double = 0
    var contrast: Double = 1.0
    var highlights: Double = 0
    var shadows: Double = 0
    var blacks: Double = 0
    var warmth: Double = 0
    var tint: Double = 0
    var saturation: Double = 1
    var grain: Double = 0.55
    var grainSize: Double = 1
    var forcePixelGrain: Bool = false
    var halation: Double = 0.38
    var halationSize: Double = 16
    var sharpen: Double = 0.15
    var useLook: Bool = true
    var crop: CropAspect = .original

    static let signature = PhotoEdits()
    static let neutral = PhotoEdits(grain: 0, halation: 0, sharpen: 0, useLook: false)
}

struct PhotoRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var filename: String
    var isRAW: Bool
    var edits: PhotoEdits

    var fileExtension: String { URL(fileURLWithPath: filename).pathExtension.uppercased() }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPEG"
    case heic = "HEIC"
    var id: String { rawValue }
    var fileExtension: String { self == .heic ? "heic" : "jpg" }
}
