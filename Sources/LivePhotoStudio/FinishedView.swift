import SwiftUI
import Photos
import PhotosUI
import ImageIO

struct FinishedActions:View {
 @Bindable var model:Model
 var body:some View {
 VStack(spacing:12) {
 Button { model.processCurrent() } label: {
 Label(L("处理"),systemImage:"sparkles").font(.headline).frame(maxWidth:.infinity,minHeight:34)
 }.buttonStyle(.borderedProminent).controlSize(.large)
 .disabled(model.url == nil || model.busy || !model.finishedLoaded)
 .guideTarget(.process)
 .overlay(alignment:.topTrailing) {
 if model.sessionProcessedCount > 0 {
 Button { model.seek();model.showFinished=true } label: {
 Text("\(model.sessionProcessedCount)").font(.system(size:12,weight:.semibold,design:.rounded))
 .foregroundStyle(.white).padding(.horizontal,6).frame(minWidth:23,minHeight:23)
 .background(.red,in:Capsule()).overlay(Capsule().stroke(.background,lineWidth:2))
 .padding(4).contentShape(Rectangle())
 }.buttonStyle(.plain).offset(x:9,y:-11).disabled(model.busy)
 .accessibilityLabel(L("本次已处理")+" \(model.sessionProcessedCount)")
 .help(L("本次处理数量，重启后归零"))
 }
 }
 if !model.finishedItems.isEmpty || model.guideStep != nil {
 Button { model.seek();model.showFinished=true } label: {
 HStack(spacing:5) {
 Image(systemName:"square.stack").foregroundStyle(.primary)
 Text(L("已处理")).foregroundStyle(.primary);Spacer()
 Text(L("已选 \(model.finishedSelection.count)/\(model.finishedItems.count)"))
 Image(systemName:"chevron.right").font(.caption2)
 }.font(.caption).foregroundStyle(.secondary)
 }.buttonStyle(.plain).disabled(model.busy).guideTarget(.collection)
 }
 FinishedDelivery(model:model).guideTarget(.delivery)
 if model.busy || (!model.status.isEmpty && !["所有处理","拖动蓝色","已旋转","方向已","已恢复","已取消","已完成处理"].contains(where:{model.status.hasPrefix($0)})) {
 HStack(alignment:.top,spacing:8) {
 if model.busy { ProgressView().controlSize(.small) }
 Text(L(model.status)).font(.caption).foregroundStyle(.primary).frame(maxWidth:.infinity,alignment:.leading).lineLimit(3).textSelection(.enabled)
 }
 }
 }
 }
}

struct FinishedDelivery:View {
 @Bindable var model:Model
 var body:some View {
 VStack(spacing:10) {
 HStack(spacing:10) {
 Button { model.saveFinishedPhotos() } label: {
 Label(L("添加到照片"),systemImage:"photo.on.rectangle").frame(maxWidth:.infinity)
 }.help(L("将所选处理结果添加到照片"))
 Button { model.sendFinished() } label: {
 Label(L("隔空投送"),systemImage:"antenna.radiowaves.left.and.right").frame(maxWidth:.infinity)
 }.help(L("发送所选处理结果"))
 }.buttonStyle(.bordered).controlSize(.large)
 Button { model.exportFinished() } label: {
 Label(model.finishedExportTitle,systemImage:"folder").frame(maxWidth:.infinity)
 }.buttonStyle(.bordered).controlSize(.large).help(L("导出所选处理结果"))
 }.disabled(model.busy || model.selectedFinished.isEmpty || model.selectedFinished.contains(where:{!$0.isAvailable}))
 }
}

struct FinishedView:View {
 @Bindable var model:Model
 @Environment(\.dismiss) private var dismiss
 var body:some View {
 VStack(spacing:0) {
 HStack {
 Label(L("已处理"),systemImage:"square.stack").font(.title2.weight(.semibold))
 Text("\(model.finishedItems.count)").foregroundStyle(.secondary)
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
 Label(item.isAvailable ? (item.kind == .gif ? "GIF" : "LIVE") : L("文件不可用"),systemImage:item.isAvailable ? (item.kind == .gif ? "photo" : "livephoto") : "exclamationmark.triangle").font(.caption2).foregroundStyle(item.isAvailable ? Color.secondary : Color.orange)
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
 Button(L("全选")) { model.finishedSelection=Set(model.finishedItems.map(\.id)) }
 Button(L("取消全选")) { model.finishedSelection=[] }
 Text(L("已选 \(model.finishedSelection.count)/\(model.finishedItems.count)")).font(.caption).foregroundStyle(.secondary)
 Spacer()
 Button(L("移除"),systemImage:"trash",role:.destructive) { model.removeFinished() }.disabled(model.finishedSelection.isEmpty)
 }.disabled(model.busy)
 HStack(alignment:.bottom,spacing:20) {
 HStack(spacing:8) {
 if model.busy { ProgressView().controlSize(.small) }
 Text(L(model.finishedStatus.isEmpty ? "处理结果保存在本机，关闭窗口后仍会保留。" : model.finishedStatus))
 .font(.caption).foregroundStyle(.secondary).lineLimit(3).frame(maxWidth:.infinity,alignment:.leading)
 }
 FinishedDelivery(model:model).frame(width:300)
 }
 }.padding(20)
 }.frame(width:820,height:560).interactiveDismissDisabled(model.busy)
 .onAppear { if model.finishedFocus == nil { model.finishedFocus=model.finishedItems.first?.id } }
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
 if loader.failed { Text(L("无法预览此处理结果")).font(.caption).foregroundStyle(.secondary) }
 Button(L(item.kind == .gif ? (playing ? "停止预览" : "预览 GIF") : "播放实况"),systemImage:playing && item.kind == .gif ? "stop.fill" : "play.fill") {
 if item.kind == .gif { playing.toggle() }
 else if loader.photo != nil { play += 1 }
 else { loader.load(item:item,root:root);play += 1 }
 }.disabled(!item.isAvailable || loader.loading)
 Text(ByteCountFormatter.string(fromByteCount:item.byteCount,countStyle:.file)).font(.caption).foregroundStyle(.secondary)
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

