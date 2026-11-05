import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

/// Publishes complete, independent copies of selected finished items. The
/// collection and existing destination files are never used as staging space.
enum FinishedExport {
    static func publish(_ items: [FinishedItem], from root: URL, to destination: URL) async throws -> [URL] {
        try Task.checkCancellation()
        guard !items.isEmpty, Set(items.map(\.id)).count == items.count,
              items.allSatisfy(\.isAvailable) else {
            throw EngineError.cannotWrite("请选择完整且不重复的处理结果。")
        }
        let root = root.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        // A successful export may trigger removal of the selected finished
        // items. Never publish into the collection, including through an alias,
        // or that cleanup could also remove the newly exported copies.
        var insideCollection = destination.path == root.path || destination.path.hasPrefix(rootPrefix)
        var ancestor = destination
        while !insideCollection {
            try Task.checkCancellation()
            // File identity also covers differently cased paths on a
            // case-insensitive volume, where a text prefix is insufficient.
            if FinishedStore.sameDirectory(ancestor, root) { insideCollection = true; break }
            // A bridged Foundation URL can turn file:/// into file:///../
            // rather than returning the root again. Stop before asking for its
            // parent, and require every other step to shorten the absolute path.
            let path = ancestor.path
            if path == "/" { break }
            guard path.hasPrefix("/"), !path.isEmpty else {
                throw EngineError.cannotWrite("请选择有效的导出文件夹。")
            }
            let parent = ancestor.deletingLastPathComponent().standardizedFileURL
            guard parent.pathComponents.count < ancestor.pathComponents.count else {
                throw EngineError.cannotWrite("请选择有效的导出文件夹。")
            }
            ancestor = parent
        }
        guard !insideCollection else {
            throw EngineError.cannotWrite("导出位置不能在处理结果保存文件夹内，请选择其他文件夹。")
        }
        guard try destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw EngineError.cannotWrite("请选择有效的导出文件夹。")
        }
        let fm = FileManager.default
        let staging = destination.appendingPathComponent(".LivePhotoStudio-Export-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        var reserved = Set<String>()
        var prepared = [(source: URL, destination: URL)]()

        for item in items {
            try Task.checkCancellation()
            let values = try item.directory(in: root).resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw incomplete() }
            let extensions = item.kind == .livePhoto ? ["JPG", "MOV"] : ["gif"]
            let base = safeTitle(item.title, fallback: item.kind == .livePhoto ? "LivePhoto" : "GIF")
                + "-" + String(item.id.uuidString.prefix(8))
            let name = try unusedName(base, extensions: extensions, in: destination, reserved: reserved)
            let sources = item.kind == .livePhoto ? [item.imageURL(in: root), item.movURL(in: root)] : [item.gifURL(in: root)]
            let itemStage = staging.appendingPathComponent(item.id.uuidString, isDirectory: true)
            try fm.createDirectory(at: itemStage, withIntermediateDirectories: false)
            var copies = [URL]()
            for (source, ext) in zip(sources, extensions) {
                try Task.checkCancellation()
                let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? 0) > 0 else { throw incomplete() }
                let fileName = name + "." + ext
                let copy = itemStage.appendingPathComponent(fileName)
                try fm.copyItem(at: source, to: copy)
                try Task.checkCancellation()
                copies.append(copy)
                reserved.insert(fileName.lowercased())
                prepared.append((copy, destination.appendingPathComponent(fileName)))
            }
            if item.kind == .livePhoto {
                let checks = await Verifier.verify(imageURL: copies[0], movURL: copies[1])
                guard checks.allSatisfy({ $0.status == .pass }),
                      Verifier.imageAssetID(copies[0]) == item.assetID else { throw incomplete() }
            } else {
                guard let source = CGImageSourceCreateWithURL(copies[0] as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary),
                      CGImageSourceGetType(source) as String? == UTType.gif.identifier,
                      CGImageSourceGetCount(source) > 0 else { throw incomplete() }
            }
        }
        return try commit(prepared)
    }

    /// RENAME_EXCL is a no-overwrite operation even if another process creates
    /// the same destination after our name check. All sources are on the target
    /// volume, so publication never falls back to copying across volumes.
    static func commit(_ prepared: [(source: URL, destination: URL)]) throws -> [URL] {
        var published = [(url: URL, device: dev_t, inode: ino_t)]()
        do {
            for file in prepared {
                try Task.checkCancellation()
                var identity = stat()
                guard file.source.path.withCString({ lstat($0, &identity) }) == 0 else { throw posixError() }
                let moved = file.source.path.withCString { source in
                    file.destination.path.withCString { destination in renamex_np(source, destination, UInt32(RENAME_EXCL)) }
                }
                guard moved == 0 else { throw posixError() }
                published.append((file.destination, identity.st_dev, identity.st_ino))
            }
            try Task.checkCancellation()
            return published.map(\.url)
        } catch {
            for file in published.reversed() {
                var identity = stat()
                // Do not remove a different file that replaced our output.
                if file.url.path.withCString({ lstat($0, &identity) }) == 0,
                   identity.st_dev == file.device, identity.st_ino == file.inode {
                    try? FileManager.default.removeItem(at: file.url)
                }
            }
            throw error
        }
    }

    private static func safeTitle(_ title: String, fallback: String) -> String {
        var clean = ""
        for scalar in title.unicodeScalars {
            let part = CharacterSet.controlCharacters.contains(scalar) || "/:\\".unicodeScalars.contains(scalar) ? "-" : String(scalar)
            guard clean.utf8.count + part.utf8.count <= 120 else { break }
            clean += part
        }
        clean = clean.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return clean.isEmpty ? fallback : clean
    }

    private static func unusedName(_ base: String, extensions: [String], in directory: URL, reserved: Set<String>) throws -> String {
        for suffix in 0..<10_000 {
            try Task.checkCancellation()
            let name = suffix == 0 ? base : base + "-" + String(suffix + 1)
            let available = extensions.allSatisfy { ext in
                let fileName = name + "." + ext
                // lstat also finds broken symlinks, which must not be replaced.
                var info = stat()
                let absent = directory.appendingPathComponent(fileName).path.withCString { lstat($0, &info) } != 0 && errno == ENOENT
                return !reserved.contains(fileName.lowercased()) && absent
            }
            if available { return name }
        }
        throw EngineError.cannotWrite("无法创建不重名的导出文件，请更换文件夹。")
    }
    private static func incomplete() -> EngineError { .cannotWrite("处理结果文件不完整或信息无效。") }
    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
