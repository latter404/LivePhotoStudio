import SwiftUI
import Photos
import PhotosUI
import ImageIO

struct FinishedActions:View {
 @Bindable var model:Model
 var body:some View {
 VStack(spacing:8) {
 statusBanner
 Button { model.processCurrent() } label: {
 HStack(spacing:8) {
  Image(systemName:"sparkles")
   .symbolEffect(.pulse,options:.repeating,isActive:model.busy)
  Text(L(model.busy ? "处理中…" : "处理"))
 }
 .font(.headline)
 .frame(maxWidth:.infinity,minHeight:34)
 }.buttonStyle(.borderedProminent).controlSize(.large)
 .disabled(model.url == nil || model.busy || !model.finishedLoaded)
 .guideTarget(.process)
 HStack(spacing:10) {
  Button { model.savePhotos() } label: {
   Label(L("添加到照片"),systemImage:"photo.on.rectangle").frame(maxWidth:.infinity).frame(height:32)
  }.buttonStyle(.bordered).controlSize(.large).disabled(model.url == nil || model.busy)
  Button { model.sendAirDrop() } label: {
   Label(L("隔空投送"),systemImage:"antenna.radiowaves.left.and.right").frame(maxWidth:.infinity).frame(height:32)
  }.buttonStyle(.bordered).controlSize(.large).disabled(model.url == nil || model.busy)
 }.guideTarget(.delivery)
 HStack(spacing:10) {
  Button { model.export() } label: { Label(L("导出"),systemImage:"folder").frame(maxWidth:.infinity).frame(height:32) }
   .buttonStyle(.bordered).controlSize(.large).disabled(model.url == nil || model.busy)
  Button { model.seek();model.showFinished=true } label: {
   Label(L("已处理"),systemImage:"square.stack").frame(maxWidth:.infinity).frame(height:32)
  }.buttonStyle(.bordered).controlSize(.large).disabled(model.busy).guideTarget(.collection)
   .overlay(alignment:.topTrailing) {
    if model.sessionProcessedCount > 0 {
     Text("\(model.sessionProcessedCount)").font(.system(size:11,weight:.semibold,design:.rounded)).foregroundStyle(.white)
      .padding(.horizontal,6).frame(minWidth:20,minHeight:20).background(.red,in:Capsule()).overlay(Capsule().stroke(.background,lineWidth:2)).offset(x:8,y:-8)
    }
   }
 }
 }
 }

 @ViewBuilder private var statusBanner:some View {
  let visible = !model.busy && !model.status.isEmpty && !["所有处理","拖动蓝色","已旋转","方向已","已恢复","已取消","已完成处理","已导出","GIF 已导出","当前选区已添加"].contains(where:{model.status.hasPrefix($0)})
  let error = model.status.contains("失败") || model.status.contains("无法") || model.status.contains("错误") || model.status.contains("不支持") || model.status.contains("异常")
  if visible {
   HStack(alignment:.center,spacing:7) {
    Image(systemName:error ? "exclamationmark.triangle.fill" : "info.circle.fill")
     .foregroundStyle(error ? Color.red : Color.secondary)
    Text(L(model.status))
     .font(.caption)
     .foregroundStyle(error ? Color.red : Color.primary)
     .lineLimit(2)
     .frame(maxWidth:.infinity,alignment:.leading)
     .textSelection(.enabled)
   }
   .padding(.horizontal,9)
   .frame(maxWidth:.infinity,minHeight:36,maxHeight:36,alignment:.center)
   .background((error ? Color.red : Color.secondary).opacity(0.12),in:RoundedRectangle(cornerRadius:8))
  } else {
   Color.clear.frame(height:0)
  }
 }
}

struct FinishedDelivery:View {
 @Bindable var model:Model
 var body:some View {
 HStack(spacing:10) {
 Button { model.saveFinishedPhotos() } label: {
 Label(L("添加到照片"),systemImage:"photo.on.rectangle").frame(maxWidth:.infinity).frame(height:32)
 }.controlSize(.large).help(L("将所选处理结果添加到照片"))
 Button { model.sendFinished() } label: {
 Label(L("隔空投送"),systemImage:"antenna.radiowaves.left.and.right").frame(maxWidth:.infinity).frame(height:32)
 }.controlSize(.large).help(L("发送所选处理结果"))
 }.buttonStyle(.bordered).buttonBorderShape(.capsule)
 .frame(minWidth:330)
 .disabled(model.busy || model.selectedFinished.isEmpty || model.selectedFinished.contains(where:{!$0.isAvailable}))
 }
}

