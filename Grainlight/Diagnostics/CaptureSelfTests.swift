#if DEBUG
import SwiftUI
import AVFoundation
import CoreVideo

struct CaptureSelfTestView: View {
    @State private var status = "Running capture-path integration checks"
    var body: some View { Text(status).task { status = await CaptureSelfTests.run() } }
}

@MainActor
enum CaptureSelfTests {
    static func run() async -> String {
        var results = [[String: Any]]()
        func check(_ name: String, _ pass: Bool) { results.append(["test": name, "passed": pass]) }
        UserDefaults.standard.set(false, forKey: "autoExport")
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let twelve = CMVideoDimensions(width: 4032, height: 3024)
            let fortyEight = CMVideoDimensions(width: 8064, height: 6048)
            check("prefer supported 12MP over 48MP", CameraService.preferredDimensions([fortyEight,twelve])?.width == twelve.width)
            check("reject invalid dimensions", CameraService.preferredDimensions([CMVideoDimensions(width:0,height:0)]) == nil)
            let bayer = kCVPixelFormatType_14Bayer_RGGB
            check("fixture is recognized as Bayer", AVCapturePhotoOutput.isBayerRAWPixelFormat(bayer))
            let raw = try CameraService.makePhotoSettings(rawFormats:[bayer],dimensions:twelve,jpegAvailable:true)
            check("Bayer uses speed (SDK requirement)",raw.photoQualityPrioritization == .speed)
            check("Bayer request retains RAW pixel format",raw.rawPhotoPixelFormatType == bayer)
            check("RAW request uses configured dimensions",raw.maxPhotoDimensions.width == twelve.width)
            let second = try CameraService.makePhotoSettings(rawFormats:[bayer],dimensions:twelve,jpegAvailable:true)
            check("each capture has fresh unique settings",raw.uniqueID != second.uniqueID)
            let jpeg = try CameraService.makePhotoSettings(rawFormats:[],dimensions:twelve,jpegAvailable:true)
            check("JPEG fallback uses processed format",jpeg.rawPhotoPixelFormatType == 0 && jpeg.format != nil)
            check("JPEG can use quality",jpeg.photoQualityPrioritization == .quality)
            do { _ = try CameraService.makePhotoSettings(rawFormats:[],dimensions:twelve,jpegAvailable:false); check("no codec rejected",false) }
            catch { check("no codec rejected",true) }
            do { _ = try CameraService.makePhotoSettings(rawFormats:[bayer],dimensions:CMVideoDimensions(width:0,height:0),jpegAvailable:true); check("invalid resolution rejected",false) }
            catch { check("invalid resolution rejected",true) }
            check("Objective-C submission exception becomes NSError",GLExceptionBoundarySelfTest())
            var noError: NSError?
            check("exception boundary normal success",GLPerformSafely({},&noError) && noError == nil)

            let library = PhotoLibrary()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let fixture = UIGraphicsImageRenderer(size:CGSize(width:4032,height:3024),format:format).image { c in
                UIColor.darkGray.setFill();c.fill(CGRect(x:0,y:0,width:4032,height:3024))
                UIColor.orange.setFill();c.fill(CGRect(x:0,y:0,width:1500,height:2000))
            }
            let data = fixture.jpegData(compressionQuality:0.9)!
            var ids=[UUID]()
            for _ in 0..<5 { ids.append(try library.saveCapture(data,isRAW:false).id) }
            check("five 12MP capture payloads persist",ids.allSatisfy{library.record($0) != nil})
            let first = library.record(ids[0])!
            let source = library.sourceURL(for:first)
            let original = try Data(contentsOf:source)
            library.update(first.id,edits:.neutral)
            check("capture survives index reload",PhotoLibrary().record(first.id)?.edits == .neutral)
            let preview = await Task.detached { FilmRenderer.shared.renderPreview(url:source,edits:.neutral,maxDimension:650) }.value
            check("12MP capture develops on iOS",preview != nil && max(preview!.size.width,preview!.size.height) <= 650)
            let exported: Result<URL,Error> = await withCheckedContinuation { continuation in
                library.export(library.record(first.id)!,format:.jpeg){continuation.resume(returning:$0)}
            }
            let exportURL = try exported.get()
            check("capture exports full resolution JPEG",UIImage(contentsOfFile:exportURL.path)?.size == CGSize(width:4032,height:3024))
            try FileManager.default.removeItem(at:exportURL)
            check("capture source bytes unchanged by edits/export",try Data(contentsOf:source) == original)
            for _ in 0..<200 {
                if FileManager.default.fileExists(atPath:library.thumbnailURL(for:library.record(first.id)!).path) { break }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            check("capture produces thumbnail",UIImage(contentsOfFile:library.thumbnailURL(for:library.record(first.id)!).path) != nil)
            let rawURL=documents.appendingPathComponent("synthetic-bayer-o1.dng")
            let rawData=try Data(contentsOf:rawURL)
            let rawRecord=try library.saveCapture(rawData,isRAW:true);ids.append(rawRecord.id)
            let rawSource=library.sourceURL(for:rawRecord)
            let savedRawData=try Data(contentsOf:rawSource)
            check("RAW capture payload retained as DNG",rawSource.pathExtension == "dng" && savedRawData == rawData)
            let rawPreview=await Task.detached { FilmRenderer.shared.renderPreview(url:rawSource,edits:.signature,maxDimension:650) }.value
            check("synthetic RAW capture develops on iOS",rawPreview != nil)
            for id in ids { library.delete(id) }
            check("delete persists",PhotoLibrary().photos.isEmpty)
            check("no library errors",library.lastError == nil)
        } catch { results.append(["test":"integration threw: \(error)","passed":false]) }
        let passed=results.allSatisfy{$0["passed"] as? Bool == true}
        let report:[String:Any] = ["passed":passed,"tests":results,"scope":"Real iOS settings objects and injected JPEG/DNG payloads. No sensor capture on Simulator."]
        if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {
            try? data.write(to:documents.appendingPathComponent("capture-self-test.json"),options:.atomic)
        }
        return passed ? "Capture-path checks passed" : "Capture-path checks failed"
    }
}
#endif
