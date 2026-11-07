import XCTest
import AVFoundation
import AudioToolbox
@testable import LivePhotoStudio

/// Synthetic MOV fixtures: no personal iPhone media is embedded in the test suite.
final class AudioRegressionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LivePhotoAudioTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testEnabledAACPreservedAndDisabledAlternateOmitted() async throws {
        try await verifyAlternateAudio(turns: 0)
    }

    func testRotationDoesNotEnableDisabledAlternateAudio() async throws {
        try await verifyAlternateAudio(turns: 1)
    }

    private func verifyAlternateAudio(turns: Int) async throws {
        let source = directory.appendingPathComponent("alternates.mov")
        try await makeMovie(at: source, stereoAAC: true, alternateEnabled: false)
        let sourceTracks = try await AVURLAsset(url: source).loadTracks(withMediaType: .audio)
        XCTAssertEqual(sourceTracks.count, 2)
        let enabled = try await sourceTracks[0].load(.isEnabled)
        let alternateEnabled = try await sourceTracks[1].load(.isEnabled)
        XCTAssertTrue(enabled)
        XCTAssertFalse(alternateEnabled, "Fixture must contain a genuinely disabled alternate")

        let result = try await LivePhotoEngine.convert(input: source, outputDir: directory,
            baseName: "converted", settings: ConversionSettings(), quarterTurns: turns)
        let tracks = try await AVURLAsset(url: result.movURL).loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1, "Disabled alternate must not become a second audible track")
        let before = try await audioBytes(url: source, track: sourceTracks[0])
        let after = try await audioBytes(url: result.movURL, track: XCTUnwrap(tracks.first))
        XCTAssertFalse(before.isEmpty)
        XCTAssertEqual(before, after, "The selected AAC track must be copied without audio recompression")
        XCTAssertTrue(result.videoWasCopied)
        let checks = await Verifier.verify(imageURL: result.imageURL, movURL: result.movURL)
        XCTAssertTrue(checks.allSatisfy { $0.status == .pass })
    }

    func testEnabledQuadraphonicULawTranscodesWithoutCrash() async throws {
        let source = directory.appendingPathComponent("quad.mov")
        try await makeMovie(at: source, stereoAAC: false, alternateEnabled: true)
        let result = try await LivePhotoEngine.convert(input: source, outputDir: directory,
            baseName: "quad-converted", settings: ConversionSettings())
        let tracks = try await AVURLAsset(url: result.movURL).loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let descriptions = try await XCTUnwrap(tracks.first).load(.formatDescriptions)
        let format = try XCTUnwrap(descriptions.first)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kAudioFormatMPEG4AAC)
        let asbd = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(format)).pointee
        XCTAssertEqual(asbd.mChannelsPerFrame, 4, "Valid multichannel layout must not be silently downmixed")
        let encodedAudio = try await audioBytes(url: result.movURL, track: tracks[0])
        XCTAssertFalse(encodedAudio.isEmpty)
        XCTAssertTrue(result.videoWasCopied)
    }

    func testMultichannelWithoutLayoutFailsBeforeWriterConstruction() throws {
        let format = try audioDescription(channels: 4, ulaw: true, includeLayout: false)
        XCTAssertThrowsError(try LivePhotoEngine.reencodeAudioSettings(formatDescription: format))
    }

    func testSpeedPreservesEnabledAudioAndMuteStillRemovesIt() async throws {
        let source=directory.appendingPathComponent("speed-audio.mov")
        try await makeMovie(at:source,stereoAAC:true,alternateEnabled:false)
        for (speed,mute) in [(1.0,false),(0.5,false),(2.0,false),(0.5,true)] {
            let recipe=LivePreparation(input:source,start:0.12,length:0.72,cover:0.36,custom:false,edge:0,fps:0,hevc:true,mute:mute,turns:1,watermark:nil,speed:speed)
            let result=try await recipe.generate(in:directory.appendingPathComponent("speed-\(speed)-\(mute)"))
            let asset=AVURLAsset(url:result.movURL)
            let tracks=try await asset.loadTracks(withMediaType:.audio)
            XCTAssertEqual(tracks.count,mute ? 0 : 1,"Disabled spatial alternatives must stay excluded")
            XCTAssertEqual(result.clipDuration,0.72/speed,accuracy:0.04)
            if let audio=tracks.first {
                let descriptions=try await audio.load(.formatDescriptions)
                let format=try XCTUnwrap(descriptions.first)
                let asbd=try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(format)).pointee
                XCTAssertEqual(asbd.mChannelsPerFrame,2)
                let range=try await audio.load(.timeRange)
                XCTAssertEqual(range.start.seconds,0,accuracy:0.03)
                XCTAssertEqual(range.duration.seconds,result.clipDuration,accuracy:0.04)
                let bytes=try await audioBytes(url:result.movURL,track:audio)
                XCTAssertFalse(bytes.isEmpty)
            }
        }
    }

    func testCollageUsesOnlyFirstEnabledAudioWhenRequested() async throws {
        let source=directory.appendingPathComponent("collage-audio.mov")
        try await makeMovie(at:source,stereoAAC:true,alternateEnabled:false)
        for enabled in [false,true] {
            var options=CollageOptions();options.duration=0.8;options.includeFirstAudio=enabled
            let pair=try await LiveCollage.generate(inputs:[source,source],options:options,in:directory.appendingPathComponent("collage-\(enabled)"))
            let tracks=try await AVURLAsset(url:pair.movURL).loadTracks(withMediaType:.audio)
            XCTAssertEqual(tracks.count,enabled ? 1 : 0)
            if let track=tracks.first {
                let bytes=try await audioBytes(url:pair.movURL,track:track)
                XCTAssertFalse(bytes.isEmpty)
                let duration=try await track.load(.timeRange).duration.seconds
                XCTAssertEqual(duration,0.8,accuracy:0.04)
            }
        }
    }

    private func audioBytes(url: URL, track: AVAssetTrack) async throws -> Data {
        let reader = try AVAssetReader(asset: AVURLAsset(url: url))
        // AVAssetReaderTrackOutput requires a track belonging to its exact asset instance.
        let asset = reader.asset
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let matching = try XCTUnwrap(tracks.first { $0.trackID == track.trackID })
        let output = AVAssetReaderTrackOutput(track: matching, outputSettings: nil)
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? failure("read audio") }
        var bytes = Data()
        while let sample = output.copyNextSampleBuffer() {
            if let block = CMSampleBufferGetDataBuffer(sample) {
                var packet = Data(count: CMBlockBufferGetDataLength(block))
                let status = packet.withUnsafeMutableBytes {
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
                }
                guard status == noErr else { throw failure("copy audio packet") }
                bytes.append(packet)
            }
        }
        guard reader.status == .completed else { throw reader.error ?? failure("read incomplete") }
        return bytes
    }

    private func audioDescription(channels: Int, ulaw: Bool, includeLayout: Bool = true) throws -> CMAudioFormatDescription {
        let bytesPerSample = ulaw ? 1 : 2
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000,
            mFormatID: ulaw ? kAudioFormatULaw : kAudioFormatLinearPCM,
            mFormatFlags: ulaw ? 0 : kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * bytesPerSample), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * bytesPerSample), mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: UInt32(bytesPerSample * 8), mReserved: 0)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels == 4 ? kAudioChannelLayoutTag_Quadraphonic : kAudioChannelLayoutTag_Stereo
        var result: CMAudioFormatDescription?
        let status = withUnsafePointer(to: &layout) { layoutPointer in
            CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
                layoutSize: includeLayout ? MemoryLayout<AudioChannelLayout>.size : 0,
                layout: includeLayout ? layoutPointer : nil, magicCookieSize: 0, magicCookie: nil,
                extensions: nil, formatDescriptionOut: &result)
        }
        guard status == noErr, let result else { throw failure("audio format \(status)") }
        return result
    }

    private func audioSample(format: CMAudioFormatDescription, frame: Int, count: Int, ulaw: Bool) throws -> CMSampleBuffer {
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)!.pointee
        let size = Int(asbd.mBytesPerFrame) * count
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: size, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: size, flags: 0, blockBufferOut: &block)
        guard status == noErr, let block else { throw failure("audio block") }
        var bytes = [UInt8](repeating: ulaw ? 0xEF : 0x10, count: size)
        status = bytes.withUnsafeMutableBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: size) }
        guard status == noErr else { throw failure("audio fill") }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: 48_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        var sampleSize = Int(asbd.mBytesPerFrame)
        status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
            formatDescription: format, sampleCount: count, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw failure("audio sample \(status)") }
        return sample
    }

    private func makeMovie(at url: URL, stereoAAC: Bool, alternateEnabled: Bool) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 120])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        writer.add(video)
        var audio: [(AVAssetWriterInput, CMAudioFormatDescription, Bool)] = []
        if stereoAAC {
            let format = try audioDescription(channels: 2, ulaw: false)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000], sourceFormatHint: format)
            writer.add(input); audio.append((input, format, false))
        }
        let format = try audioDescription(channels: 4, ulaw: true)
        let alternate = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
        alternate.marksOutputTrackAsEnabled = alternateEnabled
        writer.add(alternate); audio.append((alternate, format, true))
        guard writer.startWriting() else { throw writer.error ?? failure("start fixture") }
        writer.startSession(atSourceTime: .zero)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "audio-regression-fixture")
        var fixtureError: Error?
        var videoIndex = 0
        group.enter()
        video.requestMediaDataWhenReady(on: queue) {
            while video.isReadyForMoreMediaData && videoIndex < 30 {
                var pixel: CVPixelBuffer?
                CVPixelBufferCreate(nil, 160, 120, kCVPixelFormatType_32ARGB, nil, &pixel)
                guard let pixel else { fixtureError = self.failure("fixture pixels"); break }
                CVPixelBufferLockBaseAddress(pixel, [])
                memset(CVPixelBufferGetBaseAddress(pixel), 80 + Int32(videoIndex), CVPixelBufferGetDataSize(pixel))
                CVPixelBufferUnlockBaseAddress(pixel, [])
                guard adaptor.append(pixel, withPresentationTime: CMTime(value: CMTimeValue(videoIndex), timescale: 30)) else {
                    fixtureError = writer.error ?? self.failure("fixture video append"); break
                }
                videoIndex += 1
            }
            if videoIndex == 30 || fixtureError != nil {
                video.markAsFinished(); group.leave()
            }
        }
        for (input, format, ulaw) in audio {
            var frame = 0
            group.enter()
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData && frame < 48_000 {
                    let count = min(1024, 48_000 - frame)
                    do {
                        let sample = try self.audioSample(format: format, frame: frame, count: count, ulaw: ulaw)
                        guard input.append(sample) else { throw writer.error ?? self.failure("fixture audio append") }
                        frame += count
                    } catch { fixtureError = error; break }
                }
                if frame == 48_000 || fixtureError != nil {
                    input.markAsFinished(); group.leave()
                }
            }
        }
        await withCheckedContinuation { continuation in
            group.notify(queue: queue) { writer.finishWriting { continuation.resume() } }
        }
        if let fixtureError { throw fixtureError }
        guard writer.status == .completed else { throw writer.error ?? failure("finish fixture") }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "AudioRegressionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
