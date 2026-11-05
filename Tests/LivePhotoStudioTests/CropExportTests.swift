import XCTest
import AVFoundation
import AppKit
import ImageIO
@testable import LivePhotoStudio

final class CropExportTests:XCTestCase {
 private var root:URL!
 override func setUpWithError() throws { root=FileManager.default.temporaryDirectory.appendingPathComponent("CropExport-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true) }
 override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }

 func testOffCenterCropMatchesSourceForVideoGIFAndLiveCover() async throws {
 let input=root.appendingPathComponent("corners.mov");try fixture(input)
 let crop=CropRegion(rect:CGRect(x:0.1,y:0.05,width:0.5,height:0.5))
 let original=try await frame(input)
 let expected=original.cropping(to:crop.pixelRect(in:CGSize(width:original.width,height:original.height)))!
 // A full-frame SDR transcode controls for the existing color conversion.
 // Crop coordinates are independently checked against that same color pipeline.
 let referenceURL=root.appendingPathComponent("full-reference.mov")
 try await Transcode.run(input:input,output:referenceURL,start:0,end:1,maxEdge:0,fps:30,hevc:true)
 let reference=try await frame(referenceURL)
 let expectedVideo=reference.cropping(to:crop.pixelRect(in:CGSize(width:reference.width,height:reference.height)))!
 let output=root.appendingPathComponent("cropped.mov")
 try await Transcode.run(input:input,output:output,start:0,end:1,maxEdge:0,fps:30,hevc:true,crop:crop)
 let video=try await frame(output)
 XCTAssertEqual(video.width,160);XCTAssertEqual(video.height,120)
 XCTAssertLessThan(difference(video,expectedVideo),8)
 let wrong=reference.cropping(to:CGRect(x:32,y:108,width:160,height:120))!
 XCTAssertGreaterThan(difference(video,wrong),30,"Vertical origin must not be inverted")
 XCTAssertGreaterThan(minimumBorderRGB(video),50,"Crop must not add black padding")
 print("cropGeometryMAE=\(difference(video,expectedVideo)); originalSDRMAE=\(difference(video,expected))")
 let gif=root.appendingPathComponent("cropped.gif")
 try await GIFExporter.run(input:input,output:gif,start:0,length:0.3,maxEdge:0,fps:30,crop:crop)
 let source=CGImageSourceCreateWithURL(gif as CFURL,nil)!
 XCTAssertEqual(CGImageSourceGetCount(source),9)
 let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
 XCTAssertEqual(image.width,160);XCTAssertEqual(image.height,120)
 XCTAssertLessThan(difference(image,expected),12)
 var recipe=LivePreparation(input:input,start:0,length:1,cover:0.5,custom:false,edge:0,fps:0,hevc:true,mute:false,turns:0,watermark:nil)
 recipe.crop=crop
 XCTAssertTrue(recipe.reencodes)
 let pair=try await recipe.generate(in:root.appendingPathComponent("live"))
 let cover=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(pair.imageURL as CFURL,nil)!,0,nil)!
 let motion=try await frame(pair.movURL)
 XCTAssertEqual(cover.width,160);XCTAssertEqual(cover.height,120)
 XCTAssertLessThan(difference(cover,motion),8)
 XCTAssertLessThan(difference(cover,expectedVideo),8)
 }

