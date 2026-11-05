import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import Darwin

/// A finished item owns independent media, so changing or moving the source
/// video never changes a clip already added to the collection.
struct FinishedItem: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case livePhoto, gif }
    let id: UUID
    let title: String
    let kind: Kind
    let createdAt: Date
    let start: Double
    let duration: Double
    let byteCount: Int64
    let assetID: String?
    var videoWasCopied = false
    var mediaChecksums: [String: String] = [:]
    var mediaSizes: [String: Int64] = [:]
    // Recomputed on load. Kept out of metadata so a temporary missing file is
    // never committed as the permanent state of the finished item.
    var isAvailable = true
    private enum CodingKeys: String, CodingKey {
        case id, title, kind, createdAt, start, duration, byteCount, assetID, videoWasCopied, mediaChecksums, mediaSizes
    }

    func directory(in root: URL) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func imageURL(in root: URL) -> URL { directory(in: root).appendingPathComponent("LivePhoto.JPG") }
    func movURL(in root: URL) -> URL { directory(in: root).appendingPathComponent("LivePhoto.MOV") }
    func gifURL(in root: URL) -> URL { directory(in: root).appendingPathComponent("Animation.gif") }
    func thumbnailURL(in root: URL) -> URL { directory(in: root).appendingPathComponent("Thumbnail.jpg") }
    func conversionResult(in root: URL) -> ConversionResult? {
        guard kind == .livePhoto, isAvailable, let assetID else { return nil }
        return ConversionResult(imageURL: imageURL(in: root), movURL: movURL(in: root), assetID: assetID,
                                baseName: "LivePhoto", clipDuration: duration, videoWasCopied: videoWasCopied)
    }
}

