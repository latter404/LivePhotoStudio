import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import LivePhotoStudio

final class ImageWatermarkTests: XCTestCase {
    private func makePNG(at url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 40,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 80, height: 40))
        context.setFillColor(CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.8))
        context.fillEllipse(in: CGRect(x: 4, y: 4, width: 32, height: 32))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    func testImageWatermarkUsesSourceAspectAndPosition() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try makePNG(at: url)
        var mark = Watermark(); mark.imageMode = true; mark.imagePath = url.path; mark.position = 5; mark.freeX = 0.8; mark.freeY = 0.2; mark.scale = 0.06
        let (_, rect) = try XCTUnwrap(mark.stamp(in: CGSize(width: 1000, height: 600)))
        XCTAssertEqual(rect.width / rect.height, 2.0, accuracy: 0.04)
        XCTAssertGreaterThan(rect.minX, 500)
        XCTAssertEqual((600 - rect.maxY) / (600 - rect.height), 0.2, accuracy: 0.02)
        XCTAssertTrue(mark.imageAvailable)
    }

    func testImageWatermarkRendersPixelsAndMissingFileIsInactive() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try makePNG(at: url)
        var mark = Watermark(); mark.imageMode = true; mark.imagePath = url.path; mark.position = 0; mark.scale = 0.08; mark.opacity = 1
        let canvas = try XCTUnwrap(CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let output = mark.applying(to: canvas)
        XCTAssertNotEqual(output.dataProvider?.data as Data?, canvas.dataProvider?.data as Data?)
        mark.imagePath = url.deletingLastPathComponent().appendingPathComponent("gone.png").path
        XCTAssertFalse(mark.imageAvailable)
        XCTAssertFalse(mark.active)
        XCTAssertNil(mark.stamp(in: CGSize(width: 320, height: 240)))
    }
}
