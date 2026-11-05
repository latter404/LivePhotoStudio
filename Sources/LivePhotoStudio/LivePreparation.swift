import Foundation

/// An immutable snapshot shared by preview, AirDrop, Photos and file export.
struct LivePreparation {
 let input:URL
 let start:Double
 let length:Double
 let cover:Double
 let custom:Bool
 let edge:Int
 let fps:Int
 let hevc:Bool
 let mute:Bool
 let turns:Int
 let watermark:Watermark?
 var crop:CropRegion? = nil
 var reencodes:Bool { custom || watermark != nil || (crop != nil && crop?.isFull == false) }
 func generate(in directory:URL) async throws -> ConversionResult {
 if let crop {
 let r=crop.rect
 guard r.minX.isFinite,r.minY.isFinite,r.width.isFinite,r.height.isFinite,r.width>0,r.height>0,r.minX>=0,r.minY>=0,r.maxX<=1.00000001,r.maxY<=1.00000001 else { throw EngineError.cannotWrite("裁切范围无效") }
 }
 do {
 try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 let temp=directory.appendingPathComponent(".transcode.mov")
 defer { try? FileManager.default.removeItem(at:temp) }
 if reencodes { try await Transcode.run(input:input,output:temp,start:start,end:start+length,maxEdge:custom ? edge : 0,fps:custom ? fps : 0,hevc:custom ? hevc : true,quarterTurns:turns,watermark:watermark,crop:crop) }
 var settings=ConversionSettings()
 settings.trimStart=reencodes ? 0 : start;settings.trimEnd=reencodes ? 0 : start+length
 settings.frameTime=max(0,min(cover,length-0.02));settings.dropAudio=mute
 let pair=try await LivePhotoEngine.convert(input:reencodes ? temp : input,outputDir:directory,baseName:"LivePhoto",settings:settings,quarterTurns:reencodes ? 0 : turns)
 guard await Verifier.verify(imageURL:pair.imageURL,movURL:pair.movURL).allSatisfy({$0.status == .pass}) else { throw EngineError.cannotWrite("生成结果未通过配对校验") }
 return pair
 } catch { try? FileManager.default.removeItem(at:directory);throw error }
 }
 static func temporaryDirectory()->URL { FileManager.default.temporaryDirectory.appendingPathComponent("LivePhotoAction-"+UUID().uuidString,isDirectory:true) }
}
