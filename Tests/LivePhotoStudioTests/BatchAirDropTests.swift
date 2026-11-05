import XCTest
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
@testable import LivePhotoStudio

final class BatchAirDropTests:XCTestCase {
 private var root:URL!
 override func setUpWithError() throws {
 root=FileManager.default.temporaryDirectory.appendingPathComponent("BatchAirDropTests-"+UUID().uuidString,isDirectory:true)
 try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
 }
 override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }

 func testSameNamedLivePhotosAndGIFsRemainIndependentAndByteIdentical() async throws {
 let pairs=try await makePairs()
 let first=try makeGIF(in:"gif-a",shade:0.2),second=try makeGIF(in:"gif-b",shade:0.8)
 let directory=root.appendingPathComponent("share")
 let items=try await ShareBatch.prepare(assets:[.livePhoto(pairs.0),.livePhoto(pairs.1),.file(first),.file(second)],in:directory)
 XCTAssertEqual(items.count,4)
 XCTAssertEqual(Set(items.map { $0.deletingLastPathComponent() }).count,4)
 for (pair,item) in zip([pairs.0,pairs.1],items.prefix(2)) {
 XCTAssertEqual(item.pathExtension,"pvt")
 let image=item.appendingPathComponent(pair.imageURL.lastPathComponent)
 let video=item.appendingPathComponent(pair.movURL.lastPathComponent)
 XCTAssertEqual(try Data(contentsOf:image),try Data(contentsOf:pair.imageURL))
 XCTAssertEqual(try Data(contentsOf:video),try Data(contentsOf:pair.movURL))
 let checks=await Verifier.verify(imageURL:image,movURL:video)
 XCTAssertTrue(checks.allSatisfy { $0.status == .pass })
 let metadata=try PropertyListSerialization.propertyList(from:Data(contentsOf:item.appendingPathComponent("metadata.plist")),format:nil) as? [String:String]
 XCTAssertEqual(metadata?["PFVideoComplementMetadataVersionKey"],"1")
 }
 XCTAssertNotEqual(pairs.0.assetID,pairs.1.assetID)
 XCTAssertEqual(try Data(contentsOf:items[2]),try Data(contentsOf:first))
 XCTAssertEqual(try Data(contentsOf:items[3]),try Data(contentsOf:second))
 XCTAssertNotEqual(try Data(contentsOf:items[2]),try Data(contentsOf:items[3]))
 // A completed share can discard the transfer set without deleting the shelf.
 try FileManager.default.removeItem(at:directory)
 for file in [pairs.0.imageURL,pairs.0.movURL,pairs.1.imageURL,pairs.1.movURL,first,second] {
 XCTAssertTrue(FileManager.default.fileExists(atPath:file.path))
 }
 }

 func testMissingLaterItemRemovesWholeTransferSetAndLeavesSourceUntouched() async throws {
 let source=try makeGIF(in:"source",shade:0.5),before=try Data(contentsOf:source)
 let directory=root.appendingPathComponent("failed-share")
 do {
 _=try await ShareBatch.prepare(assets:[.file(source),.file(root.appendingPathComponent("missing.gif"))],in:directory)
 XCTFail("An incomplete selection must never be handed to AirDrop")
 } catch { }
 XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
 XCTAssertEqual(try Data(contentsOf:source),before)
 let retry=try await ShareBatch.prepare(assets:[.file(source)],in:directory)
 XCTAssertEqual(retry.count,1)
 }

 func testMismatchedLivePhotoAbortsEntireBatch() async throws {
 let pairs=try await makePairs()
 let wrong=ConversionResult(imageURL:pairs.0.imageURL,movURL:pairs.1.movURL,assetID:pairs.0.assetID,baseName:"Clip",clipDuration:1,videoWasCopied:true)
 let directory=root.appendingPathComponent("mismatched")
 do {
 _=try await ShareBatch.prepare(assets:[.livePhoto(pairs.0),.livePhoto(wrong)],in:directory)
 XCTFail("Mismatched photo/video identifiers must reject the entire batch")
 } catch { }
 XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
 for pair in [pairs.0,pairs.1] {
 let checks=await Verifier.verify(imageURL:pair.imageURL,movURL:pair.movURL)
 XCTAssertTrue(checks.allSatisfy { $0.status == .pass })
 }
 }

 func testExistingDirectoryIsNeverCleanedOnFailure() async throws {
 let directory=root.appendingPathComponent("existing")
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
 let sentinel=directory.appendingPathComponent("keep.txt")
 try Data("user-owned".utf8).write(to:sentinel)
 let source=try makeGIF(in:"source",shade:0.4)
 do { _=try await ShareBatch.prepare(assets:[.file(source)],in:directory);XCTFail("Existing directories must not be reused") }
 catch { }
 XCTAssertEqual(try Data(contentsOf:sentinel),Data("user-owned".utf8))
 }

 func testEmptyAndCancelledBatchesLeaveNoTransferDirectory() async throws {
 let empty=root.appendingPathComponent("empty")
 do { _=try await ShareBatch.prepare(assets:[],in:empty);XCTFail("An empty batch must be rejected") }
 catch { }
 XCTAssertFalse(FileManager.default.fileExists(atPath:empty.path))
 let source=try makeGIF(in:"source",shade:0.5),cancelled=root.appendingPathComponent("cancelled")
 let task=Task {
 withUnsafeCurrentTask { $0?.cancel() }
 return try await ShareBatch.prepare(assets:[.file(source)],in:cancelled)
 }
 do { _=try await task.value;XCTFail("Cancelled preparation must fail") }
 catch { XCTAssertTrue(error is CancellationError) }
 XCTAssertFalse(FileManager.default.fileExists(atPath:cancelled.path))
 XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
 }

 func testFileSymlinkCannotCreateTransferDependingOnPersistentSource() async throws {
 let source=try makeGIF(in:"source",shade:0.7),link=root.appendingPathComponent("link.gif"),directory=root.appendingPathComponent("symlink-share")
 try FileManager.default.createSymbolicLink(at:link,withDestinationURL:source)
 do { _=try await ShareBatch.prepare(assets:[.file(link)],in:directory);XCTFail("Share media must be independent regular files") }
 catch { }
 XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
 XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
 }

 @MainActor func testPreparationFailureReleasesBusyStateForRetryWithoutOpeningService() async throws {
 let airDrop=LivePhotoAirDrop(serviceFactory:{
 XCTFail("Invalid preparation must fail before creating any sharing service")
 return nil
 })
 do { try await airDrop.send([]) { _ in XCTFail("No service should start for empty selection") };XCTFail("Empty selection must fail") }
 catch { }
 XCTAssertFalse(airDrop.active)
 do { try await airDrop.send([.file(root.appendingPathComponent("missing.gif"))]) { _ in XCTFail("No service should start for missing item") };XCTFail("Missing media must fail") }
 catch { }
 XCTAssertFalse(airDrop.active)
 }

 @MainActor func testCompletionFromDifferentServiceObjectReleasesSessionAndTemporaryCopies() async throws {
 let source=try makeGIF(in:"source",shade:0.5)
 let service=TestAirDropSharingService()
 let airDrop=LivePhotoAirDrop(serviceFactory:{ service })
 var outcomes:[Bool]=[]
 try await airDrop.sendBatch([.file(source)]) { _,completed in outcomes.append(completed) }
 XCTAssertTrue(airDrop.active)
 XCTAssertEqual(service.performedItems.count,1)
 let copy=try XCTUnwrap(service.performedItems.first?.first as? URL)
 let directory=copy.deletingLastPathComponent().deletingLastPathComponent()
 XCTAssertTrue(FileManager.default.fileExists(atPath:copy.path))
 let delegate=try XCTUnwrap(service.delegate)
 // The callback object intentionally differs from the object that performed
 // sharing. Session association belongs to the per-invocation delegate.
 delegate.sharingService?(callbackService(),didShareItems:[copy])
 XCTAssertFalse(airDrop.active)
 XCTAssertEqual(outcomes,[true])
 XCTAssertNil(service.delegate)
 XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
 XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
 delegate.sharingService?(callbackService(),didShareItems:[copy])
 XCTAssertEqual(outcomes,[true],"Duplicate callbacks must not complete a session twice")
 }

 @MainActor func testCancellationAndFailureReleaseSessionWithoutReportingSuccess() async throws {
 let source=try makeGIF(in:"source",shade:0.4)
 let service=TestAirDropSharingService()
 let airDrop=LivePhotoAirDrop(serviceFactory:{ service })
 var outcomes:[Bool]=[]
 for error in [NSError(domain:NSCocoaErrorDomain,code:NSUserCancelledError),NSError(domain:NSCocoaErrorDomain,code:NSFileReadUnknownError)] {
 try await airDrop.sendBatch([.file(source)]) { _,completed in outcomes.append(completed) }
 let copy=try XCTUnwrap(service.performedItems.last?.first as? URL)
 let delegate=try XCTUnwrap(service.delegate)
 delegate.sharingService?(callbackService(),didFailToShareItems:[copy],error:error)
 XCTAssertFalse(airDrop.active)
 XCTAssertFalse(FileManager.default.fileExists(atPath:copy.deletingLastPathComponent().deletingLastPathComponent().path))
 XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
 }
 XCTAssertEqual(outcomes,[false,false])
 }

 @MainActor func testOldDelegateCannotFinishOrDeleteANewerSession() async throws {
 let source=try makeGIF(in:"source",shade:0.6)
 let first=TestAirDropSharingService(),second=TestAirDropSharingService()
 var services:[TestAirDropSharingService]=[first,second]
 let airDrop=LivePhotoAirDrop(serviceFactory:{ services.removeFirst() })
 var outcomes:[Bool]=[]
 try await airDrop.sendBatch([.file(source)]) { _,completed in outcomes.append(completed) }
 let oldDelegate=try XCTUnwrap(first.delegate)
 oldDelegate.sharingService?(callbackService(),didShareItems:[])
 try await airDrop.sendBatch([.file(source)]) { _,completed in outcomes.append(completed) }
 let newCopy=try XCTUnwrap(second.performedItems.first?.first as? URL)
 oldDelegate.sharingService?(callbackService(),didFailToShareItems:[],error:NSError(domain:NSCocoaErrorDomain,code:NSUserCancelledError))
 XCTAssertTrue(airDrop.active)
 XCTAssertTrue(FileManager.default.fileExists(atPath:newCopy.path))
 XCTAssertEqual(outcomes,[true])
 let newDelegate=try XCTUnwrap(second.delegate)
 newDelegate.sharingService?(callbackService(),didShareItems:[newCopy])
 XCTAssertFalse(airDrop.active)
 XCTAssertEqual(outcomes,[true,true])
 }

 @MainActor func testSynchronousCompletionCanStartAnotherSessionWithoutOldStateReset() async throws {
 let source=try makeGIF(in:"source",shade:0.3)
 let first=TestAirDropSharingService(),second=TestAirDropSharingService()
 var services:[TestAirDropSharingService]=[first,second]
 let airDrop=LivePhotoAirDrop(serviceFactory:{ services.removeFirst() })
 let callback=callbackService()
 first.onPerform={ [weak first] items in first?.delegate?.sharingService?(callback,didShareItems:items) }
 var outcomes:[Bool]=[]
 var retryError:Error?
 try await airDrop.sendBatch([.file(source)]) { _,completed in
 outcomes.append(completed)
 do { try airDrop.sendFile(source) { _ in } }
 catch { retryError=error }
 }
 XCTAssertNil(retryError)
 XCTAssertEqual(outcomes,[true])
 XCTAssertTrue(airDrop.active,"The new session must survive return from the old send call")
 let copy=try XCTUnwrap(second.performedItems.first?.first as? URL)
 XCTAssertTrue(FileManager.default.fileExists(atPath:copy.path))
 let delegate=try XCTUnwrap(second.delegate)
 delegate.sharingService?(callback,didFailToShareItems:[copy],error:NSError(domain:NSCocoaErrorDomain,code:NSUserCancelledError))
 XCTAssertFalse(airDrop.active)
 }

 // Public custom-service initializer: never requests the built-in AirDrop
 // service. Reuse one inert callback argument instead of repeatedly initializing
 // AppKit sharing machinery. perform(withItems:) is never called on this object.
 @MainActor private static let callbackPlaceholder =
 NSSharingService(title:"Lifecycle Test Callback",image:NSImage(size:NSSize(width:1,height:1)),alternateImage:nil) { }

 @MainActor private func callbackService() -> NSSharingService {
 Self.callbackPlaceholder
 }

 private func makeGIF(in name:String,shade:CGFloat) throws -> URL {
 let directory=root.appendingPathComponent(name,isDirectory:true)
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 let file=directory.appendingPathComponent("Animation.gif")
 let context=try XCTUnwrap(CGContext(data:nil,width:8,height:8,bitsPerComponent:8,bytesPerRow:32,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
 context.setFillColor(gray:shade,alpha:1);context.fill(CGRect(x:0,y:0,width:8,height:8))
 let image=try XCTUnwrap(context.makeImage()),destination=try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL,UTType.gif.identifier as CFString,1,nil))
 CGImageDestinationAddImage(destination,image,nil)
 XCTAssertTrue(CGImageDestinationFinalize(destination))
 return file
 }

 private func makePairs() async throws -> (ConversionResult,ConversionResult) {
 let source=root.appendingPathComponent("source.mp4")
 try await makeVideo(at:source)
 let first=root.appendingPathComponent("pair-a"),second=root.appendingPathComponent("pair-b")
 try FileManager.default.createDirectory(at:first,withIntermediateDirectories:true)
 try FileManager.default.createDirectory(at:second,withIntermediateDirectories:true)
 let a=try await LivePhotoEngine.convert(input:source,outputDir:first,baseName:"Clip",settings:ConversionSettings())
 let b=try await LivePhotoEngine.convert(input:source,outputDir:second,baseName:"Clip",settings:ConversionSettings())
 return (a,b)
 }

 private func makeVideo(at url:URL) async throws {
 let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
 let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:64,AVVideoHeightKey:48])
 let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB])
 writer.add(input);XCTAssertTrue(writer.startWriting());writer.startSession(atSourceTime:.zero)
 for index in 0..<12 {
 var buffer:CVPixelBuffer?
 XCTAssertEqual(CVPixelBufferCreate(nil,64,48,kCVPixelFormatType_32ARGB,nil,&buffer),kCVReturnSuccess)
 let pixels=try XCTUnwrap(buffer)
 CVPixelBufferLockBaseAddress(pixels,[])
 let base=try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
 memset(base,Int32(20+index*5),CVPixelBufferGetDataSize(pixels))
 CVPixelBufferUnlockBaseAddress(pixels,[])
 while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds:1_000_000) }
 XCTAssertTrue(adaptor.append(pixels,withPresentationTime:CMTime(value:Int64(index),timescale:12)))
 }
 input.markAsFinished()
 await withCheckedContinuation { continuation in writer.finishWriting { continuation.resume() } }
 XCTAssertEqual(writer.status,.completed)
 }
}

/// Does not create a sharing window, discover devices, or send any data.
@MainActor private final class TestAirDropSharingService:AirDropSharingService {
 weak var delegate:(any NSSharingServiceDelegate)?
 var performedItems:[[Any]]=[]
 var onPerform:(([Any])->Void)?
 func canPerform(withItems items:[Any]?) -> Bool { !(items?.isEmpty ?? true) }
 func perform(withItems items:[Any]) { performedItems.append(items);onPerform?(items) }
}
