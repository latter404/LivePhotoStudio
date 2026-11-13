import XCTest
import AVFoundation
import Photos
import ImageIO
@testable import LivePhotoStudio

final class LiveCollageTests:XCTestCase {
 var root:URL!
 override func setUpWithError() throws {root=FileManager.default.temporaryDirectory.appendingPathComponent("CollageQA-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
 override func tearDownWithError() throws {try? FileManager.default.removeItem(at:root)}
 func testLayoutsFillCanvasWithoutEmptyCellsOrUpscaling() throws {
 for count in 2...9 {for layout in CollageLayout.allCases {
 let sizes=(0..<count).map{$0%2==0 ? CGSize(width:320,height:180) : CGSize(width:180,height:320)}
 let g=try CollageGeometry(sizes:sizes,layout:layout,maxEdge:7680)
 XCTAssertEqual(g.rects.count,count)
 XCTAssertEqual(g.rects.reduce(0){$0+$1.width*$1.height},g.size.width*g.size.height,accuracy:0.01)
 for (i,rect) in g.rects.enumerated() {
 XCTAssertGreaterThan(rect.width,0);XCTAssertGreaterThan(rect.height,0)
 XCTAssertLessThanOrEqual(rect.maxX,g.size.width);XCTAssertLessThanOrEqual(rect.maxY,g.size.height)
 XCTAssertLessThanOrEqual(rect.width,sizes[i].width+1);XCTAssertLessThanOrEqual(rect.height,sizes[i].height+1)
 for j in 0..<i {let intersection=rect.intersection(g.rects[j]);XCTAssertTrue(intersection.isNull || intersection.isEmpty)}
 }
 }}
 }
 func testLiveCollageHasMotionInEveryTileAndMatchingCover() async throws {
 let first=root.appendingPathComponent("red.mov"),second=root.appendingPathComponent("blue.mov")
 try fixture(first);try fixture(second,rotated:true)
 for (name,layout,fps) in [("horizontal24",CollageLayout.horizontal,24),("horizontal25",CollageLayout.horizontal,25),("vertical50",.vertical,50),("grid60",.grid,60)] {
 var options=CollageOptions();options.layout=layout;options.maxEdge=640;options.fps=fps;options.duration=0.8
 let inputs=layout == .grid ? [first,second,first] : [first,second]
 let pair=try await LiveCollage.generate(inputs:inputs,options:options,in:root.appendingPathComponent(name))
 XCTAssertFalse(pair.videoWasCopied);XCTAssertEqual(pair.clipDuration,0.8,accuracy:0.002)
 let checks=await Verifier.verify(imageURL:pair.imageURL,movURL:pair.movURL);XCTAssertTrue(checks.allSatisfy{$0.status == .pass})
 let early=try await frame(pair.movURL,0.1),late=try await frame(pair.movURL,0.7)
 let sizes=inputs.indices.map{$0==1 ? CGSize(width:120,height:160) : CGSize(width:160,height:120)}
 let g=try CollageGeometry(sizes:sizes,layout:layout,maxEdge:640)
 XCTAssertEqual(early.width,Int(g.size.width));XCTAssertEqual(early.height,Int(g.size.height))
 for (index,rect) in g.rects.enumerated() {
 let center=CGRect(x:rect.midX-3,y:rect.midY-3,width:6,height:6)
 let e=try XCTUnwrap(early.cropping(to:center)),l=try XCTUnwrap(late.cropping(to:center))
 XCTAssertGreaterThan(difference(e,l),20,"Each tile must animate")
 let source=try await frame(inputs[index],0.1)
 XCTAssertLessThan(difference(try XCTUnwrap(early.cropping(to:rect)),source),12,"Each tile must preserve source direction and content")
 }
 let cover=try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(pair.imageURL as CFURL,nil)!,0,nil))
 let midpoint=try await frame(pair.movURL,0.4)
 XCTAssertLessThan(difference(cover,midpoint),8,"Cover and playback must share orientation and layout")
 let recognized=await withCheckedContinuation { continuation in
 PHLivePhoto.request(withResourceFileURLs:[pair.imageURL,pair.movURL],placeholderImage:nil,targetSize:CGSize(width:200,height:200),contentMode:.aspectFit) {photo,info in
 if info[PHLivePhotoInfoIsDegradedKey] as? Bool == true {return};continuation.resume(returning:photo != nil)
 }
 }
 XCTAssertTrue(recognized)
 let shared=try await ShareBatch.prepare(assets:[.livePhoto(pair)],in:root.appendingPathComponent("share-"+name))
 XCTAssertEqual(shared.count,1)
 XCTAssertEqual(try Data(contentsOf:shared[0].appendingPathComponent(pair.movURL.lastPathComponent)),try Data(contentsOf:pair.movURL))
 let audio=try await AVURLAsset(url:pair.movURL).loadTracks(withMediaType:.audio);XCTAssertTrue(audio.isEmpty)
 }
 }
 func testShortestClipCancellationAndExistingDirectorySafety() async throws {
 let first=root.appendingPathComponent("short.mov"),second=root.appendingPathComponent("long.mov")
 try fixture(first,frames:15);try fixture(second)
 let pair=try await LiveCollage.generate(inputs:[first,second],options:CollageOptions(),in:root.appendingPathComponent("shortest"))
 XCTAssertEqual(pair.clipDuration,0.5,accuracy:0.002)
 let protected=root.appendingPathComponent("protected");try FileManager.default.createDirectory(at:protected,withIntermediateDirectories:true)
 let marker=protected.appendingPathComponent("keep.txt");try Data("keep".utf8).write(to:marker)
 do {_=try await LiveCollage.generate(inputs:[first,second],options:CollageOptions(),in:protected);XCTFail()} catch {}
 XCTAssertEqual(try Data(contentsOf:marker),Data("keep".utf8))
 let output=root.appendingPathComponent("cancelled")
 let task=Task {try await LiveCollage.generate(inputs:[first,second],options:CollageOptions(),in:output)};task.cancel()
 do {_=try await task.value;XCTFail()} catch {}
 XCTAssertFalse(FileManager.default.fileExists(atPath:output.path))
 }
 @MainActor func testSelectionToggleAndCollagePreserveOriginals() async throws {
 let video=root.appendingPathComponent("original.mov");try fixture(video)
 let pair=try await LivePhotoEngine.convert(input:video,outputDir:root,baseName:"paired",settings:ConversionSettings())
 let store=FinishedStore(root:root.appendingPathComponent("history"))
 let a=try await store.addLive(pair,title:"A",start:0,duration:1),b=try await store.addLive(pair,title:"B",start:0,duration:1)
 let model=Model();model.finishedStore=store;await model.loadFinished()
 XCTAssertFalse(model.allFinishedSelected);model.toggleAllFinished();XCTAssertTrue(model.allFinishedSelected);XCTAssertEqual(model.finishedSelection.count,2)
 model.toggleAllFinished();XCTAssertTrue(model.finishedSelection.isEmpty)
 model.finishedSelection=[a.id];model.toggleAllFinished();XCTAssertEqual(model.finishedSelection,[a.id,b.id]);XCTAssertTrue(model.canCollage)
 try await model.createCollage(ids:[a.id,b.id],options:CollageOptions())
 XCTAssertEqual(model.finishedItems.count,3);XCTAssertEqual(model.finishedSelection.count,1);XCTAssertEqual(model.sessionProcessedCount,1)
 XCTAssertFalse(model.finishedSelection.contains(a.id));XCTAssertFalse(model.finishedSelection.contains(b.id))
 let originals=try await store.validate(ids:[a.id,b.id]);XCTAssertTrue(originals.allSatisfy(\.isAvailable))
 XCTAssertFalse(model.busy)
 }
 func testHighResolutionWithExternalSyntheticFixtures() async throws {
 guard let folder=ProcessInfo.processInfo.environment["COLLAGE_FIXTURES"],let output=ProcessInfo.processInfo.environment["COLLAGE_QA_OUTPUT"] else {throw XCTSkip("Optional high-resolution synthetic fixtures")}
 let input=URL(fileURLWithPath:folder),out=URL(fileURLWithPath:output)
 var reports:[[String:Any]]=[]
 for (name,names,edge) in [("mixed-4k",["4K.mov","8Kportrait.mov"],3840),("pair-8k",["8K.mov","8K.mov"],7680),("portrait-pair-8k",["8Kportrait.mov","8Kportrait.mov"],7680),("nine-tiles",Array(repeating:"portrait30.mov",count:9),3840)] {
 var options=CollageOptions();options.maxEdge=edge
 let began=Date()
 let pair=try await LiveCollage.generate(inputs:names.map{input.appendingPathComponent($0)},options:options,in:out.appendingPathComponent(name))
 let cover=try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(pair.imageURL as CFURL,nil)!,0,nil))
 let checks=await Verifier.verify(imageURL:pair.imageURL,movURL:pair.movURL)
 XCTAssertTrue(checks.allSatisfy{$0.status == .pass})
 XCTAssertEqual(pair.clipDuration,3,accuracy:0.002)
 for t in [0.0,1.5,2.99] {_ = try await frame(pair.movURL,t)}
 let recognized=await withCheckedContinuation { continuation in
 PHLivePhoto.request(withResourceFileURLs:[pair.imageURL,pair.movURL],placeholderImage:nil,targetSize:CGSize(width:120,height:120),contentMode:.aspectFit) {photo,info in
 if info[PHLivePhotoInfoIsDegradedKey] as? Bool == true {return};continuation.resume(returning:photo != nil)
 }
 }
 XCTAssertTrue(recognized)
 reports.append(["systemRecognized":recognized,"case":name,"seconds":pair.clipDuration,"width":cover.width,"height":cover.height,"elapsedSeconds":Date().timeIntervalSince(began),"pairValid":true])
 print("Collage stress: \(name) \(cover.width)x\(cover.height)")
 }
 try JSONSerialization.data(withJSONObject:reports,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("results.json"))
 }
 private func fixture(_ url:URL,rotated:Bool=false,frames:Int=30) throws {
 let writer=try AVAssetWriter(outputURL:url,fileType:.mov)
 let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:160,AVVideoHeightKey:120])
 if rotated {input.transform=CGAffineTransform(a:0,b:1,c:-1,d:0,tx:120,ty:0)}
 let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB])
 writer.add(input);writer.startWriting();writer.startSession(atSourceTime:.zero)
 for i in 0..<frames {autoreleasepool {
 var p:CVPixelBuffer?;CVPixelBufferCreate(nil,160,120,kCVPixelFormatType_32ARGB,nil,&p);let buffer=p!
 CVPixelBufferLockBaseAddress(buffer,[])
 let context=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:160,height:120,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
 context.setFillColor(CGColor(red:i<15 ? 0.9 : 0.2,green:0.2,blue:i<15 ? 0.2 : 0.9,alpha:1));context.fill(CGRect(x:0,y:0,width:160,height:120))
 context.setFillColor(CGColor(red:0.2,green:0.9,blue:0.2,alpha:1));context.fill(CGRect(x:0,y:0,width:25,height:30))
 CVPixelBufferUnlockBaseAddress(buffer,[])
 while !input.isReadyForMoreMediaData {Thread.sleep(forTimeInterval:0.001)}
 adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(i),timescale:30))
 }}
 input.markAsFinished();let done=DispatchSemaphore(value:0);writer.finishWriting{done.signal()};done.wait();XCTAssertEqual(writer.status,.completed)
 }
 private func frame(_ url:URL,_ t:Double) async throws -> CGImage {
 let g=AVAssetImageGenerator(asset:AVURLAsset(url:url));g.appliesPreferredTrackTransform=true;g.requestedTimeToleranceBefore = .zero;g.requestedTimeToleranceAfter = .zero
 return try await g.image(at:CMTime(seconds:t,preferredTimescale:60000)).image
 }
 private func difference(_ a:CGImage,_ b:CGImage)->Double {
 func bytes(_ image:CGImage)->[UInt8] {
 var data=[UInt8](repeating:0,count:24*24*4)
 data.withUnsafeMutableBytes {p in let c=CGContext(data:p.baseAddress,width:24,height:24,bitsPerComponent:8,bytesPerRow:96,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;c.draw(image,in:CGRect(x:0,y:0,width:24,height:24))};return data
 }
 let x=bytes(a),y=bytes(b);return zip(x,y).map{abs(Double($0)-Double($1))}.reduce(0,+)/Double(x.count)
 }
}
