import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit

/// An original, independently designed RAW-to-display pipeline.
/// This is NOT the proprietary Chromagraph/Yedlin math.
final class FilmRenderer {
    static let shared = FilmRenderer()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let context: CIContext
    private let lookCube: Data

    private init() {
        self.context = CIContext(options: [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace,
            .cacheIntermediates: true
        ])
        self.lookCube = Self.makeLookCube(dimension: 33)
    }

    func renderPreview(url: URL, edits: PhotoEdits, maxDimension: CGFloat = 1600) -> UIImage? {
        guard let image = process(url: url, edits: edits, maxDimension: maxDimension),
              let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    func export(url: URL, edits: PhotoEdits, format: ExportFormat, quality: CGFloat = 0.94) throws -> URL {
        guard let image = process(url: url, edits: edits, maxDimension: nil) else {
            throw RenderError.cannotDecode
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Grainlight-\(UUID().uuidString).\(format.fileExtension)")
        let options: [CIImageRepresentationOption: Any] = [.lossyCompressionQuality: quality]
        let data: Data?
        switch format {
        case .jpeg:
            data = context.jpegRepresentation(of: image, colorSpace: colorSpace, options: options)
        case .heic:
            data = context.heifRepresentation(of: image, format: .RGBA8,
                                              colorSpace: colorSpace, options: options)
        }
        guard let data else { throw RenderError.cannotExport }
        try data.write(to: output, options: .atomic)
        return output
    }

    private func process(url: URL, edits: PhotoEdits, maxDimension: CGFloat?) -> CIImage? {
        var input: CIImage
        if url.pathExtension.lowercased() == "dng",
           let raw = CIRAWFilter(imageURL: url) {
            // Disable Apple's usual RAW boost/creative local contrast.
            // Sensor demosaic / white balance are still performed by Core Image.
            raw.boostAmount = 0
            // boostShadowAmount is ignored when boostAmount == 0.
            raw.localToneMapAmount = 0
            raw.contrastAmount = 0
            raw.detailAmount = 0.45
            raw.luminanceNoiseReductionAmount = 0.6
            raw.colorNoiseReductionAmount = 0.75
            raw.exposure = 0
            guard let output = raw.outputImage else { return nil }
            if let exif = raw.properties[kCGImagePropertyOrientation] as? NSNumber {
                input = output.oriented(forExifOrientation: exif.int32Value)
            } else {
                input = output
            }
        } else {
            guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                return nil
            }
            input = image
        }

        if let maxDimension {
            let longestSide = max(input.extent.width, input.extent.height)
            if longestSide > maxDimension {
                let scale = maxDimension / longestSide
                input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }
        let extent = input.extent

        // Exposure before the bespoke color/tone rendering.
        input = filtered("CIExposureAdjust", input, [kCIInputEVKey: edits.exposure])
        input = filtered("CIHighlightShadowAdjust", input, [
            "inputHighlightAmount": max(0.15, min(1.8, 1 + edits.highlights * 0.7)),
            "inputShadowAmount": edits.shadows * 0.65
        ])
        input = filtered("CIColorControls", input, [
            kCIInputContrastKey: edits.contrast,
            kCIInputSaturationKey: edits.saturation,
            kCIInputBrightnessKey: -edits.blacks * 0.14
        ])

        if edits.useLook {
            input = filtered("CIColorCube", input, [
                "inputCubeDimension": 33,
                "inputCubeData": lookCube
            ])
        }

        // A subtle warm/cool split with magenta/green tint control.
        if edits.warmth != 0 || edits.tint != 0 {
            input = filtered("CIColorMatrix", input, [
                "inputRVector": CIVector(x: 1 + edits.warmth * 0.065, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1 - edits.tint * 0.065, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 - edits.warmth * 0.075, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ])
        }

        if edits.halation > 0 {
            // Isolate bright pixels, blur, tint red-orange and screen-composite.
            var glow = filtered("CIColorControls", input, [
                kCIInputContrastKey: 2.3,
                kCIInputBrightnessKey: -0.33,
                kCIInputSaturationKey: 0.25
            ])
            glow = filtered("CIGaussianBlur", glow, [kCIInputRadiusKey: edits.halationSize])
            glow = filtered("CIColorMatrix", glow, [
                "inputRVector": CIVector(x: 0.75, y: 0.12, z: 0.05, w: 0),
                "inputGVector": CIVector(x: 0.25, y: 0.12, z: 0.02, w: 0),
                "inputBVector": CIVector(x: 0.06, y: 0.03, z: 0.01, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: edits.halation * 0.38)
            ])
            input = filtered("CIScreenBlendMode", glow.cropped(to: extent),
                             [kCIInputBackgroundImageKey: input]).cropped(to: extent)
        }

        if edits.sharpen > 0 {
            input = filtered("CISharpenLuminance", input, [
                kCIInputSharpnessKey: edits.sharpen * 0.7
            ])
        }

        if edits.grain > 0 {
            let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
            let scale = edits.forcePixelGrain ? 1 : CGFloat(edits.grainSize)
            let grain = noise.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let mono = filtered("CIColorMatrix", grain, [
                "inputRVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
                "inputGVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
                "inputBVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: min(0.5, edits.grain * 0.24))
            ]).cropped(to: extent)
            input = filtered("CIOverlayBlendMode", grainIsOpaque(mono),
                             [kCIInputBackgroundImageKey: input]).cropped(to: extent)
        }
        input = input.cropped(to: extent)
        if let targetRatio = edits.crop.ratio {
            let bounds = input.extent
            let originalRatio = bounds.width / bounds.height
            let cropWidth = originalRatio > targetRatio ? bounds.height * targetRatio : bounds.width
            let cropHeight = originalRatio > targetRatio ? bounds.height : bounds.width / targetRatio
            let rectangle = CGRect(x: bounds.midX - cropWidth / 2, y: bounds.midY - cropHeight / 2,
                                   width: cropWidth, height: cropHeight)
            input = input.cropped(to: rectangle)
        }
        return input
    }

    private func grainIsOpaque(_ image: CIImage) -> CIImage { image }

    private func filtered(_ name: String, _ input: CIImage, _ additional: [String: Any]) -> CIImage {
        guard let filter = CIFilter(name: name) else { return input }
        filter.setValue(input, forKey: kCIInputImageKey)
        for (key, value) in additional { filter.setValue(value, forKey: key) }
        return filter.outputImage ?? input
    }

    /// 33^3 original filmic LUT. Smooth toe and shoulder, muted blues, warm highlight / cool shadow split.
    /// Floating point LUT is built once and applied to RAW-derived image, not a JPEG preset.
    private static func makeLookCube(dimension size: Int) -> Data {
        var floats = [Float]()
        floats.reserveCapacity(size * size * size * 4)
        func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
        func filmic(_ x: Double) -> Double {
            // Restrained shadows and low-key midtones with a soft highlight shoulder.
            // An original approximation, calibrated by visual comparison only.
            let v = clamp(x)
            return clamp(pow(v, 1.28) * (1.06 - 0.11 * v))
        }
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let rgb = [Double(r), Double(g), Double(b)].map { $0 / Double(size - 1) }
                    let y = rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
                    let chroma = 0.78 + 0.07 * (1 - y)
                    var colors = rgb.map { filmic(y + ($0 - y) * chroma) }
                    let shadow = pow(1 - y, 2)
                    let highlight = pow(y, 1.3)
                    let blueExcess = max(0, rgb[2] - rgb[0]) * highlight
                    // Warmer pale highlights and blue/green lowlights. Sky blue
                    // shifts toward ivory without stamping a uniform sepia filter.
                    colors[0] = clamp(colors[0] + highlight * 0.20 + blueExcess * 0.14)
                    colors[1] = clamp(colors[1] + highlight * 0.025)
                    colors[2] = clamp(colors[2] + shadow * 0.012 - highlight * 0.19 - blueExcess * 0.18)
                    floats.append(contentsOf: colors.map { Float($0) })
                    floats.append(1)
                }
            }
        }
        return floats.withUnsafeBytes { Data($0) }
    }

    enum RenderError: LocalizedError {
        case cannotDecode, cannotExport
        var errorDescription: String? {
            switch self {
            case .cannotDecode: return "Couldn't decode this RAW or image file."
            case .cannotExport: return "The device couldn't encode the edited image."
            }
        }
    }
}
