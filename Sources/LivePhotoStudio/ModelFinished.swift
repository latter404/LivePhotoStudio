import AppKit
import Photos

extension Model {
 var selectedFinished:[FinishedItem] { finishedItems.filter { finishedSelection.contains($0.id) } }
 var finishedExportTitle:String {
 let kinds=Set(selectedFinished.map(\.kind))
 return L(kinds.count > 1 ? "导出文件…" : kinds.first == .gif ? "导出为 GIF 文件…" : "导出为 JPG+MOV 文件…")
 }
 func loadFinished() async {
 guard !finishedLoading, !finishedLoaded else { return }
 finishedLoading=true
 defer { finishedLoading=false }
 do {
 finishedItems=try await finishedStore.load()
 // Existing results are available for browsing after launch, but selecting
 // them for delivery is an explicit action in this session. Newly processed
 // results still accumulate through processCurrent(); refresh keeps selections.
 finishedSelection.removeAll()
 sessionProcessedIDs.removeAll()
 finishedFocus=finishedItems.first?.id;finishedLoaded=true
 if await finishedStore.loadWarningCount > 0 { finishedStatus="部分处理结果无法读取，可在列表中移除。" }
 } catch { finishedStatus=error.localizedDescription }
 }
 func refreshFinished() async {
 do {
 finishedItems=try await finishedStore.load()
 finishedSelection.formIntersection(Set(finishedItems.filter(\.isAvailable).map(\.id)))
 sessionProcessedIDs.formIntersection(Set(finishedItems.filter(\.isAvailable).map(\.id)))
 if !finishedItems.contains(where:{$0.id == finishedFocus}) { finishedFocus=finishedItems.first?.id }
 } catch { finishedStatus=error.localizedDescription }
 }
 func processCurrent() {
 guard !busy,finishedLoaded,let source=url,let recipe=currentPreparation() else { return }
 guard !(watermarkEnabled && watermark.imageMode && !watermark.imageAvailable) else {
  status=L("图片水印文件不可用，请重新选择图片")
  return
 }
 // Freeze every option before starting work; later edits cannot alter a finished item.
 let isGIF=gifMode,begin=start,clipLength=length,title=source.lastPathComponent
 let outputEdge=gifCustom ? gifEdge : 0,outputFPS=gifCustom ? gifFPS : 0
 let turns=quarterTurns,mark=activeWatermark,crop=activeCrop,playbackSpeed=speed,gifRecipe=currentGIFRecipe
 busy=true;seek();status="正在处理…";finishedStatus=""
 let directory=LivePreparation.temporaryDirectory()
 Task {
 defer { try? FileManager.default.removeItem(at:directory);busy=false }
 do {
 let item:FinishedItem
 if isGIF {
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 let file=directory.appendingPathComponent("Animation.gif")
 try await GIFExporter.run(input:source,output:file,start:begin,length:clipLength,maxEdge:outputEdge,fps:outputFPS,quarterTurns:turns,watermark:mark,crop:crop,speed:playbackSpeed)
 item=try await finishedStore.addGIF(file,title:title,start:begin,duration:max(0.02,(clipLength/playbackSpeed*100).rounded()/100),sourceDuration:clipLength)
 if let gifRecipe { lastGIFSize=(gifRecipe,item.byteCount) }
 } else {
 let pair=try await recipe.generate(in:directory)
 item=try await finishedStore.addLive(pair,title:title,start:begin,duration:pair.clipDuration,sourceDuration:clipLength)
 }
 finishedItems.insert(item,at:0);finishedSelection.insert(item.id);sessionProcessedIDs.insert(item.id);finishedFocus=item.id
 status="已完成处理";finishedStatus=""
 } catch { status=error.localizedDescription;finishedStatus=error.localizedDescription }
 }
 }
 func checkedFinished(_ ids:Set<UUID>) async throws -> [FinishedItem] {
 let items=try await finishedStore.validate(ids:ids)
 guard !items.isEmpty,items.allSatisfy(\.isAvailable) else {
 for item in items where !item.isAvailable { if let index=finishedItems.firstIndex(where:{$0.id == item.id}) { finishedItems[index]=item } }
 sessionProcessedIDs.formIntersection(Set(finishedItems.filter(\.isAvailable).map(\.id)))
 throw EngineError.cannotRead("处理结果文件不存在或无法读取。")
 }
 return items
 }
 func completedFinished(_ ids:Set<UUID>,delete:Bool,message:String) async {
 status=message;finishedStatus=message
 guard delete else { return }
 do {
 try await finishedStore.remove(ids:ids)
 await refreshFinished()
 status=message+" · 已移到废纸篓";finishedStatus=status
 } catch { status=message+" · 处理结果清理未完成："+error.localizedDescription;finishedStatus=status;await refreshFinished() }
 }
 func saveFinishedPhotos() {
 let ids=Set(selectedFinished.map(\.id));guard !busy,!ids.isEmpty else { return }
 let shouldDelete=FinishedPreferences.shared.deleteAfterPhotos
 busy=true;seek();status="正在添加处理结果到照片…";finishedStatus=status
 Task {
 defer { busy=false }
 do {
 let items=try await checkedFinished(ids),root=finishedStore.root
 let auth=await PHPhotoLibrary.requestAuthorization(for:.addOnly)
 guard auth == .authorized || auth == .limited else { throw EngineError.cannotWrite("请在系统设置中允许添加照片。") }
 try await PHPhotoLibrary.shared().performChanges {
 for item in items {
 let request=PHAssetCreationRequest.forAsset()
 if item.kind == .livePhoto {
 request.addResource(with:.photo,fileURL:item.imageURL(in:root),options:nil)
 request.addResource(with:.pairedVideo,fileURL:item.movURL(in:root),options:nil)
 } else { request.addResource(with:.photo,fileURL:item.gifURL(in:root),options:nil) }
 }
 }
 await completedFinished(ids,delete:shouldDelete,message:"已添加 \(items.count) 项到照片")
 } catch { status=error.localizedDescription;finishedStatus=status }
 }
 }
 func sendFinished() {
 let ids=Set(selectedFinished.map(\.id));guard !busy,!ids.isEmpty else { return }
 let shouldDelete=FinishedPreferences.shared.deleteAfterAirDrop
 busy=true;seek();status="正在准备批量隔空投送…";finishedStatus=status
 Task {
 do {
 let items=try await checkedFinished(ids),root=finishedStore.root
 let assets:[AirDropAsset]=items.map { item in
 if let pair=item.conversionResult(in:root) { return .livePhoto(pair) }
 return .file(item.gifURL(in:root))
 }
 try await airDrop.sendBatch(assets) { [weak self] message,completed in
 guard let self else { return }
 Task { @MainActor in
 await self.finishAirDrop(ids,windowClosed:completed,delete:shouldDelete,message:message)
 }
 }
 status="请在隔空投送窗口选择接收设备";finishedStatus=status
 } catch { status=error.localizedDescription;finishedStatus=status;busy=false }
 }
 }
 /// AirDrop can call didShareItems even when its chooser was cancelled.
 /// Never infer permission to remove persistent items from that callback alone.
 func finishAirDrop(_ ids:Set<UUID>,windowClosed:Bool,delete:Bool,message:String,
 confirm:@MainActor () async -> Bool = { await FilePanels.confirmAirDropCleanup() }) async {
 defer { busy=false }
 status=message;finishedStatus=message
 guard windowClosed,delete,await confirm() else { return }
 await completedFinished(ids,delete:true,message:message)
 }
 func exportFinished() {
 let ids=Set(selectedFinished.map(\.id));guard !busy,!ids.isEmpty else { return }
 let shouldDelete=FinishedPreferences.shared.deleteAfterExport
 busy=true;seek()
 Task {
 defer { busy=false }
 guard let destination=await FilePanels.selectExportDirectory() else { status="";finishedStatus="";return }
 status="正在导出处理结果…";finishedStatus=status
 do {
 let items=try await checkedFinished(ids)
 _=try await FinishedExport.publish(items,from:finishedStore.root,to:destination)
 await completedFinished(ids,delete:shouldDelete,message:"已导出 \(items.count) 项处理结果")
 } catch { status=error.localizedDescription;finishedStatus=status }
 }
 }
 func removeFinished() {
 let ids=finishedSelection;guard !busy,!ids.isEmpty else { return }
 busy=true
 Task {
 defer { busy=false }
 do { try await finishedStore.remove(ids:ids);finishedStatus="已移到废纸篓" }
 catch { finishedStatus=error.localizedDescription }
 await refreshFinished()
 }
 }
 func chooseFinishedLocation() {
 guard !busy else { return };busy=true
 Task {
 defer { busy=false }
 guard let chosen=await FilePanels.selectFinishedDirectory(current:finishedStore.root) else { return }
 let destination=(chosen.lastPathComponent == "Finished" && chosen.deletingLastPathComponent().lastPathComponent == "LivePhotoStudio" ? chosen : chosen.appendingPathComponent("LivePhotoStudio/Finished",isDirectory:true)).standardizedFileURL
 guard !FinishedStore.sameDirectory(destination,finishedStore.root) else { return }
 let previous=finishedStore,oldIDs=Set(finishedItems.map(\.id))
 finishedStatus="正在移动处理结果…"
 do {
 let items=try await previous.migrate(to:destination)
 FinishedPreferences.shared.setDirectory(destination)
 finishedStore=FinishedStore(root:destination);finishedItems=items;finishedLoaded=true
 finishedSelection.formIntersection(Set(items.filter(\.isAvailable).map(\.id)))
 sessionProcessedIDs.formIntersection(Set(items.filter(\.isAvailable).map(\.id)))
 finishedStatus="保存位置已更新"
 // New copies have been verified before preferences change. Old copies are recoverable.
 do { try await previous.remove(ids:oldIDs) }
 catch { finishedStatus="保存位置已更新，旧位置副本尚未清理。" }
 } catch { finishedStatus=error.localizedDescription }
 }
 }
 func startGuide() {
 guard !busy else { return }
 seek();NSApp.keyWindow?.makeFirstResponder(nil)
 showFinished=false;showFinishedSettings=false
 Task { @MainActor in await Task.yield();guideStep=0 }
 }
 func finishGuide() { guideStep=nil;UserDefaults.standard.set(true,forKey:"guide.batch.v1") }
}

