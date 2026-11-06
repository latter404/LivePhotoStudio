import AVFoundation

/// Selection coordinates always refer to the source. Only output time is scaled.
enum MediaTiming {
    static let speeds: [Double] = [0.25, 0.5, 1, 1.5, 2, 4]

    static func validate(speed: Double) throws {
        guard speed.isFinite, (0.25...4).contains(speed) else {
            throw EngineError.cannotWrite("播放速度必须在 0.25× 至 4× 之间。")
        }
    }

    static func retimed(_ source: AVAsset, start: Double, end: Double, speed: Double) async throws -> AVAsset {
        try validate(speed: speed)
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 60000),
                                end: CMTime(seconds: end, preferredTimescale: 60000))
        let composition = AVMutableComposition()
        for track in try await source.load(.tracks) where track.mediaType == .video || track.mediaType == .audio {
            if track.mediaType == .audio, try await !track.load(.isEnabled) { continue }
            let available = CMTimeRangeGetIntersection(range, otherRange: try await track.load(.timeRange))
            guard available.duration > .zero else { continue }
            guard let target = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw EngineError.cannotRead("无法创建变速轨道")
            }
            try target.insertTimeRange(available, of: track, at: available.start - range.start)
            if track.mediaType == .video { target.preferredTransform = try await track.load(.preferredTransform) }
        }
        composition.scaleTimeRange(CMTimeRange(start: .zero, duration: range.duration),
                                   toDuration: CMTime(seconds: (end - start) / speed, preferredTimescale: 60000))
        return composition
    }
}
