import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

/// An original, independently designed RAW-to-display pipeline.
/// This is NOT the proprietary Chromagraph/Yedlin math.
// CIContext is thread-safe; the lock bounds peak full-resolution rendering memory.
final class FilmRenderer: @unchecked Sendable {
    private let renderLock = NSLock()
    static let shared = FilmRenderer()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let context: CIContext
    private let lookCube: Data

    private init() {
        self.context = CIContext(options: [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace,
            .cacheIntermediates: false
        ])
        self.lookCube = Self.makeLookCube(dimension: 33)
    }

    #if canImport(UIKit)
    func renderPreview(url: URL, edits: PhotoEdits, maxDimension: CGFloat = 1600) -> UIImage? {
        renderLock.lock(); defer { renderLock.unlock() }
        guard let image = process(url: url, edits: edits, maxDimension: maxDimension),
              let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    #endif

    func export(url: URL, edits: PhotoEdits, format: ExportFormat, quality: CGFloat = 0.94) throws -> URL {
        renderLock.lock(); defer { renderLock.unlock() }
        guard let image = process(url: url, edits: edits, maxDimension: nil) else {
            throw RenderError.cannotDecode
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Grainlight-\(UUID().uuidString).\(format.fileExtension)")
        let options: [CIImageRepresentationOption: Any] = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
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

    func process(url: URL, edits: PhotoEdits, maxDimension: CGFloat?) -> CIImage? {
        var input: CIImage
        if url.pathExtension.lowercased() == "dng" {
            // Do not silently fall back to a DNG embedded JPEG.
            guard let raw = CIRAWFilter(imageURL: url) else { return nil }
            raw.boostAmount = 0
            if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
            if raw.isContrastSupported { raw.contrastAmount = 0 }
            if raw.isDetailSupported { raw.detailAmount = 0.45 }
            if raw.isLuminanceNoiseReductionSupported { raw.luminanceNoiseReductionAmount = 0.6 }
            if raw.isColorNoiseReductionSupported { raw.colorNoiseReductionAmount = 0.75 }
            raw.exposure = 0
            // CIRAWFilter applies its EXIF orientation itself; never rotate twice.
            guard let output = raw.outputImage else { return nil }
            input = output
        } else {
            guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                return nil
            }
            input = image
        }

        return process(input: input, edits: edits, maxDimension: maxDimension)
    }

    // Shared by the shipping app and the native macOS controlled-image tests.
    func process(input original: CIImage, edits: PhotoEdits, maxDimension: CGFloat?) -> CIImage? {
        guard !original.extent.isEmpty, !original.extent.isInfinite else { return nil }
        var input = original.transformed(by: CGAffineTransform(translationX: -original.extent.minX, y: -original.extent.minY))
        var renderScale: CGFloat = 1
        if let maxDimension {
            let longestSide = max(input.extent.width, input.extent.height)
            if longestSide > maxDimension {
                let scale = maxDimension / longestSide
                renderScale = scale
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
            // Compress over-range highlights BEFORE the bounded LUT, preserving hue ratios.
            guard let shoulder = Self.shoulderKernel?.apply(extent: extent, arguments: [input]) else { return nil }
            input = shoulder
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
            guard let mask = Self.highlightKernel?.apply(extent: extent, arguments: [input]) else { return nil }
            var glow = filtered("CIGaussianBlur", mask.clampedToExtent(), [kCIInputRadiusKey: edits.halationSize * Double(renderScale)]).cropped(to: extent)
            let strength = min(0.5, edits.halation * 0.25)
            // Scale RGB and alpha together: valid premultiplied color, black remains black.
            glow = filtered("CIColorMatrix", glow, [
                "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: strength * 0.32, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: strength * 0.08, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: strength)
            ])
            input = filtered("CIScreenBlendMode", glow,
                             [kCIInputBackgroundImageKey: input]).cropped(to: extent)
        }

        if edits.sharpen > 0 {
            input = filtered("CISharpenLuminance", input, [
                kCIInputSharpnessKey: edits.sharpen * 0.7
            ])
        }

        if edits.grain > 0 {
            let scale = edits.forcePixelGrain ? 1 : edits.grainSize * Double(renderScale)
            guard let textured = Self.grainKernel?.apply(extent: extent, arguments: [input, max(0.05, scale), edits.grain]) else { return nil }
            input = textured
        }
        input = input.cropped(to: extent)
        if let targetRatio = edits.crop.ratio {
            let bounds = input.extent
            let originalRatio = bounds.width / bounds.height
            let cropWidth = originalRatio > targetRatio ? bounds.height * targetRatio : bounds.width
            let cropHeight = originalRatio > targetRatio ? bounds.height : bounds.width / targetRatio
            let rectangle = CGRect(x: floor(bounds.midX - cropWidth / 2), y: floor(bounds.midY - cropHeight / 2),
                                   width: floor(cropWidth), height: floor(cropHeight))
            input = input.cropped(to: rectangle)
        }
        return input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
    }

    private static let shoulderKernel = CIColorKernel(source: """
        kernel vec4 shoulder(__sample p) {
            vec3 c = max(p.rgb, vec3(0.0));
            float m = max(c.r, max(c.g, c.b));
            float t = 0.7 + 0.3 * (1.0 - exp(-(m - 0.7) / 0.3));
            return vec4(c * (m > 0.7 ? t / max(m, 0.00001) : 1.0), p.a);
        }
        """)
    private static let highlightKernel = CIColorKernel(source: """
        kernel vec4 highlights(__sample p) {
            float y = dot(p.rgb, vec3(0.2126, 0.7152, 0.0722));
            float h = smoothstep(0.72, 1.0, y);
            return vec4(h, h, h, 1.0);
        }
        """)
    private static let grainKernel = CIColorKernel(source: """
        kernel vec4 grain(__sample p, float size, float strength) {
            vec2 cell = floor(destCoord() / size);
            float n = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
            float y = clamp(dot(p.rgb, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
            float weight = 4.0 * y * (1.0 - y);
            return vec4(clamp(p.rgb + vec3(n * strength * 0.12 * weight), 0.0, 1.0), p.a);
        }
        """)

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
            return clamp(pow(v, 1.50) * (1.30 - 0.30 * v))
        }
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let rgb = [Double(r), Double(g), Double(b)].map { $0 / Double(size - 1) }
                    let y = rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
                    let chroma = 0.78 + 0.07 * (1 - y)
                    var colors = rgb.map { filmic(y + ($0 - y) * chroma) }
                    let shadow = pow(1 - y, 2) * y
                    let highlight = pow(y, 1.3)
                    let skyWeight = pow(clamp((y - 0.40) / 0.40), 2)
                    let blueExcess = max(0, rgb[2] - rgb[0] - 0.04) * skyWeight
                    // Warmer pale highlights and blue/green lowlights. Sky blue
                    // shifts toward ivory without stamping a uniform sepia filter.
                    colors[0] = clamp(colors[0] + highlight * 0.10 - shadow * 0.18 + blueExcess * 0.35)
                    colors[1] = clamp(colors[1] + highlight * 0.065)
                    colors[2] = clamp(colors[2] + shadow * 0.06 - highlight * 0.065 - blueExcess * 0.50)
                    // Bright blue sky approaches a luminous cream; dark blues are gated out.
                    let skyMix = clamp(blueExcess * 8)
                    let skyTone = 0.55 + 0.45 * filmic(y)
                    let cream = [clamp(skyTone + 0.055), clamp(skyTone + 0.025), clamp(skyTone - 0.045)]
                    colors = zip(colors, cream).map { $0 * (1 - skyMix) + $1 * skyMix }
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
