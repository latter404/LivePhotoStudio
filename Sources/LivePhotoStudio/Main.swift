import SwiftUI
import AVKit
import Photos
import UniformTypeIdentifiers
import Observation

@MainActor @Observable final class Model {
 static let shared = Model()
 var url: URL?
 var player = AVPlayer()
 var duration = 3.0
 var start = 0.0
 var length = 3.0
 private(set) var durationWasCustomized = false
 var cover = 1.5
 var quarterTurns = 0
 var speed = 1.0
 var outputDuration:Double { length / speed }
 var watermarkEnabled = false
 var watermark = Watermark()
 init() {
 let defaults=UserDefaults.standard
 watermark.text=defaults.string(forKey:"watermark.text") ?? ""
 if let path=defaults.string(forKey:"watermark.imagePath"), !path.isEmpty { watermark.imagePath=path }
 watermark.imageMode=defaults.bool(forKey:"watermark.imageMode")
 if defaults.object(forKey:"watermark.scale") != nil { watermark.scale=min(0.10,max(0.02,defaults.double(forKey:"watermark.scale"))) }
 if defaults.object(forKey:"watermark.opacity") != nil { watermark.opacity=min(1,max(0.15,defaults.double(forKey:"watermark.opacity"))) }
 watermark.position=min(5,max(0,defaults.integer(forKey:"watermark.position")))
 if let value=defaults.object(forKey:"watermark.freeX") as? Double, value.isFinite { watermark.freeX=min(1,max(0,value)) }
 if let value=defaults.object(forKey:"watermark.freeY") as? Double, value.isFinite { watermark.freeY=min(1,max(0,value)) }
 }
 var watermarkPercent:Double {
 get { watermark.scale*100 }
 set { if newValue.isFinite { watermark.scale=(min(10,max(2,newValue))*10).rounded()/1000 } }
 }
 var watermarkOpacityPercent:Double {
 get { watermark.opacity*100 }
 set { if newValue.isFinite { watermark.opacity=min(100,max(15,newValue))/100 } }
 }
 func watermarkChanged() { invalidateCropResult();clearLivePreview() }
 func chooseWatermarkImage() {
  Task { @MainActor in
   guard let url=await FilePanels.selectWatermarkImage() else { return }
   watermark.imagePath=url.standardizedFileURL.path;watermark.imageMode=true
   watermarkChanged();rememberWatermark()
  }
 }
 func removeWatermarkImage() {
  watermark.imagePath=nil;watermark.imageMode=false;watermarkChanged();rememberWatermark()
 }
 func rememberWatermark() {
 let defaults=UserDefaults.standard
 defaults.set(watermark.text,forKey:"watermark.text");defaults.set(watermark.scale,forKey:"watermark.scale")
 defaults.set(watermark.imagePath,forKey:"watermark.imagePath");defaults.set(watermark.imageMode,forKey:"watermark.imageMode")
 defaults.set(watermark.position,forKey:"watermark.position");defaults.set(watermark.opacity,forKey:"watermark.opacity")
 defaults.set(watermark.freeX,forKey:"watermark.freeX");defaults.set(watermark.freeY,forKey:"watermark.freeY")
 }
 var sourceDisplaySize = CGSize(width:16,height:9)
 var activeWatermark: Watermark? { watermarkEnabled && watermark.active ? watermark : nil }
 var orientedDisplaySize: CGSize { quarterTurns % 2 == 0 ? sourceDisplaySize : CGSize(width:sourceDisplaySize.height,height:sourceDisplaySize.width) }
 var cropPreset:CropPreset = .original
 var cropRegion:CropRegion = .full
 var cropEditing=false
 var activeCrop:CropRegion? { cropPreset != .off && !cropRegion.isFull ? cropRegion : nil }
 var displayCropRect:CGRect {
 var rect=activeCrop?.pixelRect(in:orientedDisplaySize) ?? CGRect(origin:.zero,size:orientedDisplaySize)
 if activeCrop != nil && !gifMode { rect.size=CGSize(width:max(2,floor(rect.width/2)*2),height:max(2,floor(rect.height/2)*2)) }
 return rect
 }
 var outputDisplaySize:CGSize { displayCropRect.size }
 func setCropPreset(_ preset:CropPreset) {
 guard !busy else { return }
 let wasFull=cropRegion.isFull
 cropPreset=preset == .off ? .original : preset
 if preset == .off || preset == .original { cropRegion = .full;cropEditing=false }
 else if preset == .free {
 if wasFull { cropRegion=CropRegion(rect:CGRect(x:0.1,y:0.1,width:0.8,height:0.8)) }
 cropEditing=true
 } else {
 cropRegion=preset.fittedRegion(in:orientedDisplaySize,center:CGPoint(x:cropRegion.rect.midX,y:cropRegion.rect.midY));cropEditing=true
 }
 invalidateCropResult()
 }
 func invalidateCropResult() { result=nil;gifResult=nil;savedPhotoAssetID=nil }

