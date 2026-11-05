import Foundation

enum ExportFiles {
 /// Publish only our two files. Never remove the user's destination directory.
 static func publish(_ result:ConversionResult, into directory:URL, name:String) throws -> ConversionResult {
 let image=directory.appendingPathComponent(name+"."+result.imageURL.pathExtension)
 let movie=directory.appendingPathComponent(name+"."+result.movURL.pathExtension)
 let fm=FileManager.default
 guard !fm.fileExists(atPath:image.path), !fm.fileExists(atPath:movie.path) else { throw EngineError.cannotWrite("同名文件已存在，请重新导出。") }
 try fm.copyItem(at:result.imageURL,to:image)
 do { try fm.copyItem(at:result.movURL,to:movie) }
 catch { try? fm.removeItem(at:image);throw error }
 return ConversionResult(imageURL:image,movURL:movie,assetID:result.assetID,baseName:name,clipDuration:result.clipDuration,videoWasCopied:result.videoWasCopied)
 }
}
