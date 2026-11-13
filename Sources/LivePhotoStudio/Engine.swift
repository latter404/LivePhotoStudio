// Portions based on Revive by Edward Shen, licensed under MIT.
// Source: https://github.com/Ed3110/Revive/tree/feb46245b5c6a1d3982909916832a02d71a33828
// See Licenses/Revive-MIT.txt and Licenses/THIRD_PARTY_NOTICES.txt.
import AVFoundation
import AudioToolbox
import CoreVideo
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

enum EngineError: LocalizedError {
    case noVideoTrack
    case cannotRead(String)
    case cannotWrite(String)
    case stillExtractionFailed(String)
    case cancelled

    var errorDescription: String? {
        let L = Localizer.shared
        func join(_ key: String, _ detail: String) -> String {
            detail.isEmpty ? L.t(key) : "\(L.t(key)): \(detail)"
        }
        switch self {
        case .noVideoTrack: return L.t("err_no_video")
        case .cannotRead(let d): return join("err_read", d)
        case .cannotWrite(let d): return join("err_write", d)
        case .stillExtractionFailed(let d): return join("err_still", d)
        case .cancelled: return L.t("err_cancelled")
        }
    }
}

struct ConversionSettings {
    var trimStart: Double = 0
    var trimEnd: Double = 0          // 0 = until end (filled in from duration)
    var frameTime: Double? = nil     // relative to trimStart; nil = clip midpoint
    var useHEIC: Bool = false
    var exactTrim: Bool = false      // re-encode once for frame-accurate cuts
    var dropAudio: Bool = false      // mute: omit the audio track entirely
}

struct ConversionResult {
    let imageURL: URL
    let movURL: URL
    let assetID: String
    let baseName: String
    let clipDuration: Double
    let videoWasCopied: Bool
}

/// Converts a video into a Live Photo pair. The video bitstream is copied
/// byte-for-byte (AVAssetReader/Writer passthrough) unless `exactTrim` is on
/// or the container needs conversion AVFoundation can't passthrough.
enum LivePhotoEngine {
    static let keyContentID = "com.apple.quicktime.content.identifier"
    static let keyStillImageTime = "com.apple.quicktime.still-image-time"
    static let keySpaceMDTA = "mdta"
    static let makerAppleAssetIDKey = "17"

    // MARK: metadata items

    private static func item(_ key: String, _ value: NSObject & NSCopying, _ dataType: String) -> AVMutableMetadataItem {
        let m = AVMutableMetadataItem()
        m.key = key as NSString
        m.keySpace = AVMetadataKeySpace(rawValue: keySpaceMDTA)
        m.value = value
        m.dataType = dataType
        return m
    }

    private static func topLevelMetadata(assetID: String) -> [AVMetadataItem] {
        [
            item(keyContentID, assetID as NSString, "com.apple.metadata.datatype.UTF-8"),
            // present in real captured Live Photos; helps downstream consumers
            item("com.apple.quicktime.live-photo.auto", NSNumber(value: 1), "com.apple.metadata.datatype.int8"),
            item("com.apple.quicktime.live-photo.vitality-score", NSNumber(value: Float(1.0)), "com.apple.metadata.datatype.float32"),
            item("com.apple.quicktime.live-photo.vitality-scoring-version", NSNumber(value: Int64(4)), "com.apple.metadata.datatype.int64"),
        ]
    }