extension Model {
 var allFinishedSelected:Bool { !finishedItems.isEmpty && Set(finishedItems.map(\.id)).isSubset(of:finishedSelection) }
 func toggleAllFinished() {
 guard !busy else {return}
 finishedSelection=allFinishedSelected ? [] : Set(finishedItems.map(\.id))
 }
 var canCollage:Bool { (2...9).contains(selectedFinished.count) && selectedFinished.allSatisfy{$0.kind == .livePhoto && $0.isAvailable} }
 func createCollage(ids:[UUID],options:CollageOptions) async throws {
 guard !busy,Set(ids).count==ids.count,(2...9).contains(ids.count) else {throw EngineError.cannotWrite(L("请选择 2–9 张实况照片"))}
 busy=true;seek();finishedStatus=L("正在生成实况拼图…")
 let temporary=LivePreparation.temporaryDirectory()
 defer {busy=false;try? FileManager.default.removeItem(at:temporary)}
 do {
 let validated=try await checkedFinished(Set(ids))
 let items=try ids.map { id -> FinishedItem in
 guard let item=validated.first(where:{$0.id==id}),item.kind == .livePhoto else {throw EngineError.cannotRead(L("拼图仅支持实况照片"))};return item
 }
 let pair=try await LiveCollage.generate(inputs:items.map{$0.movURL(in:finishedStore.root)},options:options,in:temporary)
 try Task.checkCancellation()
 let item=try await finishedStore.addLive(pair,title:L("实况拼图"),start:0,duration:pair.clipDuration,sourceDuration:pair.clipDuration)
 finishedItems.insert(item,at:0);finishedSelection=[item.id];sessionProcessedIDs.insert(item.id);finishedFocus=item.id
 finishedStatus=L("拼图已生成，原实况已保留。");status="已完成处理"
 } catch {
 finishedStatus=error is CancellationError ? L("已取消拼图") : error.localizedDescription
 throw error
 }
 }
}
