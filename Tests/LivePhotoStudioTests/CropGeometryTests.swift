import XCTest
@testable import LivePhotoStudio

final class CropGeometryTests: XCTestCase {
    private func assertInside(_ r: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue([r.minX,r.minY,r.width,r.height].allSatisfy { $0.isFinite }, file: file, line: line)
        XCTAssertGreaterThanOrEqual(r.minX, -0.000001, file: file, line: line)
        XCTAssertGreaterThanOrEqual(r.minY, -0.000001, file: file, line: line)
        XCTAssertLessThanOrEqual(r.maxX, 1.000001, file: file, line: line)
        XCTAssertLessThanOrEqual(r.maxY, 1.000001, file: file, line: line)
        XCTAssertGreaterThan(r.width, 0, file: file, line: line)
        XCTAssertGreaterThan(r.height, 0, file: file, line: line)
    }
    func testInvalidRegionsAndPixelBoundsAreSafe() {
        for r in [CGRect(x: Double.nan,y:0,width:1,height:1),CGRect(x:0,y:0,width:0,height:1),CGRect(x:2,y:2,width:1,height:1)] { XCTAssertTrue(CropRegion(rect:r).isFull) }
        let r=CropRegion(rect:CGRect(x:0.123,y:0.234,width:0.321,height:0.456))
        let pixels=r.pixelRect(in:CGSize(width:3840,height:2160))
        XCTAssertEqual(pixels.minX,(0.123*3840).rounded())
        XCTAssertEqual(pixels.minY,(0.234*2160).rounded())
        XCTAssertEqual(pixels.width,(0.321*3840).rounded())
        XCTAssertEqual(pixels.height,(0.456*2160).rounded())
        XCTAssertEqual(CropRegion.full.pixelRect(in:CGSize(width:4320,height:7680)),CGRect(x:0,y:0,width:4320,height:7680))
        XCTAssertEqual(r.pixelRect(in:CGSize(width:Double.infinity,height:2160)),.zero)
        assertInside(CropRegion(rect:CGRect(x:-0.2,y:0.8,width:0.5,height:0.7)).rect)
    }
    func testEveryPresetFitsLandscapePortraitAnd8K() {
        for size in [CGSize(width:1920,height:1080),CGSize(width:1080,height:1920),CGSize(width:7680,height:4320),CGSize(width:4320,height:7680)] {
            for preset in CropPreset.allCases {
                let crop=preset.fittedRegion(in:size)
                assertInside(crop.rect)
                if let aspect=preset.aspect(in:size) {
                    XCTAssertEqual(crop.rect.width*size.width/(crop.rect.height*size.height),aspect,accuracy:0.000001,"\(preset) \(size)")
                }
            }
        }
        XCTAssertEqual(CropPreset.landscape43.aspect(in:CGSize(width:100,height:100))!,4.0/3.0,accuracy:0.000001)
        XCTAssertEqual(CropPreset.portrait916.aspect(in:CGSize(width:100,height:100))!,9.0/16.0,accuracy:0.000001)
    }
    func testTranslationNeverChangesRoundedCropDimensions() {
        for size in [CGSize(width:3840,height:2160),CGSize(width:2160,height:3840),CGSize(width:7680,height:4320)] {
            let square=CropPreset.square.fittedRegion(in:size)
            let expected=square.pixelRect(in:size)
            XCTAssertEqual(expected.width,expected.height)
            for step in -100...100 {
                let moved=square.moved(by:CGSize(width:Double(step)/100,height:Double(step)/100)).pixelRect(in:size)
                XCTAssertEqual(moved.size,expected.size)
                XCTAssertGreaterThanOrEqual(moved.minX,0);XCTAssertGreaterThanOrEqual(moved.minY,0)
                XCTAssertLessThanOrEqual(moved.maxX,size.width);XCTAssertLessThanOrEqual(moved.maxY,size.height)
            }
        }
        // Half-pixel size rounding must also be independent from floating-point origin drift.
        let halfPixel=CropRegion(rect:CGRect(x:0.1,y:0.2,width:0.35,height:0.35))
        for step in 0...100 {
            XCTAssertEqual(halfPixel.moved(by:CGSize(width:Double(step)/200,height:Double(step)/200)).pixelRect(in:CGSize(width:10,height:10)).size,CGSize(width:4,height:4))
        }
    }
    func testMovingKeepsSizeAndClampsAllEdges() {
        let crop=CropRegion(rect:CGRect(x:0.2,y:0.25,width:0.4,height:0.5))
        for x in [-5.0,-0.1,0,0.1,5] { for y in [-5.0,-0.1,0,0.1,5] {
            let moved=crop.moved(by:CGSize(width:x,height:y))
            assertInside(moved.rect)
            XCTAssertEqual(moved.rect.width,crop.rect.width,accuracy:0.000001)
            XCTAssertEqual(moved.rect.height,crop.rect.height,accuracy:0.000001)
        } }
    }
    func testFreeResizingAllEightHandlesKeepsOppositeEdgesAndBounds() {
        let crop=CropRegion(rect:CGRect(x:0.25,y:0.2,width:0.5,height:0.6))
        for handle in CropHandle.allCases { for dx in [-5.0,-0.1,0,0.1,5] { for dy in [-5.0,-0.1,0,0.1,5] {
            let r=crop.resized(handle:handle,translation:CGSize(width:dx,height:dy),sourceSize:CGSize(width:1920,height:1080),aspect:nil).rect
            assertInside(r)
            if handle.horizontal<0 { XCTAssertEqual(r.maxX,crop.rect.maxX,accuracy:0.000001) }
            if handle.horizontal>0 { XCTAssertEqual(r.minX,crop.rect.minX,accuracy:0.000001) }
            if handle.vertical<0 { XCTAssertEqual(r.maxY,crop.rect.maxY,accuracy:0.000001) }
            if handle.vertical>0 { XCTAssertEqual(r.minY,crop.rect.minY,accuracy:0.000001) }
        } } }
    }
    func testFixedRatioResizingAllHandlesWithExtremeDrags() {
        for size in [CGSize(width:1920,height:1080),CGSize(width:1080,height:1920),CGSize(width:4320,height:7680)] {
            for preset in [CropPreset.square,.landscape169,.portrait916,.landscape43,.portrait34] {
                let fitted=preset.fittedRegion(in:size),r=fitted.rect
                let crop=CropRegion(rect:CGRect(x:r.midX-r.width*0.3,y:r.midY-r.height*0.3,width:r.width*0.6,height:r.height*0.6))
                let aspect=preset.aspect(in:size)!
                for handle in CropHandle.allCases { for dx in [-5.0,-0.08,0,0.08,5] { for dy in [-5.0,-0.08,0,0.08,5] {
                    let result=crop.resized(handle:handle,translation:CGSize(width:dx,height:dy),sourceSize:size,aspect:aspect).rect
                    assertInside(result)
                    XCTAssertEqual(result.width*size.width/(result.height*size.height),aspect,accuracy:0.000001,"\(size) \(preset) \(handle) \(dx),\(dy)")
                } } }
            }
        }
    }
    func testRotationPreservesSelectedContentAndRoundTrips() {
        let crop=CropRegion(rect:CGRect(x:0.1,y:0.2,width:0.3,height:0.4))
        let rotated=crop.rotated(clockwise:1).rect
        XCTAssertEqual(rotated.minX,0.4,accuracy:0.000001)
        XCTAssertEqual(rotated.minY,0.1,accuracy:0.000001)
        XCTAssertEqual(rotated.width,0.4,accuracy:0.000001)
        XCTAssertEqual(rotated.height,0.3,accuracy:0.000001)
        for turn in -8...8 {
            let result=crop.rotated(clockwise:turn).rotated(clockwise:-turn).rect
            XCTAssertEqual(result.minX,crop.rect.minX,accuracy:0.000001)
            XCTAssertEqual(result.minY,crop.rect.minY,accuracy:0.000001)
            XCTAssertEqual(result.width,crop.rect.width,accuracy:0.000001)
            XCTAssertEqual(result.height,crop.rect.height,accuracy:0.000001)
        }
    }
}
