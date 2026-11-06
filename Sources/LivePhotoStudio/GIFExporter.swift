import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import Foundation

struct GIFRecipe: Equatable, Sendable {
 let input:URL
 let start:Double
 let length:Double
 let maxEdge:Int
 let fps:Int
 var quarterTurns:Int = 0
 var watermark:Watermark? = nil
 var crop:CropRegion? = nil
 var speed:Double = 1
}

struct GIFSizeEstimate: Sendable {
 let bytes:Int64
 let sampledFrames:Int
 let totalFrames:Int
}

/// Serialize estimates, including cancellation, so rapid edits cannot stack decoders.
actor GIFSizeEstimator {
 static let shared=GIFSizeEstimator()
 private var previous:Task<GIFSizeEstimate,Error>?
 private var cachedRecipe:GIFRecipe?
 private var cachedStamp:Date?
 private var cachedEstimate:GIFSizeEstimate?
 func estimate(_ recipe:GIFRecipe) async throws -> GIFSizeEstimate {
 let stamp=try? recipe.input.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate
 if recipe == cachedRecipe,stamp == cachedStamp,let cachedEstimate { return cachedEstimate }
 let preceding=previous
 let task=Task.detached(priority:.utility) {
 _ = await preceding?.result
 try Task.checkCancellation()
 return try await GIFExporter.estimate(recipe)
 }
 previous=task
 let value=try await withTaskCancellationHandler { try await task.value } onCancel:{ task.cancel() }
 try Task.checkCancellation()
 cachedRecipe=recipe;cachedStamp=stamp;cachedEstimate=value
 return value
 }
}

enum GIFExporter {
 static func run(input:URL,output:URL,start:Double,length:Double,maxEdge:Int,fps:Int,quarterTurns:Int = 0,watermark:Watermark? = nil,crop:CropRegion? = nil,speed:Double = 1,progress:(@Sendable(Int,Int)->Void)?=nil) async throws {
 let recipe=GIFRecipe(input:input,start:start,length:length,maxEdge:maxEdge,fps:fps,quarterTurns:quarterTurns,watermark:watermark,crop:crop,speed:speed)
 let temp=output.deletingLastPathComponent().appendingPathComponent(".gif-\(UUID().uuidString).gif")
 defer { try? FileManager.default.removeItem(at:temp) }
 _ = try await encode(recipe,output:temp,sampleOnly:false,progress:progress)
 try Task.checkCancellation()
 if FileManager.default.fileExists(atPath:output.path) { _=try FileManager.default.replaceItemAt(output,withItemAt:temp) } else { try FileManager.default.moveItem(at:temp,to:output) }
 }

 static func estimate(_ recipe:GIFRecipe) async throws -> GIFSizeEstimate {
 let temp=FileManager.default.temporaryDirectory.appendingPathComponent("LivePhoto-GIFEstimate-\(UUID().uuidString).gif")
 defer { try? FileManager.default.removeItem(at:temp) }
 let (count,samples)=try await encode(recipe,output:temp,sampleOnly:true,progress:nil)
 let bytes=try temp.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
 // 32-byte stream header + trailer; the remaining independent frame blocks
 // use exactly the same palette/LZW encoder as the final output.
 let estimate=Double(max(0,bytes-33))/Double(samples)*Double(count)+33
 guard estimate.isFinite,estimate<Double(Int64.max) else { throw EngineError.cannotWrite("GIF 片段过长") }
 return GIFSizeEstimate(bytes:Int64(estimate.rounded()),sampledFrames:samples,totalFrames:count)
 }