struct FinishedView:View {
 @Bindable var model:Model
 @Environment(\.dismiss) private var dismiss
 @State private var showCollage=false
 @State private var showContextGuide=false
 var body:some View {
 VStack(spacing:0) {
 HStack {
 Label(L("已处理"),systemImage:"square.stack").font(.title2.weight(.semibold))
 Spacer()
 Button(L("完成")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
 }.padding(20)
 Divider()
 if model.finishedItems.isEmpty {
 ContentUnavailableView(L("还没有处理结果"),systemImage:"square.stack",description:Text(L("选好片段后点击「处理」，处理结果会保存在这里。")))
 .frame(maxWidth:.infinity,maxHeight:.infinity)
 } else {
 HStack(spacing:0) {
 List {
 ForEach(model.finishedItems) { item in
 HStack(spacing:10) {
 Toggle(isOn:Binding(get:{model.finishedSelection.contains(item.id)},set:{selected in
 if selected { model.finishedSelection.insert(item.id) } else { model.finishedSelection.remove(item.id) }
 })) { Text(item.title) }.labelsHidden().toggleStyle(.checkbox)
 .accessibilityLabel(L("选择处理结果")+" "+item.title)
 Button { model.finishedFocus=item.id } label: {
 HStack(spacing:10) {
 FinishedThumbnail(url:item.thumbnailURL(in:model.finishedStore.root)).frame(width:56,height:56).background(.quaternary,in:RoundedRectangle(cornerRadius:6)).clipped()
 VStack(alignment:.leading,spacing:5) {
 Text(item.title).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
 Text("\(item.start,specifier:"%.2f")–\(item.start+(item.sourceDuration ?? item.duration),specifier:"%.2f") s").font(.caption).monospacedDigit().foregroundStyle(.secondary)
 HStack(spacing:8) {
  Label(item.isAvailable ? (item.kind == .gif ? "GIF" : "LIVE") : L("文件不可用"),systemImage:item.isAvailable ? (item.kind == .gif ? "photo" : "livephoto") : "exclamationmark.triangle")
  Text(ByteCountFormatter.string(fromByteCount:item.byteCount,countStyle:.file)).monospacedDigit()
 }.font(.caption2).foregroundStyle(item.isAvailable ? Color.secondary : Color.orange)
 }.frame(maxWidth:.infinity,alignment:.leading)
 }
 }.buttonStyle(.plain)
 }.padding(.vertical,4)
 .listRowBackground(model.finishedFocus == item.id ? Color.accentColor.opacity(0.10) : Color.clear)
 }
 }.listStyle(.inset).frame(width:330).disabled(model.busy)
 Divider()
 if let item=model.finishedItems.first(where:{$0.id == model.finishedFocus}) {
 FinishedPreview(item:item,root:model.finishedStore.root).id(item.id).padding(16).frame(maxWidth:.infinity,maxHeight:.infinity)
 } else { Color.clear.frame(maxWidth:.infinity,maxHeight:.infinity) }
 }
 }
 Divider()
 VStack(spacing:12) {
 HStack(spacing:12) {
 Button { model.toggleAllFinished() } label: {
 Label(L("全选"),systemImage:model.allFinishedSelected ? "checkmark.circle.fill" : "circle")
 }.overlay(alignment:.topTrailing) {
 }.help(L(model.allFinishedSelected ? "再次点击取消全选" : "选择全部处理结果"))
 Button(L("拼图"),systemImage:"square.grid.2x2") { showCollage=true }.disabled(!model.canCollage).help(L("请选择 2–9 张实况照片"))
 Button { model.exportFinished() } label: { Label(L("导出"),systemImage:"folder") }.buttonStyle(.bordered).controlSize(.small).help(L("导出所选处理结果")).disabled(model.finishedSelection.isEmpty)
 Button(L("删除"),systemImage:"trash",role:.destructive) { model.removeFinished() }.disabled(model.finishedSelection.isEmpty)
 Spacer()
 FinishedDelivery(model:model)
 }.disabled(model.busy).contextGuideTarget(.finishedActions)
 }.padding(20)
 }.frame(width:820,height:560).interactiveDismissDisabled(model.busy)
 .sheet(isPresented:$showCollage) { CollageView(model:model) }
 .overlayPreferenceValue(ContextGuideTargetPreferenceKey.self) { anchors in
  if showContextGuide {
   ContextGuideOverlay(target:.finishedActions,symbol:"square.and.arrow.up",title:UIStrings.isEnglish ? "Batch actions" : "批量操作",detail:UIStrings.isEnglish ? "Select one or more results, then add them to Photos, AirDrop, export, or create a collage from this action area." : "选择一个或多个处理结果后，可以在这里添加到照片、隔空投送、导出，或生成实况拼图。",anchors:anchors) {
    showContextGuide=false
    UserDefaults.standard.set(true,forKey:"guide.finished.v1")
   }
  }
 }
 .onAppear {
  if model.finishedFocus == nil { model.finishedFocus=model.finishedItems.first?.id }
  if !model.finishedItems.isEmpty && !UserDefaults.standard.bool(forKey:"guide.finished.v1") { showContextGuide=true }
 }
 }
}

private struct FinishedThumbnail:View {
 let url:URL
 var body:some View {
 if let image=NSImage(contentsOf:url) { Image(nsImage:image).resizable().scaledToFit() }
 else { Image(systemName:"photo").foregroundStyle(.secondary) }
 }
}

private struct FinishedPreview:View {
 let item:FinishedItem
 let root:URL
 @State private var loader=FinishedLiveLoader()
 @State private var playing=false
 @State private var play=0
 var body:some View {
 VStack(spacing:12) {
 ZStack {
 if !item.isAvailable { ContentUnavailableView(L("文件不可用"),systemImage:"exclamationmark.triangle") }
 else if let photo=loader.photo { LivePhotoPlayer(photo:photo,play:play).frame(maxWidth:.infinity,maxHeight:.infinity) }
 else if playing && item.kind == .gif { FinishedGIFPreview(url:item.gifURL(in:root)) }
 else {
 FinishedCover(url:item.kind == .livePhoto ? item.imageURL(in:root) : item.gifURL(in:root)).frame(maxWidth:.infinity,maxHeight:.infinity)
 if loader.loading { ProgressView().padding(10).background(.regularMaterial,in:Circle()) }
 }
 }.frame(maxWidth:.infinity,maxHeight:.infinity).clipped()
  // The first click loads the native PHLivePhoto view and starts playback.
  // Once it is present, the system view supplies its own Live Photo badge and
  // hover-to-play interaction.
  .contentShape(Rectangle())
  .onTapGesture {
   guard item.kind == .livePhoto, item.isAvailable, !loader.loading else { return }
   if loader.photo != nil { play += 1 }
   else { loader.load(item:item,root:root); play += 1 }
  }
 if loader.failed { Text(L("无法预览此处理结果")).font(.caption).foregroundStyle(.secondary) }
 if item.kind == .gif {
  Button(L(playing ? "停止预览" : "预览 GIF"),systemImage:playing ? "stop.fill" : "play.fill") {
   playing.toggle()
  }.disabled(!item.isAvailable || loader.loading)
 }
 }
 .onDisappear { loader.cancel() }
 }
}

/// Only the focused item gets a larger cover; list rows keep their small thumbnails.
private struct FinishedCover:View {
 let url:URL
 @State private var image:CGImage?
 var body:some View {
 Group {
 if let image { Image(decorative:image,scale:1).resizable().scaledToFit() }
 else { ProgressView().controlSize(.small) }
 }.task(id:url) {
 let file=url
 let result=await Task.detached(priority:.userInitiated) { () -> CGImage? in
 guard let source=CGImageSourceCreateWithURL(file as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary) else { return nil }
 return CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1200,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
 }.value
 guard !Task.isCancelled else { return }
 image=result
 }
 }
}

@MainActor @Observable private final class FinishedLiveLoader {
 var photo:PHLivePhoto?
 var loading=false
 var failed=false
 private var request:PHLivePhotoRequestID=PHLivePhotoRequestIDInvalid
 private var generation=UUID()
 func load(item:FinishedItem,root:URL) {
 cancel();loading=true;failed=false
 let token=generation
 request=PHLivePhoto.request(withResourceFileURLs:[item.imageURL(in:root),item.movURL(in:root)],placeholderImage:nil,targetSize:CGSize(width:600,height:440),contentMode:.aspectFit) { [weak self] photo,info in
 guard info[PHLivePhotoInfoIsDegradedKey] as? Bool != true else { return }
 Task { @MainActor in
 guard let self,self.generation == token else { return }
 self.photo=photo;self.loading=false;self.failed=photo == nil;self.request=PHLivePhotoRequestIDInvalid
 }
 }
 }
 func cancel() {
 generation=UUID()
 if request != PHLivePhotoRequestIDInvalid { PHLivePhoto.cancelRequest(withRequestID:request) }
 request=PHLivePhotoRequestIDInvalid;photo=nil;loading=false
 }
}

