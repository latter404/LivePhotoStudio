import SwiftUI
import Photos
import PhotosUI

struct LivePreview: View {
 let result:ConversionResult
 @Environment(\.dismiss) private var dismiss
 @State private var photo:PHLivePhoto?
 @State private var failed=false
 @State private var play=0
 var body:some View {
 VStack(spacing:14) {
 HStack { Label(L("实况照片预览"),systemImage:"livephoto").font(.headline);Spacer();Button(L("完成")) { dismiss() } }
 if let photo { LivePhotoPlayer(photo:photo,play:play).frame(maxWidth:.infinity,maxHeight:.infinity);Button(L("播放实况"),systemImage:"play.fill") { play += 1 }.buttonStyle(.borderedProminent) }
 else if failed { Text(L("系统无法加载这组实况文件，请重新导出。")).frame(maxWidth:.infinity,maxHeight:.infinity) }
 else { ProgressView(L("正在加载实况…")).frame(maxWidth:.infinity,maxHeight:.infinity) }
 Text(L("这里播放的是按当前选区和设置生成的实况。关闭预览后可直接点击「隔空投送」，发送完整实况包到 iPhone。")).font(.callout).foregroundStyle(.secondary)
 }.padding(20).frame(width:640,height:600)
 .task {
 let loaded:PHLivePhoto?=await withCheckedContinuation { continuation in
 PHLivePhoto.request(withResourceFileURLs:[result.imageURL,result.movURL],placeholderImage:nil,targetSize:CGSize(width:600,height:450),contentMode:.aspectFit) { photo,info in
 if info[PHLivePhotoInfoIsDegradedKey] as? Bool == true { return }
 continuation.resume(returning:photo)
 }
 }
 photo=loaded;failed=loaded == nil
 }
 }
}
struct LivePhotoPlayer:NSViewRepresentable {
 let photo:PHLivePhoto
 let play:Int
 class Coordinator { var play=0 }
 func makeCoordinator()->Coordinator { Coordinator() }
 func makeNSView(context:Context)->PHLivePhotoView { let view=PHLivePhotoView();view.livePhoto=photo;return view }
 func updateNSView(_ view:PHLivePhotoView,context:Context) {
 if view.livePhoto !== photo { view.livePhoto=photo }
 if context.coordinator.play != play { context.coordinator.play=play;view.startPlayback(with:.full) }
 }
}
