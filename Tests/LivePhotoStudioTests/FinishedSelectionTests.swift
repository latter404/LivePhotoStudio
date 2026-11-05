import XCTest
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
@testable import LivePhotoStudio

final class FinishedSelectionTests: XCTestCase {
    private var scratch: URL!
    private var root: URL { scratch.appendingPathComponent("Results", isDirectory: true) }

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("FinishedSelectionTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: scratch) }

    @MainActor func testHistoricalResultsAreUnselectedOnLaunchAndRelaunch() async throws {
        let source = try makeGIF()
        let store = FinishedStore(root: root)
        let first = try await store.addGIF(source, title: "First", start: 0, duration: 1)
        let second = try await store.addGIF(source, title: "Second", start: 1, duration: 1)
        let originalBytes = try Data(contentsOf: first.gifURL(in: root))
        let session = Model(); session.finishedStore = store
        await session.loadFinished()
        XCTAssertEqual(Set(session.finishedItems.map(\.id)), [first.id, second.id])
        XCTAssertTrue(session.finishedSelection.isEmpty)
        XCTAssertTrue(session.selectedFinished.isEmpty)
        XCTAssertEqual(session.sessionProcessedCount, 0)
        XCTAssertTrue(session.finishedLoaded)

        session.finishedSelection = [first.id]
        // A repeated view task in the same session must not clear a selection.
        await session.loadFinished()
        XCTAssertEqual(session.finishedSelection, [first.id])
        XCTAssertEqual(session.sessionProcessedCount, 0)
        session.finishedSelection = Set(session.finishedItems.map(\.id))
        XCTAssertEqual(session.sessionProcessedCount, 0, "Selecting historical items must not count as processing")

        let restarted = Model(); restarted.finishedStore = FinishedStore(root: root)
        await restarted.loadFinished()
        XCTAssertEqual(Set(restarted.finishedItems.map(\.id)), [first.id, second.id])
        XCTAssertTrue(restarted.finishedSelection.isEmpty)
        XCTAssertTrue(restarted.selectedFinished.isEmpty)
        XCTAssertEqual(restarted.sessionProcessedCount, 0)
        XCTAssertTrue(restarted.sessionProcessedIDs.isEmpty)
        XCTAssertEqual(session.finishedSelection, [first.id, second.id])
        XCTAssertEqual(try Data(contentsOf: first.gifURL(in: root)), originalBytes)
    }

    @MainActor func testRefreshPreservesValidManualSelectionWithoutSelectingOtherResults() async throws {
        let source = try makeGIF()
        let store = FinishedStore(root: root)
        let first = try await store.addGIF(source, title: "First", start: 0, duration: 1)
        let second = try await store.addGIF(source, title: "Second", start: 1, duration: 1)
        let model = Model(); model.finishedStore = store
        await model.loadFinished()
        model.finishedSelection = [first.id]

        let third = try await store.addGIF(source, title: "Arrived outside the editor", start: 2, duration: 1)
        await model.refreshFinished()
        XCTAssertEqual(Set(model.finishedItems.map(\.id)), [first.id, second.id, third.id])
        XCTAssertEqual(model.finishedSelection, [first.id])
        XCTAssertEqual(model.sessionProcessedCount, 0)

        model.finishedSelection = [first.id, second.id]
        // Simulate only a missing generated test file, never the real results library.
        try FileManager.default.removeItem(at: first.gifURL(in: root))
        await model.refreshFinished()
        XCTAssertEqual(model.finishedSelection, [second.id])
        XCTAssertEqual(model.selectedFinished.map(\.id), [second.id])
        XCTAssertFalse(try XCTUnwrap(model.finishedItems.first { $0.id == first.id }).isAvailable)
        XCTAssertFalse(model.finishedSelection.contains(third.id))
        XCTAssertEqual(model.sessionProcessedCount, 0)
    }

    @MainActor func testNewlyProcessedResultsAccumulateSelectionWithinTheSession() async throws {
        let gif = try makeGIF()
        let trash = scratch.appendingPathComponent("TestTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let store = FinishedStore(root: root, trash: { directory in
            try FileManager.default.moveItem(at: directory, to: trash.appendingPathComponent(directory.lastPathComponent))
        })
        let historical = try await store.addGIF(gif, title: "Historical", start: 0, duration: 1)
        let source = scratch.appendingPathComponent("synthetic.mov")
        try await makeVideo(at: source)
        let model = Model(); model.finishedStore = store
        await model.loadFinished()
        XCTAssertTrue(model.finishedSelection.isEmpty)
        XCTAssertEqual(model.sessionProcessedCount, 0)
        model.url = source; model.duration = 1; model.start = 0; model.length = 0.25; model.cover = 0.1
        model.gifMode = true
        model.processCurrent()
        try await waitForProcessing(model)
        XCTAssertEqual(model.finishedItems.count, 2, model.status)
        let firstNew = try XCTUnwrap(model.finishedItems.first { $0.id != historical.id })
        XCTAssertEqual(model.finishedSelection, [firstNew.id])
        XCTAssertEqual(model.sessionProcessedCount, 1)
        XCTAssertEqual(model.sessionProcessedIDs, [firstNew.id])

        model.start = 0.5
        model.processCurrent()
        try await waitForProcessing(model)
        XCTAssertEqual(model.finishedItems.count, 3, model.status)
        let newIDs = Set(model.finishedItems.filter { $0.id != historical.id }.map(\.id))
        XCTAssertEqual(newIDs.count, 2)
        XCTAssertEqual(model.finishedSelection, newIDs)
        XCTAssertEqual(model.sessionProcessedCount, 2)
        XCTAssertEqual(model.sessionProcessedIDs, newIDs)
        XCTAssertFalse(model.finishedSelection.contains(historical.id))
        await model.refreshFinished()
        XCTAssertEqual(model.finishedSelection, newIDs)
        XCTAssertEqual(model.sessionProcessedCount, 2)

        model.finishedSelection = [historical.id]
        XCTAssertEqual(model.sessionProcessedCount, 2, "The badge is independent of the current selection")
        model.finishedSelection = Set(model.finishedItems.map(\.id))
        XCTAssertEqual(model.sessionProcessedCount, 2)
        await model.finishAirDrop(newIDs, windowClosed: true, delete: false, message: "Closed",
            confirm: { XCTFail("Disabled cleanup must not ask for confirmation"); return false })
        XCTAssertEqual(model.sessionProcessedCount, 2, "Sending without cleanup keeps current-session results")

        let restarted = Model(); restarted.finishedStore = FinishedStore(root: root)
        await restarted.loadFinished()
        XCTAssertEqual(restarted.finishedItems.count, 3)
        XCTAssertEqual(restarted.sessionProcessedCount, 0)
        XCTAssertEqual(model.sessionProcessedCount, 2)

        await model.completedFinished([firstNew.id], delete: true, message: "Done")
        let remainingNew = try XCTUnwrap(newIDs.subtracting([firstNew.id]).first)
        XCTAssertEqual(model.sessionProcessedIDs, [remainingNew])
        XCTAssertEqual(model.sessionProcessedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent(firstNew.id.uuidString).path))
        XCTAssertTrue(model.finishedItems.contains { $0.id == historical.id })
        let missing = try XCTUnwrap(model.finishedItems.first { $0.id == remainingNew })
        try FileManager.default.removeItem(at: missing.gifURL(in: root))
        await model.refreshFinished()
        XCTAssertEqual(model.sessionProcessedCount, 0, "Unavailable results must not remain in the badge")
        XCTAssertTrue(model.finishedItems.contains { $0.id == historical.id && $0.isAvailable })
    }

    @MainActor func testSessionCountSurvivesMigrationWithoutCountingImportedHistory() async throws {
        let gif = try makeGIF()
        let store = FinishedStore(root: root)
        let history = try await store.addGIF(gif, title: "Existing", start: 0, duration: 1)
        let source = scratch.appendingPathComponent("migration-source.mov")
        try await makeVideo(at: source)
        let model = Model(); model.finishedStore = store
        await model.loadFinished()
        model.url = source; model.duration = 1; model.start = 0; model.length = 0.25; model.cover = 0.1
        model.gifMode = true; model.processCurrent()
        try await waitForProcessing(model)
        let processedID = try XCTUnwrap(model.sessionProcessedIDs.first)
        XCTAssertEqual(model.sessionProcessedCount, 1)

        let target = scratch.appendingPathComponent("Migrated", isDirectory: true)
        let destinationStore = FinishedStore(root: target)
        let otherHistory = try await destinationStore.addGIF(gif, title: "Already at destination", start: 1, duration: 1)
        _ = try await store.migrate(to: target)
        model.finishedStore = destinationStore
        await model.refreshFinished()
        XCTAssertEqual(Set(model.finishedItems.map(\.id)), [history.id, otherHistory.id, processedID])
        XCTAssertEqual(model.sessionProcessedIDs, [processedID])
        XCTAssertEqual(model.sessionProcessedCount, 1)
        XCTAssertEqual(model.finishedSelection, [processedID])
        let restarted = Model(); restarted.finishedStore = FinishedStore(root: target)
        await restarted.loadFinished()
        XCTAssertEqual(restarted.finishedItems.count, 3)
        XCTAssertEqual(restarted.sessionProcessedCount, 0)
    }

    @MainActor private func waitForProcessing(_ model: Model) async throws {
        let deadline = Date().addingTimeInterval(10)
        while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(model.busy, "Processing did not finish before the test deadline")
        guard !model.busy else { throw NSError(domain: "FinishedSelectionTests", code: 1) }
    }

    private func makeGIF() throws -> URL {
        let url = scratch.appendingPathComponent(UUID().uuidString + ".gif")
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8,
            bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        return url
    }

    private func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
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
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            XCTAssertTrue(adaptor.append(frame, withPresentationTime: CMTime(value: Int64(index), timescale: 12)))
        }
        input.markAsFinished(); await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
