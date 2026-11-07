import AVFoundation
import Foundation

enum CollageLayout:String,CaseIterable,Identifiable {
 case grid,horizontal,vertical
 var id:String {rawValue}
 var title:String { switch self {case .grid:return L("网格");case .horizontal:return L("横向");case .vertical:return L("纵向")} }
 var symbol:String {switch self {case .grid:return "square.grid.2x2";case .horizontal:return "rectangle.split.3x1";case .vertical:return "rectangle.split.1x2"}}
}

/// Rows share a width and tiles share their row height. Every tile keeps its
/// aspect ratio (apart from pixel rounding), so mixed orientations need no bars.
struct CollageGeometry {
 let size:CGSize
 let rects:[CGRect]
 init(sizes:[CGSize],layout:CollageLayout,maxEdge:Int) throws {
 guard (2...9).contains(sizes.count),maxEdge>=2,maxEdge<=7680,
 sizes.allSatisfy({$0.width.isFinite && $0.height.isFinite && $0.width>=2 && $0.height>=2}) else {throw EngineError.cannotWrite(L("拼图参数无效"))}
 let columns=layout == .horizontal ? sizes.count : layout == .vertical ? 1 : Int(ceil(sqrt(Double(sizes.count))))
 let rows=stride(from:0,to:sizes.count,by:columns).map{Array($0..<min($0+columns,sizes.count))}
 let ratios=sizes.map{$0.width/$0.height}
 let rowRatios=rows.map{$0.reduce(0){$0+ratios[$1]}}
 let naturalWidth=zip(rows,rowRatios).map { row,sum in row.map{sizes[$0].height}.min()! * sum }.min()!
 let relativeHeight=rowRatios.reduce(0){$0+1/$1}
 let scale=min(1,Double(maxEdge)/max(naturalWidth,naturalWidth*relativeHeight))
 let w=max(2,floor(naturalWidth*scale/2)*2),h=max(2,floor(naturalWidth*relativeHeight*scale/2)*2)
 size=CGSize(width:w,height:h)
 var rectangles:[CGRect]=[],y=0.0,relativeY=0.0
 for (r,row) in rows.enumerated() {
 relativeY += 1/rowRatios[r]
 let endY=r == rows.count-1 ? h : (h*relativeY/relativeHeight).rounded()
 var x=0.0,cumulative=0.0
 for (i,index) in row.enumerated() {
 cumulative += ratios[index]
 let endX=i == row.count-1 ? w : (w*cumulative/rowRatios[r]).rounded()
 guard endX>x,endY>y else {throw EngineError.cannotWrite(L("拼图尺寸过小"))}
 rectangles.append(CGRect(x:x,y:y,width:endX-x,height:endY-y));x=endX
 }
 y=endY
 }
 rects=rectangles
 }
}

struct CollageOptions {
 var layout:CollageLayout = .grid
 var maxEdge=3840
 var fps=30
 var duration=3.0
 var includeFirstAudio=false
 var audioIndex=0
}

