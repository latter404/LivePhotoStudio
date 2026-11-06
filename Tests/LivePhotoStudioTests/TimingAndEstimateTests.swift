import XCTest
import AVFoundation
import ImageIO
import Photos
@testable import LivePhotoStudio

final class TimingAndEstimateTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root=FileManager.default.temporaryDirectory.appendingPathComponent("TimingQA-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
    }
    override func tearDownWithError() throws {
        if ProcessInfo.processInfo.environment["TIMING_QA_KEEP"] == "1" { print("Kept synthetic QA: \(root.path)") }
        else { try? FileManager.default.removeItem(at:root) }
    }

    func testCopyTrimMatchesSourceFramesAndExactDuration() async throws {
        for (fps, fractional, portrait) in [(24,false,false),(30,false,true),(50,false,false),(60,false,true),(30,true,false)] {
            let input=root.appendingPathComponent("source-\(fps)-\(fractional).mov")
            try fixture(input,fps:fps,fractional:fractional,portrait:portrait)
            let start=1.257, end=4.249, cover=1.137
            var settings=ConversionSettings();settings.trimStart=start;settings.trimEnd=end;settings.frameTime=cover
            let result=try await LivePhotoEngine.convert(input:input,outputDir:root,baseName:"copy-\(fps)-\(fractional)",settings:settings,quarterTurns:1)
            XCTAssertEqual(result.clipDuration,end-start,accuracy:0.002)
            XCTAssertTrue(result.videoWasCopied)
            let sourceAsset=try await Rotation.asset(url:input,turns:1)
            for t in [0.0,cover,end-start-0.0001] {
                let expected=try await frame(sourceAsset,time:start+t)
                let actual=try await frame(AVURLAsset(url:result.movURL),time:t)
                XCTAssertLessThan(difference(expected,actual),1,"\(fps) fps, time \(t)")
            }
            let jpeg=try XCTUnwrap(CGImageSourceCreateWithURL(result.imageURL as CFURL,nil))
            let coverImage=try XCTUnwrap(CGImageSourceCreateImageAtIndex(jpeg,0,nil))
            let expectedCover=try await frame(sourceAsset,time:start+cover)
            XCTAssertLessThan(difference(expectedCover,coverImage),3)
            let original=try await packets(input), copied=try await packets(result.movURL)
            XCTAssertFalse(copied.isEmpty)
            XCTAssertTrue(copied.allSatisfy { original.contains($0) },"Trim must not re-encode any video sample")
            print("exactTrim fps=\(fps) fractional=\(fractional) portrait=\(portrait) duration=\(result.clipDuration)")
        }
    }

    func testSpeedLiveDurationCoverAndCustomFPS() async throws {
        let input=root.appendingPathComponent("speed.mov");try fixture(input,fps:60,portrait:true)
        for speed in [0.25,0.5,1.5,2.0,4.0] {
            let start=0.7,length=1.6,cover=0.8
            let recipe=LivePreparation(input:input,start:start,length:length,cover:cover,custom:true,edge:240,fps:30,hevc:true,mute:true,turns:1,watermark:nil,speed:speed)
            let pair=try await recipe.generate(in:root.appendingPathComponent("speed-\(speed)"))
            XCTAssertFalse(pair.videoWasCopied)
            XCTAssertEqual(pair.clipDuration,length/speed,accuracy:0.035)
            let asset=AVURLAsset(url:pair.movURL)
            let tracks=try await asset.loadTracks(withMediaType:.video)
            let track=try XCTUnwrap(tracks.first)
            let rate=try await track.load(.nominalFrameRate)
            XCTAssertEqual(rate,30,accuracy:0.2)
            let expected=try await frame(try await Rotation.asset(url:input,turns:1),time:start+cover)
            let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(pair.imageURL as CFURL,nil)!,0,nil))
            XCTAssertLessThan(difference(expected,image),12)
            let movie=try await frame(asset,time:cover/speed)
            XCTAssertLessThan(difference(movie,image),3)
            for t in [0.0,length/speed-1.0/30] {
                let expectedFrame=try await frame(try await Rotation.asset(url:input,turns:1),time:start+t*speed)
                let actualFrame=try await frame(asset,time:t)
                XCTAssertLessThan(difference(expectedFrame,actualFrame),12,"Speed boundary \(speed), time \(t)")
            }
            let source=try await asset.load(.duration)
            XCTAssertGreaterThan(source.seconds,0)
            print("speed=\(speed) outputDuration=\(pair.clipDuration) fps=\(rate)")
        }
    }

    func testCoverAtFractionalSelectionEndUsesFinalSourceFrame() async throws {
        let input=root.appendingPathComponent("last-cover.mov");try fixture(input,fps:24)
        var settings=ConversionSettings();settings.trimStart=1.257;settings.trimEnd=4.249;settings.frameTime=2.9919
        let pair=try await LivePhotoEngine.convert(input:input,outputDir:root,baseName:"last-cover-pair",settings:settings)
        let expected=try await frame(AVURLAsset(url:input),time:4.2489)
        let source=try XCTUnwrap(CGImageSourceCreateWithURL(pair.imageURL as CFURL,nil))
        let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        XCTAssertLessThan(difference(expected,image),3)
        let actual=try await frame(AVURLAsset(url:pair.movURL),time:pair.clipDuration-0.001)
        XCTAssertLessThan(difference(expected,actual),1)
        let recognized:Bool=await withCheckedContinuation { continuation in
            PHLivePhoto.request(withResourceFileURLs:[pair.imageURL,pair.movURL],placeholderImage:nil,targetSize:CGSize(width:100,height:100),contentMode:.aspectFit) { photo,info in
                if info[PHLivePhotoInfoIsDegradedKey] as? Bool == true { return }
                continuation.resume(returning:photo != nil)
            }
        }
        XCTAssertTrue(recognized)
    }

    func testEngineRejectsCaseOnlySourceOverwrite() async throws {
        let input=root.appendingPathComponent("keep-original.mov");try fixture(input,fps:24,seconds:1)
        let before=try Data(contentsOf:input)
        do {
            _=try await LivePhotoEngine.convert(input:input,outputDir:root,baseName:"KEEP-ORIGINAL",settings:ConversionSettings())
            XCTFail("Must not replace the original movie")
        } catch {}
        XCTAssertEqual(try Data(contentsOf:input),before)
    }

    func testGIFSpeedEstimateAndActualTiming() async throws {
        let input=root.appendingPathComponent("gif.mov");try fixture(input,fps:60)
        for speed in [0.5,1.0,2.0,4.0] {
            let crop=CropRegion(rect:CGRect(x:0.1,y:0.2,width:0.7,height:0.6))
            let mark=Watermark(text:"TEST",position:4,scale:0.08,opacity:0.75)
            let recipe=GIFRecipe(input:input,start:0.7,length:1.613,maxEdge:160,fps:30,quarterTurns:1,watermark:mark,crop:crop,speed:speed)
            let estimate=try await GIFSizeEstimator.shared.estimate(recipe)
            XCTAssertLessThanOrEqual(estimate.sampledFrames,3)
            let out=root.appendingPathComponent("speed-\(speed).gif")
            try await GIFExporter.run(input:input,output:out,start:recipe.start,length:recipe.length,maxEdge:recipe.maxEdge,fps:recipe.fps,quarterTurns:recipe.quarterTurns,watermark:mark,crop:crop,speed:speed)
            let size=try XCTUnwrap(out.resourceValues(forKeys:[.fileSizeKey]).fileSize)
            let ratio=Double(estimate.bytes)/Double(size)
            XCTAssertGreaterThan(ratio,0.65);XCTAssertLessThan(ratio,1.45)
            let source=try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL,nil))
            XCTAssertEqual(CGImageSourceGetCount(source),estimate.totalFrames)
            var duration=0.0
            for i in 0..<CGImageSourceGetCount(source) {
                let props=CGImageSourceCopyPropertiesAtIndex(source,i,nil)! as NSDictionary
                let gif=props[kCGImagePropertyGIFDictionary] as! NSDictionary
                duration += gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
            }
            XCTAssertEqual(duration,recipe.length/speed,accuracy:0.006)
            print("GIF speed=\(speed) estimate=\(estimate.bytes) actual=\(size) ratio=\(ratio) seconds=\(duration)")
        }
    }

    func testHighFrameRateSlowMotionUsesSourceFramesByDefault() async throws {
        let input=root.appendingPathComponent("120fps.mov");try fixture(input,fps:120,seconds:2)
        let recipe=LivePreparation(input:input,start:0.25,length:1,cover:0.5,custom:false,edge:0,fps:0,hevc:true,mute:true,turns:0,watermark:nil,speed:0.25)
        let pair=try await recipe.generate(in:root.appendingPathComponent("120fps-slow"))
        let asset=AVURLAsset(url:pair.movURL),tracks=try await AVURLAsset(url:pair.movURL).loadTracks(withMediaType:.video)
        let fps=try await tracks[0].load(.nominalFrameRate),size=try await tracks[0].load(.naturalSize)
        XCTAssertEqual(pair.clipDuration,4,accuracy:0.002)
        XCTAssertEqual(fps,30,accuracy:0.3)
        XCTAssertEqual(size,CGSize(width:320,height:240))
        for t in [0.5,1.5,2.5,3.5] {
            let expected=try await frame(AVURLAsset(url:input),time:0.25+t*0.25)
            let output=try await frame(asset,time:t)
            XCTAssertLessThan(difference(expected,output),12)
        }
    }

    @MainActor func testProcessingStoresOutputTimeAndActualGIFBytes() async throws {
        let input=root.appendingPathComponent("process.mov");try fixture(input,fps:30,seconds:2)
        let store=FinishedStore(root:root.appendingPathComponent("history")),model=Model()
        model.finishedStore=store;await model.loadFinished()
        model.load(input);try await waitUntil { !model.busy }
        model.start=0.3;model.length=1.2;model.cover=0.6;model.speed=0.5
        model.processCurrent();try await waitUntil { !model.busy }
        let live=try XCTUnwrap(model.finishedItems.first)
        XCTAssertEqual(live.kind,.livePhoto);XCTAssertEqual(live.duration,2.4,accuracy:0.035)
        XCTAssertEqual(live.sourceDuration ?? 0,1.2,accuracy:0.001)
        model.gifMode=true;model.processCurrent();try await waitUntil { !model.busy }
        let gif=try XCTUnwrap(model.finishedItems.first)
        XCTAssertEqual(gif.kind,.gif);XCTAssertEqual(gif.duration,2.4,accuracy:0.006)
        XCTAssertEqual(model.lastGIFSize?.bytes,gif.byteCount)
        XCTAssertEqual(model.lastGIFSize?.recipe,model.currentGIFRecipe)
        let restored=Model();restored.finishedStore=store;await restored.loadFinished()
        XCTAssertEqual(restored.finishedItems.count,2)
        XCTAssertTrue(restored.finishedSelection.isEmpty);XCTAssertTrue(restored.sessionProcessedIDs.isEmpty)
        XCTAssertEqual(restored.finishedItems.first?.sourceDuration,1.2)
    }

    func testGIFEstimateCancellationAndInvalidSpeed() async throws {
        let input=root.appendingPathComponent("cancel.mov");try fixture(input,fps:30)
        let recipe=GIFRecipe(input:input,start:0,length:3,maxEdge:0,fps:30)
        let task=Task { try await GIFSizeEstimator.shared.estimate(recipe) };task.cancel()
        do { _=try await task.value;XCTFail("Cancelled estimate must stop") } catch {}
        for speed in [0.0,-1,.nan,.infinity,10] {
            var bad=recipe;bad.speed=speed
            do { _=try await GIFExporter.estimate(bad);XCTFail("Invalid speed accepted") } catch {}
            var live=LivePreparation(input:input,start:0,length:1,cover:0.5,custom:false,edge:0,fps:0,hevc:true,mute:true,turns:0,watermark:nil);live.speed=speed
            do { _=try await live.generate(in:root.appendingPathComponent("bad"));XCTFail("Invalid live speed accepted") } catch {}
        }
    }

    @MainActor func testTrimHandlesSeekTheirOwnBoundariesAndPreserveCover() async throws {
        let input=root.appendingPathComponent("long.mov");try fixture(input,fps:30,seconds:12,portrait:true)
        let model=Model();model.load(input)
        try await waitUntil { !model.busy }
        model.start=4;model.length=3;model.cover=1.5
        model.trimEnd(to:8)
        try await waitUntil { abs(model.player.currentTime().seconds-8)<0.002 }
        XCTAssertEqual(model.cover,1.5)
        model.trimStart(to:4.5)
        try await waitUntil { abs(model.player.currentTime().seconds-4.5)<0.002 }
        XCTAssertEqual(model.start+model.cover,5.5,accuracy:0.001)
        XCTAssertEqual(model.start+model.length,8,accuracy:0.001)
        model.seek()
        try await waitUntil { abs(model.player.currentTime().seconds-5.5)<0.002 }
        model.speed=2
        model.preview()
        try await waitUntil { model.player.rate == 2 }
        XCTAssertEqual(model.player.currentItem?.forwardPlaybackEndTime.seconds ?? 0,8,accuracy:0.001)
        model.seek();XCTAssertEqual(model.player.rate,0)
        model.start=0;model.length=0.3;model.cover=0.15;model.speed=2;model.gifMode=true
        model.preview()
        XCTAssertTrue(model.player.isMuted,"GIF previews must be silent like GIF output")
        try await waitUntil { !model.previewing }
        XCTAssertEqual(model.player.rate,0)
    }

    @MainActor func testDefaultOutputStaysWithinThreeSecondsAcrossSpeeds() async throws {
        let input=root.appendingPathComponent("defaults.mov");try fixture(input,fps:30,seconds:14)
        let model=Model();model.load(input);try await waitUntil { !model.busy }
        for speed in MediaTiming.speeds {
            model.setSpeed(speed)
            XCTAssertEqual(model.outputDuration,3,accuracy:0.0001)
            XCTAssertEqual(model.length,3*speed,accuracy:0.0001)
            XCTAssertFalse(model.durationWasCustomized)
            XCTAssertLessThanOrEqual(model.start+model.length,model.visibleStart+model.visibleDuration)
        }
        model.setSpeed(0.5)
        let pair=try await XCTUnwrap(model.currentPreparation()).generate(in:root.appendingPathComponent("default-half"))
        XCTAssertEqual(pair.clipDuration,3,accuracy:0.001)
        model.gifMode=true
        let gif=root.appendingPathComponent("default-half.gif")
        try await GIFExporter.run(input:input,output:gif,start:model.start,length:model.length,maxEdge:160,fps:30,speed:model.speed)
        let images=try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL,nil))
        var seconds=0.0
        for i in 0..<CGImageSourceGetCount(images) {
            let properties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(images,i,nil) as? [String:Any])
            let values=try XCTUnwrap(properties[kCGImagePropertyGIFDictionary as String] as? [String:Any])
            seconds += (values[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double) ?? (values[kCGImagePropertyGIFDelayTime as String] as? Double) ?? 0
        }
        XCTAssertEqual(seconds,3,accuracy:0.006)
    }

    @MainActor func testManualDurationIsKeptUntilResetOrNewVideo() async throws {
        let input=root.appendingPathComponent("manual.mov");try fixture(input,fps:30,seconds:8)
        let model=Model();model.load(input);try await waitUntil { !model.busy }
        model.trimEnd(to:4)
        model.setSpeed(0.5)
        XCTAssertTrue(model.durationWasCustomized)
        XCTAssertEqual(model.length,4,accuracy:0.0001)
        XCTAssertEqual(model.outputDuration,8,accuracy:0.0001)
        model.resetOutputDuration()
        XCTAssertEqual(model.length,1.5,accuracy:0.0001)
        XCTAssertEqual(model.outputDuration,3,accuracy:0.0001)
        model.setSpeed(1)
        model.trimStart(to:0.5)
        model.setSpeed(0.25)
        XCTAssertEqual(model.start,0.5,accuracy:0.0001)
        XCTAssertEqual(model.length,2.5,accuracy:0.0001)
        model.load(input);try await waitUntil { !model.busy }
        XCTAssertFalse(model.durationWasCustomized)
        XCTAssertEqual(model.speed,1)
        XCTAssertEqual(model.outputDuration,3,accuracy:0.0001)
    }

    @MainActor func testDefaultDurationHandlesShortSourceAndEndOfVideo() {
        let model=Model();model.duration=0.4;model.length=0.4
        for speed in MediaTiming.speeds {
            model.setSpeed(speed)
            XCTAssertLessThanOrEqual(model.outputDuration,3)
            XCTAssertLessThanOrEqual(model.start+model.length,model.duration)
        }
        model.duration=30;model.start=28;model.setSpeed(4)
        XCTAssertEqual(model.outputDuration,3,accuracy:0.0001)
        XCTAssertEqual(model.start+model.length,30,accuracy:0.0001)
        XCTAssertGreaterThanOrEqual(model.cover,0)
        XCTAssertLessThan(model.cover,model.length)
    }

    @MainActor private func waitUntil(_ condition:() -> Bool) async throws {
        let deadline=Date().addingTimeInterval(8)
        while !condition(),Date()<deadline { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertTrue(condition(),"Timed out waiting for player/model")
    }

    private func frame(_ asset:AVAsset,time:Double) async throws -> CGImage {
        let g=AVAssetImageGenerator(asset:asset);g.appliesPreferredTrackTransform=true
        g.requestedTimeToleranceBefore = .zero;g.requestedTimeToleranceAfter = .zero
        return try await g.image(at:CMTime(seconds:time,preferredTimescale:60000)).image
    }
    private func difference(_ a:CGImage,_ b:CGImage) -> Double {
        func pixels(_ image:CGImage) -> [UInt8] {
            var bytes=[UInt8](repeating:0,count:32*32*4)
            bytes.withUnsafeMutableBytes { buf in
                let c=CGContext(data:buf.baseAddress,width:32,height:32,bitsPerComponent:8,bytesPerRow:128,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                c.draw(image,in:CGRect(x:0,y:0,width:32,height:32))
            };return bytes
        }
        return zip(pixels(a),pixels(b)).map{abs(Double($0)-Double($1))}.reduce(0,+)/4096
    }
    private func packets(_ url:URL) async throws -> [Data] {
        let reader=try AVAssetReader(asset:AVURLAsset(url:url))
        let track=try await reader.asset.loadTracks(withMediaType:.video)[0]
        let out=AVAssetReaderTrackOutput(track:track,outputSettings:nil);reader.add(out)
        XCTAssertTrue(reader.startReading());var values:[Data]=[]
        while let sample=out.copyNextSampleBuffer() {
            guard let data=CMSampleBufferGetDataBuffer(sample) else { continue }
            var bytes=Data(count:CMBlockBufferGetDataLength(data))
            let status=bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(data,atOffset:0,dataLength:$0.count,destination:$0.baseAddress!) }
            XCTAssertEqual(status,noErr);values.append(bytes)
        };return values
    }
    private func fixture(_ url:URL,fps:Int,fractional:Bool=false,seconds:Double=6,portrait:Bool=false) throws {
        let writer=try AVAssetWriter(outputURL:url,fileType:.mov)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:320,AVVideoHeightKey:240,AVVideoCompressionPropertiesKey:[AVVideoMaxKeyFrameIntervalKey:fps*3,AVVideoAllowFrameReorderingKey:true,AVVideoAverageBitRateKey:2_000_000]])
        if portrait { input.transform=CGAffineTransform(a:0,b:1,c:-1,d:0,tx:240,ty:0) }
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB])
        writer.add(input);XCTAssertTrue(writer.startWriting());writer.startSession(atSourceTime:.zero)
        for i in 0..<Int(Double(fps)*seconds) {
            try autoreleasepool {
                var pb:CVPixelBuffer?;CVPixelBufferCreate(nil,320,240,kCVPixelFormatType_32ARGB,nil,&pb)
                let p=try XCTUnwrap(pb);CVPixelBufferLockBaseAddress(p,[])
                let c=CGContext(data:CVPixelBufferGetBaseAddress(p),width:320,height:240,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(p),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
                for band in 0..<8 {
                    c.setFillColor(CGColor(red:Double((i*3+band*21)%220+20)/255,green:Double((i+band*13)%190+30)/255,blue:Double((i*2+band*31)%200+30)/255,alpha:1))
                    c.fill(CGRect(x:band*40,y:0,width:40,height:240))
                }
                CVPixelBufferUnlockBaseAddress(p,[])
                while !input.isReadyForMoreMediaData { usleep(1000) }
                XCTAssertTrue(adaptor.append(p,withPresentationTime:CMTime(value:Int64(i)*(fractional ? 1001:1000),timescale:Int32(fps*1000))))
            }
        }
        input.markAsFinished();let done=DispatchSemaphore(value:0)
        writer.finishWriting { done.signal() };done.wait()
        XCTAssertEqual(writer.status,.completed)
    }
}
