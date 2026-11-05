import XCTest
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
@testable import LivePhotoStudio

final class FinishedExportTests: XCTestCase {
    private var scratch: URL!
    private var root: URL { scratch.appendingPathComponent("Finished", isDirectory: true) }
    private var destination: URL { scratch.appendingPathComponent("Export", isDirectory: true) }

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("FinishedExportTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    func testMixedBatchIsFlatByteIdenticalAndRepeatedExportDoesNotOverwrite() async throws {
        let gif = try makeGIFItem(title: "同一个片段")
        let live = try await makeLiveItem(title: "同一个片段")
        let originals = [gif.gifURL(in: root), live.imageURL(in: root), live.movURL(in: root)]
        let bytes = try originals.map { try Data(contentsOf: $0) }
        let first = try await FinishedExport.publish([gif, live], from: root, to: destination)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(Set(first.map { $0.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL }),
                       [destination.resolvingSymlinksInPath().standardizedFileURL])
        XCTAssertEqual(try first.map { try Data(contentsOf: $0) }, bytes)
        XCTAssertEqual(first[1].deletingPathExtension().lastPathComponent, first[2].deletingPathExtension().lastPathComponent)
        let checks = await Verifier.verify(imageURL: first[1], movURL: first[2])
        XCTAssertTrue(checks.allSatisfy { $0.status == .pass })
        let second = try await FinishedExport.publish([gif, live], from: root, to: destination)
        XCTAssertTrue(Set(first).isDisjoint(with: Set(second)))
        XCTAssertEqual(try second.map { try Data(contentsOf: $0) }, bytes)
        XCTAssertEqual(try first.map { try Data(contentsOf: $0) }, bytes)
        XCTAssertEqual(try originals.map { try Data(contentsOf: $0) }, bytes)
        XCTAssertEqual(try contents().count, 6)
    }

    func testUnsafeAndLongTitlesStayWithinDestination() async throws {
        let item = try makeGIFItem(title: "../../路径/\u{0000}:\\" + String(repeating: "👩🏽‍💻", count: 100))
        let files = try await FinishedExport.publish([item], from: root, to: destination)
        let output = try XCTUnwrap(files.first)
        XCTAssertEqual(output.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL,
                       destination.resolvingSymlinksInPath().standardizedFileURL)
        XCTAssertLessThan(output.lastPathComponent.utf8.count, 255)
        XCTAssertFalse(output.lastPathComponent.contains("/"))
        XCTAssertFalse(output.lastPathComponent.contains(":"))
        XCTAssertTrue(output.lastPathComponent.contains(String(item.id.uuidString.prefix(8))))
    }

