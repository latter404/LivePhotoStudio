import AVFoundation
import Foundation
import CoreImage

enum Transcode {
 static func run(input: URL, output: URL, start: Double, end: Double, maxEdge: Int, fps: Int, hevc: Bool, quarterTurns: Int = 0, watermark: Watermark? = nil, crop: CropRegion? = nil) async throws {
 guard start.isFinite,end.isFinite,start>=0,end>start,maxEdge>=0,maxEdge<=32768,fps>=0,fps<=240 else { throw EngineError.cannotWrite("导出时间范围、尺寸或帧率无效") }
 try Task.checkCancellation()
 let asset = try await Rotation.asset(url: input, turns: quarterTurns)
 let duration=try await asset.load(.duration).seconds
 guard duration.isFinite,duration>0,start<duration else { throw EngineError.cannotRead("视频时间范围无效") }
 let end=min(end,duration)
 guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw EngineError.noVideoTrack }
 let size = try await track.load(.naturalSize)
 let transform = try await track.load(.preferredTransform)
 let bounds = CGRect(origin: .zero, size: size).applying(transform)
 guard bounds.width.isFinite,bounds.height.isFinite,bounds.width>0,bounds.height>0,bounds.width<=32768,bounds.height<=32768 else { throw EngineError.cannotRead("视频画面尺寸无效或超出支持范围") }
 if let crop {
 let r=crop.rect
 guard r.minX.isFinite,r.minY.isFinite,r.width.isFinite,r.height.isFinite,r.width>0,r.height>0,r.minX>=0,r.minY>=0,r.maxX<=1.00000001,r.maxY<=1.00000001 else { throw EngineError.cannotWrite("裁切范围无效") }
 }
 let activeCrop=crop.flatMap { $0.isFull ? nil : $0 }
 var cropRect=activeCrop?.pixelRect(in:bounds.size) ?? CGRect(origin:.zero,size:bounds.size)
 // Video encoders require even output dimensions. Trim at most one pixel
 // from the right/bottom inside the chosen region; never introduce padding.
 cropRect.size=CGSize(width:floor(cropRect.width/2)*2,height:floor(cropRect.height/2)*2)
 guard cropRect.width>=2,cropRect.height>=2 else { throw EngineError.cannotWrite("裁切区域至少需要 2 × 2 像素") }
 let scale = maxEdge == 0 ? 1 : min(1, Double(maxEdge) / max(cropRect.width, cropRect.height))
 let width = max(2, floor(cropRect.width * scale / 2) * 2)
 let height = max(2, floor(cropRect.height * scale / 2) * 2)
 guard hevc || max(width,height)<=4096 else { throw EngineError.cannotWrite("4K 以上的自定义导出请选择 HEVC 编码。") }
 let composition = AVMutableVideoComposition()
 composition.renderSize = CGSize(width: width, height: height)
 composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
 let sourceFPS = try await track.load(.nominalFrameRate)
 guard sourceFPS.isFinite,sourceFPS>0 else { throw EngineError.cannotRead("视频帧率无效") }
 composition.frameDuration = fps == 0 ? CMTime(seconds: 1 / Double(max(1, sourceFPS)), preferredTimescale: 60000) : CMTime(value: 1, timescale: Int32(fps))
 composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
 composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
 composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
 let instruction = AVMutableVideoCompositionInstruction()
 instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
 let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
 layer.setTransform(transform.concatenating(CGAffineTransform(translationX: -bounds.minX-cropRect.minX, y: -bounds.minY-cropRect.minY)).concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
 instruction.layerInstructions = [layer]; composition.instructions = [instruction]
 var finalComposition = composition
 if let label=watermark?.ciStamp(in:composition.renderSize) {
 let canvas=CGRect(x:0,y:0,width:width,height:height)
 let filtered=AVMutableVideoComposition(asset:asset,applyingCIFiltersWithHandler: { request in
 let source=request.sourceImage
 let sourceWidth=source.extent.width,sourceHeight=source.extent.height
 // Core Image is bottom-left based; editor regions are top-left based.
 let ciCrop=CGRect(x:source.extent.minX+cropRect.minX/bounds.width*sourceWidth,
 y:source.extent.minY+(bounds.height-cropRect.maxY)/bounds.height*sourceHeight,
 width:cropRect.width/bounds.width*sourceWidth,height:cropRect.height/bounds.height*sourceHeight)
 let normalized=source.cropped(to:ciCrop).transformed(by:CGAffineTransform(translationX:-ciCrop.minX,y:-ciCrop.minY)).transformed(by:CGAffineTransform(scaleX:width/ciCrop.width,y:height/ciCrop.height))
 request.finish(with:label.composited(over:normalized).cropped(to:canvas),context:nil)
 })
 filtered.renderSize=composition.renderSize;filtered.frameDuration=composition.frameDuration;filtered.sourceTrackIDForFrameTiming=kCMPersistentTrackID_Invalid
 filtered.colorPrimaries=composition.colorPrimaries;filtered.colorTransferFunction=composition.colorTransferFunction;filtered.colorYCbCrMatrix=composition.colorYCbCrMatrix
 finalComposition=filtered
 }
 let preset = hevc ? (max(width,height)>3840 ? AVAssetExportPresetHEVC7680x4320 : AVAssetExportPresetHEVCHighestQuality) : AVAssetExportPresetHighestQuality
 // AVFoundation can occasionally report a frame rate outside the requested
 // rate after a completed export. Retry once from the original source with a
 // fresh session; never accept a lower frame rate or re-encode a previous result.
 for attempt in 0..<2 {
 try Task.checkCancellation()
 guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw EngineError.cannotWrite("无法创建转码任务") }
 session.videoComposition = finalComposition
 session.outputURL = output; session.outputFileType = .mov
 session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 60000), end: CMTime(seconds: end, preferredTimescale: 60000))
 await session.export()
 guard session.status == .completed else { throw EngineError.cannotWrite(session.error?.localizedDescription ?? "转码失败") }
 let exported=AVURLAsset(url:output)
 guard let outTrack=try await exported.loadTracks(withMediaType:.video).first else { throw EngineError.noVideoTrack }
 let outSize=try await outTrack.load(.naturalSize)
 let outRate=try await outTrack.load(.nominalFrameRate)
 let sizeMatches=abs(outSize.width-width)<2 && abs(outSize.height-height)<2
 let rateMatches=fps==0 || abs(outRate-Float(fps))<0.2
 if sizeMatches && rateMatches { return }
 if sizeMatches && !rateMatches && attempt == 0 {
 // Only a completed output created by this session can reach this branch.
 try Task.checkCancellation()
 try FileManager.default.removeItem(at:output)
 continue
 }
 throw EngineError.cannotWrite("系统编码器输出 \(Int(outSize.width))×\(Int(outSize.height))、\(String(format:"%.2f",outRate)) fps，未达到所选参数，请更换编码或降低设置。")
 }

 }
}
