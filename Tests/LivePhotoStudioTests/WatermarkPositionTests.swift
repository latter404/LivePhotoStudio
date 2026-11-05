import XCTest
import AppKit
import AVFoundation
import ImageIO
import CoreImage
@testable import LivePhotoStudio

final class WatermarkPositionTests: XCTestCase {
    private let sizes = [CGSize(width:1280,height:720),CGSize(width:720,height:1280),
                         CGSize(width:7680,height:4320),CGSize(width:4320,height:7680)]

    func testPresetsKeepTheirExistingMarginsAndIgnoreFreeCoordinates() throws {
        for size in sizes {
            let margin=min(size.width,size.height)*0.03
            for position in 0...4 {
                var mark=Watermark();mark.text="Watermark 水印";mark.position=position
                let (before,rect)=try XCTUnwrap(mark.stamp(in:size))
                mark.freeX = -7;mark.freeY = .nan
                let (after,afterRect)=try XCTUnwrap(mark.stamp(in:size))
                XCTAssertEqual(rect,afterRect)
                XCTAssertEqual(before.dataProvider?.data as Data?,after.dataProvider?.data as Data?)
                let expectedX:CGFloat = position == 4 ? (size.width-rect.width)/2 : [1,3].contains(position) ? margin : size.width-margin-rect.width
                let expectedY:CGFloat = position == 4 ? (size.height-rect.height)/2 : [2,3].contains(position) ? size.height-margin-rect.height : margin
                XCTAssertEqual(rect.minX,expectedX,accuracy:0.000001)
                XCTAssertEqual(rect.minY,expectedY,accuracy:0.000001)
            }
        }
    }

    func testFreePlacementClampsAndKeepsWholeStampInsideEveryOrientation() throws {
        for size in sizes + [CGSize(width:2,height:2)] {
            for point in [CGPoint(x:0,y:0),CGPoint(x:1,y:1),CGPoint(x:-10,y:50),CGPoint(x:Double.nan,y:Double.infinity)] {
                var mark=Watermark();mark.text="Watermark 水印";mark.position=5
                mark.freeX=point.x;mark.freeY=point.y
                let (_,rect)=try XCTUnwrap(mark.stamp(in:size))
                XCTAssertTrue([rect.minX,rect.minY,rect.width,rect.height].allSatisfy(\.isFinite))
                XCTAssertGreaterThanOrEqual(rect.minX,-0.000001)
                XCTAssertGreaterThanOrEqual(rect.minY,-0.000001)
                XCTAssertLessThanOrEqual(rect.maxX,size.width+0.000001)
                XCTAssertLessThanOrEqual(rect.maxY,size.height+0.000001)
                if point.x.isNaN {
                    XCTAssertEqual(rect.midX,size.width/2,accuracy:0.000001)
                    XCTAssertEqual(rect.midY,size.height/2,accuracy:0.000001)
                }
            }
        }
    }

    func testPreviewAndExportShareTopLeftPlacementAcrossResolutions() throws {
        for size in sizes {
            var mark=Watermark();mark.text="Preview / Export";mark.position=5;mark.freeX=0.23;mark.freeY=0.71
            // Includes portrait/landscape and an inset cropped-output shape.
            for output in [size,CGSize(width:size.width*0.7,height:size.height*0.6)] {
                let preview=CGSize(width:output.width/12,height:output.height/12)
                for canvas in [preview,output] {
                    let (_,rect)=try XCTUnwrap(mark.stamp(in:canvas))
                    XCTAssertEqual(rect.minX/(canvas.width-rect.width),0.23,accuracy:0.000001)
                    XCTAssertEqual((canvas.height-rect.maxY)/(canvas.height-rect.height),0.71,accuracy:0.000001)
                }
            }
        }
    }

