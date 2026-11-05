import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Decode on the actor executor. ImageIO never receives a request to decode all
/// frames; the player requests only the frame that follows the displayed one.
actor FinishedGIFDecoder {
    struct Frame: @unchecked Sendable {
        let image: CGImage
        let delay: TimeInterval
        let index: Int
    }
    private let url: URL
    private let maxPixelSize: Int
    private var source: CGImageSource?

    init(url: URL, maxPixelSize: Int = 1000) {
        self.url = url
        self.maxPixelSize = min(1600, max(1, maxPixelSize))
    }

    func frameCount() throws -> Int {
        try Task.checkCancellation()
        return CGImageSourceGetCount(try openedSource())
    }

    func frame(at index: Int) throws -> Frame {
        try Task.checkCancellation()
        let source = try openedSource()
        guard index >= 0, index < CGImageSourceGetCount(source) else { throw unreadable() }
        let options: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, index, options),
              thumbnail.width > 0, thumbnail.height > 0,
              thumbnail.width <= maxPixelSize, thumbnail.height <= maxPixelSize else { throw unreadable() }
        try Task.checkCancellation()
        // Make a small independent raster on this executor. Rendering the
        // NSImageView cannot trigger deferred decoding of a source-sized frame.
        guard let context = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height,
            bitsPerComponent: 8, bytesPerRow: thumbnail.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw unreadable() }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard let image = context.makeImage() else { throw unreadable() }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let rawDelay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1
        let delay = rawDelay.isFinite && rawDelay > 0 ? min(rawDelay, 3600) : 0.1
        try Task.checkCancellation()
        return Frame(image: image, delay: delay, index: index)
    }

    func close() { source = nil }

    private func openedSource() throws -> CGImageSource {
        if let source { return source }
        guard url.isFileURL,
              let input = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(input) as String? == UTType.gif.identifier,
              CGImageSourceGetCount(input) > 0 else { throw unreadable() }
        source = input
        return input
    }
    private func unreadable() -> EngineError { .cannotRead("无法预览此处理结果") }
}

/// The editor owns the preview rectangle. Source pixels must not become a
/// minimum SwiftUI layout size when a new animation frame is assigned.
private final class FlexibleGIFImageView: NSImageView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
}

struct FinishedGIFPreview: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSImageView {
        let view = FlexibleGIFImageView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.animates = false
        view.setAccessibilityLabel(L("预览 GIF"))
        context.coordinator.start(url: url, in: view)
        return view
    }
    func updateNSView(_ view: NSImageView, context: Context) {
        context.coordinator.start(url: url, in: view)
    }
    static func dismantleNSView(_ view: NSImageView, coordinator: Coordinator) {
        coordinator.stop()
        view.image = nil
    }

    @MainActor final class Coordinator {
        private var task: Task<Void, Never>?
        private var generation = UUID()
        private var currentURL: URL?
        private weak var imageView: NSImageView?

        func start(url: URL, in view: NSImageView) {
            guard currentURL != url || task == nil || imageView !== view else { return }
            stop()
            currentURL = url
            imageView = view
            let token = generation
            let decoder = FinishedGIFDecoder(url: url)
            task = Task { [weak self] in
                do {
                    let count = try await decoder.frameCount()
                    var current = try await decoder.frame(at: 0)
                    while !Task.isCancelled {
                        guard let self, self.generation == token, let imageView = self.imageView else { break }
                        imageView.imageScaling = .scaleProportionallyUpOrDown
                        imageView.image = NSImage(cgImage: current.image,
                            size: NSSize(width: current.image.width, height: current.image.height))
                        if count == 1 { break }
                        // At most the displayed raster and this one next raster
                        // exist. Waiting and decoding overlap without piling up
                        // delayed timers or frame tasks when a large GIF is slow.
                        let nextIndex = (current.index + 1) % count
                        async let next = decoder.frame(at: nextIndex)
                        try await Task.sleep(nanoseconds: UInt64(current.delay * 1_000_000_000))
                        current = try await next
                    }
                } catch is CancellationError {
                    // Leaving the focused item is normal cancellation.
                } catch {
                    if let self, self.generation == token, let view = self.imageView {
                        view.imageScaling = .scaleNone
                        view.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: L("无法预览此处理结果"))
                        view.toolTip = L("无法预览此处理结果")
                    }
                }
                await decoder.close()
            }
        }

        func stop() {
            generation = UUID()
            task?.cancel()
            task = nil
            imageView?.image = nil
            imageView?.toolTip = nil
            imageView = nil
            currentURL = nil
        }
    }
}