 private static func encode(_ recipe:GIFRecipe,output:URL,sampleOnly:Bool,progress:(@Sendable(Int,Int)->Void)?) async throws -> (Int,Int) {
 try Task.checkCancellation()
 try MediaTiming.validate(speed:recipe.speed)
 if let crop=recipe.crop {
 let r=crop.rect
 guard r.minX.isFinite,r.minY.isFinite,r.width.isFinite,r.height.isFinite,r.width>0,r.height>0,r.minX>=0,r.minY>=0,r.maxX<=1.00000001,r.maxY<=1.00000001 else { throw EngineError.cannotWrite("裁切范围无效") }
 }
 let activeCrop=recipe.crop.flatMap { $0.isFull ? nil : $0 }
 let asset=try await Rotation.asset(url:recipe.input,turns:recipe.quarterTurns)
 let total=try await asset.load(.duration).seconds
 let track=try await asset.loadTracks(withMediaType:.video).first
 let sourceFPS=try await track?.load(.nominalFrameRate) ?? 30
 let fps=recipe.fps == 0 ? min(50,max(1,Double(sourceFPS)*recipe.speed)) : Double(recipe.fps)
 guard recipe.length.isFinite,recipe.start.isFinite,total.isFinite,recipe.length>0,recipe.start>=0,recipe.start<total,fps.isFinite,fps>=1,fps<=50,recipe.maxEdge>=0 else { throw EngineError.cannotWrite("GIF 时间范围或帧率无效") }
 let outputLength=min(recipe.length,total-recipe.start)/recipe.speed
 let ticks=max(2,round(outputLength*100))
 let frameCount=min(ceil(outputLength*fps-1e-8),floor(ticks/2))
 guard frameCount.isFinite,frameCount<Double(Int.max) else { throw EngineError.cannotWrite("GIF 片段过长") }
 let count=max(1,Int(frameCount))
 let indices=sampleOnly ? Array(Set([0,count/2,count-1])).sorted() : []
 let sampleCount=sampleOnly ? indices.count : count
 let stream=try StreamingGIFWriter(url:output)
 let generator=AVAssetImageGenerator(asset:asset)
 generator.appliesPreferredTrackTransform=true
 generator.maximumSize=activeCrop == nil ? CGSize(width:recipe.maxEdge,height:recipe.maxEdge) : .zero
 generator.requestedTimeToleranceBefore = .zero;generator.requestedTimeToleranceAfter = .zero
 for j in 0..<sampleCount {
 try Task.checkCancellation()
 let i=sampleOnly ? indices[j] : j
 let t=recipe.start+Double(i)/fps*recipe.speed
 let (image,_)=try await generator.image(at:CMTime(seconds:t,preferredTimescale:60000))
 try Task.checkCancellation()
 let a=round(Double(i)*ticks/Double(count)),b=round(Double(i+1)*ticks/Double(count))
 try autoreleasepool {
 let cropped:CGImage
 if let activeCrop {
 let region=activeCrop.pixelRect(in:CGSize(width:image.width,height:image.height))
 guard let cut=image.cropping(to:region) else { throw EngineError.cannotWrite("无法裁切 GIF 画面") }
 cropped=try resized(cut,maxEdge:recipe.maxEdge)
 } else { cropped=image }
 try stream.append(recipe.watermark?.applying(to:cropped) ?? cropped,delay:Int(b-a))
 }
 progress?(j+1,count)
 }
 try stream.finish()
 return (count,sampleCount)
 }
 private static func resized(_ image:CGImage,maxEdge:Int) throws -> CGImage {
 guard maxEdge>0,max(image.width,image.height)>maxEdge else { return image }
 let scale=Double(maxEdge)/Double(max(image.width,image.height))
 let width=max(1,Int((Double(image.width)*scale).rounded())),height=max(1,Int((Double(image.height)*scale).rounded()))
 guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw EngineError.cannotWrite("无法缩放裁切画面") }
 context.interpolationQuality = .high
 context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
 guard let result=context.makeImage() else { throw EngineError.cannotWrite("无法读取裁切画面") }
 return result
 }
}