 var gifMode = false
 var gifCustom = false
 var gifEdge = 0
 var gifFPS = 0
 var gifResult: URL?
 var lastGIFSize:(recipe:GIFRecipe,bytes:Int64)?
 var currentGIFRecipe:GIFRecipe? {
 guard let url else { return nil }
 return GIFRecipe(input:url,start:start,length:length,maxEdge:gifCustom ? gifEdge : 0,fps:gifCustom ? gifFPS : 0,quarterTurns:quarterTurns,watermark:activeWatermark,crop:activeCrop,speed:speed)
 }
 var custom = false
 var edge = 0
 var fps = 0
 var hevc = true
 var mute = false
 var busy = false
 var status = "所有处理都在本机完成"
 var info = ""
 var thumbnails: [NSImage] = []
 var thumbnailStart=0.0
 var thumbnailSpan=3.0
 @ObservationIgnored private var thumbnailTask:Task<Void,Never>?
 @ObservationIgnored private let thumbnailLoader = ThumbnailLoader()
 var result: ConversionResult?
 var savedPhotoAssetID: String?
 let airDrop=LivePhotoAirDrop()
 var finishedStore = FinishedStore(root:FinishedPreferences.shared.directoryURL)
 var finishedItems: [FinishedItem] = []
 var finishedSelection = Set<UUID>()
 var sessionProcessedIDs = Set<UUID>()
 var sessionProcessedCount: Int { sessionProcessedIDs.count }
 var finishedFocus: UUID?
 var showFinished = false
 var showFinishedSettings = false
 var guideStep:Int?
 var guideOffered=false
 var finishedLoaded = false
 var finishedLoading = false
 var finishedStatus = ""
 var previewResult:ConversionResult?
 private var previewDirectory:URL?
 func currentPreparation()->LivePreparation? {
 guard let url else { return nil }
 return LivePreparation(input:url,start:start,length:length,cover:cover,custom:custom,edge:edge,fps:fps,hevc:hevc,mute:mute,turns:quarterTurns,watermark:activeWatermark,crop:activeCrop,speed:speed)
 }
 func clearLivePreview() {
 previewResult=nil
 if let previewDirectory { try? FileManager.default.removeItem(at:previewDirectory) }
 previewDirectory=nil
 }
 func prepareLivePreview(ready:@escaping()->Void) {
 guard !busy,let recipe=currentPreparation() else { return }
 busy=true;seek();clearLivePreview();status="正在生成当前选区的实况预览…"
 let directory=LivePreparation.temporaryDirectory()
 Task {
 do { previewResult=try await recipe.generate(in:directory);previewDirectory=directory;status="实况已准备好 · 未保存到导出目录";busy=false;ready() }
 catch { try? FileManager.default.removeItem(at:directory);status=error.localizedDescription;busy=false }
 }
 }
 var timelineSpan = 0.0
 var visibleStart = 0.0
 var visibleDuration: Double { timelineSpan == 0 ? duration : min(timelineSpan,duration) }
 func browseTimeline(to value:Double) {
 guard !busy,value.isFinite else { return }
 let offset=min(max(0,start-visibleStart),max(0,visibleDuration-length))
 visibleStart=min(max(0,value),max(0,duration-visibleDuration))
 start=min(max(0,visibleStart+offset),max(0,duration-length))
 seek()
 }
 func centerTimeline() { visibleStart = min(max(0,start + length/2 - visibleDuration/2),max(0,duration-visibleDuration)) }
 func handle(_ u: URL) { guard !busy else { return }; if u.isFileURL { load(u) } else if ["livephotostudio","livephotostudio-test"].contains(u.scheme ?? ""), let path=URLComponents(url:u,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="path"})?.value { gifMode=false;load(URL(fileURLWithPath:path)) } }
 var previewing = false
 private var boundaryObserver: Any?
 func choose() {
 guard !busy else { return };busy=true
 ExportDiagnostics.begin("open")
 Task {
 let selected=await FilePanels.selectVideo()
 busy=false
 if let selected { load(selected) }
 }
 }

 static func validDisplaySize(_ size:CGSize)->Bool {
 size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1 && size.width <= 65536 && size.height <= 65536
 }
 func load(_ u: URL) {
 guard !busy else { return }; busy = true
 Task {
 do {
 let a = AVURLAsset(url: u)
 let d = try await a.load(.duration).seconds
 guard d.isFinite, d > 0, let t = try await a.loadTracks(withMediaType: .video).first else { throw EngineError.noVideoTrack }
 let rawSize = try await t.load(.naturalSize); let transform = try await t.load(.preferredTransform); let bounds=CGRect(origin:.zero,size:rawSize).applying(transform); let size=CGSize(width:abs(bounds.width),height:abs(bounds.height)); let rate = try await t.load(.nominalFrameRate)
 guard Self.validDisplaySize(size) else { throw EngineError.cannotRead("视频尺寸或方向信息无效。") }
 sourceDisplaySize = size; quarterTurns = 0; speed = 1; durationWasCustomized = false; lastGIFSize = nil; cropPreset = .original; cropRegion = .full; cropEditing=false; url = u; duration = d; timelineSpan = d > 10 ? 10 : 0; visibleStart = 0; start = 0; length = min(3, d); cover = length / 2; result = nil; savedPhotoAssetID = nil; gifResult = nil
 player.replaceCurrentItem(with: AVPlayerItem(asset: a)); seek()
 info = "\(Int(size.width)) × \(Int(size.height)) · \(String(format: "%.2f", rate)) fps · \(String(format: "%.1f", d)) 秒"
 status = "拖动蓝色选区定位片段，拖动白色标记选择封面"
 thumbnails=[];refreshThumbnails()

 } catch { status = error.localizedDescription }
 busy = false
 }
 }
 func refreshThumbnails() {
 thumbnailTask?.cancel()
 guard let url else { return }
 let begin=visibleStart,span=visibleDuration
 thumbnailTask=Task {
 do {
 try await Task.sleep(nanoseconds:120_000_000)
 let images=try await thumbnailLoader.load(url:url,start:begin,span:span)
 try Task.checkCancellation()
 guard self.url == url, self.visibleStart == begin, self.visibleDuration == span else { return }
 thumbnails=images;thumbnailStart=begin;thumbnailSpan=span
 } catch { /* Cancelled or unavailable thumbnails do not block editing. */ }
 }
 }
 func rotate(_ delta: Int) {
 guard let url, !busy else { return }
 seek(); busy = true
 let next = (quarterTurns + delta + 4) % 4
 Task {
 do {
 let asset = try await Rotation.asset(url:url,turns:next)
 player.replaceCurrentItem(with:AVPlayerItem(asset:asset))
 if cropPreset != .off {
 cropRegion=cropRegion.rotated(clockwise:delta)
 if abs(delta) % 2 == 1 { switch cropPreset {
 case .landscape43:cropPreset = .portrait34
 case .portrait34:cropPreset = .landscape43
 case .landscape32:cropPreset = .portrait23
 case .portrait23:cropPreset = .landscape32
 case .landscape169:cropPreset = .portrait916
 case .portrait916:cropPreset = .landscape169
 default:break
 } }
 }
 quarterTurns = next; result = nil; savedPhotoAssetID = nil; gifResult = nil; seek()
 status = activeCrop != nil ? "方向已更新 · 保留当前裁切范围" : activeWatermark != nil ? "方向已更新 · 文字水印将高质量重新编码" : next == 0 ? "已恢复原始方向 · 视频原画质" : "已旋转 \(next * 90)° · 原画质导出不重新编码、不加黑边"
 } catch { status = error.localizedDescription }
 busy = false
 }
 }
 private var previewGeneration = UUID()
 private var playbackEndObserver:NSObjectProtocol?
 func preview() {
 guard url != nil,!busy else { return }
 if previewing { seek();return }
 seek()
 let generation=UUID();previewGeneration=generation
 previewing=true
 player.isMuted=gifMode || mute
 player.currentItem?.audioTimePitchAlgorithm = .spectral
 player.currentItem?.forwardPlaybackEndTime=CMTime(seconds:start+length,preferredTimescale:60000)
 playbackEndObserver=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:player.currentItem,queue:.main) { [weak self] _ in
 Task { @MainActor in guard let self,self.previewGeneration == generation else { return };self.seek() }
 }
 boundaryObserver=player.addBoundaryTimeObserver(forTimes:[NSValue(time:CMTime(seconds:start+length,preferredTimescale:60000))],queue:.main) { [weak self] in
 Task { @MainActor in guard let self,self.previewGeneration == generation else { return };self.seek() }
 }
 player.seek(to:CMTime(seconds:start,preferredTimescale:60000),toleranceBefore:.zero,toleranceAfter:.zero) { [weak self] finished in
 Task { @MainActor in
 guard let self,finished,self.previewing,self.previewGeneration == generation else { return }
 self.player.playImmediately(atRate:Float(self.speed))
 }
 }
 }
 func seek(to position:Double? = nil) {
 previewGeneration=UUID();previewing=false
 if let boundaryObserver { player.removeTimeObserver(boundaryObserver);self.boundaryObserver=nil }
 if let playbackEndObserver { NotificationCenter.default.removeObserver(playbackEndObserver);self.playbackEndObserver=nil }
 player.pause()
 player.currentItem?.forwardPlaybackEndTime = .invalid
 let time=max(0,min(position ?? start+cover,max(0,duration-1.0/60000)))
 player.seek(to:CMTime(seconds:time,preferredTimescale:60000),toleranceBefore:.zero,toleranceAfter:.zero)
 }
 func trimStart(to position:Double) {
 guard !busy,position.isFinite else { return }
 durationWasCustomized = true
 let end=start+length,absoluteCover=start+cover
 start=min(max(0,position),end-min(0.2,duration));length=end-start
 cover=min(max(0,absoluteCover-start),max(0,length-1.0/60000))
 seek(to:start)
 }
 func trimEnd(to position:Double) {
 guard !busy,position.isFinite else { return }
 durationWasCustomized = true
 length=min(duration-start,max(min(0.2,duration),position-start))
 cover=min(cover,max(0,length-1.0/60000))
 seek(to:start+length-1.0/60000)
 }
 func setSpeed(_ value:Double) {
 guard !busy,MediaTiming.speeds.contains(value) else { return }
 speed=value
 if !durationWasCustomized { resetOutputDuration() }
 else { seek();invalidateCropResult();clearLivePreview() }
 }
 func resetOutputDuration() {
 guard !busy else { return }
 durationWasCustomized=false
 length=min(3*speed,duration)
 start=min(start,max(0,duration-length));cover=length/2
 if length > visibleDuration { timelineSpan=[10.0,30.0,60.0].first(where:{$0 >= length}) ?? 0 }
 centerTimeline();seek();invalidateCropResult();clearLivePreview()
 }
 func export() {
 guard !busy else { return }
 if gifMode { exportGIF();return }
 ExportDiagnostics.begin("live")
 guard let url,let recipe=currentPreparation() else { ExportDiagnostics.record("live.noInput");return }
 ExportDiagnostics.record("live.settings.ready")
 busy=true
 Task {
 defer { busy=false }
 guard let root=await FilePanels.selectExportDirectory() else { status="";return }
 ExportDiagnostics.record("live.playback.stop")
 seek()
 result=nil;savedPhotoAssetID=nil;status="正在生成实况照片…"
 let dir=LivePreparation.temporaryDirectory()
 defer { try? FileManager.default.removeItem(at:dir) }
 let name=String(url.deletingPathExtension().lastPathComponent.prefix(60))+"-实况-"+String(UUID().uuidString.prefix(8))
 do {
 ExportDiagnostics.record("live.generate")
 let r=try await recipe.generate(in:dir)
 ExportDiagnostics.record("live.publish")
 result=try ExportFiles.publish(r,into:root,name:name)
 status="已导出 · \(String(format:"%.2f",r.clipDuration)) 秒 · "+(recipe.reencodes ? "已按设置重新编码" : "视频未经重新编码")
 ExportDiagnostics.record("live.completed")
 } catch { status=error.localizedDescription;ExportDiagnostics.record("live.failed domain=\((error as NSError).domain) code=\((error as NSError).code)") }
 }
 }
 func exportGIF() {
 guard !busy,let url else { return }
 let begin=start,duration=length,edge=gifCustom ? gifEdge : 0,rate=gifCustom ? gifFPS : 0,turns=quarterTurns,mark=activeWatermark,crop=activeCrop,playbackSpeed=speed
 ExportDiagnostics.begin("gif");busy=true
 Task {
 defer { busy=false }
 guard let target=await FilePanels.selectGIFDestination(name:url.deletingPathExtension().lastPathComponent+".gif") else { status="";return }
 ExportDiagnostics.record("gif.playback.stop")
 seek()
 gifResult=nil;result=nil;status="正在生成 GIF…"
 do {
 ExportDiagnostics.record("gif.generate")
 try await GIFExporter.run(input:url,output:target,start:begin,length:duration,maxEdge:edge,fps:rate,quarterTurns:turns,watermark:mark,crop:crop,speed:playbackSpeed) { done,total in
 if done % 5 == 0 { Task { @MainActor in self.status="正在生成 GIF · \(done)/\(total) 帧" } }
 }
 gifResult=target;status="GIF 已导出 · \(String(format:"%.2f",duration/playbackSpeed)) 秒";ExportDiagnostics.record("gif.completed")
 } catch { status=error.localizedDescription;ExportDiagnostics.record("gif.failed domain=\((error as NSError).domain) code=\((error as NSError).code)") }
 }
 }
 func sendAirDrop() {
 if gifMode { sendGIF();return }
 guard !busy,let recipe=currentPreparation() else { return }
 busy=true;seek();status="正在生成当前选区并准备隔空投送…"
 let dir=LivePreparation.temporaryDirectory()
 Task {
 defer { try? FileManager.default.removeItem(at:dir) }
 do {
 let pair=try await recipe.generate(in:dir)
 try await airDrop.send(pair) { [weak self] message in self?.status=message;self?.busy=false }
 status="请在隔空投送窗口选择你的 iPhone"
 } catch { status=error.localizedDescription;busy=false }
 }
 }
 func savePhotos() {
 if gifMode { saveGIFPhotos();return }
 guard !busy,let recipe=currentPreparation() else { return }
 busy=true;seek();status="正在准备添加当前选区到照片…"
 let dir=LivePreparation.temporaryDirectory()
 Task {
 defer { try? FileManager.default.removeItem(at:dir);busy=false }
 let auth=await PHPhotoLibrary.requestAuthorization(for:.addOnly)
 guard auth == .authorized || auth == .limited else { status="请在系统设置中允许添加照片。";return }
 do {
 let pair=try await recipe.generate(in:dir)
 try await PHPhotoLibrary.shared().performChanges {
 let request=PHAssetCreationRequest.forAsset()
 request.addResource(with:.photo,fileURL:pair.imageURL,options:nil)
 request.addResource(with:.pairedVideo,fileURL:pair.movURL,options:nil)
 }
 status="当前选区已添加到「照片」"
 NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:"/System/Applications/Photos.app"),configuration:NSWorkspace.OpenConfiguration(),completionHandler:nil)
 } catch { status=error.localizedDescription }
 }
 }

 func generateGIF(in directory:URL) async throws -> URL {
 guard let url else { throw EngineError.noVideoTrack }
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 let output=directory.appendingPathComponent(url.deletingPathExtension().lastPathComponent+".gif")
 try await GIFExporter.run(input:url,output:output,start:start,length:length,maxEdge:gifCustom ? gifEdge : 0,fps:gifCustom ? gifFPS : 0,quarterTurns:quarterTurns,watermark:activeWatermark,crop:activeCrop,speed:speed)
 return output
 }
 func sendGIF() {
 guard !busy,url != nil else { return }
 busy=true;seek();status="正在准备 GIF 隔空投送…"
 let dir=LivePreparation.temporaryDirectory()
 Task {
 defer { try? FileManager.default.removeItem(at:dir) }
 do {
 let file=try await generateGIF(in:dir)
 try airDrop.sendFile(file) { [weak self] message in self?.status=message;self?.busy=false }
 status="请在隔空投送窗口选择接收设备"
 } catch { status=error.localizedDescription;busy=false }
 }
 }
 func saveGIFPhotos() {
 guard !busy,url != nil else { return }
 busy=true;seek();status="正在添加 GIF 到照片…"
 let dir=LivePreparation.temporaryDirectory()
 Task {
 defer { try? FileManager.default.removeItem(at:dir);busy=false }
 let auth=await PHPhotoLibrary.requestAuthorization(for:.addOnly)
 guard auth == .authorized || auth == .limited else { status="请在系统设置中允许添加照片。";return }
 do {
 let file=try await generateGIF(in:dir)
 try await PHPhotoLibrary.shared().performChanges {
 let request=PHAssetCreationRequest.forAsset()
 request.addResource(with:.photo,fileURL:file,options:nil)
 }
 status="GIF 已添加到「照片」"
 } catch { status=error.localizedDescription }
 }
 }

}
final class Delegate: NSObject, NSApplicationDelegate {
 func applicationDidFinishLaunching(_ notification:Notification) { ExportDiagnostics.install();AppPreferences.shared.applyAppearance() }
 func applicationDidBecomeActive(_ notification:Notification) { AppMenuController.shared.pruneMenus() }
 func applicationWillUpdate(_ notification:Notification) { AppMenuController.shared.pruneMenus() }
 func application(_ application: NSApplication, open urls: [URL]) { if let u = urls.first { Task { @MainActor in Model.shared.handle(u); NSApp.activate(ignoringOtherApps: true) } } }
 func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct LivePhotoStudioApp: App {
 @NSApplicationDelegateAdaptor(Delegate.self) var delegate
 var body: some Scene {
 Window(L("实况工坊"), id:"main") {
 ContentView(model: Model.shared).id(AppPreferences.shared.language.rawValue)
 .environment(\.locale, AppPreferences.shared.locale)
 }.defaultSize(width:1180,height:780).commands { AppCommands() }
 }
}
struct ContentView: View {
 @Bindable var model: Model
 @State private var videoDropTargeted=false
 var body: some View {
 HStack(spacing:0) {
 VStack(alignment:.leading,spacing:16) {
 if model.url != nil { editor }
 else {
 WelcomeView(model:model,dropTargeted:videoDropTargeted)
 }
 }.padding(.leading,20).padding(.vertical,20).frame(maxWidth:.infinity,maxHeight:.infinity).guideTarget(.importVideo)
 VStack(spacing:0) {
 ScrollView { settings.padding(.horizontal,20).padding(.top,20).padding(.bottom,16) }
 .frame(maxHeight:.infinity)
 actions.padding(.horizontal,20).padding(.top,12).padding(.bottom,20)
 }.frame(width:380)
 }.background(Color.primary.opacity(0.045)).background(Color(nsColor:.windowBackgroundColor))
 .frame(minWidth:900,minHeight:640)
 .accessibilityHidden(model.guideStep != nil)
 .task {
 await model.loadFinished()
 if !model.guideOffered { model.guideOffered=true;if !UserDefaults.standard.bool(forKey:"guide.batch.v1") { model.startGuide() } }
 }
 .overlayPreferenceValue(GuideTargetPreferenceKey.self) { anchors in
 if model.guideStep != nil { GuideOverlay(model:model,anchors:anchors) }
 }
 .sheet(isPresented:$model.showFinished) { FinishedView(model:model) }
 .sheet(isPresented:$model.showFinishedSettings) { FinishedSettingsView(model:model) }
 .onOpenURL { model.handle($0) }
 .onChange(of:model.mute) { _,_ in model.player.isMuted=model.gifMode || model.mute }
 .onChange(of:model.gifMode) { _,_ in model.player.isMuted=model.gifMode || model.mute }
 .onChange(of:model.cropRegion) { _,_ in model.invalidateCropResult() }
 .onChange(of:model.visibleStart) { _,_ in model.refreshThumbnails() }
 .onChange(of:model.timelineSpan) { _,_ in model.refreshThumbnails() }
 .onChange(of:model.watermarkEnabled) { _,_ in model.watermarkChanged();model.rememberWatermark() }
 .onChange(of:model.watermark.text) { _,_ in model.watermarkChanged();model.rememberWatermark() }
 .onChange(of:model.watermark.imageMode) { _,_ in model.watermarkChanged();model.rememberWatermark() }
 .onChange(of:model.watermark.imagePath) { _,_ in model.watermarkChanged();model.rememberWatermark() }
 .onChange(of:model.watermark.position) { _,position in if position == 5 { model.cropEditing=false };model.watermarkChanged();model.rememberWatermark() }
 .onChange(of:model.watermark.scale) { _,_ in model.watermarkChanged();model.rememberWatermark() }
 .onChange(of:model.watermark.opacity) { _,_ in model.watermarkChanged();model.rememberWatermark() }
 .onDrop(of:[.fileURL],isTargeted:$videoDropTargeted) { providers in guard !model.busy,let p=providers.first else { return false }; _=p.loadObject(ofClass:URL.self) { u,_ in if let u { Task { @MainActor in model.load(u) } } }; return true }
 }
 var actions:some View { FinishedActions(model:model) }

