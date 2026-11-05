import Foundation

/// Local, bounded phase log. Never records media paths, names, watermark text or content.
enum ExportDiagnostics {
 private static let lock=NSLock()
 static var url:URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/LivePhotoStudio/Export.log") }
 static func record(_ phase:String) {
 lock.lock();defer { lock.unlock() }
 do {
 let file=url
 try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
 if !FileManager.default.fileExists(atPath:file.path) { FileManager.default.createFile(atPath:file.path,contents:nil) }
 let handle=try FileHandle(forWritingTo:file);defer { try? handle.close() }
 if try handle.seekToEnd()>65536 { try handle.truncate(atOffset:0) }
 let line="\(Date().ISO8601Format()) \(phase)\n"
 try handle.write(contentsOf:Data(line.utf8));try handle.synchronize()
 } catch { /* Diagnostics must never prevent normal operation. */ }
 }
 static func install() {
 begin("app")
 #if arch(arm64)
 let arch="arm64"
 #else
 let arch="x86_64"
 #endif
 record("app.environment arch=\(arch) ramGiB=\(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) cores=\(ProcessInfo.processInfo.processorCount)")
 NSSetUncaughtExceptionHandler { exception in
 // No reason string: system errors can include private media paths.
 ExportDiagnostics.record("app.uncaughtException name=\(exception.name.rawValue)")
 }
 }
 static func begin(_ operation:String) {
 record("\(operation).begin version=\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development") os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
 }
}