    func testDragUsesStartingAnchorAndStableCanvasTranslation() throws {
        var mark=Watermark();mark.text="Drag";mark.position=5;mark.freeX=0.3;mark.freeY=0.7
        let size=CGSize(width:360,height:640)
        let (_,rect)=try XCTUnwrap(mark.stamp(in:size))
        let available=CGSize(width:size.width-rect.width,height:size.height-rect.height)
        let initial=mark.freePosition(translatedBy:.zero,canvasSize:size,stampSize:rect.size)
        XCTAssertEqual(initial.x,0.3,accuracy:0.000001)
        XCTAssertEqual(initial.y,0.7,accuracy:0.000001)
        let moved=mark.freePosition(translatedBy:CGSize(width:available.width*0.25,height:-available.height*0.3),canvasSize:size,stampSize:rect.size)
        XCTAssertEqual(moved.x,0.55,accuracy:0.000001)
        XCTAssertEqual(moved.y,0.4,accuracy:0.000001)
        XCTAssertEqual(mark.freePosition(translatedBy:CGSize(width:-10000,height:10000),canvasSize:size,stampSize:rect.size),CGPoint(x:0,y:1))
        XCTAssertEqual(mark.freePosition(translatedBy:CGSize(width:50,height:50),canvasSize:size,stampSize:size),initial)
        XCTAssertEqual(mark.freePosition(translatedBy:CGSize(width:Double.nan,height:Double.infinity),canvasSize:size,stampSize:rect.size),initial)
    }

