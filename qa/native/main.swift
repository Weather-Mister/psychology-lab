import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let renderer = FilmRenderer.shared
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CIContext(options: [.workingColorSpace: cs, .outputColorSpace: cs])
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var results: [[String: Any]] = []
func check(_ name: String, _ condition: Bool, _ details: String = "") {
    results.append(["test": name, "passed": condition, "details": details])
    print("\(condition ? "PASS" : "FAIL") \(name) \(details)")
}
func fixture(_ width: Int, _ height: Int, _ pixel: (Int, Int) -> [Float]) -> CIImage {
    var values = [Float]()
    for y in 0..<height { for x in 0..<width { values += pixel(x,y) } }
    return values.withUnsafeBytes {
        CIImage(bitmapData: Data($0), bytesPerRow: width*16, size: CGSize(width: width,height: height), format: .RGBAf, colorSpace: cs)
    }
}
func pixels(_ image: CIImage) -> [Float] {
    let w = Int(image.extent.width), h = Int(image.extent.height)
    var p = [Float](repeating: 0, count: w*h*4)
    context.render(image, toBitmap: &p, rowBytes: w*16, bounds: image.extent, format: .RGBAf, colorSpace: cs)
    return p
}
func write(_ image: CIImage, _ name: String) throws {
    try context.writePNGRepresentation(of: image, to: output.appendingPathComponent(name+".png"), format: .RGBA8, colorSpace: cs)
}
func render(_ input: CIImage, _ edits: PhotoEdits, _ max: CGFloat? = nil) -> CIImage {
    guard let image = renderer.process(input: input, edits: edits, maxDimension: max) else { fatalError("Renderer failed") }
    return image
}
let ramp = fixture(512,128) { x,_ in let v=Float(x)/511; return [v,v,v,1] }
let neutral = render(ramp,.neutral)
let before = pixels(ramp), after = pixels(neutral)
let neutralError = zip(before,after).map{abs($0-$1)}.max()!
check("neutral ramp identity", neutralError < 0.015, "maximum channel error \(neutralError)")
var look = PhotoEdits.neutral; look.useLook = true
let developed = render(ramp,look)
try write(ramp,"ramp-input"); try write(developed,"ramp-signature-tone")
let tone = pixels(developed)
let minimumToneStep=(1..<512).map{tone[$0*4]-tone[($0-1)*4]}.min()!
check("look ramp monotonic",minimumToneStep >= -0.0001,"minimum step \(minimumToneStep)")
check("look black stays black", tone[0...2].allSatisfy{abs($0)<0.005})
let white = Array(tone[(511*4)..<(511*4+3)])
check("signature creamy highlight bounds", white.max()!-white.min()! > 0.04 && white.max()!-white.min()! < 0.20, "white RGB \(white)")
let hdr = fixture(256,32) { x,_ in let v=0.5+Float(x)/255*3.5;return [v,v,v,1] }
let hdrOut = pixels(render(hdr,look))
check("over-range highlight separation", hdrOut[100*4] > hdrOut[40*4]+0.005, "1.05 and 1.87 input remain distinct")
check("finite output", hdrOut.allSatisfy{$0.isFinite})
let gray = fixture(256,256){_,_ in [0.5,0.5,0.5,1]}
var grain = PhotoEdits.neutral;grain.grain=1
let g1=pixels(render(gray,grain)),g2=pixels(render(gray,grain))
check("deterministic grain", g1 == g2)
let mean=(0..<(256*256)).reduce(Float(0)){$0+g1[$1*4]}/Float(256*256)
check("grain mean neutrality", abs(mean-0.5)<0.005,"mean \(mean)")
check("monochrome grain", stride(from:0,to:g1.count,by:4).allSatisfy{abs(g1[$0]-g1[$0+2])<0.001})
check("grain has variance", (g1.max() ?? 0) > 0.52 && (g1.min() ?? 1)<0.48)
try write(render(gray,grain),"grain-midgray")
var halo = PhotoEdits.neutral;halo.halation=1;halo.halationSize=12
let black=fixture(128,128){_,_ in [0,0,0,1]}
let hb=pixels(render(black,halo))
check("halation leaves black unchanged", stride(from:0,to:hb.count,by:4).allSatisfy{abs(hb[$0])<0.0001})
let edge=fixture(256,256){x,y in x>112 && x<144 && y>64 && y<192 ? [1,1,1,1]:[0,0,0,1]}
let haloImage=render(edge,halo);let hp=pixels(haloImage)
let nearby=(128*256+108)*4
check("halation spreads warm light", hp[nearby]>0.001 && hp[nearby]>hp[nearby+2])
try write(edge,"halation-input");try write(haloImage,"halation-output")
for aspect in CropAspect.allCases {
    var e=PhotoEdits.neutral;e.crop=aspect
    let im=render(ramp,e)
    let ratio=aspect.ratio ?? 4
    check("crop \(aspect.rawValue)",abs(im.extent.width/im.extent.height-ratio)<=1.0/im.extent.height && im.extent.minX==0 && im.extent.minY==0)
}
let resized=render(ramp,.neutral,100)
check("preview bounded dimensions",resized.extent.width==100 && resized.extent.height==25)
let invalid=output.appendingPathComponent("invalid.dng");try Data("not a raw image".utf8).write(to:invalid)
check("invalid RAW rejected",renderer.process(url:invalid,edits:.neutral,maxDimension:nil)==nil)
let inputURL=output.appendingPathComponent("ramp-input.png")
let originalData=try Data(contentsOf:inputURL)
let jpeg=try renderer.export(url:inputURL,edits:.neutral,format:.jpeg)
let decoded=CIImage(contentsOf:jpeg)!
check("JPEG export decodes at full dimensions",decoded.extent.size==ramp.extent.size)
check("source bytes preserved",try Data(contentsOf:inputURL)==originalData)
try FileManager.default.copyItem(at:jpeg,to:output.appendingPathComponent("neutral-export.jpg"))
try FileManager.default.removeItem(at:jpeg)
do {
    let heic=try renderer.export(url:inputURL,edits:.neutral,format:.heic)
    check("HEIC export decodes",CIImage(contentsOf:heic) != nil)
    try FileManager.default.copyItem(at:heic,to:output.appendingPathComponent("neutral-export.heic"))
    try FileManager.default.removeItem(at:heic)
} catch { check("HEIC export",false,error.localizedDescription) }
// Digital RGB swatches validate color management, not a camera's spectral accuracy.
let swatches = fixture(256,64) { x,_ in
    let colors: [[Float]] = [[0.72,0.47,0.34,1],[0.27,0.39,0.64,1],[0.19,0.48,0.25,1],[0.8,0.12,0.09,1]]
    return colors[x/64]
}
let swatchPixels=pixels(render(swatches,.neutral)), expected=pixels(swatches)
let colorError=zip(swatchPixels,expected).map{abs($0-$1)}.max()!
check("neutral digital swatch accuracy",colorError<0.015,"max RGB error \(colorError)")
try write(swatches,"color-input"); try write(render(swatches,.signature),"color-signature")
var shadowEdits=PhotoEdits.neutral;shadowEdits.shadows=1
let shadowResult=pixels(render(ramp,shadowEdits))
check("shadow lift responds",shadowResult[40*4]>after[40*4])
var exposureEdits=PhotoEdits.neutral;exposureEdits.exposure=1
check("positive exposure responds",pixels(render(ramp,exposureEdits))[128*4]>after[128*4])
let cg=context.createCGImage(swatches,from:swatches.extent)!
let rotatedURL=output.appendingPathComponent("orientation-6.jpg")
let dest=CGImageDestinationCreateWithURL(rotatedURL as CFURL,UTType.jpeg.identifier as CFString,1,nil)!
CGImageDestinationAddImage(dest,cg,[kCGImagePropertyOrientation:6] as CFDictionary)
check("orientation fixture encoded",CGImageDestinationFinalize(dest))
let rotated=renderer.process(url:rotatedURL,edits:.neutral,maxDimension:nil)
check("JPEG EXIF orientation applied once",rotated?.extent.width==64 && rotated?.extent.height==256)
for orientation in [1,6] {
    let rawURL=output.appendingPathComponent("synthetic-bayer-o\(orientation).dng")
    let rawData=try Data(contentsOf:rawURL)
    if let raw=renderer.process(url:rawURL,edits:.neutral,maxDimension:nil) {
        check("synthetic Bayer DNG decode o\(orientation)",true)
        let width:CGFloat = orientation==1 ? 640:480
        let height:CGFloat = orientation==1 ? 480:640
        check("DNG orientation o\(orientation)",raw.extent.width==width && raw.extent.height==height,"extent \(raw.extent)")
        try write(raw,"synthetic-raw-developed-o\(orientation)")
        check("RAW source preserved o\(orientation)",try Data(contentsOf:rawURL)==rawData)
    } else { check("synthetic Bayer DNG decode o\(orientation)",false,"Core Image rejected synthetic fixture") }
}
// Screenshot-derived style probe: processed JPEG input, not an original RAW pair.
let referenceURL=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("qa/reference/input.jpg")
for (name,edits) in [("reference-neutral",PhotoEdits.neutral),("reference-signature",PhotoEdits.signature)] {
    if let image=renderer.process(url:referenceURL,edits:edits,maxDimension:nil) { try write(image,name) }
    else { check("reference probe decode",false) }
}
try FileManager.default.copyItem(at:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("qa/reference/target.jpg"),to:output.appendingPathComponent("reference-target.jpg"))
// Guard the reference-density change without relying on a screenshot's exposure.
let gray18=fixture(64,64){_,_ in [0.18,0.18,0.18,1]}
let dense=pixels(render(gray18,look))
check("signature shadow density",dense[0]<0.09 && dense[0]>0.01,"18 percent gray red \(dense[0])")
let coolBlue=fixture(64,64){_,_ in [0.08,0.15,0.28,1]}
let blue=pixels(render(coolBlue,look))
check("dark blue remains blue",blue[2]>blue[0] && blue[2]>blue[1])
let nearBlack=fixture(64,64){_,_ in [0.015,0.015,0.015,1]}
let shadowDetail=pixels(render(nearBlack,look))
check("near-black detail preserved",shadowDetail[1]>0 && shadowDetail[1]<dense[1])
let editsData=try JSONEncoder().encode(PhotoEdits.signature)
check("edits persistence roundtrip",try JSONDecoder().decode(PhotoEdits.self,from:editsData)==PhotoEdits.signature)
try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("results.json"))
if results.contains(where:{$0["passed"] as? Bool == false}) { exit(1) }
