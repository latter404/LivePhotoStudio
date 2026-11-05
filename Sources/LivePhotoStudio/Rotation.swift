import AVFoundation

/// Quarter-turns compose with the source orientation; samples are never decoded here.
enum Rotation {
 static func asset(url: URL, turns: Int) async throws -> AVAsset {
 let source = AVURLAsset(url: url)
 let n = (turns % 4 + 4) % 4
 guard n != 0 else { return source }
 let composition = AVMutableComposition()
 let duration = try await source.load(.duration)
 for track in try await source.load(.tracks) where track.mediaType == .video || track.mediaType == .audio {
 // Composition tracks default to enabled. Exclude disabled alternatives before
 // insertion so rotation cannot re-enable iPhone spatial audio (Apple TN3177).
 if track.mediaType == .audio, try await !track.load(.isEnabled) { continue }
 guard let target = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw EngineError.cannotRead("无法创建旋转轨道") }
 try target.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
 if track.mediaType == .video {
 let size = try await track.load(.naturalSize)
 let original = try await track.load(.preferredTransform)
 let rotations = [CGAffineTransform.identity, CGAffineTransform(a:0,b:1,c:-1,d:0,tx:0,ty:0), CGAffineTransform(a:-1,b:0,c:0,d:-1,tx:0,ty:0), CGAffineTransform(a:0,b:-1,c:1,d:0,tx:0,ty:0)]
 let rotated = original.concatenating(rotations[n])
 let bounds = CGRect(origin:.zero,size:size).applying(rotated)
 target.preferredTransform = rotated.concatenating(CGAffineTransform(translationX:-bounds.minX,y:-bounds.minY))
 }
 }
 return composition
 }
}