    func testFreePlacementIsAppliedToActualImagePixels() throws {
        let width=320,height=480
        let context=try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        let blank=try XCTUnwrap(context.makeImage())
        var mark=Watermark();mark.text="Position";mark.position=5;mark.freeX=0;mark.freeY=0
        let topLeft=mark.applying(to:blank)
        mark.freeX=1;mark.freeY=1
        let bottomRight=mark.applying(to:blank)
        mark.position=3
        let presetTopLeft=mark.applying(to:blank)
        mark.position=0
        let presetBottomRight=mark.applying(to:blank)
        func inkBounds(_ image:CGImage) throws -> CGRect {
            let data=try XCTUnwrap(image.dataProvider?.data) as Data
            var minX=width,minY=height,maxX = -1,maxY = -1
            for y in 0..<height { for x in 0..<width {
                if data[y*image.bytesPerRow+x*4+3]>0 {
                    minX=min(minX,x);minY=min(minY,y);maxX=max(maxX,x);maxY=max(maxY,y)
                }
            } }
            XCTAssertGreaterThanOrEqual(maxX,0)
            return CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)
        }
        let left=try inkBounds(topLeft),right=try inkBounds(bottomRight)
        XCTAssertLessThan(left.midX,CGFloat(width)/2)
        XCTAssertGreaterThan(right.midX,CGFloat(width)/2)
        // Compare actual pixels with the already-established preset directions,
        // without assuming a memory-row convention for CGImage bitmap storage.
        let knownTop=try inkBounds(presetTopLeft),knownBottom=try inkBounds(presetBottomRight)
        let margin=CGFloat(min(width,height))*0.03
        XCTAssertEqual(left.midY,knownTop.midY,accuracy:margin+1)
        XCTAssertEqual(right.midY,knownBottom.midY,accuracy:margin+1)
        XCTAssertGreaterThan(abs(left.midY-right.midY),CGFloat(height)/2)
    }

    func testCIStampHonorsTinyDestinationBoundsAndRasterAgreement() throws {
        let ci=CIContext(options:[.workingColorSpace:NSNull(),.outputColorSpace:NSNull()])
        for size in [CGSize(width:2,height:2),CGSize(width:8,height:3),CGSize(width:3,height:8)] {
            var mark=Watermark();mark.text="Fit";mark.position=5;mark.freeX=0.23;mark.freeY=0.71;mark.opacity=0.8
            let (raster,rect)=try XCTUnwrap(mark.stamp(in:size))
            XCTAssertTrue(rect.width<CGFloat(raster.width) || rect.height<CGFloat(raster.height))
            let label=try XCTUnwrap(mark.ciStamp(in:size))
            // CIImage.extent describes the affected pixel bounds. A fractional
            // translation expands this transformed raster to its enclosing pixel
            // rectangle; it does not round the requested watermark position.
            let expectedPixelBounds=rect.integral
            XCTAssertEqual(label.extent.minX,expectedPixelBounds.minX,accuracy:0.000001)
            XCTAssertEqual(label.extent.minY,expectedPixelBounds.minY,accuracy:0.000001)
            XCTAssertEqual(label.extent.width,expectedPixelBounds.width,accuracy:0.000001)
            XCTAssertEqual(label.extent.height,expectedPixelBounds.height,accuracy:0.000001)
            let canvas=CGRect(origin:.zero,size:size)
            XCTAssertTrue(canvas.contains(label.extent),"The fitted raster's affected pixels must remain inside the output")
            for corner in [CGPoint.zero,CGPoint(x:1,y:1)] {
                var edge=mark;edge.freeX=corner.x;edge.freeY=corner.y
                let edgeLabel=try XCTUnwrap(edge.ciStamp(in:size))
                XCTAssertTrue(canvas.contains(edgeLabel.extent),"Dragging to a corner must not put fitted CI pixels outside the output")
            }
            let clear=CIImage(color:CIColor(red:0,green:0,blue:0,alpha:0)).cropped(to:canvas)
            let ciResult=try XCTUnwrap(ci.createCGImage(label.composited(over:clear),from:canvas,format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB()))
            let context=try XCTUnwrap(CGContext(data:nil,width:Int(size.width),height:Int(size.height),bitsPerComponent:8,bytesPerRow:Int(size.width)*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            let cgResult=mark.applying(to:try XCTUnwrap(context.makeImage()))
            let a=rgba(ciResult),b=rgba(cgResult)
            // Different native interpolation kernels can differ on subpixel ink;
            // the enclosing pixel bounds above must be exact and raster
            // alpha/color stay close to the CGContext/GIF path.
            let meanError=zip(a,b).map { abs(Double($0)-Double($1)) }.reduce(0,+)/Double(a.count)
            XCTAssertLessThan(meanError,12)
        }
        // The ordinary preset path keeps the original CI operations exactly.
        for position in 0...4 {
            var mark=Watermark();mark.text="Preset";mark.position=position;mark.opacity=0.7
            let size=CGSize(width:320,height:240),canvas=CGRect(x:0,y:0,width:320,height:240)
            let (stamp,rect)=try XCTUnwrap(mark.stamp(in:size))
            let old=CIImage(cgImage:stamp).applyingFilter("CIColorMatrix",parameters:["inputAVector":CIVector(x:0,y:0,z:0,w:mark.opacity)]).transformed(by:CGAffineTransform(translationX:rect.minX,y:rect.minY))
            let revised=try XCTUnwrap(mark.ciStamp(in:size))
            let a=try XCTUnwrap(ci.createCGImage(old,from:canvas,format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB()))
            let b=try XCTUnwrap(ci.createCGImage(revised,from:canvas,format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB()))
            XCTAssertEqual(rgba(a),rgba(b))
        }
    }

    func testFreePositionSurvivesRotationCropResizeInGIFVideoAndLiveCover() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("FreeWatermark-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let source=root.appendingPathComponent("portrait-source.mov")
        try makeDarkOrientedVideo(source)
        // Source metadata rotates the 320x240 raster to portrait. An additional
        // half-turn, inset crop and downscale must all precede watermark placement.
        let crop=CropRegion(rect:CGRect(x:0.1,y:0.15,width:0.75,height:0.75))
        var mark=Watermark();mark.text="FREE";mark.position=5;mark.freeX=0.8;mark.freeY=0.2;mark.scale=0.1;mark.opacity=1
        let movie=root.appendingPathComponent("free.mov")
        try await Transcode.run(input:source,output:movie,start:0,end:1,maxEdge:160,fps:30,hevc:true,quarterTurns:2,watermark:mark,crop:crop)
        let gif=root.appendingPathComponent("free.gif")
        try await GIFExporter.run(input:source,output:gif,start:0,length:0.2,maxEdge:160,fps:30,quarterTurns:2,watermark:mark,crop:crop)
        var recipe=LivePreparation(input:source,start:0,length:1,cover:0.5,custom:true,edge:160,fps:30,hevc:true,mute:true,turns:2,watermark:mark)
        recipe.crop=crop
        let pair=try await recipe.generate(in:root.appendingPathComponent("live"))
        func still(_ url:URL) throws -> CGImage {
            let source=try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL,nil))
            return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        }
        func frame(_ url:URL) async throws -> CGImage {
            let generator=AVAssetImageGenerator(asset:AVURLAsset(url:url));generator.appliesPreferredTrackTransform=true
            return try await generator.image(at:CMTime(seconds:0.1,preferredTimescale:600)).image
        }
        let images=[try await frame(movie),try still(gif),try await frame(pair.movURL),try still(pair.imageURL)]
        var measured=[CGPoint]()
        for image in images {
            XCTAssertEqual(image.width,120);XCTAssertEqual(image.height,160)
            let actual=try brightCentroid(image)
            let context=try XCTUnwrap(CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            let blank=try XCTUnwrap(context.makeImage())
            // The old corner presets form an independent direction reference.
            // This avoids assuming a bitmap row order and catches flipped output.
            var corner=mark;corner.position=3
            let topLeft=try brightCentroid(corner.applying(to:blank))
            corner.position=0
            let bottomRight=try brightCentroid(corner.applying(to:blank))
            let normalized=CGPoint(x:(actual.x-topLeft.x)/(bottomRight.x-topLeft.x),y:(actual.y-topLeft.y)/(bottomRight.y-topLeft.y))
            XCTAssertEqual(normalized.x,0.8,accuracy:0.06,"Free watermark must remain toward the right after rotation/crop/resize")
            XCTAssertEqual(normalized.y,0.2,accuracy:0.06,"Free watermark must remain toward the top after rotation/crop/resize")
            measured.append(actual)
        }
        for point in measured.dropFirst() {
            XCTAssertEqual(point.x,measured[0].x,accuracy:2)
            XCTAssertEqual(point.y,measured[0].y,accuracy:2)
        }
    }

    private func brightCentroid(_ image:CGImage) throws -> CGPoint {
        let width=image.width,height=image.height
        var pixels=[UInt8](repeating:0,count:width*height*4)
        pixels.withUnsafeMutableBytes { buffer in
            let context=CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        }
        var count=0,xTotal=0,yTotal=0
        for y in 0..<height { for x in 0..<width {
            let i=(y*width+x)*4
            if pixels[i]>170 && pixels[i+1]>170 && pixels[i+2]>170 { count += 1;xTotal += x;yTotal += y }
        } }
        XCTAssertGreaterThan(count,10,"Expected visible white watermark pixels")
        return CGPoint(x:Double(xTotal)/Double(max(count,1)),y:Double(yTotal)/Double(max(count,1)))
    }

    private func rgba(_ image:CGImage) -> [UInt8] {
        var data=[UInt8](repeating:0,count:image.width*image.height*4)
        data.withUnsafeMutableBytes { buffer in
            let context=CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        return data
    }

    private func makeDarkOrientedVideo(_ url:URL) throws {
        let writer=try AVAssetWriter(outputURL:url,fileType:.mov)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:320,AVVideoHeightKey:240])
        input.transform=CGAffineTransform(a:0,b:1,c:-1,d:0,tx:240,ty:0)
        let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB])
        writer.add(input);XCTAssertTrue(writer.startWriting());writer.startSession(atSourceTime:.zero)
        for index in 0..<30 {
            var pixel:CVPixelBuffer?;CVPixelBufferCreate(nil,320,240,kCVPixelFormatType_32ARGB,nil,&pixel)
            let buffer=try XCTUnwrap(pixel);CVPixelBufferLockBaseAddress(buffer,[])
            let context=try XCTUnwrap(CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:320,height:240,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue))
            context.setFillColor(CGColor(gray:0.08,alpha:1));context.fill(CGRect(x:0,y:0,width:320,height:240))
            CVPixelBufferUnlockBaseAddress(buffer,[])
            while !input.isReadyForMoreMediaData { usleep(1000) }
            XCTAssertTrue(adaptor.append(buffer,withPresentationTime:CMTime(value:Int64(index),timescale:30)))
        }
        input.markAsFinished();let finished=DispatchSemaphore(value:0);writer.finishWriting { finished.signal() };finished.wait()
        XCTAssertEqual(writer.status,.completed)
    }
}
