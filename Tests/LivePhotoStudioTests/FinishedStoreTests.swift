import XCTest
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
@testable import LivePhotoStudio

final class FinishedStoreTests: XCTestCase {
    private var scratch: URL!
    private var root: URL { scratch.appendingPathComponent("Finished", isDirectory: true) }

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("FinishedStoreTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    func testIndependentCopiesSurviveSourceChangeAndRestart() async throws {
        let source = scratch.appendingPathComponent("clip.gif")
        try makeGIF(at: source, width: 800, height: 400)
        let bytes = try Data(contentsOf: source)
        let store = FinishedStore(root: root)
        let first = try await store.addGIF(source, title: "Same source", start: 0, duration: 3)
        let second = try await store.addGIF(source, title: "Same source", start: 7, duration: 3)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.directory(in: root), second.directory(in: root))
        try Data("The source has changed".utf8).write(to: source)
        let reopened = FinishedStore(root: root)
        let items = try await reopened.load()
        XCTAssertEqual(items.map(\.id), [second.id, first.id])
        XCTAssertEqual(items.map(\.start), [7, 0])
        for item in items {
            XCTAssertTrue(item.isAvailable)
            XCTAssertEqual(try Data(contentsOf: item.gifURL(in: root)), bytes)
            let thumbnail = try XCTUnwrap(CGImageSourceCreateWithURL(item.thumbnailURL(in: root) as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(thumbnail, 0, nil))
            XCTAssertEqual(image.width, 320)
            XCTAssertEqual(image.height, 160)
        }
    }

    func testLivePhotoPreservesPairBytesAndReopensAsSameAsset() async throws {
        let source = scratch.appendingPathComponent("source.mov")
        try makeVideo(at: source)
        let original = try await LivePhotoEngine.convert(input: source, outputDir: scratch,
                                                        baseName: "original", settings: ConversionSettings())
        let photoBytes = try Data(contentsOf: original.imageURL)
        let movieBytes = try Data(contentsOf: original.movURL)
        let store = FinishedStore(root: root)
        let saved = try await store.addLive(original, title: "Portrait", start: 1, duration: original.clipDuration)
        try FileManager.default.removeItem(at: original.imageURL)
        try FileManager.default.removeItem(at: original.movURL)
        let restored = try await FinishedStore(root: root).load()
        XCTAssertEqual(restored.count, 1)
        let item = try XCTUnwrap(restored.first)
        let pair = try XCTUnwrap(item.conversionResult(in: root))
        XCTAssertEqual(saved.id, item.id)
        XCTAssertEqual(pair.assetID, original.assetID)
        XCTAssertEqual(try Data(contentsOf: pair.imageURL), photoBytes)
        XCTAssertEqual(try Data(contentsOf: pair.movURL), movieBytes)
        let checks = await Verifier.verify(imageURL: pair.imageURL, movURL: pair.movURL)
        XCTAssertTrue(checks.allSatisfy { $0.status == .pass })
        let mismatched = ConversionResult(imageURL: pair.imageURL, movURL: pair.movURL, assetID: UUID().uuidString,
            baseName: pair.baseName, clipDuration: pair.clipDuration, videoWasCopied: pair.videoWasCopied)
        do {
            _ = try await store.addLive(mismatched, title: "Bad pair", start: 0, duration: pair.clipDuration)
            XCTFail("Pair metadata mismatch was accepted")
        } catch { }
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(entries.map(\.lastPathComponent), [saved.id.uuidString], "Failed staging must be removed")
    }

    func testInvalidInputDoesNotCommitOrRemoveExistingItems() async throws {
        let source = scratch.appendingPathComponent("good.gif")
        try makeGIF(at: source)
        let store = FinishedStore(root: root)
        let saved = try await store.addGIF(source, title: "Keep", start: 0, duration: 1)
        let invalid = scratch.appendingPathComponent("bad.gif")
        try Data("invalid image".utf8).write(to: invalid)
        do { _ = try await store.addGIF(invalid, title: "Bad", start: 0, duration: 1); XCTFail("Invalid GIF accepted") } catch { }
        do { _ = try await store.addGIF(source, title: "Bad timing", start: -.infinity, duration: 1); XCTFail("Invalid timing accepted") } catch { }
        let items = try await store.load()
        XCTAssertEqual(items.map(\.id), [saved.id])
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(entries.map(\.lastPathComponent), [saved.id.uuidString])
        XCTAssertTrue(FileManager.default.fileExists(atPath: invalid.path))
    }

