import SwiftUI
import ImageIO

struct CollageView:View {
 @Bindable var model:Model
 @Environment(\.dismiss) private var dismiss
 @State private var items:[FinishedItem]
 @State private var sizes:[CGSize]=[]
 @State private var options=CollageOptions()
 @State private var task:Task<Void,Never>?
 @State private var error=""
 @State private var draggedItem:UUID?
 @State private var previewLoader=CollageLivePreviewLoader()
 @State private var showContextGuide=false
 init(model:Model) {
  self.model=model
  _items=State(initialValue:model.selectedFinished)
  _options=State(initialValue:{var value=CollageOptions();value.includeFirstAudio=true;return value}())
 }
 private var maximumDuration:Double { min(30,items.map(\.duration).min() ?? 3) }
 private var geometry:CollageGeometry? {try? CollageGeometry(sizes:sizes,layout:options.layout,maxEdge:options.maxEdge)}
 var body:some View {
 VStack(alignment:.leading,spacing:16) {
 HStack {Label(L("实况拼图"),systemImage:"square.grid.2x2").font(.title2.weight(.semibold));Spacer()}
 HStack(alignment:.top,spacing:24) {
 CollageLivePreview(items:items,root:model.finishedStore.root,options:options,loader:previewLoader) {
  GeometryReader { proxy in
   if let geometry {
    let scale=min(proxy.size.width/geometry.size.width,proxy.size.height/geometry.size.height)
    ZStack(alignment:.topLeading) {
     ForEach(Array(items.enumerated()),id:\.element.id) { index,item in
      if index<geometry.rects.count {
       let rect=geometry.rects[index]
       Image(nsImage:NSImage(contentsOf:item.thumbnailURL(in:model.finishedStore.root)) ?? NSImage()).resizable()
       .frame(width:rect.width*scale,height:rect.height*scale)
       .overlay(alignment:.topLeading) {
        Button { options.includeFirstAudio=true;options.audioIndex=index } label: {
         HStack(spacing:3) { Text("\(index+1)").monospacedDigit(); Image(systemName: options.includeFirstAudio && options.audioIndex == index ? "speaker.wave.2.fill" : "speaker.slash") }
         .font(.caption.bold()).padding(.horizontal,6).padding(.vertical,4).background(.regularMaterial,in:Capsule()).padding(4)
        }.buttonStyle(.plain).help(L("选择这张的声音"))
       }
       .contentShape(Rectangle())
       .onDrag { draggedItem=item.id;return NSItemProvider(object:item.id.uuidString as NSString) }
       .onDrop(of:[.text],delegate:CollageDropDelegate(item:item,items:$items,sizes:$sizes,draggedItem:$draggedItem,audioIndex:$options.audioIndex))
       .offset(x:rect.minX*scale,y:rect.minY*scale)
      }
     }
    }.frame(width:geometry.size.width*scale,height:geometry.size.height*scale,alignment:.topLeading).frame(maxWidth:.infinity,maxHeight:.infinity)
   } else {ProgressView().frame(maxWidth:.infinity,maxHeight:.infinity)}
  }
 }
 .frame(minWidth:350).clipped().background(.black.opacity(0.05),in:RoundedRectangle(cornerRadius:10))
 VStack(alignment:.leading,spacing:14) {
 collageSettingRow("布局",symbol:"rectangle.split.3x1") {
  Picker(selection:$options.layout) {ForEach(CollageLayout.allCases) {layout in Label(layout.title,systemImage:layout.symbol).tag(layout)}} label: {EmptyView()}
   .labelsHidden().pickerStyle(.menu)
 }
 collageSettingRow("分辨率",symbol:"arrow.up.left.and.arrow.down.right") {
  Picker(selection:$options.maxEdge) {
   Text("480p").tag(854); Text("720p").tag(1280); Text("1080p").tag(1920)
   Text("2K").tag(2560); Text("4K").tag(3840); Text("8K").tag(7680); Text(L("原始")).tag(0)
  } label: {EmptyView()}
   .labelsHidden().pickerStyle(.menu)
 }
 collageSettingRow("帧率",symbol:"film") {
  Picker(selection:$options.fps) {ForEach([24,25,30,50,60],id:\.self) {Text("\($0) fps").tag($0)}} label: {EmptyView()}
   .labelsHidden().pickerStyle(.menu)
 }
 collageSettingRow("时长",symbol:"clock") {
  Picker(selection:$options.duration) {
   ForEach(durationOptions,id:\.self) { value in Text(String(format:"%.2f s",value)).monospacedDigit().tag(value) }
  } label: {EmptyView()}
   .labelsHidden().pickerStyle(.menu).help(L("不超过最短片段，默认最多 3 秒。"))
 }
 Spacer(minLength:0)
 }.frame(width:280,alignment:.trailing).disabled(model.busy)
 }.frame(maxWidth:.infinity,alignment:.leading).frame(height:350)
 if !error.isEmpty {Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)}
 HStack(alignment:.center,spacing:12) {
 Text(L("拼图会高质量重新编码为 SDR。原实况保留，生成后仅选中新拼图。"))
  .font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal:false,vertical:true)
  .frame(maxWidth:.infinity,alignment:.leading)
 if model.busy {ProgressView().controlSize(.small);Text(L("正在生成实况拼图…")).font(.caption).lineLimit(1)}
 Button(L("取消")) {if model.busy {task?.cancel()} else {dismiss()}}.keyboardShortcut(.cancelAction)
 Button(L("生成拼图"),systemImage:"square.grid.2x2") {
 task=Task {
 do {try await model.createCollage(ids:items.map(\.id),options:options);dismiss()}
 catch is CancellationError {error=""}
 catch {self.error=error.localizedDescription}
 }
 }.buttonStyle(.borderedProminent).disabled(model.busy || geometry==nil).keyboardShortcut(.defaultAction).contextGuideTarget(.collageGenerate)
 }
 }.padding(20).frame(width:720).interactiveDismissDisabled(model.busy)
 .overlayPreferenceValue(ContextGuideTargetPreferenceKey.self) { anchors in
  if showContextGuide {
   ContextGuideOverlay(target:.collageGenerate,symbol:"square.grid.2x2",title:UIStrings.isEnglish ? "Create the collage" : "生成实况拼图",detail:UIStrings.isEnglish ? "Arrange the selected Live Photos, choose the output settings, then create one new Live Photo here." : "调整选中的实况照片排版和输出参数，然后在这里生成一张新的实况拼图。",anchors:anchors) {
    showContextGuide=false
    UserDefaults.standard.set(true,forKey:"guide.collage.v1")
   }
  }
 }
 .task {
 options.duration=min(3,maximumDuration)
 let urls=items.map{$0.imageURL(in:model.finishedStore.root)}
 sizes=await Task.detached(priority:.userInitiated) {
 urls.map {url in
 guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let values=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any],let w=values[kCGImagePropertyPixelWidth as String] as? Double,let h=values[kCGImagePropertyPixelHeight as String] as? Double else {return CGSize.zero}
 return CGSize(width:w,height:h)
 }
 }.value
 }
 .onAppear {
  if !UserDefaults.standard.bool(forKey:"guide.collage.v1") { showContextGuide=true }
 }
 }


 private func collageSettingRow<Control:View>(_ title:String,symbol:String,@ViewBuilder control:()->Control) -> some View {
  HStack(spacing:12) {
   Label(L(title),systemImage:symbol)
    .frame(maxWidth:.infinity,alignment:.leading)
   control()
    .frame(width:156,alignment:.trailing)
  }
  .frame(maxWidth:.infinity,alignment:.trailing)
 }

 private var durationOptions:[Double] {
  let maximum=max(0.1,maximumDuration)
  var values=Array(stride(from:0.1,through:maximum,by:0.1)).map { ($0 * 100).rounded() / 100 }
  if let last=values.last, abs(last-maximum)>0.001 { values.append(maximum) }
  return values
 }
}

private struct CollageDropDelegate:DropDelegate {
 let item:FinishedItem
 @Binding var items:[FinishedItem]
 @Binding var sizes:[CGSize]
 @Binding var draggedItem:UUID?
 @Binding var audioIndex:Int
 func dropEntered(info:DropInfo) {
  guard let draggedItem,draggedItem != item.id,
        let from=items.firstIndex(where:{$0.id==draggedItem}),
        let to=items.firstIndex(where:{$0.id==item.id}),from != to,
        sizes.count == items.count else {return}
  withAnimation(.easeInOut(duration:0.12)) {
   let movedItem=items.remove(at:from),movedSize=sizes.remove(at:from)
   items.insert(movedItem,at:to);sizes.insert(movedSize,at:to)
   if audioIndex == from { audioIndex=to }
   else if from < to, audioIndex > from, audioIndex <= to { audioIndex -= 1 }
   else if to < from, audioIndex >= to, audioIndex < from { audioIndex += 1 }
  }
 }
 func performDrop(info:DropInfo)->Bool {draggedItem=nil;return true}
}