/// Files are committed as one directory rename. The app can quit between any
/// copy/write without publishing a half-finished item. Large media stays on disk;
/// collection previews use a separate bounded-resolution thumbnail.
actor FinishedStore {
    nonisolated let root: URL
    private let trash: @Sendable (URL) throws -> Void
    private(set) var loadWarningCount = 0

    nonisolated static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LivePhotoStudio/Finished", isDirectory: true)
    }

    /// URL spelling is not directory identity: symlinks and case-insensitive
    /// volumes can expose the same folder through different paths. Callers must
    /// check this before treating migration as permission to trash the old root.
    nonisolated static func sameDirectory(_ first: URL, _ second: URL) -> Bool {
        guard first.isFileURL, second.isFileURL else { return false }
        let a = first.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        let b = second.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        if a.path == b.path { return true }
        var firstInfo = stat(), secondInfo = stat()
        guard a.path.withCString({ lstat($0, &firstInfo) }) == 0,
              b.path.withCString({ lstat($0, &secondInfo) }) == 0,
              (firstInfo.st_mode & S_IFMT) == S_IFDIR,
              (secondInfo.st_mode & S_IFMT) == S_IFDIR else { return false }
        return firstInfo.st_dev == secondInfo.st_dev && firstInfo.st_ino == secondInfo.st_ino
    }

    /// Walk existing and not-yet-created ancestors instead of comparing path
    /// spelling. Foundation can retain a case alias when the destination has
    /// several missing suffix components, even on a case-insensitive volume.
    nonisolated private static func containsDirectory(_ ancestor: URL, _ descendant: URL) -> Bool {
        guard ancestor.isFileURL, descendant.isFileURL else { return false }
        var candidate = descendant.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        var visited = Set<String>()
        while visited.insert(candidate.path).inserted {
            if sameDirectory(ancestor, candidate) { return true }
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            if parent.path == candidate.path { return false }
            candidate = parent
        }
        return false
    }

    init(root: URL = FinishedStore.defaultRoot,
         trash: @escaping @Sendable (URL) throws -> Void = { url in
             try FileManager.default.trashItem(at: url, resultingItemURL: nil)
         }) {
        self.root = root.standardizedFileURL
        self.trash = trash
    }

    func load() throws -> [FinishedItem] {
        loadWarningCount = 0
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let directories = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        var items = [FinishedItem]()
        for directory in directories {
            var safeDirectoryID: UUID?
            do {
                guard let directoryID = UUID(uuidString: directory.lastPathComponent),
                      directory.lastPathComponent == directoryID.uuidString,
                      try isPlainDirectory(directory) else { throw invalidItem() }
                safeDirectoryID = directoryID
                let metadata = directory.appendingPathComponent("item.json")
                let metadataSize = try regularFileSize(metadata)
                guard metadataSize > 0, metadataSize < 1_048_576 else { throw invalidItem() }
                var item = try JSONDecoder().decode(FinishedItem.self, from: Data(contentsOf: metadata))
                guard item.id == directoryID, valid(item) else { throw invalidItem() }
                let assets = item.kind == .livePhoto ? [item.imageURL(in: root), item.movURL(in: root)] : [item.gifURL(in: root)]
                item.isAvailable = assets.allSatisfy {
                    guard let expected = item.mediaSizes[$0.lastPathComponent], expected > 0 else { return false }
                    return (try? regularFileSize($0)) == expected
                }
                if !item.isAvailable { loadWarningCount += 1 }
                items.append(item)
            } catch {
                // Retain a removable placeholder for an app-owned UUID folder.
                // Never derive a path from corrupt metadata or follow a link.
                if let id = safeDirectoryID {
                    let date = (try? directory.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                    items.append(FinishedItem(id: id, title: id.uuidString, kind: .livePhoto, createdAt: date,
                        start: 0, duration: 0, byteCount: 0, assetID: nil, isAvailable: false))
                }
                // Leave damaged or unfamiliar data in place for recovery.
                loadWarningCount += 1
            }
        }
        return items.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Full integrity checking is reserved for selected output actions. Opening
    /// the collection only performs small metadata and file-size reads.
    func validate(ids: Set<UUID>) throws -> [FinishedItem] {
        guard !ids.isEmpty else { return [] }
        let selected = try load().filter { ids.contains($0.id) }
        guard Set(selected.map(\.id)) == ids else { throw invalidItem() }
        return try selected.map { original in
            var item = original
            guard item.isAvailable else { return item }
            let assets = item.kind == .livePhoto ? [item.imageURL(in: root), item.movURL(in: root)] : [item.gifURL(in: root)]
            for asset in assets {
                try Task.checkCancellation()
                do {
                    guard let expected = item.mediaChecksums[asset.lastPathComponent],
                          try checksum(asset) == expected else { item.isAvailable = false; break }
                } catch is CancellationError { throw CancellationError() }
                catch { item.isAvailable = false; break }
            }
            return item
        }
    }

    /// The caller passes the dedicated finished-items directory, not the user-
    /// selected parent. Switch preferences only after this succeeds. The old
    /// root is deliberately retained until the caller has persisted that switch.
    func migrate(to destination: URL) async throws -> [FinishedItem] {
        let target = destination.standardizedFileURL
        if Self.sameDirectory(root, target) { return try load() }
        guard !Self.containsDirectory(root, target), !Self.containsDirectory(target, root) else {
            throw EngineError.cannotWrite("新保存位置不能位于当前处理结果文件夹内。")
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        guard try isPlainDirectory(target) else { throw invalidItem() }
        let directories: [URL]
        if FileManager.default.fileExists(atPath: root.path) {
            directories = try FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        } else { directories = [] }
        var created = [URL]()
        var staging: URL?
        do {
            for directory in directories {
                try Task.checkCancellation()
                guard let id = UUID(uuidString: directory.lastPathComponent), directory.lastPathComponent == id.uuidString else { continue }
                guard try isPlainDirectory(directory) else { throw invalidItem() }
                let expected = try fingerprints(in: directory)
                let final = target.appendingPathComponent(id.uuidString, isDirectory: true)
                if FileManager.default.fileExists(atPath: final.path) {
                    guard try isPlainDirectory(final), try fingerprints(in: final) == expected else {
                        throw EngineError.cannotWrite("新位置已有不同内容的同名处理结果，未更改保存位置。")
                    }
                    continue
                }
                let pending = target.appendingPathComponent(".migration-" + UUID().uuidString, isDirectory: true)
                staging = pending
                try FileManager.default.copyItem(at: directory, to: pending)
                guard try fingerprints(in: pending) == expected else { throw invalidItem() }
                try FileManager.default.moveItem(at: pending, to: final)
                staging = nil
                created.append(final)
            }
            // Re-read only the small metadata once all copies have been verified.
            return try await FinishedStore(root: target).load()
        } catch {
            if let staging { try? FileManager.default.removeItem(at: staging) }
            for directory in created { try? FileManager.default.removeItem(at: directory) }
            throw error
        }
    }

    func addLive(_ pair: ConversionResult, title: String, start: Double, duration: Double) async throws -> FinishedItem {
        guard validTiming(start: start, duration: duration), !pair.assetID.isEmpty else { throw invalidItem() }
        guard try regularFileSize(pair.imageURL) > 0, try regularFileSize(pair.movURL) > 0 else { throw invalidItem() }
        let id = UUID()
        return try await commit(id: id, title: title, kind: .livePhoto, start: start, duration: duration,
                          assetID: pair.assetID, videoWasCopied: pair.videoWasCopied,
                          sources: [(pair.imageURL, "LivePhoto.JPG"), (pair.movURL, "LivePhoto.MOV")])
    }

    func addGIF(_ file: URL, title: String, start: Double, duration: Double) async throws -> FinishedItem {
        guard validTiming(start: start, duration: duration), try regularFileSize(file) > 0 else { throw invalidItem() }
        return try await commit(id: UUID(), title: title, kind: .gif, start: start, duration: duration,
                          assetID: nil, videoWasCopied: false,
                          sources: [(file, "Animation.gif")])
    }

    /// Remove only requested UUID-owned entries. The default moves them to the
    /// user's Trash, never deletes source videos or silently purges finished work.
    func remove(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
            let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            guard try isPlainDirectory(directory) else { throw invalidItem() }
            try trash(directory)
        }
    }

    private func commit(id: UUID, title: String, kind: FinishedItem.Kind, start: Double, duration: Double,
                        assetID: String?, videoWasCopied: Bool, sources: [(URL, String)]) async throws -> FinishedItem {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent("." + id.uuidString + ".inprogress", isDirectory: true)
        let destination = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: staging) } }
        var byteCount: Int64 = 0
        var checksums: [String: String] = [:]
        var sizes: [String: Int64] = [:]
        for (source, name) in sources {
            _ = try regularFileSize(source)
            let target = staging.appendingPathComponent(name)
            try FileManager.default.copyItem(at: source, to: target)
            let size = try regularFileSize(target)
            byteCount += size
            sizes[name] = size
            checksums[name] = try checksum(target)
        }
        let thumbnailSource: URL
        if kind == .livePhoto {
            thumbnailSource = staging.appendingPathComponent("LivePhoto.JPG")
            let checks = await Verifier.verify(imageURL: thumbnailSource, movURL: staging.appendingPathComponent("LivePhoto.MOV"))
            guard checks.allSatisfy({ $0.status == .pass }), Verifier.imageAssetID(thumbnailSource) == assetID else {
                throw EngineError.cannotWrite("实况文件不完整或配对校验失败，请重新导出。")
            }
        } else {
            thumbnailSource = staging.appendingPathComponent("Animation.gif")
            guard let imageSource = CGImageSourceCreateWithURL(thumbnailSource as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetType(imageSource) as String? == UTType.gif.identifier,
                  CGImageSourceGetCount(imageSource) > 0 else { throw invalidItem() }
        }
        try Task.checkCancellation()
        try makeThumbnail(from: thumbnailSource, to: staging.appendingPathComponent("Thumbnail.jpg"))
        let cleanedTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
        let item = FinishedItem(id: id, title: cleanedTitle, kind: kind, createdAt: Date(), start: start,
                                duration: duration, byteCount: byteCount, assetID: assetID,
                                videoWasCopied: videoWasCopied, mediaChecksums: checksums, mediaSizes: sizes)
        guard valid(item) else { throw invalidItem() }
        try JSONEncoder().encode(item).write(to: staging.appendingPathComponent("item.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: destination)
        committed = true
        return item
    }

    private func makeThumbnail(from source: URL, to destination: URL) throws {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, options),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw EngineError.cannotWrite("无法生成处理结果缩略图。") }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw EngineError.cannotWrite("无法生成处理结果缩略图。") }
    }

    private func validTiming(start: Double, duration: Double) -> Bool {
        start.isFinite && start >= 0 && duration.isFinite && duration > 0 && (start + duration).isFinite
    }
    private func valid(_ item: FinishedItem) -> Bool {
        validTiming(start: item.start, duration: item.duration) && item.byteCount > 0 && item.title.count <= 512 &&
            item.createdAt.timeIntervalSinceReferenceDate.isFinite &&
            (item.kind == .gif || !(item.assetID ?? "").isEmpty)
    }
    private func isPlainDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values.isDirectory == true && values.isSymbolicLink != true
    }
    private func regularFileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else { throw invalidItem() }
        return Int64(size)
    }
    private func checksum(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let block = try file.read(upToCount: 1_048_576), !block.isEmpty {
            try Task.checkCancellation()
            hash.update(data: block)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func fingerprints(in directory: URL) throws -> [String: String] {
        guard try isPlainDirectory(directory) else { throw invalidItem() }
        var result: [String: String] = [:]
        func visit(_ folder: URL, prefix: String) throws {
            let children = try FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
            for child in children {
                let relative = prefix + child.lastPathComponent
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true else { throw invalidItem() }
                if values.isDirectory == true {
                    result[relative + "/"] = "directory"
                    try visit(child, prefix: relative + "/")
                } else {
                    guard values.isRegularFile == true else { throw invalidItem() }
                    result[relative] = try checksum(child)
                }
            }
        }
        try visit(directory, prefix: "")
        return result
    }
    private func invalidItem() -> EngineError { .cannotWrite("处理结果文件不完整或信息无效。") }
}
