import AppKit
import UniformTypeIdentifiers

/// PVT layout follows the interoperable makelive format (see Licenses/makelive-MIT.txt).
/// The image and video are copied unchanged, never transcoded for sharing.
enum LivePhotoPackage {
 static func create(from pair:ConversionResult, in directory:URL) async throws -> URL {
 try Task.checkCancellation()
 for url in [pair.imageURL,pair.movURL] {
 guard url.isFileURL else { throw EngineError.cannotRead("处理结果文件不存在或无法读取。") }
 let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
 guard values.isRegularFile == true,values.isSymbolicLink != true,(values.fileSize ?? 0)>0 else {
 throw EngineError.cannotRead("处理结果文件不存在或无法读取。")
 }
 }
 let checks=await Verifier.verify(imageURL:pair.imageURL,movURL:pair.movURL)
 try Task.checkCancellation()
 guard checks.allSatisfy({$0.status == .pass}) else { throw EngineError.cannotWrite("实况文件不完整或配对校验失败，请重新导出。") }
 // Keep a caller-supplied display name from introducing path components.
 let baseName=pair.baseName.replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:":",with:"_")
 var package=directory.appendingPathComponent((baseName.isEmpty ? "LivePhoto" : baseName)+".pvt",isDirectory:true)
 guard !FileManager.default.fileExists(atPath:package.path) else { throw EngineError.cannotWrite("分享包已存在，请重试。") }
 try FileManager.default.createDirectory(at:package,withIntermediateDirectories:true)
 do {
 try FileManager.default.copyItem(at:pair.imageURL,to:package.appendingPathComponent(pair.imageURL.lastPathComponent))
 try Task.checkCancellation()
 try FileManager.default.copyItem(at:pair.movURL,to:package.appendingPathComponent(pair.movURL.lastPathComponent))
 try Task.checkCancellation()
 let metadata=try PropertyListSerialization.data(fromPropertyList:["PFVideoComplementMetadataVersionKey":"1"],format:.xml,options:0)
 try metadata.write(to:package.appendingPathComponent("metadata.plist"),options:.atomic)
 var values=URLResourceValues();values.isPackage=true;try package.setResourceValues(values)
 return package
 } catch { try? FileManager.default.removeItem(at:package);throw error }
 }
}

enum AirDropAsset {
 case livePhoto(ConversionResult)
 case file(URL)
}

/// Creates an isolated, complete transfer set. Callers own the returned directory
/// until the system share service finishes; persistent finished items stay intact.
enum ShareBatch {
 static func prepare(assets:[AirDropAsset],in directory:URL) async throws -> [URL] {
 guard !assets.isEmpty else { throw EngineError.cannotWrite("请选择至少一项处理结果。") }
 let manager=FileManager.default
 guard !manager.fileExists(atPath:directory.path) else { throw EngineError.cannotWrite("分享目录已存在，请重试。") }
 try manager.createDirectory(at:directory,withIntermediateDirectories:true)
 do {
 var items:[URL]=[]
 for (index,asset) in assets.enumerated() {
 try Task.checkCancellation()
 // Separate folders also avoid clashes between equally named Live Photo pairs.
 let itemDirectory=directory.appendingPathComponent(String(format:"%04d",index+1)+"-"+UUID().uuidString,isDirectory:true)
 try manager.createDirectory(at:itemDirectory,withIntermediateDirectories:false)
 switch asset {
 case .livePhoto(let pair):
 items.append(try await LivePhotoPackage.create(from:pair,in:itemDirectory))
 case .file(let file):
 items.append(try copyFile(file,into:itemDirectory))
 }
 }
 try Task.checkCancellation()
 return items
 } catch {
 try? manager.removeItem(at:directory)
 throw error
 }
 }

 static func copyFile(_ file:URL,into directory:URL) throws -> URL {
 guard file.isFileURL else { throw EngineError.cannotRead("处理结果文件不存在或无法读取。") }
 let values=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
 guard values.isRegularFile == true,values.isSymbolicLink != true,(values.fileSize ?? 0)>0 else {
 throw EngineError.cannotRead("处理结果文件不存在或无法读取。")
 }
 let copy=directory.appendingPathComponent(file.lastPathComponent)
 try FileManager.default.copyItem(at:file,to:copy)
 return copy
 }
}

/// A small seam for lifecycle tests; production uses only public AppKit APIs.
@MainActor protocol AirDropSharingService:AnyObject {
 var delegate:(any NSSharingServiceDelegate)? { get set }
 func canPerform(withItems items:[Any]?) -> Bool
 func perform(withItems items:[Any])
}
extension NSSharingService:AirDropSharingService { }

