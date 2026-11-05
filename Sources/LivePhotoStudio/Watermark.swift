import AppKit
import AVFoundation
import CoreImage

struct Watermark: Sendable {
 var text = ""
 var position = 0
 // For free placement, 0...1 spans the available space around the stamp.
 // Y follows the editor's top-to-bottom coordinates, not Core Graphics' Y axis.
 var freeX = 0.5
 var freeY = 0.5
 var scale = 0.04
 var opacity = 0.75
 var content: String { String(text.replacingOccurrences(of:"\n",with:" ").replacingOccurrences(of:"\r",with:" ").trimmingCharacters(in:.whitespacesAndNewlines).prefix(120)) }
 var active: Bool { !content.isEmpty }
 func stamp(in size: CGSize) -> (CGImage, CGRect)? {
 guard active, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, scale.isFinite else { return nil }
 let short = min(size.width,size.height), margin = short * 0.03
 let effectiveScale = min(0.12,max(0.015,scale))
 let text = content
 let key = WatermarkStampCache.Key(text:text,width:size.width,height:size.height,scale:effectiveScale)
 guard let image = WatermarkStampCache.shared.image(for:key,create:{
 var fontSize = short * effectiveScale
 func attributes(_ font:CGFloat) -> [NSAttributedString.Key:Any] {
 let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.7);shadow.shadowBlurRadius=max(1,font*0.08);shadow.shadowOffset=NSSize(width:0,height:-font*0.04)
 return [.font:NSFont.systemFont(ofSize:font,weight:.semibold),.foregroundColor:NSColor.white,.shadow:shadow]
 }
 var attrs=attributes(fontSize)
 var measured=(text as NSString).size(withAttributes:attrs)
 let available=max(1,size.width-margin*2)
 if measured.width+fontSize*0.3 > available { fontSize *= available/(measured.width+fontSize*0.3);attrs=attributes(fontSize);measured=(text as NSString).size(withAttributes:attrs) }
 let pad=max(2,fontSize*0.15),w=ceil(measured.width+pad*2),h=ceil(measured.height+pad*2)
 guard let context=CGContext(data:nil,width:Int(w),height:Int(h),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
 (text as NSString).draw(at:NSPoint(x:pad,y:pad),withAttributes:attrs)
 NSGraphicsContext.restoreGraphicsState()
 return context.makeImage()
 }) else { return nil }
 var w=CGFloat(image.width),h=CGFloat(image.height)
 if position == 5 {
 // Very small cropped outputs can be smaller than the raster's shadow padding.
 // Fit the whole stamp rather than clipping it when dragging to an edge.
 let fit=min(1,min(size.width/w,size.height/h))
 w *= fit;h *= fit
 return (image,CGRect(x:(size.width-w)*Self.freeCoordinate(freeX),y:(size.height-h)*(1-Self.freeCoordinate(freeY)),width:w,height:h))
 }
 let x:CGFloat = position == 4 ? (size.width-w)/2 : [1,3].contains(position) ? margin : size.width-margin-w
 let y:CGFloat = position == 4 ? (size.height-h)/2 : [2,3].contains(position) ? size.height-margin-h : margin
 return (image,CGRect(x:x,y:y,width:w,height:h))
 }
 static func freeCoordinate(_ value:Double) -> Double { value.isFinite ? min(1,max(0,value)) : 0.5 }
 /// Translation is measured in the preview's stable canvas coordinates. The
 /// normalized result can be rendered at any output resolution without flipping Y.
 func freePosition(translatedBy translation:CGSize,canvasSize:CGSize,stampSize:CGSize) -> CGPoint {
 let x=Self.freeCoordinate(freeX),y=Self.freeCoordinate(freeY)
 let width=canvasSize.width-stampSize.width,height=canvasSize.height-stampSize.height
 let dx=translation.width.isFinite && width.isFinite && width>0 ? translation.width/width : 0
 let dy=translation.height.isFinite && height.isFinite && height>0 ? translation.height/height : 0
 return CGPoint(x:Self.freeCoordinate(x+dx),y:Self.freeCoordinate(y+dy))
 }
 /// Core Image must honor the same destination rectangle as the preview and
 /// CGContext/GIF path, including a stamp fitted to a very small output.
 func ciStamp(in size:CGSize) -> CIImage? {
 guard let (stamp,rect)=stamp(in:size) else { return nil }
 var label=CIImage(cgImage:stamp).applyingFilter("CIColorMatrix",parameters:["inputAVector":CIVector(x:0,y:0,z:0,w:opacity)])
 let sx=rect.width/CGFloat(stamp.width),sy=rect.height/CGFloat(stamp.height)
 if sx != 1 || sy != 1 { label=label.transformed(by:CGAffineTransform(scaleX:sx,y:sy)) }
 return label.transformed(by:CGAffineTransform(translationX:rect.minX,y:rect.minY))
 }
 func applying(to image:CGImage) -> CGImage {
 let size=CGSize(width:image.width,height:image.height)
 guard let (label,rect)=stamp(in:size),let c=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
 c.draw(image,in:CGRect(origin:.zero,size:size));c.setAlpha(opacity);c.draw(label,in:rect)
 return c.makeImage() ?? image
 }
}

/// Rasterizing the same text/shadow for each GIF frame or preview update is
/// unnecessary. Only the small immutable stamp is cached, never video frames.
/// Position and opacity are applied later and intentionally aren't raster keys.
private final class WatermarkStampCache: @unchecked Sendable {
 struct Key: Hashable {
 let text:String
 let width:CGFloat
 let height:CGFloat
 let scale:Double
 }
 struct Entry { let image:CGImage;let cost:Int }
 static let shared=WatermarkStampCache()
 private let lock=NSLock()
 private var entries:[Key:Entry]=[:]
 private var order:[Key]=[]
 private var cost=0
 private let limit=8*1024*1024
 func image(for key:Key,create:()->CGImage?)->CGImage? {
 lock.lock()
 if let entry=entries[key] {
 order.removeAll{$0==key};order.append(key)
 lock.unlock();return entry.image
 }
 lock.unlock()
 guard let rendered=create() else { return nil }
 let (bytes,overflow)=rendered.bytesPerRow.multipliedReportingOverflow(by:rendered.height)
 guard !overflow,bytes<=limit else { return rendered }
 lock.lock();defer{lock.unlock()}
 if let existing=entries[key] { return existing.image }
 while (cost+bytes>limit || order.count>=24),let oldest=order.first {
 order.removeFirst();if let removed=entries.removeValue(forKey:oldest) { cost-=removed.cost }
 }
 entries[key]=Entry(image:rendered,cost:bytes);order.append(key);cost+=bytes
 return rendered
 }
}