 var editor: some View {
 VStack(spacing:12) {
 CropVideoCanvas(model:model).frame(maxWidth:.infinity,maxHeight:.infinity).background(.black).clipShape(RoundedRectangle(cornerRadius:10))

 HStack(spacing:10) {
 Text(model.url?.lastPathComponent ?? "").font(.caption.weight(.semibold)).lineLimit(1).truncationMode(.middle).help(model.url?.lastPathComponent ?? "")
 Spacer(minLength:0)
 Text(L(model.info)).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
 }

 Timeline(model:model).frame(height:84).disabled(model.busy)
 ViewThatFits(in:.horizontal) {
 HStack(spacing:10) { timelineRange.fixedSize();Spacer(minLength:8);timelineActions.fixedSize() }
 VStack(alignment:.leading,spacing:8) {
 timelineRange
 HStack { Spacer();timelineActions }
 }
 }.disabled(model.busy)
 if model.visibleDuration < model.duration { HStack { Label(L("浏览"),systemImage:"slider.horizontal.3").font(.caption).foregroundStyle(.secondary); Slider(value:Binding(get:{model.visibleStart},set:{model.browseTimeline(to:$0)}),in:0...max(0.001,model.duration-model.visibleDuration)).accessibilityLabel(L("浏览长视频")); Text("\(model.visibleStart,specifier:"%.1f") s").font(.caption).monospacedDigit().frame(width:55) }.frame(height:18).disabled(model.busy) }
 }
 }
 var timelineRange:some View {
 HStack(spacing:10) {
 Label { Text("\(model.start,specifier:"%.2f")–\(model.start+model.length,specifier:"%.2f") s").monospacedDigit() } icon: { Image(systemName:"clock") }.font(.caption)
 Picker(L("时间轴"),selection:$model.timelineSpan) { Text(L("全片")).tag(0.0); Text(L("10 秒")).tag(10.0); Text(L("30 秒")).tag(30.0); Text(L("60 秒")).tag(60.0) }.labelsHidden().frame(width:90).help(L("时间轴显示范围")).onChange(of:model.timelineSpan) { _,_ in model.centerTimeline() }
 }
 }
 var timelineActions:some View {
 HStack(spacing:10) {
 Button(L(model.previewing ? "停止" : "预览选区"),systemImage:model.previewing ? "stop.fill" : "play.fill") { model.preview() }
 Button(L("重置为 3 秒"),systemImage:"arrow.counterclockwise") { model.resetOutputDuration() }.help(L("将输出时长恢复为 3 秒；素材不足时使用可用长度。拖动选区两端可自定时长。"))
 }
 }
 var settings: some View { EditorInspector(model:model) }

}
struct Timeline: View {
 @Bindable var model: Model
 @State private var dragStart: Double?
 @State private var dragEnd: Double?
 var body: some View {
 GeometryReader { g in
 let w=g.size.width, span=model.visibleDuration, origin=model.visibleStart
 let x=w*(model.start-origin)/span, selectedWidth=w*model.length/span
 VStack(spacing:5) {
 ZStack(alignment:.leading) {
 HStack(spacing:0) { ForEach(Array(model.thumbnails.enumerated()),id:\.offset) { _,img in Image(nsImage:img).resizable().scaledToFill().frame(width:w*model.thumbnailSpan/span/CGFloat(max(1,model.thumbnails.count)),height:54).clipped() } }.frame(width:w*model.thumbnailSpan/span,alignment:.leading).offset(x:w*(model.thumbnailStart-origin)/span).frame(width:w,height:54,alignment:.leading).clipped()
 Color.black.opacity(0.35).frame(width:w,height:54).allowsHitTesting(false)
 RoundedRectangle(cornerRadius:5).fill(Color.accentColor.opacity(0.14)).overlay(RoundedRectangle(cornerRadius:5).stroke(Color.accentColor,lineWidth:3)).frame(width:max(3,selectedWidth),height:58).offset(x:x)
 .gesture(DragGesture().onChanged { v in if dragStart==nil { dragStart=model.start }; model.start=min(max(0,(dragStart ?? 0)+v.translation.width/w*span),model.duration-model.length); model.seek() }.onEnded { _ in dragStart=nil;model.centerTimeline() })
 handle.frame(width:10,height:58).offset(x:x-5).gesture(DragGesture().onChanged { v in if dragEnd==nil { dragEnd=model.start+model.length; dragStart=model.start }; model.trimStart(to:(dragStart ?? 0)+v.translation.width/w*span) }.onEnded { _ in dragStart=nil;dragEnd=nil })
 handle.frame(width:10,height:58).offset(x:x+selectedWidth-5).gesture(DragGesture().onChanged { v in if dragEnd==nil { dragEnd=model.length }; model.trimEnd(to:model.start+(dragEnd ?? 0)+v.translation.width/w*span) }.onEnded { _ in dragEnd=nil })
 Rectangle().fill(.white).frame(width:3,height:64).overlay(Image(systemName:"diamond.fill").font(.system(size:9)).foregroundStyle(.white).offset(y:-29)).frame(width:14).contentShape(Rectangle()).offset(x:w*(model.start+model.cover-origin)/span-7)
 .gesture(DragGesture().onChanged { v in if dragStart==nil { dragStart=model.cover };model.cover=min(max(0,(dragStart ?? 0)+v.translation.width/w*span),max(0,model.length-0.02));model.seek() }.onEnded { _ in dragStart=nil })
 }.frame(width:w,height:64).clipped()
 HStack { ForEach(0..<5) { i in if i>0 { Spacer() }; Text("\(origin+span*Double(i)/4,specifier:"%.1f")s").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary) } }
 }
 }.accessibilityElement(children:.ignore).accessibilityLabel(L("视频选区")).accessibilityValue(L("起点 \(model.start) 秒，长度 \(model.length) 秒")).accessibilityAdjustableAction { direction in switch direction { case .increment:model.start=min(model.duration-model.length,model.start+0.1);case .decrement:model.start=max(0,model.start-0.1);@unknown default:break };model.centerTimeline();model.seek() }
 }
 var handle:some View { RoundedRectangle(cornerRadius:3).fill(.blue).overlay(Capsule().fill(.white).frame(width:2,height:18)) }
}
struct NativePlayer: NSViewRepresentable {
 let player:AVPlayer
 func makeNSView(context:Context)->AVPlayerView { let v=AVPlayerView();v.player=player;v.controlsStyle = .none;v.videoGravity = .resizeAspect;return v }
 func updateNSView(_ view:AVPlayerView,context:Context) { if view.player !== player { view.player=player } }
}
