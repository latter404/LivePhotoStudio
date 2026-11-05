import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LivePhotoStudio

final class FinishedGIFPreviewTests: XCTestCase {
    func testFramesKeepTheirTimingDifferAndDownsampleOnDemand() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GIFPreview-" + UUID().uuidString + ".gif")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 3, nil))
        let width = 1600, height = 900
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let delays = [0.04, 0.12, 0.25]
        let colors = [CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                      CGColor(red: 0, green: 1, blue: 0, alpha: 1),
                      CGColor(red: 0, green: 0, blue: 1, alpha: 1)]
        for index in 0..<3 {
            context.setFillColor(colors[index])
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let image = try XCTUnwrap(context.makeImage())
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFUnclampedDelayTime: delays[index],
                kCGImagePropertyGIFDelayTime: delays[index]
            ]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let decoder = FinishedGIFDecoder(url: url, maxPixelSize: 200)
        let count = try await decoder.frameCount()
        XCTAssertEqual(count, 3)
        var hashes = [Data]()
        // Request out of sequence too; the decoder must not assume all prior
        // frames are retained by the player.
        for index in [0, 2, 1] {
            let frame = try await decoder.frame(at: index)
            XCTAssertEqual(frame.index, index)
            XCTAssertEqual(frame.image.width, 200)
            XCTAssertLessThanOrEqual(frame.image.height, 113)
            XCTAssertEqual(frame.delay, delays[index], accuracy: 0.011)
            hashes.append(try XCTUnwrap(frame.image.dataProvider?.data) as Data)
        }
        XCTAssertNotEqual(hashes[0], hashes[1])
        XCTAssertNotEqual(hashes[1], hashes[2])
        XCTAssertNotEqual(hashes[0], hashes[2])
        do { _ = try await decoder.frame(at: 3); XCTFail("Out-of-range frame accepted") } catch { }
        await decoder.close()
    }

    func testInvalidGIFAndCancelledDecodeDoNotReturnFrames() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GIFPreviewInvalid-" + UUID().uuidString + ".gif")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Not a GIF".utf8).write(to: url)
        let decoder = FinishedGIFDecoder(url: url)
        do { _ = try await decoder.frameCount(); XCTFail("Invalid GIF accepted") } catch { }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await decoder.frame(at: 0)
        }
        do { _ = try await task.value; XCTFail("Cancelled decode returned an image") }
        catch is CancellationError { }
        catch { XCTFail("Expected cancellation before opening invalid input") }
        await decoder.close()
    }
}
