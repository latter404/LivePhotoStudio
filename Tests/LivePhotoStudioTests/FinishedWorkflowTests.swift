import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import LivePhotoStudio

final class FinishedWorkflowTests:XCTestCase {
 @MainActor func testCleanupPreferencesDefaultOffAndRemainIndependent() {
 let suite="FinishedWorkflowTests-"+UUID().uuidString
 let defaults=UserDefaults(suiteName:suite)!
 defer { defaults.removePersistentDomain(forName:suite) }
 let initial=FinishedPreferences(defaults:defaults)
 XCTAssertFalse(initial.deleteAfterPhotos);XCTAssertFalse(initial.deleteAfterAirDrop);XCTAssertFalse(initial.deleteAfterExport)
 initial.deleteAfterExport=true
 initial.setDirectory(URL(fileURLWithPath:"/tmp/ExampleFinishedItems",isDirectory:true))
 let restored=FinishedPreferences(defaults:defaults)
 XCTAssertFalse(restored.deleteAfterPhotos);XCTAssertFalse(restored.deleteAfterAirDrop);XCTAssertTrue(restored.deleteAfterExport)
 XCTAssertEqual(restored.directoryURL.path,"/tmp/ExampleFinishedItems")
 }
 @MainActor func testSuccessfulActionKeepsItemsByDefaultAndOnlyTrashesSelectedWhenEnabled() async throws {
 let scratch=FileManager.default.temporaryDirectory.appendingPathComponent("FinishedWorkflowTests-"+UUID().uuidString)
 defer { try? FileManager.default.removeItem(at:scratch) }
 let trash=scratch.appendingPathComponent("Trash",isDirectory:true),root=scratch.appendingPathComponent("Finished",isDirectory:true)
 try FileManager.default.createDirectory(at:trash,withIntermediateDirectories:true)
 let source=scratch.appendingPathComponent("source.gif")
 let context=CGContext(data:nil,width:16,height:16,bitsPerComponent:8,bytesPerRow:64,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 context.setFillColor(CGColor(red:0.2,green:0.4,blue:0.6,alpha:1));context.fill(CGRect(x:0,y:0,width:16,height:16))
 let destination=CGImageDestinationCreateWithURL(source as CFURL,UTType.gif.identifier as CFString,1,nil)!
 CGImageDestinationAddImage(destination,context.makeImage()!,nil);XCTAssertTrue(CGImageDestinationFinalize(destination))
 let original=try Data(contentsOf:source)
 let store=FinishedStore(root:root,trash:{ url in try FileManager.default.moveItem(at:url,to:trash.appendingPathComponent(url.lastPathComponent)) })
 let first=try await store.addGIF(source,title:"One",start:0,duration:3)
 let second=try await store.addGIF(source,title:"Two",start:3,duration:3)
 let model=Model();model.finishedStore=store
 await model.loadFinished()
 // Cleanup must preserve the user's remaining selection, rather than relying
 // on historical results being automatically selected when the app launches.
 model.finishedSelection=[first.id,second.id]
 await model.completedFinished([first.id],delete:false,message:"Done")
 XCTAssertEqual(model.finishedItems.count,2)
 // A system "didShare" callback can be a cancelled AirDrop chooser.
 // With cleanup enabled, declining confirmation must preserve every item.
 model.busy=true
 await model.finishAirDrop([first.id],windowClosed:true,delete:true,message:"Closed",confirm:{ false })
 XCTAssertEqual(model.finishedItems.count,2);XCTAssertFalse(model.busy)
 XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:trash.path).isEmpty)
 await model.finishAirDrop([first.id],windowClosed:false,delete:true,message:"Failed",confirm:{ XCTFail("Failure must not ask to clean up");return true })
 await model.finishAirDrop([first.id],windowClosed:true,delete:false,message:"Closed",confirm:{ XCTFail("Cleanup is disabled");return true })
 XCTAssertEqual(model.finishedItems.count,2)
 await model.finishAirDrop([first.id],windowClosed:true,delete:true,message:"Received",confirm:{ true })
 XCTAssertEqual(model.finishedItems.map(\.id),[second.id])
 XCTAssertEqual(model.finishedSelection,[second.id])
 XCTAssertTrue(FileManager.default.fileExists(atPath:trash.appendingPathComponent(first.id.uuidString).path))
 XCTAssertEqual(try Data(contentsOf:source),original)
 XCTAssertEqual(try Data(contentsOf:second.gifURL(in:root)),original)
 }
}