enum LiveCollage {
 static func generate(inputs:[URL],options:CollageOptions,in directory:URL) async throws -> ConversionResult {
 guard (2...9).contains(inputs.count),[24,30,50,60].contains(options.fps),options.duration.isFinite,options.duration>0,options.duration<=30 else {throw EngineError.cannotWrite(L("拼图参数无效"))}
 try Task.checkCancellation()
 // A caller owns this new directory. Never overwrite an existing result.
 guard !FileManager.default.fileExists(atPath:directory.path) else {throw EngineError.cannotWrite(L("拼图目录已存在"))}
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 var succeeded=false
 defer {if !succeeded {try? FileManager.default.removeItem(at:directory)}}
 let composition=AVMutableComposition()
 let assets=inputs.map { AVURLAsset(url:$0) }
 defer {withExtendedLifetime(assets) {}}
 var tracks:[AVAssetTrack]=[],sizes:[CGSize]=[],transforms:[CGAffineTransform]=[],durations:[Double]=[]
 for asset in assets {
 try Task.checkCancellation()
 guard let track=try await asset.loadTracks(withMediaType:.video).first else {throw EngineError.noVideoTrack}
 let duration=try await asset.load(.duration).seconds
 let size=try await track.load(.naturalSize),transform=try await track.load(.preferredTransform)
 let bounds=CGRect(origin:.zero,size:size).applying(transform)
 guard duration.isFinite,duration>0,bounds.width>0,bounds.height>0 else {throw EngineError.cannotRead(L("拼图片段无效"))}
 tracks.append(track);sizes.append(bounds.size);durations.append(duration)
 transforms.append(transform.concatenating(CGAffineTransform(translationX:-bounds.minX,y:-bounds.minY)))
 }
 let seconds=min(options.duration,durations.min()!)
 let time=CMTime(seconds:seconds,preferredTimescale:60000),range=CMTimeRange(start:.zero,duration:time)
 let geometry=try CollageGeometry(sizes:sizes,layout:options.layout,maxEdge:options.maxEdge)
 var layers:[AVMutableVideoCompositionLayerInstruction]=[]
 for index in tracks.indices {
 guard let target=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else {throw EngineError.cannotWrite(L("无法创建拼图轨道"))}
 try target.insertTimeRange(range,of:tracks[index],at:.zero)
 let rect=geometry.rects[index],source=sizes[index]
 let layer=AVMutableVideoCompositionLayerInstruction(assetTrack:target)
 layer.setTransform(transforms[index].concatenating(CGAffineTransform(scaleX:rect.width/source.width,y:rect.height/source.height)).concatenating(CGAffineTransform(translationX:rect.minX,y:rect.minY)),at:.zero)
 layers.append(layer)
 }
 if options.includeFirstAudio {
 let audioInputIndex=min(max(0,options.audioIndex),inputs.count-1)
 let asset=AVURLAsset(url:inputs[audioInputIndex])
 for audio in try await asset.loadTracks(withMediaType:.audio) where try await audio.load(.isEnabled) {
 let available=CMTimeRangeGetIntersection(range,otherRange:try await audio.load(.timeRange))
 if available.duration > .zero,let target=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) {try target.insertTimeRange(available,of:audio,at:available.start)}
 break
 }
 }
 let video=AVMutableVideoComposition();video.renderSize=geometry.size;video.frameDuration=CMTime(value:1,timescale:Int32(options.fps))
 video.sourceTrackIDForFrameTiming=kCMPersistentTrackID_Invalid
 video.colorPrimaries=AVVideoColorPrimaries_ITU_R_709_2;video.colorTransferFunction=AVVideoTransferFunction_ITU_R_709_2;video.colorYCbCrMatrix=AVVideoYCbCrMatrix_ITU_R_709_2
 let instruction=AVMutableVideoCompositionInstruction();instruction.timeRange=range;instruction.layerInstructions=layers;video.instructions=[instruction]
 let movie=directory.appendingPathComponent("Composition.mov")
 guard let export=AVAssetExportSession(asset:composition,presetName:max(geometry.size.width,geometry.size.height)>3840 ? AVAssetExportPresetHEVC7680x4320 : AVAssetExportPresetHEVCHighestQuality) else {throw EngineError.cannotWrite(L("无法创建拼图任务"))}
 export.outputURL=movie;export.outputFileType = .mov;export.videoComposition=video;export.timeRange=range
 await withTaskCancellationHandler(operation:{await export.export()},onCancel:{export.cancelExport()})
 try Task.checkCancellation()
 guard export.status == .completed else {throw EngineError.cannotWrite(export.error?.localizedDescription ?? L("拼图生成失败"))}
 let out=AVURLAsset(url:movie)
 guard let track=try await out.loadTracks(withMediaType:.video).first else {throw EngineError.noVideoTrack}
 let outSize=try await track.load(.naturalSize),rate=try await track.load(.nominalFrameRate),duration=try await out.load(.duration).seconds
 guard outSize==geometry.size,abs(rate-Float(options.fps))<0.2,abs(duration-seconds)<0.035 else {throw EngineError.cannotWrite(L("拼图输出参数不一致"))}
 var settings=ConversionSettings();settings.trimEnd=seconds;settings.frameTime=seconds/2
 let pair=try await LivePhotoEngine.convert(input:movie,outputDir:directory,baseName:"LiveCollage",settings:settings)
 try FileManager.default.removeItem(at:movie);succeeded=true
 return ConversionResult(imageURL:pair.imageURL,movURL:pair.movURL,assetID:pair.assetID,baseName:pair.baseName,clipDuration:pair.clipDuration,videoWasCopied:false)
 }
}