    func testEmptyDuplicateAndUnavailableSelectionsDoNotTouchFiles() async throws {
        let item = try makeGIFItem(title: "Keep")
        let keep = destination.appendingPathComponent("existing.txt")
        let original = Data("Unrelated user file".utf8)
        try original.write(to: keep)
        var missing = item; missing.isAvailable = false
        for items in [[], [item, item], [missing]] {
            do { _ = try await FinishedExport.publish(items, from: root, to: destination); XCTFail("Invalid selection accepted") }
            catch { }
        }
        XCTAssertEqual(try contents().map { $0.resolvingSymlinksInPath() }, [keep.resolvingSymlinksInPath()])
        XCTAssertEqual(try Data(contentsOf: keep), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.gifURL(in: root).path))
    }

    func testInvalidLaterItemLeavesNoPartialBatchOrStagingFolder() async throws {
        let first = try makeGIFItem(title: "First")
        let invalid = try makeGIFItem(title: "Broken")
        let firstBytes = try Data(contentsOf: first.gifURL(in: root))
        try Data("not a GIF".utf8).write(to: invalid.gifURL(in: root))
        do { _ = try await FinishedExport.publish([first, invalid], from: root, to: destination); XCTFail("Corrupt GIF accepted") }
        catch { }
        XCTAssertTrue(try contents().isEmpty)
        XCTAssertEqual(try Data(contentsOf: first.gifURL(in: root)), firstBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: invalid.gifURL(in: root).path))
    }

    func testCommitCollisionRollsBackEarlierFilesAndPreservesConflictingFile() throws {
        let first = scratch.appendingPathComponent("staged-first")
        let second = scratch.appendingPathComponent("staged-second")
        let firstTarget = destination.appendingPathComponent("first.gif")
        let secondTarget = destination.appendingPathComponent("second.gif")
        let unrelated = Data("Existing file must remain".utf8)
        try Data("new first".utf8).write(to: first)
        try Data("new second".utf8).write(to: second)
        try unrelated.write(to: secondTarget)
        XCTAssertThrowsError(try FinishedExport.commit([(first, firstTarget), (second, secondTarget)]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstTarget.path))
        XCTAssertEqual(try Data(contentsOf: secondTarget), unrelated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(try contents().map { $0.resolvingSymlinksInPath() }, [secondTarget.resolvingSymlinksInPath()])
    }

    func testCancellationLeavesCollectionAndDestinationIntact() async throws {
        let item = try makeGIFItem(title: "Cancelled")
        let root = root, destination = destination
        let (stream, gate) = AsyncStream<Void>.makeStream()
        let operation = Task {
            for await _ in stream { break }
            return try await FinishedExport.publish([item], from: root, to: destination)
        }
        operation.cancel(); gate.finish()
        do { _ = try await operation.value; XCTFail("Cancelled export succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(try contents().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.gifURL(in: root).path))
    }

    func testRejectsCollectionAndDescendantsIncludingSymlinkAliasesWithoutChanges() async throws {
        let item = try makeGIFItem(title: "Keep original")
        let nested = item.directory(in: root).appendingPathComponent("Nested/Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let existing = nested.appendingPathComponent("existing.txt")
        let existingBytes = Data("Already present; do not modify".utf8)
        try existingBytes.write(to: existing)
        let originalBytes = try Data(contentsOf: item.gifURL(in: root))
        let alias = scratch.appendingPathComponent("CollectionAlias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        let before = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
        let destinations = [root, item.directory(in: root), nested,
                            alias, item.directory(in: alias).appendingPathComponent("Nested/Exports", isDirectory: true)]
        for target in destinations {
            do {
                _ = try await FinishedExport.publish([item], from: root, to: target)
                XCTFail("An export destination inside the collection was accepted")
            } catch {
                guard case EngineError.cannotWrite(let message) = error else {
                    XCTFail("Expected the collection-location error, got \(error)"); continue
                }
                XCTAssertEqual(message, "导出位置不能在处理结果保存文件夹内，请选择其他文件夹。")
            }
        }
        // Canonicalize the source root too: a root alias must not hide that the
        // actual destination belongs to the collection.
        do {
            _ = try await FinishedExport.publish([item], from: alias, to: nested)
            XCTFail("A symbolic source-root alias bypassed the location check")
        } catch { }
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted(), before)
        XCTAssertEqual(try Data(contentsOf: item.gifURL(in: root)), originalBytes)
        XCTAssertEqual(try Data(contentsOf: existing), existingBytes)
        XCTAssertTrue(try contents().isEmpty)
    }

    func testSimilarlyNamedSiblingFolderIsAllowed() async throws {
        let item = try makeGIFItem(title: "Sibling")
        let sibling = root.deletingLastPathComponent().appendingPathComponent("Finished-Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let files = try await FinishedExport.publish([item], from: root, to: sibling)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].deletingLastPathComponent().resolvingSymlinksInPath(), sibling.resolvingSymlinksInPath())
        XCTAssertEqual(try Data(contentsOf: files[0]), try Data(contentsOf: item.gifURL(in: root)))
    }

    func testDifferentlyCasedCollectionAliasIsRejectedWhenSupported() async throws {
        let item = try makeGIFItem(title: "Case alias")
        let alias = root.deletingLastPathComponent().appendingPathComponent("fINISHED", isDirectory: true)
        try XCTSkipIf(!FinishedStore.sameDirectory(root, alias), "Test volume uses case-sensitive paths")
        let existing = item.directory(in: root).appendingPathComponent("keep.txt")
        let bytes = Data("Preserve existing file".utf8)
        try bytes.write(to: existing)
        let before = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
        for target in [alias, item.directory(in: alias)] {
            do {
                _ = try await FinishedExport.publish([item], from: root, to: target)
                XCTFail("A differently cased path bypassed the collection boundary")
            } catch {
                guard case EngineError.cannotWrite(let message) = error else {
                    XCTFail("Expected the collection-location error, got \(error)"); continue
                }
                XCTAssertEqual(message, "导出位置不能在处理结果保存文件夹内，请选择其他文件夹。")
            }
        }
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted(), before)
        XCTAssertEqual(try Data(contentsOf: existing), bytes)
    }

    private func contents() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func makeGIFItem(title: String) throws -> FinishedItem {
        let item = FinishedItem(id: UUID(), title: title, kind: .gif, createdAt: Date(), start: 0,
                                duration: 1, byteCount: 1, assetID: nil)
        try FileManager.default.createDirectory(at: item.directory(in: root), withIntermediateDirectories: true)
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 12, bitsPerComponent: 8,
            bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(item.gifURL(in: root) as CFURL, UTType.gif.identifier as CFString, 2, nil))
        for color in [0.2, 0.8] {
            context.setFillColor(CGColor(gray: color, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
            CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()),
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 0.5]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        return item
    }

    private func makeLiveItem(title: String) async throws -> FinishedItem {
        let source = scratch.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 48])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        writer.add(input)
        XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for index in 0..<12 {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32ARGB, nil, &buffer)
            let frame = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(frame, [])
            memset(CVPixelBufferGetBaseAddress(frame), Int32(30 + index * 4), CVPixelBufferGetDataSize(frame))
            CVPixelBufferUnlockBaseAddress(frame, [])
            while !input.isReadyForMoreMediaData { usleep(2000) }
            XCTAssertTrue(adaptor.append(frame, withPresentationTime: CMTime(value: Int64(index), timescale: 12)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        let pair = try await LivePhotoEngine.convert(input: source, outputDir: scratch.appendingPathComponent("pair"),
                                                     baseName: "original", settings: ConversionSettings())
        return try await FinishedStore(root: root).addLive(pair, title: title, start: 0, duration: pair.clipDuration)
    }
}