    private static func stillImageTimeFormatDescription() throws -> CMFormatDescription {
        let spec: [CFString: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier: "\(keySpaceMDTA)/\(keyStillImageTime)",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType: "com.apple.metadata.datatype.int8",
        ]
        var desc: CMFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray,
            formatDescriptionOut: &desc
        )
        guard status == noErr, let desc else {
            throw EngineError.cannotWrite("still-image-time format description failed (OSStatus \(status))")
        }
        return desc
    }

    // MARK: keyframe snapping

    /// Passthrough can only start at a sync (key) frame; find the one at/before `time`.
    private static func snapToPreviousSync(track: AVAssetTrack, time: CMTime) -> CMTime {
        guard track.canProvideSampleCursors,
              let cursor = track.makeSampleCursor(presentationTimeStamp: time) else { return time }
        var steps = 0
        while !cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue && steps < 100_000 {
            if cursor.stepInDecodeOrder(byCount: -1) == 0 { break }
            steps += 1
        }
        let snapped = cursor.presentationTimeStamp
        return snapped.isNumeric && snapped <= time ? snapped : time
    }

    // MARK: main entry

    /// Convert `input` into a Live Photo pair inside `outputDir` (created if needed).
    static func convert(
        input: URL,
        outputDir: URL,
        baseName: String,
        settings: ConversionSettings,
        quarterTurns: Int = 0,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> ConversionResult {
        try Task.checkCancellation()
        let asset = try await Rotation.asset(url: input, turns: quarterTurns)
        let duration = try await asset.load(.duration).seconds
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw EngineError.noVideoTrack
        }

        guard duration.isFinite, duration > 0, settings.trimStart.isFinite,
              settings.trimEnd.isFinite, settings.frameTime?.isFinite != false else {
            throw EngineError.cannotRead("视频时间范围无效")
        }
        let trimStart = max(0, settings.trimStart)
        let trimEnd = settings.trimEnd > 0 ? min(settings.trimEnd, duration) : duration
        guard trimStart < trimEnd else { throw EngineError.cannotRead("选区不在视频范围内") }
        let requestedDuration = trimEnd - trimStart
        // The selected range may start between frame boundaries. Subtracting a
        // full frame here can choose the penultimate source frame as the cover.
        let lastFrameOffset = max(0, requestedDuration - 1.0 / 60000)
        let frameRel = min(max(0, settings.frameTime ?? requestedDuration / 2), lastFrameOffset)
        let stillTimeAbs = trimStart + frameRel

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let imageURL = outputDir.appendingPathComponent("\(baseName).\(settings.useHEIC ? "HEIC" : "JPG")")
        let movURL = outputDir.appendingPathComponent("\(baseName).MOV")
        let sourcePath=input.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
        guard ![imageURL,movURL].contains(where: { $0.standardizedFileURL.resolvingSymlinksInPath().path.lowercased() == sourcePath }) else {
            throw EngineError.cannotWrite("输出路径与原视频相同，请选择其他位置。")
        }
        try? FileManager.default.removeItem(at: imageURL)
        try? FileManager.default.removeItem(at: movURL)

        var succeeded = false
        defer {
            if !succeeded {
                try? FileManager.default.removeItem(at: imageURL)
                try? FileManager.default.removeItem(at: movURL)
            }
        }
        let assetID = UUID().uuidString.uppercased()

        // still first (from the source, frame-accurate, full resolution)
        // progress emits string KEYS; the UI localizes them (see Localizer)
        progress?("prog_still")
        try await extractStill(asset: asset, at: stillTimeAbs, to: imageURL,
                               heic: settings.useHEIC, assetID: assetID)

        let videoCompatible = await isVideoPassthroughCompatible(videoTrack)
        let videoWasCopied: Bool
        if settings.exactTrim || !videoCompatible {
            progress?(settings.exactTrim ? "prog_exact" : "prog_reencode")
            let tmp = outputDir.appendingPathComponent(".\(baseName).exact.mov")
            try? FileManager.default.removeItem(at: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            try await exactTrimExport(asset: asset, start: trimStart, end: trimEnd, to: tmp)
            let trimmed = AVURLAsset(url: tmp)
            try await passthroughWrite(asset: trimmed, to: movURL, assetID: assetID,
                                       timeRange: nil, stillTimeAbs: frameRel,
                                       dropAudio: settings.dropAudio)
            videoWasCopied = false
        } else {
            // Only the video track drives keyframe snapping: passthrough can
            // start only at a sync frame, but a re-encoded track cuts precisely.
            progress?("prog_mux")
            var range: CMTimeRange? = nil
            if trimStart > 0.01 || trimEnd < duration - 0.01 {
                let start = videoCompatible
                    ? snapToPreviousSync(track: videoTrack,
                                         time: CMTime(seconds: trimStart, preferredTimescale: 60000))
                    : CMTime(seconds: trimStart, preferredTimescale: 60000)
                let end = CMTime(seconds: trimEnd, preferredTimescale: 60000)
                range = CMTimeRange(start: start, end: end)
            }
            videoWasCopied = try await passthroughWrite(
                asset: asset, to: movURL, assetID: assetID,
                timeRange: range, stillTimeAbs: stillTimeAbs,
                presentationRange: CMTimeRange(start: CMTime(seconds: trimStart, preferredTimescale: 60000), end: CMTime(seconds: trimEnd, preferredTimescale: 60000)),
                dropAudio: settings.dropAudio)
        }

        let outDuration = try await AVURLAsset(url: movURL).load(.duration).seconds
        succeeded = true
        return ConversionResult(
            imageURL: imageURL, movURL: movURL, assetID: assetID, baseName: baseName,
            clipDuration: outDuration, videoWasCopied: videoWasCopied
        )
    }

    // MARK: still extraction

    private static func extractStill(
        asset: AVAsset, at time: Double, to url: URL, heic: Bool, assetID: String
    ) async throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let cmTime = CMTime(seconds: time, preferredTimescale: 60000)
        let cgImage: CGImage
        do {
            (cgImage, _) = try await generator.image(at: cmTime)
        } catch {
            throw EngineError.stillExtractionFailed(error.localizedDescription)
        }

        let type = heic ? UTType.heic : UTType.jpeg
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw EngineError.stillExtractionFailed("Couldn't create \(type.preferredFilenameExtension ?? "") destination")
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: heic ? 0.95 : 0.98,
            kCGImagePropertyMakerAppleDictionary: [makerAppleAssetIDKey: assetID],
        ]
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw EngineError.stillExtractionFailed("image encoding failed")
        }
    }

    // MARK: exact trim (one visually lossless-ish re-encode, frame accurate)

    private static func exactTrimExport(asset: AVAsset, start: Double, end: Double, to url: URL) async throws {
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset = presets.contains(AVAssetExportPresetHEVCHighestQuality)
            ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw EngineError.cannotWrite("couldn't create export session")
        }
        session.outputURL = url
        session.outputFileType = .mov
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 60000),
            end: CMTime(seconds: end, preferredTimescale: 60000)
        )
        await session.export()
        if session.status != .completed {
            throw EngineError.cannotWrite(session.error?.localizedDescription ?? "export failed")
        }
    }

    // MARK: codec compatibility (copy vs. re-encode, decided per track)

    /// Video codecs a QuickTime .mov accepts for stream-copy passthrough.
    private static let passthroughVideoCodecs: Set<FourCharCode> = [
        kCMVideoCodecType_H264,
        kCMVideoCodecType_HEVC,
        kCMVideoCodecType_HEVCWithAlpha,
        kCMVideoCodecType_AppleProRes4444XQ,
        kCMVideoCodecType_AppleProRes4444,
        kCMVideoCodecType_AppleProRes422HQ,
        kCMVideoCodecType_AppleProRes422,
        kCMVideoCodecType_AppleProRes422LT,
        kCMVideoCodecType_AppleProRes422Proxy,
        kCMVideoCodecType_JPEG,
        kCMVideoCodecType_JPEG_OpenDML,
    ]

    /// Audio formats a QuickTime .mov accepts for stream-copy passthrough.
    private static let passthroughAudioFormats: Set<FourCharCode> = [
        kAudioFormatMPEG4AAC,
        kAudioFormatMPEG4AAC_HE,
        kAudioFormatMPEG4AAC_HE_V2,
        kAudioFormatMPEG4AAC_LD,
        kAudioFormatMPEG4AAC_ELD,
        kAudioFormatAppleLossless,
        kAudioFormatLinearPCM,
    ]

    // Debug-only test hook: REVIVE_FORCE_REENCODE=1 forces the video re-encode
    // branch even for a copy-compatible codec, so the transcode path can be
    // exercised on a codec the OS can actually decode (e.g. H.264). Release
    // builds always return false (the whole check is compiled out).
    private static var forceReencodeVideo: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["REVIVE_FORCE_REENCODE"] == "1"
        #else
        return false
        #endif
    }

    private static func isPassthroughCompatible(_ desc: CMFormatDescription, mediaType: AVMediaType) -> Bool {
        let subtype = CMFormatDescriptionGetMediaSubType(desc)
        if mediaType == .video { return !forceReencodeVideo && passthroughVideoCodecs.contains(subtype) }
        if mediaType == .audio { return passthroughAudioFormats.contains(subtype) }
        return false
    }

    static func isVideoPassthroughCompatible(_ track: AVAssetTrack) async -> Bool {
        if forceReencodeVideo { return false }
        guard let desc = try? await track.load(.formatDescriptions).first else { return false }
        return passthroughVideoCodecs.contains(CMFormatDescriptionGetMediaSubType(desc))
    }

    /// Near visually-lossless HEVC (VideoToolbox constant-quality). Used only
    /// when the source video codec cannot be stream-copied into a .mov.
    private static func reencodeVideoSettings(width: Int, height: Int) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: 0.9,
            ],
        ]
    }

    static func reencodeAudioSettings(formatDescription: CMFormatDescription) throws -> [String: Any] {
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee,
              asbd.mSampleRate.isFinite, asbd.mSampleRate > 0,
              asbd.mChannelsPerFrame > 0, asbd.mChannelsPerFrame <= 64 else {
            throw EngineError.cannotRead("音轨的采样率或声道信息无效。可以开启静音后重试。")
        }
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: asbd.mSampleRate,
            AVNumberOfChannelsKey: Int(asbd.mChannelsPerFrame),
            AVEncoderBitRateKey: 256_000,
        ]
        // canApply may return true without this required key; constructing a
        // >2-channel AAC input would then raise an uncaught Objective-C exception.
        if asbd.mChannelsPerFrame > 2 {
            var layoutSize = 0
            guard let layout = CMAudioFormatDescriptionGetChannelLayout(formatDescription, sizeOut: &layoutSize),
                  layoutSize >= 3 * MemoryLayout<UInt32>.size else {
                throw EngineError.cannotWrite("这段多声道音频缺少声道布局，无法导出。可以开启静音后重试。")
            }
            settings[AVChannelLayoutKey] = Data(bytes: layout, count: layoutSize)
        }
        return settings
    }

    private static let videoDecodeSettings: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ]
    private static let audioDecodeSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    // MARK: writer (lossless passthrough per track; re-encode only when forced)
    //
    // Returns true iff the video track was stream-copied (bit-for-bit).

    @discardableResult
    private static func passthroughWrite(
        asset: AVAsset, to url: URL, assetID: String,
        timeRange: CMTimeRange?, stillTimeAbs: Double, presentationRange: CMTimeRange? = nil, dropAudio: Bool = false
    ) async throws -> Bool {
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) }
        catch { throw EngineError.cannotRead(error.localizedDescription) }
        if let timeRange { reader.timeRange = timeRange }

        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: url, fileType: .mov) }
        catch { throw EngineError.cannotWrite(error.localizedDescription) }
        writer.metadata = topLevelMetadata(assetID: assetID)
        writer.movieTimeScale = 60000

        var videoCopied = true
        var pairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        let tracks = try await asset.load(.tracks)
        for track in tracks where track.mediaType == .video || (track.mediaType == .audio && !dropAudio) {
            // iPhone spatial recordings contain enabled stereo AAC plus a disabled
            // APAC alternative. Follow the movie's default selection (Apple TN3177).
            if track.mediaType == .audio, try await !track.load(.isEnabled) { continue }
            guard let formatDesc = try await track.load(.formatDescriptions).first else { continue }
            let compatible = isPassthroughCompatible(formatDesc, mediaType: track.mediaType)

            // reader: nil = deliver compressed samples (copy); settings = decode
            let readerSettings: [String: Any]?
            let writerSettings: [String: Any]?
            if compatible {
                readerSettings = nil
                writerSettings = nil
            } else if track.mediaType == .video {
                let size = try await track.load(.naturalSize)
                readerSettings = videoDecodeSettings
                writerSettings = reencodeVideoSettings(
                    width: Int(abs(size.width)), height: Int(abs(size.height)))
                videoCopied = false
            } else {
                readerSettings = audioDecodeSettings
                writerSettings = try reencodeAudioSettings(formatDescription: formatDesc)
            }

            let output = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
            guard reader.canAdd(output) else { throw EngineError.cannotRead("can't read \(track.mediaType.rawValue) track") }
            reader.add(output)

            let input: AVAssetWriterInput
            if writerSettings == nil {  // passthrough
                input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil,
                                           sourceFormatHint: formatDesc)
            } else {                    // re-encode
                guard writer.canApply(outputSettings: writerSettings, forMediaType: track.mediaType) else {
                    throw EngineError.cannotWrite(track.mediaType == .audio
                        ? "这段音频的声道布局或编码暂不支持导出。可以开启静音后重试。"
                        : "系统编码器不支持这段视频的输出参数。")
                }
                input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: writerSettings)
            }
            input.expectsMediaDataInRealTime = false
            if track.mediaType == .video {
                input.mediaTimeScale = 60000
                input.transform = try await track.load(.preferredTransform)
            }
            guard writer.canAdd(input) else { throw EngineError.cannotWrite("can't write \(track.mediaType.rawValue) track") }
            writer.add(input)
            pairs.append((output, input))
        }
        guard !pairs.isEmpty else { throw EngineError.noVideoTrack }

        let metaInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil,
                                           sourceFormatHint: try stillImageTimeFormatDescription())
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metaInput)
        guard writer.canAdd(metaInput) else { throw EngineError.cannotWrite("can't add still-image-time metadata track") }
        writer.add(metaInput)

        guard reader.startReading() else {
            throw EngineError.cannotRead(reader.error?.localizedDescription ?? "startReading failed")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw EngineError.cannotWrite(writer.error?.localizedDescription ?? "startWriting failed")
        }
        // Keep the decoder's keyframe preroll, but hide it from presentation.
        // QuickTime edit lists allow exact trim without re-encoding the video.
        let sessionStart = presentationRange?.start ?? timeRange?.start ?? .zero
        writer.startSession(atSourceTime: sessionStart)

        let stillGroup = AVTimedMetadataGroup(
            items: [item(keyStillImageTime, NSNumber(value: 0), "com.apple.metadata.datatype.int8")],
            timeRange: CMTimeRange(
                start: CMTime(seconds: stillTimeAbs, preferredTimescale: 60000),
                duration: CMTime(value: 200, timescale: 3000)
            )
        )

        let cancellation = ExportCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                // All completion state belongs to this queue. A failed writer may stop
                // invoking readiness callbacks, so the timer also observes terminal states.
                let queue = DispatchQueue(label: "livephoto.writer")
                let watchdog = DispatchSource.makeTimerSource(queue: queue)
                var completed = false
                var finishing = false
                var metadataDone = false
                var trackDone = Array(repeating: false, count: pairs.count)
                func stop(_ error: Error?) {
                    guard !completed else { return }
                    completed = true
                    watchdog.setEventHandler {}; watchdog.cancel()
                    if let error {
                        reader.cancelReading()
                        if writer.status == .writing { writer.cancelWriting() }
                        cont.resume(throwing: error)
                    } else { cont.resume() }
                }
                func checkFailure() -> Bool {
                    guard !completed else { return true }
                    if cancellation.isCancelled { stop(EngineError.cancelled); return true }
                    if reader.status == .failed || reader.status == .cancelled {
                        stop(EngineError.cannotRead(reader.error?.localizedDescription ?? "读取已中止")); return true
                    }
                    if writer.status == .failed || writer.status == .cancelled {
                        stop(EngineError.cannotWrite(writer.error?.localizedDescription ?? "写入已中止")); return true
                    }
                    return false
                }
                func finishIfReady() {
                    guard !checkFailure(), !finishing, metadataDone, trackDone.allSatisfy({ $0 }) else { return }
                    finishing = true
                    if let presentationRange { writer.endSession(atSourceTime: presentationRange.end) }
                    writer.finishWriting {
                        queue.async {
                            guard !checkFailure() else { return }
                            if writer.status == .completed { stop(nil) }
                            else { stop(EngineError.cannotWrite(writer.error?.localizedDescription ?? "写入未完成")) }
                        }
                    }
                }
                watchdog.schedule(deadline: .now(), repeating: .milliseconds(100))
                watchdog.setEventHandler { _ = checkFailure() }
                watchdog.resume()
                metaInput.requestMediaDataWhenReady(on: queue) {
                    guard !checkFailure(), !metadataDone, metaInput.isReadyForMoreMediaData else { return }
                    guard adaptor.append(stillGroup) else {
                        stop(EngineError.cannotWrite(writer.error?.localizedDescription ?? "实况时间信息写入失败")); return
                    }
                    metadataDone = true; metaInput.markAsFinished(); finishIfReady()
                }
                for (index, (output, input)) in pairs.enumerated() {
                    input.requestMediaDataWhenReady(on: queue) {
                        guard !checkFailure(), !trackDone[index] else { return }
                        while input.isReadyForMoreMediaData && !completed {
                            let hasSample: Bool = autoreleasepool {
                                guard let sample = output.copyNextSampleBuffer() else { return false }
                                if !input.append(sample) {
                                    stop(EngineError.cannotWrite(writer.error?.localizedDescription ?? "媒体样本写入失败"))
                                }
                                return true
                            }
                            guard !checkFailure() else { return }
                            if !hasSample {
                                trackDone[index] = true; input.markAsFinished(); finishIfReady(); return
                            }
                        }
                    }
                }
            }
        } onCancel: { cancellation.cancel() }
        return videoCopied
    }
}

/// Cancellation can arrive on any executor; writer state stays on its serial queue.
private final class ExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
