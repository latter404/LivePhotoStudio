import XCTest
import AppKit
@testable import LivePhotoStudio

final class RobustnessTests:XCTestCase {
 @MainActor func testRejectsInvalidVideoGeometryBeforeIntegerConversion() {
 for size in [CGSize(width:Double.nan,height:720),CGSize(width:1280,height:Double.infinity),CGSize(width:0,height:720),CGSize(width:-1,height:720),CGSize(width:Double.greatestFiniteMagnitude,height:720)] {
 XCTAssertFalse(Model.validDisplaySize(size))
 }
 for size in [CGSize(width:1280,height:720),CGSize(width:7680,height:4320),CGSize(width:4320,height:7680)] {
 XCTAssertTrue(Model.validDisplaySize(size))
 }
 }
 @MainActor func testCropStateFeedsEveryLivePreparationAndResets() {
 let model=Model();model.url=URL(fileURLWithPath:"/tmp/fixture.mov");model.sourceDisplaySize=CGSize(width:1920,height:1080)
 XCTAssertNil(model.activeCrop);XCTAssertFalse(model.currentPreparation()!.reencodes)
 model.setCropPreset(.portrait916)
 XCTAssertTrue(model.cropEditing);XCTAssertNotNil(model.currentPreparation()!.crop)
 XCTAssertTrue(model.currentPreparation()!.reencodes)
 let selected=model.cropRegion
 model.cropEditing=false
 XCTAssertEqual(model.cropRegion,selected)
 model.busy=true;model.setCropPreset(.off)
 XCTAssertEqual(model.cropRegion,selected)
 model.busy=false;model.setCropPreset(.off)
 XCTAssertNil(model.activeCrop);XCTAssertFalse(model.cropEditing)
 XCTAssertFalse(model.currentPreparation()!.reencodes)
 }
}