    func testMissingMediaRemainsVisibleAndMalformedMetadataDoesNotBlockOthers() async throws {
        let source = scratch.appendingPathComponent("clip.gif")
        try makeGIF(at: source)
        let store = FinishedStore(root: root)
        let missing = try await store.addGIF(source, title: "Missing", start: 0, duration: 1)
        let intact = try await store.addGIF(source, title: "Intact", start: 1, duration: 1)
        try FileManager.default.removeItem(at: missing.gifURL(in: root))
        let malformed = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
        try Data("broken json".utf8).write(to: malformed.appendingPathComponent("item.json"))
        let items = try await store.load()
        XCTAssertEqual(items.count, 3)
        XCTAssertFalse(try XCTUnwrap(items.first { $0.id == missing.id }).isAvailable)
        XCTAssertTrue(try XCTUnwrap(items.first { $0.id == intact.id }).isAvailable)
        XCTAssertFalse(try XCTUnwrap(items.first { $0.id.uuidString == malformed.lastPathComponent }).isAvailable)
        let warningCount = await store.loadWarningCount
        XCTAssertEqual(warningCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: malformed.path))
    }

    func testForeignUUIDAndSymlinksCannotEscapeStore() async throws {
        let source = scratch.appendingPathComponent("clip.gif")
        try makeGIF(at: source)
        let store = FinishedStore(root: root)
        let saved = try await store.addGIF(source, title: "Keep", start: 0, duration: 1)
        // A JSON record whose id does not match its directory cannot redirect
        // later file access or delete a different valid item.
        let impostor = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: impostor, withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: impostor.appendingPathComponent("item.json"))
        let external = scratch.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let symbolicID = UUID()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(symbolicID.uuidString), withDestinationURL: external)
        let items = try await store.load()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.filter(\.isAvailable).map(\.id), [saved.id])
        let placeholder = try XCTUnwrap(items.first { $0.id.uuidString == impostor.lastPathComponent })
        XCTAssertFalse(placeholder.isAvailable)
        XCTAssertNil(placeholder.conversionResult(in: root))
        do { try await store.remove(ids: [symbolicID]); XCTFail("Symbolic directory removal accepted") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.directory(in: root).path))
    }

    func testRemovalIsRecoverableAndKeepsOtherItemsAndSources() async throws {
        let source = scratch.appendingPathComponent("clip.gif")
        try makeGIF(at: source)
        let trash = scratch.appendingPathComponent("TestTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let store = FinishedStore(root: root, trash: { directory in
            try FileManager.default.moveItem(at: directory, to: trash.appendingPathComponent(directory.lastPathComponent))
        })
        let first = try await store.addGIF(source, title: "First", start: 0, duration: 1)
        let second = try await store.addGIF(source, title: "Second", start: 1, duration: 1)
        try await store.remove(ids: [])
        let beforeRemoval = try await store.load()
        XCTAssertEqual(beforeRemoval.count, 2)
        try await store.remove(ids: [first.id])
        let remaining = try await store.load()
        XCTAssertEqual(remaining.map(\.id), [second.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent(first.id.uuidString).appendingPathComponent("Animation.gif").path))
        // Restore the directory, as Finder's Put Back would do.
        try FileManager.default.moveItem(at: trash.appendingPathComponent(first.id.uuidString), to: first.directory(in: root))
        let restored = try await store.load()
        XCTAssertEqual(restored.count, 2)
    }

    func testChangedMediaIsUnavailableEvenWhenFileSizeIsUnchanged() async throws {
        let source = scratch.appendingPathComponent("clip.gif")
        try makeGIF(at: source)
        let store = FinishedStore(root: root)
        let saved = try await store.addGIF(source, title: "Damaged", start: 0, duration: 1)
        var damaged = try Data(contentsOf: saved.gifURL(in: root))
        damaged[damaged.count / 2] ^= 0xff
        try damaged.write(to: saved.gifURL(in: root))
        let lightLoad = try await store.load()
        XCTAssertEqual(lightLoad.first?.isAvailable, true, "List loading only checks metadata and file sizes")
        let loaded = try await store.validate(ids: [saved.id])
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, saved.id)
        XCTAssertEqual(loaded.first?.isAvailable, false)
        XCTAssertEqual(try Data(contentsOf: saved.gifURL(in: root)), damaged, "Loading must never delete or rewrite damaged media")
    }

    func testMigrationCopiesVerifiesAndReusesIdenticalItemsWithoutTouchingOriginals() async throws {
        let source = scratch.appendingPathComponent("clip.gif")
        try makeGIF(at: source)
        let store = FinishedStore(root: root)
        let first = try await store.addGIF(source, title: "First", start: 0, duration: 1)
        let second = try await store.addGIF(source, title: "Second", start: 1, duration: 1)
        let target = scratch.appendingPathComponent("UserFolder/LivePhotoStudio/Finished", isDirectory: true)
        let migrated = try await store.migrate(to: target)
        XCTAssertEqual(Set(migrated.map(\.id)), [first.id, second.id])
        for item in [first, second] {
            XCTAssertEqual(try Data(contentsOf: item.gifURL(in: target)), try Data(contentsOf: item.gifURL(in: root)))
            XCTAssertTrue(FileManager.default.fileExists(atPath: item.directory(in: root).path))
        }
        let repeated = try await store.migrate(to: target)
        XCTAssertEqual(repeated.count, 2)
        let verified = try await FinishedStore(root: target).validate(ids: [first.id, second.id])
        XCTAssertTrue(verified.allSatisfy(\.isAvailable))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMigrationConflictPreservesBothRootsAndRollsBackNewCopies() async throws {
        let source = scratch.appendingPathComponent("clip.gif")
        try makeGIF(at: source)
        let store = FinishedStore(root: root)
        let first = try await store.addGIF(source, title: "First", start: 0, duration: 1)
        let second = try await store.addGIF(source, title: "Second", start: 1, duration: 1)
        let target = scratch.appendingPathComponent("Other/LivePhotoStudio/Finished", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: first.directory(in: root), to: first.directory(in: target))
        let conflicting = Data("Do not replace".utf8)
        try conflicting.write(to: first.gifURL(in: target))
        do { _ = try await store.migrate(to: target); XCTFail("Conflicting media was replaced") } catch { }
        XCTAssertEqual(try Data(contentsOf: first.gifURL(in: target)), conflicting)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.directory(in: target).path))
        let originals = try await store.validate(ids: [first.id, second.id])
        XCTAssertTrue(originals.allSatisfy(\.isAvailable))
        let targetChildren = try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)
        XCTAssertEqual(targetChildren.map(\.lastPathComponent), [first.id.uuidString])
    }

    func testMigrationRejectsNestedRootsAndSelectionValidationRejectsMissingIDs() async throws {
        let source = scratch.appendingPathComponent("clip.gif")
        try makeGIF(at: source)
        let store = FinishedStore(root: root)
        let item = try await store.addGIF(source, title: "Keep", start: 0, duration: 1)
        for target in [root.appendingPathComponent("nested"), scratch!] {
            do { _ = try await store.migrate(to: target); XCTFail("Nested migration was accepted") } catch { }
        }
        do { _ = try await store.validate(ids: [item.id, UUID()]); XCTFail("Missing selected item silently ignored") } catch { }
        let none = try await store.validate(ids: [])
        XCTAssertTrue(none.isEmpty)
        let sameRoot = try await store.migrate(to: root)
        XCTAssertEqual(sameRoot.map(\.id), [item.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("nested").path))
    }

    func testDirectoryAliasIsSameLibraryAndMigrationIsNonDestructiveNoOp() async throws {
        let source = scratch.appendingPathComponent("clip.gif")
        try makeGIF(at: source)
        let store = FinishedStore(root: root)
        let item = try await store.addGIF(source, title: "Keep", start: 0, duration: 1)
        let alias = scratch.appendingPathComponent("FinishedAlias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        XCTAssertTrue(FinishedStore.sameDirectory(root, alias))
        XCTAssertTrue(FinishedStore.sameDirectory(alias, root))
        XCTAssertTrue(FinishedStore.sameDirectory(root, root.appendingPathComponent("..", isDirectory: true).appendingPathComponent("Finished", isDirectory: true)))
        let before = try Data(contentsOf: item.gifURL(in: root))
        let after = try await store.migrate(to: alias)
        XCTAssertEqual(after.map(\.id), [item.id])
        XCTAssertEqual(try Data(contentsOf: item.gifURL(in: root)), before)
        let stillValid = try await store.validate(ids: [item.id])
        XCTAssertTrue(stillValid.allSatisfy(\.isAvailable))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).map(\.lastPathComponent), [item.id.uuidString])
    }

    func testDirectoryIdentityRecognizesCaseVariantsWhenTheVolumeSupportsThem() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let other = scratch.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        XCTAssertFalse(FinishedStore.sameDirectory(root, other))
        XCTAssertFalse(FinishedStore.sameDirectory(root, scratch.appendingPathComponent("Missing", isDirectory: true)))
        let variant = scratch.appendingPathComponent("FINISHED", isDirectory: true)
        if FileManager.default.fileExists(atPath: variant.path) {
            XCTAssertTrue(FinishedStore.sameDirectory(root, variant), "Directory identity must win over URL spelling")
        } else {
            XCTAssertFalse(FinishedStore.sameDirectory(root, variant), "Distinct case-sensitive paths must remain distinct")
        }
    }

    func testMigrationRejectsNestedAliasesWithSeveralMissingDestinationComponents() async throws {
        let source = scratch.appendingPathComponent("clip.gif")
        try makeGIF(at: source)
        let store = FinishedStore(root: root)
        let item = try await store.addGIF(source, title: "Keep", start: 0, duration: 1)
        let before = try Data(contentsOf: item.gifURL(in: root))
        let alias = scratch.appendingPathComponent("nested-root-alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        var roots = [root, alias]
        let uppercased = scratch.appendingPathComponent("FINISHED", isDirectory: true)
        if FileManager.default.fileExists(atPath: uppercased.path) {
            XCTAssertTrue(FinishedStore.sameDirectory(root, uppercased))
            roots.append(uppercased)
        }
        for spelling in roots {
            // This is inside an existing selected item's folder. If allowed,
            // later cleanup of that item would also trash the newly moved library.
            let destination = spelling.appendingPathComponent(item.id.uuidString + "/new/LivePhotoStudio/Finished", isDirectory: true)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            do { _ = try await store.migrate(to: destination); XCTFail("Nested alias was accepted") } catch { }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertEqual(try Data(contentsOf: item.gifURL(in: root)), before)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.directory(in: root).appendingPathComponent("new").path))
        let items = try await store.validate(ids: [item.id])
        XCTAssertTrue(items.allSatisfy(\.isAvailable))
    }

    func testMigrationRejectsAncestorAliasesWithoutPublishingIntoThem() async throws {
        let source = scratch.appendingPathComponent("clip.gif")
        try makeGIF(at: source)
        let ancestor = scratch.appendingPathComponent("ParentFolder", isDirectory: true)
        let nestedRoot = ancestor.appendingPathComponent("nested/LivePhotoStudio/Finished", isDirectory: true)
        let store = FinishedStore(root: nestedRoot)
        let item = try await store.addGIF(source, title: "Keep", start: 0, duration: 1)
        let before = try Data(contentsOf: item.gifURL(in: nestedRoot))
        let alias = scratch.appendingPathComponent("ancestor-alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: ancestor)
        var targets = [ancestor, alias]
        let uppercased = scratch.appendingPathComponent("PARENTFOLDER", isDirectory: true)
        if FileManager.default.fileExists(atPath: uppercased.path) {
            XCTAssertTrue(FinishedStore.sameDirectory(ancestor, uppercased))
            targets.append(uppercased)
        }
        for destination in targets {
            do { _ = try await store.migrate(to: destination); XCTFail("Ancestor alias was accepted") } catch { }
            XCTAssertFalse(FileManager.default.fileExists(atPath: item.directory(in: destination).path))
            XCTAssertEqual(try Data(contentsOf: item.gifURL(in: nestedRoot)), before)
        }
        let items = try await store.validate(ids: [item.id])
        XCTAssertTrue(items.allSatisfy(\.isAvailable))
    }

    private func makeGIF(at url: URL, width: Int = 64, height: Int = 48) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil))
        for color in [0.2, 0.8] {
            context.setFillColor(CGColor(gray: color, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let frame = try XCTUnwrap(context.makeImage())
            CGImageDestinationAddImage(destination, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 0.5]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func makeVideo(at url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 48])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<12 {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
            let frame = try XCTUnwrap(pixelBuffer)
            CVPixelBufferLockBaseAddress(frame, [])
            memset(CVPixelBufferGetBaseAddress(frame), Int32(30 + index * 4), CVPixelBufferGetDataSize(frame))
            CVPixelBufferUnlockBaseAddress(frame, [])
            while !input.isReadyForMoreMediaData { usleep(2000) }
            XCTAssertTrue(adaptor.append(frame, withPresentationTime: CMTime(value: Int64(index), timescale: 12)))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        XCTAssertEqual(writer.status, .completed)
    }
}