/// ImageIO performs quantization/LZW for each frame. This writer preserves those
/// compressed bytes, adding a local palette and explicit animation timing.
final class StreamingGIFWriter {
 private let file:FileHandle
 private var size:(Int,Int)?
 private var closed=false
 init(url:URL) throws {
 guard FileManager.default.createFile(atPath:url.path,contents:nil) else { throw EngineError.cannotWrite("无法创建 GIF") }
 file=try FileHandle(forWritingTo:url)
 }
 deinit { if !closed { try? file.close() } }
 func append(_ image:CGImage,delay:Int) throws {
 guard image.width>0,image.height>0,image.width<=65535,image.height<=65535 else { throw EngineError.cannotWrite("GIF 尺寸超出格式限制") }
 if let size { guard size.0==image.width,size.1==image.height else { throw EngineError.cannotWrite("GIF 帧尺寸不一致") } }
 else {
 size=(image.width,image.height)
 var header=Data("GIF89a".utf8)
 header.append(contentsOf:word(image.width)+word(image.height)+[0x70,0,0]) // no global palette
 header.append(contentsOf:[0x21,0xFF,0x0B]);header.append(Data("NETSCAPE2.0".utf8));header.append(contentsOf:[3,1,0,0,0])
 try file.write(contentsOf:header)
 }
 let encoded=NSMutableData()
 guard let destination=CGImageDestinationCreateWithData(encoded,UTType.gif.identifier as CFString,1,nil) else { throw EngineError.cannotWrite("无法创建 GIF 帧") }
 CGImageDestinationAddImage(destination,image,nil)
 guard CGImageDestinationFinalize(destination) else { throw EngineError.cannotWrite("GIF 帧编码失败") }
 let frame=try Self.imageBlock(encoded as Data)
 let ticks=min(65535,max(2,delay))
 try file.write(contentsOf:Data([0x21,0xF9,4,0x08 | frame.transparentFlag]+word(ticks)+[frame.transparentIndex,0]))
 try file.write(contentsOf:frame.data)
 }
 func finish() throws {
 guard size != nil,!closed else { throw EngineError.cannotWrite("GIF 没有画面") }
 try file.write(contentsOf:Data([0x3B]));try file.close();closed=true
 }
 private func word(_ value:Int)->[UInt8] { [UInt8(value & 255),UInt8((value>>8)&255)] }
 static func imageBlock(_ data:Data) throws -> (data:Data,transparentFlag:UInt8,transparentIndex:UInt8) {
 let bytes=[UInt8](data)
 func invalid()->EngineError { .cannotWrite("系统返回了无效 GIF 帧") }
 guard bytes.count>=13,String(bytes:bytes[0..<3],encoding:.ascii)=="GIF" else { throw invalid() }
 var offset=13
 let globalBits=bytes[10]&7,globalCount=bytes[10]&0x80 == 0 ? 0 : 3*(1<<(Int(globalBits)+1))
 guard offset+globalCount<=bytes.count else { throw invalid() }
 let globalPalette=Array(bytes[offset..<offset+globalCount]);offset+=globalCount
 var transparentFlag:UInt8=0,transparentIndex:UInt8=0
 func skipBlocks(_ start:Int)throws->Int {
 var p=start
 while p<bytes.count { let n=Int(bytes[p]);p+=1;guard p+n<=bytes.count else { throw invalid() };p+=n;if n==0{return p} }
 throw invalid()
 }
 while offset<bytes.count {
 let marker=bytes[offset];offset+=1
 if marker==0x21 {
 guard offset<bytes.count else { throw invalid() };let label=bytes[offset];offset+=1
 if label==0xF9 {
 guard offset+6<=bytes.count,bytes[offset]==4 else { throw invalid() }
 transparentFlag=bytes[offset+1]&1;transparentIndex=bytes[offset+4]
 }
 offset=try skipBlocks(offset)
 } else if marker==0x2C {
 guard offset+9<=bytes.count else { throw invalid() }
 var descriptor=Array(bytes[offset..<offset+9]);offset+=9
 let localBits=descriptor[8]&7,hasLocal=descriptor[8]&0x80 != 0
 let localCount=hasLocal ? 3*(1<<(Int(localBits)+1)) : 0
 guard offset+localCount<bytes.count else { throw invalid() }
 let palette=hasLocal ? Array(bytes[offset..<offset+localCount]) : globalPalette
 guard !palette.isEmpty else { throw invalid() };offset+=localCount
 descriptor[8]=(descriptor[8]&0x60)|0x80|(hasLocal ? localBits : globalBits)
 let payloadStart=offset;offset+=1 // LZW minimum code size, then data sub-blocks
 let end=try skipBlocks(offset)
 var result=Data([0x2C]);result.append(contentsOf:descriptor);result.append(contentsOf:palette);result.append(contentsOf:bytes[payloadStart..<end])
 return (result,transparentFlag,transparentIndex)
 } else { throw invalid() }
 }
 throw invalid()
 }
}