 func testCropAfterSourceOrientationAndQuarterTurnWithWatermark() async throws {
 let input=root.appendingPathComponent("oriented.mov");try fixture(input,oriented:true)
 for turn in [0,1,3] {
 let asset=try await Rotation.asset(url:input,turns:turn)
 let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true
 let original=try await generator.image(at:CMTime(seconds:0.5,preferredTimescale:600)).image
 let crop=CropRegion(rect:CGRect(x:0,y:0,width:0.75,height:0.5))
 let cut=original.cropping(to:crop.pixelRect(in:CGSize(width:original.width,height:original.height)))!
 var watermark=Watermark();watermark.text="CROP";watermark.position=0;watermark.scale=0.1;watermark.opacity=1
 var invisible=watermark;invisible.opacity=0
 let referenceURL=root.appendingPathComponent("reference-marked-\(turn).mov")
 try await Transcode.run(input:input,output:referenceURL,start:0,end:1,maxEdge:0,fps:30,hevc:true,quarterTurns:turn,watermark:invisible)
 let reference=try await frame(referenceURL)
 let referenceCut=reference.cropping(to:crop.pixelRect(in:CGSize(width:reference.width,height:reference.height)))!
 let expectedVideo=watermark.applying(to:referenceCut)
 let expected=watermark.applying(to:cut)
 let output=root.appendingPathComponent("marked-\(turn).mov")
 try await Transcode.run(input:input,output:output,start:0,end:1,maxEdge:0,fps:30,hevc:true,quarterTurns:turn,watermark:watermark,crop:crop)
 let video=try await frame(output)
 XCTAssertEqual(video.width,expected.width);XCTAssertEqual(video.height,expected.height)
 XCTAssertLessThan(difference(video,expectedVideo),10,"crop + watermark orientation \(turn)")
 XCTAssertGreaterThan(minimumBorderRGB(video),50)
 print("cropWatermarkGeometryMAE turn=\(turn): \(difference(video,expectedVideo))")
 let gif=root.appendingPathComponent("marked-\(turn).gif")
 try await GIFExporter.run(input:input,output:gif,start:0,length:0.2,maxEdge:0,fps:30,quarterTurns:turn,watermark:watermark,crop:crop)
 let image=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(gif as CFURL,nil)!,0,nil)!
 XCTAssertEqual(image.width,expected.width);XCTAssertEqual(image.height,expected.height)
 XCTAssertLessThan(difference(image,expected),15,"GIF crop + watermark orientation \(turn)")
 }
 }

 func testCropPrecedesResizeAndFullCropKeepsPassthrough() async throws {
 let input=root.appendingPathComponent("resize.mov");try fixture(input)
 let crop=CropRegion(rect:CGRect(x:0.25,y:0.25,width:0.5,height:0.5))
 let gif=root.appendingPathComponent("resize.gif")
 try await GIFExporter.run(input:input,output:gif,start:0,length:0.2,maxEdge:100,fps:30,crop:crop)
 let image=CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(gif as CFURL,nil)!,0,nil)!
 XCTAssertEqual(image.width,100);XCTAssertEqual(image.height,75)
 let video=root.appendingPathComponent("resize-crop.mov")
 try await Transcode.run(input:input,output:video,start:0,end:1,maxEdge:100,fps:30,hevc:true,crop:crop)
 let track=try await AVURLAsset(url:video).loadTracks(withMediaType:.video).first!
 let size=try await track.load(.naturalSize)
 XCTAssertEqual(size.width,100);XCTAssertEqual(size.height,74)
 var recipe=LivePreparation(input:input,start:0,length:1,cover:0.5,custom:false,edge:0,fps:0,hevc:true,mute:false,turns:0,watermark:nil)
 recipe.crop = .full
 XCTAssertFalse(recipe.reencodes)
 let pair=try await recipe.generate(in:root.appendingPathComponent("full"))
 XCTAssertTrue(pair.videoWasCopied)
 let full=try await frame(pair.movURL)
 XCTAssertEqual(full.width,320);XCTAssertEqual(full.height,240)
 }

 func testInvalidMutatedCropFailsBeforeCreatingOutput() async throws {
 let input=root.appendingPathComponent("invalid.mov");try fixture(input)
 for rect in [CGRect(x:Double.nan,y:0,width:0.5,height:0.5),CGRect(x:2,y:0,width:0.5,height:0.5)] {
 var crop=CropRegion.full;crop.rect=rect
 let video=root.appendingPathComponent("invalid-output.mov"),gif=root.appendingPathComponent("invalid-output.gif")
 do {try await Transcode.run(input:input,output:video,start:0,end:1,maxEdge:0,fps:30,hevc:true,crop:crop);XCTFail("Invalid crop accepted")} catch {}
 do {try await GIFExporter.run(input:input,output:gif,start:0,length:0.2,maxEdge:0,fps:30,crop:crop);XCTFail("Invalid crop accepted")} catch {}
 XCTAssertFalse(FileManager.default.fileExists(atPath:video.path));XCTAssertFalse(FileManager.default.fileExists(atPath:gif.path))
 var recipe=LivePreparation(input:input,start:0,length:1,cover:0.5,custom:false,edge:0,fps:0,hevc:true,mute:false,turns:0,watermark:nil);recipe.crop=crop
 do {_=try await recipe.generate(in:root.appendingPathComponent("invalid-live"));XCTFail("Invalid recipe accepted")} catch {}
 XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("invalid-live").path))
 }
 }
 private func minimumBorderRGB(_ image:CGImage)->Int {
 let w=image.width,h=image.height
 var bytes=[UInt8](repeating:0,count:w*h*4)
 bytes.withUnsafeMutableBytes { buffer in
 let c=CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
 }
 var minimum=765
 for y in 0..<h {for x in 0..<w where x==0 || y==0 || x==w-1 || y==h-1 {let i=(y*w+x)*4;minimum=min(minimum,Int(bytes[i])+Int(bytes[i+1])+Int(bytes[i+2]))}}
 return minimum
 }

 private func frame(_ url:URL) async throws -> CGImage {
 let generator=AVAssetImageGenerator(asset:AVURLAsset(url:url));generator.appliesPreferredTrackTransform=true
 return try await generator.image(at:CMTime(seconds:0.5,preferredTimescale:600)).image
 }
 private func pixels(_ image:CGImage)->[UInt8] {
 var bytes=[UInt8](repeating:0,count:64*64*4)
 bytes.withUnsafeMutableBytes { buffer in
 let c=CGContext(data:buffer.baseAddress,width:64,height:64,bitsPerComponent:8,bytesPerRow:256,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c.draw(image,in:CGRect(x:0,y:0,width:64,height:64))
 };return bytes
 }
 private func difference(_ a:CGImage,_ b:CGImage)->Double {
 let aa=pixels(a),bb=pixels(b)
 return zip(aa,bb).map{abs(Double($0)-Double($1))}.reduce(0,+)/Double(aa.count)
 }
 private func fixture(_ url:URL,oriented:Bool=false) throws {
 let writer=try AVAssetWriter(outputURL:url,fileType:.mov)
 let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:320,AVVideoHeightKey:240,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:2_000_000]])
 if oriented { input.transform=CGAffineTransform(a:0,b:1,c:-1,d:0,tx:240,ty:0) }
 let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB])
 writer.add(input);XCTAssertTrue(writer.startWriting());writer.startSession(atSourceTime:.zero)
 for i in 0..<30 {
 var pixel:CVPixelBuffer?;CVPixelBufferCreate(nil,320,240,kCVPixelFormatType_32ARGB,nil,&pixel)
 let p=pixel!;CVPixelBufferLockBaseAddress(p,[])
 let c=CGContext(data:CVPixelBufferGetBaseAddress(p),width:320,height:240,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(p),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
 let colors:[CGColor]=[NSColor.red.cgColor,NSColor.green.cgColor,NSColor.blue.cgColor,NSColor.yellow.cgColor]
 for q in 0..<4 {c.setFillColor(colors[q]);c.fill(CGRect(x:(q%2)*160,y:(q/2)*120,width:160,height:120))}
 // Asymmetric central stripe ensures crop order and scaling cannot accidentally match.
 c.setFillColor(NSColor.magenta.cgColor);c.fill(CGRect(x:80,y:30,width:24,height:150))
 CVPixelBufferUnlockBaseAddress(p,[])
 while !input.isReadyForMoreMediaData { usleep(1000) }
 XCTAssertTrue(adaptor.append(p,withPresentationTime:CMTime(value:Int64(i),timescale:30)))
 }
 input.markAsFinished();let done=DispatchSemaphore(value:0);writer.finishWriting {done.signal()};done.wait()
 XCTAssertEqual(writer.status,.completed)
 }
}
