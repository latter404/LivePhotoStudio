// Portions based on Revive by Edward Shen, licensed under MIT.
// Source: https://github.com/Ed3110/Revive/tree/feb46245b5c6a1d3982909916832a02d71a33828
// See Licenses/Revive-MIT.txt and Licenses/THIRD_PARTY_NOTICES.txt.
import XCTest
import AVFoundation
import Photos
import ImageIO
import UniformTypeIdentifiers
@testable import LivePhotoStudio

/// End-to-end tests for the conversion engine. Each test generates a real H.264
/// video on the fly (no fixture files in the repo), runs the engine, then checks
/// the output the same way the app does — via Verifier.
final class EngineTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReviveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // Proves the whole pipeline: a converted pair passes every Verifier check
    // (both files exist, matching UUID on each side, still-image-time track).
    func testProducesValidLivePhotoPair() async throws {
        let src = tmp.appendingPathComponent("src.mp4")
        try makeTestVideo(at: src)

        let result = try await LivePhotoEngine.convert(
            input: src, outputDir: tmp, baseName: "IMG_TEST", settings: ConversionSettings())

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.imageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.movURL.path))

        let checks = await Verifier.verify(imageURL: result.imageURL, movURL: result.movURL)
        for check in checks {
            XCTAssertEqual(check.status, .pass, "驗證未通過:\(check.label) — \(check.detail)")
        }
    }

    // Proves the zero-quality-loss promise for real: the compressed video
    // bitstream in the output is byte-for-byte identical to the source (not just
    // that a "copied" flag is set). This is the in-test equivalent of the
    // `ffmpeg -c copy | md5` check.
    func testH264VideoStreamIsByteIdentical() async throws {
        let src = tmp.appendingPathComponent("src.mp4")
        try makeTestVideo(at: src)

        let result = try await LivePhotoEngine.convert(
            input: src, outputDir: tmp, baseName: "IMG_LL", settings: ConversionSettings())

        XCTAssertTrue(result.videoWasCopied, "H.264 應走無損 passthrough")
        let before = try await compressedVideoBytes(src)
        let after = try await compressedVideoBytes(result.movURL)
        XCTAssertFalse(before.isEmpty, "測試影片沒讀到任何樣本")
        XCTAssertEqual(before, after, "影片壓縮位元流應與來源完全相同(零損失)")
    }

    @MainActor func testOriginalCropResetPreservesVideoAfterModelLoad() async throws {
        let src = tmp.appendingPathComponent("original-default.mp4")
        try makeTestVideo(at: src)
        let model = Model()
        model.load(src)
        let deadline = Date().addingTimeInterval(10)
        while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.url, src)
        XCTAssertEqual(model.cropPreset, .original)
        XCTAssertFalse(model.cropEditing)
        XCTAssertNil(model.activeCrop)
        model.setCropPreset(.square)
        XCTAssertNotNil(model.activeCrop)
        model.setCropPreset(.original)
        XCTAssertNil(model.activeCrop)
        XCTAssertFalse(model.cropEditing)
        let recipe = try XCTUnwrap(model.currentPreparation())
        XCTAssertFalse(recipe.reencodes)
        let result = try await recipe.generate(in: tmp.appendingPathComponent("model-original"))
        let before = try await compressedVideoBytes(src)
        let after = try await compressedVideoBytes(result.movURL)
        XCTAssertEqual(before, after)
    }

    @MainActor func testLongVideoStartsWithUsableTenSecondTimeline() async throws {
        let src = tmp.appendingPathComponent("long-timeline.mp4")
        try makeTestVideo(at: src, seconds: 12, fps: 10, width: 64, height: 48)
        let model = Model()
        model.load(src)
        let deadline = Date().addingTimeInterval(10)
        while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.url, src)
        XCTAssertEqual(model.visibleDuration, 10)
        XCTAssertEqual(model.length, 3)
        model.browseTimeline(to: 2)
        XCTAssertEqual(model.visibleStart, 2)
        XCTAssertGreaterThanOrEqual(model.start, model.visibleStart)
        XCTAssertLessThanOrEqual(model.start + model.length, model.visibleStart + model.visibleDuration)
    }

    /// Reads the raw compressed samples of a file's video track (passthrough,
    /// no decode) and concatenates them — exact bytes, for equality comparison.
    private func compressedVideoBytes(_ url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return Data() }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil) // nil = compressed
        reader.add(output)
        reader.startReading()
        var acc = Data()
        while let sbuf = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sbuf) else { continue }
            let len = CMBlockBufferGetDataLength(block)
            var bytes = [UInt8](repeating: 0, count: len)
            if CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: len, destination: &bytes) == kCMBlockBufferNoErr {
                acc.append(contentsOf: bytes)
            }
        }
        return acc
    }

    // Proves the verifier actually catches a broken pair: A's photo with B's
    // video have different UUIDs, so the "identifiers match" check must fail.
    func testVerifierRejectsMismatchedPair() async throws {
        let a = tmp.appendingPathComponent("a.mp4"); try makeTestVideo(at: a)
        let b = tmp.appendingPathComponent("b.mp4"); try makeTestVideo(at: b)

        let ra = try await LivePhotoEngine.convert(
            input: a, outputDir: tmp, baseName: "A", settings: ConversionSettings())
        let rb = try await LivePhotoEngine.convert(
            input: b, outputDir: tmp, baseName: "B", settings: ConversionSettings())

        let checks = await Verifier.verify(imageURL: ra.imageURL, movURL: rb.movURL)
        // checks[2] is the "identifiers match" check
        XCTAssertEqual(checks[2].status, .fail, "不同 UUID 的配對應被判定失敗")
    }

    func testCustomResolutionAndFrameRate() async throws {
        let src = tmp.appendingPathComponent("custom-src.mp4")
        try makeTestVideo(at: src, seconds: 2, fps: 30, width: 640, height: 480)
        let dst = tmp.appendingPathComponent("custom.mov")
        try await Transcode.run(input: src, output: dst, start: 0.25, end: 1.75, maxEdge: 320, fps: 24, hevc: false)
        let asset = AVURLAsset(url: dst)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        XCTAssertEqual(size.width, 320)
        XCTAssertEqual(size.height, 240)
        XCTAssertEqual(fps, 24, accuracy: 0.1)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1.5, accuracy: 0.05)
        let r = try await LivePhotoEngine.convert(input: dst, outputDir: tmp, baseName: "CUSTOM", settings: ConversionSettings())
        let checks = await Verifier.verify(imageURL: r.imageURL, movURL: r.movURL)
        XCTAssertTrue(checks.allSatisfy { $0.status == .pass })
    }

    func testSystemRecognizesLivePhoto() async throws {
        let src = tmp.appendingPathComponent("system-src.mp4")
        try makeTestVideo(at: src, seconds: 3)
        let r = try await LivePhotoEngine.convert(input: src, outputDir: tmp, baseName: "SYSTEM", settings: ConversionSettings())
        let success: Bool = await withCheckedContinuation { cont in
            PHLivePhoto.request(withResourceFileURLs: [r.imageURL, r.movURL], placeholderImage: nil, targetSize: .zero, contentMode: .aspectFit) { photo, info in
                if (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true { return }
                cont.resume(returning: photo != nil)
            }
        }
        XCTAssertTrue(success, "Photos framework must recognize the pair as a Live Photo")
    }

    func testTrimmedPairIsRecognized() async throws {
        let src = tmp.appendingPathComponent("trim-src.mp4")
        try makeTestVideo(at: src, seconds: 5)
        var settings = ConversionSettings()
        settings.trimStart = 1.25; settings.trimEnd = 4.25; settings.frameTime = 1.5
        let r = try await LivePhotoEngine.convert(input: src, outputDir: tmp, baseName: "TRIM", settings: settings, quarterTurns: 1)
        XCTAssertTrue(r.videoWasCopied)
        XCTAssertGreaterThanOrEqual(r.clipDuration, 3)
        XCTAssertLessThanOrEqual(r.clipDuration, 4.3)
        let success: Bool = await withCheckedContinuation { cont in
            PHLivePhoto.request(withResourceFileURLs: [r.imageURL, r.movURL], placeholderImage: nil, targetSize: .zero, contentMode: .aspectFit) { photo, info in
                if (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true { return }
                cont.resume(returning: photo != nil)
            }
        }
        XCTAssertTrue(success)
    }

    func testGIFFramesSizeAndDuration() async throws {
        let src=tmp.appendingPathComponent("gif-src.mp4")
        try makeTestVideo(at:src,seconds:4)
        let dst=tmp.appendingPathComponent("result.gif")
        try await GIFExporter.run(input:src,output:dst,start:0.5,length:3,maxEdge:160,fps:30)
        let imageSource=CGImageSourceCreateWithURL(dst as CFURL,nil)!
        XCTAssertEqual(CGImageSourceGetCount(imageSource),90)
        let image=CGImageSourceCreateImageAtIndex(imageSource,0,nil)!
        XCTAssertEqual(image.width,160);XCTAssertEqual(image.height,120)
        var duration=0.0
        for i in 0..<90 {
            let props=CGImageSourceCopyPropertiesAtIndex(imageSource,i,nil)! as NSDictionary
            let gif=props[kCGImagePropertyGIFDictionary] as! NSDictionary
            duration += gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif[kCGImagePropertyGIFDelayTime] as? Double ?? 0
        }
        XCTAssertEqual(duration,3,accuracy:0.02)
    }

    func testOriginalSizeGIFKeepsOrientationAndTiming() async throws {
        for rate in [24,60] {
            let src=tmp.appendingPathComponent("original-\(rate).mp4")
            try makeTestVideo(at:src,seconds:1,fps:rate,width:320,height:240)
            let dst=tmp.appendingPathComponent("original-\(rate).gif")
            try await GIFExporter.run(input:src,output:dst,start:0,length:1,maxEdge:0,fps:0,quarterTurns:1)
            let source=CGImageSourceCreateWithURL(dst as CFURL,nil)!
            XCTAssertEqual(CGImageSourceGetCount(source),min(rate,50))
            let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
            XCTAssertEqual(image.width,240);XCTAssertEqual(image.height,320)
            var duration=0.0
            for i in 0..<CGImageSourceGetCount(source) {
                let props=CGImageSourceCopyPropertiesAtIndex(source,i,nil)! as NSDictionary
                let gif=props[kCGImagePropertyGIFDictionary] as! NSDictionary
                duration += gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
            }
            XCTAssertEqual(duration,1,accuracy:0.02)
        }
    }

    func testRotatedPortraitPreservesOrientation() async throws {
        let src=tmp.appendingPathComponent("rotated.mp4")
        try makeTestVideo(at:src,seconds:2,fps:30,width:640,height:360,rotated:true)
        let copied=try await LivePhotoEngine.convert(input:src,outputDir:tmp,baseName:"ROTATED",settings:ConversionSettings())
        let copyTrack=try await AVURLAsset(url:copied.movURL).loadTracks(withMediaType:.video).first!
        let transform=try await copyTrack.load(.preferredTransform)
        XCTAssertEqual(transform.b,1,accuracy:0.001)
        let dst=tmp.appendingPathComponent("portrait.mov")
        try await Transcode.run(input:src,output:dst,start:0,end:1.5,maxEdge:320,fps:60,hevc:true)
        let t=try await AVURLAsset(url:dst).loadTracks(withMediaType:.video).first!
        let size=try await t.load(.naturalSize)
        XCTAssertEqual(size.width,180);XCTAssertEqual(size.height,320)
        let fps=try await t.load(.nominalFrameRate);XCTAssertEqual(fps,60,accuracy:0.1)
    }

    func testQuarterTurnsComposeWithSourceOrientationWithoutEncoding() async throws {
        let src=tmp.appendingPathComponent("already-rotated.mp4")
        try makeTestVideo(at:src,seconds:2,width:640,height:360,rotated:true)
        let original=try await compressedVideoBytes(src)
        for turn in [1,2,3,4,-1] {
            let pair=try await LivePhotoEngine.convert(input:src,outputDir:tmp,baseName:"TURN-\(turn)",settings:ConversionSettings(),quarterTurns:turn)
            let bytes=try await compressedVideoBytes(pair.movURL)
            XCTAssertEqual(original,bytes)
            let track=try await AVURLAsset(url:pair.movURL).loadTracks(withMediaType:.video).first!
            let size=try await track.load(.naturalSize),transform=try await track.load(.preferredTransform)
            let rect=CGRect(origin:.zero,size:size).applying(transform)
            XCTAssertEqual(abs(rect.width),turn % 2 == 0 ? 360 : 640,accuracy:0.001)
            XCTAssertEqual(abs(rect.height),turn % 2 == 0 ? 640 : 360,accuracy:0.001)
            let image=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(pair.imageURL as CFURL,nil)!,0,nil)!
            XCTAssertEqual(image.width,Int(abs(rect.width)));XCTAssertEqual(image.height,Int(abs(rect.height)))
        }
    }

    func testQuarterTurnsCustomAndGIF() async throws {
        let src=tmp.appendingPathComponent("rotate-src.mp4")
        try makeTestVideo(at:src,seconds:2,width:640,height:360)
        let mov=tmp.appendingPathComponent("rotate-custom.mov")
        try await Transcode.run(input:src,output:mov,start:0,end:1.5,maxEdge:320,fps:24,hevc:true,quarterTurns:3)
        let track=try await AVURLAsset(url:mov).loadTracks(withMediaType:.video).first!
        let size=try await track.load(.naturalSize)
        XCTAssertEqual(size.width,180);XCTAssertEqual(size.height,320)
        let gif=tmp.appendingPathComponent("rotate.gif")
        try await GIFExporter.run(input:src,output:gif,start:0,length:1,maxEdge:320,fps:15,quarterTurns:1)
        let source=CGImageSourceCreateWithURL(gif as CFURL,nil)!
        XCTAssertEqual(CGImageSourceGetCount(source),15)
        let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
        XCTAssertEqual(image.width,180);XCTAssertEqual(image.height,320)
    }

    func testWatermarkIsWrittenIntoGIFAndCustomVideo() async throws {
        let src=tmp.appendingPathComponent("mark-source.mp4")
        try makeTestVideo(at:src,seconds:2,width:640,height:360)
        let mark=Watermark(text:"测试 TEST",position:4,scale:0.1,opacity:1)
        let movie=tmp.appendingPathComponent("marked.mov")
        try await Transcode.run(input:src,output:movie,start:0,end:1.5,maxEdge:320,fps:24,hevc:true,quarterTurns:1,watermark:mark)
        let generator=AVAssetImageGenerator(asset:AVURLAsset(url:movie));generator.appliesPreferredTrackTransform=true
        let (frame,_)=try await generator.image(at:CMTime(seconds:0.5,preferredTimescale:600))
        let gif=tmp.appendingPathComponent("marked.gif")
        try await GIFExporter.run(input:src,output:gif,start:0,length:1,maxEdge:320,fps:15,quarterTurns:1,watermark:mark)
        let image=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(gif as CFURL,nil)!,0,nil)!
        for candidate in [frame,image] {
            XCTAssertEqual(candidate.width,180);XCTAssertEqual(candidate.height,320)
            var bytes=[UInt8](repeating:0,count:180*320*4)
            bytes.withUnsafeMutableBytes { buffer in
                let c=CGContext(data:buffer.baseAddress,width:180,height:320,bitsPerComponent:8,bytesPerRow:720,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                c.draw(candidate,in:CGRect(x:0,y:0,width:180,height:320))
            }
            let white=(0..<180*320).filter { bytes[$0*4]>190 && bytes[$0*4+1]>190 && bytes[$0*4+2]>190 }
            XCTAssertGreaterThan(white.count,20,"White watermark must appear on the dark source")
        }
    }

    func testFlatExportDoesNotOverwriteOrLeavePartialPair() throws {
        let source=tmp.appendingPathComponent("source"),destination=tmp.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        let image=source.appendingPathComponent("photo.JPG"),movie=source.appendingPathComponent("photo.MOV")
        try Data("image".utf8).write(to:image);try Data("movie".utf8).write(to:movie)
        let result=ConversionResult(imageURL:image,movURL:movie,assetID:"test",baseName:"photo",clipDuration:3,videoWasCopied:true)
        let published=try ExportFiles.publish(result,into:destination,name:"test")
        XCTAssertEqual(published.imageURL.deletingLastPathComponent().path,destination.path)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath:destination.path)),Set(["test.JPG","test.MOV"]))
        XCTAssertThrowsError(try ExportFiles.publish(result,into:destination,name:"test"))
        XCTAssertEqual(try Data(contentsOf:published.movURL),Data("movie".utf8))
        try FileManager.default.removeItem(at:movie)
        XCTAssertThrowsError(try ExportFiles.publish(result,into:destination,name:"failure"))
        XCTAssertFalse(FileManager.default.fileExists(atPath:destination.appendingPathComponent("failure.JPG").path))
        XCTAssertEqual(try Data(contentsOf:published.imageURL),Data("image".utf8))
    }

    func testAirDropPackagePreservesPairAndSystemType() async throws {
        let source=tmp.appendingPathComponent("airdrop.mp4");try makeTestVideo(at:source,seconds:2)
        let pair=try await LivePhotoEngine.convert(input:source,outputDir:tmp,baseName:"AIR",settings:ConversionSettings(),quarterTurns:1)
        let package=try await LivePhotoPackage.create(from:pair,in:tmp.appendingPathComponent("share"))
        let entries=try FileManager.default.contentsOfDirectory(atPath:package.path)
        XCTAssertEqual(Set(entries),Set(["AIR.JPG","AIR.MOV","metadata.plist"]))
        XCTAssertEqual(try Data(contentsOf:package.appendingPathComponent("AIR.JPG")),try Data(contentsOf:pair.imageURL))
        XCTAssertEqual(try Data(contentsOf:package.appendingPathComponent("AIR.MOV")),try Data(contentsOf:pair.movURL))
        let props=try PropertyListSerialization.propertyList(from:Data(contentsOf:package.appendingPathComponent("metadata.plist")),format:nil) as! [String:String]
        XCTAssertEqual(props["PFVideoComplementMetadataVersionKey"],"1")
        let values=try package.resourceValues(forKeys:[.isPackageKey,.contentTypeKey])
        XCTAssertEqual(values.isPackage,true)
        XCTAssertTrue(["com.apple.live-photo-bundle","com.apple.private.live-photo-bundle"].contains(values.contentType?.identifier ?? ""))
        XCTAssertEqual(values.contentType?.conforms(to:.package),true)
        let recognized:Bool=await withCheckedContinuation { c in
            PHLivePhoto.request(withResourceFileURLs:[package.appendingPathComponent("AIR.JPG"),package.appendingPathComponent("AIR.MOV")],placeholderImage:nil,targetSize:.zero,contentMode:.aspectFit) { photo,info in
                if info[PHLivePhotoInfoIsDegradedKey] as? Bool == true { return };c.resume(returning:photo != nil)
            }
        }
        XCTAssertTrue(recognized)
    }

    func testAirDropRejectsBrokenPairWithoutTouchingSource() async throws {
        let image=tmp.appendingPathComponent("broken.JPG"),movie=tmp.appendingPathComponent("broken.MOV")
        try Data("keep".utf8).write(to:image)
        let pair=ConversionResult(imageURL:image,movURL:movie,assetID:"bad",baseName:"broken",clipDuration:3,videoWasCopied:true)
        do { _=try await LivePhotoPackage.create(from:pair,in:tmp.appendingPathComponent("share"));XCTFail("Must reject broken pair") } catch { }
        XCTAssertEqual(try Data(contentsOf:image),Data("keep".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath:tmp.appendingPathComponent("share/broken.pvt").path))
    }

    @MainActor func testDirectActionsUseCurrentSettingsWithoutFileExport() async throws {
        let source=tmp.appendingPathComponent("direct.mp4");try makeTestVideo(at:source,seconds:3)
        let model=Model();model.url=source;model.length=1;model.cover=0.5
        let first=model.currentPreparation()!
        model.quarterTurns=1;model.length=2;model.cover=1
        let second=model.currentPreparation()!
        let a=try await first.generate(in:tmp.appendingPathComponent("preview"))
        let b=try await second.generate(in:tmp.appendingPathComponent("send"))
        XCTAssertNil(model.result,"Direct generation must not create a file-export result")
        XCTAssertEqual(a.clipDuration,1,accuracy:0.05);XCTAssertEqual(b.clipDuration,2,accuracy:0.05)
        let firstImage=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(a.imageURL as CFURL,nil)!,0,nil)!
        let secondImage=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(b.imageURL as CFURL,nil)!,0,nil)!
        XCTAssertEqual(firstImage.width,320);XCTAssertEqual(firstImage.height,240)
        XCTAssertEqual(secondImage.width,240);XCTAssertEqual(secondImage.height,320)
        let package=try await LivePhotoPackage.create(from:b,in:tmp.appendingPathComponent("airdrop"))
        XCTAssertTrue(FileManager.default.fileExists(atPath:package.path))
    }

    @MainActor func testLongTimelineBrowsingKeepsSelectionVisible() {
        let model=Model();model.duration=331.2;model.timelineSpan=30;model.start=0;model.length=3;model.cover=1.5
        model.browseTimeline(to:150)
        XCTAssertEqual(model.start,150);XCTAssertEqual(model.visibleStart,150)
        XCTAssertEqual(model.length,3);XCTAssertEqual(model.cover,1.5)
        model.browseTimeline(to:999)
        XCTAssertEqual(model.visibleStart,301.2,accuracy:0.001)
        XCTAssertGreaterThanOrEqual(model.start,model.visibleStart)
        XCTAssertLessThanOrEqual(model.start+model.length,model.duration)
        model.start=325;model.centerTimeline()
        XCTAssertEqual(model.start,325)
        model.browseTimeline(to:0)
        XCTAssertGreaterThanOrEqual(model.start,0)
        XCTAssertLessThanOrEqual(model.start+model.length,30)
    }

    @MainActor func testBusyOperationsCannotChangeSelectionOrMode() {
        let model=Model();model.duration=331.2;model.timelineSpan=30;model.start=150;model.visibleStart=140;model.gifMode=true;model.busy=true
        model.browseTimeline(to:250)
        model.handle(URL(string:"livephotostudio://open?path=/tmp/test.mov")!)
        XCTAssertEqual(model.start,150);XCTAssertEqual(model.visibleStart,140)
        XCTAssertTrue(model.gifMode);XCTAssertNil(model.url)
        model.busy=false;model.browseTimeline(to:.nan)
        XCTAssertEqual(model.start,150)
    }

    func testInvalidLiveRangesFailWithoutPartialFiles() async throws {
        let src=tmp.appendingPathComponent("invalid-range.mp4")
        try makeTestVideo(at:src)
        for (start,end,cover) in [(2.0,3.0,0.5),(0.8,0.2,0.1),(Double.nan,1,0.5),(0,1,Double.infinity)] {
            var settings=ConversionSettings();settings.trimStart=start;settings.trimEnd=end;settings.frameTime=cover
            do { _=try await LivePhotoEngine.convert(input:src,outputDir:tmp,baseName:"INVALID",settings:settings);XCTFail("Invalid range accepted") } catch { }
            XCTAssertFalse(FileManager.default.fileExists(atPath:tmp.appendingPathComponent("INVALID.JPG").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath:tmp.appendingPathComponent("INVALID.MOV").path))
        }
    }

    func testCoverAtClipEndClampsToLastFrame() async throws {
        let src=tmp.appendingPathComponent("end-cover.mp4");try makeTestVideo(at:src)
        var settings=ConversionSettings();settings.frameTime=1
        let pair=try await LivePhotoEngine.convert(input:src,outputDir:tmp,baseName:"END",settings:settings)
        let checks=await Verifier.verify(imageURL:pair.imageURL,movURL:pair.movURL)
        XCTAssertTrue(checks.allSatisfy { $0.status == .pass })
    }

    func testCancelledGIFKeepsExistingOutputAndRemovesTemporaryFile() async throws {
        let src=tmp.appendingPathComponent("cancel-gif.mp4");try makeTestVideo(at:src,seconds:3)
        let output=tmp.appendingPathComponent("keep.gif"),original=Data("existing user output".utf8)
        try original.write(to:output)
        let task=Task { try await GIFExporter.run(input:src,output:output,start:0,length:3,maxEdge:0,fps:50) }
        task.cancel()
        do { try await task.value;XCTFail("Cancelled GIF must fail") } catch { }
        XCTAssertEqual(try Data(contentsOf:output),original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:tmp.path).contains { $0.hasPrefix(".gif-") })
    }

    func testLivePumpCancellationCompletesAndCleansPair() async throws {
        let src=tmp.appendingPathComponent("cancel-live.mp4");try makeTestVideo(at:src,seconds:3)
        let directory=tmp!,done=expectation(description:"Cancelled writer completes")
        let task=Task {
            defer { done.fulfill() }
            do {
                _=try await LivePhotoEngine.convert(input:src,outputDir:directory,baseName:"CANCEL",settings:ConversionSettings()) { phase in
                    if phase == "prog_mux" { withUnsafeCurrentTask { $0?.cancel() } }
                }
                XCTFail("Cancelled writer must fail")
            } catch { }
        }
        await fulfillment(of:[done],timeout:5)
        task.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath:tmp.appendingPathComponent("CANCEL.JPG").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:tmp.appendingPathComponent("CANCEL.MOV").path))
    }

    func testInvalidTranscodeParametersFailBeforeExport() async throws {
        let src=tmp.appendingPathComponent("invalid-transcode.mp4");try makeTestVideo(at:src)
        for (start,end,fps) in [(Double.nan,1.0,30),(0,Double.infinity,30),(0,1,Int.max),(1,0,30)] {
            let output=tmp.appendingPathComponent("invalid.mov")
            do { try await Transcode.run(input:src,output:output,start:start,end:end,maxEdge:0,fps:fps,hevc:true);XCTFail("Invalid parameters accepted") } catch { }
            XCTAssertFalse(FileManager.default.fileExists(atPath:output.path))
        }
    }

    func testStreamingGIFHasIndependentPalettesLoopAndFrameDelays() throws {
        let output=tmp.appendingPathComponent("palette.gif"),writer=try StreamingGIFWriter(url:output)
        let colors:[[CGFloat]]=[[1,0,0],[0,1,0],[0,0,1]]
        var references=[CGImage]()
        for (index,color) in colors.enumerated() {
            let context=CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:32,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red:color[0],green:color[1],blue:color[2],alpha:1));context.fill(CGRect(x:0,y:0,width:8,height:8))
            let image=context.makeImage()!
            let encoded=NSMutableData(),destination=CGImageDestinationCreateWithData(encoded,UTType.gif.identifier as CFString,1,nil)!
            CGImageDestinationAddImage(destination,image,nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
            references.append(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(encoded as CFData,nil)!,0,nil)!)
            try writer.append(image,delay:[3,4,5][index])
        }
        try writer.finish()
        let source=CGImageSourceCreateWithURL(output as CFURL,nil)!
        XCTAssertEqual(CGImageSourceGetCount(source),3)
        let properties=CGImageSourceCopyProperties(source,nil)! as NSDictionary
        XCTAssertEqual((properties[kCGImagePropertyGIFDictionary] as! NSDictionary)[kCGImagePropertyGIFLoopCount] as? Int,0)
        for index in 0..<3 {
            let image=CGImageSourceCreateImageAtIndex(source,index,nil)!
            var pixel=[UInt8](repeating:0,count:4)
            pixel.withUnsafeMutableBytes { buffer in
                let context=CGContext(data:buffer.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image,in:CGRect(x:0,y:0,width:1,height:1))
            }
            var expected=[UInt8](repeating:0,count:4)
            expected.withUnsafeMutableBytes { buffer in
                let context=CGContext(data:buffer.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(references[index],in:CGRect(x:0,y:0,width:1,height:1))
            }
            XCTAssertEqual(pixel,expected,"Streaming must preserve ImageIO's independently quantized frame")
            XCTAssertGreaterThan(pixel[index],200)
            for channel in 0..<3 where channel != index { XCTAssertLessThan(pixel[channel],80) }
            let props=CGImageSourceCopyPropertiesAtIndex(source,index,nil)! as NSDictionary
            let gif=props[kCGImagePropertyGIFDictionary] as! NSDictionary
            XCTAssertEqual(gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0,[0.03,0.04,0.05][index],accuracy:0.001)
        }
    }

    func testStreamingGIFParserRejectsTruncatedBlocks() throws {
        let bad:[[UInt8]]=[[],Array("GIF89a".utf8),Array("GIF89a".utf8)+[1,0,1,0,0x80,0,0],Array("GIF89a".utf8)+[1,0,1,0,0,0,0,0x21,0xF9,4,0],Array("GIF89a".utf8)+[1,0,1,0,0,0,0,0x2C,0,0]]
        for bytes in bad { XCTAssertThrowsError(try StreamingGIFWriter.imageBlock(Data(bytes))) }
        // Exercise every truncation boundary of a real system-encoded frame.
        let context=CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:32,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));context.fill(CGRect(x:0,y:0,width:8,height:8))
        let encoded=NSMutableData(),destination=CGImageDestinationCreateWithData(encoded,UTType.gif.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(destination,context.makeImage()!,nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
        let data=encoded as Data,complete=try StreamingGIFWriter.imageBlock(data)
        for count in 0..<data.count {
            do { let parsed=try StreamingGIFWriter.imageBlock(Data(data.prefix(count)));XCTAssertEqual(parsed.data,complete.data) }
            catch { } // Partial input must fail safely; trailer is not part of a frame block.
        }
    }

    func testStreamingGIFPreservesTransparentFramePixels() throws {
        let output=tmp.appendingPathComponent("transparent.gif"),writer=try StreamingGIFWriter(url:output)
        let context=CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:32,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));context.fill(CGRect(x:0,y:0,width:8,height:8))
        try writer.append(context.makeImage()!,delay:5)
        context.clear(CGRect(x:0,y:0,width:8,height:8));context.setFillColor(CGColor(red:0,green:0,blue:1,alpha:1));context.fill(CGRect(x:0,y:0,width:4,height:8))
        try writer.append(context.makeImage()!,delay:5);try writer.finish()
        let source=CGImageSourceCreateWithURL(output as CFURL,nil)!,image=CGImageSourceCreateImageAtIndex(source,1,nil)!
        var pixels=[UInt8](repeating:0,count:8*8*4)
        pixels.withUnsafeMutableBytes { buffer in
            let target=CGContext(data:buffer.baseAddress,width:8,height:8,bitsPerComponent:8,bytesPerRow:32,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            target.draw(image,in:CGRect(x:0,y:0,width:8,height:8))
        }
        XCTAssertEqual(pixels[(4*8+1)*4+3],255)
        XCTAssertEqual(pixels[(4*8+7)*4+3],0)
    }

    // MARK: test fixture

    /// Writes a short real H.264 .mp4 (solid frames) so the engine has something
    /// genuine to stream-copy.
    private func makeTestVideo(
        at url: URL, seconds: Double = 1.0, fps: Int = 30, width: Int = 320, height: Int = 240, rotated: Bool = false
    ) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        if rotated { input.transform=CGAffineTransform(a:0,b:1,c:-1,d:0,tx:CGFloat(height),ty:0) }
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        guard writer.canAdd(input) else { throw fail("cannot add writer input") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? fail("startWriting") }
        writer.startSession(atSourceTime: .zero)

        for i in 0..<Int(seconds * Double(fps)) {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB, nil, &pb)
            guard let buf = pb else { continue }
            CVPixelBufferLockBaseAddress(buf, [])
            if let base = CVPixelBufferGetBaseAddress(buf) {
                memset(base, Int32(30 + i * 3), CVPixelBufferGetDataSize(buf)) // changing shade
            }
            CVPixelBufferUnlockBaseAddress(buf, [])
            while !input.isReadyForMoreMediaData { usleep(2000) }
            adaptor.append(buf, withPresentationTime:
                CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? fail("finishWriting") }
    }

    private func fail(_ msg: String) -> NSError {
        NSError(domain: "ReviveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
