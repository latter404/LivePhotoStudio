import SwiftUI
import Photos

/// Lazily builds a short, temporary Live Photo pair for the collage preview.
/// The pair is kept outside the finished-results store and removed when the
/// preview is cancelled or the collage window disappears.
@MainActor @Observable
final class CollageLivePreviewLoader {
 var photo:PHLivePhoto?
 var loading=false
 var failed=false
 private var task:Task<Void,Never>?
 private var request:PHLivePhotoRequestID=PHLivePhotoRequestIDInvalid
 private var outputDirectory:URL?
 private var generation=UUID()

 func load(items:[FinishedItem],root:URL,options:CollageOptions) {
  guard !items.isEmpty else { return }
  cancel()
  loading=true;failed=false
  let token=generation
  // Keep preview work responsive on 4K/8K selections. The final Generate
  // action still uses the exact user-selected resolution.
  var previewOptions=options
  previewOptions.maxEdge=min(max(options.maxEdge,480),1920)
  previewOptions.duration=min(options.duration,3.0)
  let directory=LivePreparation.temporaryDirectory()
  outputDirectory=directory
  let movies=items.map{$0.movURL(in:root)}
  task=Task { [weak self] in
   do {
    let pair=try await LiveCollage.generate(inputs:movies,options:previewOptions,in:directory)
    try Task.checkCancellation()
    let live=try await Self.requestPhoto(image:pair.imageURL,movie:pair.movURL)
    guard let self,self.generation == token else { return }
    self.photo=live;self.loading=false;self.failed=live == nil
   } catch is CancellationError {
    guard let self,self.generation == token else { return }
    self.loading=false
   } catch {
    guard let self,self.generation == token else { return }
    self.loading=false;self.failed=true
   }
  }
 }

 func cancel() {
  generation=UUID()
  task?.cancel();task=nil
  if request != PHLivePhotoRequestIDInvalid { PHLivePhoto.cancelRequest(withRequestID:request) }
  request=PHLivePhotoRequestIDInvalid
  photo=nil;loading=false;failed=false
  if let directory=outputDirectory { try? FileManager.default.removeItem(at:directory) }
  outputDirectory=nil
 }

 private static func requestPhoto(image:URL,movie:URL) async throws -> PHLivePhoto? {
  try await withTaskCancellationHandler(operation: {
   await withCheckedContinuation { continuation in
    let request=PHLivePhoto.request(withResourceFileURLs:[image,movie],placeholderImage:nil,targetSize:CGSize(width:1200,height:900),contentMode:.aspectFit) { photo,info in
     guard info[PHLivePhotoInfoIsDegradedKey] as? Bool != true else { return }
     continuation.resume(returning:photo)
    }
    // The request is retained by Photos until completion. Cancellation of
    // the outer task is handled by `cancel()` on the owning loader.
    _ = request
   }
  },onCancel:{})
 }
}

/// Shared interaction wrapper for the collage preview. The caller supplies
/// the normal static layout as `content`; the first click swaps in the native
/// PHLivePhoto view and starts playback. Subsequent hover playback is handled
/// by PHLivePhotoView itself.
struct CollageLivePreview<Content:View>:View {
 let items:[FinishedItem]
 let root:URL
 let options:CollageOptions
 @Bindable var loader:CollageLivePreviewLoader
 let content:Content
 @State private var play=0

 init(items:[FinishedItem],root:URL,options:CollageOptions,loader:CollageLivePreviewLoader,@ViewBuilder content:()->Content) {
  self.items=items;self.root=root;self.options=options;self.loader=loader;self.content=content()
 }

 var body:some View {
  ZStack {
   if let photo=loader.photo {
    LivePhotoPlayer(photo:photo,play:play).frame(maxWidth:.infinity,maxHeight:.infinity)
   } else {
    content
    if loader.loading { ProgressView().padding(10).background(.regularMaterial,in:Circle()) }
    if loader.failed { Image(systemName:"exclamationmark.triangle").foregroundStyle(.secondary) }
   }
  }
  .contentShape(Rectangle())
  .onTapGesture {
   guard !loader.loading else { return }
   if loader.photo != nil { play += 1 }
   else { loader.load(items:items,root:root,options:options);play += 1 }
  }
  .onChange(of: options.fingerprint) { _,_ in loader.cancel() }
  .onDisappear { loader.cancel() }
 }
}

private extension CollageOptions {
 var fingerprint:String { "\(layout.rawValue)|\(maxEdge)|\(fps)|\(duration)|\(includeFirstAudio)|\(audioIndex)" }
}