/// Each invocation retains its own delegate. Apple's delegate contract describes
/// the callback service but does not promise object identity with the instance
/// returned by NSSharingService(named:). Associate callbacks with our session
/// token instead of comparing the framework's service objects.
@MainActor private final class AirDropSessionDelegate:NSObject,NSSharingServiceDelegate {
 let token:UUID
 private weak var sourceWindow:NSWindow?
 private let completion:(UUID,String,Bool)->Void
 init(token:UUID,sourceWindow:NSWindow?,completion:@escaping(UUID,String,Bool)->Void) {
 self.token=token;self.sourceWindow=sourceWindow;self.completion=completion
 super.init()
 }
 func sharingService(_ sharingService:NSSharingService,willShareItems items:[Any]) {
 ExportDiagnostics.record("airdrop.delegate.willShare")
 }
 func sharingService(_ sharingService:NSSharingService,didShareItems items:[Any]) {
 ExportDiagnostics.record("airdrop.delegate.didShare")
 completion(token,"隔空投送窗口已关闭 · 发送结果请以系统窗口和接收设备为准",true)
 }
 func sharingService(_ sharingService:NSSharingService,didFailToShareItems items:[Any],error:Error) {
 ExportDiagnostics.record("airdrop.delegate.didFail")
 let message=(error as NSError).code == NSUserCancelledError ? "已取消隔空投送" : "隔空投送未完成："+error.localizedDescription
 completion(token,message,false)
 }
 func sharingService(_ sharingService:NSSharingService,sourceWindowForShareItems items:[Any],sharingContentScope:UnsafeMutablePointer<NSSharingService.SharingContentScope>)->NSWindow? { sourceWindow }
}

@MainActor final class LivePhotoAirDrop {
 private let serviceFactory:()->(any AirDropSharingService)?
 private var service:(any AirDropSharingService)?
 private var delegateBridge:AirDropSessionDelegate?
 private var sessionToken:UUID?
 private var temporaryDirectory:URL?
 private var completion:((String,Bool)->Void)?
 var active:Bool { sessionToken != nil }
 init(serviceFactory:@escaping()->(any AirDropSharingService)? = { NSSharingService(named:.sendViaAirDrop) }) {
 self.serviceFactory=serviceFactory
 }
 func send(_ pair:ConversionResult, completion:@escaping(String)->Void) async throws {
 try await send([.livePhoto(pair)],completion:completion)
 }
 func send(_ assets:[AirDropAsset],completion:@escaping(String)->Void) async throws {
 try await sendBatch(assets) { message,_ in completion(message) }
 }
 /// The Boolean is windowClosed: true means AppKit invoked didShareItems, which
 /// AirDrop can also invoke after cancelling its chooser. It is NOT a delivery
 /// receipt and must never by itself authorize deleting persistent finished
 /// items. False denotes didFailToShareItems, including explicit cancellation.
 func sendBatch(_ assets:[AirDropAsset],completion:@escaping(String,Bool)->Void) async throws {
 let token=try startSession()
 let directory=FileManager.default.temporaryDirectory.appendingPathComponent("LivePhotoAirDrop-"+UUID().uuidString,isDirectory:true)
 do {
 let items=try await ShareBatch.prepare(assets:assets,in:directory)
 try Task.checkCancellation()
 ExportDiagnostics.record("airdrop.prepare.completed")
 try begin(items:items,in:directory,token:token,completion:completion)
 } catch {
 try? FileManager.default.removeItem(at:directory)
 reset(token:token)
 ExportDiagnostics.record("airdrop.prepare.failed")
 throw error
 }
 }
 func sendFile(_ file:URL,completion:@escaping(String)->Void) throws {
 let token=try startSession()
 let directory=FileManager.default.temporaryDirectory.appendingPathComponent("LivePhotoAirDrop-"+UUID().uuidString,isDirectory:true)
 do {
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 let copy=try ShareBatch.copyFile(file,into:directory)
 try begin(items:[copy],in:directory,token:token) { message,_ in completion(message) }
 } catch {
 try? FileManager.default.removeItem(at:directory)
 reset(token:token)
 ExportDiagnostics.record("airdrop.prepare.failed")
 throw error
 }
 }
 private func startSession() throws -> UUID {
 guard !active else { throw EngineError.cannotWrite("请先完成或取消当前隔空投送。") }
 let token=UUID();sessionToken=token
 ExportDiagnostics.record("airdrop.prepare.begin")
 return token
 }
 private func begin(items:[URL],in directory:URL,token:UUID,completion:@escaping(String,Bool)->Void) throws {
 guard sessionToken == token else { throw CancellationError() }
 guard let sharing=serviceFactory(),sharing.canPerform(withItems:items) else { throw EngineError.cannotWrite("当前系统无法启动隔空投送，请检查设备设置后重试。") }
 let bridge=AirDropSessionDelegate(token:token,sourceWindow:NSApp?.keyWindow) { [weak self] token,message,windowClosed in
 self?.finish(token:token,message:message,windowClosed:windowClosed)
 }
 self.completion=completion;temporaryDirectory=directory;service=sharing;delegateBridge=bridge;sharing.delegate=bridge
 ExportDiagnostics.record("airdrop.perform")
 sharing.perform(withItems:items)
 }
 private func reset(token:UUID) {
 guard sessionToken == token else { return }
 if let directory=temporaryDirectory { try? FileManager.default.removeItem(at:directory) }
 temporaryDirectory=nil;service?.delegate=nil;service=nil;delegateBridge=nil;completion=nil;sessionToken=nil
 }
 private func finish(token:UUID,message:String,windowClosed:Bool) {
 guard sessionToken == token else {
 ExportDiagnostics.record("airdrop.callback.stale")
 return
 }
 let callback=completion
 // Reset before invoking the caller: a callback may immediately start a new
 // share, and an old callback must not release that new session's resources.
 reset(token:token)
 // The legacy "completed" log event denotes AppKit's callback, not delivery.
 ExportDiagnostics.record(windowClosed ? "airdrop.session.completed" : "airdrop.session.failedOrCancelled")
 callback?(message,windowClosed)
 }
}
