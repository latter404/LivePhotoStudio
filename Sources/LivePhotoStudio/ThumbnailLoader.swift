import AppKit
import AVFoundation

/// Preview-only thumbnails. The export pipelines never use these reduced images.
/// A small per-source cache makes returning to a recently viewed range immediate.
@MainActor final class ThumbnailLoader {
    private struct Key: Hashable {
        let url: URL
        let modificationDate: Date?
        let fileSize: Int?
        let start: Double
        let span: Double
        let count: Int
    }
    private struct Entry { let images: [NSImage]; let cost: Int }
    private var source: URL?
    private var generation = 0
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private var cost = 0
    private let limit = 8 * 1024 * 1024

    func clear() {
        generation &+= 1
        source = nil; entries.removeAll(); order.removeAll(); cost = 0
    }

    func load(url: URL, start: Double, span: Double, count: Int = 20) async throws -> [NSImage] {
        try Task.checkCancellation()
        guard start.isFinite, start >= 0, span.isFinite, span > 0, count > 0, count <= 40 else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        let url = url.standardizedFileURL
        if source != url { clear(); source = url }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = Key(url: url, modificationDate: values?.contentModificationDate,
                      fileSize: values?.fileSize, start: start, span: span, count: count)
        if let entry = entries[key] {
            order.removeAll { $0 == key }; order.append(key)
            return entry.images
        }
        let requestGeneration = generation

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 100)
        // Preserve existing time-tolerance behavior; only thumbnail reuse and
        // cancellation change. A separate generator belongs to each request.
        let cancellation = GeneratorCancellation(generator)
        return try await withTaskCancellationHandler {
            var images: [NSImage] = []
            var bytes = 0
            for index in 0..<count {
                try Task.checkCancellation()
                let time = CMTime(seconds: start + span * Double(index) / Double(count), preferredTimescale: 600)
                let (image, _) = try await generator.image(at: time)
                images.append(NSImage(cgImage: image, size: .zero))
                bytes += image.bytesPerRow * image.height
            }
            try Task.checkCancellation()
            if source == url, generation == requestGeneration, bytes <= limit {
                if let previous = entries.removeValue(forKey: key) {
                    cost -= previous.cost; order.removeAll { $0 == key }
                }
                while (cost + bytes > limit || order.count >= 8), let oldest = order.first {
                    order.removeFirst()
                    if let removed = entries.removeValue(forKey: oldest) { cost -= removed.cost }
                }
                entries[key] = Entry(images: images, cost: bytes)
                order.append(key); cost += bytes
            }
            return images
        } onCancel: {
            // Swift Task cancellation alone doesn't stop an AVFoundation decode.
            cancellation.cancel()
        }
    }
}

private final class GeneratorCancellation: @unchecked Sendable {
    let generator: AVAssetImageGenerator
    init(_ generator: AVAssetImageGenerator) { self.generator = generator }
    func cancel() { generator.cancelAllCGImageGeneration() }
}
